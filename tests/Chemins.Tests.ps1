# Le chemin stable des shims, et la jonction qui l'y mene.
#
# POURQUOI CE FICHIER EXISTE. Le 15 aout 2026, jour de la publication sur
# PowerShell Gallery, l'installateur posait dans PATH le dossier `shims` DU
# MODULE. Sur la machine de l'auteur, ou le module est un lien symbolique vers un
# depot, ce chemin ne bouge jamais et rien ne se voyait. Installe depuis la
# Gallery, le module vit sous ...\Modules\DevContext\1.3.0\ : le numero de
# version est dans le chemin, et la mise a jour suivante laisse PATH derriere
# elle.
#
# Le defaut n'etait donc visible sur AUCUNE machine avant la publication -- meme
# schema que les cinq impasses de la machine vierge, et que le code decidant sur
# du texte traduit : ce qui casse est ce que l'auteur n'est pas en position de
# voir.
#
# Aucun test ici n'ecrit dans PATH ni dans le registre. Les fonctions prennent
# leurs sources en parametres, ce qui est toute la raison de les avoir separees.

BeforeAll {
    $script:Racine = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force
}

Describe 'Le chemin stable ne porte aucun numero de version' {
    It 'se construit sous LOCALAPPDATA' {
        InModuleScope DevContext {
            $stable = Get-CtxShimStable -Lien (Get-CtxShimLien -Racine (Get-CtxShimRacine -Base 'C:\base'))
            $stable | Should -Be 'C:\base\DevContext\current\shims'
        }
    }

    It 'ne contient jamais de segment ressemblant a une version' {
        # L'assertion qui porte tout le correctif. Un chemin qui contient
        # « 1.3.0 » est un chemin qui se perime a la mise a jour suivante.
        InModuleScope DevContext {
            Get-CtxShimStable | Should -Not -Match '\\\d+\.\d+\.\d+(\\|$)'
        }
    }

    It 'tient quand LOCALAPPDATA est absent de l environnement' {
        # Un service, une tache planifiee, un shell minimal : la variable peut
        # manquer. [IO.Path]::Combine avec une chaine vide rendrait un chemin
        # relatif, donc une entree PATH qui designe le dossier courant.
        InModuleScope DevContext {
            $r = Get-CtxShimRacine -Base ''
            $r | Should -Not -BeNullOrEmpty
            [System.IO.Path]::IsPathRooted($r) | Should -BeTrue
        }
    }

    It 'la jonction pointe sur la RACINE du module, pas sur shims' {
        # Ce qui garde `..\DevContext.psd1` valide depuis l'interieur du dossier
        # shims. Faire pointer la jonction sur shims lui-meme casserait la
        # resolution du module : le shim tomberait dans son catch et deleguerait
        # sans jamais garder.
        InModuleScope DevContext {
            Split-Path (Get-CtxShimLien) -Leaf | Should -Be 'current'
            Split-Path (Get-CtxShimStable) -Leaf | Should -Be 'shims'
            Split-Path (Get-CtxShimStable) -Parent | Should -Be (Get-CtxShimLien)
        }
    }
}

