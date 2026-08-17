# Un profil d'editeur porte-t-il l'identite d'un AUTRE contexte ?
#
# CE QUE CE CONTROLE A TROUVE LE JOUR OU IL A ETE ECRIT
#
# 17 aout 2026, sur la machine de l'auteur : le profil du contexte CLIENT
# portait le compte GitHub personnel, et le profil personnel portait celui du
# client. Les deux profils etaient parfaitement isoles -- l'isolation empeche
# les sessions de s'ECRASER, elle n'empeche personne de se connecter au mauvais
# compte DANS le bon profil.
#
# C'est la faute que le module existe pour empecher, et rien ne la signalait.

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
    Import-Module $script:Module -Force
}

Describe 'Test-CtxTexteContientCompte' {
    It 'trouve le compte quand la cle y est' {
        InModuleScope DevContext {
            Test-CtxTexteContientCompte -Texte 'xx github-alice yy' -Login 'alice' | Should -BeTrue
        }
    }

    It 'ne confond PAS un login avec le prefixe d un autre' {
        # LE PIEGE. Une recherche de sous-chaine repond OUI a 'thier' sur
        # 'github-thierryvm', et accuse alors un contexte innocent d'avoir
        # l'identite d'un autre. Meme defaut que 'Apps' matchant 'Apps-Autre'
        # dans la resolution de contexte -- troisieme occurrence ici.
        InModuleScope DevContext {
            Test-CtxTexteContientCompte -Texte 'github-thierryvm' -Login 'thier' | Should -BeFalse
            Test-CtxTexteContientCompte -Texte 'github-alice-bob' -Login 'alice' | Should -BeFalse
            Test-CtxTexteContientCompte -Texte 'github-alice2' -Login 'alice' | Should -BeFalse
        }
    }

    It 'accepte la cle suivie d un caractere qui ne peut pas faire partie d un login' {
        # Les cles voisines dans la base sont collees les unes aux autres, et
        # 'github-alice-usages' est une cle DIFFERENTE ; en revanche un octet
        # binaire ou un guillemet borne bien le login.
        InModuleScope DevContext {
            Test-CtxTexteContientCompte -Texte 'github-alice"suite' -Login 'alice' | Should -BeTrue
            Test-CtxTexteContientCompte -Texte "github-alice`0zz" -Login 'alice' | Should -BeTrue
        }
    }

    It 'ne suppose rien sur une entree vide ou nulle' {
        InModuleScope DevContext {
            Test-CtxTexteContientCompte -Texte '' -Login 'alice' | Should -BeFalse
            Test-CtxTexteContientCompte -Texte 'github-alice' -Login '' | Should -BeFalse
            Test-CtxTexteContientCompte -Texte $null -Login $null | Should -BeFalse
        }
    }

    It 'echappe les caracteres de regex presents dans un login' {
        # Un login ne peut pas contenir de point, mais la fonction ne doit pas
        # dependre de cette garantie externe : un '.' non echappe matcherait
        # n'importe quel caractere.
        InModuleScope DevContext {
            Test-CtxTexteContientCompte -Texte 'github-axb' -Login 'a.b' | Should -BeFalse
        }
    }
}

Describe 'Test-CtxDoctorProfilComptes' {
    It 'se tait quand chaque profil ne porte que son propre compte' {
        # Un rapport qui felicite a chaque ligne finit lu en diagonale.
        InModuleScope DevContext {
            Test-CtxDoctorProfilComptes -Faits @(
                [pscustomobject]@{ Contexte = 'perso'; Attendu = 'alice'; Etrangers = @() }
                [pscustomobject]@{ Contexte = 'client'; Attendu = 'bob'; Etrangers = @() }
            ) | Should -BeNullOrEmpty
        }
    }

    It 'SIGNALE un compte etranger, en le nommant avec son contexte' {
        InModuleScope DevContext {
            $c = @(Test-CtxDoctorProfilComptes -Faits @(
                    [pscustomobject]@{
                        Contexte  = 'client'
                        Attendu   = 'bob'
                        Etrangers = @([pscustomobject]@{ Contexte = 'perso'; Login = 'alice' })
                    }
                ))
            $c.Count | Should -Be 1
            $c[0].Verdict | Should -Be 'PROBLEME'
            $c[0].Domaine | Should -Be 'editeur'
            $c[0].Sujet | Should -Be 'comptes/client'
            $c[0].Detail | Should -Match 'alice'
            $c[0].Detail | Should -Match 'perso'
            $c[0].Detail | Should -Match 'bob'
            # Le correctif doit nommer l'alternative, pas seulement le probleme :
            # se deconnecter casserait la synchro des reglages, et personne
            # n'applique un correctif qui lui retire quelque chose.
            $c[0].Correctif | Should -Match 'MICROSOFT|Microsoft'
        }
    }

    It 'nomme TOUS les comptes etrangers, pas seulement le premier' {
        InModuleScope DevContext {
            $c = @(Test-CtxDoctorProfilComptes -Faits @(
                    [pscustomobject]@{
                        Contexte  = 'client'
                        Attendu   = 'bob'
                        Etrangers = @(
                            [pscustomobject]@{ Contexte = 'perso'; Login = 'alice' }
                            [pscustomobject]@{ Contexte = 'autre'; Login = 'carol' }
                        )
                    }
                ))
            $c[0].Detail | Should -Match 'alice'
            $c[0].Detail | Should -Match 'carol'
        }
    }

    It 'rend un constat PAR contexte concerne' {
        InModuleScope DevContext {
            $c = @(Test-CtxDoctorProfilComptes -Faits @(
                    [pscustomobject]@{ Contexte = 'a'; Attendu = 'x'; Etrangers = @([pscustomobject]@{ Contexte = 'b'; Login = 'y' }) }
                    [pscustomobject]@{ Contexte = 'b'; Attendu = 'y'; Etrangers = @([pscustomobject]@{ Contexte = 'a'; Login = 'x' }) }
                ))
            $c.Count | Should -Be 2
            @($c.Sujet) | Should -Contain 'comptes/a'
            @($c.Sujet) | Should -Contain 'comptes/b'
        }
    }
}

