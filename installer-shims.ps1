#Requires -Version 7
<#
.SYNOPSIS
    Puts the DevContext shim folder at the FRONT of the user PATH.

.DESCRIPTION
    The shims decide from the FOLDER, never from the session. That is what makes
    them work where an alias cannot: git-bash, npm scripts, Node's execFileSync,
    an AI agent's shell. The only handover point common to all of them is PATH.

    User scope only -- no administrator rights, fully reversible.

    Like the module itself, the shims are used from the repository, never copied.
    That makes PATH a fourth external consumer pointing at this folder by
    absolute path. Moving the repository breaks it silently, exactly as it broke
    the shortcuts and the registry key on 13 Aug 2026. See INSTALLATION.md.

.PARAMETER Verifier
    Reports the current state. Touches nothing.

.PARAMETER Restaurer
    Removes the shim folder from the user PATH.

.PARAMETER AsLibrary
    Loads the functions without running anything, so tests can exercise the pure
    PATH logic without installing on the machine running them.

.EXAMPLE
    pwsh -NoProfile -File .\installer-shims.ps1 -Verifier
#>
[CmdletBinding()]
param(
    [switch]$Verifier,
    [switch]$Restaurer,
    [switch]$AsLibrary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ShimDir  = Join-Path $PSScriptRoot 'shims'
$script:ShimFichiers = @('supabase.ps1', 'supabase.cmd', 'supabase', 'editor.ps1')

# Written into every generated entry point, and the ONLY thing that authorises
# deleting one. An installer that removes files by name pattern eventually
# removes a file somebody else put there.
$script:MarqueGeneree = 'GENERE PAR DEVCONTEXT'

# ---------------------------------------------------------------------------
# Pure PATH logic -- no registry, no side effect, therefore testable
# ---------------------------------------------------------------------------

function Compare-CtxPathEntry {
    <#
      Windows resolves PATH without regard to case, and treats a trailing
      backslash as noise. Comparing raw strings would happily install a second
      copy of an entry that is already there.
    #>
    param([string]$A, [string]$B)
    $A.Trim().TrimEnd('\', '/').ToLowerInvariant() -eq $B.Trim().TrimEnd('\', '/').ToLowerInvariant()
}

function Add-CtxPathEntry {
    <#
      Returns the new PATH, or nothing at all when the entry is already there.
      "Nothing" is the signal for "no write needed" -- the caller must not write
      a value it did not get.

      Every other entry is copied through verbatim, empty ones included. An
      empty entry means "the current directory" on Windows, which is a fair
      thing to raise with the user, but not something an installer decides on
      their behalf.
    #>
    param(
        [Parameter(Mandatory)][string]$Entry,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Current
    )
    $entries = $Current -split ';'
    if ($entries | Where-Object { $_ -and (Compare-CtxPathEntry $_ $Entry) }) { return }
    if (-not $Current) { return $Entry }
    (@($Entry) + $entries) -join ';'
}

function Remove-CtxPathEntry {
    <#
      Removes every copy of the entry, and only that entry. Returns nothing when
      there was nothing to remove.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Fonction pure : rend la nouvelle chaine PATH, n ecrit rien. Le registre est ecrit par Set-CtxUserPath.')]
    param(
        [Parameter(Mandatory)][string]$Entry,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Current
    )
    $entries = $Current -split ';'
    $kept = @($entries | Where-Object { -not ($_ -and (Compare-CtxPathEntry $_ $Entry)) })
    if ($kept.Count -eq $entries.Count) { return }
    $kept -join ';'
}

# ---------------------------------------------------------------------------
# Registry access -- raw, and preserving the value kind
# ---------------------------------------------------------------------------

function Get-CtxUserPath {
    <#
      Reads HKCU\Environment\Path WITHOUT expanding variables, and reports the
      registry kind alongside.

      Why not [Environment]::GetEnvironmentVariable('Path','User'): it returns
      the EXPANDED value. Writing that back bakes %USERPROFILE% in as a literal
      path and downgrades REG_EXPAND_SZ to REG_SZ -- permanently, and silently.
      The author's own PATH happens to be REG_SZ with no variables in it, so the
      damage would only have shown up on someone else's machine.

      -Cle exists so the tests can prove that property against a scratch key,
      instead of skipping on any machine whose PATH happens to hold no variable.
    #>
    param([string]$Cle = 'HKCU:\Environment')

    if (-not (Test-Path -LiteralPath $Cle)) {
        return [pscustomobject]@{ Value = ''; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
    }
    $item = Get-Item -LiteralPath $Cle
    if ('Path' -notin $item.GetValueNames()) {
        return [pscustomobject]@{ Value = ''; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString }
    }
    [pscustomobject]@{
        Value = [string]$item.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        Kind  = $item.GetValueKind('Path')
    }
}

function Set-CtxUserPath {
    # Ecriture reelle dans HKCU\Environment. -WhatIf doit pouvoir la retenir.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][Microsoft.Win32.RegistryValueKind]$Kind,
        [string]$Cle = 'HKCU:\Environment'
    )
    if (-not $PSCmdlet.ShouldProcess($Cle, 'reecrire la valeur Path')) { return }
    Set-ItemProperty -LiteralPath $Cle -Name 'Path' -Value $Value -Type $Kind
    if ($Cle -eq 'HKCU:\Environment') { Publish-CtxEnvironmentChange }
}

function Publish-CtxEnvironmentChange {
    <#
      Writing the registry directly does not tell anybody. [Environment]::
      SetEnvironmentVariable broadcasts WM_SETTINGCHANGE for you; since we
      deliberately bypass it to preserve the value kind, we broadcast ourselves.

      Best effort: if the interop type cannot be built, the PATH is still
      correct on disk and a new terminal will pick it up. We say so out loud
      rather than let the user believe something happened that did not.
    #>
    $signature = @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    try {
        if (-not ('DevContext.NativeMethods' -as [type])) {
            Add-Type -Namespace 'DevContext' -Name 'NativeMethods' -MemberDefinition $signature
        }
        $resultat = [UIntPtr]::Zero
        # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 2
        [void][DevContext.NativeMethods]::SendMessageTimeout(
            [IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$resultat)
    }
    catch {
        Write-Warning "Diffusion WM_SETTINGCHANGE impossible : $($_.Exception.Message)"
        Write-Warning "Le PATH est correct dans le registre. Les applications deja lancees ne le verront qu'apres redemarrage."
    }
}

# ---------------------------------------------------------------------------
# Editor entry points -- generated, because the list is per machine
# ---------------------------------------------------------------------------
#
# The supabase guard ships as three committed files: there is exactly one
# supabase. Editors are the opposite. This machine carries VS Code, Cursor,
# Windsurf, Antigravity and Trae; the next one carries Positron and VSCodium and
# a build of Cursor from a path nobody guessed. Committing an entry point for
# every name we can think of would shadow commands that are not installed --
# typing `cursor` on a machine without Cursor would answer with a DevContext
# error instead of "command not found", which is worse than doing nothing.
#
# So: entry points are written for the editors actually FOUND, and removed when
# an editor goes away. shims/.gitignore keeps them out of the repository.

function New-CtxEntryPointContent {
    <#
      PURE. The two entry-point bodies for one editor name.

      The editor's name travels in an environment variable, never as a script
      parameter: the argument stream belongs to the caller and reaches the
      editor untouched. `code --wait COMMIT_EDITMSG` is git's editor.

      `setlocal` matters. Without it, `set DEVCTX_SHIM_EDITOR` leaks into the
      calling cmd.exe session, and the next shim invoked from that session
      would inherit the wrong editor name.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Fonction pure : rend le contenu des points d entree, ne cree aucun fichier.')]
    param([Parameter(Mandatory)][string]$Nom)

    $cmd = @(
        '@echo off'
        "rem $($script:MarqueGeneree) -- ne pas editer, relancer installer-shims.ps1"
        'setlocal'
        "set `"DEVCTX_SHIM_EDITOR=$Nom`""
        'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0editor.ps1" %*'
        'exit /b %ERRORLEVEL%'
    ) -join "`r`n"

    $posix = @(
        '#!/bin/sh'
        "# $($script:MarqueGeneree) -- ne pas editer, relancer installer-shims.ps1"
        'DIR=$(dirname "$0")'
        "DEVCTX_SHIM_EDITOR=$Nom exec pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"`$DIR/editor.ps1`" `"`$@`""
    ) -join "`n"

    [pscustomobject]@{ Cmd = $cmd + "`r`n"; Posix = $posix + "`n" }
}

function Get-CtxEntryPointsExistants {
    <#
      Entry points we generated, and only those. Identified by their marker, not
      by their name: a file we did not write is not ours to delete.
    #>
    param([string]$Dossier = $script:ShimDir)

    Get-ChildItem -LiteralPath $Dossier -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $script:ShimFichiers } |
        Where-Object {
            $tete = Get-Content -LiteralPath $_.FullName -TotalCount 3 -ErrorAction SilentlyContinue
            $tete -and ($tete -join "`n").Contains($script:MarqueGeneree)
        }
}

function Sync-CtxEditorEntryPoints {
    <#
      Brings the entry points in line with the editors present on this machine.

      Reports what it did rather than printing: the caller decides how to show
      it, and a test can assert on the result instead of scraping the console.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # AllowEmptyCollection, et ce n'est pas une commodite : `-Restaurer`
        # appelle avec @() pour tout retirer. Sans cela, la desinstallation
        # levait sur la liaison de parametre et laissait les points d entree
        # derriere elle, tout en retirant le PATH.
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Noms,
        [string]$Dossier = $script:ShimDir
    )

    $ecrits = @()
    $retires = @()

    foreach ($nom in $Noms) {
        $contenu = New-CtxEntryPointContent -Nom $nom
        $paires = @(
            @{ Chemin = (Join-Path $Dossier "$nom.cmd"); Valeur = $contenu.Cmd }
            @{ Chemin = (Join-Path $Dossier $nom);       Valeur = $contenu.Posix }
        )
        foreach ($p in $paires) {
            if ($PSCmdlet.ShouldProcess($p.Chemin, 'ecrire le point d entree')) {
                # -NoNewline : les fins de ligne sont dans le contenu, et elles
                # sont porteuses. Un `#!/bin/sh` termine en CRLF echoue sur
                # « bad interpreter: /bin/sh^M », une erreur qui nomme
                # l'interpreteur plutot que la cause.
                Set-Content -LiteralPath $p.Chemin -Value $p.Valeur -Encoding ASCII -NoNewline
                $ecrits += $p.Chemin
            }
        }
    }

    $attendus = @($Noms | ForEach-Object { $_; "$_.cmd" })
    foreach ($f in Get-CtxEntryPointsExistants -Dossier $Dossier) {
        if ($f.Name -in $attendus) { continue }
        if ($PSCmdlet.ShouldProcess($f.FullName, 'retirer un point d entree devenu inutile')) {
            Remove-Item -LiteralPath $f.FullName -Force
            $retires += $f.FullName
        }
    }

    [pscustomobject]@{ Ecrits = $ecrits; Retires = $retires }
}

function Test-CtxShimComplet {
    <#
      Three entry points, three callers. Installing a partial set would put a
      hole in the guard exactly where the missing shell is.
    #>
    $manquants = @($script:ShimFichiers | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:ShimDir $_)) })
    if ($manquants.Count) {
        throw "Fichiers de shim manquants : $($manquants -join ', '). Depot incomplet, installation interrompue."
    }
}

