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

# T est INTERNE au module : un script autonome doit sourcer le fichier de langue
# lui-meme. L'oublier n'a pas de symptome visible autre que des messages du type
# « [inst.pose] » -- et c'est exactement pourquoi une cle manquante s'affiche au
# lieu de disparaitre.
. (Join-Path $PSScriptRoot 'src' 'Langue.ps1')
Set-CtxLangue | Out-Null

# Meme fichier que celui charge par le module : les regles de chemin ne doivent
# exister qu'une fois. Deux exemplaires d'une meme regle, c'est l'incident du
# 12 aout 2026 -- une correction appliquee a la copie qui n'etait pas executee.
. (Join-Path $PSScriptRoot 'src' 'Chemins.ps1')

# Le dossier REEL, celui ou vivent et s'ecrivent les fichiers.
$script:ShimDir  = Join-Path $PSScriptRoot 'shims'

# Le chemin pose dans PATH : une jonction, sans numero de version. Voir
# src/Chemins.ps1 pour ce que cette distinction repare.
$script:Jonction     = Get-CtxShimLien
$script:CheminStable = Get-CtxShimStable
$script:ShimFichiers = @(
    'supabase.ps1', 'supabase.cmd', 'supabase'
    'gh.ps1', 'gh.cmd', 'gh'
    'vercel.ps1', 'vercel.cmd', 'vercel'
    'editor.ps1'
)

# Les CLI enrobees par un shim COMMIS -- par opposition aux editeurs, dont les
# points d'entree sont generes d'apres ce qui est installe sur la machine.
# Sert au rapport de `-Verifier` : montrer la resolution reelle de chacune est
# le seul moyen de voir qu'un shim est bien devant le vrai binaire.
$script:ShimOutils = @('supabase', 'gh', 'vercel')

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
        Write-Warning (T 'inst.broadcast' $_.Exception.Message)
        Write-Warning (T 'inst.broadcastSuite')
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
        throw (T 'inst.shimsManquants' ($manquants -join ', '))
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
        Write-Warning (T 'inst.moduleIllisible' $_.Exception.Message)
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
$pose  = -not (Add-CtxPathEntry -Entry $script:CheminStable -Current $etat.Value)

# L'ancienne forme : le dossier du module directement dans PATH. Presente sur
# toute machine installee avant le 15 aout 2026. On la detecte pour la retirer,
# et non pour la tolerer : deux de nos dossiers dans PATH, c'est la boucle que
# les shims interrompent desormais par compteur.
$ancienPose = -not (Add-CtxPathEntry -Entry $script:ShimDir -Current $etat.Value)

