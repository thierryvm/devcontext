#Requires -Version 7
<#
    Identity guard for the GitHub CLI.

    WHY THIS EXISTS

    `gh` reads its account from a configuration directory named by
    GH_CONFIG_DIR. Without that variable it falls back to the machine-wide
    config -- that is, to whichever account was logged in last. `work` sets the
    variable, but `work` is a PowerShell command: from git-bash, an npm script
    or an agent's shell it was never set.

    That is the failure this whole module was built around, and until now it was
    handled by discipline: "never run gh from bash". A rule the tool can enforce
    itself has no business living in somebody's memory.

    CONTRACT -- IT CORRECTS BEFORE IT REFUSES

    The supabase guard can only refuse: nobody can guess which database was
    meant. Here the right answer is known, because the folder gives it. So:

      GH_CONFIG_DIR unset, the context has its config  -> set it, silently
      GH_CONFIG_DIR unset, a `gh auth ...` command     -> set it, and say so
      GH_CONFIG_DIR unset, no config yet, a WRITE      -> refuse, name the fix
      GH_CONFIG_DIR set and matching                   -> nothing to do
      GH_CONFIG_DIR set on ANOTHER context             -> refuse writes

    A read is never refused, only flagged. Refusing reads would cost more than
    it protects, and a blocked user reaches for the raw binary -- with no guard
    at all.

    The variable is set on THIS process, which exists only to launch `gh`. The
    caller's session is never modified.

    Delegates unchanged whenever it is not certain: no context owning the
    folder, a missing or broken module, any unexpected error.

    Exit code is the real CLI's, except on refusal, which exits 1.

    Console messages stay pure ASCII: an em-dash renders as '-' in git-bash and
    worse elsewhere, and a refusal is the one output that must read correctly on
    a machine we know nothing about.

    No param() block on purpose: [CmdletBinding()] would swallow arguments like
    -debug or -verbose as its own parameters instead of forwarding them.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$ShimDir = $PSScriptRoot
$Arguments = @($args)

# Meme garde-fou anti-boucle que shims/supabase.ps1, et meme raison : depuis que
# PATH designe une jonction vers le module, un meme dossier porte deux noms. Si
# les deux se retrouvent dans PATH, chaque shim ecarte le sien, trouve l'autre,
# et l'appelle sans fin. Un compteur ne ment pas, la ou un chemin ment
# volontiers : jonctions, casse, noms 8.3, lecteurs subst, chemins UNC.
#
# Il INTERROMPT la boucle, il ne saute jamais le controle : poser la variable a
# la main ne peut donc qu'echouer plus tot, jamais obtenir un passe-droit.
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
    # Deliberately duplicated from the module rather than imported: this must
    # still work when the module is missing or broken, which is exactly when
    # delegation matters most.
    $here = $ShimDir.TrimEnd('\', '/')
    Get-Command gh -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path $_.Source -Parent).TrimEnd('\', '/') -ne $here } |
        Select-Object -First 1 -ExpandProperty Source
}

# La langue du shim. Il doit pouvoir refuser meme si le module est absent, donc
# il source le fichier de langue directement et se rabat sur une phrase anglaise
# codee en dur si meme cela echoue. Un refus muet serait pire qu'un refus mal
# traduit.
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
    $exe = Resolve-RealExe
    if (-not $exe) {
        Write-Error (Dire 'garde.introuvable' '{0} not found in PATH (outside the shims).' @('gh'))
        exit 127
    }
    & $exe @Arguments
    exit $LASTEXITCODE
}

# --- decide -----------------------------------------------------------------
#
# La regle vit dans le module (src/Gh.ps1), jamais ici. Lecon du 16 aout 2026 :
# une regle ecrite dans un shim n'existe que pour les appelants qui traversent
# ce shim -- voir CHANGELOG 1.3.5.

$module   = $null
$verdict  = $null

try {
    $module  = Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -PassThru -ErrorAction Stop
    $verdict = & $module {
        param($a, $p) Resolve-CtxGhVerdict -Arguments $a -Path $p
    } $Arguments $PWD.Path
}
catch {
    Invoke-Real
}

if (-not $verdict) { Invoke-Real }

# stderr, jamais stdout : `gh api`, `gh pr view --json` et consorts sont lus par
# des scripts, et un mot de plus sur leur sortie casse un jq en aval.
if ($verdict.Avertissement) { [Console]::Error.WriteLine("  $($verdict.Avertissement)") }

if ($verdict.Allowed) {
    # Sur CE processus, qui n'existe que pour lancer gh. L'enfant en herite ;
    # la session de l'appelant n'est pas touchee.
    if ($verdict.Redirection) { $env:GH_CONFIG_DIR = $verdict.Redirection }
    Invoke-Real
}

# --- refuse -----------------------------------------------------------------
#
# Hors du try, deliberement : une levee pendant l'affichage retomberait sinon
# dans Invoke-Real, et transformerait un refus en execution.

& $module { param($v) Write-CtxGhRefus -Verdict $v } $verdict

exit 1
