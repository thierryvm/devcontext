# Ce qui doit etre vrai AVANT qu'une version parte, et qui ne peut pas etre
# verifie en essayant.
#
# Une version publiee ne se supprime jamais : elle se delist, et reste
# telechargeable par numero exact, pour toujours. Une regle de publication ecrite
# dans le YAML d'un workflow ne s'essaie donc qu'en publiant -- c'est-a-dire en
# commettant une fois la faute qu'elle devait empecher.
#
# D'ou tools/Assert-Release.ps1 : la moitie interessante est pure, et c'est elle
# qui est exercee ici sur les cas qui ne doivent JAMAIS atteindre une vraie
# release.

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'Assert-Release.ps1') -AsLibrary
}

Describe 'Version portee par un tag' {
    It 'lit <Tag> comme <Attendu>' -ForEach @(
        @{ Tag = 'v1.9.0';   Attendu = '1.9.0' }
        @{ Tag = 'v1.9';     Attendu = '1.9' }
        @{ Tag = 'v1.9.0.1'; Attendu = '1.9.0.1' }
        @{ Tag = ' v2.0.0 '; Attendu = '2.0.0' }
    ) {
        Get-CtxVersionDepuisTag -Tag $Tag | Should -Be $Attendu
    }

    It 'refuse <Tag>, qui n est pas une version finale' -ForEach @(
        @{ Tag = '1.9.0' }          # sans le v : ce n'est pas la convention du depot
        @{ Tag = 'v1.9.0-rc1' }     # une pre-publication publierait une version finale
        @{ Tag = 'v1.9.0+build' }
        @{ Tag = 'release-1.9.0' }
        @{ Tag = 'v' }
        @{ Tag = '' }
        @{ Tag = $null }
    ) {
        Get-CtxVersionDepuisTag -Tag $Tag | Should -BeNullOrEmpty
    }
}

