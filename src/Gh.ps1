# gh -- correcteur d'identite, et garde-fou quand il ne peut plus corriger.
#
# POURQUOI CE FICHIER EXISTE
#
# `gh` lit son compte dans un dossier de configuration designe par
# GH_CONFIG_DIR. Sans cette variable il retombe sur la configuration GLOBALE de
# la machine, c'est-a-dire sur le dernier compte connecte, quel qu'il soit.
# `work` pose la variable -- mais `work` est une commande PowerShell. Depuis
# git-bash, un script npm ou le shell d'un agent, elle n'a jamais ete posee.
#
# C'est la panne qui a fait naitre ce module. Elle etait traitee jusqu'ici par
# la discipline : "ne jamais lancer gh depuis bash". Une regle que l'outil
# peut tenir lui-meme n'a pas a etre confiee a la memoire de quelqu'un.
#
# CORRIGER AVANT DE REFUSER
#
# Le garde-fou Supabase ne peut que refuser : personne ne peut deviner quelle
# base l'utilisateur voulait vraiment atteindre. Ici la bonne reponse est
# connue, et c'est le dossier qui la donne. Refuser serait rendre un service de
# moins que ce qui est possible.
#
#   GH_CONFIG_DIR absent, le contexte a sa config    -> on la pose, en silence
#   GH_CONFIG_DIR absent, commande `gh auth ...`     -> on la pose, et on le dit
#   GH_CONFIG_DIR absent, pas de config, ECRITURE    -> refus + marche a suivre
#   GH_CONFIG_DIR pose et concordant                 -> rien a faire
#   GH_CONFIG_DIR pose sur un AUTRE contexte         -> refus des ecritures
#
# UNE LECTURE N'EST JAMAIS REFUSEE. Elle est signalee quand l'identite ne
# concorde pas. Refuser une lecture couterait plus qu'elle ne protege, et le
# reflexe d'un utilisateur bloque est d'appeler le binaire brut -- donc sans
# aucun garde-fou. La remarque vient de la relecture du 16 aout 2026 sur
# l'exclusion Supabase, et elle vaut ici mot pour mot.
#
# CE QUE CE FICHIER NE SAIT PAS FAIRE, ET QUI EST ASSUME
#
# Un verbe inconnu est traite comme une lecture. La grammaire de `gh` est
# reguliere -- `gh <nom> <verbe>` -- et les verbes se repetent d'un nom a
# l'autre, si bien qu'un nouveau NOM (gh en ajoute regulierement) est couvert
# sans rien changer ici. Un nouveau VERBE d'ecriture, lui, passerait. Le choix
# est delibere : sur un desaccord d'identite, rien ne passe en SILENCE -- ce qui
# n'est pas refuse est signale -- et `ctx` rend deja NO-GO sur la meme
# condition. Ce garde-fou est une seconde ligne, pas la seule.

# Les verbes qui ECRIVENT sur GitHub, ou dans le dossier de configuration.
#
# Classes par VERBE et non par commande complete : c'est ce qui fait qu'un nom
# ajoute par GitHub demain -- `gh ruleset`, `gh attestation`, tous arrives apres
# la v1 -- est couvert sans mise a jour. Les verbes composes sont coupes sur le
# tiret, ce qui attrape `item-add`, `field-create` ou `item-edit` de `gh project`.
$script:GhVerbesEcriture = @(
    'create', 'delete', 'edit', 'merge', 'close', 'reopen', 'rename', 'transfer'
    'archive', 'unarchive', 'add', 'remove', 'set', 'sync', 'upload', 'clear'
    'lock', 'unlock', 'pin', 'unpin', 'ready', 'comment', 'review', 'approve'
    'restore', 'revoke', 'dispatch', 'cancel', 'rerun', 'enable', 'disable'
    'block', 'unblock', 'accept', 'decline', 'fork', 'import', 'install'
    'uninstall', 'publish', 'promote', 'star', 'unstar', 'subscribe'
    'unsubscribe', 'invite', 'stop', 'run'
    # Ecrivent dans le dossier de configuration lui-meme. Un `gh auth login`
    # lance avec le dossier d'un AUTRE contexte y installe le mauvais compte,
    # et c'est precisement l'incident fondateur.
    'login', 'logout', 'switch', 'refresh'
)

