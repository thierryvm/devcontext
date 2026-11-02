# vercel -- meme dispositif que gh, sur une CLI qui n'offre pas la meme prise.
#
# CE QUI DIFFERE DE gh
#
# `vercel` n'a pas d'equivalent de GH_CONFIG_DIR : son dossier de configuration
# ne se choisit QUE par l'option `-Q, --global-config DIR`. L'isolation ne peut
# donc pas se poser dans l'environnement -- elle doit s'ecrire dans la ligne de
# commande, a chaque appel. C'est exactement ce que faisait deja
# Invoke-DevVercel, et qui n'existait que dans PowerShell.
#
# CE QUI EST GARDE, ET CE QUI NE L'EST PAS
#
# Deux refus seulement, et ils sont ceux de la feuille de route :
#
#   deploiement `--prod` depuis une branche qui n'est pas la branche par defaut
#   `env rm` visant explicitement l'environnement production
#
# Ne sont delibrement PAS gardes :
#
#   `vercel rollback` -- c'est un geste de REPARATION. Le refuser tombe toujours
#     au pire moment : pendant un incident, depuis une branche de correctif.
#   `vercel promote` -- promouvoir un deploiement deja construit depuis une
#     branche laterale est un correctif a chaud legitime.
#   `vercel rm` -- ce qu'il supprime n'est pas identifiable comme production
#     depuis la ligne de commande seule. Refuser sur un doute, c'est refuser au
#     hasard.
#
# Cette liste courte est un choix. Un garde-fou dont on peut enoncer la regle en
# une phrase est un garde-fou qu'on garde ; SECURITY.md la reprend telle quelle.

# Comment la CLI lit une ligne. Releve sur ses sources -- packages/cli/src sur
# GitHub le 1er novembre 2026, puis le paquet 65.8.0 installe ici, le 2
# novembre -- lues, jamais executees.
#
# Une premiere lecture ne connait que les options GLOBALES, en mode permissif,
# par la bibliotheque `arg`. Le premier mot qui reste est compare EXACTEMENT a
# la table des commandes -- une Map JavaScript, sans mise en minuscules. S'il
# n'y est pas, c'est un chemin a deployer ; s'il n'y a pas de mot, c'est
# `vercel deploy`. Une option que cette lecture ne connait pas n'est PAS
# ecartee : le mode permissif la range avec les mots, et elle devient elle-meme
# le premier mot. `vercel --prod build` deploie donc `build` en production, la
# ou `vercel build --prod` construit.
#
# Ce que `arg` fait des ecritures moins courantes, et que ce lecteur reproduit :
# un groupe de lettres (`-dd`, `-dQ dir`) s'eclate en options courtes, dont
# seule la DERNIERE peut prendre une valeur ; un booleen ignore ce qui suit son
# `=` (`--debug=0` vaut vrai) ; chaque booleen global a sa negation `--no-` ; et
# tout ce qui suit un `--` nu est un mot.
#
# Le sens de l'erreur decide du contenu de ces listes, comme pour Supabase.
# Une option globale OUBLIEE rend la lecture ambigue, donc un refus de trop.
# Une commande OUBLIEE fait prendre son nom pour un chemin, donc un refus de
# trop -- seulement avec `--prod`, seulement hors branche par defaut. Dans les
# deux cas l'erreur se voit et se leve par derogation ; l'erreur inverse
# deploierait en production sans un mot.
$script:VercelOptionsGlobalesAValeur = @('cwd', 'local-config', 'global-config', 'scope', 'token', 'team', 'api')
$script:VercelOptionsGlobalesBool    = @(
    'help', 'version', 'debug', 'no-color', 'non-interactive', 'changelog',
    'no-help', 'no-version', 'no-debug', 'no-non-interactive', 'no-changelog'
)
$script:VercelCourtesAValeur         = @('A', 'Q', 'S', 't', 'T')
$script:VercelCourtesBool            = @('h', 'v', 'd')

