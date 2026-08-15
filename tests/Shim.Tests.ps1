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

Describe 'shim — refus de bout en bout' {
    # Builds a whole fake world under $TestDrive: a context, an index with one
    # production project, a linked folder, a git repository on a side branch,
    # and a DECOY binary.
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
            'refdeprod' = @{ key = 'supabase-token'; name = 'demo-prod'; env = 'prod'; envSource = 'auto' }
            'refdedev'  = @{ key = 'supabase-token'; name = 'demo-dev';  env = 'dev';  envSource = 'auto' }
        } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ctxDir 'supabase-index.json') -Encoding UTF8

        # Project linked to the production ref, on a branch that is not default
        $script:proj = Join-Path $script:projRoot 'appli'
        New-Item -ItemType Directory -Path (Join-Path $script:proj 'supabase' '.temp') -Force | Out-Null
        Set-Content (Join-Path $script:proj 'supabase' '.temp' 'project-ref') 'refdeprod' -NoNewline

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
        Set-Content (Join-Path $script:proj 'supabase' '.temp' 'project-ref') 'refdedev' -NoNewline
        try {
            $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'db reset' ''
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Code   | Should -Be 42
        }
        finally {
            Set-Content (Join-Path $script:proj 'supabase' '.temp' 'project-ref') 'refdeprod' -NoNewline
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
}
