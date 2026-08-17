# La surface de confiance des agents IA.
#
# Le module cloisonne QUI ON EST ; rien n'y regardait OU CA ECRIT. Les agents
# portent pourtant deja une frontiere -- le dossier de travail, elargi par une
# liste de dossiers approuves -- et le defaut n'est pas l'absence de mecanisme :
# c'est que cette liste s'ecrit en PORTEE UTILISATEUR, une approbation ponctuelle
# a la fois, et que personne ne la relit.
#
# Mesure du 17 aout 2026 sur la machine de l'auteur : 14 dossiers approuves
# globalement, dont la racine d'un contexte, le Bureau et un dossier de session
# cree pour un besoin d'un jour. Tous actifs dans chaque session, y compris dans
# un dossier client.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Confiance des agents — decision' {

    It 'ne dit rien quand aucun dossier n est approuve' {
        InModuleScope DevContext {
            Test-CtxDoctorAgentConfiance -Faits @() -Contexte 'perso' | Should -BeNullOrEmpty
        }
    }

    It 'ne dit rien quand tout appartient au contexte courant' {
        # Un rapport qui felicite a chaque ligne finit lu en diagonale.
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'F:\Apps'; Proprietaire = 'perso' }
                [pscustomobject]@{ Portee = 'projet'; Fichier = 'p'; Dossier = 'F:\Apps\x'; Proprietaire = 'perso' }
            )
            Test-CtxDoctorAgentConfiance -Faits $faits -Contexte 'perso' | Should -BeNullOrEmpty
        }
    }

    It 'signale un dossier appartenant a un AUTRE contexte' {
        # LE cas : ouvert dans un dossier client, l'agent peut aussi ecrire dans
        # l'arborescence d'un autre. Ce n'est pas du desordre, c'est une question
        # de confidentialite -- d'ou PROBLEME et non ATTENTION.
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'F:\Apps'; Proprietaire = 'perso' }
            )
            $c = @(Test-CtxDoctorAgentConfiance -Faits $faits -Contexte 'goldteam')

            $c.Count | Should -Be 1
            $c[0].Domaine | Should -Be 'agent'
            $c[0].Sujet | Should -Be 'confiance/perso'
            $c[0].Verdict | Should -Be 'PROBLEME'
            $c[0].Detail | Should -Match 'perso'
            $c[0].Detail | Should -Match ([regex]::Escape('F:\Apps'))
            $c[0].Correctif | Should -Not -BeNullOrEmpty
        }
    }

    It 'nomme la portee, parce que c est elle qui explique l etendue' {
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'F:\Apps'; Proprietaire = 'perso' }
            )
            $c = @(Test-CtxDoctorAgentConfiance -Faits $faits -Contexte 'goldteam')
            $c[0].Detail | Should -Match 'utilisateur|user'
        }
    }

    It 'se tait sur les etrangers quand il n y a pas de contexte courant' {
        # Sans contexte, "etranger" ne veut rien dire : il n'y a rien a
        # traverser. Inventer une reference vaudrait moins que se taire.
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'projet'; Fichier = 'p'; Dossier = 'F:\Apps'; Proprietaire = 'perso' }
            )
            Test-CtxDoctorAgentConfiance -Faits $faits -Contexte $null | Should -BeNullOrEmpty
        }
    }

    It 'signale les dossiers hors de tout contexte accordes globalement' {
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'C:\Bureau'; Proprietaire = $null }
            )
            $c = @(Test-CtxDoctorAgentConfiance -Faits $faits -Contexte 'perso')

            $c.Count | Should -Be 1
            $c[0].Sujet | Should -Be 'confiance/globale'
            $c[0].Verdict | Should -Be 'ATTENTION'
            $c[0].Detail | Should -Match ([regex]::Escape('C:\Bureau'))
        }
    }

    It 'ne reproche RIEN a un dossier accorde en portee projet' {
        # C'est precisement la bonne pratique que le correctif recommande.
        # La signaler serait apprendre l'inverse de ce qu'on enseigne.
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'projet'; Fichier = 'p'; Dossier = 'C:\Bureau'; Proprietaire = $null }
            )
            Test-CtxDoctorAgentConfiance -Faits $faits -Contexte 'perso' | Should -BeNullOrEmpty
        }
    }

    It 'groupe par contexte proprietaire, dans un ordre stable' {
        # Les cles d'une table de hachage n'ont pas d'ordre garanti, et une
        # sortie dont l'ordre varie rend deux executions incomparables. Le piege
        # est deja enregistre dans AGENTS.md.
        InModuleScope DevContext {
            $faits = @(
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'F:\Z'; Proprietaire = 'zeta' }
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'F:\A'; Proprietaire = 'alpha' }
                [pscustomobject]@{ Portee = 'utilisateur'; Fichier = 'u'; Dossier = 'F:\A2'; Proprietaire = 'alpha' }
            )
            $c = @(Test-CtxDoctorAgentConfiance -Faits $faits -Contexte 'goldteam')

            $c.Count | Should -Be 2
            $c[0].Sujet | Should -Be 'confiance/alpha'
            $c[1].Sujet | Should -Be 'confiance/zeta'
            # Les deux dossiers d'alpha tiennent dans UN constat, pas deux.
            $c[0].Detail | Should -Match ([regex]::Escape('F:\A'))
            $c[0].Detail | Should -Match ([regex]::Escape('F:\A2'))
        }
    }
}