Describe 'Le tag et le manifeste doivent dire la meme chose' {
    It 'ne dit rien quand ils concordent' {
        Test-CtxTagCorrespondManifeste -Tag 'v1.9.0' -VersionManifeste '1.9.0' |
            Should -BeNullOrEmpty
    }

    It 'attrape le tag pose sur un manifeste qu on a oublie de faire monter' {
        # LE cas. Il est silencieux autrement : la Gallery repondrait « cette
        # version existe deja », en nommant le symptome et jamais l'edition
        # oubliee.
        $faute = Test-CtxTagCorrespondManifeste -Tag 'v1.9.0' -VersionManifeste '1.8.0'
        $faute | Should -Not -BeNullOrEmpty
        $faute | Should -Match '1\.9\.0'
        $faute | Should -Match '1\.8\.0'
    }

    It 'refuse 1.9.0 contre 1.9.0.0, qui sont deux numeros distincts' {
        # Ce test a d'abord affirme le CONTRAIRE, sur la croyance que .NET tenait
        # ces deux versions pour egales. Il ne le fait pas : Revision vaut -1
        # contre 0. Et une fois la question posee franchement, le refus est la
        # bonne reponse -- ce sont deux numeros differents sur la Gallery, et un
        # numero publie ne se reprend jamais.
        Test-CtxTagCorrespondManifeste -Tag 'v1.9.0' -VersionManifeste '1.9.0.0' |
            Should -Not -BeNullOrEmpty
    }

    It 'tolere les espaces autour de la version du manifeste' {
        Test-CtxTagCorrespondManifeste -Tag 'v1.9.0' -VersionManifeste ' 1.9.0 ' |
            Should -BeNullOrEmpty
    }

    It 'refuse un manifeste sans version' {
        Test-CtxTagCorrespondManifeste -Tag 'v1.9.0' -VersionManifeste '' |
            Should -Not -BeNullOrEmpty
    }

    It 'refuse un tag mal forme plutot que de deviner' {
        Test-CtxTagCorrespondManifeste -Tag 'v1.9.0-rc1' -VersionManifeste '1.9.0' |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Audit du paquet assemble' {
    BeforeAll {
        $script:Minimal = @('DevContext.psd1', 'DevContext.psm1', 'LICENSE', 'README.md')
        # Un lecteur qui ne rend rien : on n'examine alors que les CHEMINS.
        $script:Muet = { param($p) $null = $p; '' }
    }

    It 'laisse passer un paquet correct' {
        Find-CtxFautesPaquet -Fichiers $script:Minimal -LireContenu $script:Muet |
            Should -BeNullOrEmpty
    }

    It 'refuse un paquet vide' {
        Find-CtxFautesPaquet -Fichiers @() -LireContenu $script:Muet |
            Should -Not -BeNullOrEmpty
    }

    It 'refuse <Intrus>, qui ne doit pas partir' -ForEach @(
        @{ Intrus = '.git/config' }
        @{ Intrus = '.git/filter-repo/commit-map' }
        @{ Intrus = 'tests/Doctor.Tests.ps1' }
        @{ Intrus = '.github/workflows/ci.yml' }
        @{ Intrus = '.claude/agents/security-auditor.md' }
        @{ Intrus = 'tools/Build-Package.ps1' }
        @{ Intrus = 'AGENTS.md' }
        @{ Intrus = 'CONTRIBUTING.md' }
    ) {
        $fautes = Find-CtxFautesPaquet -Fichiers ($script:Minimal + $Intrus) -LireContenu $script:Muet
        $fautes | Should -Not -BeNullOrEmpty
        ($fautes -join "`n") | Should -Match ([regex]::Escape($Intrus))
    }

    It 'accepte des separateurs Windows dans les chemins' {
        # Get-ChildItem rend des \, les motifs sont ecrits en /. Sans
        # normalisation, aucun interdit ne matcherait -- et l'audit passerait au
        # vert sur un paquet qui contient tout ce qu'il ne devrait pas.
        $fautes = Find-CtxFautesPaquet -Fichiers ($script:Minimal + '.git\config') -LireContenu $script:Muet
        $fautes | Should -Not -BeNullOrEmpty
    }

    It 'refuse un paquet ampute de <Manquant>' -ForEach @(
        @{ Manquant = 'DevContext.psd1' }
        @{ Manquant = 'DevContext.psm1' }
        @{ Manquant = 'LICENSE' }
        @{ Manquant = 'README.md' }
    ) {
        $liste = @($script:Minimal | Where-Object { $_ -ne $Manquant })
        $fautes = Find-CtxFautesPaquet -Fichiers $liste -LireContenu $script:Muet
        ($fautes -join "`n") | Should -Match ([regex]::Escape($Manquant))
    }

    It 'lit le contenu par le lecteur injecte, jamais par le disque' {
        # Preuve structurelle : aucun de ces fichiers n'existe. Si la fonction
        # allait interroger le disque, elle ne verrait rien et rendrait vert.
        #
        # Le piege est enregistre dans AGENTS.md : une fonction qui recoit une
        # dependance ET consulte quand meme la vraie, c'est une dependance
        # injectee a moitie -- donc pas injectee.
        $appeles = [System.Collections.Generic.List[string]]::new()
        $lecteur = {
            param($p)
            $appeles.Add($p)
            if ($p -eq 'README.md') { 'AKIAIOSFODNN7EXAMPLE' } else { '' }
        }
        $fautes = Find-CtxFautesPaquet -Fichiers $script:Minimal -LireContenu $lecteur

        $appeles | Should -Contain 'README.md'
        $appeles.Count | Should -Be $script:Minimal.Count
        ($fautes -join "`n") | Should -Match 'README\.md'
    }

    It 'ne recopie PAS le secret trouve dans le message de faute' {
        # Un rapport de CI est public. Publier la valeur pour annoncer qu'on en a
        # trouve une serait exactement la faute qu'on cherchait a empecher.
        $valeur = 'ghp_' + ('A' * 36)
        $lecteur = { param($p) if ($p -eq 'README.md') { $valeur } else { '' } }
        $fautes = Find-CtxFautesPaquet -Fichiers $script:Minimal -LireContenu $lecteur

        $fautes | Should -Not -BeNullOrEmpty
        ($fautes -join "`n") | Should -Not -Match ([regex]::Escape($valeur))
        ($fautes -join "`n") | Should -Match 'README\.md'
    }

    It 'refuse un chemin de profil utilisateur' {
        # Le chemin est ASSEMBLE et non ecrit tel quel, et ce n'est pas une
        # coquetterie : Documentation.Tests.ps1 balaie TOUT fichier suivi a la
        # recherche d'un chemin de profil, et ce fichier-ci en est un. Ecrit en
        # entier, le fixture faisait rougir ce scan-la -- un test qui, pour
        # verifier une regle, commet ce que la regle interdit.
        #
        # Ne pas "simplifier" en recollant la chaine.
        $faux = 'C:\Users' + '\' + 'quelquun' + '\AppData\Local'
        $lecteur = { param($p) if ($p -eq 'README.md') { $faux } else { '' } }
        Find-CtxFautesPaquet -Fichiers $script:Minimal -LireContenu $lecteur |
            Should -Not -BeNullOrEmpty
    }

    It 'laisse passer <Nom>, qui est de la documentation' -ForEach @(
        # Assembles pour la meme raison que le cas ci-dessus : ce fichier est
        # lui-meme balaye par Documentation.Tests.ps1 et Portabilite.Tests.ps1,
        # et ces deux-la n'exemptent PAS la meme liste de noms neutres. Ecrits en
        # entier, ces fixtures rougissaient chez l'un sans rougir chez l'autre.
        @{ Nom = 'moi' }
        @{ Nom = 'vous' }
        @{ Nom = '<vous>' }
        @{ Nom = '%USERNAME%' }
        @{ Nom = '$env:USERNAME' }
    ) {
        $exemple = 'C:\Users' + '\' + $Nom + '\AppData\Local'
        $lecteur = { param($p) if ($p -eq 'README.md') { $exemple } else { '' } }
        Find-CtxFautesPaquet -Fichiers $script:Minimal -LireContenu $lecteur |
            Should -BeNullOrEmpty
    }
}

Describe 'Sortie standard — ce qui est capturable doit etre SEUL' {
    # Mesure du 17 aout 2026 : `$d = pwsh -NoProfile -File .\tools\Build-Package.ps1`
    # rendait TROIS lignes et non un chemin. Les lignes de progression passaient
    # par Write-Host, avec en commentaire l'idee que cela laissait stdout propre
    # -- vrai dans un meme processus, faux a travers `pwsh -File`, ou le flux
    # d'information de l'enfant arrive sur la sortie standard du parent.
    #
    # Ici la valeur rendue est une VERSION. Contaminee, c'est elle qu'on irait
    # comparer, puis publier.

    BeforeAll {
        $script:Script = (Resolve-Path (Join-Path $PSScriptRoot '..' 'tools' 'Assert-Release.ps1')).Path

        function New-FauxPaquet {
            param([Parameter(Mandatory)][string]$Dans, [string]$Version = '9.9.9')
            $d = Join-Path $Dans 'DevContext'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            "@{ ModuleVersion = '$Version'; RootModule = 'DevContext.psm1' }" |
                Set-Content (Join-Path $d 'DevContext.psd1') -Encoding UTF8
            foreach ($f in @('DevContext.psm1', 'LICENSE', 'README.md')) {
                'rien de sensible' | Set-Content (Join-Path $d $f) -Encoding UTF8
            }
            $d
        }
    }

    It 'rend la version, et RIEN d autre, sur la sortie standard' {
        $paquet = New-FauxPaquet -Dans $TestDrive
        $sortie = @(& pwsh -NoProfile -File $script:Script -Dossier $paquet -Tag 'v9.9.9' 2>$null)

        $LASTEXITCODE | Should -Be 0
        $sortie.Count | Should -Be 1 -Because 'le compte rendu doit partir sur stderr'
        $sortie[0].Trim() | Should -Be '9.9.9'
    }

    It 'sort en erreur et ne rend RIEN quand il refuse' {
        # Sans code de sortie non nul, le workflow enchainerait sur la
        # publication d'un paquet que ce script vient de refuser.
        $paquet = New-FauxPaquet -Dans $TestDrive -Version '9.9.9'
        $sortie = @(& pwsh -NoProfile -File $script:Script -Dossier $paquet -Tag 'v1.0.0' 2>$null)

        $LASTEXITCODE | Should -Not -Be 0
        $sortie | Should -BeNullOrEmpty
    }

    It 'refuse un dossier qui n est pas un paquet assemble' {
        $vide = Join-Path $TestDrive 'pas-un-paquet'
        New-Item -ItemType Directory -Path $vide -Force | Out-Null
        $null = & pwsh -NoProfile -File $script:Script -Dossier $vide -Tag 'v9.9.9' 2>$null
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe 'Motifs de secrets — une seule liste' {
    It 'la CI et l audit de paquet lisent la MEME source' {
        # Le piege « deriver une liste et recopier sa jumelle » a deja coute une
        # session sur les alias ctx-*. Le workflow de CI appelle donc ce script
        # au lieu de tenir sa propre copie des motifs.
        $ci = Get-Content (Join-Path $PSScriptRoot '..' '.github' 'workflows' 'ci.yml') -Raw
        $ci | Should -Match 'Assert-Release\.ps1'
        $ci | Should -Match 'Get-CtxMotifsSecrets'
    }

    It 'couvre les emetteurs qui comptent pour ce module' {
        $motifs = (Get-CtxMotifsSecrets) -join '|'
        foreach ($attendu in @('sbp_', 'sb_secret_', 'github_pat_', 'xox', 'AKIA', 'PRIVATE KEY')) {
            $motifs.Contains($attendu) | Should -BeTrue -Because "l emetteur $attendu doit etre couvert"
        }
    }
}

Describe 'La repetition du job de publication' {
    # CE BLOC EXISTE PARCE QUE RIEN NE REGARDAIT CE FICHIER. Sur les trois echecs
    # de publication du 18 aout 2026, deux etaient dans les etapes qui precedent
    # le geste de publier -- des etapes qui ne tournaient que sur un vrai tag,
    # donc impossibles a essayer sans depenser un numero de version. Un numero
    # publie ne se reprend jamais.
    BeforeAll {
        $script:Workflow = Get-Content -LiteralPath (
            Join-Path (Split-Path $PSScriptRoot -Parent) '.github/workflows/release.yml') -Raw

        # Un lecteur minimal plutot qu'une dependance YAML : ce module n'en a
        # aucune, et en ajouter une pour lire quatre blocs serait un mauvais
        # echange. Les cles de job sont a deux espaces sous `jobs:`.
        function Get-CtxBlocJob {
            param([Parameter(Mandatory)][string]$Yaml, [Parameter(Mandatory)][string]$Nom)

            $lignes = $Yaml -split "`r?`n"
            $debut = -1
            for ($i = 0; $i -lt $lignes.Count; $i++) {
                if ($lignes[$i] -match "^  $([regex]::Escape($Nom))\s*:\s*$") { $debut = $i; break }
            }
            if ($debut -lt 0) { return $null }

            $bloc = @($lignes[$debut])
            for ($i = $debut + 1; $i -lt $lignes.Count; $i++) {
                if ($lignes[$i] -match '^  \S') { break }
                $bloc += $lignes[$i]
            }
            $bloc -join "`n"
        }
    }

    It 'existe, et ne tourne que la ou rien ne peut etre publie' {
        $bloc = Get-CtxBlocJob -Yaml $script:Workflow -Nom 'repetition'
        $bloc | Should -Not -BeNullOrEmpty -Because 'sans elle, ces etapes ne s essaient qu en publiant'
        $bloc | Should -Match "needs\.verifier\.outputs\.publier != 'true'"
    }

    It 'partage les etapes avec le job de publication, au lieu de les recopier' {
        # LE test de ce chantier. Une repetition qui re-tape ces etapes serait le
        # jumeau recopie d'une chose derivee -- exactement le defaut qui a produit
        # les echecs du 18 aout. Et une repetition qui derive de ce qu'elle repete
        # est pire qu'aucune : elle rend vert a propos de quelque chose qui
        # n'existe plus.
        $publier = Get-CtxBlocJob -Yaml $script:Workflow -Nom 'publier'
        $repetition = Get-CtxBlocJob -Yaml $script:Workflow -Nom 'repetition'

        $action = 'uses: ./.github/actions/take-audited-package'
        $publier | Should -BeLike "*$action*"
        $repetition | Should -BeLike "*$action*"
    }

    It 'ne laisse aucune copie de ces etapes dans le workflow' {
        # Le pendant du test precedent : partager ne sert a rien si une copie
        # survit a cote. Ces deux marqueurs appartiennent desormais a l'action
        # composite, et a elle seule.
        foreach ($marqueur in @('download-artifact', 'These are the bytes that were audited')) {
            $script:Workflow | Should -Not -BeLike "*$marqueur*" -Because "'$marqueur' doit vivre dans l action composite, pas ici"
        }
    }

    It 'l action composite existe et exige la version auditee' {
        $action = Join-Path (Split-Path $PSScriptRoot -Parent) '.github/actions/take-audited-package/action.yml'
        Test-Path -LiteralPath $action | Should -BeTrue

        $texte = Get-Content -LiteralPath $action -Raw
        $texte | Should -Match 'download-artifact'
        $texte | Should -Match 'required:\s*true' -Because 'sans version, la comparaison des octets ne veut rien dire'
    }

    It 'ne nomme AUCUN environnement, ce qui met la cle hors de portee' {
        # C'est l'affirmation que porte l'en-tete de ce workflow : « la cle est un
        # secret d'environnement, donc elle n'est pas seulement inutilisee avant
        # l'approbation, elle est INACCESSIBLE ». Rien ne la verifiait.
        $repetition = Get-CtxBlocJob -Yaml $script:Workflow -Nom 'repetition'
        $repetition | Should -Not -Match '(?m)^\s{4}environment:'
        $repetition | Should -Match 'PSGALLERY_API_KEY' -Because 'la repetition doit PROUVER que la cle est vide, pas l ignorer'
    }

    It 'laisse la porte d approbation exactement ou elle etait' {
        # Le controle qui compte le plus dans ce fichier. Tout ce qui precede
        # serait sans valeur si la porte avait disparu en chemin.
        $publier = Get-CtxBlocJob -Yaml $script:Workflow -Nom 'publier'
        $publier | Should -Match '(?m)^\s{4}environment:'
        $publier | Should -Match 'name: publication'
        $publier | Should -Match "needs\.verifier\.outputs\.publier == 'true'"
    }

    It 'se declenche sur une PR qui touche la machinerie de publication' {
        # Attendre qu'on pense a lancer un essai a blanc, c'est le « il suffira de
        # s en souvenir » que ce depot reproche partout ailleurs.
        $script:Workflow | Should -Match '(?m)^\s{2}pull_request:'
        foreach ($chemin in @('.github/workflows/release.yml', 'tools/Assert-Release.ps1', 'DevContext.psd1')) {
            $script:Workflow | Should -BeLike "*$chemin*"
        }
    }
}
