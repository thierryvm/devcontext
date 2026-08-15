# Analyse statique et conformité de l'API publique.
#
# PSScriptAnalyzer n'est pas une dépendance d'exécution du module : ces tests se
# déclarent SAUTÉS quand il est absent, plutôt que verts. Un test qui passe
# parce qu'il n'a rien examiné est un mensonge silencieux, et c'est ainsi qu'une
# suite finit par ne plus rien garantir. La CI, elle, l'installe — le filet y est
# donc toujours tendu.

BeforeAll {
    $script:Racine    = Split-Path $PSScriptRoot -Parent
    $script:Reglages  = Join-Path $script:Racine 'PSScriptAnalyzerSettings.psd1'
    $script:Analyseur = [bool](Get-Module -ListAvailable PSScriptAnalyzer)
    Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force
}

# La liste des fichiers analyses est DERIVEE du depot, jamais ecrite a la main.
#
# Elle etait en dur, et src\Editors.ps1 comme src\Shortcuts.ps1 y ont echappe
# des leur creation : la suite restait verte en ayant analyse six fichiers sur
# huit, sans rien dire. C'est le meme defaut que la table d'editeurs qui a
# precede la decouverte — une liste qu'un humain doit penser a completer est une
# liste qui sera incomplete.
#
# Seuls les fichiers SUIVIS PAR GIT sont pris : un brouillon local n'a pas a
# faire echouer la suite, et un fichier livre n'a pas le droit d'y echapper.
$script:FichiersAnalysables = @(
    & git -C (Split-Path $PSScriptRoot -Parent) ls-files '*.ps1' '*.psm1' 2>$null
) | Where-Object { $_ -and $_ -notlike 'tests/*' }

Describe 'PSScriptAnalyzer' {
    # -ForEach avec une table de hachage : c'est le mecanisme par lequel Pester
    # fait passer une donnee de la phase de DECOUVERTE a la phase d'EXECUTION.
    # Les deux phases ont des portees distinctes, et lire $script:… directement
    # dans le corps d'un It rend une variable vide -- ce test affirmait donc
    # « 0 fichier » pendant que les tests suivants en analysaient onze. Vert ou
    # rouge, un test qui mesure autre chose que ce qu'il annonce est le meme
    # defaut, vu de deux cotes.
    It 'couvre tous les fichiers livres, sans liste ecrite a la main' `
        -ForEach @(@{ Decouverts = $script:FichiersAnalysables }) {
        # Le garde-fou du garde-fou. Si ce compte tombe, la derivation a cesse
        # de fonctionner et les tests suivants n'examinent plus rien -- en
        # silence, puisqu'une liste vide ne genere aucun test.
        $Decouverts.Count | Should -BeGreaterThan 5
        $Decouverts | Should -Contain 'src/Editors.ps1'
        $Decouverts | Should -Contain 'shims/editor.ps1'
        $Decouverts | Should -Not -Contain 'tests/Analyse.Tests.ps1'
    }

    It 'ne signale ni erreur ni avertissement dans <_>' -ForEach $script:FichiersAnalysables {
        if (-not $script:Analyseur) {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer absent de cette machine (la CI l installe)'
            return
        }
        $resultats = Invoke-ScriptAnalyzer -Path (Join-Path $script:Racine $_) -Settings $script:Reglages
        $lisible = $resultats | ForEach-Object { "$($_.Line): [$($_.RuleName)] $($_.Message)" }
        $lisible | Should -BeNullOrEmpty
    }
}

Describe 'API publique' {
    BeforeAll {
        $script:Publiques = @((Get-Module DevContext).ExportedFunctions.Values)
    }

    It 'expose au moins les commandes attendues' {
        $script:Publiques.Count | Should -BeGreaterThan 10
    }

    It 'chaque fonction exportee porte une aide' {
        # `Get-Help ctx-doctor` doit repondre. C'est la seule documentation
        # qu'un utilisateur consulte au moment ou il en a besoin, et la seule
        # qu'un agent IA trouve sans qu'on la lui donne.
        $muettes = @(
            $script:Publiques | Where-Object {
                -not (Get-Help $_.Name -ErrorAction SilentlyContinue).Synopsis -or
                (Get-Help $_.Name).Synopsis -match '^\s*$|^' + [regex]::Escape($_.Name)
            } | ForEach-Object { $_.Name }
        )
        $muettes | Should -BeNullOrEmpty -Because 'une commande sans .SYNOPSIS est une commande qu on n ose pas lancer'
    }

    It 'chaque fonction exportee suit la convention Verbe-Nom' {
        $fautives = @(
            $script:Publiques | Where-Object { $_.Verb -notin (Get-Verb).Verb } | ForEach-Object { $_.Name }
        )
        $fautives | Should -BeNullOrEmpty
    }

    It 'aucun alias exporte n entre en collision avec une commande PowerShell' {
        # `supabase` et `vercel` masquent DELIBEREMENT les binaires du meme nom,
        # ce qui est tout leur objet. Masquer une applet de commande native,
        # en revanche, casserait des scripts sans rapport.
        $collisions = @(
            (Get-Module DevContext).ExportedAliases.Keys | ForEach-Object {
                $c = Get-Command $_ -CommandType Cmdlet, Function -ErrorAction SilentlyContinue |
                     Where-Object { $_.Source -ne 'DevContext' }
                if ($c) { $_ }
            }
        )
        $collisions | Should -BeNullOrEmpty
    }
}

Describe 'chargement du module' {
    It 'se charge sans avertissement' {
        $avertissements = @()
        Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force -WarningVariable avertissements -WarningAction SilentlyContinue
        $avertissements | Should -BeNullOrEmpty
    }

    It 'declare tous ses fichiers sources dans le depot' {
        # Le module source src\*.ps1 : un fichier oublie au commit rend le
        # module incapable de se charger sur une machine neuve, alors qu'il
        # fonctionne parfaitement ici.
        $sources = @(Get-ChildItem (Join-Path $script:Racine 'src') -Filter '*.ps1' -ErrorAction SilentlyContinue)
        $suivis  = @(& git -C $script:Racine ls-files 'src/*.ps1' 2>$null)
        $sources.Count | Should -Be $suivis.Count -Because 'tout fichier de src doit etre suivi par git'
    }

    It 'chaque fichier de src est reference par le psm1' {
        $psm1 = Get-Content (Join-Path $script:Racine 'DevContext.psm1') -Raw
        foreach ($f in (Get-ChildItem (Join-Path $script:Racine 'src') -Filter '*.ps1')) {
            $psm1 | Should -Match ([regex]::Escape($f.Name)) -Because "$($f.Name) serait sinon du code mort"
        }
    }
}
