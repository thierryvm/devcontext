# Ce qui part dans le paquet publie.
#
# CE FICHIER EXISTE A CAUSE D'UNE MESURE, PAS D'UNE INTUITION. Le 15 aout 2026,
# un paquet d'essai construit avec Publish-PSResource depuis le depot de travail
# contenait .git en entier : 825 Ko sur 1060, dont .git/config (URL de push et
# alias SSH de l'auteur) et .git/filter-repo/commit-map, la table anciens-SHA
# vers nouveaux d'une reecriture d'anonymisation.
#
# Ce qui rend l'erreur particuliere : une version publiee sur PowerShell Gallery
# ne se supprime pas. Elle se delie seulement, et reste telechargeable par numero
# exact. Il n'existe donc aucune version suivante qui repare celle-la. C'est le
# seul endroit du projet ou un test ne protege pas d'une regression rattrapable,
# mais d'un fait definitif.
#
# Les deux dangers sont symetriques et ce fichier couvre les deux : embarquer ce
# qui ne devrait pas partir, et ECARTER ce dont le module a besoin pour
# fonctionner. Le second ne se voit qu'a l'installation, chez quelqu'un d'autre.

BeforeAll {
    $script:Racine = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:Racine 'tools' 'Build-Package.ps1') -AsLibrary
}

Describe 'Select-CtxFichiersPublies' {
    It 'ecarte tout ce qui commence par .git' -ForEach @(
        @{ Chemin = '.git/config' }
        @{ Chemin = '.git/filter-repo/commit-map' }
        @{ Chemin = '.gitignore' }
        @{ Chemin = 'shims/.gitignore' }
        @{ Chemin = '.gitattributes' }
        @{ Chemin = '.github/workflows/ci.yml' }
    ) {
        Select-CtxFichiersPublies -Fichiers @($Chemin) | Should -BeNullOrEmpty
    }

    It 'ecarte l outillage de developpement : <Chemin>' -ForEach @(
        @{ Chemin = '.claude/agents/security-auditor.md' }
        @{ Chemin = 'tools/Build-Package.ps1' }
        @{ Chemin = 'tests/Paquet.Tests.ps1' }
        @{ Chemin = 'PSScriptAnalyzerSettings.psd1' }
        @{ Chemin = 'AGENTS.md' }
        @{ Chemin = 'CONTRIBUTING.md' }
        @{ Chemin = 'docs/plans/2026-08-13-garde-fou-production.md' }
        @{ Chemin = 'docs/demo/ctx-doctor.svg' }
    ) {
        Select-CtxFichiersPublies -Fichiers @($Chemin) | Should -BeNullOrEmpty
    }

    It 'garde ce qui sert a se servir du module : <Chemin>' -ForEach @(
        @{ Chemin = 'DevContext.psm1' }
        @{ Chemin = 'DevContext.psd1' }
        @{ Chemin = 'DevContext.format.ps1xml' }
        @{ Chemin = 'src/Doctor.ps1' }
        @{ Chemin = 'lang/en.psd1' }
        @{ Chemin = 'shims/supabase.cmd' }
        @{ Chemin = 'installer-shims.ps1' }
        @{ Chemin = 'LICENSE' }
        @{ Chemin = 'README.md' }
        @{ Chemin = 'SECURITY.md' }
        @{ Chemin = 'docs/GUIDE.md' }
        @{ Chemin = 'docs/ARCHITECTURE.md' }
    ) {
        Select-CtxFichiersPublies -Fichiers @($Chemin) | Should -Be $Chemin
    }

    It 'normalise les separateurs Windows avant de filtrer' {
        # git ls-files rend des slashs, mais un appelant qui passerait une liste
        # obtenue autrement casserait CHAQUE motif d'exclusion d'un coup -- donc
        # sans qu'aucun test individuel ne rougisse.
        Select-CtxFichiersPublies -Fichiers @('.github\workflows\ci.yml') | Should -BeNullOrEmpty
    }

    It 'accepte une liste vide sans lever' {
        { Select-CtxFichiersPublies -Fichiers @() } | Should -Not -Throw
    }
}

