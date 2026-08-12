# DevContext.psm1 — isolation de contextes de travail (Windows / PowerShell 7+)
#
# Principe : un contexte = un dossier + un jeu de variables d'environnement.
# On ne se deconnecte jamais de rien. Chaque terminal porte une identite.
#
# Le perso est un contexte comme les autres. Il n'existe PAS d'etat neutre :
# un etat neutre, c'est l'identite du dernier qui a parle, et c'est exactement
# ce que ce module existe pour supprimer.
#
# Secrets : jamais sur disque en clair. Stockes dans le coffre SecretManagement
# 'DevContext' sous la cle devctx/<contexte>/<nom>.

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

$script:CtxRoot   = $env:DEVCTX_ROOT ? $env:DEVCTX_ROOT : 'F:\CTX'
$script:VaultName = 'DevContext'
$script:SshConfig = Join-Path $HOME '.ssh\config'
$script:GitConfig = Join-Path $HOME '.gitconfig'

# Cles de secrets gerees par contexte. Ajouter ici pour supporter un nouveau service.
$script:SecretMap = [ordered]@{
    'github-token'   = 'GH_TOKEN'
    'vercel-token'   = 'VERCEL_TOKEN'
    'supabase-token' = 'SUPABASE_ACCESS_TOKEN'
    'supabase-db'    = 'SUPABASE_DB_PASSWORD'
    'sentry-token'   = 'SENTRY_READ_TOKEN'
}

# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

function Get-CtxPath {
    param([Parameter(Mandatory)][string]$Name)
    Join-Path $script:CtxRoot $Name
}

function Read-CtxManifest {
    param([Parameter(Mandatory)][string]$Name)

    $manifest = Join-Path (Get-CtxPath $Name) 'context.json'
    if (-not (Test-Path $manifest)) {
        throw "Contexte '$Name' introuvable ($manifest). 'ctx-list' pour voir les contextes existants."
    }
    Get-Content $manifest -Raw | ConvertFrom-Json
}

function Get-CtxProp {
    # Lecture defensive : les manifestes crees avant l'ajout d'un champ n'ont
    # pas ce champ, et Set-StrictMode transforme un acces absent en exception.
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Path,
        $Default = $null
    )
    $cursor = $Object
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $cursor) { return $Default }
        if (-not $cursor.PSObject.Properties[$part]) { return $Default }
        $cursor = $cursor.$part
    }
    if ($null -eq $cursor -or $cursor -eq '') { return $Default }
    $cursor
}

function Get-NormalizedRoot {
    # Un separateur final non ambigu : sans lui, 'F:\PROJECTS\Apps' matcherait
    # aussi 'F:\PROJECTS\Apps-Autre', et le garde-fou dirait le contraire du vrai.
    param([Parameter(Mandatory)][string]$Path)
    ($Path.TrimEnd('\', '/')) + '\'
}

function Test-CtxVault {
    if (-not (Get-Module -ListAvailable Microsoft.PowerShell.SecretManagement)) {
        throw "Module SecretManagement absent. Installer :`n  Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser"
    }
    if (-not (Get-SecretVault -Name $script:VaultName -ErrorAction SilentlyContinue)) {
        Write-Host "Creation du coffre '$($script:VaultName)'..." -ForegroundColor Yellow
        Register-SecretVault -Name $script:VaultName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault:$false
    }
}

function Get-CtxSecret {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key
    )
    Get-Secret -Vault $script:VaultName -Name "devctx/$Name/$Key" -AsPlainText -ErrorAction SilentlyContinue
}

function Set-CtxSecret {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][securestring]$Value
    )
    Set-Secret -Vault $script:VaultName -Name "devctx/$Name/$Key" -SecureStringSecret $Value
}

function Get-CtxManifests {
    if (-not (Test-Path $script:CtxRoot)) { return @() }
    Get-ChildItem $script:CtxRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'context.json') } |
        ForEach-Object { Get-Content (Join-Path $_.FullName 'context.json') -Raw | ConvertFrom-Json }
}

# ---------------------------------------------------------------------------
# Resolve-DevContextForPath — a QUI appartient ce dossier ?
# ---------------------------------------------------------------------------

function Resolve-DevContextForPath {
    <#
      Le vrai danger n'est pas « la mauvaise identite est active ». C'est
      « une identite est active pendant que je me tiens dans le dossier d'une
      autre ». Cette fonction repond a la seconde question, et c'est elle qui
      arme le garde-fou de `ctx`.

      La racine la plus longue gagne : un contexte imbrique sous un autre est
      resolu vers le plus specifique des deux.
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)

    $full = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }
    $candidate = $null
    $bestLength = -1

    foreach ($m in Get-CtxManifests) {
        $root = Get-CtxProp $m 'root'
        if (-not $root) { continue }
        $normalized = Get-NormalizedRoot $root
        if ((Get-NormalizedRoot $full).StartsWith($normalized, [StringComparison]::OrdinalIgnoreCase)) {
            if ($normalized.Length -gt $bestLength) {
                $bestLength = $normalized.Length
                $candidate = $m
            }
        }
    }
    $candidate
}

# ---------------------------------------------------------------------------
# ctx-list
# ---------------------------------------------------------------------------

function Get-DevContextList {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:CtxRoot)) {
        Write-Host "Aucun contexte. Racine absente : $($script:CtxRoot)" -ForegroundColor DarkGray
        return
    }

    Get-CtxManifests | ForEach-Object {
        [pscustomobject]@{
            Contexte = $_.name
            Label    = Get-CtxProp $_ 'label'
            Email    = Get-CtxProp $_ 'email'
            Racine   = Get-CtxProp $_ 'root'
            Actif    = ($env:DEVCTX -eq $_.name)
        }
    }
}

