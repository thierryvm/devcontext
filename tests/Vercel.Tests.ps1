# Tests du garde-fou `vercel`.
#
# Meme decoupe qu ailleurs : la decision est pure et se verifie sans reseau ni
# compte ; l injection de `--global-config` et le refus se verifient de bout en
# bout contre un LEURRE qui annonce ce qu il a recu.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Test-CtxVercelGuard' {
    It 'REFUSE un deploiement de production hors branche par defaut' {
        $v = Test-CtxVercelGuard -Arguments @('deploy', '--prod') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
        $v.Reason  | Should -Match 'feat/x'
    }

    It 'reconnait le deploiement nu, sans sous-commande' {
        # `vercel --prod` deploie. Ne juger que `vercel deploy --prod` laisserait
        # passer la forme la plus courte, qui est aussi la plus tapee.
        (Test-CtxVercelGuard -Arguments @('--prod') -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed |
            Should -BeFalse
    }

    It 'reconnait --target production comme --prod' {
        (Test-CtxVercelGuard -Arguments @('deploy', '--target', 'production') -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed |
            Should -BeFalse
    }

    It 'laisse passer le meme deploiement depuis la branche par defaut' {
        $v = Test-CtxVercelGuard -Arguments @('deploy', '--prod') -CurrentBranch 'main' -DefaultBranch 'main'
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'branche-par-defaut'
    }

    It 'ne bloque jamais sur une branche inconnue' {
        # Hors depot, ou HEAD detachee. On ne refuse pas sur une supposition.
        $v = Test-CtxVercelGuard -Arguments @('deploy', '--prod')
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'branche-inconnue'
    }

    It 'laisse passer vercel build --prod, qui ne deploie rien' {
        # Construction locale. Le refuser serait un faux refus sur une commande
        # sans effet distant -- et un faux refus enseigne a contourner l outil.
        $v = Test-CtxVercelGuard -Arguments @('build', '--prod') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'non-deploiement'
    }

    It 'REFUSE env rm sur la production' {
        $v = Test-CtxVercelGuard -Arguments @('env', 'rm', 'CLE', 'production')
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'env-rm-production'
    }

    It 'laisse passer env rm sur les autres environnements' {
        (Test-CtxVercelGuard -Arguments @('env', 'rm', 'CLE', 'preview')).Allowed     | Should -BeTrue
        (Test-CtxVercelGuard -Arguments @('env', 'rm', 'CLE', 'development')).Allowed | Should -BeTrue
    }

    It 'laisse passer env rm sans cible, que la CLI demandera' {
        # Sans environnement ecrit, `vercel` ouvre une invite et l humain voit ce
        # qu il choisit. Refuser ici ferait disparaitre la commande pour les
        # environnements de developpement aussi, ou elle est banale.
        (Test-CtxVercelGuard -Arguments @('env', 'rm', 'CLE')).Allowed | Should -BeTrue
    }

    It 'ne garde deliberement PAS rollback ni promote' {
        # rollback est un geste de REPARATION : le refuser tombe toujours pendant
        # un incident, depuis une branche de correctif. promote agit sur un
        # deploiement deja construit. SECURITY.md porte la meme liste.
        (Test-CtxVercelGuard -Arguments @('rollback') -CurrentBranch 'hotfix/x' -DefaultBranch 'main').Allowed |
            Should -BeTrue
        (Test-CtxVercelGuard -Arguments @('promote', 'https://x') -CurrentBranch 'hotfix/x' -DefaultBranch 'main').Allowed |
            Should -BeTrue
    }

    It 'la derogation explicite passe avant tout' {
        $v = Test-CtxVercelGuard -Arguments @('deploy', '--prod') -CurrentBranch 'feat/x' -DefaultBranch 'main' -Override
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'derogation'
    }
}

Describe 'shim vercel — de bout en bout' {
    BeforeAll {
        $script:ctxRoot  = Join-Path $TestDrive 'CTXVC'
        $script:projRoot = Join-Path $TestDrive 'PROJVC'
        $script:ctxDir   = Join-Path $script:ctxRoot 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null

        @{ name = 'demo'; label = 'Demo'; email = 'demo@exemple.com'; root = $script:projRoot } |
            ConvertTo-Json | Set-Content (Join-Path $script:ctxDir 'context.json') -Encoding UTF8

        $script:proj = Join-Path $script:projRoot 'appli'
        New-Item -ItemType Directory -Path $script:proj -Force | Out-Null
        Push-Location $script:proj
        try {
            git init -b main --quiet 2>$null | Out-Null
            git -c user.email='t@exemple.com' -c user.name='T' commit --allow-empty -m 'init' --quiet 2>$null | Out-Null
            git checkout -b 'feat/chantier' --quiet 2>$null | Out-Null
        }
        finally { Pop-Location }

        $script:decoy = Join-Path $TestDrive 'binvc'
        New-Item -ItemType Directory -Path $script:decoy -Force | Out-Null
        @"
@echo off
echo LEURRE-APPELE
echo ARGS=%*
exit /b 42
"@ | Set-Content (Join-Path $script:decoy 'vercel.cmd') -Encoding ascii

        $script:Shim = (Resolve-Path (Join-Path $PSScriptRoot '..' 'shims' 'vercel.ps1')).Path

        $script:Run = {
            param($ShimPath, $Cwd, $CtxRoot, $Decoy, $CliArgs, $Allow)
            $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
Remove-Item Env:DEVCTX_VERCEL_CONFIG -ErrorAction SilentlyContinue
`$env:DEVCTX_ALLOW_VERCEL = '$Allow'
`$env:PATH = '$Decoy;' + `$env:PATH
Set-Location '$Cwd'
& '$ShimPath' $CliArgs
exit `$LASTEXITCODE
"@
            $out = pwsh -NoProfile -Command $code 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
        }
    }

    It 'REFUSE un deploiement de production depuis une branche laterale' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'deploy --prod' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'REFUSE env rm sur la production' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'env rm CLE production' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'laisse passer un deploiement de preview et propage le code de sortie' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'deploy' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'injecte --global-config des que le contexte porte une session' {
        $vc = Join-Path $script:ctxDir 'vercel'
        New-Item -ItemType Directory -Path $vc -Force | Out-Null
        Set-Content (Join-Path $vc 'auth.json') '{}' -Encoding ascii
        try {
            $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'ls' ''
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Output | Should -Match '--global-config'
            $r.Output | Should -Match ([regex]::Escape($vc))
        }
        finally { Remove-Item $vc -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'n injecte rien quand le contexte n a pas de session' {
        # Pointer vers un dossier vide rendrait « non connecte » la ou `vercel`
        # fonctionnait. Une regression n est pas une protection.
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'ls' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match '--global-config'
    }

    It 'redirige vercel login meme sans session prealable' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'login' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Match '--global-config'
    }

    It 'ne remplace pas un --global-config ecrit par l appelant' {
        # Un choix explicite n est pas a nous. Meme regle que pour GH_CONFIG_DIR.
        $vc = Join-Path $script:ctxDir 'vercel'
        New-Item -ItemType Directory -Path $vc -Force | Out-Null
        Set-Content (Join-Path $vc 'auth.json') '{}' -Encoding ascii
        try {
            $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'ls --global-config C:\ailleurs' ''
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Output | Should -Match ([regex]::Escape('C:\ailleurs'))
            $r.Output | Should -Not -Match ([regex]::Escape($vc))
        }
        finally { Remove-Item $vc -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'laisse passer la derogation explicite' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'deploy --prod' '1'
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }
}
