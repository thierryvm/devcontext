# `ctx exec <commande>` -- lancer une commande sous le contexte du DOSSIER.
#
# Le defaut que cette commande ferme, releve le 25 aout 2026 : un processus
# enfant herite de DEVCTX_ALLOW_PROD, la derogation documentee du garde-fou
# production. Un humain desarme le garde-fou une fois, deliberement, dans sa
# session -- et tout ce qu'il lance ensuite porte le garde-fou desarme dans des
# dossiers qui n'y ont jamais consenti.
#
# Les contraintes, toutes testees ici :
#   - l'environnement de l'enfant est CONSTRUIT (liste fermee), jamais copie du
#     parent puis rapiece ;
#   - les trois DEVCTX_ALLOW_* sont retirees, toujours ;
#   - le contexte vient du DOSSIER, jamais de $env:DEVCTX ;
#   - le code de sortie de l'enfant est rendu tel quel ;
#   - un dossier qu'aucun contexte ne possede est un REFUS, avec son propre code ;
#   - l'environnement du processus appelant n'est JAMAIS modifie, pas meme un
#     instant. La premiere version l'echangeait puis le restaurait : deux
#     `ctx exec` en parallele se passaient alors la derogation et le jeton du
#     parent, et un script lance lisait les secrets du parent dans la portee du
#     module. Mesure par l'audit de securite du 27 septembre 2026.
#
# La sortie de l'enfant va a la console, pas au pipeline : les tests la font
# donc ecrire dans un fichier.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Get-CtxEnvironnementDeBase' {
    It 'ne reprend du parent AUCUNE variable hors de la liste fermee' {
        # Le cas qui justifie la construction plutot que la copie : une variable
        # que personne n'a pensee. GITHUB_TOKEN passe AVANT GH_CONFIG_DIR pour
        # gh -- heritee d'une session perso, elle ouvrirait le compte perso dans
        # un dossier client, quel que soit le contexte pose.
        InModuleScope DevContext {
            $base = Get-CtxEnvironnementDeBase -Machine @{ OS = 'Windows_NT' } -Volatile @{} -Utilisateur @{} -Processus @{
                GITHUB_TOKEN      = 'jeton-parent'
                DEVCTX            = 'autre'
                DEVCTX_ALLOW_PROD = '1'
                SystemRoot        = 'C:\WINDOWS'
            }
            $base.ContainsKey('GITHUB_TOKEN') | Should -BeFalse
            $base.ContainsKey('DEVCTX') | Should -BeFalse
            $base.ContainsKey('DEVCTX_ALLOW_PROD') | Should -BeFalse
            $base['SystemRoot'] | Should -Be 'C:\WINDOWS'
            $base['OS'] | Should -Be 'Windows_NT'
        }
    }

    It 'ne reprend pas du parent ce qui oriente l identite ou le code charge' -ForEach @(
        # HOME : git y trouve ~/.gitconfig, donc les includeIf qui choisissent
        # l'identite. PSModulePath : quel DevContext un pwsh enfant charge.
        # DEVCTX_ROOT : ou vivent les contextes -- l'enfant recoit celle qui a
        # DECIDE, jamais celle de la session. Releves par l'audit du 27/09/2026.
        @{ Nom = 'HOME' }
        @{ Nom = 'PSModulePath' }
        @{ Nom = 'DEVCTX_ROOT' }
        @{ Nom = 'USERPROFILE' }
    ) {
        InModuleScope DevContext -Parameters @{ Nom = $Nom } {
            $base = Get-CtxEnvironnementDeBase -Machine @{} -Volatile @{} -Utilisateur @{} -Processus @{ $Nom = 'C:\ailleurs' }
            $base.ContainsKey($Nom) | Should -BeFalse
        }
    }

    It 'compose Path comme Windows : systeme PUIS utilisateur' {
        # Les shims vivent dans le PATH utilisateur. Un Path pris au parent
        # pourrait les avoir perdus -- ou porter node_modules/.bin devant eux.
        InModuleScope DevContext {
            $base = Get-CtxEnvironnementDeBase -Machine @{ Path = 'C:\Sys;' } -Volatile @{} -Utilisateur @{ Path = 'C:\Shims' } -Processus @{ Path = 'C:\Parent' }
            $base['Path'] | Should -Be 'C:\Sys;C:\Shims'
        }
    }

    It 'la valeur utilisateur remplace la valeur systeme, sauf Path' {
        InModuleScope DevContext {
            $base = Get-CtxEnvironnementDeBase -Machine @{ TEMP = 'C:\Windows\Temp' } -Volatile @{} -Utilisateur @{ TEMP = 'C:\Users\moi\Temp' } -Processus @{}
            $base['TEMP'] | Should -Be 'C:\Users\moi\Temp'
        }
    }

    It 'l identite de session vient de la cle Volatile, pas du parent -- le registre systeme dit USERNAME=SYSTEM' {
        InModuleScope DevContext {
            $base = Get-CtxEnvironnementDeBase -Machine @{ USERNAME = 'SYSTEM' } -Volatile @{ USERNAME = 'moi'; USERPROFILE = 'C:\Users\moi' } -Utilisateur @{} -Processus @{ USERNAME = 'usurpe' }
            $base['USERNAME'] | Should -Be 'moi'
            $base['USERPROFILE'] | Should -Be 'C:\Users\moi'
        }
    }

    It 'accepte des sources vides ou nulles' {
        InModuleScope DevContext {
            $base = Get-CtxEnvironnementDeBase -Machine $null -Volatile $null -Utilisateur @{} -Processus $null
            $base | Should -BeOfType [hashtable]
            $base.Count | Should -Be 0
        }
    }
}

