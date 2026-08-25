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

function Get-CtxConfigPath {
    <#
      Ou vit le reglage machine du module.

      Aux emplacements que le systeme prevoit pour cela, et nulle part ailleurs :
      pas a cote du depot, qui peut demenager, ni sur un lecteur qui peut ne pas
      exister.
    #>
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'DevContext', 'config.json')
    }
    else {
        [System.IO.Path]::Combine($HOME, '.config', 'devcontext', 'config.json')
    }
}

function Get-CtxRootDefault {
    <#
      Ou vivent les contextes. Trois sources, dans cet ordre.

      1. $env:DEVCTX_ROOT — le dernier mot, pour un shell, un test, une CI.
      2. Le fichier de configuration — pose une fois par `ctx-root`, et c'est
         ce que la plupart des gens utiliseront sans jamais le savoir.
      3. Un defaut PORTABLE.

      Le defaut valait 'F:\CTX'. Ce lecteur est celui de l'auteur : sur toute
      autre machine, le module se chargeait sans erreur et ne trouvait aucun
      contexte, `ctx-new` echouait sur un lecteur absent, et DEVCTX_ROOT
      n'apparaissait dans aucune documentation. Autrement dit, l'outil ne
      fonctionnait que chez une personne, en silence. Releve le 15 aout 2026.

      Le defaut est desormais celui que le systeme prevoit pour des donnees
      applicatives : %LOCALAPPDATA%\DevContext\contexts sous Windows,
      ~/.local/share/devcontext/contexts ailleurs. Une installation existante ne
      bouge pas — son chemin est dans le fichier de configuration, que
      l'installateur y ecrit.
    #>
    if ($env:DEVCTX_ROOT) { return $env:DEVCTX_ROOT }

    $config = Get-CtxConfigPath
    if (Test-Path -LiteralPath $config) {
        try {
            $lu = Get-Content -LiteralPath $config -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            # PAS Get-CtxProp : cette fonction s'execute pendant le CHARGEMENT du
            # module, avant que les helpers plus bas n'existent. L'appeler ici
            # levait, le catch avalait l'erreur, et le reglage etait ignore en
            # silence -- les contextes d'une installation existante se seraient
            # volatilises sans un mot. Trouve en verifiant, pas en relisant.
            $racine = if ($lu -and $lu.PSObject.Properties.Name -contains 'root') { [string]$lu.root }
            if ($racine) { return $racine }
        }
        catch {
            # Un reglage illisible ne doit pas empecher le module de se charger :
            # il retombe sur le defaut, et `ctx doctor` le signale.
            Write-Verbose "config.json illisible : $($_.Exception.Message)"
        }
    }

    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        [System.IO.Path]::Combine($env:LOCALAPPDATA, 'DevContext', 'contexts')
    }
    else {
        [System.IO.Path]::Combine($HOME, '.local', 'share', 'devcontext', 'contexts')
    }
}

$script:CtxRoot   = Get-CtxRootDefault
$script:VaultName = 'DevContext'

function Set-DevContextRoot {
    <#
    .SYNOPSIS
        Choisit ou vivent les contextes, une fois pour toutes.

    .DESCRIPTION
        Ecrit le chemin dans le reglage machine, lu par toute session ulterieure.
        Sans cela, chacun devrait poser DEVCTX_ROOT dans son profil PowerShell --
        un reglage qu'on oublie de reporter sur la machine suivante, et qui
        s'evapore quand on lance un shell sans profil.

        Les contextes contiennent des cles SSH et des configurations de compte.
        Les poser sur un lecteur amovible ou un partage reseau, c'est accepter
        qu'ils disparaissent au milieu d'une session -- possible, mais que ce
        soit un choix, pas une surprise.

        Ne DEPLACE rien : le contenu existant reste ou il est. La commande
        signale ce qu'elle a trouve a l'ancien emplacement.

    .PARAMETER Path
        Dossier des contextes. Cree s'il n'existe pas.

    .EXAMPLE
        ctx-root D:\DevContext

    .EXAMPLE
        ctx-root    # affiche la racine active et d'ou elle vient
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Position = 0)][string]$Path)

    if (-not $Path) {
        $origine = if ($env:DEVCTX_ROOT) { T 'racine.source.variable' }
        elseif (Test-Path -LiteralPath (Get-CtxConfigPath)) { T 'racine.source.reglage' (Get-CtxConfigPath) }
        else { T 'racine.source.defaut' }

        Write-Host ''
        Write-Host "  $(T 'racine.titre' $script:CtxRoot)" -ForegroundColor Cyan
        Write-Host "    $(T 'racine.source' $origine)"
        Write-Host "    $(T 'racine.existe' (Test-Path -LiteralPath $script:CtxRoot))"
        Write-Host "    $(T 'racine.contextes' @(Get-CtxManifests).Count)"
        Write-Host ''
        Write-Host "  $(T 'racine.changer')" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $cible = [System.IO.Path]::GetFullPath($Path)
    $config = Get-CtxConfigPath

    if (-not $PSCmdlet.ShouldProcess($config, "pointer la racine des contextes sur $cible")) { return }

    $dossierConfig = Split-Path $config -Parent
    if (-not (Test-Path -LiteralPath $dossierConfig)) {
        New-Item -ItemType Directory -Path $dossierConfig -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $cible)) {
        New-Item -ItemType Directory -Path $cible -Force | Out-Null
    }

    $ancienne = $script:CtxRoot
    @{ root = $cible } | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding UTF8
    $script:CtxRoot = $cible

    Write-Host ''
    Write-Host "  $(T 'racine.titre' $cible)" -ForegroundColor Green
    Write-Host "    $(T 'racine.ecrit' $config)" -ForegroundColor DarkGray

    if ($ancienne -and $ancienne -ne $cible -and (Test-Path -LiteralPath $ancienne)) {
        $restes = @(Get-ChildItem -LiteralPath $ancienne -Directory -ErrorAction SilentlyContinue)
        if ($restes) {
            Write-Host ''
            Write-Host "  $(T 'racine.restes' $restes.Count)" -ForegroundColor Yellow
            Write-Host "    $ancienne" -ForegroundColor Yellow
            Write-Host "    $(T 'racine.restesRien')" -ForegroundColor DarkGray
            Write-Host "    $(T 'racine.restesDecision')" -ForegroundColor DarkGray
        }
    }
    if ($env:DEVCTX_ROOT -and $env:DEVCTX_ROOT -ne $cible) {
        Write-Host ''
        Write-Warning (T 'racine.varPrime' $env:DEVCTX_ROOT)
    }
    Write-Host ''
}

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
# Modules de fonctionnalités
# ---------------------------------------------------------------------------
#
# Sourcés, et non déclarés en NestedModules : ils partagent ainsi la portée du
# module — ils voient $script:CtxRoot et les helpers internes — et un seul
# Export-ModuleMember reste la source de vérité de ce qui sort. Le manifeste est
# le second verrou : l'export réel est l'INTERSECTION des deux listes, et une
# fonction ajoutée à une seule des deux devient invisible sans la moindre erreur.

foreach ($fichier in @('Chemins.ps1', 'Langue.ps1', 'Doctor.ps1', 'Fix.ps1', 'Jetons.ps1', 'Mcp.ps1', 'Editors.ps1', 'Agents.ps1', 'Shortcuts.ps1', 'Dashboard.ps1', 'Gh.ps1', 'Vercel.ps1', 'Init.ps1', 'Ctx.ps1')) {
    . (Join-Path $PSScriptRoot 'src' $fichier)
}

# La langue est resolue une fois, au chargement : DEVCTX_LANG, puis la culture
# du systeme, puis l'anglais. Un shell qui pose la variable et reimporte le
# module change de langue ; sinon rien a configurer.
Set-CtxLangue | Out-Null

# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

function Get-CtxPath {
    # Combine, pas Join-Path : ce dernier resout le LECTEUR et echoue sur
    # « Cannot find drive » quand la racine vit sur un volume non monte -- une
    # cle USB retiree, un lecteur reseau absent, ou simplement le lecteur de
    # quelqu'un d'autre. Ici on fabrique un chemin, on ne visite pas un endroit.
    param([Parameter(Mandatory)][string]$Name)
    [System.IO.Path]::Combine($script:CtxRoot, $Name)
}

function Read-CtxManifest {
    param([Parameter(Mandatory)][string]$Name)

    $manifest = Join-Path (Get-CtxPath $Name) 'context.json'
    if (-not (Test-Path $manifest)) {
        throw (T 'manifeste.introuvable' $Name $manifest)
    }
    Get-Content $manifest -Raw | ConvertFrom-Json
}

