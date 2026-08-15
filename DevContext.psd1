# Manifeste du module DevContext.
#
# POURQUOI IL EXISTE. Sans lui, `Get-Module DevContext` annonce « 0.0 » — donc
# rien. Sur un outil qui décide de l'identité sous laquelle partent les commits
# et les déploiements, ne pas savoir quelle version est chargée est un angle
# mort : c'est exactement la question qu'on se pose le jour où un comportement
# surprend.
#
# ⚠️ `ModuleVersion` se met à jour À LA MAIN, quand un changement mérite d'être
# nommé. Un numéro qui ne bouge jamais ment autant qu'une absence de numéro.

@{
    RootModule        = 'DevContext.psm1'
    ModuleVersion     = '1.3.1'
    GUID              = 'b4f2c8a1-7e35-4d69-9a02-3c8d1e5f7b04'
    Author            = 'Thierry V.'
    # En anglais : c'est le texte affiché sur PowerShell Gallery, donc la
    # première phrase que lit quelqu'un qui ne connaît pas encore l'outil.
    Description       = 'Keep development identities apart, per folder. One context = one folder + one complete identity: git email, SSH key, GitHub account, Vercel session, Supabase tokens, VS Code profile, MCP servers. Several coexist at once, and the folder decides which applies -- including a guard that refuses destructive commands against a production database, from every shell.'

    PowerShellVersion = '7.0'

    # Table view for ctx-sb. PowerShell falls back to a list layout past four
    # display properties, and a command meant to show the estate at a glance
    # cannot ship one object per paragraph.
    FormatsToProcess  = @('DevContext.format.ps1xml')

    # Le coffre est une dépendance DURE : sans lui, aucun jeton n'est chargé et
    # le module ne peut pas tenir sa promesse. Le module vérifie déjà sa
    # présence à l'import et lève une erreur explicite ; on le déclare ici pour
    # que l'information existe aussi AVANT l'installation.
    RequiredModules   = @(
        'Microsoft.PowerShell.SecretManagement'
        'Microsoft.PowerShell.SecretStore'
    )

    # Énumérés explicitement plutôt que par joker : ce qui est exporté est une
    # décision, pas une conséquence. Un `*` exporterait aussi les fonctions
    # internes le jour où l'une d'elles cesse d'être privée par accident.
    FunctionsToExport = @(
        'Assert-DevContext'
        'Clear-DevContext'
        'Close-DevContext'
        'Get-DevContextDoctor'
        'Get-DevContextList'
        'Get-DevEditorList'
        'Get-CtxArgumentValeur'
        'Get-CtxSupabasePaires'
        'Get-CtxSupabaseRefDepuisUrl'
        'Get-DevSupabaseMap'
        'Invoke-DevSupabase'
        'Invoke-DevVercel'
        'New-DevContext'
        'New-DevShortcut'
        'New-DevProjectMcp'
        'Open-DevBrowser'
        'Open-DevCode'
        'Resolve-DevContextForPath'
        'Set-DevContextRoot'
        'Test-CtxSupabaseGuard'
        'Test-DevContext'
        'Update-DevSupabaseIndex'
        'Use-DevContext'
    )

    # `supabase` et `vercel` remplacent DÉLIBÉRÉMENT les binaires du même nom :
    # c'est ce qui garantit qu'un appel direct passe par le contexte actif.
    AliasesToExport   = @(
        'code-ctx'
        'ctx'
        'ctx-check'
        'ctx-doctor'
        'ctx-editors'
        'ctx-end'
        'ctx-list'
        'ctx-mcp'
        'ctx-new'
        'ctx-root'
        'ctx-off'
        'ctx-sb'
        'ctx-shortcut'
        'ctx-who'
        'sb-index'
        'supabase'
        'vercel'
        'web-ctx'
        'work'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            # Les tags sont le SEUL moyen d'etre trouve sur PowerShell Gallery :
            # sa recherche les interroge avant la description. Ceux qui comptent
            # sont ceux qu'on tape quand on a le probleme sans connaitre l'outil.
            Tags         = @(
                'DevContext', 'Identity', 'Isolation', 'Windows', 'PowerShell7',
                'Git', 'SSH', 'GitHub', 'Multi-Account', 'Credentials',
                'Supabase', 'Vercel', 'MCP', 'AI', 'DevTools', 'VSCode'
            )
            ProjectUri   = 'https://github.com/thierryvm/devcontext'
            # LicenseUri manquait. La Gallery affiche alors « licence non
            # declaree », ce qui, pour un outil qui manipule des identifiants,
            # est exactement le detail qui fait refermer la page.
            LicenseUri   = 'https://github.com/thierryvm/devcontext/blob/main/LICENSE'
            ReleaseNotes = 'https://github.com/thierryvm/devcontext/blob/main/CHANGELOG.md'
        }
    }
}
