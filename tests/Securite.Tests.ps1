# Tests de securite du depot lui-meme.
#
# Un module dont le metier est de manipuler des jetons n'a pas le droit d'en
# laisser fuir un. Ces tests ne verifient pas une fonction : ils verifient une
# PROPRIETE du depot, et ils echouent le jour ou quelqu'un colle une valeur
# reelle « juste pour essayer » — le geste par lequel arrivent la plupart des
# fuites.
#
# Le test de bout en bout, plus bas, est le plus severe : il fait produire au
# module son diagnostic complet AVEC les vrais jetons de la machine, puis exige
# que pas un caractere de ces jetons n'apparaisse dans la sortie.

BeforeAll {
    $script:Racine = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force

    # Uniquement les fichiers SUIVIS par git : ce qui n'est pas suivi ne partira
    # pas dans un clone, et un .env local legitime ferait echouer le test a tort.
    $script:Suivis = @(
        & git -C $script:Racine ls-files 2>$null |
            ForEach-Object { Join-Path $script:Racine $_ } |
            Where-Object { Test-Path -LiteralPath $_ }
    )
}

Describe 'aucun secret dans les fichiers suivis' {
    It 'trouve bien la liste des fichiers suivis' {
        # Sans cette garde, tous les tests suivants passeraient sur une liste
        # vide et diraient « aucun secret » sans avoir rien regarde.
        $script:Suivis.Count | Should -BeGreaterThan 10
    }

    It 'ne contient aucun jeton de type <_>' -ForEach @(
        @{ Nom = 'Supabase';  Motif = 'sbp_[A-Za-z0-9]{20,}' }
        @{ Nom = 'Supabase secret'; Motif = 'sb_secret_[A-Za-z0-9]{20,}' }
        @{ Nom = 'GitHub';    Motif = 'gh[pousr]_[A-Za-z0-9]{30,}' }
        @{ Nom = 'GitHub PAT'; Motif = 'github_pat_[A-Za-z0-9_]{30,}' }
        @{ Nom = 'OpenAI';    Motif = 'sk-[A-Za-z0-9]{32,}' }
        @{ Nom = 'Slack';     Motif = 'xox[baprs]-[A-Za-z0-9-]{20,}' }
        @{ Nom = 'AWS';       Motif = '(AKIA|ASIA)[A-Z0-9]{16}' }
        @{ Nom = 'Google';    Motif = 'AIza[A-Za-z0-9_\-]{30,}' }
        @{ Nom = 'cle privee'; Motif = '-----BEGIN [A-Z ]*PRIVATE KEY-----' }
    ) {
        $motif = $_.Motif
        $fautifs = @(
            Select-String -Path $script:Suivis -Pattern $motif -ErrorAction SilentlyContinue |
                # Les tests eux-memes portent des jetons FACTICES, c'est leur objet.
                Where-Object { $_.Path -notmatch '\\tests\\' } |
                ForEach-Object { "$($_.Filename):$($_.LineNumber)" }
        )
        $fautifs | Should -BeNullOrEmpty -Because "aucun secret ne doit partir dans un clone"
    }
}

Describe 'le module n ecrit jamais un secret' {
    It 'ne journalise aucune variable de secret dans une sortie console' {
        # Write-Host $env:SUPABASE_ACCESS_TOKEN est le geste de debug par lequel
        # un jeton finit dans un journal de terminal, puis dans une capture
        # d'ecran, puis dans une conversation.
        $sources = @($script:Suivis | Where-Object { $_ -match '\.(ps1|psm1)$' -and $_ -notmatch '\\tests\\' })
        $fautifs = @(
            Select-String -Path $sources `
                -Pattern '(Write-Host|Write-Output|Write-Information|echo)[^\r\n]*\$env:(SUPABASE_ACCESS_TOKEN|GH_TOKEN|VERCEL_TOKEN|SUPABASE_DB_PASSWORD|SENTRY_READ_TOKEN)' `
                -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }
        )
        $fautifs | Should -BeNullOrEmpty
    }

    It 'n ecrit aucun secret sur disque via Set-Content ou Out-File' {
        $sources = @($script:Suivis | Where-Object { $_ -match '\.(ps1|psm1)$' -and $_ -notmatch '\\tests\\' })
        $fautifs = @(
            Select-String -Path $sources `
                -Pattern '(Set-Content|Out-File|Add-Content)[^\r\n]*\$env:(SUPABASE_ACCESS_TOKEN|GH_TOKEN|VERCEL_TOKEN|SUPABASE_DB_PASSWORD)' `
                -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Filename):$($_.LineNumber)" }
        )
        $fautifs | Should -BeNullOrEmpty
    }

    It 'le shim ne nomme aucune variable de secret' {
        # Un refus s'affiche en clair et se colle dans une conversation.
        $t = Get-Content (Join-Path $script:Racine 'shims\supabase.ps1') -Raw
        foreach ($v in 'SUPABASE_ACCESS_TOKEN', 'GH_TOKEN', 'VERCEL_TOKEN', 'SUPABASE_DB_PASSWORD') {
            $t | Should -Not -Match $v
        }
    }

    It 'le shim n imprime pas les arguments de la commande refusee' {
        # Ils peuvent contenir --db-url, donc un mot de passe de base.
        $t = Get-Content (Join-Path $script:Racine 'shims\supabase.ps1') -Raw
        $refus = ($t -split '# --- refuse')[-1]
        $refus | Should -Not -Match '\$Arguments'
        $refus | Should -Not -Match '\$args'
    }
}

