BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-DevSupabaseMap' {
    BeforeAll {
        $script:root = Join-Path $TestDrive 'PROJECTS'

        # beta and beta-wt both point at the same project: that is the shape
        # this command exists to make visible.
        foreach ($pair in @(@('alpha', 'aaaa'), @('beta', 'bbbb'), @('beta-wt', 'bbbb'))) {
            $d = Join-Path $script:root $pair[0] 'supabase' '.temp'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Set-Content (Join-Path $d 'project-ref') $pair[1] -NoNewline
        }

        # A decoy that must NOT be picked up: right filename, wrong location.
        $piege = Join-Path $script:root 'gamma' 'autre'
        New-Item -ItemType Directory -Path $piege -Force | Out-Null
        Set-Content (Join-Path $piege 'project-ref') 'bbbb' -NoNewline

        $script:ctxDir = Join-Path $TestDrive 'CTX' 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null
        @{
            'aaaa' = @{ key = 'supabase-token';   name = 'alpha-dev';  env = 'dev'  }
            'bbbb' = @{ key = 'supabase-token-2'; name = 'beta-prod';  env = 'prod' }
            'cccc' = @{ key = 'supabase-token';   name = 'orphelin' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $script:ctxDir 'supabase-index.json') -Encoding UTF8

        $script:Prepare = {
            param($CtxDir, $Root)
            Mock Get-CtxSupabaseIndexPath { Join-Path $CtxDir 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $Root }
        }
    }

    It 'associe chaque projet a son compte' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            (Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'beta-prod').Compte |
                Should -Be 'supabase-token-2'
        }
    }

    It 'liste tous les dossiers qui visent un meme projet' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            $e = Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'beta-prod'
            $e.Dossiers.Count | Should -Be 2
            $e.Dossiers       | Should -Contain 'beta'
            $e.Dossiers       | Should -Contain 'beta-wt'
            $e.Partage        | Should -BeTrue
        }
    }

    It 'ne signale pas un projet vise par un seul dossier' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            (Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'alpha-dev').Partage |
                Should -BeFalse
        }
    }

    It 'liste un projet de l index qu aucun dossier local ne vise' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            $e = Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'orphelin'
            $e             | Should -Not -BeNullOrEmpty
            $e.Dossiers.Count | Should -Be 0
            $e.Partage     | Should -BeFalse
        }
    }

    It 'ignore un project-ref qui n est pas dans supabase/.temp' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            (Get-DevSupabaseMap -Name 'demo' | Where-Object Projet -eq 'beta-prod').Dossiers |
                Should -Not -Contain 'gamma'
        }
    }

    It 'reporte le marquage d environnement' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            $m = Get-DevSupabaseMap -Name 'demo'
            ($m | Where-Object Projet -eq 'beta-prod').Env | Should -Be 'prod'
            ($m | Where-Object Projet -eq 'alpha-dev').Env | Should -Be 'dev'
            ($m | Where-Object Projet -eq 'orphelin').Env  | Should -BeNullOrEmpty
        }
    }

    It 'porte un nom de type, pour un affichage lisible par defaut' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; r = $script:root } {
            param($c, $r)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { $r }
            (Get-DevSupabaseMap -Name 'demo')[0].PSObject.TypeNames |
                Should -Contain 'DevContext.SupabaseMapEntry'
        }
    }

    It 'renvoie une racine absente sans lever' {
        InModuleScope DevContext -Parameters @{ c = $script:ctxDir; t = $TestDrive } {
            param($c, $t)
            Mock Get-CtxSupabaseIndexPath { Join-Path $c 'supabase-index.json' }
            Mock Get-CtxSupabaseMapRoot   { Join-Path $t 'racine-inexistante' }
            $m = Get-DevSupabaseMap -Name 'demo'
            $m.Count | Should -Be 3
            ($m | Where-Object { $_.Dossiers.Count -gt 0 }) | Should -BeNullOrEmpty
        }
    }

    It 'leve un message qui nomme sb-index quand l index est absent' {
        InModuleScope DevContext -Parameters @{ t = $TestDrive } {
            param($t)
            Mock Get-CtxSupabaseIndexPath { Join-Path $t 'nulle-part.json' }
            { Get-DevSupabaseMap -Name 'demo' } | Should -Throw '*sb-index*'
        }
    }

    It 'leve quand aucun contexte n est actif et qu aucun nom n est donne' {
        InModuleScope DevContext {
            $avant = $env:DEVCTX
            try {
                Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
                { Get-DevSupabaseMap } | Should -Throw '*contexte*'
            }
            finally { if ($avant) { $env:DEVCTX = $avant } }
        }
    }
}

Describe 'ctx-sb' {
    It 'est expose comme alias de Get-DevSupabaseMap' {
        (Get-Alias 'ctx-sb' -ErrorAction SilentlyContinue).ResolvedCommandName |
            Should -Be 'Get-DevSupabaseMap'
    }
}

