#Requires -Version 7
<#
    Production guard and session isolation for the Vercel CLI.

    WHY THIS EXISTS AS A SHIM

    The module already wrapped `vercel`, but through a PowerShell alias. An
    alias exists only inside a PowerShell session that imported the module -- it
    covers neither git-bash, nor npm scripts, nor an agent's shell. Sitting in
    PATH is the only position every caller passes through.

    WHAT IS GUARDED, AND WHAT IS NOT

    Two refusals, and they are the ones on the roadmap:

      a `--prod` deployment from a branch that is not the default branch
      `env rm` explicitly targeting the production environment

    Deliberately NOT guarded: `rollback` (a repair gesture -- refusing it always
    lands during an incident), `promote` (promoting an already-built deployment
    from a side branch is a legitimate hotfix), and `rm` (what it deletes is not
    identifiable as production from the command line alone). SECURITY.md carries
    the same list.

    SESSION ISOLATION

    Vercel has no GH_CONFIG_DIR equivalent: its config directory is chosen only
    by `-Q, --global-config DIR`. Isolation therefore has to be written into the
    command line on every call. This shim injects it from the FOLDER -- and
    never when the caller already passed one, because a deliberate choice is not
    ours to overwrite.

    It injects only towards a directory that actually holds a session, or when
    the command is `login`/`logout`/`switch`, whose subject IS that directory.
    Pointing at an empty config would answer "not logged in" where `vercel`
    worked, which is a regression, not a protection.

    Exit code is the real CLI's, except on refusal, which exits 1.

    No param() block on purpose: [CmdletBinding()] would swallow -debug or
    -verbose as its own parameters instead of forwarding them.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$ShimDir = $PSScriptRoot
$Arguments = @($args)

# Meme garde-fou anti-boucle que les autres shims : depuis que PATH designe une
# jonction, un meme dossier porte deux noms, et deux entrees dans PATH feraient
# s'appeler les shims sans fin. Le compteur interrompt, il ne desarme jamais.
$Profondeur = 0
if ($env:DEVCTX_SHIM_DEPTH) { $Profondeur = [int]$env:DEVCTX_SHIM_DEPTH }
if ($Profondeur -ge 3) {
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  DevContext: shim loop detected -- a shim resolved to another shim.')
    [Console]::Error.WriteLine('  Two DevContext shim directories are probably both in PATH.')
    [Console]::Error.WriteLine('  Fix: pwsh -File installer-shims.ps1 -Verifier')
    [Console]::Error.WriteLine('')
    exit 1
}
$env:DEVCTX_SHIM_DEPTH = $Profondeur + 1

# --- delegation -------------------------------------------------------------

function Resolve-RealExe {
    # Duplicated from the module rather than imported: this has to work when the
    # module is missing or broken, which is exactly when delegating matters most.
    #
    # ExternalScript as well as Application: on Windows, npm installs `vercel`
    # as a .ps1 alongside the .cmd, and filtering to Application alone would
    # miss it on a machine where only the .ps1 is reachable.
    $here = $ShimDir.TrimEnd('\', '/')
    Get-Command vercel -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path $_.Source -Parent).TrimEnd('\', '/') -ne $here } |
        Select-Object -First 1 -ExpandProperty Source
}

$Traduit = $false
try {
    . (Join-Path $PSScriptRoot '..' 'src' 'Langue.ps1')
    Set-CtxLangue | Out-Null
    $Traduit = $true
}
catch { $Traduit = $false }

function Dire {
    param([string]$Cle, [string]$Secours, [object[]]$Arguments)
    if (-not $Traduit) {
        if ($Arguments) { return ($Secours -f $Arguments) }
        return $Secours
    }
    if ($Arguments) { return (T $Cle @Arguments) }
    T $Cle
}

function Invoke-Real {
    param([string[]]$Final = $Arguments)
    $exe = Resolve-RealExe
    if (-not $exe) {
        Write-Error (Dire 'garde.introuvable' '{0} not found in PATH (outside the shims).' @('vercel'))
        exit 127
    }
    & $exe @Final
    exit $LASTEXITCODE
}

# --- decide -----------------------------------------------------------------

$module   = $null
$decision = $null

try {
    $module   = Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -PassThru -ErrorAction Stop
    $decision = & $module {
        param($a, $p) Resolve-CtxVercelVerdict -Arguments $a -Path $p
    } $Arguments $PWD.Path
}
catch {
    Invoke-Real
}

if (-not $decision -or -not $decision.Verdict) { Invoke-Real }

# stderr : la sortie de `vercel` est lue par des scripts de deploiement.
if ($decision.Avertissement) { [Console]::Error.WriteLine("  $($decision.Avertissement)") }

if ($decision.Verdict.Allowed) {
    $final = $Arguments
    if ($decision.ConfigDir) { $final = @('--global-config', $decision.ConfigDir) + $Arguments }
    Invoke-Real -Final $final
}

# --- refuse -----------------------------------------------------------------
#
# Hors du try : une levee pendant l'affichage retomberait sinon dans Invoke-Real
# et transformerait un refus en deploiement.

& $module { param($v) Write-CtxVercelRefus -Verdict $v } $decision.Verdict

exit 1
