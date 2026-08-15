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
    # Mesure le 15 aout 2026 : `supabase db reset --linked` sur une base de PRODUCTION est
    # passe depuis git-bash, arrete seulement par un timeout reseau.
    #
    # `work` reste utile (il charge le bon jeton) ; il n'est simplement plus ce
    # qui ARME la protection.
    # --workdir redirige la CLI vers un AUTRE projet. Le garde-fou doit juger la
    # cible reelle, pas le dossier depuis lequel on tape :
    #   supabase --workdir F:\...\projet-de-prod db push
    # partait de n'importe ou et travaillait sur la production.
    $dossier = & $module { param($a) Get-CtxArgumentValeur -Arguments $a -Nom 'workdir' } $Arguments
    if (-not $dossier) { $dossier = $PWD.Path }

    # LE DOSSIER D'ABORD, la session seulement en secours.
    #
    # La version precedente lisait $env:DEVCTX en priorite et ne retombait sur le
    # dossier que si la variable etait vide. Quand session et dossier divergent
    # -- l'etat que `ctx` qualifie precisement de NO-GO -- elle interrogeait donc
    # l'index du MAUVAIS contexte, n'y trouvait pas le projet, et concluait
    # « pas de production ». Le commentaire disait « le dossier decide » ; le
    # code disait l'inverse. Releve par l'audit du 15 aout 2026.
    $contextes = @()
    $manifeste = & $module { param($p) Resolve-DevContextForPath -Path $p } $dossier
    if ($manifeste) { $contextes += & $module { param($m) Get-CtxProp $m 'name' } $manifeste }
    if ($env:DEVCTX -and $env:DEVCTX -notin $contextes) { $contextes += $env:DEVCTX }
    if ($contextes.Count -eq 0) { Invoke-Real }

    $ref = & $module { param($p) Resolve-CtxSupabaseRef -Path $p } $dossier
    if (-not $ref) { Invoke-Real }

    # Le verdict le plus restrictif l'emporte : si l'un des deux index connait ce
    # projet comme une production, c'en est une.
    $environment = $null
    $contexte    = $contextes[0]
    foreach ($c in $contextes) {
        $e = & $module { param($r, $n) Get-CtxSupabaseEnv -Ref $r -ContextName $n } $ref $c
        if ($e -eq 'prod') { $environment = 'prod'; $contexte = $c; break }
        if ($e -and -not $environment) { $environment = $e; $contexte = $c }
    }

    # L'index contient-il une production, quelque part ? Sert au seul cas ou le
    # garde-fou se ferme par defaut : un --db-url dont on ne sait pas lire la cible.
    $indexProd = $false
    foreach ($c in $contextes) {
        $p = & $module { param($n) Get-CtxSupabaseIndexPath $n } $c
        if ($p -and (Test-Path $p)) {
            $brut = Get-Content $p -Raw -ErrorAction SilentlyContinue
            if ($brut -match '"env"\s*:\s*"prod"') { $indexProd = $true; break }
        }
    }

    if ($environment -ne 'prod' -and -not $indexProd) { Invoke-Real }

    # Current branch. Absent outside a git repository, which is a pass.
    $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $currentBranch -eq 'HEAD') { $currentBranch = $null }

    # Default branch: what the remote declares, then the usual names, then
    # nothing -- and nothing means pass. We never block on a guess.
    $defaultBranch = git symbolic-ref --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $defaultBranch) {
        # Retirer le prefixe du remote, et LUI SEUL. Un `-split '/'` suivi de
        # [-1] tronquait une branche hierarchique : avec
        # origin/HEAD -> origin/release/main, la branche par defaut devenait
        # 'main', et un developpeur sur une branche locale nommee 'main' voyait
        # son `db push` vers la production accepte.
        $defaultBranch = $defaultBranch -replace '^origin/', ''
    }
    else {
        $defaultBranch = $null
        foreach ($candidate in 'main', 'master') {
            git show-ref --verify --quiet "refs/heads/$candidate" 2>$null
            if ($LASTEXITCODE -eq 0) { $defaultBranch = $candidate; break }
        }
    }

    $verdict = & $module {
        param($a, $e, $c, $d, $o, $p)
        Test-CtxSupabaseGuard -Arguments $a -Environment $e `
            -CurrentBranch $c -DefaultBranch $d -Override:$o -IndexContientProd:$p
    } $Arguments $environment $currentBranch $defaultBranch ($env:DEVCTX_ALLOW_PROD -eq '1') $indexProd

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

if (-not $projectName) { $projectName = Dire 'garde.nomInconnu' '(name unknown)' }

Write-Host ''
Write-Host "  $(Dire 'garde.refuse' 'REFUSED - DevContext production guard')" -ForegroundColor Red
Write-Host ''
Write-Host "    $(Dire 'garde.base' 'Target database : {0}' @($projectName))" -ForegroundColor Yellow
Write-Host "    $(Dire 'garde.raison' 'Reason          : {0}' @($verdict.Reason))"
Write-Host ''
Write-Host "    $(Dire 'garde.derogation' 'If you really mean this command, for this one only:')" -ForegroundColor DarkGray
Write-Host '      $env:DEVCTX_ALLOW_PROD = 1' -ForegroundColor DarkGray
Write-Host "    $(Dire 'garde.jamaisProfil1' 'Never put that in $PROFILE: it removes the guard while leaving')" -ForegroundColor DarkGray
Write-Host "    $(Dire 'garde.jamaisProfil2' 'the impression of having it.')" -ForegroundColor DarkGray
Write-Host ''

exit 1
