BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxSupabaseEnvGuess' {
    It 'reconnait prod dans le nom' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'ankora-prod' | Should -Be 'prod' }
    }
    It 'reconnait production dans le nom' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'shop production' | Should -Be 'prod' }
    }
    It 'reconnait staging comme non-production' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'ankora-staging' | Should -Be 'dev' }
    }
    It 'reconnait dev, preview et test' {
        InModuleScope DevContext {
            Get-CtxSupabaseEnvGuess 'app-dev'     | Should -Be 'dev'
            Get-CtxSupabaseEnvGuess 'app-preview' | Should -Be 'dev'
            Get-CtxSupabaseEnvGuess 'app-test'    | Should -Be 'dev'
        }
    }
    It 'ignore la casse' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'Ankora-PROD' | Should -Be 'prod' }
    }
    It 'rend null sur un nom neutre' {
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'IronTrack' | Should -BeNullOrEmpty }
    }
    It 'ne confond pas reproduction avec production' {
        # The whole point of the word boundaries. A false 'prod' would block a
        # command that had every right to run, and that is how a guard loses
        # the user's trust.
        InModuleScope DevContext { Get-CtxSupabaseEnvGuess 'reproduction-bug' | Should -BeNullOrEmpty }
    }
    It 'rend null sur une entree vide' {
        InModuleScope DevContext {
            Get-CtxSupabaseEnvGuess ''    | Should -BeNullOrEmpty
            Get-CtxSupabaseEnvGuess $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'Merge-CtxSupabaseEnv' {
    It 'conserve un env pose a la main, meme si le nom dit le contraire' {
        InModuleScope DevContext {
            $ancien = @{ 'aaaa' = [pscustomobject]@{ env = 'dev'; envSource = 'manual' } }
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous $ancien
            $r.env       | Should -Be 'dev'
            $r.envSource | Should -Be 'manual'
        }
    }
    It 'reevalue un env pose automatiquement' {
        InModuleScope DevContext {
            $ancien = @{ 'aaaa' = [pscustomobject]@{ env = $null; envSource = 'auto' } }
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous $ancien
            $r.env       | Should -Be 'prod'
            $r.envSource | Should -Be 'auto'
        }
    }
    It 'devine sur une entree entierement nouvelle' {
        InModuleScope DevContext {
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous @{}
            $r.env       | Should -Be 'prod'
            $r.envSource | Should -Be 'auto'
        }
    }
    It 'traite une entree ancienne sans champ envSource comme automatique' {
        # Indexes written before this version carry neither field. They must be
        # enriched, not treated as a deliberate choice.
        InModuleScope DevContext {
            $ancien = @{ 'aaaa' = [pscustomobject]@{ key = 'supabase-token'; name = 'app-prod' } }
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous $ancien
            $r.env       | Should -Be 'prod'
            $r.envSource | Should -Be 'auto'
        }
    }
    It 'accepte un env manuel volontairement vide' {
        # 'this project is neither, stop guessing' is a legitimate choice.
        InModuleScope DevContext {
            $ancien = @{ 'aaaa' = [pscustomobject]@{ env = $null; envSource = 'manual' } }
            $r = Merge-CtxSupabaseEnv -Ref 'aaaa' -ProjectName 'app-prod' -Previous $ancien
            $r.env       | Should -BeNullOrEmpty
            $r.envSource | Should -Be 'manual'
        }
    }
}

Describe 'Get-CtxSupabaseEnv' {
    BeforeAll {
        $script:ctxDir = Join-Path $TestDrive 'CTX' 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null
        @{
            'aaaa' = @{ key = 'supabase-token';   name = 'app-prod'; env = 'prod'; envSource = 'auto' }
            'bbbb' = @{ key = 'supabase-token-2'; name = 'app-dev';  env = 'dev';  envSource = 'auto' }
            'cccc' = @{ key = 'supabase-token';   name = 'neutre' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $script:ctxDir 'supabase-index.json') -Encoding UTF8

        $script:absent = Join-Path $TestDrive 'nulle-part.json'
    }

    It 'rend prod pour une entree marquee' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'aaaa' -ContextName 'demo' | Should -Be 'prod'
        }
    }
    It 'rend dev pour une entree marquee dev' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'bbbb' -ContextName 'demo' | Should -Be 'dev'
        }
    }
    It 'rend null pour une entree sans champ env' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'cccc' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
    It 'rend null pour un ref absent' {
        InModuleScope DevContext -Parameters @{ dir = $script:ctxDir } {
            param($dir)
            Mock Get-CtxSupabaseIndexPath { Join-Path $dir 'supabase-index.json' }
            Get-CtxSupabaseEnv -Ref 'zzzz' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
    It 'rend null quand l index n existe pas' {
        InModuleScope DevContext -Parameters @{ absent = $script:absent } {
            param($absent)
            Mock Get-CtxSupabaseIndexPath { $absent }
            Get-CtxSupabaseEnv -Ref 'aaaa' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
    It 'rend null sur un index illisible plutot que de lever' {
        InModuleScope DevContext -Parameters @{ dir = $TestDrive } {
            param($dir)
            $casse = Join-Path $dir 'casse.json'
            Set-Content $casse '{ ceci n est pas du json' -Encoding UTF8
            Mock Get-CtxSupabaseIndexPath { $casse }
            Get-CtxSupabaseEnv -Ref 'aaaa' -ContextName 'demo' | Should -BeNullOrEmpty
        }
    }
}