Describe 'Le paquet assemble' {
    BeforeAll {
        # On appelle la fonction plutot que le script : l'assemblage doit se
        # verifier meme quand l'arbre de travail est en cours de modification.
        # Melanger les deux ferait rougir ces tests pour une raison qui n'a rien
        # a voir avec eux.
        $script:Sortie = Join-Path ([System.IO.Path]::GetTempPath()) "devctx-test-paquet-$PID"
        $script:Module = New-CtxDossierPaquet -Racine $script:Racine -Destination $script:Sortie
        $script:Relatifs = @(
            Get-ChildItem -LiteralPath $script:Module -Recurse -File |
                ForEach-Object { $_.FullName.Substring($script:Module.Length + 1) -replace '\\', '/' }
        )
    }

    AfterAll {
        if ($script:Sortie -and (Test-Path -LiteralPath $script:Sortie)) {
            Remove-Item -LiteralPath $script:Sortie -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ne contient aucun fichier de plomberie git' {
        # L'assertion qui justifie ce fichier. Elle porte sur le RESULTAT, pas
        # sur la liste d'exclusion : c'est ce qui se retrouve sur disque qui part
        # sur la Gallery.
        @($script:Relatifs | Where-Object { $_ -match '(^|/)\.git($|/)' }) | Should -BeNullOrEmpty
    }

    It 'ne contient aucun chemin absolu de la machine qui construit' {
        # Un paquet qui embarquerait le dossier de son auteur publierait son nom
        # d'utilisateur Windows -- le defaut deja corrige dans les routeurs URI.
        @($script:Relatifs | Where-Object { $_ -match '^[A-Za-z]:' }) | Should -BeNullOrEmpty
    }

    It 'porte le nom que PSResourceGet attend' {
        # Publish-PSResource resout le manifeste par le NOM DU DOSSIER. Un
        # dossier « staging » echoue sur « manifeste introuvable », un message
        # qui ne nomme pas la cause.
        Split-Path $script:Module -Leaf | Should -Be 'DevContext'
        Test-Path (Join-Path $script:Module 'DevContext.psd1') | Should -BeTrue
    }

    It 'contient tout ce que le manifeste declare' {
        $manifeste = Import-PowerShellDataFile (Join-Path $script:Racine 'DevContext.psd1')
        $requis = @($manifeste.RootModule) + @($manifeste.FormatsToProcess)
        foreach ($f in $requis) {
            Test-Path (Join-Path $script:Module $f) |
                Should -BeTrue -Because "le manifeste declare '$f'"
        }
    }

    It 'contient tout ce que le module source au chargement' {
        # L'exclusion de trop est le danger symetrique, et le plus discret : il ne
        # se manifeste QUE sur une machine ou le module a ete installe depuis la
        # Gallery, donc jamais ici. On lit les noms dans le psm1 plutot que
        # d'entretenir une liste en parallele, qui divergerait au premier ajout.
        #
        # Par l'AST et non par expression reguliere : le psm1 source ses fichiers
        # en bouclant sur un tableau litteral, pas en les nommant un par un. Une
        # regex calee sur `Join-Path $PSScriptRoot 'src' 'X.ps1'` n'a rien trouve
        # -- et « rien trouve » se lit comme « rien a verifier », donc comme un
        # test vert. C'est le meme piege que le test rendait vrai plus haut :
        # lire du code comme du texte.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:Racine 'DevContext.psm1'), [ref]$null, [ref]$null)
        $sources = @(
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                ForEach-Object { $_.Value } |
                Where-Object { $_ -match '\.ps1$' } |
                Sort-Object -Unique
        )

        $sources | Should -Not -BeNullOrEmpty -Because 'le psm1 nomme les fichiers qu il source'
        foreach ($f in $sources) {
            $script:Relatifs | Should -Contain "src/$f" -Because "DevContext.psm1 source '$f' au chargement"
        }
    }

    It 'contient les deux tables de langue' {
        # Sans elles chaque message s'affiche entre crochets : le module marche,
        # et ne se lit plus. Un defaut qui ne casse rien est un defaut qu'on
        # publie.
        $script:Relatifs | Should -Contain 'lang/fr.psd1'
        $script:Relatifs | Should -Contain 'lang/en.psd1'
    }

    It 's importe sur un processus qui n a jamais vu le module' {
        # Le controle de bout en bout : toutes les assertions ci-dessus peuvent
        # passer et le paquet rester inutilisable. Dans un processus separe, car
        # ce module-ci est deja charge dans celui de la suite.
        $sortie = pwsh -NoProfile -Command "
            `$ErrorActionPreference = 'Stop'
            Import-Module '$(Join-Path $script:Module 'DevContext.psd1')' -Force
            `$m = Get-Module DevContext
            '{0}|{1}|{2}' -f `$m.Version, `$m.ExportedFunctions.Count, `$m.ExportedAliases.Count
        "
        $LASTEXITCODE | Should -Be 0 -Because 'le paquet assemble doit s importer tel quel'
        $champs = ("$sortie".Trim() -split '\|')
        [int]$champs[1] | Should -BeGreaterThan 10
        [int]$champs[2] | Should -BeGreaterThan 10
    }

    It 'pese nettement moins que le depot de travail' {
        # Pas une question d'octets : le paquet mesure sa propre discipline. Le
        # 15 aout 2026, 78 % du paquet d'essai etait .git.
        #
        # L'ATTENDU A CHANGE LE 19 AOUT 2026, ET C'EST DIT PLUTOT QUE FAIT EN
        # SILENCE. Il etait un plafond ABSOLU -- 700 ko -- et il a rougi sur la
        # croissance du module LUI-MEME : DevContext.psm1, src/Doctor.ps1 et
        # CHANGELOG.md pesent a eux trois plus de 250 ko. La composition du
        # paquet a ete relue fichier par fichier avant de toucher a cette ligne,
        # et il ne portait rien d'illegitime : docs/plans, docs/specs,
        # docs/article, docs/demo, tests et tools sont deja ecartes par
        # $script:ExclusPaquet.
        #
        # Le plafond ne disait donc pas ce que le titre de ce test annonce. Le
        # paquet est par CONSTRUCTION un sous-ensemble des fichiers suivis : il
        # doit peser moins qu'eux, et cette comparaison-la ne vieillit pas -- les
        # deux cotes grandissent ensemble. Elle reste sans appel sur le defaut de
        # reference : .git embarque ferait 4,8 Mo de paquet contre 1,3 Mo de
        # fichiers suivis.
        #
        # Un plafond ajuste a la mesure du jour aurait ete une expectative
        # recalee sur le resultat, ce que ce projet s'interdit. Une comparaison
        # structurelle n'a pas ce defaut : elle ne peut pas etre satisfaite en
        # deplacant un chiffre.
        $suivis = @(Get-CtxFichiersSuivis -Racine $script:Racine)
        $arbre = 0
        foreach ($f in $suivis) {
            $chemin = Join-Path $script:Racine $f
            if (Test-Path -LiteralPath $chemin -PathType Leaf) {
                $arbre += (Get-Item -LiteralPath $chemin).Length
            }
        }

        $paquet = (Get-ChildItem -LiteralPath $script:Module -Recurse -File | Measure-Object Length -Sum).Sum

        $arbre | Should -BeGreaterThan 0 -Because 'sans arbre a comparer, ce test ne mesure rien'
        $paquet | Should -BeLessThan $arbre
    }
}

Describe 'Assert-CtxArbrePropre' {
    # Un paquet doit correspondre a un commit, sans quoi la version publiee n'est
    # reproductible nulle part -- ni sur GitHub, ni dans l'historique.
    BeforeAll {
        $script:Bac = Join-Path ([System.IO.Path]::GetTempPath()) "devctx-test-depot-$PID"
        New-Item -ItemType Directory -Path $script:Bac -Force | Out-Null
        # Identite passee en -c : ce depot jetable ne doit rien emprunter a la
        # configuration de la machine, et surtout rien y ecrire.
        $git = @('-C', $script:Bac, '-c', 'user.email=t@example.invalid', '-c', 'user.name=Test')
        & git @git init --quiet 2>&1 | Out-Null
        Set-Content (Join-Path $script:Bac 'a.txt') 'un'
        & git @git add -A 2>&1 | Out-Null
        & git @git commit -m 'initial' --quiet 2>&1 | Out-Null
    }

    AfterAll {
        if ($script:Bac -and (Test-Path -LiteralPath $script:Bac)) {
            Remove-Item -LiteralPath $script:Bac -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'ne dit rien sur un arbre propre' {
        { Assert-CtxArbrePropre -Racine $script:Bac } | Should -Not -Throw
    }

    It 'leve des qu un fichier est modifie' {
        Set-Content (Join-Path $script:Bac 'a.txt') 'deux'
        { Assert-CtxArbrePropre -Racine $script:Bac } | Should -Throw
    }

    It 'leve aussi sur un fichier non suivi' {
        # Le cas qu'on oublie : `git status --porcelain` le rapporte, et c'est
        # exactement le fichier de brouillon qu'on ne veut pas publier.
        & git -C $script:Bac checkout -- a.txt 2>&1 | Out-Null
        Set-Content (Join-Path $script:Bac 'brouillon.txt') 'note'
        { Assert-CtxArbrePropre -Racine $script:Bac } | Should -Throw
    }
}