function Get-CtxProp {
    # Lecture defensive : les manifestes crees avant l'ajout d'un champ n'ont
    # pas ce champ, et Set-StrictMode transforme un acces absent en exception.
    #
    # [AllowNull()] parce que « defensive » doit valoir aussi pour l'objet
    # lui-meme : un dossier hors contexte n'a pas de manifeste, et le seul
    # appelant qui l'avait oublie faisait planter `ctx doctor -Live` par une
    # erreur de liaison de parametre — pas par la lecture qu'il tentait.
    # Mandatory reste : omettre l'argument est toujours une faute.
    param(
        [Parameter(Mandatory)][AllowNull()]$Object,
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
        throw (T 'vault.absent')
    }
    if (-not (Get-SecretVault -Name $script:VaultName -ErrorAction SilentlyContinue)) {
        Write-Host (T 'vault.creation' $script:VaultName) -ForegroundColor Yellow
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Aide privee, non exportee : -WhatIf ne peut pas lui parvenir. La commande publique qui l appelle porte la confirmation.')]
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

    # Une liste vide qui ne dit pas quoi faire ensuite laisse l'utilisateur a
    # l'arret. C'est la premiere commande que beaucoup taperont ; elle doit
    # donner la suivante.
    $manifestes = @(Get-CtxManifests)
    if ($manifestes.Count -eq 0) {
        $absente = if (Test-Path -LiteralPath $script:CtxRoot) { '' } else { T 'liste.vide.racineAbsente' }
        Write-Host ''
        Write-Host "  $(T 'liste.vide.titre')" -ForegroundColor Yellow
        Write-Host "  $(T 'liste.vide.racine' $script:CtxRoot)$absente" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host "  $(T 'liste.vide.creer')" -ForegroundColor Cyan
        Write-Host "    $(T 'ctx.vide.exemple')" -ForegroundColor Cyan
        Write-Host ''
        Write-Host "  $(T 'liste.vide.racineAilleurs')" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $manifestes | ForEach-Object {
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
    Write-Host "  $(T 'work.contexte' $env:DEVCTX_LABEL)" -ForegroundColor Cyan
    Write-Host "  $(T 'work.compte' (Get-CtxProp $m 'email'))"  -ForegroundColor DarkGray
    Write-Host "  $(T 'work.secrets' $(if ($loaded) { $loaded -join ', ' } else { T 'work.secretsAucun' }))" -ForegroundColor DarkGray
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
    # PAS $EventArgs : c'est une variable automatique de PowerShell, et la
    # nommer en parametre la masque en silence. Exactement le piege que
    # AGENTS.md documente pour $Args -- qui avait rendu le shim aveugle en aout
    # 2026 -- cache ici depuis le debut, dans le module lui-meme. Releve par
    # PSScriptAnalyzer le 15 aout 2026.
    param($Source, $Emplacement)
    # DEVCTX_LOCATION_HOOK
    if ($script:PreviousLocationChangedAction) {
        # Ce handler appartient a quelqu'un d'autre -- oh-my-posh, un autre
        # module. S'il leve, ce n'est pas a nous de le faire remonter : ce code
        # s'execute a CHAQUE `cd`, et une exception ici casse la session
        # entiere. On note et on continue.
        try { & $script:PreviousLocationChangedAction $Source $Emplacement }
        catch { Write-Verbose "handler LocationChanged tiers en echec : $($_.Exception.Message)" }
    }
    # Meme raison : jamais bloquant.
    try { Sync-CtxSupabaseEnv }
    catch { Write-Verbose "Sync-CtxSupabaseEnv en echec : $($_.Exception.Message)" }
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
    Write-Host "  $(T 'off.aucunActif')" -ForegroundColor Red
    if (-not (Test-Path $manifest)) {
        Write-Host "  $(T 'off.manquant1' $homeCtx)" -ForegroundColor Yellow
        Write-Host "  $(T 'off.manquant2')" -ForegroundColor Yellow
        Write-Host "  $(T 'off.manquant3')" -ForegroundColor Yellow
        Write-Host ""
        # L'exemple ne code plus le lecteur de l'auteur en dur : il montre un
        # chemin sous le dossier personnel, valable sur n'importe quelle machine.
        Write-Host "    $(T 'off.exemple' $homeCtx)" -ForegroundColor DarkGray
        Write-Host "      $(T 'off.exempleSuite' ([System.IO.Path]::Combine($HOME, 'dev')))" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# code-ctx — VS Code isole
# ---------------------------------------------------------------------------

function Get-CtxVariablesNonInteractives {
    <#
      PURE. Les variables qui signifient « je ne suis pas un terminal humain »,
      et qui n'ont donc rien a faire dans ce qu'un EDITEUR herite.

      POURQUOI CETTE FONCTION EXISTE. Ce module s'appuie sur l'heritage
      d'environnement pour transmettre le contexte a l'editeur -- c'est ecrit
      dans Open-DevCode juste en dessous. Le meme heritage transmet tout le
      reste, y compris ce que l'appelant est.

      Mesure le 22 aout 2026 : une fenetre VS Code ouverte depuis la session d'un
      agent avait ses terminaux integres sans aucune couleur. Cause : l'agent
      pose NO_COLOR=1 pour obtenir des sorties propres, PowerShell 7 respecte
      cette convention en basculant $PSStyle.OutputRendering sur PlainText, et
      la variable descendait jusqu'a chaque terminal de la fenetre. Le prompt
      emettait bien ses sequences ANSI ; l'hote les retirait au rendu.

      LISTE FERMEE, jamais une heuristique. « Ce qui ressemble a de
      l'automatisation » produirait des faux positifs sur des reglages
      deliberes, et retirer en silence le choix de quelqu'un est pire que le
      probleme. Quatre entrees, chacune avec sa raison :

        NO_COLOR      n'affiche pas de couleur
        FORCE_COLOR   le signal miroir, tout aussi peu pertinent dans un editeur
        CI            ceci est une construction, pas une session
        TERM=dumb     ce terminal n'a aucune capacite -- et SEULEMENT a 'dumb' :
                      un TERM legitime ne se touche pas

      Prend l'environnement en argument plutot que de lire $env: : c'est ce qui
      rend la decision verifiable sans fabriquer un processus.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][hashtable]$Environnement)

    if (-not $Environnement) { return }

    foreach ($nom in @('NO_COLOR', 'FORCE_COLOR', 'CI')) {
        if ($Environnement.ContainsKey($nom) -and
            -not [string]::IsNullOrWhiteSpace([string]$Environnement[$nom])) { $nom }
    }

    # TERM merite son cas a part : seule la valeur 'dumb' dit « pas de
    # capacites ». Retirer un TERM=xterm-256color casserait ce qu'il decrit.
    if ($Environnement.ContainsKey('TERM') -and
        ([string]$Environnement['TERM']).Trim() -eq 'dumb') { 'TERM' }
}

function Invoke-CtxSansHeritageNonInteractif {
    <#
      Execute $Action avec l'environnement PRIVE des variables ci-dessus, puis
      les restaure -- meme si $Action leve.

      FONCTION A PART, ET NON TROIS LIGNES DANS Open-DevCode. Ce qu'elle fait se
      verifie alors sans contexte declare et sans editeur installe. La premiere
      version vivait dans Open-DevCode, et son test appelait donc toute la
      chaine : vert sur la machine de l'auteur, ROUGE en CI, ou il n'existe ni
      contexte 'perso' ni editeur. C'est le piege qu'AGENTS.md nomme -- un test
      dont le resultat depend de la machine ne prouve rien ailleurs. La CI l'a
      attrape avant la fusion, le 22 aout 2026.

      L'appelant garde son environnement : il n'a pas demande qu'on le modifie.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Action)

    $vue = @{}
    foreach ($e in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $vue[[string]$e.Key] = [string]$e.Value
    }

    $retirees = @{}
    foreach ($nom in @(Get-CtxVariablesNonInteractives -Environnement $vue)) {
        $retirees[$nom] = $vue[$nom]
        Remove-Item -LiteralPath "Env:$nom" -ErrorAction SilentlyContinue
    }
    # JAMAIS EN SILENCE. Un environnement modifie sans un mot est exactement le
    # genre de chose qu'on cherche pendant une heure six mois plus tard.
    if ($retirees.Count) {
        Write-Verbose (T 'code.envRetire' (($retirees.Keys | Sort-Object) -join ', '))
    }

    try { & $Action }
    finally {
        foreach ($nom in $retirees.Keys) { Set-Item -LiteralPath "Env:$nom" -Value $retirees[$nom] }
    }
}

function Open-DevCode {
    <#
      Ouvre un editeur, detache, sur le profil du contexte.

      -Editor generalise ce qui etait cable sur VS Code. Les flags ne sont plus
      ecrits en dur : ils viennent de Resolve-CtxEditorArguments, donc d'une
      capacite MESUREE. Passer --extensions-dir a un editeur qui l'ignore se lit
      comme de l'isolation dans le raccourci alors que les extensions restent
      partagees — Antigravity est exactement ce cas.

      Le dossier de profil reste 'vscode' pour VS Code : de vraies sessions y
      vivent depuis aout 2026, et le renommer pour faire propre deconnecterait
      tout le monde de tous ses contextes d'un coup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name = $env:DEVCTX,
        [Parameter(Position = 1)][string]$Path,
        [string]$Editor = 'code'
    )

    if (-not $Name) { throw (T 'code.aucunActif') }

    $m   = Read-CtxManifest $Name
    $ctx = Get-CtxPath $Name
    if (-not $Path) { $Path = Get-CtxProp $m 'root' }

    $editeur = Get-CtxEditorFacts | Where-Object Name -eq $Editor | Select-Object -First 1
    if (-not $editeur) {
        throw (T 'code.editeurInconnu' $Editor)
    }

    # L'isolation reelle : ces editeurs chiffrent leurs sessions d'auth (DPAPI
    # sous Windows) dans le state.vscdb du user-data-dir. Un user-data-dir par
    # contexte = des comptes GitHub/Copilot independants, en simultane.
    $capacites = Get-CtxEditorCapabilitiesCached -Editor $editeur
    $codeArgs = Resolve-CtxEditorArguments -Capabilities $capacites -ContextDir $ctx `
        -ProfileName $editeur.Profile -Arguments @($Path)

    if (-not $capacites.UserDataDir) {
        Write-Warning (T 'editeur.sansUserDataDir' $editeur.Label)
    }

    $codeCmd = if ($editeur.Cli) { [pscustomobject]@{ Source = $editeur.Cli } }
    if (-not $codeCmd) {
        throw (T 'code.sansCli' $Editor)
    }

    Write-Host "  $(T 'code.ouverture' $editeur.Label (Get-CtxProp $m 'label' $Name) $Path)" -ForegroundColor Cyan

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
    # CE QUE L'EDITEUR NE DOIT PAS HERITER.
    #
    # L'heritage ci-dessus est voulu pour le contexte. Il transmet aussi ce que
    # l'APPELANT est : lance depuis un agent ou une CI, l'editeur recoit les
    # variables qui disent qu'il n'est pas un terminal humain, et chacun de ses
    # terminaux integres en herite a son tour, pour toute la session.
    #
    # Mesure le 22 aout 2026 : une fenetre ouverte depuis la session d'un agent
    # avait tous ses terminaux sans couleur. NO_COLOR=1 -> PowerShell bascule
    # $PSStyle.OutputRendering sur PlainText -> les sequences ANSI du prompt
    # sont retirees au rendu. Le symptome survit a la fermeture du terminal,
    # puisqu'il vit dans le processus de la FENETRE.
    Invoke-CtxSansHeritageNonInteractif -Action {

        $exe = Find-CtxEditorExecutable -Editor $editeur
        if ($exe) {
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
            #
            # Et on le DIT. Ce repli a ete muet jusqu'au 16 aout 2026, ou il s'est
            # declenche a tort sur toutes les machines : la fenetre d'un raccourci
            # restait ouverte pour toute la session d'edition, sans un mot expliquant
            # pourquoi. Un comportement degrade que rien n'annonce se lit comme une
            # panne -- et la cause etait ailleurs, deux etages plus haut.
            Write-Warning (T 'code.repliSynchrone' $codeCmd.Source $editeur.Label)
            & $codeCmd.Source @codeArgs
        }

    }
}

# ---------------------------------------------------------------------------
# web-ctx — profil navigateur dedie
# ---------------------------------------------------------------------------

function Open-DevBrowser {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name = $env:DEVCTX)

    if (-not $Name) { throw (T 'web.aucunActif') }
    $m = Read-CtxManifest $Name

    $chromeProfile = Get-CtxProp $m 'chromeProfile'
    if (-not $chromeProfile) {
        throw (T 'web.sansProfil' $Name)
    }

    $chrome = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $chrome) { throw (T 'web.chromeAbsent') }

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
    # PAS DE BLOC param() : voir Invoke-DevSupabase. `vercel -d` (debug) suffit a
    # declencher l'ambiguite avec -Debug.
    # @() OBLIGATOIRE. Une fonction ne RENVOIE pas un tableau : PowerShell le
    # deroule sur le flux de sortie, donc un seul argument revient en CHAINE --
    # et `& $exe @arguments` splatte alors ses CARACTERES. Mesure le 18 aout
    # 2026 : `vercel whoami` partait en `w h o a m i`.
    $arguments = @(Get-CtxArgumentsBruts $args)

    # LE GARDE-FOU D'ABORD, et le dossier de config resolu DEPUIS LE DOSSIER.
    #
    # Cet alias precede le shim du PATH dans toute session ayant importe le
    # module : s'il portait sa propre logique, il rendrait un verdict different
    # de celui de git-bash. C'est la panne corrigee en 1.3.5 sur `supabase`, et
    # elle est evitee ici des le premier jour -- une seule regle, deux appelants.
    #
    # L'ancienne version lisait $env:DEVCTX_VERCEL_CONFIG, donc la SESSION.
    # Resolve-CtxVercelVerdict lit le dossier, et ne retombe sur la variable que
    # hors de toute racine de contexte.
    $decision = $null
    try { $decision = Resolve-CtxVercelVerdict -Arguments $arguments }
    catch { $decision = $null }

    if ($decision -and $decision.Verdict -and -not $decision.Verdict.Allowed) {
        Write-CtxVercelRefus -Verdict $decision.Verdict
        throw (T 'vercel.refuseAlias')
    }
    if ($decision -and $decision.Avertissement) {
        Write-Host "  $($decision.Avertissement)" -ForegroundColor DarkGray
    }

    $exe = Get-CtxVercelExe

    if ($decision -and $decision.ConfigDir) {
        & $exe '--global-config' $decision.ConfigDir @arguments
    }
    else {
        & $exe @arguments
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

# The shims live inside the repository, never copied elsewhere -- same doctrine
# as the module itself. See the 12 Aug 2026 entry in CHANGELOG.md: two copies,
# one of them silently ignored, and a fix that had no effect.
$script:ShimDir = Join-Path $PSScriptRoot 'shims'

function Get-CtxShimDirs {
    <#
      TOUS les dossiers susceptibles de contenir nos shims, jamais un seul.

      C'est une correction de fond, pas une commodite. `Get-CtxSupabaseExe`
      comparait le dossier resolu a UN chemin -- celui du module. Des lors que
      PATH designe la jonction, `Get-Command supabase` rend
      ...\DevContext\current\shims\supabase.cmd, une chaine differente de
      ...\Modules\DevContext\1.3.0\shims. L'exclusion echouait, le shim se
      resolvait lui-meme, et s'appelait indefiniment.

      Comparer des chemins qui designent le meme dossier par des noms differents
      est la meme faute que decider sur du texte affiche : la valeur comparee
      n'est pas celle qui porte le sens.
    #>
    @(
        $script:ShimDir
        Get-CtxShimStable
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\', '/') } | Sort-Object -Unique
}

function Get-CtxSupabaseExe {
    <#
      Resolves the REAL supabase binary, skipping every directory of ours.

      Once a shim sits in the PATH, `Get-Command supabase` finds IT first.
      Without this exclusion the shim would invoke itself forever, and the
      module would drive the guard instead of the CLI.

      -ExcludeDir garde sa forme d'origine (un chemin unique) pour les tests et
      les appelants existants ; sans lui, l'ensemble complet est exclu.

      DEUX ECHECS, DEUX MESSAGES. L'exclusion echoue FERMEE -- elle fait lever,
      jamais executer -- et c'est le seul sens acceptable pour un module qui
      garde une base de production. Mais le message, lui, mentait sur sa cause :
      un dossier portant par hasard editor.ps1 et supabase.ps1 rendait
      « supabase introuvable » alors que le binaire etait bien la.

      Un utilisateur bloque par un message faux ne depose pas de rapport : il
      contourne le wrapper et appelle le binaire brut, donc SANS garde. Le
      message est ainsi le dernier endroit ou l'on a le droit d'etre imprecis --
      dire ce qui a ete ecarte, et pourquoi, est ce qui evite le contournement.
    #>
    param([string[]]$ExcludeDir = (Get-CtxShimDirs))

    $exclus = @($ExcludeDir | Where-Object { $_ })

    $tous = @(Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue)
    $candidate = $tous | Where-Object {
        -not (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $_.Source -Parent) -Dossiers $exclus)
    } | Select-Object -First 1

    if (-not $candidate) {
        if ($tous.Count -gt 0) {
            $ecartes = @($tous | ForEach-Object { Split-Path $_.Source -Parent } | Sort-Object -Unique)
            throw (T 'bin.supabaseEcarte' ($ecartes -join ', '))
        }
        throw (T 'bin.supabaseAbsent')
    }
    $candidate.Source
}

function Get-CtxSupabaseKeys {
    # Les cles 'supabase-token*' du contexte reellement presentes au coffre.
    param([Parameter(Mandatory)][string]$Name)
    Get-SecretInfo -Vault $script:VaultName -Name "devctx/$Name/supabase-token*" -ErrorAction SilentlyContinue |
        ForEach-Object { ($_.Name -split '/')[-1] } |
        Sort-Object
}

# Format reel d'un project-ref Supabase : 20 caracteres, minuscules et chiffres.
#
# La validation n'est pas cosmetique. Ce fichier appartient au DEPOT : son
# contenu est choisi par qui a fabrique le depot, et il ressortait tel quel dans
# les `args` d'un `npx` inscrit par `ctx mcp` -- une commande que l'assistant
# relance a chaque demarrage, depuis un fichier fait pour etre commite. Releve
# par l'audit du 15 aout 2026.
$script:SupabaseRefMotif = '^[a-z0-9]{20}$'

function Resolve-CtxSupabaseRef {
    # Remonte l'arborescence a la recherche du project-ref ecrit par `supabase link`.
    param([string]$Path = (Get-Location).Path)

    $dir = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { return $null }
    while ($dir) {
        $file = Join-Path $dir 'supabase\.temp\project-ref'
        if (Test-Path $file) {
            $ref = Get-Content $file -Raw -ErrorAction SilentlyContinue
            if ($ref) {
                $ref = $ref.Trim()
                # Un contenu qui n'a pas la forme d'un ref n'est pas un ref. On
                # rend $null plutot que de le propager : la suite le traitera
                # comme « ce dossier n'est lie a rien », ce qui est vrai.
                #
                # -cmatch et non -match : l'operateur par defaut de PowerShell
                # IGNORE la casse, donc '^[a-z0-9]{20}$' acceptait aussi bien
                # 'AVECDESMAJUSCULES000'. Une validation qu'on croit stricte et
                # qui ne l'est pas est pire qu'une validation absente.
                if ($ref -cmatch $script:SupabaseRefMotif) { return $ref }
                Write-Verbose "project-ref ignore : format inattendu dans $file"
                return $null
            }
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Aide privee, non exportee : pose une variable d environnement du processus courant, pas un etat systeme.')]
    param([AllowEmptyString()][AllowNull()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) {
        Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue
    }
    else { $env:SUPABASE_ACCESS_TOKEN = $Value }
}

# ---------------------------------------------------------------------------
# Environment tagging — which project is production?
# ---------------------------------------------------------------------------

# Naming conventions, not a source of truth. sb-index proposes, the human
# disposes: anything marked 'manual' is never recomputed.
#
# The word boundaries matter: without them 'reproduction-bug' would read as
# production, and a false refusal on a command that had every right to run is
# how a guard loses the trust that makes it useful.
$script:EnvPatternProd = '(^|[^a-z])(prod|production)([^a-z]|$)'
$script:EnvPatternDev  = '(^|[^a-z])(dev|develop|staging|preview|test|sandbox)([^a-z]|$)'

function Get-CtxSupabaseEnvGuess {
    param([AllowNull()][AllowEmptyString()][string]$ProjectName)
    if (-not $ProjectName) { return $null }
    $n = $ProjectName.ToLowerInvariant()
    # Production wins a tie: erring towards the guarded value is the safe side.
    if ($n -match $script:EnvPatternProd) { return 'prod' }
    if ($n -match $script:EnvPatternDev)  { return 'dev' }
    return $null
}

function Merge-CtxSupabaseEnv {
    <#
      Keeps a hand-set value, recomputes an automatic one.

      An entry written before this version carries neither field. Absence of
      'manual' is therefore read as 'auto' -- an old index gets enriched rather
      than mistaken for a deliberate choice.
    #>
    param(
        [Parameter(Mandatory)][string]$Ref,
        [AllowNull()][AllowEmptyString()][string]$ProjectName,
        $Previous
    )
    # Get-CtxProp rather than direct access: an index written before this
    # version carries neither field, and reading an absent property throws
    # under StrictMode. That is not hypothetical -- every existing index on
    # disk is in exactly that state.
    $old = if ($Previous -and $Previous[$Ref]) { $Previous[$Ref] } else { $null }
    if ($old -and (Get-CtxProp $old 'envSource') -eq 'manual') {
        return [pscustomobject]@{ env = (Get-CtxProp $old 'env'); envSource = 'manual' }
    }
    [pscustomobject]@{ env = (Get-CtxSupabaseEnvGuess $ProjectName); envSource = 'auto' }
}

function Get-CtxSupabaseEnv {
    # Reads the tag for one project. Returns $null on anything unexpected --
    # a missing index, a broken index, an unknown ref -- because the guard
    # treats $null as 'do not judge'.
    param(
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$ContextName
    )
    $path = Get-CtxSupabaseIndexPath $ContextName
    if (-not (Test-Path $path)) { return $null }
    try {
        $index = Get-Content $path -Raw | ConvertFrom-Json
        $entry = $index.PSObject.Properties | Where-Object { $_.Name -eq $Ref } | Select-Object -First 1
        if ($entry) { return (Get-CtxProp $entry.Value 'env') }
    }
    catch { return $null }
    return $null
}

function Update-DevSupabaseIndex {
    # SupportsShouldProcess, et il est HONORE plus bas. Cette commande reecrit
    # l'index dont depend le garde-fou production : pouvoir demander ce qu'elle
    # ferait sans qu'elle le fasse n'est pas un ornement.
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name = $env:DEVCTX)

    if (-not $Name) { throw (T 'index.aucunActif') }
    $exe = Get-CtxSupabaseExe

    $keys = @(Get-CtxSupabaseKeys $Name)
    if (-not $keys) { throw "Aucun secret 'supabase-token*' au coffre pour le contexte '$Name'." }

    # Read the existing index BEFORE rebuilding. This function writes a brand
    # new object over the old file, so without this a hand-set env would not
    # survive the first sb-index after someone set it.
    $former = @{}
    $formerPath = Get-CtxSupabaseIndexPath $Name
    if (Test-Path $formerPath) {
        try {
            (Get-Content $formerPath -Raw | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $former[$_.Name] = $_.Value }
        }
        # Message litteral, sans donnee interpolee : rien a caviarder ici.
        catch { Write-Warning (T 'index.ancienIllisible') }
    }

    $index    = [ordered]@{}
    $previous = $env:SUPABASE_ACCESS_TOKEN

    try {
        foreach ($key in $keys) {
            $token = Get-CtxSecret -Name $Name -Key $key
            if (-not $token) { continue }

            Set-CtxSupabaseToken $token
            # stderr ecarte : la CLI y ecrit « Cannot find project ref » des qu'on
            # n'est pas dans un projet lie, ce qui casserait le parsing JSON.
            $raw = (& $exe projects list -o json 2>$null) -join "`n"

            $start = $raw.IndexOf('[')
            if ($start -lt 0) {
                Write-Warning (T 'index.reponseIllisible' $key)
                continue
            }

            $count = 0
            foreach ($p in ($raw.Substring($start) | ConvertFrom-Json)) {
                $merged = Merge-CtxSupabaseEnv -Ref $p.id -ProjectName $p.name -Previous $former
                $index[$p.id] = [ordered]@{
                    key       = $key
                    name      = $p.name
                    env       = $merged.env
                    envSource = $merged.envSource
                }
                $count++
            }
            Write-Host ("  {0,-22} {1} projet(s)" -f $key, $count) -ForegroundColor DarkGray
        }
    }
    finally { Set-CtxSupabaseToken $previous }

    $path = Get-CtxSupabaseIndexPath $Name
    if ($PSCmdlet.ShouldProcess($path, 'reecrire l index Supabase')) {
        $index | ConvertTo-Json -Depth 4 | Set-Content $path -Encoding UTF8
    }
    Write-Host "  $(T 'index.ecrit' $path)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# ctx-sb — which project lives on which account
# ---------------------------------------------------------------------------

function Get-CtxSupabaseMapRoot {
    # Own function so tests can point it elsewhere without a fake manifest.
    param([Parameter(Mandatory)][string]$Name)
    Get-CtxProp (Read-CtxManifest $Name) 'root'
}

function Get-DevSupabaseMap {
    <#
      .SYNOPSIS
        Which Supabase project lives on which account, which one is production,
        and which folders point at it.

      .DESCRIPTION
        Crosses the context index with every `supabase/.temp/project-ref` found
        under the context root, and flags any project targeted by more than one
        folder.

        This is not a convenience. On 13 Aug 2026 the question "which account
        is this site on?" could only be answered by reading the index by
        hand, though the answer had been on the machine since the beginning. A
        guard whose data cannot be inspected is a guard that eventually gets
        switched off.

      .EXAMPLE
        ctx-sb

      .EXAMPLE
        ctx-sb | Where-Object Partage
        Only the projects several folders point at.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name = $env:DEVCTX)

    if (-not $Name) { throw (T 'sb.aucunActif') }

    $indexPath = Get-CtxSupabaseIndexPath $Name
    if (-not (Test-Path $indexPath)) { throw (T 'sb.sansIndex' $Name) }
    $index = Get-Content $indexPath -Raw | ConvertFrom-Json

    $root = Get-CtxSupabaseMapRoot $Name
    $byRef = @{}

    if ($root -and (Test-Path $root)) {
        $rootLength = $root.TrimEnd('\', '/').Length + 1
        Get-ChildItem $root -Recurse -Depth 4 -Filter 'project-ref' -File -ErrorAction SilentlyContinue |
            Where-Object {
                # Structural check rather than a wildcard: a file merely NAMED
                # project-ref elsewhere in the tree is not a Supabase link.
                (Split-Path $_.DirectoryName -Leaf) -eq '.temp' -and
                (Split-Path (Split-Path $_.DirectoryName -Parent) -Leaf) -eq 'supabase'
            } |
            ForEach-Object {
                $ref = (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue)
                if (-not $ref) { return }
                $ref = $ref.Trim()

                # project-ref -> .temp -> supabase -> the project folder
                $projectDir = Split-Path (Split-Path (Split-Path $_.FullName -Parent) -Parent) -Parent
                $relative = if ($projectDir.Length -gt $rootLength) {
                    $projectDir.Substring($rootLength)
                } else { Split-Path $projectDir -Leaf }

                if (-not $byRef.ContainsKey($ref)) { $byRef[$ref] = @() }
                $byRef[$ref] += $relative
            }
    }

    $index.PSObject.Properties | ForEach-Object {
        $folders = @(if ($byRef.ContainsKey($_.Name)) { $byRef[$_.Name] } else { @() })
        $entry = [pscustomobject]@{
            Compte   = Get-CtxProp $_.Value 'key'
            Projet   = Get-CtxProp $_.Value 'name'
            Env      = Get-CtxProp $_.Value 'env'
            Partage  = ($folders.Count -gt 1)
            Dossiers = $folders
            Ref      = $_.Name
            Source   = Get-CtxProp $_.Value 'envSource'
        }
        $entry.PSObject.TypeNames.Insert(0, 'DevContext.SupabaseMapEntry')
        $entry
    } | Sort-Object Compte, Projet
}

# Layout lives entirely in DevContext.format.ps1xml.
#
# An Update-TypeData -DefaultDisplayPropertySet used to sit here as a fallback.
# It did the opposite of its intent: PSStandardMembers takes precedence over a
# format file, so the table view was loaded and then ignored, and ctx-sb kept
# printing one object per paragraph. Two mechanisms for one job, the weaker one
# winning silently.

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
      le preflight d'un projet, qui voyait 3 bases sans jamais voir sa production.
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

# ---------------------------------------------------------------------------
# Production guard — pure decision, no I/O
# ---------------------------------------------------------------------------

# Sub-commands that destroy data. No legitimate use against a production
# project, in any scenario -- which is what makes refusing them cost nothing.
$script:GuardDestructive = @('db reset')

# Sub-commands that ARE legitimate in production, but only from the repo's
# default branch. Pushing migrations from a side branch is how a schema goes
# backwards: on 13 Aug 2026 a worktree carried 19 migrations against 22 on main.
$script:GuardBranchBound = @('db push', 'migration repair', 'migration up')

function Get-CtxSupabasePaires {
    <#
      Every pair of ADJACENT non-option words, lowercased.

      The obvious implementation -- take the first two non-option words -- was
      wrong, and an audit on 15 Aug 2026 proved it in one line:

          supabase db reset --linked              refused
          supabase --workdir . db reset --linked  went straight through

      It assumed every option is a lone boolean. The Supabase CLI has six global
      options that take a SEPARATE value (--workdir, --profile, --network-id,
      --dns-resolver, --agent, -o/--output), and cobra accepts global flags
      BEFORE the command. The value then became the first word and shifted the
      window one place to the right.

      Anchoring on "the first word that is a known root command" would have
      fixed those six and broken on `--profile db db reset`, where a flag value
      imitates a command. Looking at every adjacent pair has no such blind spot:
      a guarded pair is present or it is not.

      The trade is over-blocking -- a command carrying "db" and "reset" as
      adjacent VALUES would be refused. That has no realistic form, and on a
      production project a false refusal costs one override while a false pass
      costs the database.
    #>
    param([string[]]$Arguments = @())

    $mots = @(
        $Arguments |
            Where-Object { $_ -and -not "$_".StartsWith('-') } |
            ForEach-Object { "$_".ToLowerInvariant() }
    )
    for ($i = 0; $i -lt $mots.Count - 1; $i++) { "$($mots[$i]) $($mots[$i + 1])" }
}

function Get-CtxArgumentsBruts {
    <#
      Restitue la ligne de commande TELLE QU'ELLE A ETE TAPEE.

      PowerShell analyse les arguments d'une FONCTION autrement que ceux d'un
      programme externe : `--json a,b,c` y devient un TABLEAU de trois elements,
      et non la chaine 'a,b,c'. Splatte tel quel vers la CLI, cela donne
      `--json a b c`, et `gh` repond « unknown command "status" ».

      Mesure le 16 aout 2026 sur la commande qui ouvrait justement la PR de cette
      version. Les listes separees par des virgules sont partout dans ces CLI :
      `gh ... --json a,b`, `gh pr create --label a,b`, `gh issue list --assignee`.

      Les shims n'ont pas ce probleme : ils sont atteints comme des programmes
      externes. C'est le prix de l'alias, et il se paie ici, une seule fois pour
      les trois.
    #>
    param([object[]]$Arguments = @())

    @($Arguments | ForEach-Object {
            if ($_ -is [System.Array]) { (@($_) | ForEach-Object { "$_" }) -join ',' }
            else { "$_" }
        })
}

function Get-CtxArgumentValeur {
    <#
      Reads the value of a flag, in either spelling: `--nom valeur` and
      `--nom=valeur`. Returns nothing when the flag is absent.
    #>
    param(
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$Nom
    )
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = "$($Arguments[$i])"
        if ($a -eq "--$Nom") {
            if ($i + 1 -lt $Arguments.Count) { return "$($Arguments[$i + 1])" }
            return
        }
        if ($a.StartsWith("--$Nom=")) { return $a.Substring($Nom.Length + 3) }
    }
}

