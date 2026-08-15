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

function Invoke-Real {
    $exe = Resolve-RealExe
    if (-not $exe) {
        Write-Error "supabase introuvable dans le PATH (hors shims)."
        exit 127
    }
    & $exe @Arguments
    exit $LASTEXITCODE
}

# --- gather -----------------------------------------------------------------

$verdict = $null
$projectName = $null

try {
    $module = Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -PassThru -ErrorAction Stop

    # LE DOSSIER DECIDE, JAMAIS LA SESSION.
    #
    # Ce shim commencait par `if (-not $env:DEVCTX) { Invoke-Real }`, et
    # s'effacait donc des que la variable de session manquait : git-bash, script
    # npm, execFileSync depuis Node, shell d'un agent. C'est-a-dire partout ou
    # l'alias PowerShell ne va deja pas -- toute la raison d'etre du shim.
    #
    # Mesure le 15 aout 2026 : `supabase db reset --linked` sur demo-app-prod est
    # passe depuis git-bash, arrete seulement par un timeout reseau.
    #
    # `work` reste utile (il charge le bon jeton) ; il n'est simplement plus ce
    # qui ARME la protection.
    $contexte = $env:DEVCTX
    if (-not $contexte) {
        $manifeste = & $module { param($p) Resolve-DevContextForPath -Path $p } $PWD.Path
        if ($manifeste) { $contexte = & $module { param($m) Get-CtxProp $m 'name' } $manifeste }
    }
    if (-not $contexte) { Invoke-Real }

    $ref = & $module { Resolve-CtxSupabaseRef }
    if (-not $ref) { Invoke-Real }

    $environment = & $module { param($r, $c) Get-CtxSupabaseEnv -Ref $r -ContextName $c } $ref $contexte
    if ($environment -ne 'prod') { Invoke-Real }

    # Current branch. Absent outside a git repository, which is a pass.
    $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $currentBranch -eq 'HEAD') { $currentBranch = $null }

    # Default branch: what the remote declares, then the usual names, then
    # nothing -- and nothing means pass. We never block on a guess.
    $defaultBranch = git symbolic-ref --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $defaultBranch) {
        $defaultBranch = ($defaultBranch -split '/')[-1]
    }
    else {
        $defaultBranch = $null
        foreach ($candidate in 'main', 'master') {
            git show-ref --verify --quiet "refs/heads/$candidate" 2>$null
            if ($LASTEXITCODE -eq 0) { $defaultBranch = $candidate; break }
        }
    }

    $verdict = & $module {
        param($a, $e, $c, $d, $o)
        Test-CtxSupabaseGuard -Arguments $a -Environment $e `
            -CurrentBranch $c -DefaultBranch $d -Override:$o
    } $Arguments $environment $currentBranch $defaultBranch ($env:DEVCTX_ALLOW_PROD -eq '1')

    $projectName = & $module { param($r, $c)
        $p = Get-CtxSupabaseIndexPath $c
        if (Test-Path $p) {
            $i = Get-Content $p -Raw | ConvertFrom-Json
            $e = $i.PSObject.Properties | Where-Object { $_.Name -eq $r } | Select-Object -First 1
            if ($e) { Get-CtxProp $e.Value 'name' }
        }
    } $ref $contexte
}
catch {
    Invoke-Real
}

if (-not $verdict -or $verdict.Allowed) { Invoke-Real }

# --- refuse -----------------------------------------------------------------
#
# Nothing here prints an environment variable, a token, or the command's own
# arguments: a refusal message is written to logs and pasted into chats.

if (-not $projectName) { $projectName = '(nom inconnu)' }

Write-Host ''
Write-Host '  REFUSE - garde-fou production DevContext' -ForegroundColor Red
Write-Host ''
Write-Host "    Base visee : $projectName" -ForegroundColor Yellow
Write-Host "    Raison     : $($verdict.Reason)"
Write-Host ''
Write-Host '    Si cette commande est vraiment voulue, pour celle-ci seulement :' -ForegroundColor DarkGray
Write-Host '      $env:DEVCTX_ALLOW_PROD = 1' -ForegroundColor DarkGray
Write-Host '    A ne jamais poser dans $PROFILE : ce serait retirer le garde-fou' -ForegroundColor DarkGray
Write-Host '    en croyant le garder.' -ForegroundColor DarkGray
Write-Host ''

exit 1