function Get-CtxEditeursEnrobables {
    <#
      The editors worth generating an entry point for.

      Two conditions, both necessary. A command-line entry point, or the shim
      resolves to nothing and answers 127 where the bare name used to work --
      Antigravity is installed on this machine and has none. And a profile flag
      that was established, or the entry point costs a process launch to add
      nothing.
    #>
    try {
        Import-Module (Join-Path $PSScriptRoot 'DevContext.psd1') -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Module DevContext illisible, points d entree editeurs ignores : $($_.Exception.Message)"
        return @()
    }

    & (Get-Module DevContext) {
        foreach ($e in Get-CtxEditorFacts) {
            if (-not $e.Cli) { continue }
            $c = Get-CtxEditorCapabilitiesCached -Editor $e
            if (-not $c.UserDataDir) { continue }
            [pscustomobject]@{ Nom = $e.Name; Libelle = $e.Label; Methode = $c.Method; Extensions = $c.ExtensionsDir }
        }
    }
}

if ($AsLibrary) { return }

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

$etat  = Get-CtxUserPath
$pose  = -not (Add-CtxPathEntry -Entry $script:ShimDir -Current $etat.Value)

if ($Verifier) {
    Write-Host ''
    if ($pose) { Write-Host '  SHIM ACTIF dans le PATH utilisateur' -ForegroundColor Green }
    else       { Write-Host '  SHIM ABSENT du PATH utilisateur' -ForegroundColor Yellow }
    Write-Host "    dossier : $script:ShimDir"
    Write-Host "    registre: HKCU\Environment\Path ($($etat.Kind))"
    Write-Host ''
    Write-Host '  Fichiers de shim :'
    foreach ($f in $script:ShimFichiers) {
        $p = Join-Path $script:ShimDir $f
        $ok = Test-Path -LiteralPath $p
        Write-Host ('    {0,-14} {1}' -f $f, $(if ($ok) { 'present' } else { 'MANQUANT' })) `
            -ForegroundColor $(if ($ok) { 'DarkGray' } else { 'Red' })
    }
    Write-Host ''
    Write-Host '  Points d entree editeurs generes :'
    $generes = @(Get-CtxEntryPointsExistants)
    if (-not $generes) { Write-Host '    (aucun)' -ForegroundColor DarkGray }
    foreach ($g in $generes) { Write-Host "    $($g.Name)" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '  Resolution de "supabase" dans CE processus :'
    $resolus = @(Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue)
    if (-not $resolus) { Write-Host '    (aucune)' -ForegroundColor Yellow }
    foreach ($r in $resolus) {
        $premier = Compare-CtxPathEntry (Split-Path $r.Source -Parent) $script:ShimDir
        Write-Host ('    {0} {1}' -f $(if ($premier) { '->' } else { '  ' }), $r.Source) `
            -ForegroundColor $(if ($premier) { 'Green' } else { 'DarkGray' })
    }
    Write-Host ''
    if ($pose -and $resolus -and -not (Compare-CtxPathEntry (Split-Path $resolus[0].Source -Parent) $script:ShimDir)) {
        Write-Host '  Pose dans le registre, mais pas encore actif dans ce terminal.' -ForegroundColor Yellow
        Write-Host '  Ouvrir un terminal neuf.' -ForegroundColor Yellow
        Write-Host ''
    }
    return
}

