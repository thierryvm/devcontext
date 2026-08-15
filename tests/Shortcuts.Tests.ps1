# Tests for the shortcut audit.
#
# Everything here runs without a shortcut on disk and without an editor
# installed. Reading a .lnk needs a COM object and a Windows shell; DECIDING
# what a .lnk means needs neither, and that separation is what lets this suite
# give the same verdict on a CI runner as on a machine covered in shortcuts.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
    $script:Exes = @('Code.exe', 'Cursor.exe', 'Antigravity.exe')
}

Describe 'Test-CtxShortcutLaunchesEditor' {
    It 'reconnait un raccourci visant l executable de l editeur' {
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            Test-CtxShortcutLaunchesEditor -Target 'C:\Programs\VS Code\Code.exe' -Arguments '' -EditeurExecutables $e |
                Should -BeTrue
        }
    }

    It 'reconnait AUSSI un raccourci qui passe par un lanceur du module' {
        # Sans ceci, l audit ne notait que les raccourcis deja casses et restait
        # muet sur ceux qu il valait la peine de confirmer. Les 10 raccourcis de
        # cette machine visent pwsh.exe, pas un executable d editeur.
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            Test-CtxShortcutLaunchesEditor -Target 'C:\Program Files\PowerShell\7\pwsh.exe' `
                -Arguments '-File "F:\devcontext\lancer-vscode.ps1" -Context perso -Path "F:\p"' `
                -EditeurExecutables $e | Should -BeTrue
        }
    }

    It 'reconnait le lanceur generalise' {
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            Test-CtxShortcutLaunchesEditor -Target 'pwsh.exe' `
                -Arguments '-File "F:\devcontext\lancer-editeur.ps1" -Path "F:\p" -Editor cursor' `
                -EditeurExecutables $e | Should -BeTrue
        }
    }

    It 'ne reconnait pas un raccourci sans rapport' {
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            Test-CtxShortcutLaunchesEditor -Target 'C:\Program Files\Firefox\firefox.exe' -Arguments '' `
                -EditeurExecutables $e | Should -BeFalse
        }
    }

    It 'compare le nom du fichier, pas le chemin complet' {
        # Un editeur installe ailleurs reste le meme editeur.
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            Test-CtxShortcutLaunchesEditor -Target 'D:\ailleurs\portable\code.exe' -Arguments '' `
                -EditeurExecutables $e | Should -BeTrue
        }
    }
}

Describe 'Test-CtxShortcutIsolated' {
    It 'voit un --user-data-dir explicite' {
        InModuleScope DevContext {
            Test-CtxShortcutIsolated -Target 'Code.exe' -Arguments '--user-data-dir F:\CTX\perso\vscode F:\p' |
                Should -BeTrue
        }
    }

    It 'accepte un raccourci passant par le lanceur historique' {
        InModuleScope DevContext {
            Test-CtxShortcutIsolated -Target 'pwsh.exe' -Arguments '-File "F:\d\lancer-vscode.ps1" -Context perso' |
                Should -BeTrue
        }
    }

    It 'accepte un raccourci passant par le dossier de shims' {
        InModuleScope DevContext {
            Test-CtxShortcutIsolated -Target 'F:\devcontext\shims\code.cmd' -Arguments 'F:\p' `
                -ShimDir 'F:\devcontext\shims' | Should -BeTrue
        }
    }

    It 'ne se laisse pas avoir par un antislash final sur le dossier de shims' {
        InModuleScope DevContext {
            Test-CtxShortcutIsolated -Target 'F:\devcontext\shims\code.cmd' -Arguments '' `
                -ShimDir 'F:\devcontext\shims\' | Should -BeTrue
        }
    }

    It 'dit non a un lancement direct sans flag' {
        InModuleScope DevContext {
            Test-CtxShortcutIsolated -Target 'C:\p\Code.exe' -Arguments 'F:\PROJECTS\Apps\demo' | Should -BeFalse
        }
    }
}

Describe 'Test-CtxDoctorRaccourci' {
    It 'PROBLEME : ouvre un projet de contexte sur le profil partage' {
        # LE bug quotidien. Se connecter a GitHub la deconnecte des autres
        # contextes, et il faut tout refaire au redemarrage suivant.
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            $r = Test-CtxDoctorRaccourci -Nom 'Mon projet' -Target 'C:\p\Code.exe' `
                -Arguments 'F:\PROJECTS\Clients\acme' -Contexte 'acme' -EditeurExecutables $e
            $r.Verdict   | Should -Be 'PROBLEME'
            $r.Detail    | Should -Match 'acme'
            $r.Correctif | Should -Match 'ctx-shortcut'
        }
    }

    It 'ATTENTION : lance un editeur sans dossier' {
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            (Test-CtxDoctorRaccourci -Nom 'Visual Studio Code' -Target 'C:\p\Code.exe' `
                -Arguments '' -Contexte '' -EditeurExecutables $e).Verdict | Should -Be 'ATTENTION'
        }
    }

    It 'OK : passe par un lanceur, meme sans flag visible' {
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            $r = Test-CtxDoctorRaccourci -Nom 'VS Code - demo-app' -Target 'pwsh.exe' `
                -Arguments '-File "F:\d\lancer-vscode.ps1" -Context perso -Path "F:\PROJECTS\Apps\demo-app"' `
                -Contexte 'perso' -EditeurExecutables $e
            $r.Verdict | Should -Be 'OK'
            $r.Detail  | Should -Match 'perso'
        }
    }

    It 'ne rend RIEN quand le raccourci ne concerne pas un editeur' {
        # Rien, et non un constat « OK, sans rapport ». L appelant reconnaissait
        # ce cas en comparant son TEXTE, ce qui a cesse de marcher des que le
        # texte est devenu traduisible : en anglais, le filtre ne matchait plus
        # et deux cents raccourcis sans rapport auraient inonde le rapport.
        # L absence de constat, elle, ne se traduit pas.
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            Test-CtxDoctorRaccourci -Nom 'Firefox' -Target 'firefox.exe' -Arguments '' `
                -Contexte '' -EditeurExecutables $e | Should -BeNullOrEmpty
        }
    }

    It 'ne dit rien d une cible vide plutot que de lever' {
        InModuleScope DevContext -Parameters @{ e = $script:Exes } { param($e)
            { Test-CtxDoctorRaccourci -Nom 'vide' -Target '' -Arguments '' -Contexte '' -EditeurExecutables $e } |
                Should -Not -Throw
        }
    }

    It 'sans liste d executables, ne signale rien' {
        # Une machine sans editeur detecte ne doit pas produire d avis sur des
        # raccourcis dont elle ne sait rien.
        InModuleScope DevContext {
            Test-CtxDoctorRaccourci -Nom 'x' -Target 'C:\p\Code.exe' -Arguments 'F:\p' -Contexte 'perso' |
                Should -BeNullOrEmpty
        }
    }
}