Describe 'Test-CtxDossierEstShim' {
    It 'reconnait <Cas>' -ForEach @(
        @{ Cas = 'le chemin exact';            Dossier = 'C:\a\shims' }
        @{ Cas = 'une casse differente';       Dossier = 'C:\A\SHIMS' }
        @{ Cas = 'un separateur final';        Dossier = 'C:\a\shims\' }
        @{ Cas = 'les deux a la fois';         Dossier = 'C:\A\Shims\' }
    ) {
        InModuleScope DevContext -Parameters @{ d = $Dossier } { param($d)
            Test-CtxDossierEstShim -Dossier $d -Dossiers @('C:\a\shims') | Should -BeTrue
        }
    }

    It 'ne confond pas un dossier dont le nom commence pareil' {
        # Le piege du prefixe, deja rencontre sur la resolution de contexte :
        # « Apps » ne doit pas matcher « Apps-Autre ».
        InModuleScope DevContext {
            Test-CtxDossierEstShim -Dossier 'C:\a\shims-autre' -Dossiers @('C:\a\shims') | Should -BeFalse
        }
    }

    It 'rend faux sur une entree vide plutot que de lever' {
        InModuleScope DevContext {
            Test-CtxDossierEstShim -Dossier '' -Dossiers @('C:\a\shims') | Should -BeFalse
            Test-CtxDossierEstShim -Dossier 'C:\a\shims' -Dossiers @() | Should -BeFalse
        }
    }
}

Describe 'Test-CtxDossierEstShimDevContext reconnait par le CONTENU' {
    # POURQUOI CETTE SECONDE EPREUVE. Comparer des noms ne peut pas suffire, et
    # ce fichier le disait deja plus bas sans que l'implementation l'honore :
    # « les chemins mentent volontiers ». Un meme dossier de shims porte
    # aujourd'hui TROIS noms sur cette machine -- le depot, le lien symbolique
    # des modules, la jonction de PATH -- et une entree ecrite a la main dans
    # PATH en donnerait un quatrieme.
    #
    # Les marqueurs sont PORTEURS : editor.ps1 et supabase.ps1 sont ce que les
    # shims executent. On ne peut pas les retirer sans supprimer la
    # fonctionnalite, donc l'identite ne peut pas se perimer en silence.

    It 'reconnait un dossier de shims atteint sous un nom que personne ne liste' {
        $faux = Join-Path $TestDrive 'un-quatrieme-nom'
        New-Item -ItemType Directory -Path $faux | Out-Null
        Set-Content -LiteralPath (Join-Path $faux 'editor.ps1')   -Value '# marqueur'
        Set-Content -LiteralPath (Join-Path $faux 'supabase.ps1') -Value '# marqueur'

        InModuleScope DevContext -Parameters @{ d = $faux } { param($d)
            Test-CtxDossierEstShimDevContext -Dossier $d -Dossiers @('C:\a\shims') | Should -BeTrue
        }
    }

    It 'ne prend pas pour un shim un dossier qui ne porte qu un seul marqueur' {
        $presque = Join-Path $TestDrive 'presque'
        New-Item -ItemType Directory -Path $presque | Out-Null
        Set-Content -LiteralPath (Join-Path $presque 'editor.ps1') -Value '# marqueur'

        InModuleScope DevContext -Parameters @{ d = $presque } { param($d)
            Test-CtxDossierEstShimDevContext -Dossier $d -Dossiers @('C:\a\shims') | Should -BeFalse
        }
    }

    It 'garde l epreuve par le nom, sans disque' {
        InModuleScope DevContext {
            Test-CtxDossierEstShimDevContext -Dossier 'C:\a\shims' -Dossiers @('C:\a\shims') | Should -BeTrue
            Test-CtxDossierEstShimDevContext -Dossier 'C:\a\shims-autre' -Dossiers @('C:\a\shims') | Should -BeFalse
            Test-CtxDossierEstShimDevContext -Dossier '' -Dossiers @('C:\a\shims') | Should -BeFalse
        }
    }

    It 'les fichiers marqueurs existent reellement dans shims/' {
        # LE GARDE-FOU DE L IDENTITE. Sans lui, renommer un shim desarmerait la
        # reconnaissance par le contenu en silence -- et on repartirait pour un
        # tour de « le shim se prend pour l editeur ».
        InModuleScope DevContext {
            foreach ($m in $script:CtxShimMarqueurs) {
                Join-Path $script:ShimDir $m | Should -Exist
            }
        }
    }
}

Describe 'Get-CtxSupabaseExe ecarte TOUS nos dossiers' {
    # LE TEST QUI COMPTE. L'exclusion comparait a UN chemin -- celui du module.
    # Des lors que PATH designe la jonction, Get-Command rend
    # ...\DevContext\current\shims\supabase.cmd, une chaine differente : le shim
    # ne se reconnaissait plus, se resolvait lui-meme, et s'appelait sans fin.

    It 'ecarte le dossier du module ET le chemin stable' {
        InModuleScope DevContext {
            $stable = Get-CtxShimStable
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @(
                    [pscustomobject]@{ Source = (Join-Path (Get-CtxShimStable) 'supabase.cmd') }
                    [pscustomobject]@{ Source = (Join-Path $script:ShimDir 'supabase.cmd') }
                    [pscustomobject]@{ Source = 'C:\ailleurs\supabase.exe' }
                )
            }
            Get-CtxSupabaseExe | Should -Be 'C:\ailleurs\supabase.exe'
            $stable | Should -Not -BeNullOrEmpty
        }
    }

    It 'dit QUEL dossier a ete ecarte, au lieu d annoncer une absence' {
        # POURQUOI. L'identification par contenu echoue fermee -- elle fait lever,
        # jamais executer -- et c'est le bon sens pour un module qui garde une base
        # de production. Mais le message, lui, mentait sur sa cause : un dossier qui
        # porte par hasard editor.ps1 et supabase.ps1 rendait « supabase
        # introuvable » alors que le binaire etait bien la.
        #
        # Un utilisateur bloque par un message faux contourne le wrapper et appelle
        # le binaire brut -- donc SANS garde. Le message est donc le dernier endroit
        # ou l'on a le droit d'etre imprecis.
        #
        # Assertion sur le CHEMIN et non sur du texte : la suite tourne en fr et en
        # en, et comparer une phrase traduite est le defaut que ce depot a deja paye
        # quatre fois.
        $faux = Join-Path $TestDrive 'faux-positif'
        New-Item -ItemType Directory -Path $faux | Out-Null
        Set-Content -LiteralPath (Join-Path $faux 'editor.ps1')   -Value '# marqueur'
        Set-Content -LiteralPath (Join-Path $faux 'supabase.ps1') -Value '# marqueur'

        InModuleScope DevContext -Parameters @{ d = $faux } { param($d)
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @([pscustomobject]@{ Source = (Join-Path $d 'supabase.exe') })
            }
            { Get-CtxSupabaseExe } | Should -Throw ("*" + $d + "*")
        }
    }

    It 'garde le message d absence quand PATH ne propose vraiment rien' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } { @() }
            # Aucun chemin a nommer : le message d origine est le bon.
            { Get-CtxSupabaseExe } | Should -Throw (T 'bin.supabaseAbsent')
        }
    }

    It 'leve quand il ne reste que des shims, plutot que d en appeler un' {
        # Lever est le bon comportement : rendre un shim ici, c'est la boucle.
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @(
                    [pscustomobject]@{ Source = (Join-Path (Get-CtxShimStable) 'supabase.cmd') }
                    [pscustomobject]@{ Source = (Join-Path $script:ShimDir 'supabase') }
                )
            }
            { Get-CtxSupabaseExe } | Should -Throw '*supabase*'
        }
    }

    It 'Get-CtxShimDirs contient les deux formes, sans doublon' {
        InModuleScope DevContext {
            $d = @(Get-CtxShimDirs)
            $d.Count | Should -BeGreaterOrEqual 2
            $d | Should -Contain $script:ShimDir.TrimEnd('\', '/')
            $d | Should -Contain (Get-CtxShimStable).TrimEnd('\', '/')
            ($d | Sort-Object -Unique).Count | Should -Be $d.Count
        }
    }
}

Describe 'Les shims interrompent une boucle par compteur' {
    # Un compteur plutot qu'une comparaison de chemins : les chemins mentent
    # volontiers -- jonctions, casse, noms 8.3, lecteurs subst, UNC.
    It 'shims/<Fichier> lit DEVCTX_SHIM_DEPTH et sort avant de boucler' -ForEach @(
        @{ Fichier = 'supabase.ps1' }
        @{ Fichier = 'editor.ps1' }
    ) {
        $code = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'shims' $Fichier) -Raw
        $code | Should -Match 'DEVCTX_SHIM_DEPTH'
        $code | Should -Match '\$Profondeur\s+-ge\s+\d'
    }

    It 'ne saute JAMAIS le garde-fou quand la variable est posee' {
        # Une premiere version deleguait au binaire reel des la deuxieme entree,
        # ce qui donnait un contournement complet a qui posait
        # DEVCTX_SHIM_DEPTH=1 avant sa commande. Le compteur doit interrompre,
        # jamais desarmer : poser la variable a la main ne peut produire qu un
        # refus, jamais un passe-droit.
        $code = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'shims' 'supabase.ps1') -Raw
        $bloc = [regex]::Match($code, '(?s)if \(\$Profondeur\s+-ge.*?\}').Value
        $bloc | Should -Not -BeNullOrEmpty
        $bloc | Should -Match 'exit 1'
        $bloc | Should -Not -Match 'Invoke-Real'
    }
}