if ($Restaurer) {
    $retrait = Sync-CtxEditorEntryPoints -Noms @()
    foreach ($r in $retrait.Retires) { Write-Host "  retire : $(Split-Path $r -Leaf)" -ForegroundColor DarkGray }

    $nouveau = Remove-CtxPathEntry -Entry $script:ShimDir -Current $etat.Value
    if (-not $nouveau -and $nouveau -ne '') {
        Write-Host '  Deja absent du PATH. Rien a faire.' -ForegroundColor DarkGray
        return
    }
    Set-CtxUserPath -Value $nouveau -Kind $etat.Kind
    Write-Host '  Shim retire du PATH utilisateur.' -ForegroundColor Green
    Write-Host '  Les terminaux deja ouverts gardent l ancien PATH.' -ForegroundColor DarkGray
    return
}

Test-CtxShimComplet

# Les editeurs d'abord : la pose du PATH peut n'avoir rien a faire et sortir
# tot, alors qu'un editeur a pu etre installe ou desinstalle depuis.
$editeurs = @(Get-CtxEditeursEnrobables)
$sync = Sync-CtxEditorEntryPoints -Noms @($editeurs | ForEach-Object Nom)

Write-Host ''
if ($editeurs) {
    Write-Host '  Editeurs enrobes (profil par contexte) :' -ForegroundColor Green
    foreach ($e in $editeurs) {
        $ext = if ($e.Extensions) { 'profil + extensions' } else { 'profil seul' }
        Write-Host ('    {0,-22} {1,-20} ({2})' -f $e.Libelle, $ext, $e.Methode) -ForegroundColor DarkGray
    }
}
else {
    Write-Host '  Aucun editeur enrobable trouve.' -ForegroundColor Yellow
    Write-Host '  `ctx-editors` dit ce qui a ete detecte et pourquoi.' -ForegroundColor DarkGray
}
foreach ($r in $sync.Retires) { Write-Host "    retire : $(Split-Path $r -Leaf)" -ForegroundColor DarkGray }

