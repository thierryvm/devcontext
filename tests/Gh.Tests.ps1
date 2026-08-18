# Tests du garde-fou d'identite `gh`.
#
# La moitie interessante -- « cette commande ecrit-elle ? », « faut-il rediriger,
# refuser, ou se taire ? » -- est pure et se verifie sans machine, sans reseau et
# sans compte GitHub. Le reste est exerce de bout en bout contre un LEURRE : un
# garde-fou teste contre le vrai binaire, c'est parier un depot sur le fait qu'il
# marche.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Test-CtxGhEcriture' {
    It 'reconnait <Ligne> comme ecriture : <Attendu>' -ForEach @(
        @{ Ligne = 'pr create';                Attendu = $true }
        @{ Ligne = 'issue create --title x';   Attendu = $true }
        @{ Ligne = 'repo delete x/y';          Attendu = $true }
        @{ Ligne = 'pr merge 12';              Attendu = $true }
        @{ Ligne = 'secret set CLE';           Attendu = $true }
        @{ Ligne = 'release upload v1 f.zip';  Attendu = $true }
        @{ Ligne = 'auth login';               Attendu = $true }
        @{ Ligne = 'workflow run ci.yml';      Attendu = $true }
        @{ Ligne = 'extension install truc';   Attendu = $true }
        @{ Ligne = 'pr list';                  Attendu = $false }
        @{ Ligne = 'issue view 3';             Attendu = $false }
        @{ Ligne = 'repo clone owner/depot';   Attendu = $false }
        @{ Ligne = 'auth status';              Attendu = $false }
        @{ Ligne = 'pr checkout 12';           Attendu = $false }
        @{ Ligne = 'release download v1';      Attendu = $false }
    ) {
        Test-CtxGhEcriture -Arguments ($Ligne -split ' ') | Should -Be $Attendu
    }

    It 'coupe les verbes composes sur le tiret' {
        # `gh project item-add`, `field-create`, `item-edit`. C'est ce qui fait
        # qu'un nom ajoute par GitHub demain est couvert sans toucher au code :
        # les verbes, eux, se repetent d'un nom a l'autre.
        Test-CtxGhEcriture -Arguments @('project', 'item-add', '5')     | Should -BeTrue
        Test-CtxGhEcriture -Arguments @('project', 'field-create')      | Should -BeTrue
        Test-CtxGhEcriture -Arguments @('project', 'item-list')         | Should -BeFalse
    }

    It 'distingue repo clone de label clone' {
        # Le meme verbe porte les deux sens : `gh repo clone` lit, `gh label
        # clone` COPIE des libelles vers un autre depot. Un verbe ne peut pas
        # trancher, une paire si -- et cette liste d'exceptions doit rester
        # minuscule, sans quoi la classification par verbe etait le mauvais modele.
        Test-CtxGhEcriture -Arguments @('repo', 'clone', 'o/d')  | Should -BeFalse
        Test-CtxGhEcriture -Arguments @('label', 'clone', 'o/d') | Should -BeTrue
    }

    It 'juge gh api sur sa methode, pas sur son nom' {
        Test-CtxGhEcriture -Arguments @('api', 'repos/o/d')                      | Should -BeFalse
        Test-CtxGhEcriture -Arguments @('api', 'repos/o/d', '--method', 'GET')   | Should -BeFalse
        Test-CtxGhEcriture -Arguments @('api', 'repos/o/d', '--method', 'PATCH') | Should -BeTrue
        Test-CtxGhEcriture -Arguments @('api', '-X', 'DELETE', 'repos/o/d')      | Should -BeTrue
    }

    It 'voit qu un champ fait basculer gh api en POST' {
        # La CLI passe elle-meme en POST des qu'un champ est fourni, meme sans
        # --method. La regle suit la sienne plutot que la deviner.
        Test-CtxGhEcriture -Arguments @('api', 'repos/o/d/issues', '-f', 'title=x') | Should -BeTrue
        Test-CtxGhEcriture -Arguments @('api', 'x', '--raw-field', 'a=b')           | Should -BeTrue
    }

    It 'ne se laisse pas tromper par la valeur d une option' {
        # Le piege qui a fait ecarter la methode des paires adjacentes retenue
        # pour Supabase : elle ecarte les options mais garde leurs VALEURS, et
        # aurait lu 'create' ci-dessous comme un verbe.
        Test-CtxGhEcriture -Arguments @('issue', 'list', '--label', 'create') | Should -BeFalse
    }

    It 'ne dit rien d une ligne vide' {
        Test-CtxGhEcriture -Arguments @()   | Should -BeFalse
        Test-CtxGhEcriture -Arguments @('--version') | Should -BeFalse
    }
}