# Les rares cas ou le verbe seul se trompe.
#
# `gh repo clone` lit ; `gh label clone` COPIE les libelles d'un depot vers un
# autre, donc ecrit. Un verbe ne peut pas porter les deux sens : la paire, si.
# Cette liste doit rester minuscule -- si elle grossit, c'est que la
# classification par verbe n'etait pas le bon modele.
$script:GhPairesEcriture = @('label clone')

function Get-CtxGhMots {
    <#
      Le nom et le verbe d'une ligne de commande `gh`.

      Positionnel, et c'est un choix : les deux premiers mots qui ne sont pas
      des options. `gh` n'a pratiquement pas d'option globale portant une valeur
      avant le nom, donc le premier mot est le nom et le second le verbe.

      Deliberement PAS la methode des paires adjacentes retenue pour Supabase :
      celle-ci ecarte les options mais garde leurs VALEURS, si bien que
      `gh issue list --label create` produirait la paire 'list create' et ferait
      passer une simple lecture pour une ecriture. Ce qui protege une CLI ne
      protege pas forcement la suivante.
    #>
    param([string[]]$Arguments = @())

    $mots = @(
        $Arguments |
            Where-Object { $_ -and -not "$_".StartsWith('-') } |
            ForEach-Object { "$_".ToLowerInvariant() }
    )
    [pscustomobject]@{
        Nom   = if ($mots.Count -ge 1) { $mots[0] } else { $null }
        Verbe = if ($mots.Count -ge 2) { $mots[1] } else { $null }
    }
}

function Get-CtxGhOption {
    <#
      La valeur d'une option, dans les trois ecritures que `gh` accepte :
      `--nom valeur`, `--nom=valeur` et la forme courte `-X valeur`.

      Get-CtxArgumentValeur ne connait que les deux premieres. `gh api -X DELETE`
      est justement ecrit dans la troisieme.
    #>
    param(
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$Long,
        [string]$Court
    )

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = "$($Arguments[$i])"
        if ($a -eq "--$Long" -or ($Court -and $a -eq "-$Court")) {
            if ($i + 1 -lt $Arguments.Count) { return "$($Arguments[$i + 1])" }
            return
        }
        if ($a.StartsWith("--$Long=")) { return $a.Substring($Long.Length + 3) }
    }
}

function Test-CtxGhEcriture {
    <#
      DECISION PURE. Cette commande modifie-t-elle quelque chose ?

      Rendre $false n'est jamais une autorisation : c'est "rien ne prouve que
      cela ecrit". L'appelant en tire un avertissement, pas un blanc-seing.
    #>
    [CmdletBinding()]
    param([string[]]$Arguments = @())

    $mots = Get-CtxGhMots -Arguments $Arguments
    if (-not $mots.Nom) { return $false }

    # `gh api` peut etre l'un ou l'autre. La CLI bascule elle-meme en POST des
    # qu'un champ est fourni, meme sans --method : la regle suit la sienne.
    if ($mots.Nom -eq 'api') {
        $methode = Get-CtxGhOption -Arguments $Arguments -Long 'method' -Court 'X'
        if ($methode -and $methode.ToUpperInvariant() -ne 'GET') { return $true }
        foreach ($a in $Arguments) {
            $t = "$a"
            if ($t -in @('-f', '-F', '--field', '--raw-field', '--input')) { return $true }
            if ($t.StartsWith('--field=') -or $t.StartsWith('--raw-field=') -or $t.StartsWith('--input=')) { return $true }
        }
        return $false
    }

    if ($mots.Verbe) {
        if ("$($mots.Nom) $($mots.Verbe)" -in $script:GhPairesEcriture) { return $true }
        foreach ($part in ($mots.Verbe -split '-')) {
            if ($part -in $script:GhVerbesEcriture) { return $true }
        }
    }

    $false
}