function Get-CtxSupabaseRefDepuisUrl {
    <#
      Recovers the project ref from a Postgres connection string, in the two
      shapes Supabase issues:

        direct  postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres
        pooler  postgresql://postgres.<ref>:<pwd>@aws-0-....pooler.supabase.com:5432/postgres

      Returns nothing for anything else, and "nothing" is a meaningful answer:
      the caller then knows it cannot tell what this command is aimed at.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Url)

    if (-not $Url) { return }
    if ($Url -match '@db\.([a-z0-9]{20})\.supabase\.') { return $Matches[1] }
    if ($Url -match '://postgres\.([a-z0-9]{20})[:@]')  { return $Matches[1] }
}

# Les options de la CLI Supabase qui prennent leur valeur en argument SEPARE.
# Relevees sur `supabase <commande> --help`, version 2.109.1, le 24 aout 2026.
#
# Le sens de l'erreur n'est pas symetrique, et c'est lui qui decide du contenu
# de cette liste. En OUBLIER une, c'est laisser sa valeur passer pour un
# drapeau : `--profile --local` ferait alors croire a une cible locale alors que
# la commande part sur la cible par defaut. En ajouter une de TROP, c'est avaler
# le mot suivant, donc rater un `--local` et refuser une commande inoffensive.
#
# La premiere erreur coute une base, la seconde une derogation. En cas de
# doute : ajouter.
$script:GuardFlagsAValeur = @(
    'agent', 'completions', 'db-url', 'dns-resolver', 'last', 'log-level',
    'network-id', 'output', 'output-format', 'password', 'profile',
    'sql-paths', 'version', 'workdir'
)
$script:GuardFlagsCourtsAValeur = @('o', 'p')

