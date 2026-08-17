# `ctx <sous-commande>` -- la forme que tapent les doigts.
#
# Avant la 1.4.1, `ctx doctor` repondait :
#
#     Test-DevContext: A positional parameter cannot be found that accepts
#     argument 'doctor'.
#
# Une erreur de liaison de parametre nommant une fonction interne que
# l'utilisateur n'a jamais tapee. Ces tests fixent les deux garanties qui
# comptent : les deux orthographes existent, et aucune ne peut diverger de
# l'autre, parce que toutes deux descendent de la meme table.

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
    Import-Module $script:Module -Force
}

Describe 'Resolve-CtxSousCommande' {
    It 'reconnait une sous-commande, quelle que soit la casse' -ForEach @(
        @{ Mot = 'doctor'; Attendu = 'Get-DevContextDoctor' }
        @{ Mot = 'DOCTOR'; Attendu = 'Get-DevContextDoctor' }
        @{ Mot = 'List'; Attendu = 'Get-DevContextList' }
        @{ Mot = ' who '; Attendu = 'Resolve-DevContextForPath' }
    ) {
        InModuleScope DevContext -Parameters @{ M = $Mot; A = $Attendu } {
            Resolve-CtxSousCommande -Mot $M | Should -Be $A
        }
    }

    It 'rend $null sur un switch -- sinon `ctx -Quiet` afficherait une aide' {
        # Le test du tiret doit passer AVANT la recherche dans la table. Sans
        # lui, `ctx -Quiet` -- la commande la plus utilisee du module, appelee
        # par Assert-DevContext et par lancer-vscode.ps1 -- chercherait la
        # sous-commande '-quiet', ne la trouverait pas, et rendrait une aide au
        # lieu d'un booleen.
        InModuleScope DevContext {
            Resolve-CtxSousCommande -Mot '-Quiet' | Should -BeNullOrEmpty
            Resolve-CtxSousCommande -Mot '-Live' | Should -BeNullOrEmpty
        }
    }

    It 'rend $null sur vide, blanc et mot inconnu' {
        InModuleScope DevContext {
            Resolve-CtxSousCommande -Mot '' | Should -BeNullOrEmpty
            Resolve-CtxSousCommande -Mot '   ' | Should -BeNullOrEmpty
            Resolve-CtxSousCommande -Mot 'doctr' | Should -BeNullOrEmpty
            Resolve-CtxSousCommande -Mot $null | Should -BeNullOrEmpty
        }
    }
}

Describe 'ctx-<nom> et ctx <nom> ne peuvent pas diverger' {
    It 'chaque entree de la table a son alias ctx-<nom>, vers la MEME fonction' {
        $table = InModuleScope DevContext { Get-CtxSousCommandes }
        $table.Keys.Count | Should -BeGreaterThan 0

        foreach ($cle in $table.Keys) {
            $alias = Get-Alias "ctx-$cle" -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty -Because "ctx-$cle doit exister"
            $alias.Definition | Should -Be $table[$cle] -Because "ctx-$cle et 'ctx $cle' doivent viser la meme fonction"
        }
    }

    It 'chaque fonction visee est reellement exportee par le module' {
        # Un alias vers une fonction non exportee se resout dans le module et
        # echoue chez l'appelant. Le manifeste et le psm1 doivent donc
        # s'accorder, et c'est un piege deja paye dans ce depot.
        $table = InModuleScope DevContext { Get-CtxSousCommandes }
        $exportees = (Get-Module DevContext).ExportedFunctions.Keys
        foreach ($cle in $table.Keys) {
            $exportees | Should -Contain $table[$cle] -Because "'ctx $cle' appelle $($table[$cle])"
        }
    }

    It 'chaque alias ctx-<nom> est reellement EXPORTE par le module' {
        # LE DEFAUT DU 17 AOUT 2026, ecrit apres l'avoir vu. Les alias etaient
        # CREES depuis la table mais EXPORTES depuis une liste recopiee a la
        # main. La premiere sous-commande ajoutee -- `init` -- a donc donne un
        # `ctx-init` cree, jamais exporte, absent chez l'appelant, pendant que
        # `ctx init` fonctionnait. Deux orthographes, une seule qui marche :
        # exactement ce que la table etait censee rendre impossible.
        #
        # Cree n'est pas exporte, et seul l'objet module dit lequel des deux.
        $table = InModuleScope DevContext { Get-CtxSousCommandes }
        $exportes = (Get-Module DevContext).ExportedAliases.Keys
        foreach ($cle in $table.Keys) {
            $exportes | Should -Contain "ctx-$cle" -Because "ctx-$cle doit sortir du module"
        }
    }

    It 'l alias ctx vise le repartiteur, pas Test-DevContext' {
        (Get-Alias ctx).Definition | Should -Be 'Invoke-DevCtx'
    }
}