# ---------------------------------------------------------------------------
# work <contexte>  — activation
# ---------------------------------------------------------------------------

function Use-DevContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [switch]$NoCd
    )

    $m = Read-CtxManifest $Name
    $ctx = Get-CtxPath $Name
    Test-CtxVault

    # --- Identite ---
    $env:DEVCTX       = $m.name
    $env:DEVCTX_LABEL = Get-CtxProp $m 'label' $m.name
    $env:DEVCTX_DIR   = $ctx
    $env:DEVCTX_ROOT_PATH = Get-CtxProp $m 'root'
    $env:DEVCTX_GH_LOGIN  = Get-CtxProp $m 'github.login'

    # --- GitHub CLI : dossier de config dedie, plus jamais de 'gh auth switch' ---
    $env:GH_CONFIG_DIR = Join-Path $ctx 'gh'

    # --- Vercel : dossier de config dedie + scope ---
    # NB : la CLI Vercel ne lit AUCUNE variable d'environnement pour son dossier
    # de config — seulement `-Q, --global-config=DIR`. La variable ci-dessous ne
    # vaut donc que par le wrapper `vercel` defini plus bas, qui l'injecte.
    $env:DEVCTX_VERCEL_CONFIG = Join-Path $ctx 'vercel'
    $orgId = Get-CtxProp $m 'vercel.orgId'
    if ($orgId) { $env:VERCEL_ORG_ID = $orgId } else { Remove-Item Env:VERCEL_ORG_ID -ErrorAction SilentlyContinue }
    $scope = Get-CtxProp $m 'vercel.scope'
    if ($scope) { $env:DEVCTX_VERCEL_SCOPE = $scope } else { Remove-Item Env:DEVCTX_VERCEL_SCOPE -ErrorAction SilentlyContinue }

    # --- Secrets depuis le coffre ---
    $loaded = @()
    foreach ($key in $script:SecretMap.Keys) {
        $envVar = $script:SecretMap[$key]
        $value  = Get-CtxSecret -Name $Name -Key $key
        if ($value) {
            Set-Item -Path "Env:$envVar" -Value $value
            $loaded += $envVar
        }
        else {
            Remove-Item -Path "Env:$envVar" -ErrorAction SilentlyContinue
        }
    }

    # --- Repere visuel : titre de fenetre + variable pour oh-my-posh ---
    $Host.UI.RawUI.WindowTitle = "[$($env:DEVCTX_LABEL)] $(Get-CtxProp $m 'email')"

    $root = Get-CtxProp $m 'root'
    if (-not $NoCd -and $root -and (Test-Path $root)) {
        Set-Location $root
    }

    # APRES le Set-Location : le jeton Supabase depend du dossier ou l'on arrive,
    # pas de celui d'ou l'on vient. Ecrase la valeur posee par la boucle SecretMap.
    Sync-CtxSupabaseEnv

    if ($env:DEVCTX_SUPABASE_KEY -and $env:DEVCTX_SUPABASE_KEY -ne 'supabase-token') {
        $loaded = $loaded | ForEach-Object {
            if ($_ -eq 'SUPABASE_ACCESS_TOKEN') { "SUPABASE_ACCESS_TOKEN($env:DEVCTX_SUPABASE_KEY)" } else { $_ }
        }
    }

    Write-Host ""
    Write-Host "  CONTEXTE : $($env:DEVCTX_LABEL)" -ForegroundColor Cyan
    Write-Host "  Compte   : $(Get-CtxProp $m 'email')"  -ForegroundColor DarkGray
    Write-Host "  Secrets  : $(if ($loaded) { $loaded -join ', ' } else { 'aucun charge' })" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Suivi des changements de dossier
# ---------------------------------------------------------------------------
# Le jeton Supabase depend du projet. Sans ce hook, un `cd demo-app` apres un
# `work perso` laisserait le jeton du dossier precedent — meme faille que celle
# corrigee ci-dessus, simplement declenchee plus tard.
#
# Le handler eventuellement present est CHAINE, jamais ecrase : oh-my-posh et
# d'autres modules utilisent le meme point d'entree. Le marqueur en commentaire
# evite de se chainer a soi-meme lors d'un `Import-Module -Force`.
$script:PreviousLocationChangedAction = $null
$existingHook = $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction
if ($existingHook -and $existingHook.ToString() -notmatch 'DEVCTX_LOCATION_HOOK') {
    $script:PreviousLocationChangedAction = $existingHook
}
$ExecutionContext.SessionState.InvokeCommand.LocationChangedAction = {
    param($EventSender, $EventArgs)
    # DEVCTX_LOCATION_HOOK
    if ($script:PreviousLocationChangedAction) {
        try { & $script:PreviousLocationChangedAction $EventSender $EventArgs } catch { }
    }
    # Jamais bloquant : une exception ici casserait chaque `cd` de la session.
    try { Sync-CtxSupabaseEnv } catch { }
}

# ---------------------------------------------------------------------------
# ctx-off — bascule vers le contexte perso (PAS un etat neutre)
# ---------------------------------------------------------------------------

