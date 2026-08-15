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
