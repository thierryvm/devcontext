# Le garde-fou vu depuis chaque shell qui peut l'appeler.
#
# C'est la raison d'être du shim, et donc l'endroit où une régression coûte le
# plus cher. Le 15 août 2026, `supabase db reset --linked` contre demo-app-prod est
# passé depuis git-bash : la suite était verte, parce qu'elle n'interrogeait que
# PowerShell — le seul shell qui était déjà couvert par l'alias du module.
#
# Chaque test monte un monde factice et un binaire LEURRE. Un garde-fou éprouvé
# contre la vraie CLI, ce serait parier la base sur son bon fonctionnement ; ici,
# un garde-fou défaillant appelle le leurre, le test devient rouge, et rien n'est
# détruit.

BeforeAll {
    $script:ShimDir = (Resolve-Path (Join-Path $PSScriptRoot '..' 'shims')).Path

    # --- monde factice ----------------------------------------------------
    $script:ctxRoot  = Join-Path $TestDrive 'CTX'
    $script:projRoot = Join-Path $TestDrive 'PROJECTS'
    $ctxDir = Join-Path $script:ctxRoot 'demo'
    New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null

    @{ name = 'demo'; label = 'Demo'; email = 'demo@exemple.com'; root = $script:projRoot } |
        ConvertTo-Json | Set-Content (Join-Path $ctxDir 'context.json') -Encoding UTF8

    @{ 'refdeprod00000000000' = @{ key = 'supabase-token'; name = 'demo-prod'; env = 'prod'; envSource = 'auto' } } |
        ConvertTo-Json -Depth 4 | Set-Content (Join-Path $ctxDir 'supabase-index.json') -Encoding UTF8

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

    $script:decoy = Join-Path $TestDrive 'bin'
    New-Item -ItemType Directory -Path $script:decoy -Force | Out-Null
    "@echo off`r`necho LEURRE-APPELE`r`nexit /b 42" |
        Set-Content (Join-Path $script:decoy 'supabase.cmd') -Encoding ascii

    # Le leurre `gh` annonce EN PLUS le dossier de configuration recu : c'est la
    # seule trace que laisse une redirection, et donc la seule facon de prouver
    # depuis bash que l'identite a bien ete corrigee.
    "@echo off`r`necho LEURRE-APPELE`r`necho CONFIG=%GH_CONFIG_DIR%`r`nexit /b 42" |
        Set-Content (Join-Path $script:decoy 'gh.cmd') -Encoding ascii

    # Le contexte factice possede un compte gh : c'est la condition qui autorise
    # la redirection, et donc l'etat normal d'une machine correctement installee.
    $script:ghConfig = Join-Path $ctxDir 'gh'
    New-Item -ItemType Directory -Path $script:ghConfig -Force | Out-Null
    Set-Content (Join-Path $script:ghConfig 'hosts.yml') 'github.com:' -Encoding ascii

    # GIT-BASH explicitement, et surtout pas `bash` tout court : sous Windows,
    # `bash` resout d'abord vers C:\WINDOWS\system32\bash.exe, qui est le
    # lanceur WSL. WSL voit un autre systeme de fichiers (/mnt/c, pas /c) et
    # surtout un autre PATH — le shim n'y est donc pas, et le test aurait
    # mesure la mauvaise chose. Cette limite est reelle et assumee : elle est
    # signalee par `ctx doctor`, pas contournee ici.
    $script:bash = @(
        'C:\Program Files\Git\bin\bash.exe'
        'C:\Program Files\Git\usr\bin\bash.exe'
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    # MSYS monte les lecteurs en MINUSCULE : /c/Users/..., jamais /C/Users/...
    # Avec la majuscule, bash repond « No such file or directory » sur un
    # fichier qui existe pourtant.
    $script:VersPosix = {
        param([string]$p)
        '/' + $p.Substring(0, 1).ToLowerInvariant() + ($p.Substring(2) -replace '\\', '/')
    }
}

AfterAll {
    # git rend ses objets en LECTURE SEULE sous Windows. Pester echoue alors a
    # nettoyer son TestDrive, et signale l echec du conteneur entier — des tests
    # verts rapportes comme un echec, ce qui est la pire des deux erreurs.
    Get-ChildItem $TestDrive -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer -and $_.IsReadOnly } |
        ForEach-Object { $_.IsReadOnly = $false }
}