# Les options qui nomment l'environnement vise par `deploy` et `redeploy` :
# `--environment` (court `-e`), et `--target`, son alias deprecie. `--prod` en
# est le raccourci booleen.
$script:VercelOptionsEnvironnement = @('--environment', '-e', '--target')

# Noms ET alias, tels que chaque command.ts les declare.
$script:VercelCommandes = @(
    'activity', 'agent', 'agent-runs', 'ai-gateway', 'alerts', 'alias', 'aliases', 'ln', 'api',
    'bisect', 'blob', 'budgets', 'budget', 'build', 'builders', 'buy', 'cache', 'certs', 'cert',
    'changelog', 'ci', 'comments', 'connect', 'contract', 'crons', 'cron', 'curl', 'daemons',
    'daemon', 'deploy', 'deploy-hooks', 'deploy-hook', 'dev', 'develop', 'dns', 'domains', 'domain',
    'drains', 'drain', 'env', 'experiments', 'feedback', 'firewall', 'flags', 'git',
    'global-config', 'edge-config', 'guidance', 'health', 'status-page', 'help', 'httpstat', 'init',
    'inspect', 'install', 'i', 'integration', 'integration-resource', 'ir', 'kms', 'link', 'list',
    'ls', 'login', 'logout', 'logs', 'log', 'mcp', 'metrics', 'microfrontends', 'mf',
    'notifications', 'open', 'organizations', 'organization', 'pricing', 'project', 'projects',
    'promote', 'pull', 'redeploy', 'redirects', 'redirect', 'remove', 'rm', 'rollback',
    'rolling-release', 'rr', 'routes', 'sandbox', 'schedules', 'security', 'setup', 'signup',
    'skills', 'storage', 'environments', 'environment', 'targets', 'target', 'teams', 'switch',
    'team', 'telemetry', 'token-pass', 'tokenpass', 'tokens', 'traces', 'upgrade', 'usage', 'vcr',
    'version', 'versions', 'webhooks', 'webhook', 'whoami'
)