function Clear-DevContext {
    <#
      Ancienne version : effacait toutes les variables et rendait la main a
      l'etat global de la machine. C'etait le trou du dispositif — sans
      GH_CONFIG_DIR, `gh` retombe sur sa config globale, c'est-a-dire sur le
      dernier compte connecte, quel qu'il soit. Les projets clients etaient
      blindes ; le projet perso ne l'etait pas, et c'est lui qui a failli
      partir sur le mauvais compte.

      Desormais `ctx-off` bascule vers le contexte 'perso'. Le nom est
      surchargeable via $env:DEVCTX_HOME. S'il n'existe pas, on efface quand
      meme — mais on le dit fort, parce que cet etat n'est protege par rien.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $homeCtx = $env:DEVCTX_HOME ? $env:DEVCTX_HOME : 'perso'
    $manifest = Join-Path (Get-CtxPath $homeCtx) 'context.json'

    if ((Test-Path $manifest) -and -not $Force) {
        Use-DevContext $homeCtx
        return
    }

    foreach ($envVar in $script:SecretMap.Values) {
        Remove-Item -Path "Env:$envVar" -ErrorAction SilentlyContinue
    }
    foreach ($v in 'DEVCTX', 'DEVCTX_LABEL', 'DEVCTX_DIR', 'DEVCTX_ROOT_PATH',
                   'DEVCTX_GH_LOGIN', 'GH_CONFIG_DIR', 'DEVCTX_VERCEL_CONFIG',
                   'DEVCTX_VERCEL_SCOPE', 'VERCEL_ORG_ID', 'DEVCTX_SUPABASE_KEY') {
        Remove-Item -Path "Env:$v" -ErrorAction SilentlyContinue
    }

    $Host.UI.RawUI.WindowTitle = 'PowerShell — AUCUN CONTEXTE'
    Write-Host ""
    Write-Host "  Aucun contexte actif." -ForegroundColor Red
    if (-not (Test-Path $manifest)) {
        Write-Host "  Le contexte '$homeCtx' n'existe pas. Tant qu'il manque, l'identite" -ForegroundColor Yellow
        Write-Host "  perso retombe sur la config GLOBALE de la machine — celle du" -ForegroundColor Yellow
        Write-Host "  dernier compte connecte. C'est le seul trou du dispositif." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    ctx-new $homeCtx -Label 'Perso' -Email '<ton-gmail>' \``" -ForegroundColor DarkGray
        Write-Host "      -Root 'F:\PROJECTS\Apps' -GithubLogin '<ton-login>'" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# code-ctx — VS Code isole
# ---------------------------------------------------------------------------

function Open-DevCode {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name = $env:DEVCTX,
        [Parameter(Position = 1)][string]$Path
    )

    if (-not $Name) { throw "Aucun contexte actif. 'work <contexte>' d'abord, ou 'code-ctx <contexte>'." }

    $m   = Read-CtxManifest $Name
    $ctx = Get-CtxPath $Name
    if (-not $Path) { $Path = Get-CtxProp $m 'root' }

    # L'isolation reelle : VS Code chiffre ses sessions d'auth (DPAPI sous Windows)
    # dans le state.vscdb du user-data-dir. Un user-data-dir par contexte =
    # des comptes GitHub/Copilot independants, en simultane.
    $codeArgs = @(
        '--user-data-dir', (Join-Path $ctx 'vscode')
        '--extensions-dir', (Join-Path $ctx 'vscode-ext')
        $Path
    )

    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if (-not $codeCmd) {
        throw "'code' introuvable dans le PATH. Dans VS Code : Ctrl+Shift+P > 'Shell Command: Install code command in PATH'."
    }

    Write-Host "  VS Code [$(Get-CtxProp $m 'label' $Name)] -> $Path" -ForegroundColor Cyan

    # Lancement DETACHE. `code.cmd` execute `Code.exe cli.js` en avant-plan, sans
    # `start` : cmd.exe attend donc la fin du processus, et le terminal appelant
    # reste bloque tant que la fenetre VS Code est ouverte. Genant depuis un
    # terminal, parasite depuis un raccourci — la fenetre PowerShell survit
    # alors a toute la session de travail.
    #
    # `start` de cmd, et NON Start-Process : ce dernier rend bien la main tout de
    # suite, mais rattache le processus lance a la console appelante. VS Code y
    # deverse alors ses journaux (« [main ...] StorageMainService », etc.) et la
    # maintient ouverte jusqu'a sa propre fermeture — y compris apres la fin de
    # PowerShell, verifie le 2026-08-08 : les processus Code.exe etaient
    # orphelins, donc pwsh avait bien termine, et la fenetre survivait quand meme.
    # Seul `start` cree un processus reellement detache de la console.
    #
    # L'environnement du processus courant reste herite le long de la chaine
    # pwsh > cmd > start > Code.exe : c'est lui qui transmet GH_CONFIG_DIR,
    # SUPABASE_ACCESS_TOKEN et la configuration Vercel au terminal integre de
    # VS Code. Sans cet heritage, l'isolation ne vaudrait que pour les extensions.
    $exe = Join-Path (Split-Path (Split-Path $codeCmd.Source -Parent) -Parent) 'Code.exe'
    if (Test-Path -LiteralPath $exe) {
        # Seules les VALEURS sont guillemetees : un chemin peut contenir une
        # espace, un flag jamais — et `"--user-data-dir"` ne serait pas reconnu.
        $quoted = $codeArgs | ForEach-Object { if ($_ -like '--*') { $_ } else { '"{0}"' -f $_ } }
        # Le `""` qui suit `start` est le titre de la fenetre. Sans lui, cmd prend
        # le chemin guillemete de Code.exe pour un titre et n'execute rien.
        $inner = 'start "" "{0}" {1}' -f $exe, ($quoted -join ' ')
        # Start-Process pour APPELER cmd, et non l'operateur `&`. Avec `&`,
        # PowerShell ouvre un pipe pour lire la sortie de cmd ; `start` transmet
        # ce handle a Code.exe, qui le garde ouvert toute sa vie. PowerShell
        # attend alors un EOF qui n'arrive jamais et le raccourci ne se ferme
        # plus. Verifie le 2026-08-08 : pwsh survivait, en attente, parent
        # explorer. Start-Process n'ouvre aucun pipe (UseShellExecute), donc rien
        # a heriter et rien a attendre.
        Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $inner" -WindowStyle Hidden
    }
    else {
        # Chemin non standard (autre distribution, autre OS) : on retombe sur le
        # CLI, quitte a garder le terminal occupe.
        & code @codeArgs
    }
}

# ---------------------------------------------------------------------------
# web-ctx — profil navigateur dedie
# ---------------------------------------------------------------------------

function Open-DevBrowser {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name = $env:DEVCTX)

    if (-not $Name) { throw "Aucun contexte actif." }
    $m = Read-CtxManifest $Name

    $chromeProfile = Get-CtxProp $m 'chromeProfile'
    if (-not $chromeProfile) {
        throw "Pas de 'chromeProfile' dans context.json pour '$Name'. Creer le profil dans Chrome, puis relever son dossier via chrome://version (champ 'Chemin du profil')."
    }

    $chrome = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $chrome) { throw "chrome.exe introuvable." }

    Start-Process $chrome -ArgumentList "--profile-directory=`"$chromeProfile`""
}

# ---------------------------------------------------------------------------
# vercel — wrapper qui injecte le dossier de config du contexte
# ---------------------------------------------------------------------------

function Invoke-DevVercel {
    <#
      La CLI Vercel n'a pas d'equivalent de GH_CONFIG_DIR : son dossier de config
      ne se choisit que par `-Q, --global-config=DIR` (verifie sur `vercel --help`).
      Sans ce wrapper, `$env:DEVCTX_VERCEL_CONFIG` etait pose par `work` et lu par
      PERSONNE : le dossier `F:\CTX\<ctx>\vercel\` etait cree et jamais utilise.
      L'isolation Vercel ne reposait en fait que sur VERCEL_TOKEN — ce qui suffit,
      mais ce n'est pas ce que l'arborescence laissait croire.
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)

    $exe = Get-Command vercel -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) { throw "vercel introuvable dans le PATH." }

    if ($env:DEVCTX_VERCEL_CONFIG) {
        if (-not (Test-Path $env:DEVCTX_VERCEL_CONFIG)) {
            New-Item -ItemType Directory -Force -Path $env:DEVCTX_VERCEL_CONFIG | Out-Null
        }
        & $exe.Source '--global-config' $env:DEVCTX_VERCEL_CONFIG @Rest
    }
    else {
        & $exe.Source @Rest
    }
}

# ---------------------------------------------------------------------------
# supabase — wrapper qui choisit le jeton d'apres le projet
# ---------------------------------------------------------------------------

<#
  La CLI Supabase n'a ni dossier de config isolable (contrairement a `gh`) ni
  option `--global-config` (contrairement a Vercel) : son unique point d'entree
  est SUPABASE_ACCESS_TOKEN, donc UN compte par contexte. Un contexte qui en
  possede plusieurs — cas courant du perso — ne rentre pas dans ce modele.

  Ce wrapper resout le compte par le DOSSIER, comme le `includeIf` de git le
  fait deja pour l'identite de commit. Le `project-ref` que la CLI ecrit
  elle-meme dans supabase/.temp/ designe le projet ; un index ref -> cle de
  secret designe le compte. L'index se reconstruit seul (`sb-index`) en listant
  les projets de chaque jeton : aucune table a tenir a la main.

  Deliberement silencieux quand il ne sait pas : hors contexte ou hors projet
  lie, il ne decide rien et laisse passer ce que `work` a deja pose. Un wrapper
  qui devine est pire que pas de wrapper du tout.
#>

function Get-CtxSupabaseIndexPath {
    param([Parameter(Mandatory)][string]$Name)
    Join-Path (Get-CtxPath $Name) 'supabase-index.json'
}

function Get-CtxSupabaseKeys {
    # Les cles 'supabase-token*' du contexte reellement presentes au coffre.
    param([Parameter(Mandatory)][string]$Name)
    Get-SecretInfo -Vault $script:VaultName -Name "devctx/$Name/supabase-token*" -ErrorAction SilentlyContinue |
        ForEach-Object { ($_.Name -split '/')[-1] } |
        Sort-Object
}

function Resolve-CtxSupabaseRef {
    # Remonte l'arborescence a la recherche du project-ref ecrit par `supabase link`.
    param([string]$Path = (Get-Location).Path)

    $dir = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { return $null }
    while ($dir) {
        $file = Join-Path $dir 'supabase\.temp\project-ref'
        if (Test-Path $file) {
            $ref = Get-Content $file -Raw -ErrorAction SilentlyContinue
            if ($ref) { return $ref.Trim() }
        }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Set-CtxSupabaseToken {
    # $null EFFACE la variable au lieu d'y mettre une chaine vide : une chaine
    # vide serait lue par la CLI comme « jeton fourni mais invalide ».
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) {
        Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
    }
    else { $env:SUPABASE_ACCESS_TOKEN = $Value }
}

function Update-DevSupabaseIndex {
    [CmdletBinding()]
    param([string]$Name = $env:DEVCTX)

    if (-not $Name) { throw "Aucun contexte actif. 'work <contexte>' d'abord, ou 'sb-index <contexte>'." }
    $exe = Get-Command supabase -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "supabase introuvable dans le PATH." }

    $keys = @(Get-CtxSupabaseKeys $Name)
    if (-not $keys) { throw "Aucun secret 'supabase-token*' au coffre pour le contexte '$Name'." }

    $index    = [ordered]@{}
    $previous = $env:SUPABASE_ACCESS_TOKEN

    try {
        foreach ($key in $keys) {
            $token = Get-CtxSecret -Name $Name -Key $key
            if (-not $token) { continue }

            Set-CtxSupabaseToken $token
            # stderr ecarte : la CLI y ecrit « Cannot find project ref » des qu'on
            # n'est pas dans un projet lie, ce qui casserait le parsing JSON.
            $raw = (& $exe.Source projects list -o json 2>$null) -join "`n"

            $start = $raw.IndexOf('[')
            if ($start -lt 0) {
                Write-Warning "$key : reponse illisible (jeton revoque ou expire ?). Ignore."
                continue
            }

            $count = 0
            foreach ($p in ($raw.Substring($start) | ConvertFrom-Json)) {
                $index[$p.id] = [ordered]@{ key = $key; name = $p.name }
                $count++
            }
            Write-Host ("  {0,-22} {1} projet(s)" -f $key, $count) -ForegroundColor DarkGray
        }
    }
    finally { Set-CtxSupabaseToken $previous }

    $path = Get-CtxSupabaseIndexPath $Name
    $index | ConvertTo-Json -Depth 4 | Set-Content $path -Encoding UTF8
    Write-Host "  index ecrit : $path" -ForegroundColor Green
}

