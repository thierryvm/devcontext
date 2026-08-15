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

Describe 'PSScriptAnalyzer' {
    It 'ne signale ni erreur ni avertissement dans <_>' -ForEach @(
        'DevContext.psm1', 'src\Doctor.ps1', 'src\Jetons.ps1', 'src\Mcp.ps1',
        'shims\supabase.ps1', 'installer-shims.ps1'
    ) {
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