function Test-CtxGhGuard {
    <#
      DECISION PURE. Aucun disque, aucun reseau, aucune variable lue ici : tout
      arrive en parametre, ce qui rend chaque branche verifiable sans machine
      mal configuree.

      Rend un verdict portant jusqu'a trois choses :
        Allowed       la commande peut-elle partir
        Redirection   le dossier de configuration a poser POUR L'ENFANT, ou $null
        Avertissement un message a ecrire sur stderr, ou $null

      La redirection ne modifie jamais la session de l'appelant : elle vaut pour
      le processus lance, et pour lui seul.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Arguments = @(),
        # Le contexte qui possede le dossier. Vide = ce module n'a pas d'avis.
        [AllowNull()][AllowEmptyString()][string]$Contexte,
        # <racine>/<contexte>/gh, le dossier que `work` poserait.
        [AllowNull()][AllowEmptyString()][string]$ConfigAttendu,
        # Ce que porte GH_CONFIG_DIR au moment de l'appel.
        [AllowNull()][AllowEmptyString()][string]$ConfigActuel,
        # Ce dossier contient-il deja une configuration `gh` utilisable ?
        [switch]$ConfigExiste,
        [switch]$Override
    )

    # Le contexte voyage DANS le verdict. Sans cela, l'appelant devrait le
    # redemander au module pour composer le correctif -- deux interrogations
    # pour une seule question, donc deux occasions de repondre differemment.
    $laisse = {
        param($regle, $redirection, $avertissement)
        [pscustomobject]@{
            Allowed       = $true
            Rule          = $regle
            Reason        = ''
            Contexte      = $Contexte
            Redirection   = $redirection
            Avertissement = $avertissement
        }
    }
    $refuse = {
        param($regle, $raison)
        [pscustomobject]@{
            Allowed       = $false
            Rule          = $regle
            Reason        = $raison
            Contexte      = $Contexte
            Redirection   = $null
            Avertissement = $null
        }
    }

    # Hors de tout contexte, ce module n'a rien a dire. C'est le cas d'un dossier
    # personnel, d'un depot clone au hasard, d'une machine ou DevContext vient
    # d'etre installe sans qu'aucun contexte n'existe encore.
    if (-not $Contexte -or -not $ConfigAttendu) { return (& $laisse 'hors-contexte' $null $null) }
    if ($Override) { return (& $laisse 'derogation' $null $null) }

    $ecrit = Test-CtxGhEcriture -Arguments $Arguments

    # Compare sans antislash final : Windows resout les chemins sans en tenir
    # compte, et deux ecritures du meme dossier ne doivent pas passer pour un
    # desaccord d'identite.
    $meme = $false
    if ($ConfigActuel) {
        $meme = $ConfigActuel.TrimEnd('\', '/') -eq $ConfigAttendu.TrimEnd('\', '/')
    }

    if ($meme) { return (& $laisse 'concordant' $null $null) }

    if ($ConfigActuel) {
        # La variable designe un AUTRE contexte. On ne la remplace pas : elle a
        # ete posee volontairement, et un outil qui ecrase un choix explicite
        # devient imprevisible. On juge, et on le dit.
        if ($ecrit) { return (& $refuse 'contexte-autre' (T 'gh.raison.autreContexte' $Contexte)) }
        return (& $laisse 'lecture-contexte-autre' $null (T 'gh.avert.autreContexte' $Contexte))
    }

    # GH_CONFIG_DIR absent : c'est le cas de git-bash, d'un script npm, d'un
    # agent -- toute la population pour laquelle ce shim existe.

    # `gh auth ...` a le dossier de configuration pour SUJET. Le rediriger fait
    # que `gh auth login`, tape depuis n'importe ou dans le contexte, connecte
    # CE contexte. C'est aussi la sortie du cas suivant, donc elle doit marcher
    # meme quand rien n'est encore configure.
    if ((Get-CtxGhMots -Arguments $Arguments).Nom -eq 'auth') {
        return (& $laisse 'auth-redirige' $ConfigAttendu (T 'gh.avert.authRedirige' $Contexte))
    }

    if ($ConfigExiste) { return (& $laisse 'redirige' $ConfigAttendu $null) }

    # Rien a rediriger vers : ce contexte n'a pas encore de compte `gh`. Une
    # ecriture partirait donc sous le compte global de la machine, c'est-a-dire
    # le dernier connecte. C'est exactement l'incident fondateur, et `ctx doctor`
    # le signale deja comme PROBLEME : le garde-fou ne fait ici que rendre
    # effectif un diagnostic qui existait.
    if ($ecrit) { return (& $refuse 'sans-config' (T 'gh.raison.sansConfig' $Contexte)) }

    # Une lecture sous le compte global ne laisse rien derriere elle. Pas
    # d'avertissement non plus : il se declencherait a chaque commande tant que
    # le contexte n'a pas de compte `gh`, et un outil qui crie en continu finit
    # ignore le jour ou il a raison.
    & $laisse 'lecture-globale' $null $null
}