function Resolve-CtxSupabaseKey {
    # Quelle cle de secret ce dossier attend-il ? Renvoie $null si le projet est
    # lie mais absent de l'index (l'appelant doit alors alerter, pas deviner).
    param([string]$Path = (Get-Location).Path)

    $ref = Resolve-CtxSupabaseRef -Path $Path
    if (-not $ref) { return 'supabase-token' }
    if (-not $env:DEVCTX) { return 'supabase-token' }

    $indexPath = Get-CtxSupabaseIndexPath $env:DEVCTX
    if (-not (Test-Path $indexPath)) { return $null }

    try {
        $index = Get-Content $indexPath -Raw | ConvertFrom-Json
        $entry = $index.PSObject.Properties | Where-Object { $_.Name -eq $ref } | Select-Object -First 1
        if ($entry) { return $entry.Value.key }
    }
    catch { return $null }
    return $null
}

function Sync-CtxSupabaseEnv {
    <#
      Pose SUPABASE_ACCESS_TOKEN d'apres le DOSSIER COURANT, pas d'apres une cle
      fixe.

      Sans ca, `work` exportait toujours le compte par defaut, et tout processus
      enfant appelant le binaire brut — `execFileSync` depuis Node, un script
      bash, un agent IA — heritait de ce jeton. Le wrapper PowerShell ne peut
      rien intercepter dans ce cas : il n'est pas dans la chaine d'appel.

      Le defaut etait invisible, ce qui le rendait pire qu'une panne : la
      commande reussissait, sur le mauvais projet. Constate le 8 aout 2026 par
      le preflight d'demo-app, qui voyait 3 projets sans jamais voir demo-app-prod.
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)

    if (-not $env:DEVCTX) { return }

    $key = Resolve-CtxSupabaseKey -Path $Path
    if (-not $key) { return }   # index absent ou projet inconnu : on ne devine pas

    $token = Get-CtxSecret -Name $env:DEVCTX -Key $key
    if ($token) {
        $env:SUPABASE_ACCESS_TOKEN = $token
        $env:DEVCTX_SUPABASE_KEY   = $key
    }
    else {
        Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:DEVCTX_SUPABASE_KEY   -ErrorAction SilentlyContinue
    }
}

