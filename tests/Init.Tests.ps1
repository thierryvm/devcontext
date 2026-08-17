# `ctx init` -- la premiere commande, celle ou l'adoption se gagne ou se perd.
#
# CE QUE CES TESTS TIENNENT
#
# Deux garanties, et la seconde est celle qu'on oublie :
#
#   1. Sur une machine vierge, la commande dit quoi faire, dans l'ordre.
#   2. Sur une entree REDIRIGEE -- un agent, une tache planifiee, un pipe --
#      elle ne pose aucune question. Une invite n'y met pas en pause : elle lit
#      une fin de fichier et prend un defaut que personne n'a choisi. Ce depot a
#      deja paye cette lecon avec `ctx-new`, qui bloquait sur une demande de
#      passphrase impossible a satisfaire.
#
# Tout est injecte : ces tests n'installent rien, ne lisent pas la machine qui
# les fait tourner, et decrivent donc une machine vierge sans en avoir une.

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
    Import-Module $script:Module -Force

    # La sortie REELLE de `gh auth status`, relevee le 17 aout 2026. Ecrire le
    # test contre une supposition de format aurait valide un analyseur qui ne
    # lit rien de ce que la CLI produit vraiment.
    $script:StatutGh = @'
github.com
  v Logged in to github.com account octo-dev (keyring)
  - Active account: true
  - Git operations protocol: ssh
  - Token: gho_************************************
  - Token scopes: 'gist', 'read:org', 'repo', 'workflow'
'@
}

Describe 'Get-CtxGhComptesDepuisStatut' {
    It 'lit le login dans la sortie reelle de gh auth status' {
        InModuleScope DevContext -Parameters @{ S = $script:StatutGh } { param($S)
            @(Get-CtxGhComptesDepuisStatut -Texte $S) | Should -Be @('octo-dev')
        }
    }

    It 'lit PLUSIEURS comptes, sans doublon' {
        InModuleScope DevContext {
            $t = @'
github.com
  v Logged in to github.com account alice (keyring)
  - Active account: true
  v Logged in to github.com account bob (keyring)
  - Active account: false
  v Logged in to github.com account alice (keyring)
'@
            @(Get-CtxGhComptesDepuisStatut -Texte $t) | Should -Be @('alice', 'bob')
        }
    }

    It 'ne ramasse ni le jeton ni les portees des lignes voisines' {
        # Ces lignes contiennent un jeton masque. Un analyseur trop large le
        # ferait remonter dans une proposition affichee a l'ecran.
        InModuleScope DevContext -Parameters @{ S = $script:StatutGh } { param($S)
            $c = @(Get-CtxGhComptesDepuisStatut -Texte $S)
            $c | Should -Not -Contain 'gho_************************************'
            $c.Count | Should -Be 1
        }
    }

    It 'rend un tableau vide plutot que de lever, quoi qu on lui donne' {
        # FAIL-SOFT PAR CONSTRUCTION : ce resultat ne sert qu'a pre-remplir une
        # proposition. Si gh change son libelle, la proposition est moins bonne
        # et rien ne casse. Une detection cosmetique n'a pas le droit
        # d'empecher la commande de fonctionner.
        InModuleScope DevContext {
            @(Get-CtxGhComptesDepuisStatut -Texte '') | Should -BeNullOrEmpty
            @(Get-CtxGhComptesDepuisStatut -Texte $null) | Should -BeNullOrEmpty
            @(Get-CtxGhComptesDepuisStatut -Texte 'You are not logged into any GitHub hosts.') | Should -BeNullOrEmpty
            @(Get-CtxGhComptesDepuisStatut -Texte 'du bruit sans aucun rapport') | Should -BeNullOrEmpty
        }
    }
}

