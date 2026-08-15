# Filet de regression sur les deux fonctions qui decident, en production, a quel
# contexte et a quel compte appartient un dossier.
#
# Elles n'avaient ete verifiees qu'a LA MAIN, le 5 aout 2026. C'est le pire
# endroit du depot ou laisser ce vide : Resolve-DevContextForPath arme desormais
# le garde-fou production ET le shim, donc une regression ici ne casse pas un
# affichage, elle rouvre en silence la porte que tout le reste ferme.
#
# Aucun de ces tests ne touche au disque : Get-CtxManifests est simule, ce qui
# isole la DECISION de l'etat de la machine qui les execute.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Resolve-DevContextForPath' {
    BeforeAll {
        $script:Faux = {
            @(
                [pscustomobject]@{ name = 'perso';   email = 'p@x.be'; root = 'F:\PROJECTS\Apps' }
                [pscustomobject]@{ name = 'client';  email = 'c@y.com'; root = 'F:\PROJECTS\Clients\acme' }
                [pscustomobject]@{ name = 'imbrique'; email = 'i@z.io'; root = 'F:\PROJECTS\Apps\special' }
            )
        }
    }

    It 'resout un dossier vers le contexte qui le contient' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\demo-app').name | Should -Be 'perso'
        }
    }

    It 'ne confond PAS un dossier voisin dont le nom commence pareil' {
        # Le piege du prefixe. Sans separateur final, 'F:\PROJECTS\Apps'
        # matcherait aussi 'F:\PROJECTS\Apps-Autre', et le garde-fou dirait le
        # contraire du vrai — en accordant a un dossier l'identite d'un autre.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps-Autre\projet' | Should -BeNullOrEmpty
        }
    }

    It 'ne confond pas non plus au niveau du dossier lui-meme' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps-Autre' | Should -BeNullOrEmpty
        }
    }

    It 'la racine la plus longue gagne sur un contexte imbrique' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\special\projet').name |
                Should -Be 'imbrique'
        }
    }

    It 'resout la racine du contexte elle-meme' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps').name | Should -Be 'perso'
        }
    }

    It 'ignore la casse, comme le systeme de fichiers Windows' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'f:\projects\APPS\demo-app').name | Should -Be 'perso'
        }
    }

    It 'tolere un antislash final' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\demo-app\').name | Should -Be 'perso'
        }
    }

    It 'rend null hors de toute racine connue' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            Resolve-DevContextForPath -Path 'C:\Windows' | Should -BeNullOrEmpty
        }
    }

    It 'rend null quand aucun contexte n existe' {
        InModuleScope DevContext {
            Mock Get-CtxManifests { @() }
            Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\x' | Should -BeNullOrEmpty
        }
    }

    It 'ignore un manifeste sans racine plutot que de lever' {
        InModuleScope DevContext {
            Mock Get-CtxManifests { @([pscustomobject]@{ name = 'casse'; email = 'x@y.z' }) }
            { Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\x' } | Should -Not -Throw
        }
    }

    It 'resout un chemin inexistant sans lever' {
        # Resolve-Path echoue sur un dossier absent ; la resolution doit rester
        # possible, ne serait-ce que pour diagnostiquer une faute de frappe.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Mock Get-CtxManifests $f
            (Resolve-DevContextForPath -Path 'F:\PROJECTS\Apps\jamais-cree').name | Should -Be 'perso'
        }
    }
}

Describe 'Get-NormalizedRoot' {
    It 'pose un separateur final sur <_>' -ForEach @(
        'F:\PROJECTS\Apps', 'F:\PROJECTS\Apps\', 'F:\PROJECTS\Apps/'
    ) {
        InModuleScope DevContext -Parameters @{ p = $_ } { param($p)
            Get-NormalizedRoot $p | Should -Be 'F:\PROJECTS\Apps\'
        }
    }
}

Describe 'Resolve-CtxSupabaseRef' {
    BeforeAll {
        $script:racine = Join-Path $TestDrive 'projet'
        New-Item -ItemType Directory -Path (Join-Path $script:racine 'supabase\.temp') -Force | Out-Null
        Set-Content (Join-Path $script:racine 'supabase\.temp\project-ref') "  refavecespaces `n" -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $script:racine 'apps\web\src') -Force | Out-Null
    }

    It 'trouve le ref a la racine du projet' {
        InModuleScope DevContext -Parameters @{ r = $script:racine } { param($r)
            Resolve-CtxSupabaseRef -Path $r | Should -Be 'refavecespaces'
        }
    }

    It 'remonte l arborescence depuis un sous-dossier profond' {
        # Indispensable : on travaille depuis apps/web, pas depuis la racine.
        InModuleScope DevContext -Parameters @{ r = $script:racine } { param($r)
            Resolve-CtxSupabaseRef -Path (Join-Path $r 'apps\web\src') | Should -Be 'refavecespaces'
        }
    }

    It 'rend null hors de tout projet lie' {
        InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
            Resolve-CtxSupabaseRef -Path $t | Should -BeNullOrEmpty
        }
    }

    It 'rend null sur un chemin inexistant, sans boucler' {
        InModuleScope DevContext {
            Resolve-CtxSupabaseRef -Path 'Z:\nexiste\pas' | Should -BeNullOrEmpty
        }
    }
}