$nouveau = Add-CtxPathEntry -Entry $script:ShimDir -Current $etat.Value
if (-not $nouveau) {
    Write-Host ''
    Write-Host '  PATH deja pose. Rien a faire de ce cote.' -ForegroundColor DarkGray
    return
}

$sauvegarde = Join-Path $env:LOCALAPPDATA 'DevContext\path-utilisateur-avant-shims.txt'
New-Item -ItemType Directory -Path (Split-Path $sauvegarde) -Force | Out-Null
Set-Content -LiteralPath $sauvegarde -Value $etat.Value -Encoding UTF8 -NoNewline

Set-CtxUserPath -Value $nouveau -Kind $etat.Kind

Write-Host ''
Write-Host '  Shim pose en tete du PATH utilisateur.' -ForegroundColor Green
Write-Host "    $script:ShimDir"
Write-Host "    type registre preserve : $($etat.Kind)"
Write-Host "  PATH d avant sauvegarde : $sauvegarde" -ForegroundColor DarkGray
if ($nouveau.Length -gt 2000) {
    Write-Warning "Le PATH utilisateur fait $($nouveau.Length) caracteres. Certains outils anciens tronquent au-dela de 2047."
}
Write-Host '  Les terminaux deja ouverts gardent l ancien PATH — en ouvrir un neuf.' -ForegroundColor Yellow
Write-Host ''