# Les trois drapeaux qui designent la base visee.
$script:GuardFlagsCible = @('local', 'linked', 'db-url')

# Les ecritures booleennes que cobra accepte. Tout le reste lui est une erreur
# -- donc, pour nous, une ligne dont on ne sait pas ce qu'elle vise.
$script:GuardBoolVrai = @('1', 't', 'T', 'TRUE', 'true', 'True')
$script:GuardBoolFaux = @('0', 'f', 'F', 'FALSE', 'false', 'False')

function Get-CtxSupabaseCible {
    <#
      Quelle base cette ligne de commande designe-t-elle EXPLICITEMENT ?

        'locale'   --local, et rien d'autre
        'liee'     --linked, et rien d'autre
        'url'      --db-url, et rien d'autre
        'aucune'   aucun drapeau de cible : la CLI appliquera son defaut
        'ambigue'  plusieurs cibles a la fois, ou une ecriture illisible

      Rend un ETAT, jamais un verdict : l'appelant decide ce qu'il en fait.
      Meme separation que Get-CtxVerdictDossier et Test-CtxDoctor*.

      POURQUOI SAUTER LA VALEUR DES OPTIONS

      `db reset --profile --local` ne porte AUCUNE cible locale : cobra consomme
      '--local' comme valeur de --profile, et la commande part sur la cible par
      defaut. Lire les mots un a un y verrait un `--local` et laisserait passer.
      C'est exactement la classe de defaut corrigee le 15 aout 2026 dans
      Get-CtxSupabasePaires, ou la valeur d'un flag global decalait la fenetre
      de detection.

      POURQUOI `--local=false` NE COMPTE PAS

      Cobra accepte l'ecriture `--local=false`, qui veut dire le contraire du
      drapeau nu. La compter comme une cible locale serait le seul faux
      laissez-passer possible ici. Les deux jeux d'ecritures sont donc lus
      litteralement, et tout ce qui n'est ni l'un ni l'autre rend 'ambigue'.

      MESURE, CLI 2.109.1, LE 24 AOUT 2026

      Sur `db reset`, `db push` et `migration up`, la CLI declare elle-meme
      [db-url linked local] mutuellement exclusifs et refuse la combinaison
      AVANT d'executer quoi que ce soit :

          if any flags in the group [db-url linked local] are set
          none of the others can be; [db-url linked] were all set

      'ambigue' ne devrait donc jamais atteindre la vraie CLI. C'est une raison
      de PLUS de ne pas s'y fier : cette exclusion appartient a une version, pas
      au contrat. Elle confirme ici un choix pris pour une autre raison -- ne
      jamais laisser passer une ligne dont la cible n'est pas certaine.
    #>
    param([string[]]$Arguments = @())

    $cibles  = [System.Collections.Generic.List[string]]::new()
    $inconnu = $false

    $i = 0
    while ($i -lt $Arguments.Count) {
        $a = "$($Arguments[$i])"

        if ($a.StartsWith('--')) {
            $eg     = $a.IndexOf('=')
            $nom    = if ($eg -ge 0) { $a.Substring(2, $eg - 2) } else { $a.Substring(2) }
            $valeur = if ($eg -ge 0) { $a.Substring($eg + 1) } else { $null }

            # -cin et non -in : cobra distingue la casse, et `--LOCAL` lui est
            # un drapeau inconnu. Le lire comme `--local` serait inventer une
            # cible locale sur une ligne que la CLI refusera.
            if ($nom -cin $script:GuardFlagsCible) {
                if ($nom -eq 'db-url') {
                    $cibles.Add($nom)
                    if ($eg -lt 0) { $i++ }   # sa valeur suit en argument separe
                }
                elseif ($eg -lt 0)                            { $cibles.Add($nom) }
                elseif ($valeur -cin $script:GuardBoolVrai)   { $cibles.Add($nom) }
                elseif ($valeur -cin $script:GuardBoolFaux)   { }   # explicitement desactive
                else                                          { $inconnu = $true }

                $i++
                continue
            }

            if ($eg -lt 0 -and $nom -cin $script:GuardFlagsAValeur) { $i += 2; continue }
            $i++
            continue
        }

        if ($a.Length -eq 2 -and $a[0] -eq '-' -and
            $a.Substring(1) -cin $script:GuardFlagsCourtsAValeur) { $i += 2; continue }

        $i++
    }

    if ($inconnu) { return 'ambigue' }

    $distinctes = @($cibles | Sort-Object -Unique)
    if ($distinctes.Count -eq 0) { return 'aucune' }
    if ($distinctes.Count -gt 1) { return 'ambigue' }

    switch ($distinctes[0]) {
        'local'  { 'locale' }
        'linked' { 'liee' }
        'db-url' { 'url' }
    }
}

function Test-CtxSupabaseGuard {
    <#
      Pure decision. No network, no vault, no filesystem, no git. Everything it
      needs is passed in -- which is what makes it testable on its own, and what
      lets the shim be the only place that gathers state.

      Every uncertain path returns Allowed. A guard that breaks when it
      hesitates is a guard that gets uninstalled within the week.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Arguments = @(),
        [AllowNull()][string]$Environment,
        [AllowNull()][string]$CurrentBranch,
        [AllowNull()][string]$DefaultBranch,
        [switch]$Override,
        # Vrai quand l'index du contexte contient au moins un projet marque
        # 'prod'. Sert au seul cas ou ce garde-fou se ferme par defaut : voir
        # plus bas, --db-url.
        [switch]$IndexContientProd
    )

    $pass = { param($rule) [pscustomobject]@{ Allowed = $true; Rule = $rule; Reason = '' } }

    $paires      = @(Get-CtxSupabasePaires $Arguments)
    $destructive = @($paires | Where-Object { $_ -in $script:GuardDestructive })   | Select-Object -First 1
    $branchBound = @($paires | Where-Object { $_ -in $script:GuardBranchBound })   | Select-Object -First 1
    $sub         = if ($destructive) { $destructive } else { $branchBound }

    # --- cible redirigee -----------------------------------------------------
    #
    # LE SEUL ENDROIT OU CE GARDE-FOU SE FERME PAR DEFAUT.
    #
    # Il deduit la base visee du DOSSIER. `--db-url` la redirige ailleurs, et la
    # CLI obeit au flag. Une commande destructrice copiee d'un runbook et lancee
    # depuis un dossier de developpement detruisait donc la production sans un
    # mot -- exactement la classe d'erreur que ce module existe pour arreter.
    #
    # Quand on sait lire le ref de l'URL, on juge dessus. Quand on ne sait pas,
    # et qu'une production existe quelque part dans l'index, on refuse : ici,
    # « je ne sais pas » ne peut pas valoir « vas-y ».
    if ($destructive -or $branchBound) {
        $dbUrl = Get-CtxArgumentValeur -Arguments $Arguments -Nom 'db-url'
        if ($dbUrl -and -not $Override) {
            $refCible = Get-CtxSupabaseRefDepuisUrl $dbUrl
            if (-not $refCible -and $IndexContientProd) {
                return [pscustomobject]@{
                    Allowed = $false
                    Rule    = 'cible-indeterminee'
                    Reason  = (T 'garde.raison.dbUrl' $sub)
                }
            }
        }
    }

    if ($Environment -ne 'prod') { return (& $pass 'not-production') }
    if (-not $destructive -and -not $branchBound) { return (& $pass 'not-guarded') }

    if ($Override) { return (& $pass 'override') }

    # --- cible explicitement LOCALE -----------------------------------------
    #
    # LE FAUX POSITIF LE PLUS COUTEUX DU GARDE-FOU, mesure le 24 aout 2026.
    #
    # `db reset`, `db push` et `migration up` visent la base LOCALE par defaut ;
    # c'est `--linked` qui est l'opt-in vers le distant. La CLI le dit
    # elle-meme : « Resets the local database to current migrations. » Ce
    # garde-fou ne lisait que `--db-url`, jamais `--local`, et refusait donc
    # `db reset --local` dans tout dossier lie a une production -- sur toutes
    # les branches, sans condition.
    #
    # Quatre refus mesures, un seul vrai positif. Un garde-fou qui casse la ou
    # il est CERTAIN que la commande est inoffensive s'use exactement comme
    # celui qui casse quand il hesite : l'un se contourne par `psql`, l'autre
    # par DEVCTX_ALLOW_PROD=1 -- qui desarme aussi les vrais positifs.
    #
    # La regle est CONJONCTIVE, et ce n'est pas un detail : un simple
    # `if (--local) { passe }` se contourne par `db reset --local --db-url <prod>`.
    # Get-CtxSupabaseCible rend 'ambigue' des qu'une seconde cible apparait, et
    # 'ambigue' ne passe pas.
    #
    # Jugee AVANT la branche : appliquer une migration a sa base locale depuis
    # une branche laterale est le travail quotidien, pas une faute.
    if ((Get-CtxSupabaseCible $Arguments) -eq 'locale') { return (& $pass 'cible-locale') }

    if ($destructive) {
        return [pscustomobject]@{
            Allowed = $false
            Rule    = 'db-reset-prod'
            Reason  = (T 'garde.raison.reset' $sub)
        }
    }

    # Branch-bound from here. Any doubt lets the command through.
    if (-not $CurrentBranch -or -not $DefaultBranch) { return (& $pass 'branch-unknown') }
    if ($CurrentBranch -eq $DefaultBranch)           { return (& $pass 'default-branch') }

    [pscustomobject]@{
        Allowed = $false
        Rule    = 'branch-mismatch'
        Reason  = (T 'garde.raison.branche' $sub $CurrentBranch $DefaultBranch)
    }
}