Describe 'Get-CtxEnvironnementExec' {
    It 'les variables du contexte remplacent la base' {
        InModuleScope DevContext {
            $r = Get-CtxEnvironnementExec -Base @{ GH_CONFIG_DIR = 'C:\global' } -Contexte ([ordered]@{ GH_CONFIG_DIR = 'C:\ctx\gh' })
            $r['GH_CONFIG_DIR'] | Should -Be 'C:\ctx\gh'
        }
    }

    It 'une valeur $null du contexte RETIRE la variable de la base' {
        # Un secret absent du coffre doit etre absent chez l'enfant -- pas
        # herite d'une variable utilisateur posee un jour a la main.
        InModuleScope DevContext {
            $r = Get-CtxEnvironnementExec -Base @{ GH_TOKEN = 'jeton-registre' } -Contexte ([ordered]@{ GH_TOKEN = $null })
            $r.ContainsKey('GH_TOKEN') | Should -BeFalse
        }
    }

    It 'retire les trois derogations, meme posees dans le registre' -ForEach @(
        @{ Nom = 'DEVCTX_ALLOW_PROD' }
        @{ Nom = 'DEVCTX_ALLOW_GH' }
        @{ Nom = 'DEVCTX_ALLOW_VERCEL' }
    ) {
        InModuleScope DevContext -Parameters @{ Nom = $Nom } {
            $r = Get-CtxEnvironnementExec -Base @{ $Nom = '1' } -Contexte ([ordered]@{})
            $r.ContainsKey($Nom) | Should -BeFalse
        }
    }

    It 'retire les derogations meme si le contexte en porterait une' {
        InModuleScope DevContext {
            $r = Get-CtxEnvironnementExec -Base @{} -Contexte ([ordered]@{ DEVCTX_ALLOW_PROD = '1' })
            $r.ContainsKey('DEVCTX_ALLOW_PROD') | Should -BeFalse
        }
    }

    It 'lit la liste des derogations a la MEME source que ctx doctor' {
        # Deux listes qui doivent s'accorder finissent par diverger : une
        # quatrieme derogation ajoutee au diagnostic seulement passerait a
        # l'enfant sans un mot.
        InModuleScope DevContext {
            $script:CtxDerogations | Should -Contain 'DEVCTX_ALLOW_PROD'
            $script:CtxDerogations | Should -Contain 'DEVCTX_ALLOW_GH'
            $script:CtxDerogations | Should -Contain 'DEVCTX_ALLOW_VERCEL'
        }
        $doctor = Get-Content (Join-Path $PSScriptRoot '..' 'src' 'Doctor.ps1') -Raw
        $doctor | Should -Not -Match "'DEVCTX_ALLOW_GH'" -Because 'le diagnostic doit lire $script:CtxDerogations, pas une copie'
    }
}