Describe 'le diagnostic ne fuit pas les vrais jetons de la machine' {
    It 'ctx doctor -Live ne recrache aucun jeton charge' {
        # Le test le plus severe du fichier : on produit le diagnostic complet
        # avec les VRAIS jetons du shell, puis on exige qu'aucun n'apparaisse.
        # Il ne prouve rien d'utile sans jeton charge, donc il le dit.
        $jetons = @(
            $env:SUPABASE_ACCESS_TOKEN, $env:GH_TOKEN,
            $env:VERCEL_TOKEN, $env:SUPABASE_DB_PASSWORD
        ) | Where-Object { $_ -and $_.Length -ge 8 }

        if (-not $jetons) {
            Set-ItResult -Skipped -Because 'aucun jeton charge dans ce shell : lancer work <contexte> pour que ce test morde'
            return
        }

        # ON N'ASSERTE PAS SUR LA BOTTE DE FOIN. `Should -Not -Match` imprime la
        # valeur reelle quand il echoue -- c'est-a-dire, ici, la sortie QUI
        # CONTIENT LE JETON, dans le journal de CI. Le test qui garde le secret
        # le publierait au moment precis ou il attrape la fuite. Mesure le
        # 22 aout 2026 en regardant la sortie d'un echec provoque.
        #
        # Un booleen ne dit que vrai ou faux.
        $sortie = (ctx-doctor -Live | ConvertTo-Json -Depth 6)
        foreach ($j in $jetons) {
            ($sortie -match [regex]::Escape($j)) | Should -BeFalse -Because 'un jeton ne sort jamais du module'
        }
    }

    It 'ctx doctor hors ligne ne recrache aucun jeton charge' {
        $jetons = @($env:SUPABASE_ACCESS_TOKEN, $env:GH_TOKEN, $env:VERCEL_TOKEN) |
            Where-Object { $_ -and $_.Length -ge 8 }
        if (-not $jetons) { Set-ItResult -Skipped -Because 'aucun jeton charge dans ce shell'; return }

        $sortie = (ctx-doctor | ConvertTo-Json -Depth 6)
        foreach ($j in $jetons) {
            ($sortie -match [regex]::Escape($j)) | Should -BeFalse -Because 'un jeton ne sort jamais du module'
        }
    }

    It 'le rapport du tableau de bord ne recrache aucun jeton charge' {
        # LE MEME TEST, SUR LA MEME SEVERITE, applique a la nouvelle sortie.
        #
        # Elle merite le sien : le diagnostic s'affiche dans un terminal et
        # disparait avec lui, tandis que le rapport est un FICHIER, qui reste, se
        # copie, s'attache a un message et se depose sur un bureau. Une fuite y
        # a une duree de vie que la sortie console n'a pas.
        $jetons = @(
            $env:SUPABASE_ACCESS_TOKEN, $env:GH_TOKEN,
            $env:VERCEL_TOKEN, $env:SUPABASE_DB_PASSWORD
        ) | Where-Object { $_ -and $_.Length -ge 8 }

        if (-not $jetons) {
            Set-ItResult -Skipped -Because 'aucun jeton charge dans ce shell : lancer work <contexte> pour que ce test morde'
            return
        }

        # Ecrit dans TestDrive plutot qu'a son emplacement reel : un test ne doit
        # pas ecraser le rapport de l'utilisateur, et surtout pas laisser une
        # copie de la topologie ailleurs que la ou le module la range.
        $cible = Join-Path $TestDrive 'securite/rapport.html'
        InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            $null = Invoke-DevContextDashboard -Path $d -NoOpen
        }

        $html = Get-Content -LiteralPath $cible -Raw
        foreach ($j in $jetons) {
            ($html -match [regex]::Escape($j)) |
                Should -BeFalse -Because 'un rapport est un fichier : il survit au terminal'
        }
    }

    It 'le rapport ne nomme meme pas la variable qui porterait un jeton' {
        # Ceinture ET bretelles, comme pour le shim : le nom d'une variable de
        # secret dans une page qu'on partage indique OU chercher. Le rapport
        # nomme des CLES -- 'supabase-token' -- jamais des variables
        # d'environnement.
        $cible = Join-Path $TestDrive 'securite2/rapport.html'
        InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            $null = Invoke-DevContextDashboard -Path $d -NoOpen
        }
        $html = Get-Content -LiteralPath $cible -Raw
        foreach ($v in @('SUPABASE_ACCESS_TOKEN', 'GH_TOKEN', 'VERCEL_TOKEN', 'SUPABASE_DB_PASSWORD')) {
            $html | Should -Not -BeLike "*$v*"
        }
    }
}

Describe 'hygiene du depot' {
    It 'ignore les fichiers d environnement' {
        $gitignore = Get-Content (Join-Path $script:Racine '.gitignore') -Raw
        $gitignore | Should -Match '\.env'
    }

    It 'ne suit aucun fichier d environnement' {
        @($script:Suivis | Where-Object { $_ -match '\\\.env(\.|$)' }) | Should -BeNullOrEmpty
    }

    It 'ne suit aucune cle privee' {
        @($script:Suivis | Where-Object { $_ -match '(id_rsa|id_ed25519)$|\.pem$|\.pfx$|\.p12$' }) |
            Should -BeNullOrEmpty
    }
}