function Get-CtxBranchesPour {
    <#
      La branche courante et la branche par defaut DU DOSSIER VISE.

      « Du dossier vise » est la correction du 16 aout 2026. Ces deux valeurs
      etaient lues la ou la commande etait TAPEE, alors que `--workdir` peut
      designer un tout autre depot : le garde-fou jugeait donc la branche d'un
      depot et la base d'un autre. Depuis un depot pose sur sa branche par
      defaut, un `db push` vers une production restee sur une branche laterale
      passait sans un mot.

      Toute incertitude rend $null, et $null vaut « laisse passer » : on ne
      bloque jamais sur une supposition.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Dossier)

    $vide = [pscustomobject]@{ Courante = $null; Defaut = $null }
    if (-not $Dossier -or -not (Test-Path -LiteralPath $Dossier)) { return $vide }

    # Le drapeau, et non un Pop-Location dans un finally inconditionnel : si le
    # Push echoue, ce finally depilerait l'emplacement de QUELQU'UN D'AUTRE et
    # laisserait l'appelant ailleurs qu'il ne croit.
    $pousse = $false
    try {
        Push-Location -LiteralPath $Dossier -ErrorAction Stop
        $pousse = $true

        $courante = git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or $courante -eq 'HEAD') { $courante = $null }

        $defaut = git symbolic-ref --short refs/remotes/origin/HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $defaut) {
            # Retirer le prefixe du remote, et LUI SEUL. Un `-split '/'` suivi de
            # [-1] tronquait une branche hierarchique : avec
            # origin/HEAD -> origin/release/main, la branche par defaut devenait
            # 'main', et un developpeur sur une branche locale nommee 'main'
            # voyait son `db push` vers la production accepte.
            $defaut = $defaut -replace '^origin/', ''
        }
        else {
            $defaut = $null
            foreach ($candidat in 'main', 'master') {
                git show-ref --verify --quiet "refs/heads/$candidat" 2>$null
                if ($LASTEXITCODE -eq 0) { $defaut = $candidat; break }
            }
        }

        [pscustomobject]@{ Courante = $courante; Defaut = $defaut }
    }
    catch { $vide }
    finally { if ($pousse) { Pop-Location } }
}

function Resolve-CtxSupabaseVerdict {
    <#
      RASSEMBLE les faits, puis appelle la decision pure. C'est la moitie
      « gathering » du garde-fou : disque, index, git, environnement.

      ELLE VIT DANS LE MODULE, ET NON DANS LE SHIM, DEPUIS LE 16 AOUT 2026.
      Il y a deux appelants, et une regle en deux exemplaires derive :

        - le shim du PATH couvre tous les shells -- git-bash, npm, un agent ;
        - l'alias PowerShell couvre le seul shell ou il passe AVANT le shim.

      Jusqu'a cette date l'alias ne consultait pas le garde-fou du tout. Comme
      `work` importe le module, c'etait le cas de TOUS les terminaux de l'auteur.
      Meme motif que l'incident du fichier de format le 13 aout 2026 : deux
      mecanismes pour un seul travail, le plus faible gagnant en silence.

      Rend $null quand il n'y a rien a juger -- hors contexte, hors projet lie,
      aucune production en vue. « Rien a juger » vaut « laisse passer » : chaque
      appelant delegue alors au binaire reel.
    #>
    param(
        [string[]]$Arguments = @(),
        # Le dossier depuis lequel la commande est tapee. Parametre et non
        # $PWD lu ici : l'appelant sait ou il est, cette fonction ne le suppose
        # pas -- et un test peut donc l'exercer sans deplacer le shell.
        [string]$Path
    )

    # --workdir redirige la CLI vers un AUTRE projet. Le garde-fou doit juger la
    # cible reelle, pas le dossier depuis lequel on tape :
    #   supabase --workdir F:\...\projet-de-prod db push
    # partait de n'importe ou et travaillait sur la production.
    $dossier = Get-CtxArgumentValeur -Arguments $Arguments -Nom 'workdir'
    if (-not $dossier) {
        $dossier = if ($Path) { $Path } else { (Get-Location).Path }
    }

    # LE DOSSIER D'ABORD, la session seulement en secours.
    #
    # Lire $env:DEVCTX en priorite interrogeait l'index du MAUVAIS contexte
    # quand session et dossier divergent -- l'etat que `ctx` qualifie justement
    # de NO-GO -- n'y trouvait pas le projet, et concluait « pas de production ».
    $contextes = @()
    $manifeste = Resolve-DevContextForPath -Path $dossier
    if ($manifeste) { $contextes += Get-CtxProp $manifeste 'name' }
    if ($env:DEVCTX -and $env:DEVCTX -notin $contextes) { $contextes += $env:DEVCTX }
    if ($contextes.Count -eq 0) { return }

    $ref = Resolve-CtxSupabaseRef -Path $dossier
    if (-not $ref) { return }

    # Le verdict le plus restrictif l'emporte : si l'un des deux index connait ce
    # projet comme une production, c'en est une.
    $environment = $null
    $contexte    = $contextes[0]
    foreach ($c in $contextes) {
        $e = Get-CtxSupabaseEnv -Ref $ref -ContextName $c
        if ($e -eq 'prod') { $environment = 'prod'; $contexte = $c; break }
        if ($e -and -not $environment) { $environment = $e; $contexte = $c }
    }

    # L'index contient-il une production, quelque part ? Sert au seul cas ou le
    # garde-fou se ferme par defaut : un --db-url dont on ne sait pas lire la cible.
    $indexProd = $false
    foreach ($c in $contextes) {
        $p = Get-CtxSupabaseIndexPath $c
        if ($p -and (Test-Path $p)) {
            $brut = Get-Content $p -Raw -ErrorAction SilentlyContinue
            if ($brut -match '"env"\s*:\s*"prod"') { $indexProd = $true; break }
        }
    }

    if ($environment -ne 'prod' -and -not $indexProd) { return }

    $branches = Get-CtxBranchesPour -Dossier $dossier

    $verdict = Test-CtxSupabaseGuard -Arguments $Arguments -Environment $environment `
        -CurrentBranch $branches.Courante -DefaultBranch $branches.Defaut `
        -Override:($env:DEVCTX_ALLOW_PROD -eq '1') -IndexContientProd:$indexProd

    $nom = $null
    $chemin = Get-CtxSupabaseIndexPath $contexte
    if ($chemin -and (Test-Path $chemin)) {
        $index  = Get-Content $chemin -Raw | ConvertFrom-Json
        $entree = $index.PSObject.Properties | Where-Object { $_.Name -eq $ref } | Select-Object -First 1
        if ($entree) { $nom = Get-CtxProp $entree.Value 'name' }
    }

    [pscustomobject]@{ Verdict = $verdict; Projet = $nom }
}

function Write-CtxGardeRefus {
    <#
      Le bloc de refus, ecrit UNE seule fois pour les deux appelants.

      Rien ici n'imprime une variable d'environnement, un jeton, ni les
      arguments de la commande : un refus finit dans les journaux et se colle
      dans les conversations, et un `--db-url` porte un mot de passe.
    #>
    param(
        [Parameter(Mandatory)]$Verdict,
        [AllowNull()][AllowEmptyString()][string]$Projet
    )

    if (-not $Projet) { $Projet = T 'garde.nomInconnu' }

    Write-Host ''
    Write-Host "  $(T 'garde.refuse')" -ForegroundColor Red
    Write-Host ''
    Write-Host "    $(T 'garde.base' $Projet)" -ForegroundColor Yellow
    Write-Host "    $(T 'garde.raison' $Verdict.Reason)"
    Write-Host ''
    Write-Host "    $(T 'garde.derogation')" -ForegroundColor DarkGray
    Write-Host '      $env:DEVCTX_ALLOW_PROD = 1' -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil1')" -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil2')" -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------

function Invoke-DevSupabase {
    # PAS DE BLOC param(), ET C'EST PORTEUR. Avec [CmdletBinding()], PowerShell
    # reclame toute option courte qui prefixe un parametre commun : `supabase -o
    # env` echouerait sur « le nom de parametre 'o' est ambigu ». Meme piege que
    # celui documente en tete de shims/supabase.ps1, et il vaut pour une fonction
    # autant que pour un script. Releve le 16 aout 2026 sur `gh api -i user`,
    # corrige ici en meme temps : reparer une classe de defaut sur l'occurrence
    # rencontree seulement, c'est la laisser vivre chez son jumeau.
    # @() OBLIGATOIRE. Une fonction ne RENVOIE pas un tableau : PowerShell le
    # deroule sur le flux de sortie, donc un seul argument revient en CHAINE --
    # et `& $exe @arguments` splatte alors ses CARACTERES. Mesure le 18 aout
    # 2026 : `vercel whoami` partait en `w h o a m i`.
    $arguments = @(Get-CtxArgumentsBruts $args)

    # LE GARDE-FOU D'ABORD, avant meme d'ouvrir le coffre.
    #
    # Cet alias precede le shim du PATH dans toute session PowerShell ayant
    # importe le module. Jusqu'au 16 aout 2026 il ne consultait pas le garde-fou :
    # mesure sur un leurre, `supabase db reset --linked` sur un projet marque
    # prod, depuis un dossier lie, sur une branche laterale -- binaire appele,
    # code 42, aucun refus.
    #
    # Une levee du rassemblement DELEGUE, comme dans le shim : un garde-fou qui
    # casse quand il hesite est desinstalle dans la semaine.
    $decision = $null
    try { $decision = Resolve-CtxSupabaseVerdict -Arguments $arguments }
    catch { $decision = $null }

    if ($decision -and $decision.Verdict -and -not $decision.Verdict.Allowed) {
        Write-CtxGardeRefus -Verdict $decision.Verdict -Projet $decision.Projet
        # `throw` et non un simple affichage : $? doit rendre faux et un script
        # doit s'arreter. Le shim, lui, sort en 1 -- meme resultat pour son
        # appelant.
        throw (T 'garde.refuseAlias')
    }

    $exe = Get-CtxSupabaseExe

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
                        Write-Host "  $(T 'sb.projetActif' $entry.Value.name $entry.Value.key)" -ForegroundColor DarkGray
                    }
                }
                else {
                    Write-Warning "Projet '$ref' absent de l'index Supabase. Lance 'sb-index'."
                }
            }
            else {
                Write-Warning (T 'sb.sansIndexAvert' $env:DEVCTX)
            }
        }
    }

    if ($token) {
        $previous = $env:SUPABASE_ACCESS_TOKEN
        try {
            Set-CtxSupabaseToken $token
            & $exe @arguments
        }
        finally { Set-CtxSupabaseToken $previous }
    }
    else {
        & $exe @arguments
    }
}

# ---------------------------------------------------------------------------
# ctx-new — creation d'un contexte
# ---------------------------------------------------------------------------

