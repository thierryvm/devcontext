BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabaseExe — exclusion du dossier des shims' {
    # Mocked rather than measured against the real PATH: this machine carries
    # two Supabase installations (a native binary and an npm wrapper), and a
    # test that depends on how many are present proves nothing anywhere else.

    It 'ecarte le candidat situe dans le dossier des shims' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @(
                    [pscustomobject]@{ Source = (Join-Path $script:ShimDir 'supabase.cmd') }
                    [pscustomobject]@{ Source = 'C:\ailleurs\supabase.exe' }
                )
            }
            Get-CtxSupabaseExe | Should -Be 'C:\ailleurs\supabase.exe'
        }
    }

    It 'ecarte le shim meme quand il est seul, et leve' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @([pscustomobject]@{ Source = (Join-Path $script:ShimDir 'supabase.cmd') })
            }
            { Get-CtxSupabaseExe } | Should -Throw '*introuvable*'
        }
    }

    It 'leve quand aucun candidat n existe' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } { @() }
            { Get-CtxSupabaseExe } | Should -Throw '*introuvable*'
        }
    }

    It 'tolere un separateur final sur le dossier exclu' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @(
                    [pscustomobject]@{ Source = 'C:\exclu\supabase.exe' }
                    [pscustomobject]@{ Source = 'C:\garde\supabase.exe' }
                )
            }
            Get-CtxSupabaseExe -ExcludeDir 'C:\exclu\' | Should -Be 'C:\garde\supabase.exe'
        }
    }

    It 'ne filtre rien quand aucune exclusion n est demandee' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'supabase' } {
                @([pscustomobject]@{ Source = 'C:\premier\supabase.exe' })
            }
            Get-CtxSupabaseExe -ExcludeDir '' | Should -Be 'C:\premier\supabase.exe'
        }
    }
}

Describe 'Get-CtxSupabaseExe — sur la machine reelle' {
    # Ces deux tests exigent un vrai binaire `supabase`. Sur une machine qui n'en
    # a pas, ils echouaient — et c'est le symetrique exact du defaut que
    # tests/README.md interdit : un test faussement VERT ment sur sa couverture,
    # un test faussement ROUGE apprend a ignorer le rouge. Le second finit par
    # couter le premier.
    #
    # Ils se declarent donc SAUTES en nommant ce qui manque, comme le font deja
    # les tests PSScriptAnalyzer. La CI, elle, installe la CLI : le filet y est
    # reellement tendu, plutot que d'etre un rouge permanent que plus personne ne
    # lit. Constate le 15 aout 2026 — la CI etait rouge la-dessus depuis son
    # introduction, sous les avis d'analyse statique.
    BeforeAll {
        $script:SupabaseReel = [bool](
            Get-Command supabase -CommandType Application -All -ErrorAction SilentlyContinue |
                Where-Object { (Split-Path $_.Source -Parent) -notlike '*shims*' }
        )
    }

    It 'renvoie un chemin qui existe' {
        if (-not $script:SupabaseReel) {
            Set-ItResult -Skipped -Because 'aucune CLI supabase hors shims sur cette machine'
            return
        }
        InModuleScope DevContext {
            $exe = Get-CtxSupabaseExe
            Test-Path -LiteralPath $exe | Should -BeTrue
        }
    }

    It 'ne renvoie jamais un chemin situe dans le dossier des shims' {
        if (-not $script:SupabaseReel) {
            Set-ItResult -Skipped -Because 'aucune CLI supabase hors shims sur cette machine'
            return
        }
        InModuleScope DevContext {
            (Split-Path (Get-CtxSupabaseExe) -Parent).TrimEnd('\', '/') |
                Should -Not -Be $script:ShimDir.TrimEnd('\', '/')
        }
    }
}

Describe 'ShimDir' {
    It 'pointe sur un sous-dossier shims de la racine du module' {
        InModuleScope DevContext {
            Split-Path $script:ShimDir -Leaf | Should -Be 'shims'
            Split-Path $script:ShimDir -Parent |
                Should -Be (Split-Path (Get-Module DevContext).Path -Parent)
        }
    }
}
