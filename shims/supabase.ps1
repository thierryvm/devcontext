#Requires -Version 7
<#
    Production guard for the Supabase CLI.

    WHY THIS EXISTS AS A SHIM AND NOT AS A POWERSHELL FUNCTION

    The module already wraps `supabase`, but only through a PowerShell alias.
    An alias exists solely inside a PowerShell session that imported the
    module -- it covers neither git-bash, nor npm scripts, nor execFileSync
    from Node, nor an AI agent's shell. That is, none of the callers most
    likely to make the mistake. Sitting in the PATH is the only position that
    every caller passes through.

    The module itself already said so, in Sync-CtxSupabaseEnv, on 8 Aug 2026:
    "The PowerShell wrapper cannot intercept anything in that case: it is not
    in the call chain."

    CONTRACT

    Refuses only a case it is certain about. Every other path -- no context,
    no linked project, unknown environment, unreadable index, missing module,
    unexpected error -- delegates to the real CLI unchanged. A guard that
    breaks when it hesitates is a guard that gets uninstalled within the week.

    Exit code is the real CLI's, except on refusal, which exits 1.

    Console messages stay pure ASCII: an em-dash renders as '-' in git-bash and
    worse elsewhere, and a refusal message is the one output that must read
    correctly on a machine we know nothing about.

    No param() block on purpose: [CmdletBinding()] would swallow arguments
    like -debug or -verbose as its own parameters instead of forwarding them.
    $args forwards everything verbatim.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$ShimDir = $PSScriptRoot
$Arguments = @($args)

# GARDE-FOU CONTRE L'AUTO-APPEL, ET POURQUOI IL NE COMPARE PAS DES CHEMINS.
#
# Resolve-RealExe s'ecarte lui-meme en comparant le dossier resolu a
# $PSScriptRoot. Cela suffit tant qu'un seul de nos dossiers figure dans PATH.
# Depuis le 15 aout 2026, PATH designe une JONCTION vers le module : le meme
# dossier porte alors deux noms, et si les deux se retrouvent dans PATH -- une
# migration interrompue, une installation manuelle, un PATH bricole -- chaque
# shim ecarte le sien, trouve l'autre, et l'appelle. Indefiniment.
#
# Un compteur ne ment pas, la ou un chemin ment volontiers : jonctions, casse,
# noms 8.3, lecteurs `subst`, chemins UNC.
#
# IL INTERROMPT LA BOUCLE, IL NE SAUTE JAMAIS LE CONTROLE. Une premiere version
# deleguait au binaire reel des la deuxieme entree -- ce qui donnait un
# contournement complet du garde-fou a qui posait DEVCTX_SHIM_DEPTH=1 avant sa
# commande. Une variable d'environnement qui desarme une protection doit etre
# documentee et volontaire (DEVCTX_ALLOW_PROD), jamais un effet de bord d'un
# mecanisme interne.
#
# Ici le garde-fou s'execute a chaque niveau ; le compteur ne fait qu'echouer
# franchement au lieu de tourner sans fin. Poser la variable a la main ne peut
# donc qu'interrompre plus tot : un refus, jamais un passe-droit.
#
# Message en anglais et code en dur : c'est un diagnostic de defaut
# d'installation, pas une sortie normale, et il doit s'afficher meme si le
# fichier de langue est ce qui manque.
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
    Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path $_.Source -Parent).TrimEnd('\', '/') -ne $here } |
        Select-Object -First 1 -ExpandProperty Source
}

# La langue du shim.
#
# Le shim doit pouvoir REFUSER meme quand le module est absent ou casse -- c'est
# tout son contrat. Il source donc le fichier de langue directement, sans passer
# par le module, et se rabat sur une phrase anglaise codee en dur si meme cela
# echoue. Un refus muet serait pire qu'un refus mal traduit.
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
        Write-Error (Dire 'garde.introuvable' '{0} not found in PATH (outside the shims).' @('supabase'))
        exit 127
    }
    & $exe @Arguments
    exit $LASTEXITCODE
}

# --- gather -----------------------------------------------------------------
#
# LE RASSEMBLEMENT ET LA DECISION VIVENT DANS LE MODULE DEPUIS LE 16 AOUT 2026.
#
# Ils etaient ecrits ici, et nulle part ailleurs. Or dans une session PowerShell
# ayant importe le module -- toutes celles que `work` ouvre -- `supabase` resout
# l'ALIAS du module, qui precede le PATH, et ce fichier n'est jamais atteint.
# Le garde-fou couvrait donc tous les shells SAUF celui de tous les jours.
#
# Ce shim reste indispensable : il est le seul chemin depuis git-bash, un script
# npm, un execFileSync Node ou le shell d'un agent. Mais il ne detient plus la
# regle : il l'applique, comme l'autre appelant.

$module   = $null
$decision = $null

try {
    $module = Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -PassThru -ErrorAction Stop
    $decision = & $module {
        param($a, $p) Resolve-CtxSupabaseVerdict -Arguments $a -Path $p
    } $Arguments $PWD.Path
}
catch {
    Invoke-Real
}

if (-not $decision -or -not $decision.Verdict -or $decision.Verdict.Allowed) { Invoke-Real }

# --- refuse -----------------------------------------------------------------
#
# HORS DU try, deliberement : une levee pendant l'affichage du refus retomberait
# sinon dans `Invoke-Real`, et transformerait un refus en execution.

& $module { param($v, $n) Write-CtxGardeRefus -Verdict $v -Projet $n } $decision.Verdict $decision.Projet

exit 1