Describe 'Get-CtxProfilComptesFacts' {
    BeforeAll {
        # De faux profils : le controle doit se verifier sans dependre des
        # comptes reellement connectes sur la machine qui lance les tests.
        $script:racine = Join-Path $TestDrive 'profils'
        foreach ($n in 'perso', 'client', 'vide') {
            $d = Join-Path $script:racine $n
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        # perso  : porte son compte ET celui du client -> croisement
        Set-Content (Join-Path $script:racine 'perso\state.vscdb') -Value 'zz github-alice zz github-bob zz' -Encoding ascii
        # client : ne porte que le sien -> propre
        Set-Content (Join-Path $script:racine 'client\state.vscdb') -Value 'zz github-bob zz' -Encoding ascii

        $script:lecteur = {
            param($Contexte)
            Join-Path $script:racine "$Contexte\state.vscdb"
        }
        $script:manifestes = @(
            [pscustomobject]@{ name = 'perso'; github = [pscustomobject]@{ login = 'alice' } }
            [pscustomobject]@{ name = 'client'; github = [pscustomobject]@{ login = 'bob' } }
        )
    }

    It 'detecte le croisement, et seulement la ou il est' {
        InModuleScope DevContext -Parameters @{ L = $script:lecteur; M = $script:manifestes } { param($L, $M)
            $f = @(Get-CtxProfilComptesFacts -Manifestes $M -LecteurProfil $L)

            $perso = $f | Where-Object Contexte -eq 'perso'
            @($perso.Etrangers).Count | Should -Be 1
            $perso.Etrangers[0].Login | Should -Be 'bob'

            $client = $f | Where-Object Contexte -eq 'client'
            @($client.Etrangers).Count | Should -Be 0
        }
    }

    It 'se tait quand un seul contexte declare un login -- rien a croiser' {
        InModuleScope DevContext -Parameters @{ L = $script:lecteur } { param($L)
            Get-CtxProfilComptesFacts -LecteurProfil $L -Manifestes @(
                [pscustomobject]@{ name = 'perso'; github = [pscustomobject]@{ login = 'alice' } }
            ) | Should -BeNullOrEmpty
        }
    }

    It 'ignore un contexte sans login declare plutot que de lever' {
        # Un manifeste sans 'github.login' est legitime -- `ctx` le signale
        # deja. Ce controle ne doit ni planter ni inventer un login.
        InModuleScope DevContext -Parameters @{ L = $script:lecteur } { param($L)
            { Get-CtxProfilComptesFacts -LecteurProfil $L -Manifestes @(
                    [pscustomobject]@{ name = 'perso'; github = [pscustomobject]@{ login = 'alice' } }
                    [pscustomobject]@{ name = 'client' }
                ) } | Should -Not -Throw
        }
    }

    It 'ignore un profil dont la base n existe pas' {
        InModuleScope DevContext -Parameters @{ L = $script:lecteur; M = $script:manifestes } { param($L, $M)
            $f = @(Get-CtxProfilComptesFacts -Manifestes ($M + [pscustomobject]@{
                        name = 'jamaisOuvert'; github = [pscustomobject]@{ login = 'dave' }
                    }) -LecteurProfil $L)
            @($f | Where-Object Contexte -eq 'jamaisOuvert') | Should -BeNullOrEmpty
        }
    }

    It 'lit une base VERROUILLEE par l editeur' {
        # VS Code tient state.vscdb ouvert en permanence. Un diagnostic qui
        # echoue parce que l'editeur tourne ne servirait jamais, puisque c'est
        # exactement le moment ou on le lance.
        InModuleScope DevContext -Parameters @{ L = $script:lecteur; M = $script:manifestes; R = $script:racine } { param($L, $M, $R)
            $chemin = Join-Path $R 'perso\state.vscdb'
            $verrou = [System.IO.File]::Open($chemin, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read)
            try {
                $f = @(Get-CtxProfilComptesFacts -Manifestes $M -LecteurProfil $L)
                @($f | Where-Object Contexte -eq 'perso').Etrangers.Count | Should -Be 1
            }
            finally { $verrou.Dispose() }
        }
    }
}
