# Textes francais de DevContext.
#
# Une cle par message, en notation pointee : <commande>.<sujet>.
#
# Les substitutions passent par {0}, {1}… et l'operateur -f, jamais par de la
# concatenation : une traduction doit pouvoir REORDONNER ce qu'elle insere.
# L'allemand place son verbe a la fin, le francais son adjectif apres le nom ;
# une phrase assemblee par morceaux ne survit pas au premier de ces deux cas.
#
# Ces chaines sont affichees dans un terminal dont on ignore l'encodage. Elles
# restent en ASCII : un accent devient un caractere de remplacement sous
# git-bash, et un message de refus est la sortie qui doit se lire correctement
# sur une machine dont on ne sait rien.

@{
    # --- ctx : aucun contexte encore cree -----------------------------------
    'ctx.vide.titre'         = 'Aucun contexte sur cette machine.'
    'ctx.vide.racine'        = 'Racine : {0}'
    'ctx.vide.explication1'  = 'Un contexte = une identite complete : email git, cle SSH, compte GitHub,'
    'ctx.vide.explication2'  = 'session Vercel, jetons Supabase. Un par vie professionnelle.'
    'ctx.vide.creer'         = 'Pour en creer un :'
    'ctx.vide.exemple'       = 'ctx-new -Name perso -Email vous@exemple.com -Root C:\dev\perso'
    'ctx.vide.racineAilleurs' = 'Pour ranger les contextes ailleurs :  ctx-root <dossier>'
    'ctx.vide.doctor'        = 'Pour un etat des lieux de la machine : ctx-doctor'

    # --- ctx : verdict ------------------------------------------------------
    'ctx.actif'              = 'Contexte actif : {0}'
    'ctx.aucun'              = 'Contexte actif : AUCUN'
    'ctx.dossier'            = 'Dossier        : {0}'
    'ctx.git'                = 'git            : {0}'
    'ctx.gh'                 = 'gh             : {0}'
    'ctx.ghNonAuth'          = '(non authentifie)'
    'ctx.vercel'             = 'vercel         : {0}'
    'ctx.supabase'           = 'supabase       : {0}'
    'ctx.remote'             = 'remote (push)  : {0}'
    'ctx.go'                 = 'GO - identite, dossier et compte concordent.'
    'ctx.noGo'               = 'NO-GO'
    'ctx.correctif'          = 'Correctif : {0}'
    'ctx.detail'             = 'Detail complet : ctx-doctor'

    'ctx.pb.dossierSansActif' = "Ce dossier appartient au contexte '{0}', et aucun contexte n'est actif."
    'ctx.pb.dossierAutre'     = "Ce dossier appartient au contexte '{0}', mais '{1}' est actif."
    'ctx.pb.horsRacine'       = 'Hors de la racine du contexte actif ({0}).'
    'ctx.pb.compteGitHub'     = "Compte GitHub actif '{0}' - le contexte attend '{1}'."
    'ctx.pb.sansLogin'        = "Le contexte n'a pas de 'github.login' dans son manifeste : le compte actif ne peut pas etre verifie, seulement affiche."
    'ctx.pb.ghConfigDir'      = "GH_CONFIG_DIR absent : 'gh' utilise la config GLOBALE de la machine, donc le dernier compte connecte."
    'ctx.pb.supabaseIndex'    = "Projet Supabase de ce dossier absent de l'index. Lance 'sb-index'."
    'ctx.pb.supabaseCle'      = "SUPABASE_ACCESS_TOKEN porte la cle '{0}' alors que ce projet attend '{1}'. Corriger avec 'work {2} -NoCd'."

    'ctx.supabase.aucun'      = 'aucun token'
    'ctx.supabase.charge'     = 'token charge'
    'ctx.supabase.chargeCle'  = 'token charge ({0})'

    # --- ctx-list -----------------------------------------------------------
    'liste.vide.titre'        = 'Aucun contexte.'
    'liste.vide.racine'       = 'Racine : {0}'
    'liste.vide.racineAbsente' = '  (dossier absent)'
    'liste.vide.creer'        = 'En creer un :'
    'liste.vide.racineAilleurs' = 'Changer ou ils sont ranges : ctx-root <dossier>'

    # --- ctx-root -----------------------------------------------------------
    'racine.titre'            = 'Racine des contextes : {0}'
    'racine.source'           = 'source   : {0}'
    'racine.source.env'       = 'variable DEVCTX_LANG'
    'racine.source.variable'  = 'variable DEVCTX_ROOT'
    'racine.source.reglage'   = 'reglage {0}'
    'racine.source.defaut'    = 'defaut du systeme'
    'racine.existe'           = 'existe   : {0}'
    'racine.contextes'        = 'contextes: {0}'
    'racine.changer'          = 'Pour la changer : ctx-root <dossier>'
    'racine.ecrit'            = 'reglage ecrit dans : {0}'
    'racine.restes'           = "{0} contexte(s) restent a l'ancien emplacement :"
    'racine.restesRien'       = "Rien n a ete deplace. Ils contiennent des cles SSH ; les copier est"
    'racine.restesDecision'   = 'votre decision, pas celle d une commande de configuration.'
    'racine.varPrime'         = "DEVCTX_ROOT est posee dans ce shell ({0}) et l'emporte sur ce reglage."

    # --- garde-fou production ------------------------------------------------
    'garde.refuse'            = 'REFUSE - garde-fou production DevContext'
    'garde.base'              = 'Base visee : {0}'
    'garde.raison'            = 'Raison     : {0}'
    'garde.nomInconnu'        = '(nom inconnu)'
    'garde.derogation'        = "Si cette commande est vraiment voulue, pour celle-ci seulement :"
    'garde.jamaisProfil1'     = 'A ne jamais poser dans $PROFILE : ce serait retirer le garde-fou'
    'garde.jamaisProfil2'     = 'en croyant le garder.'
    'garde.raison.dbUrl'      = "'{0}' porte un --db-url qui vise une base impossible a identifier, et ce contexte contient un projet de production."
    'garde.raison.reset'      = "'{0}' detruit et recree la base. Refuse sur un projet de production."
    'garde.raison.branche'    = "'{0}' vers un projet de production depuis la branche '{1}' au lieu de '{2}'."
    'garde.introuvable'       = '{0} introuvable dans le PATH (hors shims).'
    'garde.refuseAlias'       = 'Commande refusee par le garde-fou de production DevContext.'

    # --- coffre et manifeste ---------------------------------------------------
    'vault.absent'            = "Module SecretManagement absent. Installer :`n  Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser"
    'vault.creation'          = "Creation du coffre '{0}'..."
    'manifeste.introuvable'   = "Contexte '{0}' introuvable ({1}). 'ctx-list' pour voir les contextes existants."

    # --- ctx-off ---------------------------------------------------------------
    'off.aucunActif'          = 'Aucun contexte actif.'
    'off.manquant1'           = "Le contexte '{0}' n'existe pas. Tant qu'il manque, l'identite"
    'off.manquant2'           = 'perso retombe sur la config GLOBALE de la machine - celle du'
    'off.manquant3'           = "dernier compte connecte. C'est le seul trou du dispositif."

    # --- code-ctx --------------------------------------------------------------
    'code.aucunActif'         = "Aucun contexte actif. 'work <contexte>' d'abord, ou 'code-ctx <contexte>'."
    'code.editeurInconnu'     = "'{0}' introuvable sur cette machine. 'ctx-editors' dit ce qui a ete detecte. Pour VS Code : Ctrl+Shift+P > 'Shell Command: Install code command in PATH'."
    'code.sansCli'            = "'{0}' est installe mais n'expose aucun point d'entree en ligne de commande. Il ne peut pas etre lance par DevContext."
    'code.ouverture'          = '{0} [{1}] -> {2}'
    'code.repliSynchrone'     = "Aucun executable trouve au-dessus de '{0}'. {1} est lance en avant-plan : cette fenetre restera ouverte tant qu'il tournera. 'ctx-editors' dit ce qui a ete detecte."

    # --- web-ctx ---------------------------------------------------------------
    'web.aucunActif'          = 'Aucun contexte actif.'
    'web.sansProfil'          = "Pas de 'chromeProfile' dans context.json pour '{0}'. Creer le profil dans Chrome, puis relever son dossier via chrome://version (champ 'Chemin du profil')."
    'web.chromeAbsent'        = 'chrome.exe introuvable.'

    # --- binaires enrobes -------------------------------------------------------
    'bin.vercelAbsent'        = 'vercel introuvable dans le PATH.'
    'bin.supabaseAbsent'      = 'supabase introuvable dans le PATH (hors shims).'
    'bin.supabaseEcarte'      = "supabase n'a ete trouve que dans un dossier reconnu comme un dossier de shims DevContext : {0}. Un dossier l'est s'il porte editor.ps1 ET supabase.ps1. Si c'est une vraie installation Supabase, renommer ou retirer ces deux fichiers. NE PAS appeler le binaire directement pour contourner : le garde-fou de production ne s'appliquerait plus."

    # --- sb-index ---------------------------------------------------------------
    'index.aucunActif'        = "Aucun contexte actif. 'work <contexte>' d'abord, ou 'sb-index <contexte>'."
    'index.ancienIllisible'   = 'Index existant illisible, il sera reconstruit sans les marquages manuels.'
    'index.reponseIllisible'  = '{0} : reponse illisible (jeton revoque ou expire ?). Ignore.'
    'index.ecrit'             = 'index ecrit : {0}'

    # --- ctx-sb -----------------------------------------------------------------
    'sb.aucunActif'           = "Aucun contexte actif. 'work <contexte>' d'abord, ou 'ctx-sb <contexte>'."
    'sb.sansIndex'            = "Aucun index Supabase pour '{0}'. Lance 'sb-index'."
    'sb.sansIndexAvert'       = "Aucun index Supabase pour '{0}'. Lance 'sb-index'."
    'sb.projetActif'          = '[{0} -> {1}]'

    # --- ctx-new ----------------------------------------------------------------
    'new.nomInvalide'         = 'Nom de contexte invalide : minuscules, chiffres et tirets uniquement.'
    'new.existeDeja'          = "Le contexte '{0}' existe deja ({1})."
    'new.racinePrise'         = "La racine '{0}' est deja celle du contexte '{1}'."
    'new.cleGeneration'       = 'Generation de la cle SSH du contexte (passphrase recommandee) :'
    'new.cleSansGeneration'   = 'Cle SSH NON generee (-NoKey).'
    'new.cleCommande'         = "ssh-keygen -t ed25519 -C '{0}' -f '{1}'"
    'new.cleImpossible'       = "Generation de cle SSH impossible : l'entree standard est redirigee, et ssh-keygen attendrait une passphrase indefiniment.`n  - dans un terminal interactif : relancer la meme commande`n  - dans un script ou une CI    : ajouter -NoKey, puis generer la cle plus tard`nLe contexte '{0}' a bien ete cree : {1}"
    'new.jetonsIgnores'       = 'Saisie des jetons ignoree (entree non interactive).'
    'new.jetonsPlusTard'      = 'Les poser plus tard, un par un :'
    'new.jetonsCles'          = 'cles : {0}'
    'new.jetonsSaisie'        = 'Tokens du contexte (Entree pour passer)'
    'new.cree'                = "Contexte '{0}' cree."
    'new.resteAFaire'         = 'Reste a faire, une seule fois :'
    'new.etape1'              = '1. Ajouter la cle publique au compte GitHub {0} :'
    'new.etape1Sans'          = "1. Generer la cle SSH, puis l ajouter au compte GitHub {0} :"
    'new.etape2'              = '2. work {0} ; gh auth login   (config isolee dans {1})'
    'new.etape3'              = "3. Creer le profil Chrome dedie, puis renseigner 'chromeProfile' dans context.json"
    'new.etape4'              = '4. code-ctx {0}   (editeur vierge : connecter le compte du client)'
    'new.etape5a'             = "5. Renseigner 'github.login' dans context.json - sans lui, 'ctx' ne peut"
    'new.etape5b'             = "que rapporter le compte actif, jamais verifier que c'est le bon."

    # --- ctx-end ----------------------------------------------------------------
    'end.titre'               = 'TRANSFERT - {0} ({1})'
    'end.avantPurge'          = 'A verifier avant de purger :'
    'end.item1'               = '[ ] 2FA de la messagerie basculee sur le client (pas votre telephone)'
    'end.item2'               = '[ ] Numero de recuperation et email de secours retires du compte'
    'end.item3'               = '[ ] Moyen de paiement retire de Vercel et Supabase, remplace par celui du client'
    'end.item4'               = '[ ] Votre cle SSH perso absente des Deploy keys du/des depots'
    'end.item5'               = '[ ] Tokens revoques cote fournisseur (les supprimer du coffre ne les revoque pas) :'
    'end.item5Urls'           = 'github.com/settings/tokens  |  vercel.com/account/tokens  |  supabase.com/dashboard/account/tokens'
    'end.item6'               = '[ ] Mot de passe de la messagerie change et transmis au client'
    'end.item7'               = '[ ] Sauvegarde du depot archivee de votre cote si le contrat le prevoit'
    'end.relancer'            = 'Relancer avec -Purge pour supprimer secrets et dossier de contexte.'
    'end.actifIci'            = "Le contexte '{0}' est actif dans ce terminal. 'ctx-off' d'abord - purger sous soi laisse des secrets charges en memoire."
    'end.supprime'            = 'Secrets et dossier supprimes.'

    'off.exemple'             = 'ctx-new {0} -Label ''Perso'' -Email ''<votre-email>'' '
    'off.exempleSuite'        = "-Root '{0}' -GithubLogin '<votre-login>'"
    'new.jetonsCommande'      = 'Set-Secret -Vault DevContext -Name ''devctx/{0}/<cle>'' -SecureStringSecret $s'
    'end.sshManuel1'          = "Retirer manuellement le bloc 'Host github-{0}' de {1}"
    'end.sshManuel2'          = 'et le bloc includeIf correspondant de {0}.'
    'end.projetIntact'        = "Le dossier projet {0} n'a pas ete touche."
    'ctx.incoherent'          = 'Contexte incoherent - commande interrompue.'

    # --- ctx-mcp -----------------------------------------------------------------
    'mcp.prodLectureSeule'    = 'Projet de production : le serveur reste en lecture seule malgre -Ecriture.'
    'mcp.rienADeclarer'       = 'Rien a declarer pour ce dossier.'
    'mcp.ignore'              = 'ignore : {0}'
    'mcp.aucunClient'         = 'Aucun client MCP detecte dans ce dossier. Preciser -Client pour en creer un : {0}'
    'mcp.illisible'           = '{0} existant illisible : {1}. Le corriger ou le deplacer avant de regenerer.'
    'mcp.fichier'             = '{0} - {1}'
    'mcp.ajoutes'             = 'ajoutes   : {0}'
    'mcp.remplaces'           = 'remplaces : {0}'
    'mcp.conserves'           = 'conserves : {0} (-Force pour les remplacer)'
    'mcp.clientInconnu'       = "Client MCP inconnu : '{0}'. Connus : {1}"

    # --- ctx-shortcut --------------------------------------------------------------
    'rac.dossierAbsent'       = 'Dossier introuvable : {0}'
    'rac.horsContexte'        = "Aucun contexte ne possede '{0}'. Un raccourci qui n isole rien est precisement celui qu on remplace ici. 'ctx-list' pour voir les contextes."
    'rac.aucunEditeur'        = "Aucun editeur enrobable trouve{0}. 'ctx-editors' dit ce qui a ete detecte."
    'rac.sousLeNom'           = " sous le nom '{0}'"
    'rac.lanceurAbsent'       = 'Lanceur absent : {0}. Depot incomplet.'
    'rac.existeDeja'          = 'Le raccourci existe deja : {0}. -Force pour le reecrire.'
    'rac.ecrit'               = 'Raccourci ecrit : {0}'
    'rac.projet'              = 'projet   : {0}'
    'rac.contexte'            = 'contexte : {0}'
    'rac.editeur'             = 'editeur  : {0} (par le shim, jamais par chemin absolu)'

    # --- lanceur -------------------------------------------------------------------
    'lanceur.go'              = 'GO'
    'lanceur.fermer'          = 'Entree pour fermer'
    'lanceur.moduleAbsent'    = 'Module DevContext introuvable : {0}'
    'lanceur.dossierAbsent'   = 'Dossier introuvable : {0}'
    'lanceur.horsContexte'    = "Aucun contexte ne possede '{0}'. 'ctx-list' pour voir les contextes, ou passer -Context explicitement."
    'lanceur.noGo'            = "NO-GO - l'editeur n'a pas ete lance. Corriger avant de pousser ou deployer."

    'rac.doc.isole'           = 'profil isole ({0})'
    'rac.doc.dansContexte'    = 'contexte {0}'
    'rac.doc.profilDedie'     = 'profil dedie'
    'rac.doc.partage'         = "ouvre un projet du contexte '{0}' sur le profil PARTAGE : les sessions GitHub, Copilot et marketplace y sont communes a tous les contextes"
    'rac.doc.sansDossier'     = 'lance un editeur sans dossier : il rouvrira ce que le profil partage avait en dernier'
    'rac.doc.sansDossierFix'  = "viser 'code' plutot que le chemin absolu de l executable, ou passer par ctx-shortcut"
    'rac.doc.regroupes'       = '{0} raccourci(s) ouvrant un editeur sans dossier ({1}) : ils atterrissent sur le profil partage'

    # --- installateur ----------------------------------------------------------
    'inst.broadcast'          = 'Diffusion WM_SETTINGCHANGE impossible : {0}'
    'inst.broadcastSuite'     = "Le PATH est correct dans le registre. Les applications deja lancees ne le verront qu'apres redemarrage."
    'inst.shimsManquants'     = 'Fichiers de shim manquants : {0}. Depot incomplet, installation interrompue.'
    'inst.moduleIllisible'    = 'Module DevContext illisible, points d entree editeurs ignores : {0}'
    'inst.actif'              = 'SHIM ACTIF dans le PATH utilisateur'
    'inst.absent'             = 'SHIM ABSENT du PATH utilisateur'
    'inst.dossier'            = 'dossier : {0}'
    'inst.registre'           = 'registre: HKCU\Environment\Path ({0})'
    'inst.fichiers'           = 'Fichiers de shim :'
    'inst.pointsEntree'       = 'Points d entree editeurs generes :'
    'inst.aucun'              = '(aucun)'
    'inst.aucune'             = '(aucune)'
    'inst.resolution'         = 'Resolution de "supabase" dans CE processus :'
    'inst.poseNonActif'       = 'Pose dans le registre, mais pas encore actif dans ce terminal.'
    'inst.terminalNeuf'       = 'Ouvrir un terminal neuf.'
    'inst.retire'             = 'retire : {0}'
    'inst.jonction'           = 'Jonction (chemin stable, sans numero de version) :'
    'inst.jonctionAbsente'    = 'absente -- relancez installer-shims.ps1'
    'inst.jonctionAilleurs'   = 'ne pointe PAS sur ce module ({0}) -- relancez installer-shims.ps1'
    'inst.jonctionPosee'      = 'Jonction posee.'
    'inst.jonctionRetiree'    = 'Jonction retiree.'
    'inst.ancienneEntree'     = 'Ancienne entree encore dans le PATH : {0} -- relancez installer-shims.ps1'
    'inst.ancienneRetiree'    = 'Ancienne entree retiree du PATH : {0}'
    'inst.dejaAbsent'         = 'Deja absent du PATH. Rien a faire.'
    'inst.retireDuPath'       = 'Shim retire du PATH utilisateur.'
    'inst.ancienPath'         = 'Les terminaux deja ouverts gardent l ancien PATH.'
    'inst.editeursEnrobes'    = 'Editeurs enrobes (profil par contexte) :'
    'inst.aucunEditeur'       = 'Aucun editeur enrobable trouve.'
    'inst.aucunEditeurFix'    = 'ctx-editors dit ce qui a ete detecte et pourquoi.'
    'inst.pathDejaPose'       = 'PATH deja pose. Rien a faire de ce cote.'
    'inst.pose'               = 'Shim pose en tete du PATH utilisateur.'
    'inst.typePreserve'       = 'type registre preserve : {0}'
    'inst.sauvegarde'         = 'PATH d avant sauvegarde : {0}'
    'inst.pathLong'           = 'Le PATH utilisateur fait {0} caracteres. Certains outils anciens tronquent au-dela de 2047.'
    'inst.ancienPathNeuf'     = 'Les terminaux deja ouverts gardent l ancien PATH - en ouvrir un neuf.'
    'inst.profilSeul'         = 'profil seul'
    'inst.profilEtExt'        = 'profil + extensions'

    # --- routeur URI VS Code -----------------------------------------------------
    'uri.profilDefaut'        = 'profil par defaut'
    'uri.cible'               = 'cible : {0}'
    'uri.cle'                 = 'cle    : {0}'
    'uri.valeur'              = 'valeur : {0}'
    'uri.actif'               = 'ROUTEUR ACTIF'
    'uri.verrouActif'         = 'VERROU ACTIF - VS Code ne peut pas reprendre la cle'
    'uri.verrouAbsent'        = 'VERROU ABSENT - la cle sera ecrasee au prochain lancement de VS Code'
    'uri.origine'             = "gestionnaire d'origine (bug present) - relancer sans -Verifier"
    'uri.inconnue'            = "valeur inconnue - inspecter avant d'ecraser"
    'uri.restaure'            = 'Verrou retire, gestionnaire d origine restaure.'
    'uri.introuvable'         = 'Introuvable : {0}'
    'uri.dejaEnPlace'         = 'Deja en place et verrouille, rien a faire.'
    'uri.valeurConservee'     = 'Valeur precedente inattendue, conservee dans :'
    'uri.installe'            = 'Routeur installe et cle verrouillee.'
    'uri.verifier'            = 'Verifier : .\installer-uri-router.ps1 -Verifier'
    'uri.codeAbsent'          = 'Code.exe introuvable : {0}'

    # --- ctx doctor ------------------------------------------------------------
    'doc.bin.absent'          = 'introuvable dans le PATH'
    'doc.bin.shimSeul'        = 'seul le shim DevContext repond : le binaire reel est introuvable'
    'doc.bin.une'             = '{0} - {1}'
    'doc.bin.memeVersion'     = '{0} installations, meme version ({1})'
    'doc.bin.versionsDiff'    = '{0} installations de versions differentes : {1}'
    'doc.bin.correctifDiff'   = "n'en garder qu'une - la version depend sinon du shell appelant"
    'doc.git.horsContexte'    = 'ce dossier n appartient a aucun contexte'
    'doc.git.sansEmail'       = 'aucun user.email resolu'
    'doc.git.sansEmailFix'    = 'verifier le includeIf de ~/.gitconfig'
    'doc.git.mauvaisEmail'    = '{0} au lieu de {1} (defini par {2})'
    'doc.git.mauvaisEmailFix' = 'un user.email en dur dans .git/config prime sur le includeIf'
    'doc.git.pasDepot'        = 'pas un depot git'
    'doc.remote.aucun'        = 'aucun remote origin'
    'doc.remote.login'        = 'le remote porte un login dans son URL : la regle insteadOf ne matche pas'
    'doc.remote.loginFix'     = 'git remote set-url origin https://github.com/<org>/<repo>.git'
    'doc.remote.sansAlias'    = '{0} n emprunte pas la cle SSH {1}'
    'doc.remote.sansAliasFix' = "verifier la regle insteadOf du contexte"
    'doc.path.aucune'         = 'aucune'
    'doc.path.vides'          = '{0} entree(s) vide(s) : le dossier courant est dans le chemin de recherche'
    'doc.path.videsFix'       = 'retirer les ;; du PATH utilisateur'
    'doc.mcp.enClair'         = 'secret en clair dans la configuration ({0}) : {1}'
    'doc.mcp.enClairFix'      = 'remplacer par ${NOM_DE_VARIABLE} - work exporte deja le bon jeton'
    'doc.mcp.distant'         = 'serveur distant ({0}) : authentifie par OAuth, donc lie au compte connecte, pas au dossier'
    'doc.mcp.distantFix'      = 'un serveur stdio local avec un jeton pris dans l environnement suit le contexte'
    'doc.mcp.stdio'           = 'stdio ({0})'
    'doc.mcp.aucun'           = 'aucun serveur MCP declare pour ce dossier'
    'doc.ctx.horsContexte'    = 'ce dossier n appartient a aucun contexte'
    'doc.ctx.sansActif'       = "dossier du contexte '{0}', mais aucun contexte actif dans ce shell"
    'doc.ctx.autreActif'      = "dossier du contexte '{0}', identite active '{1}'"
    'doc.gh.sansConfigDir'    = 'GH_CONFIG_DIR absent : gh utilise la config globale, donc le dernier compte connecte'
    'doc.gh.autreContexte'    = 'GH_CONFIG_DIR pointe sur un autre contexte'
    'doc.gh.dedie'            = 'config dediee au contexte'
    'doc.sb.horsIndex'        = "projet lie mais absent de l index, ou environnement non marque"
    'doc.sb.prod'             = 'ce dossier vise un projet de PRODUCTION'
    'doc.sb.prodFix'          = 'db reset y est refuse, db push hors branche par defaut aussi'
    'doc.sb.mauvaiseCle'      = "le jeton charge n est pas celui que ce projet attend"
    'doc.sb.sansJeton'        = 'aucun jeton charge dans ce shell'
    'doc.vercel.sansSession'  = 'projet Vercel lie, mais aucune session de contexte chargee'
    'doc.vercel.ok'           = 'projet lie, session dediee au contexte'
    'doc.editeur.complet'     = 'profil et extensions par contexte'
    'doc.editeur.profilSeul'  = 'profil par contexte, extensions communes'
    'doc.editeur.methode'     = '{0} ({1})'
    'doc.editeur.limiteFix'   = 'aucun ; limite de cet editeur, pas du module'
    'doc.garde.sansDossier'   = 'dossier shims introuvable'
    'doc.garde.horsPath'      = 'shims absents du PATH : la protection ne couvre que PowerShell'
    'doc.garde.horsPathFix'   = 'pwsh -File installer-shims.ps1'
    'doc.garde.jonctionAbsente' = 'Le PATH designe le chemin stable, mais la jonction n existe pas : le garde-fou ne se lance plus.'
    'doc.garde.jonctionPerimee' = 'La jonction pointe sur {0}, alors que le module charge est {1}. Le garde-fou tourne sur une version perimee.'
    'doc.garde.jonctionFix'     = 'pwsh -File installer-shims.ps1   (a relancer apres chaque mise a jour du module)'
    'doc.garde.desarme'       = 'DEVCTX_ALLOW_PROD=1 : le garde-fou est desarme dans ce shell'
    'doc.garde.desarmeFix'    = 'Remove-Item Env:DEVCTX_ALLOW_PROD'
    'doc.garde.ok'            = 'actif dans tous les shells'
    'doc.wsl.distros'         = '{0} distribution(s) installee(s) ({1}) : le shim Windows n y est pas, le garde-fou ne couvre pas ces shells'
    'doc.wsl.fix'             = 'y installer la CLI Supabase separement, ou ne pas viser un projet de production depuis WSL'

    'work.contexte'           = 'CONTEXTE : {0}'
    'work.compte'             = 'Compte   : {0}'
    'work.secrets'            = 'Secrets  : {0}'
    'work.secretsAucun'       = 'aucun charge'

    'vercel.token'            = 'token charge'
    'vercel.session'          = 'session dediee'
    'vercel.aucune'           = 'aucune session'

    # --- editeurs -------------------------------------------------------------
    'editeur.profil.isole'    = 'isole'
    'editeur.profil.partage'  = 'PARTAGE'
    'editeur.ext.isolees'     = 'isolees'
    'editeur.ext.partagees'   = 'partagees'
    'editeur.sansUserDataDir' = "{0} n'expose pas --user-data-dir : ses sessions restent communes a tous les contextes."
}
