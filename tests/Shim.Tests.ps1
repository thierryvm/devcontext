BeforeAll {
    $script:ShimDir = Join-Path $PSScriptRoot '..' 'shims'
    $script:Shim    = Join-Path $script:ShimDir 'supabase.ps1'
}

Describe 'shim — les trois points d entree' {
    It 'expose supabase.ps1, supabase.cmd et supabase' {
        # Three files on purpose: PowerShell and cmd resolve the .cmd, POSIX
        # shells resolve only the extensionless one. Losing that sibling would
        # silently uncover git-bash, which is the caller that matters most.
        Test-Path (Join-Path $script:ShimDir 'supabase.ps1') | Should -BeTrue
        Test-Path (Join-Path $script:ShimDir 'supabase.cmd') | Should -BeTrue
        Test-Path (Join-Path $script:ShimDir 'supabase')     | Should -BeTrue
    }

    It 'a une syntaxe PowerShell valide' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $script:Shim).Path, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }

    It 'ne declare aucun bloc param, qui avalerait les arguments' {
        # [CmdletBinding()] would capture -debug or -verbose as its own
        # parameters instead of forwarding them to the CLI.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $script:Shim).Path, [ref]$null, [ref]$null)
        $ast.ParamBlock | Should -BeNullOrEmpty
    }

    It 'n imprime jamais de variable d environnement sensible' {
        # A refusal message ends up in logs and pasted into chats.
        $texte = Get-Content (Resolve-Path $script:Shim).Path -Raw
        $texte | Should -Not -Match 'SUPABASE_ACCESS_TOKEN'
        $texte | Should -Not -Match 'GH_TOKEN'
        $texte | Should -Not -Match 'VERCEL_TOKEN'
    }

    It 'le point d entree POSIX delegue au meme script' {
        $sh = Get-Content (Join-Path $script:ShimDir 'supabase') -Raw
        $sh | Should -Match 'supabase\.ps1'
        $sh | Should -Match '^#!/bin/sh'
    }

    It 'le point d entree cmd propage le code de sortie' {
        $cmd = Get-Content (Join-Path $script:ShimDir 'supabase.cmd') -Raw
        $cmd | Should -Match 'ERRORLEVEL'
        $cmd | Should -Match 'supabase\.ps1'
    }
}

