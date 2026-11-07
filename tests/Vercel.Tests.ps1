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
        # Sans environnement ecrit, la CLI retire la variable de tous ses
        # environnements, apres une confirmation que `--yes` saute. Limite
        # assumee et ecrite dans SECURITY.md : refuser ici ferait disparaitre
        # la commande pour les environnements de developpement aussi.
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

Describe 'Test-CtxVercelGuard -- lit la ligne comme la CLI la lit' {
    # Releve sur les sources de la CLI (packages/cli/src sur GitHub le 1er
    # novembre 2026, paquet 65.8.0 installe le 2), sans jamais l executer :
    #
    #   - les options globales sont lues AVANT la commande, et sept d entre
    #     elles prennent une valeur en argument separe ;
    #   - la commande est le premier mot restant, compare EXACTEMENT a la table
    #     des commandes (Map JavaScript, aucune mise en minuscules) ;
    #   - un mot qui n est pas une commande est pris pour un chemin a deployer,
    #     et pas de mot du tout, c est `vercel deploy` ;
    #   - une option inconnue de cette premiere lecture (`--prod`, `-e`) n est
    #     pas ecartee : elle DEVIENT le premier mot, donc un deploiement.
    #
    # Avant ce correctif, `Get-CtxVercelMots` ecartait les options mais gardait
    # leurs valeurs, et mettait tout en minuscules : chacune des lignes
    # refusees ci-dessous passait pour une commande sans effet distant.

    It 'REFUSE <Ligne> : la valeur d une option globale n est pas la commande' -ForEach @(
        @{ Ligne = '--cwd build --prod' }
        @{ Ligne = '--cwd=build --prod' }
        @{ Ligne = '--local-config build --prod' }
        @{ Ligne = '-A build --prod' }
        @{ Ligne = '--global-config build --prod' }
        @{ Ligne = '-Q build --prod' }
        @{ Ligne = '--scope build --prod' }
        @{ Ligne = '-S build --prod' }
        @{ Ligne = '--token build --prod' }
        @{ Ligne = '-t build --prod' }
        @{ Ligne = '--team build --prod' }
        @{ Ligne = '-T build --prod' }
        @{ Ligne = '--api build --prod' }
    ) {
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
    }

    It 'REFUSE <Ligne> : un nom de commande se compare a la casse pres' -ForEach @(
        @{ Ligne = 'Logs --prod' }
        @{ Ligne = 'BUILD --prod' }
    ) {
        # Sur Windows, un dossier `logs` repond en plus a `Logs` : la CLI
        # deploierait ce dossier-la, en production.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
    }

    It 'REFUSE vercel dist --prod : un mot inconnu est un chemin a deployer' {
        $v = Test-CtxVercelGuard -Arguments @('dist', '--prod') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
    }

    It 'REFUSE <Ligne> : un mot qui n est plus une commande redevient un chemin' -ForEach @(
        @{ Ligne = 'notifications --prod' }
        @{ Ligne = 'guidance --prod' }
    ) {
        # Le sens dangereux de cette liste. Une commande OUBLIEE coute un refus
        # de trop ; un mot que la CLI ne connait plus, reste dans la liste, fait
        # passer pour sans effet ce que la CLI deploie. `notifications` a quitte
        # la table avant la 65.8.0, et `guidance` n y entre que sous un drapeau
        # interne. Releve par le contre-audit du 7 novembre 2026.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
    }

    It 'laisse passer <Ligne>, commande de la table 65.8.0' -ForEach @(
        @{ Ligne = 'monitors --prod' }
        @{ Ligne = 'page-integrity --prod' }
        @{ Ligne = 'metrics --prod' }
        @{ Ligne = 'connect --prod' }
        @{ Ligne = 'token-pass --prod' }
    ) {
        # metrics et connect sont ajoutes APRES le tableau des commandes :
        # les lire dans le seul tableau les ferait croire disparus.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'non-deploiement'
    }

    It 'REFUSE <Cas> : une espace autour de production ne l efface pas' -ForEach @(
        @{ Cas = 'deploy'; Arguments = @('deploy', '--environment', ' production'); Regle = 'prod-hors-branche' }
        @{ Cas = 'deploy ='; Arguments = @('deploy', '--environment= production '); Regle = 'prod-hors-branche' }
        @{ Cas = 'env rm'; Arguments = @('env', 'rm', 'CLE', '--environment', ' production'); Regle = 'env-rm-production' }
        @{ Cas = 'env rm, liste'; Arguments = @('env', 'rm', 'CLE', '--environment', 'preview, production'); Regle = 'env-rm-production' }
    ) {
        # La CLI ne retire pas l espace dans parseTarget, et ce que l API en
        # fait n est pas connu : mieux vaut un refus de trop que de le parier.
        $v = Test-CtxVercelGuard -Arguments $Arguments -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be $Regle
    }

    It 'REFUSE <Ligne> : une option inconnue avant la commande rend la lecture ambigue' -ForEach @(
        @{ Ligne = '--prod build' }
        @{ Ligne = '-e K=V build --prod' }
        @{ Ligne = '--meta k=v build --prod' }
        @{ Ligne = '--build-env K=V build --prod' }
        @{ Ligne = '--DEBUG build --prod' }
        @{ Ligne = '-Qd x build --prod' }
        @{ Ligne = '-dx build --prod' }
        @{ Ligne = '--no-cwd build --prod' }
        @{ Ligne = '--cwd --prod build' }
    ) {
        # `-e`, `-m` et `-b` sont des options de `deploy`, pas des options
        # globales : avant la commande, la CLI ne leur connait pas de valeur et
        # deploie. Sauter leur valeur aurait fait lire `build` et rouvert le
        # trou. Une lecture incertaine se resout du cote du refus.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
    }

    It 'laisse passer <Ligne>, qui ne deploie rien' -ForEach @(
        @{ Ligne = 'build --prod' }
        @{ Ligne = '--debug build --prod' }
        @{ Ligne = '-d build --prod' }
        @{ Ligne = '--scope equipe build --prod' }
        @{ Ligne = '-S equipe build --prod' }
        @{ Ligne = '--cwd=app build --prod' }
        @{ Ligne = '--cwd app ls --prod' }
    ) {
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'non-deploiement'
    }

    It 'REFUSE toujours deploy derriere une option globale' {
        $v = Test-CtxVercelGuard -Arguments @('--scope', 'equipe', 'deploy', '--prod') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
    }

    It 'REFUSE <Ligne> : env rm sur la production, sous toutes ses ecritures' -ForEach @(
        @{ Ligne = '--cwd app env rm CLE production' }
        @{ Ligne = '-S equipe env rm CLE production' }
        @{ Ligne = 'env remove CLE production' }
        @{ Ligne = 'env rm CLE --environment production' }
        @{ Ligne = 'env rm CLE --environment=production --yes' }
        @{ Ligne = 'env rm CLE -e production' }
        @{ Ligne = 'env rm CLE --environment preview,production' }
    ) {
        # `remove` est l alias declare de `rm` ; `--environment` (court `-e`)
        # remplace l argument positionnel, desormais deprecie, et la CLI joint
        # par des virgules les environnements multiples.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ')
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'env-rm-production'
    }

    It 'REFUSE <Ligne> : la production se demande aussi par --environment, -e, --target et --prod=' -ForEach @(
        @{ Ligne = 'deploy --environment production' }
        @{ Ligne = 'deploy --environment=production' }
        @{ Ligne = 'deploy -e production' }
        @{ Ligne = '--environment production' }
        @{ Ligne = 'deploy --prod=false' }
        @{ Ligne = 'deploy --prod=1' }
        @{ Ligne = 'deploy --target preview --target production' }
        @{ Ligne = 'deploy --environment preview --environment production' }
        @{ Ligne = 'redeploy https://x --environment production' }
    ) {
        # Releve dans la CLI 65.8.0 installee, lue sans etre executee :
        # `--environment` (court `-e`) est l option principale de deploy et de
        # redeploy, `--target` n en est plus que l alias deprecie, et `arg`
        # donne VRAI a un booleen quelle que soit la valeur ecrite apres `=`.
        # Une option a valeur repetee garde la DERNIERE occurrence : la
        # production se reconnait donc a n importe quelle occurrence.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'prod-hors-branche'
    }

    It 'laisse passer un deploiement de preview nomme par --environment' {
        (Test-CtxVercelGuard -Arguments @('deploy', '--environment', 'preview') -CurrentBranch 'feat/x' -DefaultBranch 'main').Allowed |
            Should -BeTrue
    }

    It 'lit comme la CLI <Ligne>, sans la croire ambigue' -ForEach @(
        @{ Ligne = '-dd build --prod' }
        @{ Ligne = '-dQ cfg build --prod' }
        @{ Ligne = '--debug=1 build --prod' }
        @{ Ligne = '--no-debug build --prod' }
        @{ Ligne = '-- build --prod' }
    ) {
        # `arg` eclate `-dd` en deux `-d`, accepte une lettre a valeur en fin
        # de groupe, ignore la valeur ecrite apres `=` sur un booleen, accepte
        # la negation `--no-` de chaque booleen global, et fait de tout ce qui
        # suit `--` des mots.
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ') -CurrentBranch 'feat/x' -DefaultBranch 'main'
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'non-deploiement'
    }

    It 'REFUSE <Ligne> : une lecture ambigue ne vaut jamais absence de env rm' -ForEach @(
        @{ Ligne = '-dd env rm CLE production' }
        @{ Ligne = '--debug=1 env rm CLE production' }
        @{ Ligne = '-- env rm CLE production' }
        @{ Ligne = '--inconnue env rm CLE production' }
        @{ Ligne = '-dS equipe env rm CLE production' }
    ) {
        $v = Test-CtxVercelGuard -Arguments ($Ligne -split ' ')
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'env-rm-production'
    }

    It 'laisse passer env rm visant un autre environnement, meme nomme d apres la production' {
        (Test-CtxVercelGuard -Arguments @('env', 'rm', 'CLE', '--environment', 'preview', '--git-branch', 'production-fix')).Allowed |
            Should -BeTrue
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

    It 'REFUSE <Ligne> sans appeler le leurre' -ForEach @(
        @{ Ligne = '--cwd build --prod' }
        @{ Ligne = 'Logs --prod' }
        @{ Ligne = '--prod build' }
        @{ Ligne = 'env rm CLE --environment=production' }
    ) {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy $Ligne ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'laisse passer <Ligne> jusqu au leurre' -ForEach @(
        @{ Ligne = 'build --prod' }
        @{ Ligne = '--debug build --prod' }
    ) {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy $Ligne ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'redirige vercel login meme derriere une option globale' {
        # `--scope equipe login` est un `login` : lu mot par mot, `equipe`
        # passait pour la commande, et la session ouverte atterrissait dans la
        # configuration GLOBALE -- celle du dernier compte connecte.
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy '--scope equipe login' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Match '--global-config'
    }

    It 'redirige vercel login meme derriere une lecture ambigue' {
        # Ne pas savoir lire la ligne ne doit jamais envoyer une session dans
        # la configuration globale.
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy '--inconnue login' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Match '--global-config'
    }

    It 'REFUSE deploy --environment production sans appeler le leurre' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'deploy --environment production' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'laisse passer la derogation explicite' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'deploy --prod' '1'
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }
}