function Resolve-CtxGhVerdict {
    <#
      RASSEMBLE les faits, puis appelle la decision pure.

      Vit dans le module, et non dans le shim, pour la raison apprise le 16 aout
      2026 sur le garde-fou Supabase : une regle ecrite dans le shim n'existe
      que pour les appelants qui traversent le shim. Voir CHANGELOG 1.3.5.
    #>
    param(
        [string[]]$Arguments = @(),
        [string]$Path
    )

    $dossier = if ($Path) { $Path } else { (Get-Location).Path }

    # LE DOSSIER DECIDE, JAMAIS LA SESSION. $env:DEVCTX n'est pas consulte :
    # quand session et dossier divergent -- l'etat que `ctx` nomme NO-GO -- c'est
    # le dossier qui dit la verite sur ce qui est en train d'etre modifie.
    $manifeste = Resolve-DevContextForPath -Path $dossier
    if (-not $manifeste) { return (Test-CtxGhGuard -Arguments $Arguments) }

    $contexte = Get-CtxProp $manifeste 'name'
    $attendu  = [System.IO.Path]::Combine((Get-CtxPath $contexte), 'gh')

    # "Existe" veut dire utilisable, donc porteur d'un compte. Un dossier vide
    # cree par `work` ne compte pas : y rediriger rendrait "non connecte" la
    # ou `gh` fonctionnait, et une regression pareille fait desinstaller l'outil.
    $existe = Test-Path -LiteralPath ([System.IO.Path]::Combine($attendu, 'hosts.yml'))

    Test-CtxGhGuard -Arguments $Arguments -Contexte $contexte -ConfigAttendu $attendu `
        -ConfigActuel $env:GH_CONFIG_DIR -ConfigExiste:$existe `
        -Override:($env:DEVCTX_ALLOW_GH -eq '1')
}

