BeforeAll {
    $script:Installer = (Resolve-Path (Join-Path $PSScriptRoot '..' 'installer-shims.ps1')).Path

    # -AsLibrary loads the functions without touching the machine. Without it,
    # dot-sourcing the installer would install it.
    . $script:Installer -AsLibrary
}

Describe 'installer-shims — forme du script' {
    It 'a une syntaxe valide' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Installer, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It 'expose les modes -Verifier et -Restaurer' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Installer, [ref]$null, [ref]$null)
        $names = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        $names | Should -Contain 'Verifier'
        $names | Should -Contain 'Restaurer'
    }

    It 'rapporte sans rien modifier en mode -Verifier' {
        $avant = [Environment]::GetEnvironmentVariable('Path', 'User')
        pwsh -NoProfile -File $script:Installer -Verifier | Out-Null
        [Environment]::GetEnvironmentVariable('Path', 'User') | Should -Be $avant
    }
}

Describe 'Add-CtxPathEntry' {
    It 'pose l entree en tete' {
        Add-CtxPathEntry -Entry 'C:\shims' -Current 'C:\a;C:\b' |
            Should -Be 'C:\shims;C:\a;C:\b'
    }

    It 'ne pose rien une seconde fois' {
        Add-CtxPathEntry -Entry 'C:\shims' -Current 'C:\shims;C:\a' | Should -BeNullOrEmpty
    }

    It 'reconnait une entree deja presente malgre la casse' {
        # Windows resout le PATH sans distinguer la casse : traiter
        # 'c:\shims' comme different de 'C:\shims' poserait un doublon.
        Add-CtxPathEntry -Entry 'C:\Shims' -Current 'c:\SHIMS;C:\a' | Should -BeNullOrEmpty
    }

    It 'reconnait une entree deja presente malgre un antislash final' {
        Add-CtxPathEntry -Entry 'C:\shims' -Current 'C:\shims\;C:\a' | Should -BeNullOrEmpty
    }

    It 'conserve les autres entrees telles quelles, y compris une entree vide' {
        # Une entree vide veut dire « le dossier courant » sous Windows. C'est
        # discutable, mais ce n'est pas a l'installateur d'en decider : il ne
        # touche qu'a la sienne.
        $r = Add-CtxPathEntry -Entry 'C:\shims' -Current 'C:\a;;C:\b\'
        $r | Should -Be 'C:\shims;C:\a;;C:\b\'
    }

    It 'gere un PATH vide' {
        Add-CtxPathEntry -Entry 'C:\shims' -Current '' | Should -Be 'C:\shims'
    }
}

Describe 'Remove-CtxPathEntry' {
    It 'retire uniquement son entree' {
        Remove-CtxPathEntry -Entry 'C:\shims' -Current 'C:\a;C:\shims;C:\b' |
            Should -Be 'C:\a;C:\b'
    }

    It 'retire une entree ecrite avec une autre casse ou un antislash final' {
        Remove-CtxPathEntry -Entry 'C:\shims' -Current 'C:\a;c:\SHIMS\;C:\b' |
            Should -Be 'C:\a;C:\b'
    }

    It 'retire tous les doublons de son entree' {
        Remove-CtxPathEntry -Entry 'C:\shims' -Current 'C:\shims;C:\a;C:\shims' |
            Should -Be 'C:\a'
    }

    It 'ne change rien quand l entree est absente' {
        Remove-CtxPathEntry -Entry 'C:\shims' -Current 'C:\a;C:\b' | Should -BeNullOrEmpty
    }

    It 'conserve une entree vide qui n est pas la sienne' {
        Remove-CtxPathEntry -Entry 'C:\shims' -Current 'C:\a;;C:\shims' | Should -Be 'C:\a;'
    }
}

Describe 'preservation du type registre' {
    # C'est LE piege de cette tache. [Environment]::GetEnvironmentVariable rend
    # un PATH deja DEVELOPPE ; le reecrire fige %USERPROFILE% en chemin dur et
    # retrograde REG_EXPAND_SZ en REG_SZ, definitivement et sans un mot.
    #
    # Le PATH de cette machine est REG_SZ et ne contient aucune variable : un
    # test qui l'interrogeait ne pouvait donc rien prouver, et serait reste vert
    # sur une implementation fausse. On monte plutot une cle bidon qui, elle,
    # porte le cas qui casse.
    BeforeAll {
        $script:CleTest = 'HKCU:\Software\DevContextTests\PathKind'
        New-Item -Path $script:CleTest -Force | Out-Null
        Set-ItemProperty -LiteralPath $script:CleTest -Name 'Path' `
            -Value '%USERPROFILE%\bin;C:\reel' -Type ExpandString
    }
    AfterAll {
        Remove-Item -LiteralPath 'HKCU:\Software\DevContextTests' -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'rend la valeur brute, sans developper les variables' {
        (Get-CtxUserPath -Cle $script:CleTest).Value | Should -Be '%USERPROFILE%\bin;C:\reel'
    }

    It 'rapporte le type registre REG_EXPAND_SZ' {
        (Get-CtxUserPath -Cle $script:CleTest).Kind | Should -Be 'ExpandString'
    }

    It 'reecrit sans retrograder le type ni developper la variable' {
        $etat    = Get-CtxUserPath -Cle $script:CleTest
        $nouveau = Add-CtxPathEntry -Entry 'C:\shims' -Current $etat.Value
        Set-CtxUserPath -Value $nouveau -Kind $etat.Kind -Cle $script:CleTest

        $apres = Get-CtxUserPath -Cle $script:CleTest
        $apres.Kind  | Should -Be 'ExpandString'
        $apres.Value | Should -Be 'C:\shims;%USERPROFILE%\bin;C:\reel'
        $apres.Value | Should -Match '%USERPROFILE%'
    }

    It 'lit le PATH utilisateur reel sans lever' {
        $etat = Get-CtxUserPath
        $etat.Kind  | Should -BeIn @('String', 'ExpandString')
        $etat.Value | Should -Not -BeNullOrEmpty
    }

    It 'rend une valeur vide plutot que de lever sur une cle inexistante' {
        (Get-CtxUserPath -Cle 'HKCU:\Software\DevContextTests\NexistePas').Value | Should -Be ''
    }
}
