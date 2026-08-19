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
    # --- ctx init -----------------------------------------------------------
    # La premiere commande, celle ou l'adoption se gagne ou se perd. Elle GUIDE :
    # elle demande avant chaque changement, et toute etape qu'elle n'execute pas
    # est affichee sous forme de la commande exacte qui l'execute.
    'init.titre'              = 'Mise en place de DevContext sur cette machine'
    'init.etape.coffre'       = 'Coffre a secrets (SecretManagement + SecretStore)'
    'init.etape.shims'        = 'Garde-fous joignables depuis tous les shells'
    'init.etape.contexte'     = 'Au moins un contexte de travail'
    'init.racine'             = 'Les contextes vivent dans : {0}'
    'init.racineChanger'      = 'Pour les ranger ailleurs :   ctx root <dossier>'
    'init.rienAFaire'         = 'Tout est en place. Rien a faire.'
    'init.suite'              = "Pour l'etat detaille de la machine : ctx doctor"
    'init.nonInteractif'      = "Entree redirigee : aucune question ne peut etre posee ici. Voici, dans l'ordre, ce qu'il reste a lancer."
    'init.manuel'             = 'A lancer soi-meme (installer un module est une dependance nouvelle) :'
    'init.action'             = 'mettre en place'
    'init.contexteProposition' = 'Commande pre-remplie a partir de git et gh -- a relire, puis a lancer :'

    # --- ctx : sous-commandes ----------------------------------------------
    # `ctx-doctor` et `ctx doctor` designent la meme chose. La seconde forme est
    # celle que tapent les doigts, parce que git, docker, gh et npm l'utilisent
    # tous ; la premiere se complete a la tabulation sous PowerShell.
    'ctx.sc.inconnue'        = "Sous-commande inconnue : '{0}'"
    'ctx.sc.titre'           = 'Commandes disponibles :'
    'ctx.sc.verdict'         = "dossier, identite et compte concordent-ils ?"
    'ctx.sc.tiret'           = 'Chacune existe aussi avec un tiret : ctx-doctor, ctx-list, ...'
    'ctx.sc.aide.check'      = 'meme verdict, mais leve une erreur (scripts, hooks git)'
    'ctx.sc.aide.doctor'     = 'etat de la machine : outils, comptes, garde-fous'
    'ctx.sc.aide.editors'    = 'quels editeurs savent isoler leur profil'
    'ctx.sc.aide.end'        = 'fermer la session de travail du contexte actif'
    'ctx.sc.aide.guard'      = 'dossiers approuves pour les agents : que voient-ils vraiment'
    'ctx.sc.aide.init'       = 'mettre en place DevContext sur cette machine'
    'ctx.sc.aide.list'       = 'lister les contextes de cette machine'
    'ctx.sc.aide.mcp'        = 'ecrire les serveurs MCP du projet courant'
    'ctx.sc.aide.new'        = 'creer un contexte'
    'ctx.sc.aide.off'        = 'desactiver le contexte de ce shell'
    'ctx.sc.aide.root'       = 'changer le dossier ou vivent les contextes'
    'ctx.sc.aide.sb'         = 'quel projet Supabase sur quel compte'
    'ctx.sc.aide.shortcut'   = 'creer un raccourci Bureau vers un projet'
    'ctx.sc.aide.who'        = 'a quel contexte appartient ce dossier'

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
    'ctx.ghNonVerifie'       = "(non verifie - la CLI gh n'a pas repondu)"
    'ctx.vercel'             = 'vercel         : {0}'
    'ctx.supabase'           = 'supabase       : {0}'
    'ctx.remote'             = 'remote (push)  : {0}'
    'ctx.go'                 = 'GO - identite, dossier et compte concordent.'
    'ctx.goSansCompte'       = 'GO - identite et dossier concordent. Compte GitHub non verifie, voir ci-dessus.'
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

    # --- gh : identite -------------------------------------------------------
    'gh.refuse'               = 'REFUSE - identite GitHub DevContext'
    'gh.correctif'            = 'Pour repartir sur la bonne identite :'
    'gh.derogation'           = "Si cette commande est vraiment voulue, pour celle-ci seulement :"
    'gh.raison.autreContexte' = "GH_CONFIG_DIR designe un autre contexte que '{0}', qui possede ce dossier. Cette commande ecrirait sur GitHub sous le mauvais compte."
    'gh.avert.autreContexte'  = "DevContext : lecture sous une identite qui n'est pas celle de '{0}'."
    'gh.avert.authRedirige'   = "DevContext : gh auth s'applique au contexte '{0}'."
    'gh.raison.sansConfig'    = "Le contexte '{0}' n'a pas encore de compte gh. Cette commande partirait sous le compte global de la machine, c'est-a-dire le dernier connecte."
    'gh.refuseAlias'          = 'Commande refusee par le garde-fou d identite GitHub DevContext.'

    # --- vercel --------------------------------------------------------------
    'vercel.refuse'           = 'REFUSE - garde-fou production DevContext (vercel)'
    'vercel.derogation'       = "Si cette commande est vraiment voulue, pour celle-ci seulement :"
    'vercel.raison.envRm'     = "'env rm' vise l'environnement production."
    'vercel.raison.prodBranche' = "Deploiement de production depuis la branche '{0}' au lieu de '{1}'."
    'vercel.avert.session'    = "DevContext : la session vercel s'applique au contexte '{0}'."
    'vercel.refuseAlias'      = 'Commande refusee par le garde-fou de production DevContext.'

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
    'bin.ghAbsent'            = 'gh introuvable dans le PATH (hors shims).'
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
    'doc.git.emailEnDur'      = '{0} -- mais defini en dur dans le .git/config de ce depot, pas par la regle de contexte'
    'doc.git.emailEnDurFix'   = "La valeur est juste, c'est la RAISON qui est fragile : un user.email ecrit dans .git/config prime sur le includeIf, donc ce depot est protege par une ligne recopiee a la main et non par le mecanisme. Si elle etait fausse, rien ne la rattraperait. Pour rendre la main a la regle du dossier : git config --unset user.email (et --unset user.name)."
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
    'doc.editeur.connexions'  = "un profil par contexte = un magasin de secrets par contexte : la connexion GitHub / Copilot est a ouvrir UNE FOIS dans chaque contexte, et se connecter dans l'un ne deconnecte plus l'autre"
    'doc.editeur.compteEtranger' = "le profil du contexte '{0}' garde des traces du compte {1}, qui appartient a un AUTRE contexte (autorisations d'extensions, compteurs d'usage). Ce profil n'attend que '{2}'. Cela peut etre une session ACTIVE -- Copilot, l'extension Pull Request et GitLens agiraient alors sous ce compte -- ou un RESIDU : VS Code conserve ces enregistrements apres une deconnexion, et ils re-accorderaient l'acces sans redemander a la prochaine connexion."
    'doc.editeur.compteEtrangerFix' = "Le menu Comptes de la fenetre fait autorite, pas ce diagnostic : ce fichier ne dit pas si une session est ouverte. Ouvrez une fenetre de ce contexte > menu Comptes (en bas a gauche). Si le compte etranger n'y figure pas, il n'y a RIEN a faire. S'il y figure, deconnectez-le -- et si c'est pour la synchronisation des reglages, basculez-la sur le compte MICROSOFT : VS Code l'accepte aussi, et le compte GitHub redevient propre a chaque contexte."
    # Ces quatre messages ENSEIGNENT autant qu'ils signalent. Quelqu'un qui lit
    # « dossier approuve hors contexte » sans savoir ce que ca coute referme le
    # rapport ; le constat doit donc nommer la consequence, et le correctif la
    # regle generale, pas seulement le geste.
    'doc.agent.confianceEtrangere' = "un agent ouvert ici peut aussi ecrire dans le contexte '{1}' : {2} (approuve en portee {3}). Vous travaillez dans '{0}'. Le cloisonnement de DevContext porte sur l'IDENTITE, jamais sur les ecritures : rien n'empeche un fichier de ce projet d'atterrir dans l'arborescence d'un autre client."
    'doc.agent.confianceEtrangereFix' = "Retirer ces dossiers de permissions.additionalDirectories du fichier de portee utilisateur, puis les rouvrir au cas par cas dans le .claude/settings.json DU PROJET concerne. La regle : une approbation ponctuelle enregistree globalement vaut pour toutes les sessions futures, y compris celles d'un autre client. C'est ainsi qu'une liste grossit sans que personne ne la relise."
    'doc.agent.confianceHorsContexte' = "{0} dossier(s) approuve(s) en portee utilisateur hors de tout contexte : {1}. Ils sont actifs dans CHAQUE session, quel que soit le projet ouvert."
    'doc.agent.confianceHorsContexteFix' = "Relire cette liste : chaque entree a ete approuvee pour un besoin d'un jour et n'a jamais expire. Ce qui ne sert qu'a un projet se declare dans le .claude/settings.json de ce projet ; la portee utilisateur ne devrait porter que ce qui vaut partout. Une liste qu'on n'a jamais relue n'est plus une decision, c'est un residu."
    # ctx guard
    'guard.action'     = 'retirer {0} dossier(s) approuve(s)'
    'guard.titre'      = 'Dossiers approuves pour les agents, en portee utilisateur'
    'guard.rien'       = 'Rien a corriger : aucun dossier d un contexte n est approuve globalement.'
    'guard.aRetirer'   = '{0} a retirer de la portee utilisateur :'
    'guard.aRetirerLigne' = '{0}  (contexte {1})'
    'guard.pourquoi'   = 'Approuves globalement, ils valent pour TOUTES les sessions -- y compris celles ouvertes dans le dossier d un autre client. Ce dont un projet a besoin se declare dans le .claude/settings.json de ce projet.'
    'guard.aRelire'    = '{0} hors de tout contexte, a relire vous-meme (ce n est pas une regle, c est un arbitrage) :'
    'guard.denyInerte' = 'A savoir : sous Windows, les regles deny sur chemins absolus NE bloquent PAS les ecritures (claude-code#67849, #34741). Cette commande ne fait donc que retirer des approbations -- elle n en pose aucune qui serait inerte.'
    'guard.apercu'     = 'Rien n a ete modifie. Pour appliquer : ctx guard -Apply  (une sauvegarde est ecrite avant toute modification)'
    'guard.ecrit'      = '{1} entree(s) retiree(s) de {0}'
    'guard.sauvegarde' = 'Sauvegarde : {0}'
    'guard.sansPermissions' = "Le fichier '{0}' ne porte pas de bloc permissions : rien a modifier."
    'guard.transformationSuspecte' = 'REFUS d ecrire : la transformation a touche autre chose que les dossiers annonces ({0}). Le fichier est laisse intact.'
    'guard.sauvegardeEchouee' = "La sauvegarde '{0}' n a pas pu etre ecrite. Rien n est modifie : pas de sauvegarde, pas d ecriture."
    'doc.editeur.complet'     = 'profil et extensions par contexte'
    'doc.editeur.profilSeul'  = 'profil par contexte, extensions communes'
    'doc.editeur.methode'     = '{0} ({1})'
    'doc.editeur.limiteFix'   = 'aucun ; limite de cet editeur, pas du module'
    'doc.partage.isole'       = 'magasin partage propre au contexte ({0})'
    'doc.partage.commun'      = "{0} ecrit son stockage d'application -- secrets des extensions, dossiers recents, dossiers approuves -- dans un magasin COMMUN A LA MACHINE. Un chemin de projet client s'y retrouve a cote des projets personnels, et deux contextes s'y deconnectent mutuellement : le magasin est commun mais son chiffrement reste par profil, donc chacun rend illisible l'entree de l'autre."
    'doc.partage.communFix'   = "Refermer cet editeur, puis le rouvrir par le raccourci du contexte (ou 'work <contexte>' puis 'code <projet>'). Le lancement pose desormais --shared-data-dir ; le dossier apparaitra et ce controle passera au vert. Il faudra se reconnecter UNE derniere fois."
    'doc.partage.sansFlag'    = "{0} possede un magasin commun a la machine mais n'expose pas --shared-data-dir : son stockage d'application reste partage entre les contextes."
    # --- identifiants hors cloisonnement ------------------------------------
    # Ces messages doivent tenir seuls : ils sont lus par quelqu'un qui ne sait
    # pas encore qu'un jeton peut vivre ailleurs que la ou `work` le pose.
    'doc.jeton.aucun'         = "{0} : aucun identifiant a l emplacement par defaut"
    'doc.jeton.horsCloisonnement' = "{0} porte un identifiant a son emplacement PAR DEFAUT ({1}), hors de tout contexte. Il repond depuis N IMPORTE QUEL dossier, y compris celui d un client, des qu un appel echappe au PATH : npx, chemin absolu, WSL, ou un outil qui lance la CLI lui-meme."
    'doc.jeton.horsCloisonnementFix' = "Le REVOQUER, pas seulement l effacer : un jeton retire du disque reste valide cote service. Depuis un shell SANS contexte actif : {0}. Verifier ensuite que les sessions cloisonnees sont intactes (work <contexte> -NoCd; ctx)."
    'doc.jeton.compteEtranger' = "{0} connait, a son emplacement PAR DEFAUT ({2}), un compte declare par un AUTRE contexte : {1}. Tout appel qui echappe au PATH lira ce fichier-la, pas celui du contexte -- et repondra donc sous ce compte depuis n importe quel dossier."
    'doc.jeton.compteEtrangerFix' = "Depuis un shell SANS contexte actif : {0} --user <login>. Verifier ensuite que la session cloisonnee de chaque contexte est intacte (work <contexte> -NoCd; gh auth status). Le jeton reste valide cote service tant qu il n est pas revoque."
    # --- ctx doctor -Fix ----------------------------------------------------
    # Le diagnostic connait deja la reponse ; faire retaper la commande est une
    # friction pour rien. Mais il ne repare que ce qu'il peut PROUVER et
    # ANNULER, et il nomme le reste avec la raison -- un silence se lirait
    # "il n'y a plus rien a faire".
    'fix.jsonIncompatible'    = "-Json et -Fix ne vont pas ensemble : -Json sert a un programme, -Fix parle a un humain. Lancer 'ctx doctor -Json' pour l'etat, puis 'ctx doctor -Fix' pour agir."
    'fix.rienAFaire'          = 'Rien a reparer.'
    'fix.titreFaits'          = 'Reparations automatiques :'
    'fix.titreManuels'        = 'A faire a la main :'
    'fix.relancer'            = "Relancer 'ctx doctor' pour verifier."
    'fix.ignore'              = 'ignore'
    'fix.pathIllisible'       = "PATH utilisateur illisible dans le registre."
    'fix.pathRien'            = 'PATH deja propre'
    'fix.pathAbsent'          = "aucun PATH utilisateur dans le registre : rien a nettoyer"
    'fix.sauvegardeSansDossier' = "aucun dossier de sauvegarde disponible : la reparation est annulee, elle ne serait pas reversible"
    'fix.sauvegardeEchec'     = "sauvegarde impossible dans {0} : la reparation est annulee, elle ne serait pas reversible"
    'fix.pathEntrees'         = 'entree(s) de PATH'
    'fix.pathAction'          = 'retirer du PATH utilisateur'
    'fix.pathFait'            = '{0} entree(s) retiree(s) du PATH utilisateur (sauvegarde ecrite)'
    'fix.installateurAbsent'  = 'installateur introuvable : {0}'
    'fix.shimsAction'         = 'relancer pour reposer les shims et la jonction'
    'fix.shimsFait'           = 'shims et jonction reposes'
    'fix.shimsEchec'          = "l'installateur a rendu le code {0}"
    'fix.non.shell'           = "le correctif est 'work <contexte>', qui pose des variables dans le shell APPELANT. Un processus fils ne peut pas ecrire dans l'environnement de son parent -- c'est une propriete du systeme, pas une lacune."
    'fix.non.index'           = "demande de reconstruire l'index Supabase : 'sb-index'. Il interroge le reseau, donc il ne part jamais tout seul."
    'fix.non.admin'           = "modifie le PATH SYSTEME, donc exige les droits administrateur. Un outil qui reclame l'elevation en silence est un outil dont on se mefie ensuite."
    'fix.non.wsl'             = "rien du cote Windows ne peut le fermer : une distribution porte son propre PATH."
    'fix.non.paquet'          = "installer ou desinstaller un binaire n'est jamais le travail d'un diagnostic."

    'doc.garde.sansDossier'   = 'dossier shims introuvable'
    'doc.garde.horsPath'      = 'shims absents du PATH : la protection ne couvre que PowerShell'
    'doc.garde.horsPathFix'   = 'pwsh -File installer-shims.ps1'
    'doc.garde.jonctionAbsente' = 'Le PATH designe le chemin stable, mais la jonction n existe pas : le garde-fou ne se lance plus.'
    'doc.garde.jonctionPerimee' = 'La jonction pointe sur {0}, alors que le module charge est {1}. Le garde-fou tourne sur une version perimee.'
    'doc.garde.jonctionFix'     = 'pwsh -File installer-shims.ps1   (a relancer apres chaque mise a jour du module)'
    'doc.garde.desarme'       = '{0} : garde-fou desarme dans ce shell'
    'doc.garde.masque'        = 'Shim masque : un binaire est resolu avant le notre -- {0}'
    'doc.garde.masqueFix'     = "Le PATH SYSTEME precede toujours le PATH utilisateur, ou l'installateur ecrit. Sortir ce dossier du PATH systeme (droits admin), ou reinstaller l'outil en portee utilisateur -- winget, scoop, npm et les installeurs .msi proposent tous ce choix. Sous PowerShell l'alias du module couvre deja le cas ; depuis bash, non."
    'doc.garde.masqueFixRetrait' = "Ce dossier est DEJA dans le PATH utilisateur, derriere nos shims : le sortir du PATH SYSTEME suffit (droits admin). Rien a reinstaller, le binaire reste joignable, et la manoeuvre s'annule en recollant la ligne. Sous PowerShell l'alias du module couvre deja le cas ; depuis bash, non."
    # Dit ce qui a ete VERIFIE -- les shims sont joignables -- et non ce qui
    # serait agreable a conclure. Qu'ils gagnent reellement la resolution est une
    # autre question, et c'est le controle 'priorite' qui y repond : l'ancienne
    # formule « actif dans tous les shells » s'affichait juste au-dessus d'un
    # PROBLEME disant l'inverse.
    'doc.garde.ok'            = 'shims dans le PATH, donc joignables depuis tous les shells'
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
    'editeur.partage.isole'   = 'isole'
    'editeur.partage.commun'  = 'COMMUN'
    'editeur.partage.sansObjet' = 'sans objet'
    'editeur.sansUserDataDir' = "{0} n'expose pas --user-data-dir : ses sessions restent communes a tous les contextes."
}
