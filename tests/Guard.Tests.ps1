BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabaseSubcommand' {
    It 'joint les deux premiers arguments non-option' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('db', 'reset') | Should -Be 'db reset'
        }
    }
    It 'ignore les options placees avant la sous-commande' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('--debug', 'db', 'reset') | Should -Be 'db reset'
        }
    }
    It 'ignore les options placees apres la sous-commande' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('db', 'reset', '--linked') | Should -Be 'db reset'
        }
    }
    It 'normalise la casse' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @('DB', 'Reset') | Should -Be 'db reset'
        }
    }
    It 'rend une chaine vide sans argument' {
        InModuleScope DevContext {
            Get-CtxSupabaseSubcommand @() | Should -Be ''
        }
    }
}

Describe 'Test-CtxSupabaseGuard — hors production' {
    It 'laisse passer db reset quand le projet est marque dev' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'dev' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer db reset quand l environnement est inconnu' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment $null `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
}

Describe 'Test-CtxSupabaseGuard — db reset en production' {
    It 'refuse, quelle que soit la branche' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
        $r.Rule    | Should -Be 'db-reset-prod'
    }
    It 'refuse aussi hors depot git' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'prod' `
             -CurrentBranch $null -DefaultBranch $null
        $r.Allowed | Should -BeFalse
    }
    It 'laisse passer si le contournement explicite est pose' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main' -Override
        $r.Allowed | Should -BeTrue
        $r.Rule    | Should -Be 'override'
    }
}

Describe 'Test-CtxSupabaseGuard — db push en production' {
    It 'laisse passer depuis la branche par defaut' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch 'main' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'refuse depuis une autre branche' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch 'feat/pwa-start-url-cockpit' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
        $r.Rule    | Should -Be 'branch-mismatch'
    }
    It 'laisse passer si la branche par defaut est indeterminable' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch $null
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer hors depot git' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'push') -Environment 'prod' `
             -CurrentBranch $null -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'applique la meme regle a migration repair' {
        $r = Test-CtxSupabaseGuard -Arguments @('migration', 'repair') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
    }
    It 'applique la meme regle a migration up' {
        $r = Test-CtxSupabaseGuard -Arguments @('migration', 'up') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeFalse
    }
}

Describe 'Test-CtxSupabaseGuard — commandes hors liste noire' {
    It 'laisse passer db pull en production depuis une branche quelconque' {
        $r = Test-CtxSupabaseGuard -Arguments @('db', 'pull') -Environment 'prod' `
             -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $r.Allowed | Should -BeTrue
    }
    It 'laisse passer db dump en production' {
        (Test-CtxSupabaseGuard -Arguments @('db', 'dump') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer gen types en production' {
        (Test-CtxSupabaseGuard -Arguments @('gen', 'types') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer une invocation sans argument' {
        (Test-CtxSupabaseGuard -Arguments @() -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
    It 'laisse passer projects list' {
        (Test-CtxSupabaseGuard -Arguments @('projects', 'list', '-o', 'json') -Environment 'prod' `
         -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed | Should -BeTrue
    }
}
