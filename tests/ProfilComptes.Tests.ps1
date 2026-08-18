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

Describe 'Get-CtxSqliteTexteVivant' {
    # LE DEFAUT, MESURE LE 18 AOUT 2026.
    #
    # Le controle lisait state.vscdb en entier et y cherchait un login. Apres
    # une deconnexion REELLE -- confirmee dans le menu Comptes de la fenetre,
    # capture a l'appui -- le nom etait toujours dans le fichier, et le
    # diagnostic accusait encore un profil propre. Aucune action de
    # l'utilisateur ne pouvait effacer ce verdict.
    #
    # SQLite ne reecrit pas ce qu'il libere : `secure_delete` est desactive par
    # defaut. Lire le fichier entier, c'est lire le present ET le passe sans
    # pouvoir les distinguer.
    #
    # LE MONDE FAUX. Un fichier SQLite construit octet par octet, avec un
    # fragment vivant et un fragment mort dans chacun des trois endroits ou du
    # texte peut survivre a sa suppression. Aucune base reelle n'est ouverte :
    # ce qui est teste ici est une lecture de format, pas un moteur.

    BeforeAll {
        $script:Faux = {
            $taille = 512
            $o = New-Object byte[] ($taille * 4)

            $mettre = {
                param([int]$Pos, [string]$Texte)
                $b = [System.Text.Encoding]::ASCII.GetBytes($Texte)
                [Array]::Copy($b, 0, $o, $Pos, $b.Length)
            }

            # --- entete de base ---
            & $mettre 0 "SQLite format 3"
            $o[15] = 0
            $o[16] = 2; $o[17] = 0                       # taille de page : 512
            $o[32] = 0; $o[33] = 0; $o[34] = 0; $o[35] = 3   # premiere page tronc de la liste libre
            $o[36] = 0; $o[37] = 0; $o[38] = 0; $o[39] = 2   # 2 pages libres

            # --- page 1 : feuille b-tree, entete a 100 ---
            $o[100] = 13                                  # feuille de table
            $o[101] = 0; $o[102] = 0                      # aucun bloc libere
            $o[103] = 0; $o[104] = 1                      # 1 cellule
            $o[105] = 1; $o[106] = 144                    # contenu commence a 400
            & $mettre 150 " github-mortgap "              # espace non alloue : MORT
            & $mettre 400 " github-vivantun "             # zone de contenu : VIVANT

            # --- page 2 : feuille b-tree avec un bloc libere ---
            $b2 = 512
            $o[$b2] = 13
            $o[$b2 + 1] = 0; $o[$b2 + 2] = 200            # premier bloc libere a 200
            $o[$b2 + 3] = 0; $o[$b2 + 4] = 2
            $o[$b2 + 5] = 0; $o[$b2 + 6] = 100            # contenu commence a 100
            $o[$b2 + 200] = 0; $o[$b2 + 201] = 0          # bloc suivant : aucun
            $o[$b2 + 202] = 0; $o[$b2 + 203] = 60         # taille du bloc : 60
            & $mettre ($b2 + 120) " github-vivantdeux "   # dans le contenu : VIVANT
            & $mettre ($b2 + 210) " github-mortbloc "     # dans le bloc libere : MORT

            # --- page 3 : page tronc de la liste libre ---
            $b3 = 1024
            $o[$b3 + 4] = 0; $o[$b3 + 5] = 0; $o[$b3 + 6] = 0; $o[$b3 + 7] = 1
            $o[$b3 + 8] = 0; $o[$b3 + 9] = 0; $o[$b3 + 10] = 0; $o[$b3 + 11] = 4
            & $mettre ($b3 + 100) " github-morttronc "    # page libre : MORT

            # --- page 4 : feuille de la liste libre ---
            & $mettre (1536 + 50) " github-mortfeuille "  # page libre : MORT

            $o
        }
    }

    It 'garde ce qui vit dans la zone de contenu' {
        $octets = & $script:Faux
        InModuleScope DevContext -Parameters @{ Octets = $octets } {
            param($Octets)
            $t = Get-CtxSqliteTexteVivant -Octets $Octets
            $t | Should -Match 'github-vivantun'
            $t | Should -Match 'github-vivantdeux'
        }
    }

    It 'jette l espace non alloue, les blocs liberes et les pages libres' {
        # Les trois endroits ou une chaine survit a sa suppression. Chacun a
        # coute une accusation a tort sur une machine reelle.
        $octets = & $script:Faux
        InModuleScope DevContext -Parameters @{ Octets = $octets } {
            param($Octets)
            $t = Get-CtxSqliteTexteVivant -Octets $Octets
            $t | Should -Not -Match 'github-mortgap'
            $t | Should -Not -Match 'github-mortbloc'
            $t | Should -Not -Match 'github-morttronc'
            $t | Should -Not -Match 'github-mortfeuille'
        }
    }

    It 'degrade vers le texte brut quand ce n est pas du SQLite' {
        # Un format qu'on ne reconnait plus doit devenir TROP BAVARD, jamais
        # aveugle : un faux positif se voit, un faux negatif non.
        InModuleScope DevContext {
            $o = New-Object byte[] 600
            $b = [System.Text.Encoding]::ASCII.GetBytes(' github-quelquun ')
            [Array]::Copy($b, 0, $o, 300, $b.Length)
            Get-CtxSqliteTexteVivant -Octets $o | Should -Match 'github-quelquun'
        }
    }

    It 'ne rend rien sur une entree nulle, et replie sur le brut si c est court' {
        # ATTENDU CORRIGE, ET DIT PLUTOT QUE CHANGE EN SILENCE. Ce test exigeait
        # d'abord que 10 octets ne rendent rien. C'etait faux : le minimum de
        # 512 octets appartient au FORMAT SQLite, pas a cette fonction. Ecrit
        # ainsi, il rendait aveugle toute lecture d'un fichier court -- et deux
        # tests deja en place l'ont attrape en rougissant.
        InModuleScope DevContext {
            Get-CtxSqliteTexteVivant -Octets $null | Should -BeNullOrEmpty

            $o = New-Object byte[] 40
            $b = [System.Text.Encoding]::ASCII.GetBytes(' github-court ')
            [Array]::Copy($b, 0, $o, 5, $b.Length)
            Get-CtxSqliteTexteVivant -Octets $o | Should -Match 'github-court'
        }
    }
}