Describe 'Invoke-DevCtx -- repartition' {
    BeforeAll {
        # Un shell neuf par cas : `ctx` lit des variables d'environnement, et
        # deux cas qui se les partagent finissent par se mentir l'un a l'autre.
        $script:Appel = {
            param($Module, $Ligne)
            $code = @"
Import-Module '$Module' -Force
`$ErrorActionPreference = 'Continue'
$Ligne
"@
            (pwsh -NoProfile -Command $code 2>&1) -join "`n"
        }
    }

    It 'ctx doctor rend des objets de diagnostic, sans erreur de liaison' {
        $s = & $script:Appel $script:Module '(ctx doctor).Count'
        $s | Should -Not -Match 'positional parameter|parametre positionnel'
        $s | Should -Not -Match 'Test-DevContext'
    }

    It 'ctx list ne passe PAS un argument $null a la fonction cible' {
        # LA REGRESSION DU 17 AOUT 2026, ecrite en meme temps que la
        # fonctionnalite. En PowerShell,
        #     $reste = if ($n -gt 1) { ... } else { @() }
        # rend $null et non un tableau vide : la branche vide est ENUMEREE par
        # le pipeline et ne produit aucun objet. Splatte, cela passait un
        # argument positionnel $null, et `ctx list` -- une commande sans aucun
        # parametre positionnel -- echouait dessus.
        #
        # Sans le @() explicite de src/Ctx.ps1, ce test rougit.
        $s = & $script:Appel $script:Module 'ctx list'
        $s | Should -Not -Match 'positional parameter|parametre positionnel'
        $s | Should -Not -Match '\$null'
    }

    It 'ctx who ne passe pas non plus de chaine vide' {
        $s = & $script:Appel $script:Module 'ctx who'
        $s | Should -Not -Match 'empty string|chaine vide'
    }

    It 'ctx doctor -Live transmet le switch a la sous-commande' {
        # Le cas qui aurait casse si `ctx` avait ete une fonction AVANCEE : une
        # fonction avancee rejette un parametre nomme qu'elle ne declare pas, et
        # ValueFromRemainingArguments ne ramasse que le POSITIONNEL. La
        # sous-commande aurait marche, et chacun de ses switches aurait casse.
        $s = & $script:Appel $script:Module '@(ctx doctor -Live | Where-Object { $_.Sujet -eq ''jeton'' }).Count'
        $s | Should -Not -Match "cannot be found that matches parameter name 'Live'"
    }

    It 'ctx sans argument reste le verdict, et -Quiet reste un booleen' {
        $s = & $script:Appel $script:Module '(ctx -Quiet).GetType().Name'
        $s | Should -Match 'Boolean'
    }

    It 'un mot inconnu affiche l aide, et nomme le mot fautif' {
        $s = & $script:Appel $script:Module 'ctx doctr'
        $s | Should -Match 'doctr'
        $s | Should -Match 'ctx doctor'
        # Surtout PAS le nom d'une fonction interne : c'est tout l'objet du correctif.
        $s | Should -Not -Match 'Test-DevContext'
    }

    It 'ctx help affiche l aide sans signaler d erreur' {
        $s = & $script:Appel $script:Module 'ctx help'
        $s | Should -Match 'ctx doctor'
        $s | Should -Not -Match 'inconnue|Unknown subcommand'
    }

    It 'l aide liste TOUTES les sous-commandes, pas une liste recopiee' {
        # L'aide lit la table. Si elle etait recopiee a la main, la premiere
        # sous-commande ajoutee serait absente de l'ecran d'aide, en silence.
        $table = InModuleScope DevContext { Get-CtxSousCommandes }
        $s = & $script:Appel $script:Module 'ctx help'
        foreach ($cle in $table.Keys) {
            $s | Should -Match "ctx $cle" -Because "l aide doit mentionner 'ctx $cle'"
        }
    }
}
