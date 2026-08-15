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
    ModuleVersion     = '1.0.0'
    GUID              = 'b4f2c8a1-7e35-4d69-9a02-3c8d1e5f7b04'
    Author            = 'Thierry V.'
    Description       = 'Cloisonnement des identités de développement par contexte : git, SSH, gh, Vercel, Supabase. Un contexte = un dossier + une identité complète, plusieurs coexistant en simultané.'

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
        'Get-DevSupabaseMap'
        'Invoke-DevSupabase'
        'Invoke-DevVercel'
        'New-DevContext'
        'New-DevProjectMcp'
        'Open-DevBrowser'
        'Open-DevCode'
        'Resolve-DevContextForPath'
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
        'ctx-end'
        'ctx-list'
        'ctx-mcp'
        'ctx-new'
        'ctx-off'
        'ctx-sb'
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
            Tags       = @('DevContext', 'Identity', 'Git', 'SSH', 'Windows', 'Isolation')
            ProjectUri = 'https://github.com/thierryvm/devcontext'
        }
    }
}