Describe 'Test-CtxGhGuard' {
    BeforeAll {
        $script:Attendu = 'C:\CTX\perso\gh'
        $script:Autre   = 'C:\CTX\client\gh'
    }

    It 'n a aucun avis hors de tout contexte' {
        # Un dossier personnel, un depot clone au hasard, une machine ou
        # DevContext vient d etre installe : ce module n a rien a y dire.
        $v = Test-CtxGhGuard -Arguments @('pr', 'create')
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'hors-contexte'
        $v.Redirection | Should -BeNullOrEmpty
    }

    It 'ne fait rien quand la configuration concorde deja' {
        $v = Test-CtxGhGuard -Arguments @('pr', 'create') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigActuel $script:Attendu
        $v.Rule | Should -Be 'concordant'
        $v.Redirection | Should -BeNullOrEmpty
    }

    It 'ignore un antislash final dans la comparaison' {
        $v = Test-CtxGhGuard -Arguments @('pr', 'create') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigActuel ($script:Attendu + '\')
        $v.Rule | Should -Be 'concordant'
    }

    It 'REFUSE une ecriture quand la variable designe un autre contexte' {
        # L incident fondateur : ouvrir une PR sous le compte d un autre client.
        $v = Test-CtxGhGuard -Arguments @('pr', 'create') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigActuel $script:Autre
        $v.Allowed  | Should -BeFalse
        $v.Rule     | Should -Be 'contexte-autre'
        $v.Contexte | Should -Be 'perso'
    }

    It 'laisse passer une LECTURE sous un autre contexte, mais la signale' {
        # Refuser une lecture couterait plus qu elle ne protege : un utilisateur
        # bloque appelle le binaire brut, donc sans aucun garde-fou. Mais rien ne
        # passe en silence sur un desaccord d identite.
        $v = Test-CtxGhGuard -Arguments @('pr', 'list') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigActuel $script:Autre
        $v.Allowed       | Should -BeTrue
        $v.Avertissement | Should -Not -BeNullOrEmpty
    }

    It 'ne remplace JAMAIS une variable posee volontairement' {
        # Meme sur un desaccord : un outil qui ecrase un choix explicite devient
        # imprevisible. Il juge, il ne decide pas a la place.
        $v = Test-CtxGhGuard -Arguments @('pr', 'list') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigActuel $script:Autre
        $v.Redirection | Should -BeNullOrEmpty
    }

    It 'redirige en silence quand le contexte a deja son compte' {
        $v = Test-CtxGhGuard -Arguments @('pr', 'create') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigExiste
        $v.Allowed       | Should -BeTrue
        $v.Rule          | Should -Be 'redirige'
        $v.Redirection   | Should -Be $script:Attendu
        $v.Avertissement | Should -BeNullOrEmpty
    }

    It 'redirige gh auth AVANT meme qu une configuration existe, et le dit' {
        # C est la sortie du cas suivant : `gh auth login` tape n importe ou dans
        # le contexte doit connecter CE contexte. Sans cela, le correctif propose
        # par le refus ne fonctionnerait pas depuis git-bash.
        $v = Test-CtxGhGuard -Arguments @('auth', 'login') -Contexte 'perso' -ConfigAttendu $script:Attendu
        $v.Allowed       | Should -BeTrue
        $v.Rule          | Should -Be 'auth-redirige'
        $v.Redirection   | Should -Be $script:Attendu
        $v.Avertissement | Should -Not -BeNullOrEmpty
    }

    It 'REFUSE une ecriture quand le contexte n a pas encore de compte gh' {
        $v = Test-CtxGhGuard -Arguments @('pr', 'create') -Contexte 'perso' -ConfigAttendu $script:Attendu
        $v.Allowed | Should -BeFalse
        $v.Rule    | Should -Be 'sans-config'
    }

    It 'laisse passer une lecture sous le compte global, SANS crier' {
        # L avertissement se declencherait a chaque commande tant que le contexte
        # n a pas de compte gh. Un outil qui crie en continu est ignore le jour
        # ou il a raison ; `ctx doctor` porte deja ce constat, une fois.
        $v = Test-CtxGhGuard -Arguments @('pr', 'list') -Contexte 'perso' -ConfigAttendu $script:Attendu
        $v.Allowed       | Should -BeTrue
        $v.Rule          | Should -Be 'lecture-globale'
        $v.Avertissement | Should -BeNullOrEmpty
    }

    It 'la derogation explicite passe avant tout' {
        $v = Test-CtxGhGuard -Arguments @('pr', 'create') -Contexte 'perso' `
            -ConfigAttendu $script:Attendu -ConfigActuel $script:Autre -Override
        $v.Allowed | Should -BeTrue
        $v.Rule    | Should -Be 'derogation'
    }
}

Describe 'shim gh — de bout en bout' {
    BeforeAll {
        $script:ctxRoot  = Join-Path $TestDrive 'CTXGH'
        $script:projRoot = Join-Path $TestDrive 'PROJGH'
        $script:ctxDir   = Join-Path $script:ctxRoot 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir -Force | Out-Null

        @{ name = 'demo'; label = 'Demo'; email = 'demo@exemple.com'; root = $script:projRoot } |
            ConvertTo-Json | Set-Content (Join-Path $script:ctxDir 'context.json') -Encoding UTF8

        $script:proj = Join-Path $script:projRoot 'appli'
        New-Item -ItemType Directory -Path $script:proj -Force | Out-Null

        # Hors de toute racine de contexte : le shim ne doit rien y changer.
        $script:dehors = Join-Path $TestDrive 'DEHORS'
        New-Item -ItemType Directory -Path $script:dehors -Force | Out-Null

        # Le leurre annonce sa presence ET ce qu il a recu : c est ainsi qu on
        # verifie une redirection, qui ne laisse aucune autre trace.
        $script:decoy = Join-Path $TestDrive 'bingh'
        New-Item -ItemType Directory -Path $script:decoy -Force | Out-Null
        @"
@echo off
echo LEURRE-APPELE
echo CONFIG=%GH_CONFIG_DIR%
exit /b 42
"@ | Set-Content (Join-Path $script:decoy 'gh.cmd') -Encoding ascii

        $script:Shim = (Resolve-Path (Join-Path $PSScriptRoot '..' 'shims' 'gh.ps1')).Path

        $script:Run = {
            param($ShimPath, $Cwd, $CtxRoot, $Decoy, $CliArgs, $ConfigDir, $Allow)
            # Il faut EFFACER GH_CONFIG_DIR, pas seulement s abstenir de la
            # poser : `pwsh -Command` herite de l environnement du parent, et la
            # suite tourne dans un shell ou `work` l a deja posee. S abstenir
            # laisserait le test mesurer autre chose que ce qu il annonce --
            # exactement le defaut releve sur DEVCTX le 15 aout 2026.
            $poseConfig = if ($ConfigDir) {
                "`$env:GH_CONFIG_DIR = '$ConfigDir'"
            } else {
                'Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue'
            }
            $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
$poseConfig
`$env:DEVCTX_ALLOW_GH = '$Allow'
`$env:PATH = '$Decoy;' + `$env:PATH
Set-Location '$Cwd'
& '$ShimPath' $CliArgs
exit `$LASTEXITCODE
"@
            $out = pwsh -NoProfile -Command $code 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
        }
    }

    It 'REFUSE pr create quand le contexte n a pas de compte gh' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'pr create' '' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'nomme la marche a suivre dans le refus' {
        # Un refus sans sortie est une impasse, et une impasse se contourne en
        # appelant le binaire brut -- donc sans garde-fou.
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'pr create' '' ''
        $r.Output | Should -Match 'work demo'
        $r.Output | Should -Match 'gh auth login'
    }

    It 'laisse passer une lecture sans rien rediriger' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'pr list' '' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Match 'CONFIG=\s*$|CONFIG=%GH_CONFIG_DIR%'
        $r.Code   | Should -Be 42
    }

    It 'redirige vers le contexte des qu il porte un compte' {
        $gh = Join-Path $script:ctxDir 'gh'
        New-Item -ItemType Directory -Path $gh -Force | Out-Null
        Set-Content (Join-Path $gh 'hosts.yml') 'github.com:' -Encoding ascii
        try {
            $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'pr create' '' ''
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Output | Should -Match ([regex]::Escape($gh))
            $r.Code   | Should -Be 42
        }
        finally { Remove-Item $gh -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'redirige gh auth login meme sans compte prealable' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'auth login' '' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Match ([regex]::Escape((Join-Path $script:ctxDir 'gh')))
    }

    It 'REFUSE une ecriture quand la variable designe un autre contexte' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'pr create' 'C:\CTX\ailleurs\gh' ''
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 1
    }

    It 'laisse passer la derogation explicite' {
        $r = & $script:Run $script:Shim $script:proj $script:ctxRoot $script:decoy 'pr create' 'C:\CTX\ailleurs\gh' '1'
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }

    It 'ne touche a rien hors de toute racine de contexte' {
        $r = & $script:Run $script:Shim $script:dehors $script:ctxRoot $script:decoy 'pr create' '' ''
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Output | Should -Not -Match 'REFUSE'
        $r.Code   | Should -Be 42
    }
}