function Resolve-CtxGhLoginObserve {
    <#
      PURE. Traduit une execution de `gh api user --jq .login` en ce qui a ete
      OBSERVE -- question distincte de "quel est le compte".

      Le 17 aout 2026, pendant une panne GitHub de niveau Critical (API Requests
      en Major Outage), `ctx` a rendu NO-GO sur un dossier client parfaitement
      sain. La CLI avait ecrit le corps d'erreur de l'API SUR SA SORTIE STANDARD,
      le code de sortie n'etait pas lu, et cette phrase a ete comparee au compte
      attendu comme si c'etait une identite :

          Compte GitHub actif '{"message": "No server is currently available
          to service your request..."}' - le contexte attend 'ovb-willemot'.

      La meme question etait deja posee correctement a vingt lignes de la, dans
      `ctx doctor -Live` (src/Jetons.ps1), qui teste $LASTEXITCODE depuis le
      premier jour. Deux implementations d'une seule question, une seule juste.

      Trois etats, jamais deux, parce que trois choses distinctes peuvent etre
      vraies :

        connu       le compte est mesure, la comparaison a un sens
        nonAuth     aucun identifiant la ou `gh` regarde -- fait LOCAL et hors
                    ligne, donc encore vrai pendant une panne
        nonVerifie  un identifiant existe, on n'a pas pu le lire

      Le troisieme n'est PAS un probleme, et ne doit produire aucun NO-GO. Un
      reseau injoignable ne dit rien de l'identite, et un outil qui crie au loup
      se fait desinstaller -- doctrine deja tenue par `-Live`, ou un reseau muet
      est INFO et un 401 un PROBLEME. Elle manquait ici, c'est-a-dire dans la
      commande que l'on tape vingt fois par jour.

      Le doute penche vers `nonVerifie`, jamais vers `nonAuth` : annoncer "non
      authentifie" a quelqu'un qui l'est parfaitement l'enverrait refaire un
      `gh auth login` que la panne ferait echouer, pour reparer ce qui n'est pas
      casse.

      La FORME du compte est verifiee meme quand le code de sortie vaut zero. La
      garantie ne doit pas dependre de la discipline de sortie d'un binaire
      tiers : un nom de compte GitHub ne contient ni accolade, ni guillemet, ni
      espace, ni saut de ligne.
    #>
    param(
        # Ce que la commande a ecrit sur sa sortie standard.
        [AllowNull()][AllowEmptyString()][string]$Sortie,

        # Son code de sortie. Zero seul ne suffit pas, voir plus haut.
        [int]$Code = 0,

        # hosts.yml existe-t-il la ou `gh` lira ses identifiants ?
        #
        # Trois valeurs, et le $null porte du sens : $true un identifiant est
        # present, $false il n'y en a pas, $null l'appelant n'a pas pu savoir ou
        # regarder. Un [switch] confondrait les deux derniers, et cette confusion
        # rendrait "non authentifie" sur une machine dont on ignore l'etat.
        [AllowNull()][Nullable[bool]]$ConfigExiste
    )

    $texte = if ($null -eq $Sortie) { '' } else { $Sortie.Trim() }

    # 1 a 39 caracteres, alphanumeriques ou tirets, ne commence ni ne finit par
    # un tiret : les regles de GitHub. La classe de caracteres exclut le saut de
    # ligne, donc une reponse multiligne echoue ici -- et c'est voulu.
    $formeLogin = '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$'

    if ($Code -eq 0 -and $texte -match $formeLogin) {
        return [pscustomobject]@{ Login = $texte; Etat = 'connu' }
    }
    if ($ConfigExiste -eq $false) {
        return [pscustomobject]@{ Login = $null; Etat = 'nonAuth' }
    }
    [pscustomobject]@{ Login = $null; Etat = 'nonVerifie' }
}

function Get-CtxGhExe {
    <#
      Le VRAI gh, en ecartant tous nos dossiers de shims -- sous chacun de leurs
      noms, jamais un seul. Le module a paye cette lecon trois fois :
      Get-CtxSupabaseExe (1.3.1), Find-CtxEditorCli (1.3.2), l'audit des
      raccourcis (1.3.4).
    #>
    $exclus = Get-CtxShimDirs
    $tous = @(Get-Command gh -CommandType Application -All -ErrorAction SilentlyContinue)
    $candidat = $tous | Where-Object {
        -not (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $_.Source -Parent) -Dossiers $exclus)
    } | Select-Object -First 1

    if (-not $candidat) { throw (T 'bin.ghAbsent') }
    $candidat.Source
}