Describe 'La jonction' {
    BeforeAll {
        $script:Bac    = Join-Path ([System.IO.Path]::GetTempPath()) "devctx-jonction-$PID"
        $script:CibleA = Join-Path $script:Bac 'module-1.3.0'
        $script:CibleB = Join-Path $script:Bac 'module-1.4.0'
        $script:Lien   = Join-Path $script:Bac 'current'
        foreach ($d in $script:CibleA, $script:CibleB) {
            New-Item -ItemType Directory -Path (Join-Path $d 'shims') -Force | Out-Null
        }
        Set-Content (Join-Path $script:CibleA 'DevContext.psd1') '# 1.3.0'
        Set-Content (Join-Path $script:CibleB 'DevContext.psd1') '# 1.4.0'
    }

    AfterAll {
        InModuleScope DevContext -Parameters @{ l = $script:Lien } { param($l)
            Remove-CtxJonction -Chemin $l -ErrorAction SilentlyContinue | Out-Null
        }
        if (Test-Path $script:Bac) { Remove-Item $script:Bac -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'se pose, et le manifeste du module est visible a travers' {
        # La propriete qui justifie une jonction plutot qu une copie : le chemin
        # relatif `..\DevContext.psd1` doit rester valide depuis l interieur.
        InModuleScope DevContext -Parameters @{ l = $script:Lien; c = $script:CibleA } { param($l, $c)
            Set-CtxJonction -Chemin $l -Cible $c | Out-Null
            Test-Path (Join-Path $l 'DevContext.psd1') | Should -BeTrue
            Test-Path (Join-Path $l 'shims') | Should -BeTrue
        }
    }

    It 'se repointe vers une nouvelle version sans que le chemin change' {
        # Le coeur du correctif : la mise a jour deplace la CIBLE, jamais
        # l entree PATH.
        InModuleScope DevContext -Parameters @{ l = $script:Lien; c = $script:CibleB } { param($l, $c)
            Set-CtxJonction -Chemin $l -Cible $c | Out-Null
            (Get-Content (Join-Path $l 'DevContext.psd1') -Raw).Trim() | Should -Be '# 1.4.0'
        }
    }

    It 'Test-CtxJonctionSaine compare sans egard pour la casse ni le separateur' {
        InModuleScope DevContext {
            Test-CtxJonctionSaine -Cible 'C:\A\Mod\' -ModuleAttendu 'c:\a\mod' | Should -BeTrue
            Test-CtxJonctionSaine -Cible 'C:\autre'  -ModuleAttendu 'C:\a\mod' | Should -BeFalse
            Test-CtxJonctionSaine -Cible $null       -ModuleAttendu 'C:\a\mod' | Should -BeFalse
        }
    }

    It 'Test-CtxJonctionSaine compare les dossiers REELS, pas leurs noms' {
        # MESURE SUR LA MACHINE DE L AUTEUR LE 16 AOUT 2026. `ctx doctor` rendait
        # PROBLEME sur son propre garde-fou :
        #
        #   la jonction pointe sur F:\...\devcontext
        #   le module charge est   ...\Documents\PowerShell\Modules\DevContext
        #
        # Deux chaines, UN dossier -- le second est un lien symbolique vers le
        # premier. Le garde-fou tournait sur le bon code et le diagnostic
        # annoncait une version perimee.
        #
        # Cinquieme occurrence du meme defaut. Ici le cout est le pire de tous :
        # un diagnostic qui accuse a tort le mecanisme qu il surveille apprend a
        # son lecteur a l ignorer, et ce lecteur ratera la vraie panne.
        #
        # Resolveur injecte : la decision reste verifiable sans lien sur disque.
        InModuleScope DevContext {
            $faux = { param($p) if ($p -match 'lien') { 'C:\reel\module' } else { $p } }
            Test-CtxJonctionSaine -Cible 'C:\reel\module' -ModuleAttendu 'C:\chemin\du\lien' -Resolveur $faux |
                Should -BeTrue
            Test-CtxJonctionSaine -Cible 'C:\reel\module' -ModuleAttendu 'C:\ailleurs' -Resolveur $faux |
                Should -BeFalse
        }
    }

    It 'Resolve-CtxCheminReel suit une vraie jonction' {
        $reel = Join-Path $TestDrive 'cible-reelle'
        $lien = Join-Path $TestDrive 'la-jonction'
        New-Item -ItemType Directory -Path $reel | Out-Null
        New-Item -ItemType Junction -Path $lien -Target $reel | Out-Null

        InModuleScope DevContext -Parameters @{ l = $lien; r = $reel } { param($l, $r)
            (Resolve-CtxCheminReel -Chemin $l).TrimEnd('\') | Should -Be $r.TrimEnd('\')
        }
    }

    It 'Resolve-CtxCheminReel rend le chemin tel quel quand rien n est a suivre' {
        $simple = Join-Path $TestDrive 'dossier-ordinaire'
        New-Item -ItemType Directory -Path $simple | Out-Null

        InModuleScope DevContext -Parameters @{ s = $simple } { param($s)
            (Resolve-CtxCheminReel -Chemin $s).TrimEnd('\') | Should -Be $s.TrimEnd('\')
            # Un chemin absent ne doit pas lever : le doctor l appelle sur ce qu il
            # trouve, pas sur ce qu il espere.
            Resolve-CtxCheminReel -Chemin 'C:\ce\qui\n\existe\pas' | Should -Be 'C:\ce\qui\n\existe\pas'
            Resolve-CtxCheminReel -Chemin '' | Should -BeNullOrEmpty
        }
    }

    It 'REFUSE d ecraser un vrai dossier' {
        # Un installateur qui efface ce qu il n a pas pose finit par effacer
        # autre chose. Meme regle que les points d entree, reconnus a leur marque
        # et jamais a leur nom.
        $vrai = Join-Path $script:Bac 'occupe'
        New-Item -ItemType Directory -Path $vrai -Force | Out-Null
        Set-Content (Join-Path $vrai 'important.txt') 'a ne pas perdre'

        InModuleScope DevContext -Parameters @{ v = $vrai; c = $script:CibleA } { param($v, $c)
            { Set-CtxJonction -Chemin $v -Cible $c } | Should -Throw '*jonction*'
        }
        Test-Path (Join-Path $vrai 'important.txt') | Should -BeTrue
    }

    It 'leve plutot que de pointer vers une cible inexistante' {
        InModuleScope DevContext -Parameters @{ b = $script:Bac } { param($b)
            { Set-CtxJonction -Chemin (Join-Path $b 'x') -Cible (Join-Path $b 'nexiste-pas') } |
                Should -Throw
        }
    }

    It 'se retire sans emporter le contenu de la cible' {
        # Remove-Item -Recurse sur une jonction a, dans l histoire de PowerShell,
        # supprime le contenu de la CIBLE. On passe par Directory.Delete.
        InModuleScope DevContext -Parameters @{ l = $script:Lien; c = $script:CibleB } { param($l, $c)
            Set-CtxJonction -Chemin $l -Cible $c | Out-Null
            Remove-CtxJonction -Chemin $l | Should -BeTrue
            Test-Path $l | Should -BeFalse
            Test-Path (Join-Path $c 'DevContext.psd1') | Should -BeTrue
        }
    }

    It 'retirer une jonction absente rend faux, sans lever' {
        InModuleScope DevContext -Parameters @{ b = $script:Bac } { param($b)
            Remove-CtxJonction -Chemin (Join-Path $b 'jamais-posee') | Should -BeFalse
        }
    }

    It 'ne retire pas un vrai dossier qu on lui designe' {
        $vrai = Join-Path $script:Bac 'occupe'
        InModuleScope DevContext -Parameters @{ v = $vrai } { param($v)
            Remove-CtxJonction -Chemin $v | Should -BeFalse
        }
        Test-Path (Join-Path $vrai 'important.txt') | Should -BeTrue
    }
}
