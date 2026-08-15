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
$script:ShimFichiers = @('supabase.ps1', 'supabase.cmd', 'supabase')

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
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][Microsoft.Win32.RegistryValueKind]$Kind,
        [string]$Cle = 'HKCU:\Environment'
    )
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

$nouveau = Add-CtxPathEntry -Entry $script:ShimDir -Current $etat.Value
if (-not $nouveau) {
    Write-Host '  Deja pose en tete du PATH. Rien a faire.' -ForegroundColor DarkGray
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