Describe 'shim — delegation' {
    It 'transmet une commande inoffensive et rend le code 0' {
        $out = pwsh -NoProfile -File $script:Shim --version 2>&1
        $LASTEXITCODE   | Should -Be 0
        ($out -join ' ') | Should -Not -Match 'REFUSE'
    }

    It 'propage un echec du binaire reel' {
        pwsh -NoProfile -File $script:Shim 'sous-commande-inexistante' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'delegue quand aucun contexte n est actif' {
        $avant = $env:DEVCTX
        try {
            Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
            $out = pwsh -NoProfile -File $script:Shim --version 2>&1
            ($out -join ' ') | Should -Not -Match 'REFUSE'
        }
        finally { if ($avant) { $env:DEVCTX = $avant } }
    }
}

Describe 'garde-fou de production — de bout en bout' {
    # Builds a whole fake world under $TestDrive: a context, an index with one
    # production project, a linked folder, a git repository on a side branch,
    # and a DECOY binary.
    #
    # Deux appelants sont exerces sur ce meme monde, et ce n'est pas une
    # commodite : le shim PATH et l'alias PowerShell portent la MEME regle, donc
    # ils doivent rendre le MEME verdict. Le 16 aout 2026, ils ne le rendaient
    # pas -- voir le Describe des deux appelants plus bas.
    #
    # The decoy is the point. Testing a destructive command against the real
    # CLI would mean betting the database on the guard working. Here, a guard
    # that fails calls the decoy, the test goes red, and nothing is destroyed.

    BeforeAll {
        $script:ctxRoot = Join-Path $TestDrive 'CTX'
        $script:projRoot = Join-Path $TestDrive 'PROJECTS'
        $ctxDir = Join-Path $script:ctxRoot 'demo'
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null

        @{
            name = 'demo'; label = 'Demo'; email = 'demo@exemple.com'
            root = $script:projRoot
        } | ConvertTo-Json | Set-Content (Join-Path $ctxDir 'context.json') -Encoding UTF8

        @{
            'refdeprod00000000000' = @{ key = 'supabase-token'; name = 'demo-prod'; env = 'prod'; envSource = 'auto' }
            'refdedev000000000000'  = @{ key = 'supabase-token'; name = 'demo-dev';  env = 'dev';  envSource = 'auto' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ctxDir 'supabase-index.json') -Encoding UTF8

        # Project linked to the production ref, on a branch that is not default
        $script:proj = Join-Path $script:projRoot 'appli'
        New-Item -ItemType Directory -Path (Join-Path $script:proj 'supabase' '.temp') -Force | Out-Null
        Set-Content (Join-Path $script:proj 'supabase' '.temp' 'project-ref') 'refdeprod00000000000' -NoNewline

        Push-Location $script:proj
        try {
            git init -b main --quiet 2>$null | Out-Null
            git -c user.email='t@exemple.com' -c user.name='T' commit --allow-empty -m 'init' --quiet 2>$null | Out-Null
            git checkout -b 'feat/chantier' --quiet 2>$null | Out-Null
        }
        finally { Pop-Location }

        # Decoy: stands in for the real CLI and announces itself loudly
        $script:decoy = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Path $script:decoy -Force | Out-Null
        @"
@echo off
echo LEURRE-APPELE
exit /b 42
"@ | Set-Content (Join-Path $script:decoy 'supabase.cmd') -Encoding ascii

        # UN SECOND DEPOT, sur la branche par defaut, et hors de tout contexte.
        # Il sert a prouver que le garde-fou juge la branche du dossier VISE et
        # non celle d'ou la commande est tapee.
        $script:ailleurs = Join-Path $TestDrive 'ailleurs'
        New-Item -ItemType Directory -Path $script:ailleurs -Force | Out-Null
        Push-Location $script:ailleurs
        try {
            git init -b main --quiet 2>$null | Out-Null
            git -c user.email='t@exemple.com' -c user.name='T' commit --allow-empty -m 'init' --quiet 2>$null | Out-Null
        }
        finally { Pop-Location }

        $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path

        # NOT $Args: it is a PowerShell automatic variable, and a parameter of
        # that name is silently overwritten by the scriptblock's own argument
        # array. The module was bitten by exactly this on 5 Aug 2026 -- see the
        # "Ce qui est verifie" section of README.md, where $profile and $Args
        # are named. The shim then received garbage and let everything pass.
        $script:Run = {
            param($ShimPath, $Proj, $CtxRoot, $Decoy, $CliArgs, $Allow, $SansContexte)
            # Il faut EFFACER la variable, pas seulement s'abstenir de la poser :
            # `pwsh -Command` herite de l'environnement du parent, et Pester
            # tourne dans un shell ou un contexte est actif. S'abstenir laissait
            # l'enfant heriter de DEVCTX='perso' — le test ne reproduisait donc
            # jamais la condition qu'il annonçait, et serait reste vert sur un
            # shim casse.
            $poseCtx = if ($SansContexte) {
                'Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue'
            } else {
                "`$env:DEVCTX = 'demo'"
            }
            $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
$poseCtx
`$env:DEVCTX_ALLOW_PROD = '$Allow'
`$env:PATH = '$Decoy;' + `$env:PATH
Set-Location '$Proj'
& '$ShimPath' $CliArgs
exit `$LASTEXITCODE
"@
            $out = pwsh -NoProfile -Command $code 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
        }

        # LE MEME MONDE, PAR L'AUTRE APPELANT.
        #
        # Dans un shell PowerShell qui a importe le module -- c'est-a-dire tous
        # ceux que `work` ouvre -- `supabase` ne resout PAS le shim du PATH :
        # l'alias du module le precede. Ce runner exerce donc le chemin reel de
        # l'utilisateur, pas celui que la suite avait teste jusqu'ici.
        $script:RunAlias = {
            param($Module, $Proj, $CtxRoot, $Decoy, $CliArgs, $Allow, $SansContexte)
            $poseCtx = if ($SansContexte) {
                'Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue'
            } else {
                "`$env:DEVCTX = 'demo'"
            }
            $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
$poseCtx
`$env:DEVCTX_ALLOW_PROD = '$Allow'
`$env:PATH = '$Decoy;' + `$env:PATH
Import-Module '$Module' -Force
Set-Location '$Proj'
supabase $CliArgs
exit `$LASTEXITCODE
"@
            $out = pwsh -NoProfile -Command $code 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
        }
    }

    It 'refuse db reset et n appelle JAMAIS le binaire' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db reset' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Match 'demo-prod'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'refuse db push depuis une branche qui n est pas la branche par defaut' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db push' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'laisse passer db pull et propage le code de sortie du binaire' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db pull' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'laisse passer db reset quand le contournement explicite est pose' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db reset' '1'
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'laisse passer db reset sur un projet qui n est pas marque prod' {
        Set-Content (Join-Path $script:proj 'supabase' '.temp' 'project-ref') 'refdedev000000000000' -NoNewline
        try {
            $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db reset' ''
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Code   | Should -Be 42
        }
        finally {
            Set-Content (Join-Path $script:proj 'supabase' '.temp' 'project-ref') 'refdeprod00000000000' -NoNewline
        }
    }

    It 'refuse db reset SANS contexte actif, en resolvant le dossier' {
        # Le trou du 15 aout 2026. Le shim commencait par
        #     if (-not $env:DEVCTX) { Invoke-Real }
        # donc il s'effacait des que la variable de session manquait — c'est-a-dire
        # dans git-bash, dans un script npm, dans un execFileSync Node, dans le
        # shell d'un agent. Soit exactement la population pour laquelle il
        # existe : la ou l'alias PowerShell ne va pas.
        #
        # Verifie en vrai le 15 aout 2026 : `supabase db reset --linked` sur
        # demo-app-prod est passe depuis git-bash. Il n'a echoue que sur un
        # timeout reseau.
        #
        # C'est le DOSSIER qui decide, jamais la session.
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db reset' '' $true
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Match 'demo-prod'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'refuse db push hors branche par defaut SANS contexte actif' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db push' '' $true
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'laisse passer une commande inoffensive SANS contexte actif' {
        # La correction ne doit pas transformer l'absence de contexte en blocage
        # general : ce serait rendre l'outil insupportable et le faire desinstaller.
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db pull' '' $true
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'laisse passer db push une fois revenu sur la branche par defaut' {
        Push-Location $script:proj
        try {
            git checkout main --quiet 2>$null | Out-Null
            $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db push' ''
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Code   | Should -Be 42
        }
        finally {
            git checkout 'feat/chantier' --quiet 2>$null | Out-Null
            Pop-Location
        }
    }

    It 'juge la branche du dossier VISE par --workdir, pas celle d ou on tape' {
        # Meme faute que l'alias, a un autre endroit : decider sur le mauvais
        # sujet. Le shim resolvait bien la BASE depuis --workdir -- correction du
        # 15 aout 2026 -- mais continuait de lire la BRANCHE dans le dossier
        # courant. Depuis un depot pose sur sa branche par defaut, un `db push`
        # vers un projet de production reste sur une branche laterale passait
        # donc sans un mot, et le refus se declenchait sur des depots sans
        # rapport.
        $r = & $script:Run $script:Shim $script:ailleurs $script:ctxRoot $script:decoy `
            "--workdir `"$($script:proj)`" db push" ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }
}

Describe 'garde-fou de production — les DEUX appelants' {
    # LE TROU DU 16 AOUT 2026.
    #
    # Toute la suite ci-dessus appelle le shim par son chemin. Or dans un shell
    # PowerShell ayant importe le module, `supabase` ne resout pas le shim :
    #
    #     Get-Command supabase -All
    #     Alias        supabase        DevContext      <-- gagne
    #     Application  supabase.cmd    ...\shims\
    #
    # L'alias mene a Invoke-DevSupabase, qui n'appelait pas Test-CtxSupabaseGuard.
    # Mesure sur un leurre le 16 aout 2026 : `supabase db reset --linked` sur un
    # projet marque prod, depuis un dossier lie, sur une branche laterale --
    # binaire appele, code 42, aucun refus. Et `work` importe le module, donc
    # c'etait le cas de TOUS les terminaux de l'auteur.
    #
    # Meme motif que l'incident du fichier de format (13 aout 2026) : deux
    # mecanismes pour un seul travail, le plus faible gagne en silence.

    BeforeAll {
        $script:ctxRoot2  = Join-Path $TestDrive 'CTX2'
        $script:projRoot2 = Join-Path $TestDrive 'PROJECTS2'
        $ctxDir = Join-Path $script:ctxRoot2 'demo'
        New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null

        @{
            name = 'demo'; label = 'Demo'; email = 'demo@exemple.com'
            root = $script:projRoot2
        } | ConvertTo-Json | Set-Content (Join-Path $ctxDir 'context.json') -Encoding UTF8

        @{
            'refdeprod00000000000' = @{ key = 'supabase-token'; name = 'demo-prod'; env = 'prod'; envSource = 'auto' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ctxDir 'supabase-index.json') -Encoding UTF8

        $script:proj2 = Join-Path $script:projRoot2 'appli'
        New-Item -ItemType Directory -Path (Join-Path $script:proj2 'supabase' '.temp') -Force | Out-Null
        Set-Content (Join-Path $script:proj2 'supabase' '.temp' 'project-ref') 'refdeprod00000000000' -NoNewline

        Push-Location $script:proj2
        try {
            git init -b main --quiet 2>$null | Out-Null
            git -c user.email='t@exemple.com' -c user.name='T' commit --allow-empty -m 'init' --quiet 2>$null | Out-Null
            git checkout -b 'feat/chantier' --quiet 2>$null | Out-Null
        }
        finally { Pop-Location }

        $script:decoy2 = Join-Path $TestDrive 'bin2'
        New-Item -ItemType Directory -Path $script:decoy2 -Force | Out-Null
        @"
@echo off
echo LEURRE-APPELE
exit /b 42
"@ | Set-Content (Join-Path $script:decoy2 'supabase.cmd') -Encoding ascii

        $script:Module2 = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path

        $script:ParAlias = {
            param($Module, $Proj, $CtxRoot, $Decoy, $CliArgs, $Allow, $SansContexte)
            # Sans contexte actif, Invoke-DevSupabase ne consulte pas le coffre.
            # Les tests de passage l'utilisent pour rester hors de tout secret
            # reel -- et cela exerce au passage la regle qui compte : c'est le
            # DOSSIER qui decide, pas la session.
            $poseCtx = if ($SansContexte) {
                'Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue'
            } else {
                "`$env:DEVCTX = 'demo'"
            }
            $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
$poseCtx
`$env:DEVCTX_ALLOW_PROD = '$Allow'
`$env:PATH = '$Decoy;' + `$env:PATH
Import-Module '$Module' -Force
Set-Location '$Proj'
supabase $CliArgs
exit `$LASTEXITCODE
"@
            $out = pwsh -NoProfile -Command $code 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
        }
    }

    It 'l alias resout bien avant le shim du PATH' {
        # La cause. Si un jour l'alias disparait, ce test rougit et rappelle
        # pourquoi la regle doit vivre a un seul endroit.
        $code = "Import-Module '$($script:Module2)' -Force; (Get-Command supabase).CommandType"
        (pwsh -NoProfile -Command $code) | Should -Be 'Alias'
    }

    It 'ALIAS : refuse db reset et n appelle JAMAIS le binaire' {
        $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'db reset --linked' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Match 'demo-prod'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'ALIAS : refuse db push hors branche par defaut' {
        $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'db push' '' $true
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'ALIAS : laisse passer db pull et propage le code de sortie' {
        # Le correctif ne doit pas transformer l'alias en obstacle : il ne
        # refuse que ce que le shim refuse deja.
        $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'db pull' '' $true
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'ALIAS : laisse passer db reset quand le contournement explicite est pose' {
        $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'db reset' '1' $true
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }
}