Describe 'Get-CtxProfilComptesFacts, sur un magasin qui garde des octets morts' {
    It 'n accuse PAS un profil dont le compte etranger n est plus que dans le vide' {
        # LE CAS REEL DU 18 AOUT 2026, reduit a deux profils. Celui qui a ete
        # nettoye doit se taire ; celui qui porte encore l'autre compte doit
        # continuer de parler. Un correctif qui ferait taire les deux ne serait
        # pas un correctif, ce serait un interrupteur.
        $taille = 512
        $construire = {
            param([string]$Vivant, [string]$Mort)
            $o = New-Object byte[] ($taille * 2)
            $mettre = {
                param([int]$Pos, [string]$Texte)
                $b = [System.Text.Encoding]::ASCII.GetBytes($Texte)
                [Array]::Copy($b, 0, $o, $Pos, $b.Length)
            }
            & $mettre 0 "SQLite format 3"
            $o[15] = 0
            $o[16] = 2; $o[17] = 0
            $o[32] = 0; $o[33] = 0; $o[34] = 0; $o[35] = 2   # page 2 : libre
            $o[36] = 0; $o[37] = 0; $o[38] = 0; $o[39] = 1
            $o[100] = 13
            $o[101] = 0; $o[102] = 0
            $o[103] = 0; $o[104] = 1
            $o[105] = 1; $o[106] = 144                       # contenu a 400
            if ($Vivant) { & $mettre 400 (" github-$Vivant ") }
            if ($Mort) { & $mettre (512 + 100) (" github-$Mort ") }
            $o
        }

        $propre = Join-Path $TestDrive 'propre.vscdb'
        $sale = Join-Path $TestDrive 'sale.vscdb'
        # 'propre' : bob n'existe plus que dans une page libre.
        [IO.File]::WriteAllBytes($propre, (& $construire 'alice' 'bob'))
        # 'sale' : alice est bien vivante dans le contenu.
        [IO.File]::WriteAllBytes($sale, (& $construire 'alice' $null))

        InModuleScope DevContext -Parameters @{ Propre = $propre; Sale = $sale } {
            param($Propre, $Sale)
            $manifestes = @(
                [pscustomobject]@{ name = 'alpha'; github = [pscustomobject]@{ login = 'alice' } }
                [pscustomobject]@{ name = 'beta'; github = [pscustomobject]@{ login = 'bob' } }
            )
            $lecteur = {
                param($Contexte)
                if ($Contexte -eq 'alpha') { $Propre } else { $Sale }
            }.GetNewClosure()

            $faits = @(Get-CtxProfilComptesFacts -Manifestes $manifestes -LecteurProfil $lecteur)
            $faits.Count | Should -Be 2

            $alpha = $faits | Where-Object { $_.Contexte -eq 'alpha' }
            @($alpha.Etrangers).Count | Should -Be 0 -Because 'bob n est plus que dans une page libre : le nom traine, la session est partie'

            $beta = $faits | Where-Object { $_.Contexte -eq 'beta' }
            @($beta.Etrangers).Count | Should -Be 1 -Because 'alice vit dans la zone de contenu : le croisement est reel et doit rester signale'
            $beta.Etrangers[0].Login | Should -Be 'alice'
        }
    }
}
