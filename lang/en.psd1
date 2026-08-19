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
    # --- ctx init -----------------------------------------------------------
    # The first command, and where adoption is won or lost. It GUIDES: it asks
    # before each change, and every step it does not perform is printed as the
    # exact command that performs it.
    'init.titre'              = 'Setting up DevContext on this machine'
    'init.etape.coffre'       = 'Secret vault (SecretManagement + SecretStore)'
    'init.etape.shims'        = 'Guards reachable from every shell'
    'init.etape.contexte'     = 'At least one working context'
    'init.racine'             = 'Contexts live in: {0}'
    'init.racineChanger'      = 'To keep them elsewhere: ctx root <folder>'
    'init.rienAFaire'         = 'Everything is in place. Nothing to do.'
    'init.suite'              = 'For the full state of this machine: ctx doctor'
    'init.nonInteractif'      = 'Input is redirected, so no question can be asked here. This is what is left to run, in order.'
    'init.manuel'             = 'Run this yourself (installing a module is a new dependency):'
    'init.action'             = 'set up'
    'init.contexteProposition' = 'Command pre-filled from git and gh -- read it, then run it:'

    # --- ctx: subcommands ---------------------------------------------------
    # `ctx-doctor` and `ctx doctor` are the same thing. The second is what
    # fingers type, because git, docker, gh and npm all use it; the first
    # tab-completes under PowerShell.
    'ctx.sc.inconnue'        = "Unknown subcommand: '{0}'"
    'ctx.sc.titre'           = 'Available commands:'
    'ctx.sc.verdict'         = 'do folder, identity and account agree?'
    'ctx.sc.tiret'           = 'Each also exists hyphenated: ctx-doctor, ctx-list, ...'
    'ctx.sc.aide.check'      = 'same verdict, but throws (scripts, git hooks)'
    'ctx.sc.aide.doctor'     = 'state of this machine: tools, accounts, guards'
    'ctx.sc.aide.editors'    = 'which editors can isolate their profile'
    'ctx.sc.aide.end'        = 'close the active context work session'
    'ctx.sc.aide.guard'      = 'folders trusted for agents: what can they actually reach'
    'ctx.sc.aide.init'       = 'set DevContext up on this machine'
    'ctx.sc.aide.list'       = 'list the contexts on this machine'
    'ctx.sc.aide.mcp'        = 'write the current project MCP servers'
    'ctx.sc.aide.new'        = 'create a context'
    'ctx.sc.aide.off'        = 'deactivate the context in this shell'
    'ctx.sc.aide.root'       = 'change where contexts are stored'
    'ctx.sc.aide.sb'         = 'which Supabase project on which account'
    'ctx.sc.aide.shortcut'   = 'create a Desktop shortcut to a project'
    'ctx.sc.aide.who'        = 'which context owns this folder'

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
    'ctx.ghNonVerifie'       = '(not verified - the gh CLI did not answer)'
    'ctx.vercel'             = 'vercel         : {0}'
    'ctx.supabase'           = 'supabase       : {0}'
    'ctx.remote'             = 'remote (push)  : {0}'
    'ctx.go'                 = 'GO - folder, identity and account agree.'
    'ctx.goSansCompte'       = 'GO - folder and identity agree. GitHub account not verified, see above.'
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
    'garde.refuseAlias'       = 'Command refused by the DevContext production guard.'

    # --- gh: identity --------------------------------------------------------
    'gh.refuse'               = 'REFUSED - DevContext GitHub identity'
    'gh.correctif'            = 'To get back on the right identity:'
    'gh.derogation'           = 'If you really mean this command, for this one only:'
    'gh.raison.autreContexte' = "GH_CONFIG_DIR points at a context other than '{0}', which owns this folder. This command would write to GitHub under the wrong account."
    'gh.avert.autreContexte'  = "DevContext: reading under an identity that is not '{0}'."
    'gh.avert.authRedirige'   = "DevContext: gh auth applies to context '{0}'."
    'gh.raison.sansConfig'    = "Context '{0}' has no gh account yet. This command would run under the machine-wide account, that is, the last one logged into."
    'gh.refuseAlias'          = 'Command refused by the DevContext GitHub identity guard.'

    # --- vercel --------------------------------------------------------------
    'vercel.refuse'           = 'REFUSED - DevContext production guard (vercel)'
    'vercel.derogation'       = 'If you really mean this command, for this one only:'
    'vercel.raison.envRm'     = "'env rm' targets the production environment."
    'vercel.raison.prodBranche' = "Production deployment from branch '{0}' instead of '{1}'."
    'vercel.avert.session'    = "DevContext: the vercel session applies to context '{0}'."
    'vercel.refuseAlias'      = 'Command refused by the DevContext production guard.'

    # --- vault and manifest -----------------------------------------------------
    'vault.absent'            = "SecretManagement module missing. Install it:`n  Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser"
    'vault.creation'          = "Creating vault '{0}'..."
    'manifeste.introuvable'   = "Context '{0}' not found ({1}). Run 'ctx-list' to see the existing ones."

    # --- ctx-off ---------------------------------------------------------------
    'off.aucunActif'          = 'No active context.'
    'off.manquant1'           = "Context '{0}' does not exist. While it is missing, the personal"
    'off.manquant2'           = 'identity falls back to the machine-wide config - that of the last'
    'off.manquant3'           = 'account logged into. This is the one hole in the arrangement.'

    # --- code-ctx --------------------------------------------------------------
    'code.aucunActif'         = "No active context. Run 'work <context>' first, or 'code-ctx <context>'."
    'code.editeurInconnu'     = "'{0}' not found on this machine. 'ctx-editors' lists what was detected. For VS Code: Ctrl+Shift+P > 'Shell Command: Install code command in PATH'."
    'code.sansCli'            = "'{0}' is installed but exposes no command-line entry point. DevContext cannot launch it."
    'code.ouverture'          = '{0} [{1}] -> {2}'
    'code.repliSynchrone'     = "No executable found above '{0}'. {1} is launched in the foreground: this window stays open for as long as it runs. 'ctx-editors' lists what was detected."

    # --- web-ctx ---------------------------------------------------------------
    'web.aucunActif'          = 'No active context.'
    'web.sansProfil'          = "No 'chromeProfile' in context.json for '{0}'. Create the profile in Chrome, then read its folder from chrome://version (Profile Path)."
    'web.chromeAbsent'        = 'chrome.exe not found.'

    # --- wrapped binaries --------------------------------------------------------
    'bin.vercelAbsent'        = 'vercel not found in PATH.'
    'bin.ghAbsent'            = 'gh not found in PATH (outside the shims).'
    'bin.supabaseAbsent'      = 'supabase not found in PATH (outside the shims).'
    'bin.supabaseEcarte'      = 'supabase was found only in a directory recognised as a DevContext shims directory: {0}. A directory counts as one when it carries both editor.ps1 and supabase.ps1. If that is a real Supabase install, rename or remove those two files. Do NOT call the binary directly to work around this: the production guard would no longer apply.'

    # --- sb-index ---------------------------------------------------------------
    'index.aucunActif'        = "No active context. Run 'work <context>' first, or 'sb-index <context>'."
    'index.ancienIllisible'   = 'Existing index unreadable; it will be rebuilt without the manual tags.'
    'index.reponseIllisible'  = '{0}: unreadable response (token revoked or expired?). Skipped.'
    'index.ecrit'             = 'index written: {0}'

    # --- ctx-sb -----------------------------------------------------------------
    'sb.aucunActif'           = "No active context. Run 'work <context>' first, or 'ctx-sb <context>'."
    'sb.sansIndex'            = "No Supabase index for '{0}'. Run 'sb-index'."
    'sb.sansIndexAvert'       = "No Supabase index for '{0}'. Run 'sb-index'."
    'sb.projetActif'          = '[{0} -> {1}]'

    # --- ctx-new ----------------------------------------------------------------
    'new.nomInvalide'         = 'Invalid context name: lowercase letters, digits and hyphens only.'
    'new.existeDeja'          = "Context '{0}' already exists ({1})."
    'new.racinePrise'         = "Root '{0}' already belongs to context '{1}'."
    'new.cleGeneration'       = 'Generating the context SSH key (a passphrase is recommended):'
    'new.cleSansGeneration'   = 'SSH key NOT generated (-NoKey).'
    'new.cleCommande'         = "ssh-keygen -t ed25519 -C '{0}' -f '{1}'"
    'new.cleImpossible'       = "Cannot generate the SSH key: standard input is redirected, and ssh-keygen would wait for a passphrase forever.`n  - in an interactive terminal: run the same command again`n  - in a script or CI         : add -NoKey, and generate the key later`nContext '{0}' was created: {1}"
    'new.jetonsIgnores'       = 'Token entry skipped (input is not interactive).'
    'new.jetonsPlusTard'      = 'Set them later, one at a time:'
    'new.jetonsCles'          = 'keys: {0}'
    'new.jetonsSaisie'        = 'Context tokens (Enter to skip)'
    'new.cree'                = "Context '{0}' created."
    'new.resteAFaire'         = 'Left to do, once:'
    'new.etape1'              = '1. Add the public key to the GitHub account {0}:'
    'new.etape1Sans'          = '1. Generate the SSH key, then add it to the GitHub account {0}:'
    'new.etape2'              = '2. work {0} ; gh auth login   (config isolated in {1})'
    'new.etape3'              = "3. Create the dedicated Chrome profile, then set 'chromeProfile' in context.json"
    'new.etape4'              = '4. code-ctx {0}   (a blank editor: sign in with the client account)'
    'new.etape5a'             = "5. Set 'github.login' in context.json - without it, 'ctx' can only"
    'new.etape5b'             = 'report the active account, never verify that it is the right one.'

    # --- ctx-end ----------------------------------------------------------------
    'end.titre'               = 'HANDOVER - {0} ({1})'
    'end.avantPurge'          = 'To check before purging:'
    'end.item1'               = '[ ] Mailbox 2FA moved to the client (not your phone)'
    'end.item2'               = '[ ] Recovery number and backup email removed from the account'
    'end.item3'               = "[ ] Payment method removed from Vercel and Supabase, replaced by the client's"
    'end.item4'               = '[ ] Your personal SSH key absent from the deploy keys of every repository'
    'end.item5'               = '[ ] Tokens revoked at the provider (deleting them from the vault does not revoke them):'
    'end.item5Urls'           = 'github.com/settings/tokens  |  vercel.com/account/tokens  |  supabase.com/dashboard/account/tokens'
    'end.item6'               = '[ ] Mailbox password changed and handed to the client'
    'end.item7'               = '[ ] Repository backup archived on your side if the contract requires it'
    'end.relancer'            = 'Run again with -Purge to delete the secrets and the context folder.'
    'end.actifIci'            = "Context '{0}' is active in this terminal. Run 'ctx-off' first - purging from under yourself leaves secrets loaded in memory."
    'end.supprime'            = 'Secrets and folder deleted.'

    'off.exemple'             = 'ctx-new {0} -Label ''Personal'' -Email ''<your-email>'' '
    'off.exempleSuite'        = "-Root '{0}' -GithubLogin '<your-login>'"
    'new.jetonsCommande'      = 'Set-Secret -Vault DevContext -Name ''devctx/{0}/<key>'' -SecureStringSecret $s'
    'end.sshManuel1'          = "Remove the 'Host github-{0}' block by hand from {1}"
    'end.sshManuel2'          = 'and the matching includeIf block from {0}.'
    'end.projetIntact'        = 'The project folder {0} was not touched.'
    'ctx.incoherent'          = 'Inconsistent context - command interrupted.'

    # --- ctx-mcp -----------------------------------------------------------------
    'mcp.prodLectureSeule'    = 'Production project: the server stays read-only despite -Ecriture.'
    'mcp.rienADeclarer'       = 'Nothing to declare for this folder.'
    'mcp.ignore'              = 'skipped: {0}'
    'mcp.aucunClient'         = 'No MCP client detected in this folder. Pass -Client to create one: {0}'
    'mcp.illisible'           = 'existing {0} is unreadable: {1}. Fix or move it before regenerating.'
    'mcp.fichier'             = '{0} - {1}'
    'mcp.ajoutes'             = 'added    : {0}'
    'mcp.remplaces'           = 'replaced : {0}'
    'mcp.conserves'           = 'kept     : {0} (-Force to replace them)'
    'mcp.clientInconnu'       = "Unknown MCP client: '{0}'. Known: {1}"

    # --- ctx-shortcut --------------------------------------------------------------
    'rac.dossierAbsent'       = 'Folder not found: {0}'
    'rac.horsContexte'        = "No context owns '{0}'. A shortcut that isolates nothing is exactly the one this replaces. Run 'ctx-list' to see the contexts."
    'rac.aucunEditeur'        = "No wrappable editor found{0}. 'ctx-editors' lists what was detected."
    'rac.sousLeNom'           = " under the name '{0}'"
    'rac.lanceurAbsent'       = 'Launcher missing: {0}. Incomplete repository.'
    'rac.existeDeja'          = 'The shortcut already exists: {0}. Use -Force to overwrite it.'
    'rac.ecrit'               = 'Shortcut written: {0}'
    'rac.projet'              = 'project : {0}'
    'rac.contexte'            = 'context : {0}'
    'rac.editeur'             = 'editor  : {0} (through the shim, never by absolute path)'

    # --- launcher -------------------------------------------------------------------
    'lanceur.go'              = 'GO'
    'lanceur.fermer'          = 'Enter to close'
    'lanceur.moduleAbsent'    = 'DevContext module not found: {0}'
    'lanceur.dossierAbsent'   = 'Folder not found: {0}'
    'lanceur.horsContexte'    = "No context owns '{0}'. Run 'ctx-list' to see the contexts, or pass -Context explicitly."
    'lanceur.noGo'            = 'NO-GO - the editor was not launched. Fix this before pushing or deploying.'

    'rac.doc.isole'           = 'isolated profile ({0})'
    'rac.doc.dansContexte'    = 'context {0}'
    'rac.doc.profilDedie'     = 'dedicated profile'
    'rac.doc.partage'         = "opens a project of context '{0}' on the SHARED profile: its GitHub, Copilot and marketplace sessions are common to every context"
    'rac.doc.sansDossier'     = 'launches an editor with no folder: it will reopen whatever the shared profile had last'
    'rac.doc.sansDossierFix'  = "target 'code' rather than the absolute path to the executable, or go through ctx-shortcut"
    'rac.doc.regroupes'       = '{0} shortcut(s) opening an editor with no folder ({1}): they land on the shared profile'

    # --- installer -------------------------------------------------------------
    'inst.broadcast'          = 'Could not broadcast WM_SETTINGCHANGE: {0}'
    'inst.broadcastSuite'     = 'PATH is correct in the registry. Applications already running will only see it after a restart.'
    'inst.shimsManquants'     = 'Missing shim files: {0}. Incomplete repository, installation aborted.'
    'inst.moduleIllisible'    = 'DevContext module unreadable, editor entry points skipped: {0}'
    'inst.actif'              = 'SHIM ACTIVE in the user PATH'
    'inst.absent'             = 'SHIM ABSENT from the user PATH'
    'inst.dossier'            = 'folder  : {0}'
    'inst.registre'           = 'registry: HKCU\Environment\Path ({0})'
    'inst.fichiers'           = 'Shim files:'
    'inst.pointsEntree'       = 'Generated editor entry points:'
    'inst.aucun'              = '(none)'
    'inst.aucune'             = '(none)'
    'inst.resolution'         = 'Resolution of "supabase" in THIS process:'
    'inst.poseNonActif'       = 'Written to the registry, but not active in this terminal yet.'
    'inst.terminalNeuf'       = 'Open a fresh terminal.'
    'inst.retire'             = 'removed: {0}'
    'inst.jonction'           = 'Junction (stable path, no version number):'
    'inst.jonctionAbsente'    = 'missing -- run installer-shims.ps1 again'
    'inst.jonctionAilleurs'   = 'does NOT point at this module ({0}) -- run installer-shims.ps1 again'
    'inst.jonctionPosee'      = 'Junction created.'
    'inst.jonctionRetiree'    = 'Junction removed.'
    'inst.ancienneEntree'     = 'Old entry still in PATH: {0} -- run installer-shims.ps1 again'
    'inst.ancienneRetiree'    = 'Old entry removed from PATH: {0}'
    'inst.dejaAbsent'         = 'Already absent from PATH. Nothing to do.'
    'inst.retireDuPath'       = 'Shim removed from the user PATH.'
    'inst.ancienPath'         = 'Terminals already open keep the old PATH.'
    'inst.editeursEnrobes'    = 'Wrapped editors (profile per context):'
    'inst.aucunEditeur'       = 'No wrappable editor found.'
    'inst.aucunEditeurFix'    = 'ctx-editors says what was detected, and why.'
    'inst.pathDejaPose'       = 'PATH already set. Nothing to do on that side.'
    'inst.pose'               = 'Shim placed at the front of the user PATH.'
    'inst.typePreserve'       = 'registry type preserved: {0}'
    'inst.sauvegarde'         = 'previous PATH saved to: {0}'
    'inst.pathLong'           = 'The user PATH is {0} characters long. Some older tools truncate beyond 2047.'
    'inst.ancienPathNeuf'     = 'Terminals already open keep the old PATH - open a fresh one.'
    'inst.profilSeul'         = 'profile only'
    'inst.profilEtExt'        = 'profile + extensions'

    # --- VS Code URI router --------------------------------------------------------
    'uri.profilDefaut'        = 'default profile'
    'uri.cible'               = 'target: {0}'
    'uri.cle'                 = 'key   : {0}'
    'uri.valeur'              = 'value : {0}'
    'uri.actif'               = 'ROUTER ACTIVE'
    'uri.verrouActif'         = 'LOCK ACTIVE - VS Code cannot take the key back'
    'uri.verrouAbsent'        = 'LOCK ABSENT - the key will be overwritten the next time VS Code starts'
    'uri.origine'             = 'original handler (bug present) - run again without -Verifier'
    'uri.inconnue'            = 'unknown value - inspect before overwriting'
    'uri.restaure'            = 'Lock removed, original handler restored.'
    'uri.introuvable'         = 'Not found: {0}'
    'uri.dejaEnPlace'         = 'Already in place and locked, nothing to do.'
    'uri.valeurConservee'     = 'Unexpected previous value, kept in:'
    'uri.installe'            = 'Router installed and key locked.'
    'uri.verifier'            = 'Check with: .\installer-uri-router.ps1 -Verifier'
    'uri.codeAbsent'          = 'Code.exe not found: {0}'

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
    'doc.git.emailEnDur'      = '{0} -- but set in this repository .git/config, not by the context rule'
    'doc.git.emailEnDurFix'   = "The value is right; the REASON is fragile. A user.email written in .git/config overrides the includeIf, so this repository is protected by a hand-copied line rather than by the mechanism. Were it wrong, nothing would catch it. To hand control back to the folder rule: git config --unset user.email (and --unset user.name)."
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
    'doc.editeur.connexions'  = 'one profile per context = one secret store per context: the GitHub / Copilot sign-in has to be done ONCE in each context, and signing in to one no longer signs you out of the other'
    'doc.editeur.compteEtranger' = "the '{0}' context profile keeps traces of account {1}, which belongs to ANOTHER context (extension authorisations, usage counters). This profile only expects '{2}'. That may be an ACTIVE session -- Copilot, the Pull Request extension and GitLens would then act as that account -- or a LEFTOVER: VS Code keeps these records after a sign-out, and they would re-grant access without asking on the next sign-in."
    'doc.editeur.compteEtrangerFix' = "The window's Accounts menu is the authority here, not this diagnostic: the file does not say whether a session is open. Open a window of that context > Accounts menu (bottom left). If the foreign account is not listed, there is NOTHING to do. If it is, sign out -- and if it is there for Settings Sync, switch Sync to the MICROSOFT account instead: VS Code accepts it too, and the GitHub account goes back to being one per context."
    # These four TEACH as much as they report. Someone reading "trusted folder
    # outside any context" without knowing what it costs closes the report, so
    # the finding names the consequence and the fix states the rule rather than
    # only the gesture.
    'doc.agent.confianceEtrangere' = "an agent opened here can also write into the '{1}' context: {2} (trusted at {3} scope). You are working in '{0}'. DevContext partitions IDENTITY, never writes: nothing stops a file from this project landing in another client's tree."
    'doc.agent.confianceEtrangereFix' = "Remove those folders from permissions.additionalDirectories in the user-scope file, then grant them case by case in the .claude/settings.json OF THE PROJECT that needs them. The rule: a one-off approval recorded globally applies to every future session, including another client's. That is how such a list grows without anyone ever rereading it."
    'doc.agent.confianceHorsContexte' = "{0} folder(s) trusted at user scope and outside every context: {1}. They are active in EVERY session, whichever project is open."
    'doc.agent.confianceHorsContexteFix' = "Reread this list: each entry was approved for one day's need and never expired. What serves one project belongs in that project's .claude/settings.json; user scope should carry only what is true everywhere. A list nobody has reread is no longer a decision, it is a residue."
    # ctx guard
    'guard.action'     = 'remove {0} trusted folder(s)'
    'guard.titre'      = 'Folders trusted for agents, at user scope'
    'guard.rien'       = 'Nothing to correct: no context folder is trusted globally.'
    'guard.aRetirer'   = '{0} to remove from user scope:'
    'guard.aRetirerLigne' = '{0}  ({1} context)'
    'guard.pourquoi'   = 'Trusted globally, they apply to EVERY session -- including one opened in another client folder. What a project needs belongs in that project .claude/settings.json.'
    'guard.aRelire'    = '{0} outside every context, for you to review (this is a judgement call, not a rule):'
    'guard.denyInerte' = 'Worth knowing: on Windows, deny rules on absolute paths do NOT block writes (claude-code#67849, #34741). So this command only removes approvals -- it adds none that would be inert.'
    'guard.apercu'     = 'Nothing was changed. To apply: ctx guard -Apply  (a backup is written before any change)'
    'guard.ecrit'      = '{1} entry(ies) removed from {0}'
    'guard.sauvegarde' = 'Backup: {0}'
    'guard.sansPermissions' = "File '{0}' carries no permissions block: nothing to change."
    'guard.transformationSuspecte' = 'REFUSING to write: the transformation touched something other than the announced folders ({0}). The file is left untouched.'
    'guard.sauvegardeEchouee' = "Backup '{0}' could not be written. Nothing is changed: no backup, no write."
    'doc.editeur.complet'     = 'profile and extensions per context'
    'doc.editeur.profilSeul'  = 'profile per context, extensions shared'
    'doc.editeur.methode'     = '{0} ({1})'
    'doc.editeur.limiteFix'   = 'none; a limit of this editor, not of the module'
    'doc.partage.isole'       = 'shared store belongs to this context ({0})'
    'doc.partage.commun'      = "{0} writes its application storage -- extension secrets, recent folders, trusted folders -- to a MACHINE-WIDE store. A client project path ends up next to personal ones there, and two contexts sign each other out: the store is shared but its encryption stays per profile, so each one makes the other's entry unreadable."
    'doc.partage.communFix'   = "Close this editor, then reopen it from the context shortcut (or 'work <context>' then 'code <project>'). Launching now passes --shared-data-dir; the folder will appear and this check turns green. One last sign-in will be needed."
    'doc.partage.sansFlag'    = "{0} has a machine-wide store but exposes no --shared-data-dir: its application storage stays shared across contexts."
    # --- ctx doctor -Fix ----------------------------------------------------
    # The diagnostic already knows the answer; making the human retype it is
    # friction for nothing. But it repairs only what it can PROVE and UNDO, and
    # names everything else with the reason -- silence would read as "nothing
    # left to do".
    'fix.jsonIncompatible'    = "-Json and -Fix do not go together: -Json is for a program, -Fix talks to a human. Run 'ctx doctor -Json' for the state, then 'ctx doctor -Fix' to act."
    'fix.rienAFaire'          = 'Nothing to repair.'
    'fix.titreFaits'          = 'Automatic repairs:'
    'fix.titreManuels'        = 'Left to do by hand:'
    'fix.relancer'            = "Run 'ctx doctor' again to check."
    'fix.ignore'              = 'skipped'
    'fix.pathIllisible'       = 'User PATH not readable in the registry.'
    'fix.pathRien'            = 'PATH already clean'
    'fix.pathAbsent'          = 'no user PATH in the registry: nothing to clean'
    'fix.sauvegardeSansDossier' = 'no backup folder available: the repair is cancelled, it would not be reversible'
    'fix.sauvegardeEchec'     = 'cannot write the backup to {0}: the repair is cancelled, it would not be reversible'
    'fix.pathEntrees'         = 'PATH entry(ies)'
    'fix.pathAction'          = 'remove from the user PATH'
    'fix.pathFait'            = '{0} entry(ies) removed from the user PATH (backup written)'
    'fix.installateurAbsent'  = 'installer not found: {0}'
    'fix.shimsAction'         = 'run again to lay the shims and the junction'
    'fix.shimsFait'           = 'shims and junction laid again'
    'fix.shimsEchec'          = 'the installer returned code {0}'
    'fix.non.shell'           = "the fix is 'work <context>', which sets variables in the CALLING shell. A child process cannot write into its parent's environment -- that is an OS property, not a missing feature."
    'fix.non.index'           = "needs the Supabase index rebuilt: 'sb-index'. It reaches the network, so it never runs on its own."
    'fix.non.admin'           = 'changes the SYSTEM PATH, so it needs administrator rights. A tool that silently asks for elevation is a tool people stop trusting.'
    'fix.non.wsl'             = 'nothing on the Windows side can close it: a distribution carries its own PATH.'
    'fix.non.paquet'          = 'installing or uninstalling a binary is never a diagnostic job.'

    'doc.garde.sansDossier'   = 'shims folder not found'
    'doc.garde.horsPath'      = 'shims are absent from PATH: the protection covers PowerShell only'
    'doc.garde.horsPathFix'   = 'pwsh -File installer-shims.ps1'
    'doc.garde.jonctionAbsente' = 'PATH points at the stable path, but the junction does not exist: the guard no longer runs.'
    'doc.garde.jonctionPerimee' = 'The junction points at {0}, while the loaded module is {1}. The guard is running a stale version.'
    'doc.garde.jonctionFix'     = 'pwsh -File installer-shims.ps1   (run again after every module update)'
    'doc.garde.desarme'       = '{0}: guard disarmed in this shell'
    'doc.garde.masque'        = 'Shim shadowed: another binary resolves before ours -- {0}'
    'doc.garde.masqueFix'     = 'The SYSTEM PATH always precedes the user PATH, which is where the installer writes. Take that directory out of the system PATH (admin rights), or reinstall the tool at user scope -- winget, scoop, npm and .msi installers all offer that choice. Under PowerShell the module alias already covers this; from bash it does not.'
    'doc.garde.masqueFixRetrait' = "That directory is ALREADY in the user PATH, behind our shims: taking it out of the SYSTEM PATH is enough (admin rights). Nothing to reinstall, the binary stays reachable, and the change undoes by pasting the line back. Under PowerShell the module alias already covers this; from bash it does not."
    'doc.garde.ok'            = 'shims in PATH, therefore reachable from every shell'
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
    'editeur.partage.isole'   = 'isolated'
    'editeur.partage.commun'  = 'MACHINE-WIDE'
    'editeur.partage.sansObjet' = 'n/a'
    'editeur.sansUserDataDir' = '{0} does not expose --user-data-dir: its sessions stay common to every context.'
}