Describe 'Get-CtxVariablesContexte' {
    BeforeAll {
        $script:Manifeste = [pscustomobject]@{
            name   = 'acme'
            label  = 'ACME'
            email  = 'dev@acme.test'
            root   = 'C:\Work\acme'
            github = [pscustomobject]@{ login = 'acme-dev' }
        }
    }

    It 'decrit l identite, gh et vercel du contexte' {
        InModuleScope DevContext -Parameters @{ M = $script:Manifeste } {
            $v = Get-CtxVariablesContexte -Manifeste $M -DossierContexte 'C:\ctx\acme' -LireSecret { param($c, $k) $null }
            $v['DEVCTX'] | Should -Be 'acme'
            $v['DEVCTX_LABEL'] | Should -Be 'ACME'
            $v['DEVCTX_DIR'] | Should -Be 'C:\ctx\acme'
            $v['DEVCTX_ROOT_PATH'] | Should -Be 'C:\Work\acme'
            $v['DEVCTX_GH_LOGIN'] | Should -Be 'acme-dev'
            $v['GH_CONFIG_DIR'] | Should -Be ([System.IO.Path]::Combine('C:\ctx\acme', 'gh'))
            $v['DEVCTX_VERCEL_CONFIG'] | Should -Be ([System.IO.Path]::Combine('C:\ctx\acme', 'vercel'))
        }
    }

    It 'porte CHAQUE variable de secret, a $null quand le coffre n en a pas' {
        # $null est une instruction -- « retire-la » -- et non un oubli : sans
        # elle, le jeton d'un autre contexte resterait en place.
        InModuleScope DevContext -Parameters @{ M = $script:Manifeste } {
            $v = Get-CtxVariablesContexte -Manifeste $M -DossierContexte 'C:\ctx\acme' -LireSecret {
                param($c, $k) if ($c -eq 'acme' -and $k -eq 'github-token') { 'jeton-acme' }
            }
            $v['GH_TOKEN'] | Should -Be 'jeton-acme'
            foreach ($var in $script:SecretMap.Values) {
                $v.Contains($var) | Should -BeTrue -Because "$var doit etre decide, pas herite"
            }
            $v['VERCEL_TOKEN'] | Should -BeNullOrEmpty
        }
    }

    It 'lit le coffre sous -NomCoffre quand il est donne -- le nom passe a work' {
        InModuleScope DevContext -Parameters @{ M = $script:Manifeste } {
            $v = Get-CtxVariablesContexte -Manifeste $M -DossierContexte 'C:\ctx\acme' -NomCoffre 'acme-dossier' -LireSecret {
                param($c, $k) if ($c -eq 'acme-dossier' -and $k -eq 'github-token') { 'jeton-du-dossier' }
            }
            $v['GH_TOKEN'] | Should -Be 'jeton-du-dossier'
            $v['DEVCTX'] | Should -Be 'acme'
        }
    }

    It 'VERCEL_ORG_ID est retire quand le manifeste n en a pas' {
        InModuleScope DevContext -Parameters @{ M = $script:Manifeste } {
            $v = Get-CtxVariablesContexte -Manifeste $M -DossierContexte 'C:\ctx\acme' -LireSecret { param($c, $k) $null }
            $v.Contains('VERCEL_ORG_ID') | Should -BeTrue
            $v['VERCEL_ORG_ID'] | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-CtxVariablesSupabase' {
    # Elle decide du jeton Supabase de `work` ET de `ctx exec`. Sans ces tests,
    # y ecrire le NOM de la cle a la place du jeton laissait la suite verte --
    # prouve par la relecture PowerShell du 27 septembre 2026.

    It 'rend le jeton de la cle que le dossier attend, et le nom de cette cle' {
        InModuleScope DevContext {
            Mock Resolve-CtxSupabaseKey { 'supabase-client' }
            $v = Get-CtxVariablesSupabase -Contexte 'acme' -Chemin 'C:\x' -LireSecret {
                param($c, $k) if ($c -eq 'acme' -and $k -eq 'supabase-client') { 'jeton-client' }
            }
            $v['SUPABASE_ACCESS_TOKEN'] | Should -Be 'jeton-client'
            $v['DEVCTX_SUPABASE_KEY'] | Should -Be 'supabase-client'
        }
    }

    It 'retire les deux variables quand le coffre n a pas ce jeton' {
        InModuleScope DevContext {
            Mock Resolve-CtxSupabaseKey { 'supabase-client' }
            $v = Get-CtxVariablesSupabase -Contexte 'acme' -Chemin 'C:\x' -LireSecret { param($c, $k) $null }
            $v.Contains('SUPABASE_ACCESS_TOKEN') | Should -BeTrue
            $v['SUPABASE_ACCESS_TOKEN'] | Should -BeNullOrEmpty
            $v['DEVCTX_SUPABASE_KEY'] | Should -BeNullOrEmpty
        }
    }

    It 'ne decide rien quand l index ne connait pas le projet -- on ne devine pas' {
        InModuleScope DevContext {
            Mock Resolve-CtxSupabaseKey { $null }
            $v = Get-CtxVariablesSupabase -Contexte 'acme' -Chemin 'C:\x' -LireSecret { param($c, $k) 'ne-doit-pas-servir' }
            $v.Count | Should -Be 0
        }
    }

    It 'resout la cle pour le contexte DONNE, jamais pour celui de la session' {
        $avant = $env:DEVCTX
        $env:DEVCTX = 'session'
        try {
            InModuleScope DevContext {
                Mock Resolve-CtxSupabaseKey { 'supabase-token' }
                Get-CtxVariablesSupabase -Contexte 'acme' -Chemin 'C:\x' -LireSecret { param($c, $k) 'j' } | Out-Null
                Should -Invoke Resolve-CtxSupabaseKey -Times 1 -Exactly -ParameterFilter { $Contexte -eq 'acme' }
            }
        }
        finally { $env:DEVCTX = $avant }
    }
}

Describe 'work et ctx exec posent les memes variables' {
    It 'Use-DevContext applique ce que Get-CtxVariablesContexte decrit' {
        # UNE question, UNE fonction. Si `work` calculait ses variables de son
        # cote, un champ ajoute a l'un manquerait a l'autre -- la famille de
        # defauts que la 1.11.0 a fermee pour les verdicts.
        $sauve = @{}
        foreach ($n in @('DEVCTX', 'DEVCTX_LABEL', 'DEVCTX_DIR', 'DEVCTX_ROOT_PATH', 'DEVCTX_GH_LOGIN',
                'GH_CONFIG_DIR', 'DEVCTX_VERCEL_CONFIG', 'VERCEL_ORG_ID', 'DEVCTX_VERCEL_SCOPE',
                'DEVCTX_TEST_SENTINELLE', 'DEVCTX_SUPABASE_KEY') + @(InModuleScope DevContext { $script:SecretMap.Values })) {
            $sauve[$n] = [Environment]::GetEnvironmentVariable($n)
        }
        $titre = $Host.UI.RawUI.WindowTitle
        try {
            InModuleScope DevContext {
                Mock Read-CtxManifest { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test' } }
                Mock Test-CtxVault {}
                Mock Sync-CtxSupabaseEnv {}
                Mock Get-CtxVariablesContexte { [ordered]@{ DEVCTX = 'acme'; DEVCTX_LABEL = 'ACME'; DEVCTX_TEST_SENTINELLE = 'vu' } }
                Use-DevContext acme -NoCd 6>$null
                $env:DEVCTX_TEST_SENTINELLE | Should -Be 'vu'
            }
        }
        finally {
            foreach ($n in $sauve.Keys) { [Environment]::SetEnvironmentVariable($n, $(if ($null -eq $sauve[$n]) { [NullString]::Value } else { $sauve[$n] })) }
            $Host.UI.RawUI.WindowTitle = $titre
        }
    }
}

Describe 'ctx exec, de bout en bout' {
    BeforeAll {
        $script:Projet = Join-Path $TestDrive 'acme' 'site'
        New-Item -ItemType Directory -Path $script:Projet -Force | Out-Null
        $script:Racine = (Resolve-Path (Join-Path $TestDrive 'acme')).Path
        $script:Ailleurs = Join-Path $TestDrive 'sans-contexte'
        New-Item -ItemType Directory -Path $script:Ailleurs -Force | Out-Null
        $script:Pwsh = (Get-Process -Id $PID).Path
        $script:Sortie = Join-Path $TestDrive 'sortie.txt'

        # Un contexte 'acme' possede $Racine ; le coffre y rend un jeton gh.
        $script:Monde = @{ Racine = $script:Racine; Projet = $script:Projet; Ailleurs = $script:Ailleurs; Pwsh = $script:Pwsh; Sortie = $script:Sortie }
    }

    BeforeEach {
        $script:Derog = $env:DEVCTX_ALLOW_PROD
        $script:Actif = $env:DEVCTX
        $script:RacineSession = $env:DEVCTX_ROOT
        $env:DEVCTX_ALLOW_PROD = '1'
        $env:DEVCTX = 'autre-contexte'
        $env:DEVCTX_TEST_PARENT_SEUL = 'fuite'
        Remove-Item -LiteralPath $script:Sortie -ErrorAction SilentlyContinue
    }
    AfterEach {
        # Restaurer, jamais retirer : AGENTS.md, « Clearing a real env var in a test ».
        $env:DEVCTX_ALLOW_PROD = $script:Derog
        $env:DEVCTX = $script:Actif
        $env:DEVCTX_ROOT = $script:RacineSession
        Remove-Item Env:DEVCTX_TEST_PARENT_SEUL -ErrorAction SilentlyContinue
    }

    It 'l enfant tourne sous le contexte du DOSSIER, sans derogation ni variable du parent' {
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; label = 'ACME'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { if ($Key -eq 'github-token') { 'jeton-acme' } }
            Push-Location $Projet
            try {
                Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command "Set-Content -LiteralPath '$Sortie' -Value `"DEVCTX=`$env:DEVCTX|ALLOW=`$(Test-Path Env:DEVCTX_ALLOW_PROD)|PARENT=`$(Test-Path Env:DEVCTX_TEST_PARENT_SEUL)|GH=`$env:GH_TOKEN`""
            }
            finally { Pop-Location }
        }
        Get-Content -LiteralPath $script:Sortie | Should -Be 'DEVCTX=acme|ALLOW=False|PARENT=False|GH=jeton-acme'
    }

    It 'l enfant recoit la racine qui a DECIDE, pas le DEVCTX_ROOT de la session' {
        # Sinon, une session qui change DEVCTX_ROOT apres l'import rend le
        # garde-fou de l'enfant aveugle : mesure par l'audit, un leurre
        # `db reset` sur un projet prod est passe.
        $env:DEVCTX_ROOT = 'C:\racine-de-la-session-qui-ne-decide-pas'
        $decideuse = InModuleScope DevContext { $script:CtxRoot }
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command "Set-Content -LiteralPath '$Sortie' -Value `$env:DEVCTX_ROOT" }
            finally { Pop-Location }
        }
        Get-Content -LiteralPath $script:Sortie | Should -Be $decideuse
    }

    It 'rend le code de sortie de l enfant, inchange' {
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command 'exit 7' }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 7
        }
    }

    It 'un script qui leve rend 1, pas 0' {
        # Une erreur TERMINANTE fait sortir le lanceur en 1 de lui-meme.
        $script = Join-Path $script:Projet 'echoue.ps1'
        Set-Content -LiteralPath $script -Value 'Get-Item -LiteralPath "Z:\nexiste\pas\du\tout" -ErrorAction Stop'
        InModuleScope DevContext -Parameters ($script:Monde + @{ Script = $script }) {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec $Script }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'un cmdlet en echec rend 1, pas 0' {
        # LE cas qui exige la traduction de lancer-commande.ps1 : un cmdlet ne
        # pose aucun code de sortie, et sans elle un orchestrateur lisait un
        # succes. Le cas du script qui leve, seul, restait vert sans cette
        # traduction -- constate en retirant la ligne, le 27 septembre 2026.
        #
        # Un SCRIPT dont les erreurs ne sont pas terminantes rend 0, comme sous
        # `pwsh -File` : c'est la convention de PowerShell, et `ctx exec` rend
        # ce que `pwsh -Command` rendrait, ni plus severe ni plus indulgent.
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec Get-Item -LiteralPath 'Z:\nexiste\pas\du\tout' }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'un script lance ne voit NI les fonctions privees NI les variables de ctx exec' {
        # La premiere version l'executait dans la portee du module : un script
        # du depot lisait $avant -- l'environnement du parent, jetons compris --
        # et pouvait appeler Get-CtxSecret sur n'importe quel contexte.
        $script = Join-Path $script:Projet 'sonde.ps1'
        Set-Content -LiteralPath $script -Value @"
`$prive = [bool](Get-Command Get-CtxSecret -ErrorAction SilentlyContinue)
`$locale = (Test-Path variable:enfant) -or (Test-Path variable:variables) -or (Test-Path variable:avant)
Set-Content -LiteralPath '$($script:Sortie)' -Value "PRIVE=`$prive|LOCALE=`$locale"
"@
        InModuleScope DevContext -Parameters ($script:Monde + @{ Script = $script }) {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec $Script }
            finally { Pop-Location }
        }
        Get-Content -LiteralPath $script:Sortie | Should -Be 'PRIVE=False|LOCALE=False'
    }

    It 'ne touche JAMAIS l environnement du processus, pas meme pendant l execution' {
        # Le defaut de la premiere version, mesure par l'audit : l'environnement
        # d'un processus est PARTAGE par tous ses runspaces. L'echanger le temps
        # d'une commande le montrait -- derogation retiree, jeton du contexte
        # pose -- a tout autre thread, et deux `ctx exec` en parallele se
        # passaient l'environnement l'un de l'autre. Un second runspace observe
        # ici ce que voit le processus pendant que l'enfant dort.
        $observateur = [powershell]::Create()
        [void]$observateur.AddScript({
                $vus = [System.Collections.Generic.List[string]]::new()
                $fin = [datetime]::UtcNow.AddSeconds(2.5)
                while ([datetime]::UtcNow -lt $fin) {
                    $vus.Add("$([Environment]::GetEnvironmentVariable('DEVCTX_ALLOW_PROD'))|$([Environment]::GetEnvironmentVariable('DEVCTX'))")
                    Start-Sleep -Milliseconds 50
                }
                , $vus
            })
        $attente = $observateur.BeginInvoke()
        try {
            InModuleScope DevContext -Parameters $script:Monde {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { 'jeton' }
                Push-Location $Projet
                try { Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command 'Start-Sleep -Milliseconds 1500' }
                finally { Pop-Location }
            }
            $vus = @($observateur.EndInvoke($attente) | ForEach-Object { $_ })
        }
        finally { $observateur.Dispose() }
        $vus.Count | Should -BeGreaterThan 10
        ($vus | Sort-Object -Unique) | Should -Be '1|autre-contexte'
    }

    It 'le parent retrouve son environnement apres l execution' {
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command 'exit 0' }
            finally { Pop-Location }
        }
        $env:DEVCTX_ALLOW_PROD | Should -Be '1'
        $env:DEVCTX | Should -Be 'autre-contexte'
        $env:DEVCTX_TEST_PARENT_SEUL | Should -Be 'fuite'
    }

    It 'REFUSE un dossier qu aucun contexte ne possede, sans lancer la commande' {
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Push-Location $Ailleurs
            try { Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command "Set-Content -LiteralPath '$Sortie' x" }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 125
        }
        Test-Path -LiteralPath $script:Sortie | Should -BeFalse
    }

    It 'ne suit PAS $env:DEVCTX : le dossier decide, meme si la session dit autre chose' {
        # La session annonce 'autre-contexte' (BeforeEach) ; le dossier n'appartient
        # a personne. Suivre la variable aurait lance la commande.
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'autre-contexte'; email = 'a@b.test'; root = 'Z:\nulle-part' } }
            Push-Location $Ailleurs
            try { Invoke-DevCtx exec $Pwsh -NoProfile -NonInteractive -Command 'exit 0' }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 125
        }
    }

    It 'sans commande, refuse avec le meme code et n execute rien' {
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Push-Location $Projet
            try { Invoke-DevCtx exec }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 125
        }
    }

    It 'une commande introuvable dans l environnement du contexte rend 127' -ForEach @(
        @{ Commande = 'commande-qui-n-existe-nulle-part-4f2a' }
        # Get-Command accepte les jokers : sans echappement, 'Get-Dat*' etait
        # « trouvee », puis `&` echouait, et le code rendu etait 0.
        @{ Commande = 'Get-Dat*' }
    ) {
        InModuleScope DevContext -Parameters ($script:Monde + @{ Commande = $Commande }) {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { }
            Push-Location $Projet
            try { Invoke-DevCtx exec $Commande }
            finally { Pop-Location }
            $LASTEXITCODE | Should -Be 127
        }
    }

    Context 'les arguments arrivent tels qu ils ont ete tapes' {
        # Mesure par la contre-expertise du 27 septembre 2026 : passes derriere
        # `pwsh -File`, les arguments etaient relus par l'analyseur de
        # parametres de pwsh. '--title=fix(exec): x' arrivait en deux morceaux,
        # '--output=C:\x' devenait '--output=C' puis '\x'. La commande envoyee a
        # GitHub ou a Supabase n'etait plus celle qu'on avait tapee.

        It 'un programme natif recoit chaque argument a l identique' {
            # GetCommandLineArgs rend l'argv que le processus a RECU, avant toute
            # relecture par pwsh : c'est ce que verrait gh.exe ou supabase.exe.
            $sonde = Join-Path $script:Projet 'argv.ps1'
            Set-Content -LiteralPath $sonde -Value "[Environment]::GetCommandLineArgs() | Select-Object -Skip 4 | Set-Content -LiteralPath '$($script:Sortie)'"
            InModuleScope DevContext -Parameters ($script:Monde + @{ Sonde = $sonde }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec $Pwsh -NoProfile -File $Sonde '--title=fix(exec): x' '--output=C:\x' '-x:$false' 'a b' "l'apostrophe" }
                finally { Pop-Location }
            }
            @(Get-Content -LiteralPath $script:Sortie) | Should -Be @('--title=fix(exec): x', '--output=C:\x', '-x:$false', 'a b', "l'apostrophe")
        }

        It 'un script sans parametres recoit chaque argument a l identique dans $args' {
            # C'est la forme des shims gh.ps1, supabase.ps1, vercel.ps1 : ce que
            # leur $args recoit est ce qu'ils transmettent au vrai binaire.
            $sonde = Join-Path $script:Projet 'args.ps1'
            Set-Content -LiteralPath $sonde -Value "`$args | Set-Content -LiteralPath '$($script:Sortie)'"
            InModuleScope DevContext -Parameters ($script:Monde + @{ Sonde = $sonde }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec $Sonde '-x:y' '--db-url=postgresql://u:p@h:5432/d' '-R' 'owner/repo' }
                finally { Pop-Location }
            }
            @(Get-Content -LiteralPath $script:Sortie) | Should -Be @('-x:y', '--db-url=postgresql://u:p@h:5432/d', '-R', 'owner/repo')
        }

        It 'un cmdlet recoit ses parametres nommes, et chaque valeur comme du TEXTE' {
            # Le cas qui interdit de tout passer en chaines brutes : '-LiteralPath'
            # doit rester un NOM de parametre. Et le cas qui interdit d'evaluer :
            # une valeur qui ressemble a du code doit arriver comme du texte,
            # apostrophes typographiques comprises -- PowerShell les traite comme
            # des delimiteurs de chaine.
            $piege = "'; Set-Content -LiteralPath '$($script:Sortie).injecte' x; '"
            InModuleScope DevContext -Parameters ($script:Monde + @{ Piege = $piege }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec Set-Content -LiteralPath $Sortie -Value "--title=fix(exec): x $Piege ‘typo’" }
                finally { Pop-Location }
                $LASTEXITCODE | Should -Be 0
            }
            Get-Content -LiteralPath $script:Sortie | Should -Be "--title=fix(exec): x $piege ‘typo’"
            Test-Path -LiteralPath "$($script:Sortie).injecte" | Should -BeFalse
        }

        It 'un argument en forme de date arrive tel quel, sans etre relu comme une date' {
            # Troisieme audit, 29 octobre 2026 : ConvertFrom-Json convertit par
            # defaut une chaine ISO 8601 ou /Date(...)/ en DateTime, que [string]
            # reimprimait dans la culture courante. '2026-01-01T00:00:00'
            # arrivait en '01/01/2026 00:00:00', et le fuseau 'Z' disparaissait.
            $sonde = Join-Path $script:Projet 'argv-dates.ps1'
            Set-Content -LiteralPath $sonde -Value "[Environment]::GetCommandLineArgs() | Select-Object -Skip 4 | Set-Content -LiteralPath '$($script:Sortie)'"
            InModuleScope DevContext -Parameters ($script:Monde + @{ Sonde = $sonde }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec $Pwsh -NoProfile -File $Sonde '--since' '2026-01-01T00:00:00' '2026-10-29T12:34:56Z' '/Date(0)/' }
                finally { Pop-Location }
            }
            @(Get-Content -LiteralPath $script:Sortie) | Should -Be @('--since', '2026-01-01T00:00:00', '2026-10-29T12:34:56Z', '/Date(0)/')
        }

        It 'un nom de variable passe en argument ne fausse pas le code de sortie (<Nom>)' -ForEach @(
            # Troisieme audit : -ErrorVariable __etat remplacait la variable de
            # statut du bloc genere, et une cmdlet en echec rendait 0.
            @{ Nom = '__etat' }
            @{ Nom = '__cible' }
            @{ Nom = 'etat' }
        ) {
            InModuleScope DevContext -Parameters ($script:Monde + @{ Nom = $Nom }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec Get-Item -LiteralPath 'Z:\nexiste\pas\du\tout' -ErrorVariable $Nom 2>$null }
                finally { Pop-Location }
                $LASTEXITCODE | Should -Be 1
            }
        }

        It 'le bloc dynamicparam d un script ne s execute qu une fois, comme tape a la main' {
            # Lire .Parameters d'un script EVALUE ses parametres dynamiques : le
            # lanceur le faisait pour choisir sa route, avant de lancer le
            # script. Un effet de bord y avait donc lieu deux fois.
            $compteur = Join-Path $TestDrive 'dynamicparam.txt'
            Remove-Item -LiteralPath $compteur -ErrorAction SilentlyContinue
            $sonde = Join-Path $script:Projet 'dyn.ps1'
            Set-Content -LiteralPath $sonde -Value @"
[CmdletBinding()]
param([string]`$Nom)
dynamicparam { Add-Content -LiteralPath '$compteur' -Value 'passe'; `$null }
end { }
"@
            InModuleScope DevContext -Parameters ($script:Monde + @{ Sonde = $sonde }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec $Sonde -Nom 'x' }
                finally { Pop-Location }
                $LASTEXITCODE | Should -Be 0
            }
            @(Get-Content -LiteralPath $compteur).Count | Should -Be 1
        }

        It 'le vecteur d arguments ne descend pas jusqu a la commande' {
            $sonde = Join-Path $script:Projet 'canal.ps1'
            Set-Content -LiteralPath $sonde -Value "Set-Content -LiteralPath '$($script:Sortie)' -Value ([bool](Get-ChildItem Env: | Where-Object Name -like 'DEVCTX_EXEC*'))"
            InModuleScope DevContext -Parameters ($script:Monde + @{ Sonde = $sonde }) {
                Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
                Mock Get-CtxSecret { }
                Push-Location $Projet
                try { Invoke-DevCtx exec $Sonde 'secret-dans-un-argument' }
                finally { Pop-Location }
            }
            Get-Content -LiteralPath $script:Sortie | Should -Be 'False'
        }
    }

    It 'un echec avant le lancement ne laisse pas un code de sortie perime' {
        $global:LASTEXITCODE = 42
        InModuleScope DevContext -Parameters $script:Monde {
            Mock Get-CtxManifests { [pscustomobject]@{ name = 'acme'; email = 'dev@acme.test'; root = $Racine } }
            Mock Get-CtxSecret { throw 'coffre indisponible' }
            Push-Location $Projet
            try { { Invoke-DevCtx exec $Pwsh -NoProfile -Command 'exit 0' } | Should -Throw }
            finally { Pop-Location }
        }
        $LASTEXITCODE | Should -Be 125
    }

    It 'ctx-exec et ctx exec visent la meme fonction' {
        (Get-Alias ctx-exec -ErrorAction SilentlyContinue).Definition | Should -Be 'Invoke-DevContextExec'
    }
}