function Invoke-DevGh {
    <#
      L'ALIAS, et pourquoi il existe alors qu'un shim couvre deja le PATH.

      Mesure sur la machine de l'auteur le 16 aout 2026 :

          gh      -> C:\Program Files\GitHub CLI\gh.exe        (PATH systeme, index 10)
          shims   -> ...\DevContext\current\shims              (PATH utilisateur, index 19)

      Windows compose le PATH ainsi : SYSTEME d'abord, UTILISATEUR ensuite. Un
      installateur en portee utilisateur -- choix revendique de ce projet, aucun
      droit administrateur requis -- ne peut donc PAS masquer un binaire installe
      pour toute la machine. C'est le cas de `gh` des qu'il vient de winget ou du
      MSI, c'est-a-dire de l'installation standard.

      `supabase` y echappait par accident : il vient de npm, donc du PATH
      utilisateur. L'accident n'est pas une architecture.

      Cet alias rend donc le garde-fou effectif dans PowerShell quel que soit
      l'ordre du PATH. Il ne peut rien pour bash -- c'est une limite reelle,
      ecrite dans SECURITY.md, et `ctx doctor` nomme le dossier qui gagne.

      Il porte la MEME regle que le shim, jamais une copie : voir CHANGELOG 1.3.5.

      PAS DE BLOC param(), ET C'EST PORTEUR.

      Avec [CmdletBinding()], PowerShell reclame toute option courte qui prefixe
      un parametre commun. Mesure le 16 aout 2026, sur le propre diagnostic du
      module : `gh api -i user` echouait sur "le nom de parametre 'i' est
      ambigu : -InformationAction, -InformationVariable". Sont concernes -c, -d,
      -e, -i, -o, -p, -v, -w : autant d'options que ces CLI utilisent vraiment.

      C'est le piege que shims/gh.ps1 documente en tete, et il vaut pour une
      FONCTION autant que pour un script. $args transmet tout verbatim.
    #>
    $arguments = Get-CtxArgumentsBruts $args

    $verdict = $null
    try { $verdict = Resolve-CtxGhVerdict -Arguments $arguments }
    catch { $verdict = $null }

    if ($verdict -and -not $verdict.Allowed) {
        Write-CtxGhRefus -Verdict $verdict
        throw (T 'gh.refuseAlias')
    }
    if ($verdict -and $verdict.Avertissement) {
        Write-Host "  $($verdict.Avertissement)" -ForegroundColor DarkGray
    }

    $exe = Get-CtxGhExe

    if ($verdict -and $verdict.Redirection) {
        # RESTAUREE dans un finally, contrairement au shim. Celui-ci est un
        # processus jetable dont l'environnement meurt avec lui ; ici nous
        # sommes DANS la session de l'utilisateur, et y laisser GH_CONFIG_DIR
        # modifiee ferait decider les commandes suivantes par un effet de bord
        # invisible. Meme raison que le finally de Invoke-DevSupabase autour du
        # jeton.
        $avant = $env:GH_CONFIG_DIR
        try {
            $env:GH_CONFIG_DIR = $verdict.Redirection
            & $exe @arguments
        }
        finally {
            if ($null -eq $avant) { Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue }
            else { $env:GH_CONFIG_DIR = $avant }
        }
    }
    else {
        & $exe @arguments
    }
}

function Write-CtxGhRefus {
    <#
      Le bloc de refus. N'imprime ni variable d'environnement, ni jeton, ni les
      arguments de la commande : un refus finit dans les journaux et se colle
      dans les conversations.
    #>
    param([Parameter(Mandatory)]$Verdict)

    Write-Host ''
    Write-Host "  $(T 'gh.refuse')" -ForegroundColor Red
    Write-Host ''
    Write-Host "    $(T 'garde.raison' $Verdict.Reason)"
    Write-Host ''
    Write-Host "    $(T 'gh.correctif')" -ForegroundColor Cyan
    Write-Host "      work $($Verdict.Contexte) -NoCd" -ForegroundColor Cyan
    if ($Verdict.Rule -eq 'sans-config') {
        Write-Host '      gh auth login' -ForegroundColor Cyan
    }
    Write-Host ''
    Write-Host "    $(T 'gh.derogation')" -ForegroundColor DarkGray
    Write-Host '      $env:DEVCTX_ALLOW_GH = 1' -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil1')" -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil2')" -ForegroundColor DarkGray
    Write-Host ''
}