Describe 'alias gh — la couverture que le PATH ne peut pas donner' {
    # POURQUOI CET ALIAS EXISTE.
    #
    # Windows compose le PATH SYSTEME avant le PATH utilisateur, et
    # l'installateur ecrit dans le second -- c'est ce qui lui evite de demander
    # les droits administrateur. Un `gh` installe par winget vit sous Program
    # Files, donc dans le PATH systeme : le shim ne le voit JAMAIS. Mesure sur la
    # machine de l'auteur le 16 aout 2026, index 10 contre index 19.
    #
    # `supabase` echappait au probleme par accident : il vient de npm, donc du
    # PATH utilisateur. Un accident n'est pas une architecture.

    BeforeAll {
        $script:ctxRoot2  = Join-Path $TestDrive 'CTXAL'
        $script:projRoot2 = Join-Path $TestDrive 'PROJAL'
        $script:ctxDir2   = Join-Path $script:ctxRoot2 'demo'
        New-Item -ItemType Directory -Path $script:ctxDir2 -Force | Out-Null

        @{ name = 'demo'; label = 'Demo'; email = 'demo@exemple.com'; root = $script:projRoot2 } |
            ConvertTo-Json | Set-Content (Join-Path $script:ctxDir2 'context.json') -Encoding UTF8

        $script:proj2 = Join-Path $script:projRoot2 'appli'
        New-Item -ItemType Directory -Path $script:proj2 -Force | Out-Null

        $script:decoy2 = Join-Path $TestDrive 'binal'
        New-Item -ItemType Directory -Path $script:decoy2 -Force | Out-Null
        @"
@echo off
echo LEURRE-APPELE
echo CONFIG=%GH_CONFIG_DIR%
exit /b 42
"@ | Set-Content (Join-Path $script:decoy2 'gh.cmd') -Encoding ascii

        $script:Module2 = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path

        $script:ParAlias = {
            param($Module, $Proj, $CtxRoot, $Decoy, $CliArgs)
            $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
Remove-Item Env:DEVCTX_ALLOW_GH -ErrorAction SilentlyContinue
`$env:PATH = '$Decoy;' + `$env:PATH
Import-Module '$Module' -Force
Set-Location '$Proj'
gh $CliArgs
Write-Host ('APRES=[' + `$env:GH_CONFIG_DIR + ']')
exit `$LASTEXITCODE
"@
            $out = pwsh -NoProfile -Command $code 2>&1
            [pscustomobject]@{ Output = ($out -join "`n"); Code = $LASTEXITCODE }
        }
    }

    It 'gh resout bien l alias du module, pas le PATH' {
        $code = "Import-Module '$($script:Module2)' -Force; (Get-Command gh).CommandType"
        (pwsh -NoProfile -Command $code) | Should -Be 'Alias'
    }

    It 'REFUSE une ecriture quand le contexte n a pas de compte gh' {
        $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'pr create'
        $r.Output | Should -Match 'REFUSE'
        $r.Output | Should -Not -Match 'LEURRE-APPELE'
    }

    It 'redirige vers le contexte, puis RESTAURE la session' {
        # L'alias tourne DANS la session de l'utilisateur, contrairement au shim
        # qui est un processus jetable. Y laisser GH_CONFIG_DIR modifiee ferait
        # decider les commandes suivantes par un effet de bord invisible.
        $gh = Join-Path $script:ctxDir2 'gh'
        New-Item -ItemType Directory -Path $gh -Force | Out-Null
        Set-Content (Join-Path $gh 'hosts.yml') 'github.com:' -Encoding ascii
        try {
            $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'pr create'
            $r.Output | Should -Match 'LEURRE-APPELE'
            $r.Output | Should -Match ([regex]::Escape($gh))
            $r.Output | Should -Match 'APRES=\[\]'
        }
        finally { Remove-Item $gh -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'propage le code de sortie du binaire reel' {
        $r = & $script:ParAlias $script:Module2 $script:proj2 $script:ctxRoot2 $script:decoy2 'pr list'
        $r.Output | Should -Match 'LEURRE-APPELE'
        $r.Code   | Should -Be 42
    }
}

Describe 'Resolve-CtxGhLoginObserve' {
    # La regression du 17 aout 2026, en entier et sans reseau.
    #
    # Pendant une panne GitHub de niveau Critical, `ctx` a rendu NO-GO sur un
    # dossier client sain : la CLI avait ecrit le corps d'erreur de l'API sur sa
    # sortie STANDARD, le code de sortie n'etait pas lu, et cette phrase a ete
    # comparee au compte attendu comme si c'etait une identite.

    It 'lit un compte quand la CLI a reussi' {
        InModuleScope DevContext {
            $r = Resolve-CtxGhLoginObserve -Sortie "ovb-willemot`n" -Code 0 -ConfigExiste $true
            $r.Etat  | Should -Be 'connu'
            $r.Login | Should -Be 'ovb-willemot'
        }
    }

    It 'ne prend PAS un corps d erreur de l API pour une identite' {
        InModuleScope DevContext {
            # La chaine exacte affichee par ctx ce jour-la.
            $panne = '{"message": "No server is currently available to service your request. Sorry about that. Please try resubmitting your request and contact us if the problem persists."}'
            $r = Resolve-CtxGhLoginObserve -Sortie $panne -Code 1 -ConfigExiste $true
            $r.Etat  | Should -Be 'nonVerifie'
            $r.Login | Should -BeNullOrEmpty
        }
    }

    It 'refuse une reponse difforme MEME sur un code de sortie nul' {
        InModuleScope DevContext {
            # La garantie ne doit pas dependre de la discipline de sortie d un
            # binaire tiers. Un compte GitHub ne ressemble a aucune de ces
            # chaines, quoi qu en dise le code de retour.
            foreach ($difforme in @(
                    '{"message": "Bad gateway"}'
                    'error connecting to api.github.com'
                    "ovb-willemot`nwarning: a new release of gh is available"
                    '-commence-par-un-tiret'
                    'finit-par-un-tiret-'
                    'a espace'
                    ('x' * 40)
                    '')) {
                $r = Resolve-CtxGhLoginObserve -Sortie $difforme -Code 0 -ConfigExiste $true
                $r.Etat  | Should -Not -Be 'connu' -Because "'$difforme' n est pas un compte GitHub"
                $r.Login | Should -BeNullOrEmpty
            }
        }
    }

    It 'accepte les formes de compte GitHub reellement valides : <_>' -ForEach @(
        'a', 'thierryvm', 'ovb-willemot', 'A1', 'x-y-z', ('a' * 39)
    ) {
        InModuleScope DevContext -Parameters @{ nom = $_ } { param($nom)
            $r = Resolve-CtxGhLoginObserve -Sortie $nom -Code 0 -ConfigExiste $true
            $r.Etat  | Should -Be 'connu'
            $r.Login | Should -Be $nom
        }
    }

    It 'dit « non authentifie » seulement quand l absence est un fait LOCAL' {
        InModuleScope DevContext {
            # hosts.yml absent la ou `gh` regarde : verifiable hors ligne, donc
            # encore vrai pendant une panne.
            $r = Resolve-CtxGhLoginObserve -Sortie '' -Code 1 -ConfigExiste $false
            $r.Etat | Should -Be 'nonAuth'
        }
    }

    It 'penche vers « non verifie » quand l appelant ignore ou regarder' {
        InModuleScope DevContext {
            # $null n est pas $false. Les confondre enverrait quelqu un de
            # parfaitement authentifie refaire un `gh auth login` que la panne
            # ferait echouer, pour reparer ce qui n est pas casse.
            $r = Resolve-CtxGhLoginObserve -Sortie '' -Code 1 -ConfigExiste $null
            $r.Etat | Should -Be 'nonVerifie'
        }
    }

    It 'ne rend jamais un Login hors de l etat connu' {
        InModuleScope DevContext {
            # C est CETTE propriete que `ctx` utilise pour decider s il compare.
            # Un Login non nul hors de 'connu' reproduirait la panne a l identique.
            foreach ($cas in @(
                    @{ S = '{"message":"down"}'; C = 1;  E = $true }
                    @{ S = '{"message":"down"}'; C = 1;  E = $false }
                    @{ S = '{"message":"down"}'; C = 0;  E = $null }
                    @{ S = '';                   C = 1;  E = $false }
                    @{ S = $null;                C = 1;  E = $null })) {
                $r = Resolve-CtxGhLoginObserve -Sortie $cas.S -Code $cas.C -ConfigExiste $cas.E
                $r.Etat  | Should -Not -Be 'connu'
                $r.Login | Should -BeNullOrEmpty
            }
        }
    }
}