function New-DevContext {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        # Etiquette lisible, affichee par `ctx`. Obligatoire jusqu'au 15 aout
        # 2026, ce qui faisait echouer la commande que le message d'accueil
        # proposait lui-meme : « missing mandatory parameters: Label ». Un
        # premier pas qui ne marche pas est pire qu'un premier pas absent.
        [string]$Label,
        [Parameter(Mandatory)][string]$Email,
        [string]$Root,
        # Le defaut valait le nom de l'auteur du module. Tout contexte cree sur
        # une autre machine aurait donc signe les commits de son proprietaire
        # avec le nom de quelqu'un d'autre -- pas une preference discutable,
        # une faute. On reprend ce que git connait deja de l'utilisateur.
        [string]$GitUserName,
        [string]$GithubOrg,
        # Login GitHub attendu pour ce contexte. C'est lui que `ctx` compare au
        # compte reellement actif : sans valeur attendue, aucune verification
        # n'est possible, seulement un affichage.
        [string]$GithubLogin,
        [string]$VercelScope,
        [string]$ChromeProfile,
        # Cree le contexte sans generer de cle SSH. Pour un script, une CI, ou un
        # agent -- tout appelant dont l'entree standard est redirigee et qui ne
        # pourra donc jamais repondre a la demande de passphrase.
        [switch]$NoKey
    )

    if ($Name -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw (T 'new.nomInvalide')
    }

    if (-not $Label) { $Label = $Name }

    if (-not $GitUserName) {
        $GitUserName = (git config --global user.name 2>$null)
        if (-not $GitUserName) { $GitUserName = $Name }
    }

    Test-CtxVault
    $ctx = Get-CtxPath $Name
    if (Test-Path $ctx) { throw (T 'new.existeDeja' $Name $ctx) }

    # Le defaut visait 'F:\PROJECTS\Clients\<nom>' -- le lecteur de l'auteur. Sur
    # toute autre machine, la creation echouait sur un volume absent, ou pire,
    # reussissait sur un F: qui appartenait a autre chose.
    if (-not $Root) { $Root = [System.IO.Path]::Combine($HOME, 'dev', $Name) }

    # Deux contextes qui se recouvrent rendent la resolution par chemin
    # ambigue — donc le garde-fou incertain, donc inutile.
    $newRoot = Get-NormalizedRoot $Root
    foreach ($m in Get-CtxManifests) {
        $existing = Get-CtxProp $m 'root'
        if (-not $existing) { continue }
        $existingRoot = Get-NormalizedRoot $existing
        if ($newRoot -eq $existingRoot) {
            throw (T 'new.racinePrise' $Root $m.name)
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
    #
    # Interactif volontairement : une passphrase vide sur une cle qui donne acces
    # au depot d'un client, ce n'est pas une bonne idee. Utiliser ssh-agent ensuite.
    #
    # Mais interactif ne doit pas vouloir dire BLOQUANT. Quand l'entree standard
    # est redirigee -- un script, une CI, un agent IA, `pwsh -Command` --,
    # ssh-keygen attend une passphrase que personne ne tapera jamais et la
    # commande ne rend plus la main. Mesure le 15 aout 2026 : le parcours de
    # premiere installation s'arretait la, sans un message, pendant cinq minutes
    # avant qu'un delai ne l'interrompe.
    #
    # On refuse donc explicitement plutot que d'attendre. Une commande qui dit
    # ce qui lui manque vaut mieux qu'une commande qui semble travailler.
    $keyPath = [System.IO.Path]::Combine($ctx, 'ssh', 'id_ed25519')
    if (-not (Test-Path $keyPath) -and -not $NoKey) {
        if ([Console]::IsInputRedirected) {
            throw ("Generation de cle SSH impossible : l'entree standard est redirigee, " +
                "et ssh-keygen attendrait une passphrase indefiniment.`n" +
                "  - dans un terminal interactif : relancer la meme commande`n" +
                "  - dans un script ou une CI    : ajouter -NoKey, puis generer la cle plus tard`n" +
                "Le contexte '$Name' a bien ete cree : $ctx")
        }
        Write-Host "  $(T 'new.cleGeneration')" -ForegroundColor Cyan
        ssh-keygen -t ed25519 -C $Email -f $keyPath
    }
    elseif ($NoKey -and -not (Test-Path $keyPath)) {
        Write-Host "  $(T 'new.cleSansGeneration')" -ForegroundColor Yellow
        Write-Host "    $(T 'new.cleCommande' $Email $keyPath)" -ForegroundColor DarkGray
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
    #
    # Meme regle que pour la cle SSH : demander quelque chose a une entree
    # redirigee, c'est attendre pour toujours. On saute la saisie et on dit
    # comment la reprendre, plutot que de bloquer un script sur un prompt que
    # personne ne voit.
    if ([Console]::IsInputRedirected) {
        Write-Host ""
        Write-Host "  $(T 'new.jetonsIgnores')" -ForegroundColor Yellow
        Write-Host "  $(T 'new.jetonsPlusTard')" -ForegroundColor DarkGray
        Write-Host "    $(T 'new.jetonsCommande' $Name)" -ForegroundColor DarkGray
        Write-Host "    $(T 'new.jetonsCles' ($script:SecretMap.Keys -join ', '))" -ForegroundColor DarkGray
    }
    else {
        Write-Host ""
        Write-Host "  $(T 'new.jetonsSaisie')" -ForegroundColor Cyan
        foreach ($key in $script:SecretMap.Keys) {
            $secure = Read-Host "    $key" -AsSecureString
            if ($secure.Length -gt 0) { Set-CtxSecret -Name $Name -Key $key -Value $secure }
        }
    }

    Write-Host ""
    Write-Host "  $(T 'new.cree' $Label)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  $(T 'new.resteAFaire')" -ForegroundColor Yellow
    # La liste ne doit designer que ce qui existe. Avec -NoKey elle envoyait
    # chercher une cle publique jamais generee -- une impasse de plus, de la
    # meme famille que celles corrigees plus haut.
    if (Test-Path -LiteralPath "$keyPath.pub") {
        Write-Host "    $(T 'new.etape1' $Email)"
        Write-Host "       $keyPath.pub"
    }
    else {
        Write-Host "    $(T 'new.etape1Sans' $Email)" -ForegroundColor Yellow
        Write-Host "       $(T 'new.cleCommande' $Email $keyPath)" -ForegroundColor Yellow
    }
    Write-Host "    $(T 'new.etape2' $Name (Join-Path $ctx 'gh'))"
    Write-Host "    $(T 'new.etape3')"
    Write-Host "    $(T 'new.etape4' $Name)"
    if (-not $GithubLogin) {
        Write-Host "    $(T 'new.etape5a')" -ForegroundColor Yellow
        Write-Host "       $(T 'new.etape5b')" -ForegroundColor Yellow
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
    Write-Host "  $(T 'end.titre' (Get-CtxProp $m 'label' $Name) (Get-CtxProp $m 'email'))" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $(T 'end.avantPurge')" -ForegroundColor Yellow
    Write-Host "    $(T 'end.item1')"
    Write-Host "    $(T 'end.item2')"
    Write-Host "    $(T 'end.item3')"
    Write-Host "    $(T 'end.item4')"
    Write-Host "    $(T 'end.item5')"
    Write-Host "          $(T 'end.item5Urls')"
    Write-Host "    $(T 'end.item6')"
    Write-Host "    $(T 'end.item7')"
    Write-Host ""

    if (-not $Purge) {
        Write-Host "  $(T 'end.relancer')" -ForegroundColor DarkGray
        return
    }

    if ($env:DEVCTX -eq $Name) {
        throw (T 'end.actifIci' $Name)
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Purger secrets, contexte, entrees git et ssh')) { return }

    foreach ($key in $script:SecretMap.Keys) {
        Remove-Secret -Vault $script:VaultName -Name "devctx/$Name/$key" -ErrorAction SilentlyContinue
    }
    if (Test-Path $ctx) { Remove-Item $ctx -Recurse -Force }

    Write-Host "  $(T 'end.supprime')" -ForegroundColor Green
    Write-Host "  $(T 'end.sshManuel1' $Name $script:SshConfig)" -ForegroundColor Yellow
    Write-Host "  $(T 'end.sshManuel2' $script:GitConfig)" -ForegroundColor Yellow
    Write-Host "  $(T 'end.projetIntact' (Get-CtxProp $m 'root'))" -ForegroundColor DarkGray
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
    if ($env:VERCEL_TOKEN) { return T 'vercel.token' }
    if ($env:DEVCTX_VERCEL_CONFIG -and
        (Test-Path (Join-Path $env:DEVCTX_VERCEL_CONFIG 'auth.json'))) {
        return T 'vercel.session'
    }
    T 'vercel.aucune'
}

function Get-CtxVerdictVercelSession {
    <#
      PURE. Ce dossier est-il lie a un projet Vercel sans session de contexte ?

        'sansProjet'   pas de .vercel/project.json : il n'y a rien a dire
        'sansSession'  un projet Vercel, un proprietaire, et aucune session
                       dediee -- les commandes partiront sur la session GLOBALE
        'ok'           rien ne cloche

      EXTRAIT DE src/Doctor.ps1 LE 24 AOUT 2026. La regle y etait ecrite en
      ligne, donc invisible a `ctx` : celui-ci affichait « vercel : aucune
      session » et concluait GO pendant que `doctor`, sur le meme dossier,
      rendait PROBLEME. Le meme defaut que l'identite git, a un jour d'ecart, et
      le meme correctif : une seule decision, deux lecteurs.
    #>
    [CmdletBinding()]
    param(
        [switch]$ADossierVercel,
        [AllowNull()][AllowEmptyString()][string]$Proprietaire,
        [AllowNull()][AllowEmptyString()][string]$ConfigSession
    )

    if (-not $ADossierVercel) { return 'sansProjet' }
    # Sans proprietaire, aucune session dediee n'est attendue : ce dossier
    # n'appartient a personne, et le dire serait reprocher une absence normale.
    if ([string]::IsNullOrWhiteSpace($Proprietaire)) { return 'ok' }
    if ([string]::IsNullOrWhiteSpace($ConfigSession)) { return 'sansSession' }
    'ok'
}

function Get-CtxVerdictRemoteSansContexte {
    <#
      PURE. Dans un dossier que PERSONNE ne gouverne, par ou part un push ?

        'pasDepot'      aucune URL de push : il n'y a rien a dire
        'ssh'           URL SSH : l'acces ne depend d'aucun assistant HTTPS
        'httpsAssiste'  HTTPS, et un assistant repondra -- donc un compte
                        decide ailleurs que par ce dossier
        'httpsNu'       HTTPS, et rien ne repondra : l'invite d'identifiants
                        bloque un shell non interactif

      POURQUOI CET AXE EXISTE, LE 24 AOUT 2026

      La remarque « aucun contexte ne gouverne ce dossier » ne disait que la
      moitie la plus inoffensive : l'identite retombe sur le ~/.gitconfig
      global, ce qui est souvent correct. La moitie tue est le REMOTE. Sans
      contexte, pas de regle `insteadOf`, donc pas de reecriture vers la cle SSH
      du contexte -- et un push HTTPS s'authentifie par l'assistant GLOBAL,
      c'est-a-dire sous le compte qui y dort.

      Mesure du 24 aout 2026 : `git config --get-all credential.helper` ne rend
      RIEN sur cette machine, alors qu'un assistant existe bel et bien sous
      `credential.https://github.com.helper`. La lecture correcte est
      `--get-urlmatch`, la seule qui resout la portee par URL. C'est le
      gatherer qui la fait ; cette fonction-ci ne fait que decider.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$UrlPush,
        [switch]$AssistantIdentifiants
    )

    if ([string]::IsNullOrWhiteSpace($UrlPush)) { return 'pasDepot' }

    # Les deux ecritures SSH : ssh://hote/... et la forme scp git@hote:chemin.
    # Aucun '@' ne peut preceder le premier '/' d'une URL https://..., donc
    # cette seconde branche ne peut pas happer un remote HTTPS porteur d'un
    # login -- lequel reste bien un remote HTTPS, et le piege du 5 aout 2026.
    if ($UrlPush -match '^ssh://' -or $UrlPush -match '^[^/]+@[^/]+:') { return 'ssh' }

    if ($AssistantIdentifiants) { return 'httpsAssiste' }
    'httpsNu'
}

function Get-CtxOrigineConfigGit {
    <#
      PURE. Le FICHIER d'ou vient une valeur, dans une ligne de
      `git config --show-origin <cle>`.

      Le separateur est une TABULATION, et c'etait ecrit `-split '\s'` d'un cote,
      `-replace '\s.*$'` de l'autre : deux ecritures du meme decoupage, fragiles
      de la meme facon. Un chemin contenant une espace -- 'C:/Users/John
      Doe/.gitconfig', un nom d'utilisateur Windows tout a fait ordinaire --
      etait tronque a 'C:/Users/John', et le diagnostic designait alors un
      fichier qui n'existe pas.

      Mesure le 25 aout 2026 : le cas qui compte, lui, est sauf. git rend le
      config d'un depot en chemin RELATIF ('file:.git/config'), depuis la racine
      comme depuis un sous-dossier ; la detection d'une identite ecrite en dur ne
      pouvait donc pas se tromper de verdict. Ce qui se trompait etait le chemin
      AFFICHE -- envoyer quelqu'un corriger le mauvais fichier.

      Aucune machine de l'auteur n'a d'espace dans ces chemins. C'est
      exactement pourquoi ceci se corrige maintenant : le module est publie, et
      ce qui casse est ce qu'on n'est pas en position de voir.
    #>
    param([AllowNull()][string]$Ligne)

    if ([string]::IsNullOrWhiteSpace($Ligne)) { return '' }
    ($Ligne -split "`t")[0] -replace '^file:', ''
}

function Get-CtxVerdictGitIdentite {
    <#
      PURE. L'identite git effective de ce dossier est-elle celle du contexte
      qui le gouverne ?

        'horsContexte'  aucun contexte ne gouverne ce dossier : rien a comparer
        'sansEmail'     git ne resout aucun user.email ici
        'mauvaisEmail'  une autre adresse que celle du manifeste signera
        'emailEnDur'    la bonne adresse, mais posee a la main dans .git/config
        'accord'        la bonne adresse, par le mecanisme

      CE QUE CETTE FONCTION CORRIGE, LE 24 AOUT 2026

      `ctx doctor` jugeait deja cet axe. `ctx` -- la commande que le protocole
      traite comme un VERDICT, lancee a chaque debut de session -- se contentait
      de l'AFFICHER :

          Write-Host "  $(T 'ctx.git' (git config user.email))"

      Une ligne d'information au milieu d'un verdict. Resultat mesure le meme
      jour, dans le meme processus et sur le meme dossier : `ctx` rendait GO
      pendant que `ctx doctor` rendait PROBLEME. Un seul fait, deux verdicts,
      dont un faux.

      C'est la deuxieme fois. Le 19 aout 2026, Get-CtxVerdictDossier corrigeait
      exactement cette forme-la sur l'axe du proprietaire. La cause de fond est
      la meme : une regle ecrite a deux endroits finit toujours par diverger,
      et c'est celle qu'on croit qui ment.

      Et le piege attrape ici est nomme depuis longtemps dans la doctrine du
      projet -- un `user.email` en dur dans .git/config prime sur le includeIf.
      Le garde-fou quotidien ne le voyait pas.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$EmailAttendu,
        [AllowNull()][AllowEmptyString()][string]$EmailReel,
        [AllowNull()][AllowEmptyString()][string]$Origine
    )

    if ([string]::IsNullOrWhiteSpace($EmailAttendu)) { return 'horsContexte' }
    if ([string]::IsNullOrWhiteSpace($EmailReel))    { return 'sansEmail' }
    if ($EmailReel -ne $EmailAttendu)                { return 'mauvaisEmail' }

    # LA BONNE VALEUR N'EST PAS LA BONNE RAISON. Tant que la ligne recopiee a la
    # main porte l'adresse juste, rien ne se voit -- et c'est le probleme : ce
    # qui protege ce depot est cette ligne, pas le mecanisme. Mesure le 18 aout
    # 2026 sur la machine de l'auteur : six depots dans ce cas, dont un portant
    # l'adresse d'un autre compte.
    #
    # Les separateurs sont normalises plutot que decrits dans le motif : git
    # rend des slashes sur Windows aujourd'hui, et faire dependre un controle de
    # cette habitude est le genre d'hypothese qui casse ailleurs.
    if ("$Origine".Replace([char]92, '/') -match '(?i)(^|/)\.git/config$') { return 'emailEnDur' }

    'accord'
}

# UNE SEULE TABLE POUR DEUX COMMANDES.
#
# Chaque etat de l'identite git y dit ce que `ctx doctor` en rend ET ce que
# `ctx` en fait. Les deux la LISENT ; aucune des deux ne redecide.
#
# C'est ce que le test de coherence eprouve : un fait qui vaut PROBLEME chez
# l'un ne peut pas etre muet chez l'autre. Une ligne affichee sans etre jugee,
# dans un ecran qui rend un verdict, se lit comme jugee.
#
# ATTENTION n'est deliberement pas un refus : la valeur est juste, il n'y a
# aucun degat. Ce qui est signale est la FRAGILITE.
# CE QUE `ctx` AFFICHE, ET PAR QUELLE DECISION IL LE JUGE.
#
# C'est le livrable du retour d'usage du 24 aout 2026, et sa phrase tient en une
# ligne : une ligne affichee sans etre jugee, dans un ecran qui rend un verdict,
# SE LIT COMME JUGEE. Trois axes etaient dans ce cas le meme jour -- l'identite
# git, le remote, la session Vercel -- et `ctx doctor` rendait PROBLEME sur les
# trois pendant que `ctx` rendait GO.
#
# Un test derive les DEUX cotes : les lignes reellement affichees sont lues dans
# les fichiers de langue, les decisions reellement appelees dans la source de
# Test-DevContext. Seul l'APPARIEMENT est declare ici. Ajouter une ligne sans
# l'inscrire, ou l'inscrire sans appeler la decision, rend le test rouge.
#
# $null n'est pas un passe-droit : c'est l'affirmation qu'il n'y a aucun verdict
# a rendre sur ce fait -- et elle doit pouvoir se defendre.
$script:CtxAxesAffiches = [ordered]@{
    'ctx.actif'    = 'Get-CtxVerdictDossier'
    'ctx.dossier'  = $null   # le chemin courant : un fait sur l'endroit, pas sur l'identite
    'ctx.git'      = 'Get-CtxVerdictGitIdentite'
    'ctx.gh'       = 'Resolve-CtxGhLoginObserve'
    'ctx.vercel'   = 'Get-CtxVerdictVercelSession'
    'ctx.supabase' = 'Resolve-CtxSupabaseKey'
    'ctx.remote'   = 'Test-CtxDoctorRemote'
}

$script:CtxAxeGitIdentite = [ordered]@{
    horsContexte = @{ Doctor = 'INFO';      Ctx = 'rien' }
    sansEmail    = @{ Doctor = 'PROBLEME';  Ctx = 'probleme' }
    mauvaisEmail = @{ Doctor = 'PROBLEME';  Ctx = 'probleme' }
    emailEnDur   = @{ Doctor = 'ATTENTION'; Ctx = 'remarque' }
    accord       = @{ Doctor = 'OK';        Ctx = 'rien' }
}

function Get-CtxVerdictDossier {
    <#
      PURE. Le dossier courant et l'identite active s'accordent-ils ?

      Rend un ETAT, pas un message : l'appelant decide si cet etat vaut un
      refus, une remarque, ou rien. C'est la separation que le reste du module
      applique deja -- Test-CtxDoctor* decide, Get-Ctx*Facts ramasse -- et son
      absence ici a coute exactement ce qu'elle coute toujours.

      CE QUI A ETE CORRIGE LE 19 AOUT 2026

      Un dossier que PERSONNE ne possede rendait un NO-GO, motif « hors de la
      racine du contexte actif », correctif propose `work <ctx> -NoCd` -- soit
      exactement ce que l'utilisateur venait de lancer. Un verdict qu'aucune
      action n'efface est la faute du cri au loup, retournee contre le module
      lui-meme. Et `ctx doctor`, sur le meme dossier, repondait INFO : un seul
      fait, deux verdicts, dont un faux.

      Ce fichier declare pourtant, quelques lignes plus bas, que « NO-GO doit
      vouloir dire desaccord d'identite ». Un dossier sans proprietaire ne
      croise rien.

      CAUSE DE FOND

      Un contexte n'a qu'UNE racine, une chaine. « Hors de ma racine » etait
      donc confondu avec « appartient a quelqu'un d'autre » -- alors que ce
      second cas se decide par comparaison de NOMS, et se decidait deja.

      Les cinq etats sont distincts parce qu'ils appellent cinq reponses
      differentes, et les confondre deux a deux est precisement le defaut
      corrige.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Proprietaire,
        [AllowNull()][AllowEmptyString()][string]$Actif
    )

    $aProprio = -not [string]::IsNullOrWhiteSpace($Proprietaire)
    $aActif = -not [string]::IsNullOrWhiteSpace($Actif)

    if ($aProprio) {
        if (-not $aActif) { return 'dossierSansActif' }
        if ($Proprietaire -ne $Actif) { return 'dossierAutre' }
        return 'accord'
    }

    # Un contexte est charge, et ce dossier n'appartient a personne. Rien n'est
    # croise ; rien n'est decide non plus, et c'est ce qui merite d'etre dit.
    if ($aActif) { return 'sansProprietaire' }

    # Ni proprietaire, ni identite active : il n'y a aucune question.
    'neutre'
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

    # Les REMARQUES ne sont pas des problemes, et cette distinction est le
    # correctif du 19 aout 2026. Un constat vrai mais sans faute ne doit pas
    # tomber dans $problems : il y deviendrait un NO-GO, donc un refus, alors
    # que rien n'est croise.
    $remarques = @()

    # Combien de $problems qu'un `work` ne reglerait PAS. Sert au seul endroit
    # ou le correctif generique est propose : quand il ne reste que ceux-la, le
    # proposer serait envoyer vers une commande sans effet.
    $problemsHorsWork = 0

    $owner    = Resolve-DevContextForPath
    $here     = (Get-Location).Path

    # --- 0. L'outil est-il seulement installe ? ---
    #
    # Sans ce cas, la toute premiere commande d'un nouvel utilisateur repondait
    # « NO-GO » en rouge, motif « GH_CONFIG_DIR absent » -- un verdict d'echec
    # pour quelqu'un qui n'a encore rien fait de mal. NO-GO doit vouloir dire
    # « desaccord d'identite », jamais « tu n'as pas encore commence ».
    #
    # Mesure le 15 aout 2026 en simulant une machine vierge : premier ecran,
    # rouge, sans une seule indication de quoi faire ensuite.
    if (@(Get-CtxManifests).Count -eq 0) {
        if ($Quiet) { return $true }
        Write-Host ''
        Write-Host "  $(T 'ctx.vide.titre')" -ForegroundColor Yellow
        Write-Host "  $(T 'ctx.vide.racine' $script:CtxRoot)" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host "  $(T 'ctx.vide.explication1')" -ForegroundColor DarkGray
        Write-Host "  $(T 'ctx.vide.explication2')" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host "  $(T 'ctx.vide.creer')" -ForegroundColor Cyan
        Write-Host "    $(T 'ctx.vide.exemple')" -ForegroundColor Cyan
        Write-Host ''
        Write-Host "  $(T 'ctx.vide.racineAilleurs')" -ForegroundColor DarkGray
        Write-Host "  $(T 'ctx.vide.doctor')" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if (-not $Quiet) {
        Write-Host ""
        if ($env:DEVCTX) {
            Write-Host "  $(T 'ctx.actif' "$env:DEVCTX_LABEL ($env:DEVCTX)")" -ForegroundColor Cyan
        }
        else {
            Write-Host "  $(T 'ctx.aucun')" -ForegroundColor Red
        }
        Write-Host "  $(T 'ctx.dossier' $here)" -ForegroundColor DarkGray
    }

    # --- 1. Le dossier appartient-il au contexte actif ? ---
    #
    # La decision est au-dessus, pure et testable. Ce qui suit ne fait que
    # choisir le CANAL : un refus, une remarque, ou rien. Le seul etat qui a
    # change le 19 aout 2026 est 'sansProprietaire', passe des problemes aux
    # remarques -- ce qui, ici, se lit d'un coup d'oeil.
    #
    # Ce que la remarque dit est plus utile que le refus qu'elle remplace : dans
    # un dossier hors de toute racine, ce n'est pas l'identite du contexte qui
    # signera. Les regles includeIf ne portent que sur les racines de contextes,
    # mesure le 19 aout 2026 -- `git config --show-origin user.email` y
    # designait le ~/.gitconfig GLOBAL. Un depot client egare hors des racines
    # se voit a cette ligne.
    $proprietaire = Get-CtxProp $owner 'name'
    $etatDossier = Get-CtxVerdictDossier -Proprietaire $proprietaire -Actif $env:DEVCTX
    switch ($etatDossier) {
        'dossierSansActif' { $problems += T 'ctx.pb.dossierSansActif' $proprietaire }
        'dossierAutre' { $problems += T 'ctx.pb.dossierAutre' $proprietaire $env:DEVCTX }
        'sansProprietaire' { $remarques += T 'ctx.note.sansProprietaire' $env:DEVCTX }
    }

    # --- 1 bis. Ce que ce dossier est un depot git change ce qui s'y joue ----
    #
    # Lu une seule fois, et reutilise plus bas pour l'affichage : deux lectures
    # locales, aucun reseau.
    #
    # `remote get-url --push`, JAMAIS `remote.origin.url`. La regle `insteadOf`
    # reecrit l'URL au moment de l'usage : la valeur STOCKEE peut rester
    # https://github.com/... alors que le push part par la cle SSH du contexte.
    # Un controle bati sur la valeur stockee serait donc vert des deux cotes de
    # la frontiere -- et il aurait l'air de marcher.
    $estDepot = (git rev-parse --is-inside-work-tree 2>$null) -eq 'true'
    $gitEmail = if ($estDepot -or $env:DEVCTX) { (git config user.email 2>$null) } else { $null }
    $urlPush  = if ($estDepot) { (git remote get-url --push origin 2>$null) } else { $null }

    # --- 1 ter. Hors de toute racine, le REMOTE echappe aussi au contexte ----
    #
    # Ajoute le 24 aout 2026. La remarque ci-dessus ne disait que la moitie la
    # plus inoffensive : l'identite retombe sur le ~/.gitconfig global, ce qui
    # est souvent correct. C'est le remote NON REECRIT qui casse -- pas
    # d'`insteadOf`, donc un push HTTPS, donc un compte decide ailleurs qu'ici.
    #
    # Mesure du 24 aout 2026 : sur cette machine il n'existe aucun
    # `credential.helper` global, mais un `credential.https://github.com.helper`
    # -- portee par URL, invisible a `git config --get-all credential.helper`.
    # D'ou `--get-urlmatch`, la seule lecture qui resout cette portee. Croire
    # « aucun assistant » sur la foi de l'autre commande, c'est annoncer une
    # invite bloquante la ou le push part en silence sous le compte global.
    if ($etatDossier -eq 'sansProprietaire' -and $urlPush) {
        $assiste = $false
        if ($urlPush -match '^https://') {
            $assiste = -not [string]::IsNullOrWhiteSpace((git config --get-urlmatch credential.helper $urlPush 2>$null))
        }
        switch (Get-CtxVerdictRemoteSansContexte -UrlPush $urlPush -AssistantIdentifiants:$assiste) {
            'httpsAssiste' { $remarques += T 'ctx.note.remoteAssiste' $urlPush }
            'httpsNu' { $remarques += T 'ctx.note.remoteNu' $urlPush }
        }
    }

    # --- 2. Le compte GitHub actif est-il celui attendu ? ---
    # Le binaire REEL, jamais l'alias du module : celui-ci corrigerait
    # GH_CONFIG_DIR avant d'interroger l'API, et `ctx` repondrait GO en mesurant
    # une identite qu'il vient lui-meme de reparer. Voir src/Jetons.ps1.
    $ghExe = try { Get-CtxGhExe } catch { $null }

    # Y a-t-il un identifiant la ou `gh` regardera ? Question LOCALE, donc encore
    # repondable quand GitHub ne l'est pas -- c'est elle qui separe « jamais
    # connecte » de « connecte, mais injoignable a l'instant ».
    #
    # Reste $null quand GH_CONFIG_DIR est absent : le dossier par defaut de la
    # CLI depend de la plateforme, et le deviner ferait annoncer « non
    # authentifie » sur la foi d'un chemin suppose. Ce cas est deja un probleme
    # nomme plus bas (ctx.pb.ghConfigDir) ; il n'a pas besoin d'un second
    # message, encore moins d'un faux.
    $ghConfigExiste = $null
    if ($env:GH_CONFIG_DIR) {
        $ghHosts = [System.IO.Path]::Combine($env:GH_CONFIG_DIR, 'hosts.yml')
        $ghConfigExiste = Test-Path -LiteralPath $ghHosts
    }

    if ($ghExe) {
        # 2>$null garde la sortie d'erreur hors de la valeur -- mais ce n'est PAS
        # ce qui protege ici : le 17 aout 2026, la CLI a ecrit le corps d'erreur
        # de l'API sur sa sortie STANDARD, malgre cette redirection. Ce qui
        # protege est le couple code de sortie + forme du compte, dans
        # Resolve-CtxGhLoginObserve.
        $ghBrut = & $ghExe api user --jq .login 2>$null
        $ghCode = $LASTEXITCODE
        $ghObserve = Resolve-CtxGhLoginObserve -Sortie (@($ghBrut) -join "`n") `
            -Code $ghCode -ConfigExiste $ghConfigExiste
    }
    else {
        # `gh` absent n'est pas `gh` deconnecte. Rien n'a pu etre mesure, et
        # c'est `ctx doctor` qui nomme le binaire manquant.
        $ghObserve = Resolve-CtxGhLoginObserve -Sortie '' -Code 1 -ConfigExiste $null
    }

    # Null sauf si l'etat vaut 'connu' : la comparaison ci-dessous ne peut donc
    # plus porter sur autre chose qu'un compte reellement mesure.
    $ghLogin = $ghObserve.Login

    $expected = $env:DEVCTX_GH_LOGIN
    if ($expected -and $ghLogin -and ($ghLogin -ne $expected)) {
        $problems += T 'ctx.pb.compteGitHub' $ghLogin $expected
    }
    if ($env:DEVCTX -and -not $expected) {
        $problems += T 'ctx.pb.sansLogin'
    }
    if (-not $env:GH_CONFIG_DIR) {
        $problems += T 'ctx.pb.ghConfigDir'
    }

    # --- 3. Le jeton Supabase exporte correspond-il au projet du dossier ? ---
    # C'est la variable d'environnement qui compte, pas le wrapper : un binaire
    # appele directement (execFileSync, bash, agent IA) n'a que celle-la.
    if ($env:DEVCTX -and (Resolve-CtxSupabaseRef)) {
        $expectedKey = Resolve-CtxSupabaseKey
        if (-not $expectedKey) {
            $problems += T 'ctx.pb.supabaseIndex'
        }
        elseif ($env:DEVCTX_SUPABASE_KEY -ne $expectedKey) {
            $actual = if ($env:DEVCTX_SUPABASE_KEY) { $env:DEVCTX_SUPABASE_KEY } else { T 'ctx.supabase.aucun' }
            $problems += T 'ctx.pb.supabaseCle' $actual $expectedKey $env:DEVCTX
        }
    }

    # --- 4. L'identite git effective est-elle celle du contexte ? -----------
    #
    # LE QUATRIEME AXE, ajoute le 24 aout 2026. Les trois autres jugeaient le
    # proprietaire du dossier, le compte GitHub et la cle Supabase. L'identite
    # git, elle, etait AFFICHEE et jamais comparee -- une ligne d'information au
    # milieu d'un ecran qui rend un verdict.
    #
    # Or c'est le scenario fondateur du module : le depot porte un article
    # intitule committed-under-the-wrong-identity.md, et la commande lancee a
    # chaque debut de session etait muette precisement la-dessus. Mesure du
    # 24 aout 2026, meme dossier, meme processus : `ctx` GO, `ctx doctor`
    # PROBLEME.
    #
    # La decision n'est pas reecrite ici. Get-CtxVerdictGitIdentite est la meme
    # fonction que consomme `doctor`, $script:CtxAxeGitIdentite le meme tableau,
    # et un test refuse desormais qu'un etat vaille PROBLEME chez l'un et rien
    # chez l'autre.
    if ($proprietaire) {
        $origine = Get-CtxOrigineConfigGit (git config --show-origin user.email 2>$null)
        $etatGit = Get-CtxVerdictGitIdentite -EmailAttendu (Get-CtxProp $owner 'email') `
            -EmailReel $gitEmail -Origine $origine
        switch ($script:CtxAxeGitIdentite[$etatGit].Ctx) {
            'probleme' {
                if ($etatGit -eq 'sansEmail') { $problems += T 'ctx.pb.gitSansEmail' $proprietaire }
                else { $problems += T 'ctx.pb.gitIdentite' $gitEmail $proprietaire (Get-CtxProp $owner 'email') $origine }
                # `work` NE CORRIGE PAS celui-ci, et c'est tout l'interet de le
                # compter. Le correctif generique affiche sous un NO-GO suppose
                # que « presque tous se reglent par un work » ; cet axe-ci est le
                # premier a le contredire, et proposer une commande qui ne
                # change rien est le cri au loup retourne contre le module --
                # exactement ce qui a ete corrige le 19 aout 2026. Le vrai
                # correctif est nomme dans le message ci-dessus.
                $problemsHorsWork++
            }
            'remarque' { $remarques += T 'ctx.note.gitEnDur' }
        }
    }

    # --- 5. Le remote de push porte-t-il un login dans l'URL ? --------------
    #
    # Le piege du 5 aout 2026 : `https://login@github.com/...` ne matche pas la
    # regle `insteadOf`, qui est un prefixe de chaine. Le push part alors en
    # HTTPS sous le compte du `gh` GLOBAL -- silencieusement, et sous la
    # mauvaise identite.
    #
    # `doctor` le juge PROBLEME depuis ce jour-la. `ctx` affichait la meme URL
    # sans rien en dire. La decision n'est pas recopiee : c'est la fonction de
    # `doctor` qui est appelee, telle quelle.
    if ($urlPush) {
        $alias = if ($proprietaire) { "github-$proprietaire" } else { $null }
        if ((Test-CtxDoctorRemote -UrlPush $urlPush -AliasAttendu $alias).Verdict -eq 'PROBLEME') {
            $problems += T 'ctx.pb.remoteLogin' $urlPush
            $problemsHorsWork++   # se corrige par `git remote set-url`, pas par `work`
        }
    }

    # --- 6. Un projet Vercel sans session de contexte ? ---------------------
    #
    # Meme famille que l'axe 4, trouve en fermant celle-ci : `ctx` affichait
    # « vercel : aucune session » et concluait GO la ou `doctor` rendait
    # PROBLEME. Ici `work` EST le correctif, donc il reste propose.
    $aProjetVercel = Test-Path -LiteralPath (Join-Path $here '.vercel' 'project.json')
    $etatVercel = Get-CtxVerdictVercelSession -ADossierVercel:$aProjetVercel `
        -Proprietaire $proprietaire -ConfigSession $env:DEVCTX_VERCEL_CONFIG
    if ($etatVercel -eq 'sansSession') {
        $problems += T 'ctx.pb.vercelSansSession' $proprietaire
    }

    if (-not $Quiet) {
        Write-Host "  $(T 'ctx.git' $gitEmail)"
        # Trois etats, trois phrases. « (non authentifie) » servait aux trois, et
        # c'est ce qui a fait passer une panne de GitHub pour un compte manquant.
        $ghAffiche = if ($ghObserve.Etat -eq 'connu') {
            $ghObserve.Login
        } elseif ($ghObserve.Etat -eq 'nonAuth') {
            T 'ctx.ghNonAuth'
        } else {
            T 'ctx.ghNonVerifie'
        }
        Write-Host "  $(T 'ctx.gh' $ghAffiche)"
        Write-Host "  $(T 'ctx.vercel' (Get-CtxVercelState))"
        $sbState = if ($env:SUPABASE_ACCESS_TOKEN) {
            if ($env:DEVCTX_SUPABASE_KEY) { T 'ctx.supabase.chargeCle' $env:DEVCTX_SUPABASE_KEY } else { T 'ctx.supabase.charge' }
        } else { T 'ctx.supabase.aucun' }
        Write-Host "  $(T 'ctx.supabase' $sbState)"
        # `Test-Path .git` ne voyait pas un sous-dossier de depot, ni un
        # worktree lie, ou .git est un FICHIER. La question est deja repondue
        # plus haut, par git lui-meme, et l'URL deja lue : on l'affiche.
        if ($estDepot -and $urlPush) {
            Write-Host "  $(T 'ctx.remote' $urlPush)"
        }
        Write-Host ""
        if ($problems.Count -eq 0) {
            # Le GO habituel affirme que « identite, dossier et compte
            # concordent ». Quand le compte n'a pas pu etre lu, cette phrase
            # affirmerait une mesure qui n'a pas eu lieu -- deux lignes sous un
            # « gh : (non verifie) » qui dit le contraire. Un GO reste un GO :
            # les axes hors ligne, eux, ont bien ete verifies.
            #
            # Un troisieme cas depuis le 19 aout 2026, pour la meme raison : sur
            # un dossier que personne ne possede, « dossier concorde » affirme un
            # accord avec un proprietaire qui n'existe pas -- deux lignes
            # au-dessus d'une remarque qui dit « rien n'est decide non plus ».
            #
            # L'ordre n'est pas arbitraire. Le compte passe en premier, ce qui
            # laisse le comportement existant strictement inchange partout ou il
            # s'appliquait deja ; le proprietaire n'est consulte que la ou la
            # phrase habituelle serait fausse.
            $go = if ($ghObserve.Etat -eq 'nonVerifie' -and $expected) { 'ctx.goSansCompte' }
            elseif (-not $owner) { 'ctx.goSansProprietaire' }
            else { 'ctx.go' }
            Write-Host "  $(T $go)" -ForegroundColor Green
        }
        else {
            Write-Host "  $(T 'ctx.noGo')" -ForegroundColor Red
            foreach ($p in $problems) { Write-Host "    - $p" -ForegroundColor Red }

            # Un verdict sans la commande qui le corrige oblige a se souvenir de
            # la syntaxe au pire moment. Presque tous les NO-GO se reglent par un
            # `work`, et quand le dossier designe son proprietaire, on peut meme
            # le nommer.
            # ... sauf quand AUCUN des problemes n'est de ceux-la. Le message du
            # probleme porte alors son propre correctif, et une commande sans
            # effet ne vient plus s'interposer.
            $correctif = if ($problems.Count -eq $problemsHorsWork) { $null }
            elseif ($owner) { "work $($owner.name) -NoCd" }
            elseif ($env:DEVCTX) { "work $env:DEVCTX -NoCd" }
            if ($correctif) {
                Write-Host ""
                Write-Host "  $(T 'ctx.correctif' $correctif)" -ForegroundColor Yellow
            }
            Write-Host "  $(T 'ctx.detail')" -ForegroundColor DarkGray
        }

        # Apres le verdict, jamais dedans : une remarque qui remonterait au-dessus
        # se lirait comme un motif de refus.
        foreach ($r in $remarques) {
            Write-Host ""
            Write-Host "  $r" -ForegroundColor Yellow
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
        throw (T 'ctx.incoherent')
    }
}

# ---------------------------------------------------------------------------

Set-Alias -Name work      -Value Use-DevContext
# `ctx` n'est plus un alias vers Test-DevContext mais vers un repartiteur : il
# accepte `ctx doctor` en plus de `ctx-doctor`, et rend une aide utile sur un
# mot inconnu au lieu d'une erreur de liaison de parametre nommant une fonction
# interne. Le verdict reste le comportement de `ctx` sans argument. Voir src/Ctx.ps1.
Set-Alias -Name ctx       -Value Invoke-DevCtx

# Les douze alias ctx-<nom> sont derives de la table de src/Ctx.ps1, et non
# recopies : les deux orthographes ne peuvent donc pas diverger, et ajouter une
# sous-commande n'oblige a toucher qu'un seul endroit.
foreach ($sc in (Get-CtxSousCommandes).GetEnumerator()) {
    Set-Alias -Name "ctx-$($sc.Key)" -Value $sc.Value
}

Set-Alias -Name code-ctx  -Value Open-DevCode
Set-Alias -Name web-ctx   -Value Open-DevBrowser
Set-Alias -Name vercel    -Value Invoke-DevVercel
Set-Alias -Name supabase  -Value Invoke-DevSupabase
# `gh` est alias depuis la 1.4.0, et pas par symetrie : sur une installation
# standard il vit dans C:\Program Files, donc dans le PATH SYSTEME, que le PATH
# utilisateur ne peut pas preceder. Le shim ne le voit alors jamais. Voir
# Invoke-DevGh.
Set-Alias -Name gh        -Value Invoke-DevGh
Set-Alias -Name sb-index  -Value Update-DevSupabaseIndex

$exportedFunctions = @(
    'Use-DevContext', 'Clear-DevContext', 'Get-DevContextList', 'New-DevContext',
    'Close-DevContext', 'Open-DevCode', 'Open-DevBrowser', 'Test-DevContext',
    'Assert-DevContext', 'Resolve-DevContextForPath', 'Invoke-DevVercel',
    'Invoke-DevSupabase', 'Update-DevSupabaseIndex', 'Test-CtxSupabaseGuard',
    'Get-DevSupabaseMap', 'Get-DevContextDoctor', 'New-DevProjectMcp',
    'Get-CtxSupabasePaires', 'Get-CtxArgumentValeur', 'Get-CtxSupabaseRefDepuisUrl',
    'Get-DevEditorList', 'New-DevShortcut', 'Set-DevContextRoot',
    'Test-CtxGhGuard', 'Test-CtxGhEcriture', 'Test-CtxVercelGuard', 'Invoke-DevGh',
    'Invoke-DevCtx', 'Resolve-CtxPathSansVides', 'Invoke-DevContextInit',
    'Invoke-DevContextDashboard', 'Invoke-DevContextGuard'
)
# Les alias ctx-<nom> sont DERIVES de la meme table que les alias eux-memes.
# Ils y etaient recopies a la main jusqu'a la 1.8.0, et le defaut a frappe des
# la premiere sous-commande ajoutee : `ctx-init` etait cree, jamais exporte,
# donc absent chez l'appelant -- pendant que `ctx init` fonctionnait. Deux
# orthographes, une seule qui marche : exactement ce que la table etait censee
# rendre impossible.
$exportedAliases = @(
    'work', 'ctx', 'code-ctx', 'web-ctx', 'vercel', 'supabase', 'gh', 'sb-index'
) + @((Get-CtxSousCommandes).Keys | ForEach-Object { "ctx-$_" })

Export-ModuleMember -Function $exportedFunctions -Alias $exportedAliases