if ($Verifier) {
    Write-Host ''
    if ($pose) { Write-Host "  $(T 'inst.actif')" -ForegroundColor Green }
    else       { Write-Host "  $(T 'inst.absent')" -ForegroundColor Yellow }
    Write-Host "    $(T 'inst.dossier' $script:CheminStable)"
    Write-Host "    $(T 'inst.registre' $etat.Kind)"
    Write-Host ''

    $cible = Get-CtxJonctionCible -Chemin $script:Jonction
    Write-Host "  $(T 'inst.jonction')"
    if (-not $cible) {
        Write-Host "    $(T 'inst.jonctionAbsente')" -ForegroundColor Yellow
    }
    elseif (Test-CtxJonctionSaine -Cible $cible -ModuleAttendu $PSScriptRoot) {
        Write-Host "    $cible" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    $cible" -ForegroundColor Yellow
        Write-Host "    $(T 'inst.jonctionAilleurs' $PSScriptRoot)" -ForegroundColor Yellow
    }
    if ($ancienPose) {
        Write-Host ''
        Write-Host "  $(T 'inst.ancienneEntree' $script:ShimDir)" -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host "  $(T 'inst.fichiers')"
    foreach ($f in $script:ShimFichiers) {
        $p = Join-Path $script:ShimDir $f
        $ok = Test-Path -LiteralPath $p
        Write-Host ('    {0,-14} {1}' -f $f, $(if ($ok) { 'present' } else { 'MANQUANT' })) `
            -ForegroundColor $(if ($ok) { 'DarkGray' } else { 'Red' })
    }
    Write-Host ''
    Write-Host "  $(T 'inst.pointsEntree')"
    $generes = @(Get-CtxEntryPointsExistants)
    if (-not $generes) { Write-Host "    $(T 'inst.aucun')" -ForegroundColor DarkGray }
    foreach ($g in $generes) { Write-Host "    $($g.Name)" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host "  $(T 'inst.resolution')"
    $nosDossiers = @($script:CheminStable, $script:ShimDir)
    # Chaque outil separement, et non le seul `supabase` : un shim peut etre
    # devant pour l'un et derriere pour l'autre -- npm reinstalle `vercel` et le
    # place ailleurs dans PATH, par exemple. Un rapport qui n'en montre qu'un
    # laisserait croire que la reponse vaut pour les trois.
    $unDerriere = $false
    foreach ($outil in $script:ShimOutils) {
        Write-Host "    $outil" -ForegroundColor Cyan
        $resolus = @(Get-Command $outil -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue)
        if (-not $resolus) {
            Write-Host "      $(T 'inst.aucune')" -ForegroundColor Yellow
            continue
        }
        foreach ($r in $resolus) {
            $notre = Test-CtxDossierEstShimDevContext -Dossier (Split-Path $r.Source -Parent) -Dossiers $nosDossiers
            $marque = if ($notre) { '->' } else { '  ' }
            $couleur = if ($notre) { 'Green' } else { 'DarkGray' }
            Write-Host ('      {0} {1}' -f $marque, $r.Source) -ForegroundColor $couleur
        }
        if (-not (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $resolus[0].Source -Parent) -Dossiers $nosDossiers)) {
            $unDerriere = $true
        }
    }
    Write-Host ''
    if ($pose -and $unDerriere) {
        Write-Host "  $(T 'inst.poseNonActif')" -ForegroundColor Yellow
        Write-Host "  $(T 'inst.terminalNeuf')" -ForegroundColor Yellow
        Write-Host ''
    }
    return
}

if ($Restaurer) {
    $retrait = Sync-CtxEditorEntryPoints -Noms @()
    foreach ($r in $retrait.Retires) { Write-Host "  $(T 'inst.retire' (Split-Path $r -Leaf))" -ForegroundColor DarkGray }

    # Les DEUX formes, la stable et l'ancienne. Ne retirer que celle qu'on pose
    # aujourd'hui laisserait derriere elle l'entree des installations d'avant le
    # 15 aout 2026 : une desinstallation qui ne desinstalle pas tout.
    $courant = $etat.Value
    foreach ($entree in @($script:CheminStable, $script:ShimDir)) {
        $reduit = Remove-CtxPathEntry -Entry $entree -Current $courant
        if ($null -ne $reduit) { $courant = $reduit }
    }

    $jonctionRetiree = Remove-CtxJonction -Chemin $script:Jonction
    if ($jonctionRetiree) { Write-Host "  $(T 'inst.jonctionRetiree')" -ForegroundColor DarkGray }

    if ($courant -eq $etat.Value) {
        Write-Host "  $(T 'inst.dejaAbsent')" -ForegroundColor DarkGray
        return
    }
    Set-CtxUserPath -Value $courant -Kind $etat.Kind
    Write-Host "  $(T 'inst.retireDuPath')" -ForegroundColor Green
    Write-Host "  $(T 'inst.ancienPath')" -ForegroundColor DarkGray
    return
}

Test-CtxShimComplet

# Les editeurs d'abord : la pose du PATH peut n'avoir rien a faire et sortir
# tot, alors qu'un editeur a pu etre installe ou desinstalle depuis.
$editeurs = @(Get-CtxEditeursEnrobables)
$sync = Sync-CtxEditorEntryPoints -Noms @($editeurs | ForEach-Object Nom)

Write-Host ''
if ($editeurs) {
    Write-Host "  $(T 'inst.editeursEnrobes')" -ForegroundColor Green
    foreach ($e in $editeurs) {
        $ext = if ($e.Extensions) { T 'inst.profilEtExt' } else { T 'inst.profilSeul' }
        Write-Host ('    {0,-22} {1,-20} ({2})' -f $e.Libelle, $ext, $e.Methode) -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  $(T 'inst.aucunEditeur')" -ForegroundColor Yellow
    Write-Host "  $(T 'inst.aucunEditeurFix')" -ForegroundColor DarkGray
}
foreach ($r in $sync.Retires) { Write-Host "    $(T 'inst.retire' (Split-Path $r -Leaf))" -ForegroundColor DarkGray }

# La jonction AVANT le PATH. Poser dans PATH un chemin qui ne mene encore nulle
# part donnerait un `supabase` introuvable jusqu'au prochain terminal -- une
# fenetre pendant laquelle le garde-fou est annonce sans etre la.
Set-CtxJonction -Chemin $script:Jonction -Cible $PSScriptRoot | Out-Null
Write-Host ''
Write-Host "  $(T 'inst.jonctionPosee')" -ForegroundColor Green
Write-Host "    $script:Jonction"
Write-Host "    -> $PSScriptRoot" -ForegroundColor DarkGray

$courant = $etat.Value

# Migration : retirer l'ancienne entree, celle qui portait le dossier du module.
# Sur une installation Gallery elle porte un numero de version et se perime a la
# mise a jour suivante ; sur toute installation elle ferait un second dossier de
# shims dans PATH, donc une boucle potentielle.
$sansAncien = Remove-CtxPathEntry -Entry $script:ShimDir -Current $courant
if ($null -ne $sansAncien) {
    $courant = $sansAncien
    Write-Host "  $(T 'inst.ancienneRetiree' $script:ShimDir)" -ForegroundColor DarkGray
}

$nouveau = Add-CtxPathEntry -Entry $script:CheminStable -Current $courant
if (-not $nouveau) { $nouveau = $courant }
if ($nouveau -eq $etat.Value) {
    Write-Host ''
    Write-Host "  $(T 'inst.pathDejaPose')" -ForegroundColor DarkGray
    return
}

$sauvegarde = Join-Path $env:LOCALAPPDATA 'DevContext\path-utilisateur-avant-shims.txt'
New-Item -ItemType Directory -Path (Split-Path $sauvegarde) -Force | Out-Null
Set-Content -LiteralPath $sauvegarde -Value $etat.Value -Encoding UTF8 -NoNewline

Set-CtxUserPath -Value $nouveau -Kind $etat.Kind

Write-Host ''
Write-Host "  $(T 'inst.pose')" -ForegroundColor Green
Write-Host "    $script:CheminStable"
Write-Host "    $(T 'inst.typePreserve' $etat.Kind)"
Write-Host "  $(T 'inst.sauvegarde' $sauvegarde)" -ForegroundColor DarkGray
if ($nouveau.Length -gt 2000) {
    Write-Warning (T 'inst.pathLong' $nouveau.Length)
}
Write-Host "  $(T 'inst.ancienPathNeuf')" -ForegroundColor Yellow
Write-Host ''
