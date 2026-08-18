# Les trois alias transmettent-ils la ligne de commande VERBATIM ?
#
# LE DEFAUT, ET SA CLASSE.
#
# Un `[CmdletBinding()]` transforme une fonction en fonction avancee, et une
# fonction avancee reclame les PARAMETRES COMMUNS de PowerShell. Toute option
# courte qui en prefixe un devient alors ambigue avant meme d'atteindre la CLI :
#
#     gh api -i user
#     -> Le nom de parametre 'i' est ambigu : -InformationAction, -InformationVariable
#
# Sont concernes -c, -d, -e, -i, -o, -p, -v, -w. Autant d'options que ces trois
# CLI utilisent reellement : `gh api -i`, `supabase -o env`, `vercel -d`.
#
# shims/supabase.ps1 documente ce piege en tete depuis le premier jour -- « no
# param() block on purpose » -- mais la lecon n'avait ete tiree que pour les
# SCRIPTS. Les fonctions du module portaient le meme defaut, et il n'est apparu
# que le 16 aout 2026, quand l'alias `gh` a fait passer le diagnostic du module
# par son propre wrapper.
#
# Ces tests valent donc pour les trois, et pas seulement pour celui qui a casse :
# reparer une classe de defaut sur la seule occurrence rencontree, c'est la
# laisser vivre chez son jumeau. Le depot a deja paye cette lecon quatre fois.

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path

    $script:decoy = Join-Path $TestDrive 'binalias'
    New-Item -ItemType Directory -Path $script:decoy -Force | Out-Null

    foreach ($outil in 'gh', 'supabase', 'vercel') {
        @"
@echo off
echo ARGS=[%*]
exit /b 0
"@ | Set-Content (Join-Path $script:decoy "$outil.cmd") -Encoding ascii
    }

    # Une racine de contexte VIDE : aucun contexte ne possede le dossier
    # courant, donc aucun garde-fou n'a d'avis. Ce qui est mesure ici est le
    # passage des arguments, rien d'autre.
    $script:ctxRoot = Join-Path $TestDrive 'CTXVIDE'
    New-Item -ItemType Directory -Path $script:ctxRoot -Force | Out-Null

    $script:Appel = {
        param($Module, $CtxRoot, $Decoy, $Ligne)
        $code = @"
`$env:DEVCTX_ROOT = '$CtxRoot'
Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
Remove-Item Env:DEVCTX_VERCEL_CONFIG -ErrorAction SilentlyContinue
`$env:PATH = '$Decoy;' + `$env:PATH
Import-Module '$Module' -Force
Set-Location '$CtxRoot'
$Ligne
exit `$LASTEXITCODE
"@
        $out = pwsh -NoProfile -Command $code 2>&1
        ($out -join "`n")
    }
}

Describe 'les alias ne mangent pas les options courtes' {
    It 'gh transmet -i, qui prefixe -InformationAction' {
        # LE cas mesure. Le diagnostic du module appelle `gh api -i user` pour
        # lire les portees OAuth ; l'alias le faisait echouer sur la liaison de
        # parametre, donc `ctx doctor -Live` etait casse par son propre module.
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'gh api -i user'
        $sortie | Should -Match 'ARGS='
        $sortie | Should -Match '\-i'
        $sortie | Should -Not -Match 'ambigu|ambiguous'
    }

    It 'supabase transmet -o, qui prefixe -OutVariable et -OutBuffer' {
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'supabase -o env status'
        $sortie | Should -Match '\-o'
        $sortie | Should -Match 'env'
        $sortie | Should -Not -Match 'ambigu|ambiguous'
    }

    It 'vercel transmet -d, qui prefixe -Debug' {
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'vercel -d ls'
        $sortie | Should -Match '\-d'
        $sortie | Should -Not -Match 'ambigu|ambiguous'
    }

    It 'gh transmet -v et -e, qui prefixent -Verbose et -ErrorAction' {
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'gh truc -v -e'
        $sortie | Should -Match '\-v'
        $sortie | Should -Match '\-e'
        $sortie | Should -Not -Match 'ambigu|ambiguous'
    }

    It 'gh garde une liste a virgules en UN seul argument' {
        # LE SECOND DEFAUT DE L'ALIAS, mesure sur la commande qui ouvrait la PR
        # de cette version. PowerShell analyse les arguments d'une FONCTION
        # autrement que ceux d'un programme externe : `--json a,b,c` y devient un
        # TABLEAU de trois elements. Splatte tel quel, gh recevait
        # `--json databaseId status conclusion` et repondait
        # « unknown command "status" ».
        #
        # Les listes a virgules sont partout dans ces CLI : --json, --label,
        # --assignee. Un wrapper qui les casse est un wrapper qu'on retire.
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'gh run list --json databaseId,status,conclusion'
        $sortie | Should -Match 'databaseId,status,conclusion'
        $sortie | Should -Not -Match 'databaseId status conclusion'
    }

    It 'supabase et vercel gardent aussi leurs listes a virgules' {
        # La correction vit dans UNE fonction partagee. Ces deux cas existent
        # pour qu'elle ne puisse pas etre retiree d'un seul appelant sans que
        # quelque chose rougisse.
        $sb = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'supabase gen types --schema public,auth'
        $sb | Should -Match 'public,auth'

        $vc = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'vercel ls --meta a,b'
        $vc | Should -Match 'a,b'
    }

    It 'aucun des quatre wrappers ne declare de bloc param' {
        # La cause, verifiee sur l'AST plutot que sur son symptome. Un bloc
        # param() qui reviendrait un jour rougirait ici, avec la raison ecrite
        # a cote, plutot que de casser une option courte six mois plus tard.
        #
        # Invoke-DevCtx a rejoint la liste en 1.5.0 : il transmet les switches
        # des sous-commandes (`ctx doctor -Live`), donc il porte exactement le
        # meme risque que les trois autres.
        $racine = Split-Path $PSScriptRoot -Parent
        $fichiers = @(
            (Join-Path $racine 'DevContext.psm1')
            (Join-Path $racine 'src' 'Gh.ps1')
            (Join-Path $racine 'src' 'Ctx.ps1')
        )
        $attendus = @('Invoke-DevGh', 'Invoke-DevSupabase', 'Invoke-DevVercel', 'Invoke-DevCtx')
        $vus = @()
        foreach ($f in $fichiers) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
            $fonctions = $ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $n.Name -in $attendus
                }, $true)
            foreach ($fn in $fonctions) {
                $vus += $fn.Name
                $fn.Body.ParamBlock | Should -BeNullOrEmpty -Because "$($fn.Name) doit recevoir ses arguments par `$args"
            }
        }

        # Sans ceci, renommer ou deplacer un wrapper rendrait le test vert en
        # n'inspectant plus rien -- la panne la plus couteuse d'une suite.
        foreach ($nom in $attendus) {
            $vus | Should -Contain $nom -Because 'chaque wrapper doit avoir ete reellement inspecte'
        }
    }
}

