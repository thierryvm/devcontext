# English strings for DevContext, and the fallback for every other language.
#
# One key per message, dotted: <command>.<subject>.
#
# Substitutions go through {0}, {1}… and the -f operator, never through
# concatenation: a translation must be able to REORDER what it inserts. German
# puts its verb last, French its adjective after the noun; a sentence assembled
# from fragments survives neither.
#
# These are printed to a terminal whose encoding is unknown, so they stay ASCII.
# An accented character becomes a replacement glyph under git-bash, and a
# refusal message is the one output that must read correctly on a machine we
# know nothing about.

@{
    # --- ctx: no context created yet ----------------------------------------
    'ctx.vide.titre'         = 'No context on this machine.'
    'ctx.vide.racine'        = 'Root: {0}'
    'ctx.vide.explication1'  = 'A context is one complete identity: git email, SSH key, GitHub account,'
    'ctx.vide.explication2'  = 'Vercel session, Supabase tokens. One per working life.'
    'ctx.vide.creer'         = 'To create one:'
    'ctx.vide.exemple'       = 'ctx-new -Name personal -Email you@example.com -Root C:\dev\personal'
    'ctx.vide.racineAilleurs' = 'To keep contexts elsewhere:  ctx-root <folder>'
    'ctx.vide.doctor'        = 'For a survey of this machine: ctx-doctor'

    # --- ctx: verdict -------------------------------------------------------
    'ctx.actif'              = 'Active context : {0}'
    'ctx.aucun'              = 'Active context : NONE'
    'ctx.dossier'            = 'Folder         : {0}'
    'ctx.git'                = 'git            : {0}'
    'ctx.gh'                 = 'gh             : {0}'
    'ctx.ghNonAuth'          = '(not authenticated)'
    'ctx.vercel'             = 'vercel         : {0}'
    'ctx.supabase'           = 'supabase       : {0}'
    'ctx.remote'             = 'remote (push)  : {0}'
    'ctx.go'                 = 'GO - folder, identity and account agree.'
    'ctx.noGo'               = 'NO-GO'
    'ctx.correctif'          = 'Fix: {0}'
    'ctx.detail'             = 'Full detail: ctx-doctor'

    'ctx.pb.dossierSansActif' = "This folder belongs to context '{0}', and no context is active."
    'ctx.pb.dossierAutre'     = "This folder belongs to context '{0}', but '{1}' is active."
    'ctx.pb.horsRacine'       = 'Outside the active context root ({0}).'
    'ctx.pb.compteGitHub'     = "Active GitHub account '{0}' - this context expects '{1}'."
    'ctx.pb.sansLogin'        = "This context has no 'github.login' in its manifest: the active account can only be reported, never verified."
    'ctx.pb.ghConfigDir'      = "GH_CONFIG_DIR is unset: 'gh' uses the machine-wide config, therefore the last account you logged into."
    'ctx.pb.supabaseIndex'    = "This folder's Supabase project is missing from the index. Run 'sb-index'."
    'ctx.pb.supabaseCle'      = "SUPABASE_ACCESS_TOKEN carries key '{0}' while this project expects '{1}'. Fix with 'work {2} -NoCd'."

    'ctx.supabase.aucun'      = 'no token'
    'ctx.supabase.charge'     = 'token loaded'
    'ctx.supabase.chargeCle'  = 'token loaded ({0})'

    # --- ctx-list -----------------------------------------------------------
    'liste.vide.titre'        = 'No context.'
    'liste.vide.racine'       = 'Root: {0}'
    'liste.vide.racineAbsente' = '  (folder missing)'
    'liste.vide.creer'        = 'Create one:'
    'liste.vide.racineAilleurs' = 'Change where they are kept: ctx-root <folder>'

    # --- ctx-root -----------------------------------------------------------
    'racine.titre'            = 'Context root: {0}'
    'racine.source'           = 'source   : {0}'
    'racine.source.env'       = 'DEVCTX_LANG variable'
    'racine.source.variable'  = 'DEVCTX_ROOT variable'
    'racine.source.reglage'   = 'setting {0}'
    'racine.source.defaut'    = 'system default'
    'racine.existe'           = 'exists   : {0}'
    'racine.contextes'        = 'contexts : {0}'
    'racine.changer'          = 'To change it: ctx-root <folder>'
    'racine.ecrit'            = 'setting written to: {0}'
    'racine.restes'           = '{0} context(s) remain at the previous location:'
    'racine.restesRien'       = 'Nothing was moved. They hold SSH keys; copying them is'
    'racine.restesDecision'   = 'your decision, not a configuration command''s.'
    'racine.varPrime'         = 'DEVCTX_ROOT is set in this shell ({0}) and overrides this setting.'

    # --- production guard ----------------------------------------------------
    'garde.refuse'            = 'REFUSED - DevContext production guard'
    'garde.base'              = 'Target database : {0}'
    'garde.raison'            = 'Reason          : {0}'
    'garde.nomInconnu'        = '(name unknown)'
    'garde.derogation'        = 'If you really mean this command, for this one only:'
    'garde.jamaisProfil1'     = 'Never put that in $PROFILE: it removes the guard while leaving'
    'garde.jamaisProfil2'     = 'the impression of having it.'
    'garde.raison.dbUrl'      = "'{0}' carries a --db-url pointing at a database that cannot be identified, and this context holds a production project."
    'garde.raison.reset'      = "'{0}' destroys and recreates the database. Refused on a production project."
    'garde.raison.branche'    = "'{0}' towards a production project from branch '{1}' instead of '{2}'."
    'garde.introuvable'       = '{0} not found in PATH (outside the shims).'

    # --- ctx doctor ------------------------------------------------------------
    'doc.bin.absent'          = 'not found in PATH'
    'doc.bin.shimSeul'        = 'only the DevContext shim answers: the real binary is missing'
    'doc.bin.une'             = '{0} - {1}'
    'doc.bin.memeVersion'     = '{0} installations, same version ({1})'
    'doc.bin.versionsDiff'    = '{0} installations of differing versions: {1}'
    'doc.bin.correctifDiff'   = 'keep only one - otherwise the version depends on the calling shell'
    'doc.git.horsContexte'    = 'this folder belongs to no context'
    'doc.git.sansEmail'       = 'no user.email resolved'
    'doc.git.sansEmailFix'    = 'check the includeIf in ~/.gitconfig'
    'doc.git.mauvaisEmail'    = '{0} instead of {1} (set by {2})'
    'doc.git.mauvaisEmailFix' = 'a user.email hardcoded in .git/config overrides the includeIf'
    'doc.git.pasDepot'        = 'not a git repository'
    'doc.remote.aucun'        = 'no origin remote'
    'doc.remote.login'        = 'the remote URL carries a login: the insteadOf rule does not match it'
    'doc.remote.loginFix'     = 'git remote set-url origin https://github.com/<org>/<repo>.git'
    'doc.remote.sansAlias'    = '{0} does not use the {1} SSH key'
    'doc.remote.sansAliasFix' = "check this context's insteadOf rule"
    'doc.path.aucune'         = 'none'
    'doc.path.vides'          = '{0} empty entr(y/ies): the current directory is in the search path'
    'doc.path.videsFix'       = 'remove the ;; from the user PATH'
    'doc.mcp.enClair'         = 'secret in clear text in the configuration ({0}): {1}'
    'doc.mcp.enClairFix'      = 'replace with ${VARIABLE_NAME} - work already exports the right token'
    'doc.mcp.distant'         = 'remote server ({0}): authenticated by OAuth, therefore bound to the connected account, not to the folder'
    'doc.mcp.distantFix'      = 'a local stdio server taking its token from the environment follows the context'
    'doc.mcp.stdio'           = 'stdio ({0})'
    'doc.mcp.aucun'           = 'no MCP server declared for this folder'
    'doc.ctx.horsContexte'    = 'this folder belongs to no context'
    'doc.ctx.sansActif'       = "folder of context '{0}', but no context is active in this shell"
    'doc.ctx.autreActif'      = "folder of context '{0}', active identity '{1}'"
    'doc.gh.sansConfigDir'    = 'GH_CONFIG_DIR is unset: gh uses the machine-wide config, therefore the last account logged into'
    'doc.gh.autreContexte'    = 'GH_CONFIG_DIR points at another context'
    'doc.gh.dedie'            = 'config dedicated to this context'
    'doc.sb.horsIndex'        = 'project is linked but missing from the index, or its environment is untagged'
    'doc.sb.prod'             = 'this folder targets a PRODUCTION project'
    'doc.sb.prodFix'          = 'db reset is refused here, and db push outside the default branch too'
    'doc.sb.mauvaiseCle'      = 'the loaded token is not the one this project expects'
    'doc.sb.sansJeton'        = 'no token loaded in this shell'
    'doc.vercel.sansSession'  = 'Vercel project linked, but no context session loaded'
    'doc.vercel.ok'           = 'project linked, session dedicated to the context'
    'doc.editeur.complet'     = 'profile and extensions per context'
    'doc.editeur.profilSeul'  = 'profile per context, extensions shared'
    'doc.editeur.methode'     = '{0} ({1})'
    'doc.editeur.limiteFix'   = 'none; a limit of this editor, not of the module'
    'doc.garde.sansDossier'   = 'shims folder not found'
    'doc.garde.horsPath'      = 'shims are absent from PATH: the protection covers PowerShell only'
    'doc.garde.horsPathFix'   = 'pwsh -File installer-shims.ps1'
    'doc.garde.desarme'       = 'DEVCTX_ALLOW_PROD=1: the guard is disarmed in this shell'
    'doc.garde.desarmeFix'    = 'Remove-Item Env:DEVCTX_ALLOW_PROD'
    'doc.garde.ok'            = 'active in every shell'
    'doc.wsl.distros'         = '{0} distribution(s) installed ({1}): the Windows shim is not on them, the guard does not cover those shells'
    'doc.wsl.fix'             = 'install the Supabase CLI there separately, or do not target a production project from WSL'

    'work.contexte'           = 'CONTEXT : {0}'
    'work.compte'             = 'Account : {0}'
    'work.secrets'            = 'Secrets : {0}'
    'work.secretsAucun'       = 'none loaded'

    'vercel.token'            = 'token loaded'
    'vercel.session'          = 'dedicated session'
    'vercel.aucune'           = 'no session'

    # --- editors --------------------------------------------------------------
    'editeur.profil.isole'    = 'isolated'
    'editeur.profil.partage'  = 'SHARED'
    'editeur.ext.isolees'     = 'isolated'
    'editeur.ext.partagees'   = 'shared'
    'editeur.sansUserDataDir' = '{0} does not expose --user-data-dir: its sessions stay common to every context.'
}