Describe 'point d entree cmd.exe' {
    It 'refuse db reset et n appelle jamais le binaire' {
        $script = Join-Path $TestDrive 'refus.cmd'
        @"
@echo off
set DEVCTX_ROOT=$script:ctxRoot
set DEVCTX=
set DEVCTX_ALLOW_PROD=
set PATH=$script:ShimDir;$script:decoy;%PATH%
cd /d "$script:proj"
supabase db reset
"@ | Set-Content $script -Encoding ascii

        $sortie = & cmd.exe /c $script 2>&1 | Out-String
        $code = $LASTEXITCODE

        $sortie | Should -Match 'REFUSE'
        $sortie | Should -Not -Match 'LEURRE-APPELE'
        $code   | Should -Be 1
    }

    It 'propage le code de sortie du binaire reel sur une commande permise' {
        # Le .cmd doit rendre %ERRORLEVEL% : sans ca, tout echec de la CLI
        # devient un succes silencieux pour l appelant.
        $script = Join-Path $TestDrive 'passe.cmd'
        @"
@echo off
set DEVCTX_ROOT=$script:ctxRoot
set DEVCTX=
set PATH=$script:ShimDir;$script:decoy;%PATH%
cd /d "$script:proj"
supabase db pull
"@ | Set-Content $script -Encoding ascii

        $sortie = & cmd.exe /c $script 2>&1 | Out-String
        $code = $LASTEXITCODE

        $sortie | Should -Match 'LEURRE-APPELE'
        $code   | Should -Be 42
    }
}