Describe 'Resolve-CtxNomPropose' {
    It 'prefere le login GitHub a l email' {
        # C'est le nom sous lequel le travail sortira reellement.
        InModuleScope DevContext {
            Resolve-CtxNomPropose -Login 'alice-dev' -Email 'autre@exemple.com' | Should -Be 'alice-dev'
        }
    }

    It 'se rabat sur la partie locale de l email' {
        InModuleScope DevContext {
            Resolve-CtxNomPropose -Login '' -Email 'octo.dev@exemple.com' | Should -Be 'octo-dev'
        }
    }

    It 'produit TOUJOURS un nom que New-DevContext accepte' -ForEach @(
        @{ L = 'Alice.Dupont'; Attendu = 'alice-dupont' }
        @{ L = 'ACME_Corp'; Attendu = 'acme-corp' }
        @{ L = '--bordures--'; Attendu = 'bordures' }
        @{ L = 'deja-bon'; Attendu = 'deja-bon' }
    ) {
        # New-DevContext exige ^[a-z0-9][a-z0-9-]*$. Proposer un nom qu'il
        # refusera ensuite est la pire des aides : l'utilisateur croit avoir
        # suivi la consigne et se prend un rejet.
        InModuleScope DevContext -Parameters @{ L = $L; A = $Attendu } { param($L, $A)
            $n = Resolve-CtxNomPropose -Login $L -Email ''
            $n | Should -Be $A
            $n | Should -Match '^[a-z0-9][a-z0-9-]*$'
        }
    }

    It 'se rabat sur perso quand il n y a rien d exploitable' {
        InModuleScope DevContext {
            Resolve-CtxNomPropose -Login '' -Email '' | Should -Be 'perso'
            Resolve-CtxNomPropose -Login $null -Email $null | Should -Be 'perso'
            Resolve-CtxNomPropose -Login '???' -Email '@@@' | Should -Be 'perso'
        }
    }
}

Describe 'Resolve-CtxInitEtapes' {
    BeforeAll {
        $script:Vierge = [pscustomobject]@{
            Coffre = $false; ShimsDansPath = $false; Racine = 'C:\dev\ctx'; RacineExiste = $false
            NbContextes = 0; GitNom = 'Alice'; GitEmail = 'alice@exemple.com'; ComptesGh = @('alice-dev')
        }
        $script:Prete = [pscustomobject]@{
            Coffre = $true; ShimsDansPath = $true; Racine = 'C:\dev\ctx'; RacineExiste = $true
            NbContextes = 2; GitNom = 'Alice'; GitEmail = 'alice@exemple.com'; ComptesGh = @('alice-dev')
        }
    }

    It 'rend les etapes dans l ORDRE ou elles doivent etre faites' {
        # L'ordre n'est pas cosmetique : creer un contexte sans le coffre echoue
        # a mi-chemin en laissant un dossier derriere.
        InModuleScope DevContext -Parameters @{ F = $script:Vierge } { param($F)
            @((Resolve-CtxInitEtapes -Faits $F).Cle) | Should -Be @('coffre', 'shims', 'contexte')
        }
    }

    It 'marque tout comme fait sur une machine deja prete' {
        InModuleScope DevContext -Parameters @{ F = $script:Prete } { param($F)
            @(Resolve-CtxInitEtapes -Faits $F | Where-Object { -not $_.Fait }) | Should -BeNullOrEmpty
        }
    }

    It 'ne propose PAS d installer un module automatiquement' {
        # Installer une dependance ne se decide pas au nom de quelqu'un d'autre.
        InModuleScope DevContext -Parameters @{ F = $script:Vierge } { param($F)
            $coffre = Resolve-CtxInitEtapes -Faits $F | Where-Object Cle -eq 'coffre'
            $coffre.Auto | Should -BeFalse
            $coffre.Commande | Should -Match 'Install-Module'
        }
    }

    It 'pre-remplit la commande de creation depuis git et gh' {
        InModuleScope DevContext -Parameters @{ F = $script:Vierge } { param($F)
            $c = (Resolve-CtxInitEtapes -Faits $F | Where-Object Cle -eq 'contexte').Commande
            $c | Should -Match 'alice-dev'
            $c | Should -Match 'alice@exemple\.com'
        }
    }

    It 'reste utilisable quand git et gh ne savent RIEN' {
        # UNE MACHINE VIERGE EST LA CIBLE MEME DE CETTE COMMANDE, et elle n'a ni
        # identite git globale ni compte gh. Le premier jet indexait [0] sur la
        # liste des comptes : sur un tableau vide cela leve "Index was outside
        # the bounds of the array" -- donc la commande d'accueil plantait
        # exactement sur la machine qu'elle vient accueillir.
        InModuleScope DevContext {
            $f = [pscustomobject]@{
                Coffre = $false; ShimsDansPath = $false; Racine = 'C:\x'; RacineExiste = $false
                NbContextes = 0; GitNom = $null; GitEmail = $null; ComptesGh = @()
            }
            $e = $null
            { $e = Resolve-CtxInitEtapes -Faits $f } | Should -Not -Throw
            $e = Resolve-CtxInitEtapes -Faits $f
            $contexte = $e | Where-Object Cle -eq 'contexte'
            $contexte.Commande | Should -Match 'ctx-new'
            $contexte.Propose.Nom | Should -Be 'perso'
        }
    }

    It 'chaque etape porte une commande non vide, et sa cle est traduite' {
        # Le mode non interactif n'affiche QUE ces deux choses. Une commande
        # vide, ou un libelle rendu [init.etape.x], en ferait un cul-de-sac.
        InModuleScope DevContext -Parameters @{ F = $script:Vierge } { param($F)
            foreach ($e in (Resolve-CtxInitEtapes -Faits $F)) {
                $e.Commande | Should -Not -BeNullOrEmpty
                (T "init.etape.$($e.Cle)") | Should -Not -Match '^\['
            }
        }
    }
}