function Read-CtxVercelLigne {
    <#
      LA lecture d'une ligne `vercel`. Le garde-fou et la redirection de
      configuration la consomment tous deux : deux lectures de la meme ligne
      finissent par repondre deux choses (AGENTS.md, "the same question
      answered in two places").

      Rend un ETAT, jamais un verdict :

        Etat 'commande'  Commande = le premier mot, casse comprise ;
                         Suite = les arguments bruts qui le suivent
        Etat 'aucune'    rien que des options globales : `vercel` nu, qui deploie
        Etat 'ambigue'   une option inconnue ou une ecriture incertaine avant
                         le premier mot

      'ambigue' ne veut jamais dire "rien a signaler". Chaque appelant en
      decide, et toujours du cote de la regle qu'il garde : un deploiement pour
      `--prod`, la ligne entiere fouillee pour `env rm` et pour `login`.

      Remplace Get-CtxVercelMots, qui ecartait les options en gardant leurs
      valeurs et mettait tout en minuscules : `vercel --cwd build --prod` et
      `vercel Logs --prod` y passaient pour des commandes sans effet distant.
      Releve par les audits de la PR #58, les 31 octobre et 1er novembre 2026.
    #>
    param([AllowEmptyCollection()][string[]]$Arguments = @())

    $bruts = @($Arguments | ForEach-Object { "$_" })
    $ambigue = { [pscustomobject]@{ Etat = 'ambigue'; Commande = $null; Suite = @() } }
    $commande = {
        param($rang)
        if ($rang -ge $bruts.Count) { return [pscustomobject]@{ Etat = 'aucune'; Commande = $null; Suite = @() } }
        [pscustomobject]@{
            Etat     = 'commande'
            Commande = $bruts[$rang]
            Suite    = @($bruts | Select-Object -Skip ($rang + 1))
        }
    }
    # Une valeur qui commence par un tiret, `arg` la refuse comme valeur
    # manquante. On ne devine pas ce que la CLI fera de la ligne.
    $valeurLisible = { param($rang) $rang -lt $bruts.Count -and -not $bruts[$rang].StartsWith('-') }

    $i = 0
    while ($i -lt $bruts.Count) {
        $a = $bruts[$i]

        if (-not $a.StartsWith('-')) { return (& $commande $i) }

        # Tout ce qui suit `--` est un mot, options comprises.
        if ($a -eq '--') { return (& $commande ($i + 1)) }
        # `-` seul est un chemin a deployer, pas une option.
        if ($a -eq '-') { return (& $ambigue) }

        if ($a.StartsWith('--')) {
            $eg  = $a.IndexOf('=')
            $nom = if ($eg -ge 0) { $a.Substring(2, $eg - 2) } else { $a.Substring(2) }

            # -cin : la CLI distingue la casse, `--CWD` lui est inconnu.
            if ($nom -cin $script:VercelOptionsGlobalesBool) { $i++; continue }
            if ($nom -cin $script:VercelOptionsGlobalesAValeur) {
                if ($eg -ge 0) { $i++; continue }
                if (-not (& $valeurLisible ($i + 1))) { return (& $ambigue) }
                $i += 2
                continue
            }
            return (& $ambigue)
        }

        # Courtes, seules ou groupees. Une lettre a valeur ailleurs qu'en fin
        # de groupe, `arg` la refuse ; une lettre inconnue rend tout incertain.
        $lettres = @($a.Substring(1).ToCharArray() | ForEach-Object { "$_" })
        $consomme = 1
        for ($k = 0; $k -lt $lettres.Count; $k++) {
            $lettre = $lettres[$k]
            if ($lettre -cin $script:VercelCourtesBool) { continue }
            if ($lettre -cin $script:VercelCourtesAValeur -and $k -eq $lettres.Count - 1) {
                if (-not (& $valeurLisible ($i + 1))) { return (& $ambigue) }
                $consomme = 2
                continue
            }
            return (& $ambigue)
        }
        $i += $consomme
    }

    [pscustomobject]@{ Etat = 'aucune'; Commande = $null; Suite = @() }
}

function Test-CtxVercelVisePro {
    <#
      `production` est-il ecrit quelque part dans ces arguments, en valeur
      separee, apres un `=` ou dans une liste a virgules ? La CLI joint par des
      virgules les environnements multiples de `env rm`.

      Trop large a dessein : une variable NOMMEE production serait refusee
      aussi, et `Production` compte, casse ignoree, la ou le reste de la
      lecture la respecte. C'est une derogation de trop, jamais une suppression
      de trop.
    #>
    param([AllowEmptyCollection()][string[]]$Arguments = @())
    foreach ($a in $Arguments) {
        foreach ($morceau in ("$a" -split '[=,]')) {
            if ($morceau -eq 'production') { return $true }
        }
    }
    $false
}

function Test-CtxVercelDemandeProd {
    <#
      Cette ligne demande-t-elle la production a `deploy` ou `redeploy` ?

      `--prod`, sous toutes ses ecritures : `arg` donne VRAI a un booleen quoi
      qu'on ecrive apres le `=`, donc `--prod=false` deploie en production.
      Et `--environment`, `-e` ou `--target` valant `production`, a N'IMPORTE
      QUELLE occurrence : une option repetee garde la derniere, et `--prod`
      cede devant `--environment`. Les suivre exactement, ce serait parier sur
      un ordre que la CLI peut changer ; refuser des que la production est
      nommee ne parie sur rien.
    #>
    param([AllowEmptyCollection()][string[]]$Arguments = @())

    $bruts = @($Arguments | ForEach-Object { "$_" })
    for ($i = 0; $i -lt $bruts.Count; $i++) {
        $a = $bruts[$i]
        if ($a -ceq '--prod' -or $a.StartsWith('--prod=')) { return $true }

        $eg  = $a.IndexOf('=')
        $nom = if ($eg -ge 0) { $a.Substring(0, $eg) } else { $a }
        if ($nom -cnotin $script:VercelOptionsEnvironnement) { continue }

        $valeur = if ($eg -ge 0) { $a.Substring($eg + 1) } elseif ($i + 1 -lt $bruts.Count) { $bruts[$i + 1] } else { '' }
        if ($valeur -eq 'production') { return $true }
    }
    $false
}

function Test-CtxVercelGuard {
    <#
      DECISION PURE. Ni disque, ni reseau, ni git : tout arrive en parametre.

      Toute incertitude laisse passer. Une branche inconnue -- hors depot, HEAD
      detachee -- n'est pas une raison de bloquer un deploiement.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Arguments = @(),
        [AllowNull()][string]$CurrentBranch,
        [AllowNull()][string]$DefaultBranch,
        [switch]$Override,
        # Le message d'un proprietaire AMBIGU (Get-CtxMessageAmbiguite), vide sinon.
        [AllowNull()][AllowEmptyString()][string]$Ambiguite
    )

    $passe = { param($regle) [pscustomobject]@{ Allowed = $true; Rule = $regle; Reason = '' } }

    if ($Override) { return (& $passe 'derogation') }

    $ligne = Read-CtxVercelLigne -Arguments $Arguments

    # --- proprietaire ambigu -------------------------------------------------
    #
    # Ici la regle "toute incertitude laisse passer" ne tient plus : ce n'est
    # pas la branche qui est inconnue, c'est le COMPTE. Aucune session de
    # contexte n'est injectee, et la CLI retomberait sur la session globale --
    # le dernier compte connecte. Seules passent les commandes dont on SAIT
    # qu'elles ne changent rien a distance ; une commande inconnue, ou un
    # `vercel` nu (qui deploie), est refusee. Liste fermee, a dessein : une
    # liste d'ecritures oublierait la prochaine.
    #
    # La commande est celle que lit Read-CtxVercelLigne, le lecteur qu'utilise
    # aussi le reste de ce garde-fou : `--cwd ls --prod` n'a pas de commande,
    # `ls` y etant la valeur de --cwd, et la CLI, sans commande, deploie.
    # Mesure par l'audit du 30 octobre 2026. Une lecture ambigue n'est jamais
    # une lecture permise.
    #
    # Et SENSIBLE a la casse : la CLI compare les noms de commande exactement,
    # et prend un mot inconnu pour un chemin a deployer. `vercel Logs --prod`
    # passait la liste, et sur Windows un dossier `logs` repond a `Logs`.
    # Releve par le contre-audit du 1er novembre 2026.
    if ($Ambiguite) {
        $bruts = @($Arguments | ForEach-Object { "$_" })
        $lecture = ($ligne.Etat -eq 'commande' -and $ligne.Commande -cin @('whoami', 'help', 'ls', 'list', 'inspect', 'logs')) -or
        ($bruts.Count -gt 0 -and @($bruts | Where-Object { $_ -cnotin @('--version', '-v', '--help', '-h') }).Count -eq 0)
        if (-not $lecture) {
            return [pscustomobject]@{ Allowed = $false; Rule = 'proprietaire-ambigu'; Reason = $Ambiguite }
        }
        return (& $passe 'lecture-ambigue')
    }

    # --- env rm sur la production -------------------------------------------
    #
    # Seulement quand 'production' est ECRIT. Sans cible, la CLI ouvre une
    # invite et l'humain voit ce qu'il choisit ; refuser la ferait disparaitre
    # pour les environnements de developpement aussi, ou l'operation est banale.
    #
    # La sous-commande est cherchee dans TOUTE la suite, et pas au rang deux :
    # `env` lit ses propres options avant elle, et si `rm` ou son alias
    # `remove` est la sous-commande, il est forcement ecrit quelque part. Le
    # chercher partout ne peut que refuser de trop -- `env add rm production`.
    # Sur une lecture ambigue, c'est la ligne ENTIERE qui est fouillee : ne pas
    # savoir ou commence la commande n'autorise pas a conclure qu'elle est
    # absente.
    $suite = if ($ligne.Etat -eq 'ambigue') { @($Arguments | ForEach-Object { "$_" }) } else { @($ligne.Suite) }
    $envVise = ($ligne.Etat -eq 'commande' -and $ligne.Commande -ceq 'env') -or ($ligne.Etat -eq 'ambigue' -and $suite -ccontains 'env')
    $envRm = $envVise -and ($suite -ccontains 'rm' -or $suite -ccontains 'remove')
    if ($envRm -and (Test-CtxVercelVisePro -Arguments $suite)) {
        return [pscustomobject]@{
            Allowed = $false
            Rule    = 'env-rm-production'
            Reason  = (T 'vercel.raison.envRm')
        }
    }

    # --- deploiement de production hors branche par defaut -------------------
    if (-not (Test-CtxVercelDemandeProd -Arguments $Arguments)) { return (& $passe 'non-garde') }

    # `vercel build --prod` construit en local sans rien deployer : le refuser
    # serait un faux refus sur une commande sans effet distant. Seule une
    # commande CONNUE l'obtient : un mot inconnu est un chemin que la CLI
    # deploie, `vercel` nu deploie, et une lecture ambigue se juge comme un
    # deploiement -- c'est ce que la CLI en fera le plus souvent.
    $connue = $ligne.Etat -eq 'commande' -and $ligne.Commande -cin $script:VercelCommandes
    if ($connue -and $ligne.Commande -cnotin @('deploy', 'redeploy')) { return (& $passe 'non-deploiement') }

    if (-not $CurrentBranch -or -not $DefaultBranch) { return (& $passe 'branche-inconnue') }
    if ($CurrentBranch -eq $DefaultBranch)           { return (& $passe 'branche-par-defaut') }

    [pscustomobject]@{
        Allowed = $false
        Rule    = 'prod-hors-branche'
        Reason  = (T 'vercel.raison.prodBranche' $CurrentBranch $DefaultBranch)
    }
}