Describe 'les alias transmettent UN argument unique sans le disloquer' {
    # LE TROISIEME DEFAUT DE L'ALIAS, mesure le 18 aout 2026 depuis un projet
    # perso :
    #
    #     vercel whoami   -> Error: "w" is not a valid target directory
    #     gh --version    -> unknown command "v" for "gh"
    #     supabase --version -> Unknown subcommand "-" for "supabase"
    #
    # Les shims, eux, repondaient correctement : le defaut vit dans l'alias.
    #
    # CAUSE. Get-CtxArgumentsBruts se termine par @(...), mais une fonction
    # PowerShell DEROULE sa sortie -- un tableau d'UN element revient au
    # collecteur en SCALAIRE. `& $exe @arguments` splatte alors une CHAINE, et
    # splatter une chaine enumere ses CARACTERES. `whoami` partait en
    # `w h o a m i`.
    #
    # Meme mecanique que le tableau VIDE deja consigne dans AGENTS.md, une case
    # plus loin sur la meme regle : envelopper au SITE D'APPEL, jamais dans la
    # fonction.
    #
    # POURQUOI PERSONNE NE L'A VU. Tous les tests de ce fichier passaient deux
    # arguments ou plus, donc aucun ne construisait le cas qui casse -- et c'est
    # la forme la plus ordinaire qui soit : `gh --version`, `vercel whoami`,
    # `supabase login`. Le depot connait deja cette faute sous le nom
    # « n'avoir jamais construit que le cas peuple ».

    It 'gh --version arrive entier' {
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'gh --version'
        $sortie | Should -Match 'ARGS='
        $sortie | Should -Match '--version'
    }

    It 'vercel whoami arrive entier' {
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'vercel whoami'
        $sortie | Should -Match 'ARGS='
        $sortie | Should -Match 'whoami'
    }

    It 'supabase --version arrive entier' {
        $sortie = & $script:Appel $script:Module $script:ctxRoot $script:decoy 'supabase --version'
        $sortie | Should -Match 'ARGS='
        $sortie | Should -Match '--version'
    }

    It 'les trois appelants enveloppent Get-CtxArgumentsBruts au site d appel' {
        # La cause, lue dans le source plutot que dans son symptome -- meme
        # demarche que le test du bloc param() plus haut. Une affectation nue
        # rougit ici, avec la raison ecrite a cote, plutot que de casser une
        # commande a un argument six mois plus tard.
        $racine = Split-Path $PSScriptRoot -Parent
        $fichiers = @(
            (Join-Path $racine 'DevContext.psm1')
            (Join-Path $racine 'src' 'Gh.ps1')
        )
        $nus = @()
        foreach ($f in $fichiers) {
            $texte = Get-Content -LiteralPath $f -Raw
            foreach ($m in [regex]::Matches($texte, '(?m)^[^\r\n]*=\s*Get-CtxArgumentsBruts[^\r\n]*$')) {
                if ($m.Value -notmatch '@\(\s*Get-CtxArgumentsBruts') {
                    $nus += ('{0} : {1}' -f (Split-Path $f -Leaf), $m.Value.Trim())
                }
            }
        }
        $nus | Should -BeNullOrEmpty -Because 'une fonction ne peut pas RENDRE un tableau : elle le deroule. Envelopper au site d appel, @(Get-CtxArgumentsBruts $args), sinon un argument unique repart en caracteres.'
    }
}
