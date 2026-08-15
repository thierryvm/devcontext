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