Describe 'Confiance des agents — collecte' {
    # LA PORTEE UTILISATEUR EST NEUTRALISEE, ET C'EST LE POINT.
    #
    # Ecrits sans cela, ces tests lisaient le VRAI fichier de reglages de la
    # machine : ils rendaient 14 dossiers approuves la ou le scenario en
    # decrivait deux, et auraient rendu autre chose sur chaque poste. Un test
    # dont le resultat depend de la machine qui l'execute ne prouve rien
    # ailleurs -- c'est le defaut que tests/README.md nomme explicitement.
    #
    # CLAUDE_CONFIG_DIR pointe donc sur un dossier vide : la portee utilisateur
    # existe toujours, elle est simplement VIDE, ce qui est un etat que le code
    # doit savoir traverser.
    BeforeEach {
        $script:ConfigAvant = $env:CLAUDE_CONFIG_DIR
        $script:ConfigVide = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:ConfigVide -Force
        $env:CLAUDE_CONFIG_DIR = $script:ConfigVide
    }

    AfterEach {
        # RESTAURER, jamais supprimer : effacer une vraie variable desarme les
        # tests qui tournent apres. Deja paye dans ce depot.
        if ($null -ne $script:ConfigAvant) { $env:CLAUDE_CONFIG_DIR = $script:ConfigAvant }
        else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
    }

    It 'cherche aux quatre portees attendues' {
        InModuleScope DevContext {
            $chemins = @(Get-CtxAgentSettingsChemins -Dossier 'F:\projet')
            $chemins.Count | Should -Be 4
            @($chemins | Where-Object { $_.Portee -eq 'projet' }).Count | Should -Be 2
            @($chemins | Where-Object { $_.Portee -eq 'utilisateur' }).Count | Should -Be 2
            @($chemins | Where-Object { $_.Portee -eq 'projet' -and $_.Chemin -like 'F:\projet*' }).Count | Should -Be 2
        }
    }

    It 'suit CLAUDE_CONFIG_DIR quand il deplace le dossier utilisateur' {
        # L'ignorer ferait lire un fichier qui n'est pas celui qui s'applique,
        # et rendre un verdict rassurant sur une liste que personne n'utilise.
        InModuleScope DevContext {
            $avant = $env:CLAUDE_CONFIG_DIR
            try {
                $env:CLAUDE_CONFIG_DIR = 'D:\ailleurs\cfg'
                $chemins = @(Get-CtxAgentSettingsChemins -Dossier 'F:\projet')
                $user = @($chemins | Where-Object { $_.Portee -eq 'utilisateur' })
                $user.Count | Should -Be 2
                foreach ($u in $user) { $u.Chemin | Should -BeLike 'D:\ailleurs\cfg*' }
                # Le segment .claude ne s'ajoute pas une seconde fois.
                foreach ($u in $user) { $u.Chemin | Should -Not -Match '\.claude' }
            }
            finally {
                # RESTAURER, jamais supprimer : un test qui efface une vraie
                # variable desarme ceux qui tournent apres lui. Deja paye ici.
                if ($null -ne $avant) { $env:CLAUDE_CONFIG_DIR = $avant }
                else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
            }
        }
    }

    It 'lit les dossiers approuves d un fichier de projet' {
        InModuleScope DevContext {
            $projet = Join-Path $TestDrive 'projet'
            $null = New-Item -ItemType Directory -Path (Join-Path $projet '.claude') -Force
            '{ "permissions": { "additionalDirectories": ["F:\\Ailleurs", "C:\\Bureau"] } }' |
                Set-Content (Join-Path $projet '.claude\settings.json') -Encoding UTF8

            Mock Resolve-DevContextForPath { $null }
            $faits = @(Get-CtxAgentConfianceFacts -Dossier $projet)

            @($faits | Where-Object { $_.Portee -eq 'projet' }).Count | Should -Be 2
            @($faits | ForEach-Object { $_.Dossier }) | Should -Contain 'F:\Ailleurs'
        }
    }

    It 'resout le proprietaire par Resolve-DevContextForPath' {
        # Reutilisee et non reecrite : c'est elle qui porte le piege de prefixe
        # (Apps ne doit pas matcher Apps-Autre), deja paye trois fois ici.
        InModuleScope DevContext {
            $projet = Join-Path $TestDrive 'projet2'
            $null = New-Item -ItemType Directory -Path (Join-Path $projet '.claude') -Force
            '{ "permissions": { "additionalDirectories": ["F:\\Apps"] } }' |
                Set-Content (Join-Path $projet '.claude\settings.json') -Encoding UTF8

            Mock Resolve-DevContextForPath { [pscustomobject]@{ name = 'perso' } }
            $faits = @(Get-CtxAgentConfianceFacts -Dossier $projet)

            Should -Invoke Resolve-DevContextForPath -Times 1 -Exactly
            $faits[0].Proprietaire | Should -Be 'perso'
        }
    }

    It 'se tait sur un fichier illisible plutot que d accuser a tort' -ForEach @(
        @{ Cas = 'json invalide'; Contenu = 'ceci n est pas du json' }
        @{ Cas = 'vide'; Contenu = '' }
        @{ Cas = 'sans permissions'; Contenu = '{ "model": "opus" }' }
        @{ Cas = 'permissions sans dossiers'; Contenu = '{ "permissions": { "allow": [] } }' }
    ) {
        InModuleScope DevContext -Parameters @{ Contenu = $Contenu } {
            param($Contenu)
            $projet = Join-Path $TestDrive ('cas-' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path (Join-Path $projet '.claude') -Force
            Set-Content (Join-Path $projet '.claude\settings.json') -Value $Contenu -Encoding UTF8

            Mock Resolve-DevContextForPath { $null }
            { Get-CtxAgentConfianceFacts -Dossier $projet } | Should -Not -Throw
            Get-CtxAgentConfianceFacts -Dossier $projet | Should -BeNullOrEmpty
        }
    }
}