Describe 'Test-CtxPeutDemander' {
    It 'suit la sonde qu on lui donne' {
        InModuleScope DevContext {
            Test-CtxPeutDemander -Sonde { $true } | Should -BeTrue
            Test-CtxPeutDemander -Sonde { $false } | Should -BeFalse
        }
    }

    It 'repond NON quand la sonde elle-meme echoue' {
        # Dans le doute, on ne pose pas de question. Se tromper dans ce sens
        # coute un affichage ; se tromper dans l'autre bloque un agent.
        InModuleScope DevContext {
            Test-CtxPeutDemander -Sonde { throw 'pas de console' } | Should -BeFalse
        }
    }
}

Describe 'Invoke-DevContextInit' {
    BeforeAll {
        $script:Vierge = [pscustomobject]@{
            Coffre = $false; ShimsDansPath = $false; Racine = 'C:\dev\ctx'; RacineExiste = $false
            NbContextes = 0; GitNom = 'Alice'; GitEmail = 'alice@exemple.com'; ComptesGh = @('alice-dev')
        }
        $script:Prete = [pscustomobject]@{
            Coffre = $true; ShimsDansPath = $true; Racine = 'C:\dev\ctx'; RacineExiste = $true
            NbContextes = 2; GitNom = 'Alice'; GitEmail = 'alice@exemple.com'; ComptesGh = @('alice-dev')
        }
    }

    It 'sur entree redirigee : NE POSE AUCUNE QUESTION et affiche les commandes' {
        InModuleScope DevContext -Parameters @{ F = $script:Vierge } { param($F)
            # Read-Host ici ferait echouer le test au lieu de bloquer -- ce qui
            # est exactement la difference qu'on veut mesurer.
            Mock Read-Host { throw 'une question a ete posee sur une entree redirigee' }
            $sortie = Invoke-DevContextInit -Faits $F -SondeInteractive { $false } -Confirm:$false 6>&1 | Out-String
            $sortie | Should -Match 'Install-Module'
            $sortie | Should -Match 'installer-shims'
            $sortie | Should -Match 'ctx-new'
            Should -Invoke Read-Host -Times 0
        }
    }

    It 'ne rend RIEN sur le pipeline : c est un guide, pas une requete' {
        InModuleScope DevContext -Parameters @{ F = $script:Prete } { param($F)
            Invoke-DevContextInit -Faits $F -SondeInteractive { $false } -Confirm:$false | Should -BeNullOrEmpty
        }
    }

    It 'sur une machine deja prete : ne change rien et le dit' {
        InModuleScope DevContext -Parameters @{ F = $script:Prete } { param($F)
            Mock Repair-CtxShims { throw 'rien ne doit etre repare sur une machine prete' }
            $sortie = Invoke-DevContextInit -Faits $F -SondeInteractive { $true } -Confirm:$false 6>&1 | Out-String
            $sortie | Should -Match 'Install-Module|installer-shims|ctx-new' -Not
            Should -Invoke Repair-CtxShims -Times 0
        }
    }

    It 'affiche l etat MEME quand tout va bien' {
        # Le second moment le plus probable pour lancer cette commande est
        # "quelque chose cloche et je ne sais plus ce que j'ai fait".
        InModuleScope DevContext -Parameters @{ F = $script:Prete } { param($F)
            $sortie = Invoke-DevContextInit -Faits $F -SondeInteractive { $true } -Confirm:$false 6>&1 | Out-String
            $sortie | Should -Match 'C:\\dev\\ctx'
            $sortie | Should -Match 'ctx doctor'
        }
    }
}