function Resolve-CtxVercelVerdict {
    <#
      RASSEMBLE, puis decide. Rend aussi le dossier de configuration a injecter,
      quand il y en a un a injecter.

      Meme lecon que le garde-fou Supabase le 16 aout 2026 : la regle vit dans
      le module, parce qu'elle a deux appelants -- le shim du PATH et l'alias
      PowerShell, ce dernier passant AVANT le shim dans une session qui a
      importe le module.
    #>
    param(
        [string[]]$Arguments = @(),
        [string]$Path
    )

    $dossier = if ($Path) { $Path } else { (Get-Location).Path }

    $proprio  = Get-CtxProprietaire -Path $dossier
    $ambiguite = if ($proprio.Etat -eq 'ambigu') { Get-CtxMessageAmbiguite -Verdict $proprio } else { $null }

    $branches = Get-CtxBranchesPour -Dossier $dossier
    $verdict  = Test-CtxVercelGuard -Arguments $Arguments `
        -CurrentBranch $branches.Courante -DefaultBranch $branches.Defaut `
        -Override:($env:DEVCTX_ALLOW_VERCEL -eq '1') -Ambiguite $ambiguite

    $config = $null
    $avertissement = $null
    $manifeste = $proprio.Manifeste
    if ($ambiguite) {
        # Aucune redirection, pas meme celle qu'un `work` aurait posee : elle
        # designerait un contexte, et c'est precisement ce qu'on ne sait pas.
        # Une lecture qui passe est avertie, comme pour `gh`.
        if ($verdict.Allowed) { $avertissement = $ambiguite }
    }
    elseif ($manifeste) {
        $contexte = Get-CtxProp $manifeste 'name'
        $attendu  = [System.IO.Path]::Combine((Get-CtxPath $contexte), 'vercel')
        $ligne    = Read-CtxVercelLigne -Arguments $Arguments

        # Un `--global-config` deja present a ete ecrit volontairement. On ne
        # l'ecrase pas : un outil qui defait un choix explicite devient
        # imprevisible, et c'est la meme regle que pour GH_CONFIG_DIR.
        $dejaPose = @($Arguments | Where-Object {
                "$_" -eq '--global-config' -or "$_" -eq '-Q' -or "$_".StartsWith('--global-config=')
            }).Count -gt 0

        if (-not $dejaPose) {
            $connecte = Test-Path -LiteralPath ([System.IO.Path]::Combine($attendu, 'auth.json'))
            # Sur une lecture ambigue, un de ces mots n'importe ou suffit : la
            # rater enverrait la session dans la configuration GLOBALE, celle
            # du dernier compte connecte.
            $sessions = @('login', 'logout', 'switch')
            $ambigueSession = $ligne.Etat -eq 'ambigue' -and @($Arguments | Where-Object { "$_" -cin $sessions }).Count -gt 0
            if (($ligne.Etat -eq 'commande' -and $ligne.Commande -cin $sessions) -or $ambigueSession) {
                # Ces commandes ont le dossier de configuration pour SUJET. Les
                # rediriger fait qu'un `vercel login` tape dans le contexte
                # connecte CE contexte -- et c'est la sortie du cas "pas encore
                # de session", donc elle doit marcher avant qu'il y en ait une.
                if (-not (Test-Path -LiteralPath $attendu)) {
                    New-Item -ItemType Directory -Force -Path $attendu | Out-Null
                }
                $config = $attendu
                $avertissement = T 'vercel.avert.session' $contexte
            }
            elseif ($connecte) {
                $config = $attendu
            }
            # Ni session ni commande de session : on ne redirige pas. Pointer
            # vers un dossier vide rendrait "non connecte" la ou `vercel`
            # fonctionnait, ce qui est une regression, pas une protection.
        }
    }
    elseif ($env:DEVCTX_VERCEL_CONFIG) {
        # Hors de toute racine de contexte, mais un `work` est passe par la. On
        # honore ce qu'il a pose : c'est le comportement d'Invoke-DevVercel
        # depuis toujours, et le retirer casserait les dossiers qui vivent en
        # dehors des racines declarees.
        $sessionPosee = [System.IO.Path]::Combine($env:DEVCTX_VERCEL_CONFIG, 'auth.json')
        if (Test-Path -LiteralPath $sessionPosee) { $config = $env:DEVCTX_VERCEL_CONFIG }
    }

    [pscustomobject]@{ Verdict = $verdict; ConfigDir = $config; Avertissement = $avertissement }
}

