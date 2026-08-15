# La documentation doit tenir ses promesses.
#
# Un lien mort, une commande d'exemple qui echoue, un fichier cite qui n'existe
# pas : ce sont les memes impasses que celles trouvees dans la CLI le 15 aout
# 2026, simplement ecrites en Markdown. Elles coutent la meme chose au lecteur --
# le temps de decouvrir tout seul que l'instruction ne marche pas -- et elles
# sont plus faciles a introduire, parce que rien ne les execute.
#
# Ces tests les executent.

BeforeAll {
    $script:Racine = Split-Path $PSScriptRoot -Parent
    $script:Docs = @(& git -C $script:Racine ls-files '*.md')
}

Describe 'Liens internes' {
    It 'aucun lien relatif ne pointe vers un fichier absent' {
        $morts = foreach ($doc in $script:Docs) {
            $contenu = Get-Content (Join-Path $script:Racine $doc) -Raw
            # [texte](cible) ou cible est un chemin relatif vers un fichier du depot.
            foreach ($m in [regex]::Matches($contenu, '\]\((?!https?:|mailto:)([^)#]+?)(?:#[^)]*)?\)')) {
                $cible = $m.Groups[1].Value.Trim()
                if (-not $cible -or $cible -match '^[a-z]+:') { continue }

                # Resoudre RELATIVEMENT au document, y compris a la racine, ou
                # Split-Path rend une chaine vide -- ce que la premiere version
                # de ce test avait rate, en signalant tous les liens de README
                # comme morts.
                $dossier = Split-Path $doc -Parent
                $base = if ($dossier) { Join-Path $script:Racine $dossier } else { $script:Racine }
                $resolu = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $cible))

                if (-not (Test-Path -LiteralPath $resolu)) { "$doc -> $cible" }
            }
        }
        $morts | Should -BeNullOrEmpty
    }
}

Describe 'Commandes citees' {
    It 'chaque commande ctx-* citee dans la documentation existe' {
        # Une documentation qui nomme une commande absente envoie le lecteur
        # taper quelque chose qui echouera.
        Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force
        $connues = @((Get-Module DevContext).ExportedAliases.Keys) +
                   @((Get-Module DevContext).ExportedFunctions.Keys)

        $inconnues = foreach ($doc in $script:Docs) {
            $contenu = Get-Content (Join-Path $script:Racine $doc) -Raw
            foreach ($m in [regex]::Matches($contenu, '(?<![\w-])(ctx-[a-z]+)(?![\w-])')) {
                $nom = $m.Groups[1].Value
                if ($nom -notin $connues) { "$doc : $nom" }
            }
        }
        ($inconnues | Sort-Object -Unique) | Should -BeNullOrEmpty
    }
}

Describe 'Aucune donnee personnelle' {
    It 'aucun fichier suivi ne porte une adresse e-mail personnelle' {
        # Les adresses d'exemple sont explicitement neutres. Une vraie adresse
        # dans un depot public est une cible a spam offerte.
        $suspects = foreach ($f in @(& git -C $script:Racine ls-files)) {
            $chemin = Join-Path $script:Racine $f
            if ((Get-Item $chemin).Length -gt 2MB) { continue }
            $contenu = Get-Content $chemin -Raw -ErrorAction SilentlyContinue
            if (-not $contenu) { continue }
            foreach ($m in [regex]::Matches($contenu, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')) {
                $adresse = $m.Value.ToLowerInvariant()
                $neutre = $adresse -match '(exemple|example|test|noreply|localhost|\.local$|@x\.|@y\.|@z\.|github\.com|supabase|client\.com)'
                if (-not $neutre) { "$f : $adresse" }
            }
        }
        ($suspects | Sort-Object -Unique) | Should -BeNullOrEmpty
    }

    It 'aucun fichier suivi ne porte un chemin de profil utilisateur reel' {
        $suspects = foreach ($f in @(& git -C $script:Racine ls-files)) {
            $chemin = Join-Path $script:Racine $f
            if ((Get-Item $chemin).Length -gt 2MB) { continue }
            $contenu = Get-Content $chemin -Raw -ErrorAction SilentlyContinue
            if ($contenu -match '(?i)[A-Z]:\\Users\\(?!moi\b|vous\b|<|%|\$)[A-Za-z0-9._-]+\\') { $f }
        }
        ($suspects | Sort-Object -Unique) | Should -BeNullOrEmpty
    }
}