function Invoke-DevSupabase {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)]$Rest)

    $exe = Get-Command supabase -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { throw "supabase introuvable dans le PATH." }

    $token = $null
    if ($env:DEVCTX) {
        $ref = Resolve-CtxSupabaseRef
        if ($ref) {
            $path = Get-CtxSupabaseIndexPath $env:DEVCTX
            if (Test-Path $path) {
                $index = Get-Content $path -Raw | ConvertFrom-Json
                $entry = $index.PSObject.Properties | Where-Object { $_.Name -eq $ref } | Select-Object -First 1
                if ($entry) {
                    $token = Get-CtxSecret -Name $env:DEVCTX -Key $entry.Value.key
                    # Annonce uniquement quand le compte n'est PAS celui que `work`
                    # a charge : signaler l'exception, pas la normale.
                    if ($token -and $entry.Value.key -ne 'supabase-token') {
                        Write-Host "  [$($entry.Value.name) -> $($entry.Value.key)]" -ForegroundColor DarkGray
                    }
                }
                else {
                    Write-Warning "Projet '$ref' absent de l'index Supabase. Lance 'sb-index'."
                }
            }
            else {
                Write-Warning "Aucun index Supabase pour '$env:DEVCTX'. Lance 'sb-index'."
            }
        }
    }

    if ($token) {
        $previous = $env:SUPABASE_ACCESS_TOKEN
        try {
            Set-CtxSupabaseToken $token
            & $exe.Source @Rest
        }
        finally { Set-CtxSupabaseToken $previous }
    }
    else {
        & $exe.Source @Rest
    }
}

# ---------------------------------------------------------------------------
# ctx-new — creation d'un contexte
# ---------------------------------------------------------------------------

