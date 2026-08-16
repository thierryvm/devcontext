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

    It 'aucun des trois ne declare de bloc param' {
        # La cause, verifiee sur l'AST plutot que sur son symptome. Un bloc
        # param() qui reviendrait un jour rougirait ici, avec la raison ecrite
        # a cote, plutot que de casser une option courte six mois plus tard.
        $racine = Split-Path $PSScriptRoot -Parent
        $fichiers = @(
            (Join-Path $racine 'DevContext.psm1')
            (Join-Path $racine 'src' 'Gh.ps1')
        )
        foreach ($f in $fichiers) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
            $fonctions = $ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $n.Name -in @('Invoke-DevGh', 'Invoke-DevSupabase', 'Invoke-DevVercel')
                }, $true)
            foreach ($fn in $fonctions) {
                $fn.Body.ParamBlock | Should -BeNullOrEmpty -Because "$($fn.Name) doit recevoir ses arguments par `$args"
            }
        }
    }
}