Describe 'point d entree POSIX (git-bash)' {
    It 'refuse db reset sans contexte actif' {
        # LE test du 15 aout 2026. git-bash n'a jamais de DEVCTX : si le shim
        # s'appuie sur la session plutot que sur le dossier, il s'efface ici.
        if (-not $script:bash) { Set-ItResult -Skipped -Because 'bash absent de cette machine'; return }

        $sh = Join-Path $TestDrive 'refus.sh'
        $shimU = & $script:VersPosix $script:ShimDir
        $decoU = & $script:VersPosix $script:decoy
        $projU = & $script:VersPosix $script:proj
        @"
#!/bin/sh
export DEVCTX_ROOT='$($script:ctxRoot)'
unset DEVCTX
unset DEVCTX_ALLOW_PROD
export PATH="${shimU}:${decoU}:`$PATH"
cd "$projU"
supabase db reset
"@ -replace "`r`n", "`n" | Set-Content $sh -Encoding ascii -NoNewline

        # bash recoit un chemin POSIX : passe en chemin Windows, il en avale les
        # antislashs et se plaint d un fichier introuvable.
        $shU = & $script:VersPosix $sh
        $sortie = & $script:bash $shU 2>&1 | Out-String
        $code = $LASTEXITCODE

        $sortie | Should -Match 'REFUSE'
        $sortie | Should -Not -Match 'LEURRE-APPELE'
        $code   | Should -Be 1
    }

    It 'laisse passer une commande inoffensive et propage le code' {
        if (-not $script:bash) { Set-ItResult -Skipped -Because 'bash absent de cette machine'; return }

        $sh = Join-Path $TestDrive 'passe.sh'
        $shimU = & $script:VersPosix $script:ShimDir
        $decoU = & $script:VersPosix $script:decoy
        $projU = & $script:VersPosix $script:proj
        @"
#!/bin/sh
export DEVCTX_ROOT='$($script:ctxRoot)'
unset DEVCTX
export PATH="${shimU}:${decoU}:`$PATH"
cd "$projU"
supabase db pull
"@ -replace "`r`n", "`n" | Set-Content $sh -Encoding ascii -NoNewline

        # bash recoit un chemin POSIX : passe en chemin Windows, il en avale les
        # antislashs et se plaint d un fichier introuvable.
        $shU = & $script:VersPosix $sh
        $sortie = & $script:bash $shU 2>&1 | Out-String
        $sortie | Should -Match 'LEURRE-APPELE'
        $LASTEXITCODE | Should -Be 42
    }
}

Describe 'gh depuis git-bash — la panne fondatrice' {
    # git-bash n'a JAMAIS de GH_CONFIG_DIR : `work` est une commande PowerShell.
    # Jusqu'a la 1.4.0, `gh` y repartait donc sur la configuration globale de la
    # machine, c'est-a-dire sur le dernier compte connecte. C'est l'incident qui
    # a fait naitre ce module, et il etait traite par la consigne « ne jamais
    # lancer gh depuis bash ».
    #
    # Ces deux tests sont la preuve que la consigne n'est plus necessaire.

    It 'corrige l identite au lieu de la subir' {
        if (-not $script:bash) { Set-ItResult -Skipped -Because 'bash absent de cette machine'; return }

        $sh = Join-Path $TestDrive 'gh-redirige.sh'
        $shimU = & $script:VersPosix $script:ShimDir
        $decoU = & $script:VersPosix $script:decoy
        $projU = & $script:VersPosix $script:proj
        @"
#!/bin/sh
export DEVCTX_ROOT='$($script:ctxRoot)'
unset DEVCTX
unset GH_CONFIG_DIR
unset DEVCTX_ALLOW_GH
export PATH="${shimU}:${decoU}:`$PATH"
cd "$projU"
gh pr create
"@ -replace "`r`n", "`n" | Set-Content $sh -Encoding ascii -NoNewline

        $sortie = & $script:bash (& $script:VersPosix $sh) 2>&1 | Out-String

        $sortie | Should -Match 'LEURRE-APPELE'
        $sortie | Should -Match ([regex]::Escape($script:ghConfig))
        $sortie | Should -Not -Match 'REFUSE'
    }

    It 'REFUSE une ecriture quand le contexte n a aucun compte a proposer' {
        if (-not $script:bash) { Set-ItResult -Skipped -Because 'bash absent de cette machine'; return }

        # On retire le compte du contexte : il ne reste alors rien vers quoi
        # rediriger, et une ecriture partirait sous le compte global.
        $sauvegarde = Join-Path $TestDrive 'hosts-sauve.yml'
        Move-Item (Join-Path $script:ghConfig 'hosts.yml') $sauvegarde -Force
        try {
            $sh = Join-Path $TestDrive 'gh-refus.sh'
            $shimU = & $script:VersPosix $script:ShimDir
            $decoU = & $script:VersPosix $script:decoy
            $projU = & $script:VersPosix $script:proj
            @"
#!/bin/sh
export DEVCTX_ROOT='$($script:ctxRoot)'
unset DEVCTX
unset GH_CONFIG_DIR
unset DEVCTX_ALLOW_GH
export PATH="${shimU}:${decoU}:`$PATH"
cd "$projU"
gh pr create
"@ -replace "`r`n", "`n" | Set-Content $sh -Encoding ascii -NoNewline

            $sortie = & $script:bash (& $script:VersPosix $sh) 2>&1 | Out-String
            $code = $LASTEXITCODE

            $sortie | Should -Match 'REFUSE'
            $sortie | Should -Not -Match 'LEURRE-APPELE'
            $code   | Should -Be 1
        }
        finally { Move-Item $sauvegarde (Join-Path $script:ghConfig 'hosts.yml') -Force }
    }
}

Describe 'fins de ligne des points d entree' {
    # Sur les TROIS outils, et non sur le seul supabase. Un shim livre avec les
    # mauvaises fins de ligne ne casse rien sous Windows : il ne casse que sous
    # bash, c'est-a-dire exactement la population pour laquelle il existe. Une
    # regression pareille resterait invisible ici jusqu'au jour ou elle compte.
    It 'le lanceur POSIX de <_> n a pas de retour chariot Windows' -ForEach @('supabase', 'gh', 'vercel') {
        # Un #!/bin/sh suivi de CRLF echoue sous Unix par
        # « bad interpreter: /bin/sh^M ». .gitattributes l impose ; ce test le
        # verifie sur le fichier reellement present dans la copie de travail.
        $octets = [System.IO.File]::ReadAllBytes((Join-Path $script:ShimDir $_))
        $texte  = [System.Text.Encoding]::ASCII.GetString($octets)
        $texte | Should -Not -Match "`r"
    }

    It 'le lanceur cmd de <_> garde bien des CRLF' -ForEach @('supabase', 'gh', 'vercel') {
        # L inverse : cmd.exe supporte mal un .cmd en LF seul.
        $octets = [System.IO.File]::ReadAllBytes((Join-Path $script:ShimDir "$_.cmd"))
        [System.Text.Encoding]::ASCII.GetString($octets) | Should -Match "`r`n"
    }
}
