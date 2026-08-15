# Règles d'analyse statique pour DevContext.
#
# Deux règles sont écartées, et il faut dire pourquoi : une exclusion muette
# ressemble vite à un défaut qu'on a caché.

@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # PSAvoidUsingWriteHost — ce module EST une interface en ligne de
        # commande. `ctx`, `work` et `ctx doctor` s'adressent à un humain dans un
        # terminal, en couleur ; Write-Output y polluerait le pipeline des
        # fonctions qui, elles, rendent des objets. Les commandes qui produisent
        # des données (Get-DevSupabaseMap, Get-DevContextDoctor) rendent bien des
        # objets, et c'est ce que vérifient leurs tests.
        'PSAvoidUsingWriteHost'

        # PSUseSingularNouns — Get-DevContextList et Get-CtxManifests rendent
        # des collections, et les renommer casserait des alias documentés et le
        # profil de l'utilisateur. Le coût est réel, le gain purement cosmétique.
        'PSUseSingularNouns'
    )

    Rules = @{
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; Kind = 'space'; IndentationSize = 4 }
    }
}