function Get-CtxVercelExe {
    <#
      Le VRAI binaire vercel, en ecartant tous nos dossiers de shims.

      Indispensable depuis qu'un shim `vercel` existe : sans cette exclusion,
      `Get-Command vercel` trouve le shim, qui se rappelle lui-meme. Le module
      a paye cette lecon trois fois -- Get-CtxSupabaseExe (1.3.1),
      Find-CtxEditorCli (1.3.2), l'audit des raccourcis (1.3.4) -- et la
      comparaison porte donc sur TOUS les noms du dossier, jamais un seul.
    #>
    $exclus = Get-CtxShimDirs
    $tous = @(Get-Command vercel -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)
    $candidat = $tous | Where-Object {
        -not (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $_.Source -Parent) -Dossiers $exclus)
    } | Select-Object -First 1

    if (-not $candidat) { throw (T 'bin.vercelAbsent') }
    $candidat.Source
}

function Write-CtxVercelRefus {
    <#
      N'imprime ni jeton, ni variable d'environnement, ni les arguments : un
      refus finit dans les journaux et se colle dans les conversations.
    #>
    param([Parameter(Mandatory)]$Verdict)

    Write-Host ''
    Write-Host "  $(T 'vercel.refuse')" -ForegroundColor Red
    Write-Host ''
    Write-Host "    $(T 'garde.raison' $Verdict.Reason)"
    Write-Host ''
    Write-Host "    $(T 'vercel.derogation')" -ForegroundColor DarkGray
    Write-Host '      $env:DEVCTX_ALLOW_VERCEL = 1' -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil1')" -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil2')" -ForegroundColor DarkGray
    Write-Host ''
}