function New-DevContext {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Email,
        [string]$Root,
        [string]$GitUserName = 'Thierry V.',
        [string]$GithubOrg,
        # Login GitHub attendu pour ce contexte. C'est lui que `ctx` compare au
        # compte reellement actif : sans valeur attendue, aucune verification
        # n'est possible, seulement un affichage.
        [string]$GithubLogin,
        [string]$VercelScope,
        [string]$ChromeProfile
    )

    if ($Name -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "Nom de contexte invalide : minuscules, chiffres et tirets uniquement."
    }

    Test-CtxVault
    $ctx = Get-CtxPath $Name
    if (Test-Path $ctx) { throw "Le contexte '$Name' existe deja ($ctx)." }
    if (-not $Root) { $Root = "F:\PROJECTS\Clients\$Name" }

    # Deux contextes qui se recouvrent rendent la resolution par chemin
    # ambigue — donc le garde-fou incertain, donc inutile.
    $newRoot = Get-NormalizedRoot $Root
    foreach ($m in Get-CtxManifests) {
        $existing = Get-CtxProp $m 'root'
        if (-not $existing) { continue }
        $existingRoot = Get-NormalizedRoot $existing
        if ($newRoot -eq $existingRoot) {
            throw "La racine '$Root' est deja celle du contexte '$($m.name)'."
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Creer le contexte')) { return }

    # --- Arborescence ---
    foreach ($sub in 'gh', 'vercel', 'vscode', 'vscode-ext', 'ssh') {
        New-Item -ItemType Directory -Force -Path (Join-Path $ctx $sub) | Out-Null
    }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    # --- Manifeste (aucun secret ici) ---
    $manifest = [ordered]@{
        name          = $Name
        label         = $Label
        email         = $Email
        root          = $Root
        createdAt     = (Get-Date -Format 'yyyy-MM-dd')
        git           = [ordered]@{ userName = $GitUserName; userEmail = $Email }
        github        = [ordered]@{ host = "github-$Name"; org = $GithubOrg; login = $GithubLogin }
        vercel        = [ordered]@{ scope = $VercelScope; orgId = '' }
        chromeProfile = $ChromeProfile
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ctx 'context.json') -Encoding UTF8

    # --- Cle SSH dediee ---
    # Interactif volontairement : une passphrase vide sur une cle qui donne acces
    # au depot d'un client, ce n'est pas une bonne idee. Utiliser ssh-agent ensuite.
    $keyPath = Join-Path $ctx 'ssh\id_ed25519'
    if (-not (Test-Path $keyPath)) {
        Write-Host "  Generation de la cle SSH du contexte (passphrase recommandee) :" -ForegroundColor Cyan
        ssh-keygen -t ed25519 -C $Email -f $keyPath
    }

    # --- gitconfig du contexte (inclus conditionnellement) ---
    $ctxGitConfig = Join-Path $ctx 'gitconfig'
    @"
# Genere par DevContext — contexte $Name
[user]
	name = $GitUserName
	email = $Email

# Reecrit toute URL github.com vers l'alias SSH du contexte.
# Effet de bord voulu : impossible de pousser avec la mauvaise identite
# depuis un depot situe sous $Root
[url "git@github-${Name}:"]
	insteadOf = git@github.com:
	insteadOf = https://github.com/
"@ | Set-Content $ctxGitConfig -Encoding UTF8

    # --- Enregistrement du includeIf dans le .gitconfig global ---
    $gitDirPattern = ($Root -replace '\\', '/').TrimEnd('/') + '/'
    $includeBlock = @"

[includeIf "gitdir/i:$gitDirPattern"]
	path = $(($ctxGitConfig -replace '\\', '/'))
"@
    if (-not (Test-Path $script:GitConfig) -or
        -not (Select-String -Path $script:GitConfig -SimpleMatch "gitdir/i:$gitDirPattern" -Quiet)) {
        Add-Content -Path $script:GitConfig -Value $includeBlock -Encoding UTF8
    }

    # --- Bloc SSH ---
    $sshBlock = @"

Host github-$Name
	HostName github.com
	User git
	IdentityFile $keyPath
	IdentitiesOnly yes
"@
    if (-not (Test-Path $script:SshConfig)) {
        New-Item -ItemType File -Force -Path $script:SshConfig | Out-Null
    }
    if (-not (Select-String -Path $script:SshConfig -SimpleMatch "Host github-$Name" -Quiet)) {
        Add-Content -Path $script:SshConfig -Value $sshBlock -Encoding UTF8
    }

    # --- Saisie des tokens ---
    Write-Host ""
    Write-Host "  Tokens du contexte (Entree pour passer)" -ForegroundColor Cyan
    foreach ($key in $script:SecretMap.Keys) {
        $secure = Read-Host "    $key" -AsSecureString
        if ($secure.Length -gt 0) { Set-CtxSecret -Name $Name -Key $key -Value $secure }
    }

    Write-Host ""
    Write-Host "  Contexte '$Label' cree." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Reste a faire, une seule fois :" -ForegroundColor Yellow
    Write-Host "    1. Ajouter la cle publique au compte GitHub $Email :"
    Write-Host "       $keyPath.pub"
    Write-Host "    2. work $Name ; gh auth login   (config isolee dans $ctx\gh)"
    Write-Host "    3. Creer le profil Chrome dedie, puis renseigner 'chromeProfile' dans context.json"
    Write-Host "    4. code-ctx $Name   (VS Code vierge : connecter le compte du client)"
    if (-not $GithubLogin) {
        Write-Host "    5. Renseigner 'github.login' dans context.json — sans lui, 'ctx' ne peut" -ForegroundColor Yellow
        Write-Host "       que rapporter le compte actif, jamais verifier que c'est le bon." -ForegroundColor Yellow
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# ctx-end — fin de mission : checklist de transfert + purge
# ---------------------------------------------------------------------------

function Close-DevContext {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [switch]$Purge
    )

    $m   = Read-CtxManifest $Name
    $ctx = Get-CtxPath $Name

    Write-Host ""
    Write-Host "  TRANSFERT — $(Get-CtxProp $m 'label' $Name) ($(Get-CtxProp $m 'email'))" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  A verifier avant de purger :" -ForegroundColor Yellow
    Write-Host "    [ ] 2FA du Gmail bascule sur le client (pas ton telephone / ton authenticator)"
    Write-Host "    [ ] Numero de recuperation et email de secours retires du compte Google"
    Write-Host "    [ ] Moyen de paiement retire de Vercel et Supabase, remplace par celui du client"
    Write-Host "    [ ] Ta cle SSH perso absente des Deploy keys du/des depots"
    Write-Host "    [ ] Tokens revoques cote fournisseur (les supprimer du coffre ne les revoque pas) :"
    Write-Host "          github.com/settings/tokens  |  vercel.com/account/tokens  |  supabase.com/dashboard/account/tokens"
    Write-Host "    [ ] Mot de passe du Gmail change et transmis au client"
    Write-Host "    [ ] Sauvegarde du depot archivee de ton cote si le contrat le prevoit"
    Write-Host ""

    if (-not $Purge) {
        Write-Host "  Relancer avec -Purge pour supprimer secrets et dossier de contexte." -ForegroundColor DarkGray
        return
    }

    if ($env:DEVCTX -eq $Name) {
        throw "Le contexte '$Name' est actif dans ce terminal. 'ctx-off' d'abord — purger sous soi laisse des secrets charges en memoire."
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Purger secrets, contexte, entrees git et ssh')) { return }

    foreach ($key in $script:SecretMap.Keys) {
        Remove-Secret -Vault $script:VaultName -Name "devctx/$Name/$key" -ErrorAction SilentlyContinue
    }
    if (Test-Path $ctx) { Remove-Item $ctx -Recurse -Force }

    Write-Host "  Secrets et dossier supprimes." -ForegroundColor Green
    Write-Host "  Retirer manuellement le bloc 'Host github-$Name' de $($script:SshConfig)" -ForegroundColor Yellow
    Write-Host "  et le bloc includeIf correspondant de $($script:GitConfig)." -ForegroundColor Yellow
    Write-Host "  Le dossier projet $(Get-CtxProp $m 'root') n'a pas ete touche." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# ctx — verification : suis-je bien la ou je crois, avec qui je crois ?
# ---------------------------------------------------------------------------

function Get-CtxVercelState {
    # L'isolation Vercel repose sur DEUX mecanismes possibles : un dossier de
    # session cree par `vercel login`, ou VERCEL_TOKEN. Ne tester que la variable
    # affichait « aucun token » alors que le contexte etait parfaitement isole.
    # Un indicateur qui crie au loup sur un dispositif qui marche finit par etre
    # ignore le jour ou il a raison.
    if ($env:VERCEL_TOKEN) { return 'token charge' }
    if ($env:DEVCTX_VERCEL_CONFIG -and
        (Test-Path (Join-Path $env:DEVCTX_VERCEL_CONFIG 'auth.json'))) {
        return 'session dediee'
    }
    return 'aucune session'
}

function Test-DevContext {
    <#
      Ancienne version : affichait git / gh / vercel / supabase et s'arretait la.
      Elle RAPPORTAIT sans jamais JUGER — donc elle ne pouvait pas attraper le
      seul scenario qui compte : se tenir dans le dossier d'un contexte avec
      l'identite d'un autre.

      Trois verdicts desormais, et un code de sortie exploitable en script :
        - le dossier courant appartient-il au contexte actif ?
        - le compte GitHub reellement authentifie est-il celui attendu ?
        - un contexte est-il seulement actif ?
    #>
    [CmdletBinding()]
    param([switch]$Quiet)

    $problems = @()
    $owner    = Resolve-DevContextForPath
    $here     = (Get-Location).Path

    if (-not $Quiet) {
        Write-Host ""
        if ($env:DEVCTX) {
            Write-Host "  Contexte actif : $env:DEVCTX_LABEL ($env:DEVCTX)" -ForegroundColor Cyan
        }
        else {
            Write-Host "  Contexte actif : AUCUN" -ForegroundColor Red
        }
        Write-Host "  Dossier        : $here" -ForegroundColor DarkGray
    }

    # --- 1. Le dossier appartient-il au contexte actif ? ---
    if ($owner) {
        if (-not $env:DEVCTX) {
            $problems += "Ce dossier appartient au contexte '$($owner.name)', et aucun contexte n'est actif."
        }
        elseif ($owner.name -ne $env:DEVCTX) {
            $problems += "Ce dossier appartient au contexte '$($owner.name)', mais '$env:DEVCTX' est actif."
        }
    }
    elseif ($env:DEVCTX -and $env:DEVCTX_ROOT_PATH) {
        $problems += "Hors de la racine du contexte actif ($env:DEVCTX_ROOT_PATH)."
    }

    # --- 2. Le compte GitHub actif est-il celui attendu ? ---
    $ghLogin = $null
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghLogin = gh api user --jq .login 2>$null
    }
    $expected = $env:DEVCTX_GH_LOGIN
    if ($expected -and $ghLogin -and ($ghLogin -ne $expected)) {
        $problems += "Compte GitHub actif '$ghLogin' — le contexte attend '$expected'."
    }
    if ($env:DEVCTX -and -not $expected) {
        $problems += "Le contexte n'a pas de 'github.login' dans son manifeste : le compte actif ne peut pas etre verifie, seulement affiche."
    }
    if (-not $env:GH_CONFIG_DIR) {
        $problems += "GH_CONFIG_DIR absent : 'gh' utilise la config GLOBALE de la machine, donc le dernier compte connecte."
    }

    # --- 3. Le jeton Supabase exporte correspond-il au projet du dossier ? ---
    # C'est la variable d'environnement qui compte, pas le wrapper : un binaire
    # appele directement (execFileSync, bash, agent IA) n'a que celle-la.
    if ($env:DEVCTX -and (Resolve-CtxSupabaseRef)) {
        $expectedKey = Resolve-CtxSupabaseKey
        if (-not $expectedKey) {
            $problems += "Projet Supabase de ce dossier absent de l'index. Lance 'sb-index'."
        }
        elseif ($env:DEVCTX_SUPABASE_KEY -ne $expectedKey) {
            $actual = if ($env:DEVCTX_SUPABASE_KEY) { $env:DEVCTX_SUPABASE_KEY } else { 'aucune' }
            $problems += "SUPABASE_ACCESS_TOKEN porte la cle '$actual' alors que ce projet attend '$expectedKey'. Corriger avec 'work $env:DEVCTX -NoCd'."
        }
    }

    if (-not $Quiet) {
        Write-Host "  git            : $(git config user.email 2>$null)"
        Write-Host "  gh             : $(if ($ghLogin) { $ghLogin } else { '(non authentifie)' })"
        Write-Host "  vercel         : $(Get-CtxVercelState)"
        $sbState = if ($env:SUPABASE_ACCESS_TOKEN) {
            if ($env:DEVCTX_SUPABASE_KEY) { "token charge ($env:DEVCTX_SUPABASE_KEY)" } else { 'token charge' }
        } else { 'aucun token' }
        Write-Host "  supabase       : $sbState"
        if (Test-Path .git) {
            Write-Host "  remote (push)  : $(git remote get-url --push origin 2>$null)"
        }
        Write-Host ""
        if ($problems.Count -eq 0) {
            Write-Host "  GO — identite, dossier et compte concordent." -ForegroundColor Green
        }
        else {
            Write-Host "  NO-GO" -ForegroundColor Red
            foreach ($p in $problems) { Write-Host "    - $p" -ForegroundColor Red }
        }
        Write-Host ""
    }

    # Le booleen ne sort qu'en mode -Quiet. Affiche apres un NO-GO, un « False »
    # nu ressemble a un plantage : le verdict est deja ecrit en clair au-dessus,
    # et `ctx-check` couvre le besoin scriptable en levant une exception.
    if ($Quiet) { return ($problems.Count -eq 0) }
}

function Assert-DevContext {
    <#
      Meme verification, mais elle LEVE. Utilisable en tete d'un script, dans un
      hook git, ou avant toute commande sortante. Un affichage ne protege que
      celui qui le lit.
    #>
    [CmdletBinding()]
    param()
    # -Quiet est OBLIGATOIRE ici : depuis que `ctx` ne renvoie plus de booleen en
    # mode affichage, un appel sans -Quiet renverrait $null, et `-not $null` vaut
    # $true — la garde leverait sur un contexte parfaitement coherent.
    if (-not (Test-DevContext -Quiet)) {
        # Le detail n'est utile qu'en cas d'echec : on le reaffiche alors, au
        # prix d'un second controle. Sur le chemin nominal, aucune sortie.
        Test-DevContext | Out-Null
        throw "Contexte incoherent — commande interrompue."
    }
}

# ---------------------------------------------------------------------------

Set-Alias -Name work      -Value Use-DevContext
Set-Alias -Name ctx       -Value Test-DevContext
Set-Alias -Name ctx-check -Value Assert-DevContext
Set-Alias -Name ctx-list  -Value Get-DevContextList
Set-Alias -Name ctx-new   -Value New-DevContext
Set-Alias -Name ctx-off   -Value Clear-DevContext
Set-Alias -Name ctx-end   -Value Close-DevContext
Set-Alias -Name ctx-who   -Value Resolve-DevContextForPath
Set-Alias -Name code-ctx  -Value Open-DevCode
Set-Alias -Name web-ctx   -Value Open-DevBrowser
Set-Alias -Name vercel    -Value Invoke-DevVercel
Set-Alias -Name supabase  -Value Invoke-DevSupabase
Set-Alias -Name sb-index  -Value Update-DevSupabaseIndex

$exportedFunctions = @(
    'Use-DevContext', 'Clear-DevContext', 'Get-DevContextList', 'New-DevContext',
    'Close-DevContext', 'Open-DevCode', 'Open-DevBrowser', 'Test-DevContext',
    'Assert-DevContext', 'Resolve-DevContextForPath', 'Invoke-DevVercel',
    'Invoke-DevSupabase', 'Update-DevSupabaseIndex'
)
$exportedAliases = @(
    'work', 'ctx', 'ctx-check', 'ctx-list', 'ctx-new', 'ctx-off', 'ctx-end',
    'ctx-who', 'code-ctx', 'web-ctx', 'vercel', 'supabase', 'sb-index'
)

Export-ModuleMember -Function $exportedFunctions -Alias $exportedAliases
