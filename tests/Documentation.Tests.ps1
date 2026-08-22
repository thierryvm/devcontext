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

Describe 'Le tableau des coutures du 2.0' {
    # CE BLOC EXISTE PARCE QUE LE TABLEAU S'EST TROUVE FAUX. ROADMAP.md affirmait
    # que chaque ecran du tableau de bord correspondait a une fonction « en
    # place » ; mesure le 22 aout 2026, deux des cinq lectures n'etaient pas
    # exportees du tout -- donc injoignables pour n'importe quel appelant hors du
    # module, et sans la moindre erreur pour le dire.
    #
    # Le tableau porte desormais une colonne « Reachable ». Une colonne ecrite a
    # la main est une affirmation de plus ; celle-ci est confrontee a l'export
    # REEL du module charge, comme le fait deja le test des commandes citees.
    # C'est ce qui la fait vieillir en rougissant au lieu de vieillir en silence.
    BeforeAll {
        Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force
        $m = Get-Module DevContext
        $script:Joignables = @($m.ExportedFunctions.Keys) + @($m.ExportedAliases.Keys)

        $roadmap = Get-Content (Join-Path $script:Racine 'ROADMAP.md') -Raw
        $lignes = $roadmap -split "`r?`n"

        # Le tableau est repere par son en-tete plutot que par un numero de
        # ligne : un document qui bouge ne doit pas casser le test qui le lit.
        $debut = -1
        for ($i = 0; $i -lt $lignes.Count; $i++) {
            if ($lignes[$i] -match '^\|\s*Screen\s*\|\s*Reads\s*\|\s*Reachable\s*\|') { $debut = $i; break }
        }

        $script:Rangees = @()
        if ($debut -ge 0) {
            # +2 : sauter l'en-tete et la ligne de separation.
            for ($i = $debut + 2; $i -lt $lignes.Count; $i++) {
                if ($lignes[$i] -notmatch '^\|') { break }
                $cellules = @(($lignes[$i] -split '\|') | ForEach-Object { $_.Trim() })
                # Un split sur '|' produit une cellule vide a chaque bout.
                if ($cellules.Count -lt 7) { continue }

                foreach ($paire in @(@{ Noms = 2; Verdict = 3; Role = 'lit' },
                                     @{ Noms = 4; Verdict = 5; Role = 'agit' })) {
                    $commandes = @([regex]::Matches($cellules[$paire.Noms], '`([^`]+)`') |
                        ForEach-Object { ($_.Groups[1].Value -split '\s+')[0] })
                    if ($commandes.Count -eq 0) { continue }   # la cellule '—'

                    $script:Rangees += [pscustomobject]@{
                        Ecran     = $cellules[1]
                        Role      = $paire.Role
                        Commandes = $commandes
                        Annonce   = ($cellules[$paire.Verdict] -replace '\*', '')
                    }
                }
            }
        }
    }

    It 'le tableau est trouve, et il a les cinq ecrans annonces' {
        # Sans ce controle, un tableau renomme rendrait tous les tests suivants
        # verts sur zero rangee -- le « vert pour la mauvaise raison » que
        # tests/README.md consigne deja deux fois.
        @($script:Rangees).Count | Should -BeGreaterThan 4
    }

    It 'chaque commande citee est nommee telle qu elle existe, ou pas du tout' {
        # Une colonne « joignable : non » ne doit pas devenir l'endroit ou dorment
        # les fautes de frappe. Les deux fonctions internes sont donc verifiees
        # PRESENTES dans le module, meme si elles n'en sortent pas.
        $absentes = foreach ($r in $script:Rangees) {
            foreach ($c in $r.Commandes) {
                $connue = ($c -in $script:Joignables) -or
                          [bool](& (Get-Module DevContext) { param($x) Get-Command $x -ErrorAction SilentlyContinue } $c)
                if (-not $connue) { "$($r.Ecran) [$($r.Role)] : $c" }
            }
        }
        ($absentes | Sort-Object -Unique) | Should -BeNullOrEmpty
    }

    It 'la colonne annoncee dit la verite sur l export reel' {
        # LE test de ce bloc. C'est exactement l'ecart trouve le 22 aout 2026 :
        # `Get-CtxRaccourciChecks` et `Get-CtxMcpFacts` existent, sont testees, et
        # ne sortent pas du module. Le jour ou l'une des deux est exportee, cette
        # ligne rougit au lieu de laisser le tableau mentir.
        $ecarts = foreach ($r in $script:Rangees) {
            $mesure = @($r.Commandes | Where-Object { $_ -notin $script:Joignables }).Count -eq 0
            $annonce = $r.Annonce -eq 'yes'
            if ($mesure -ne $annonce) {
                "$($r.Ecran) [$($r.Role)] : ROADMAP annonce '$($r.Annonce)', mesure '$(if ($mesure) { 'yes' } else { 'no' })'"
            }
        }
        ($ecarts | Sort-Object -Unique) | Should -BeNullOrEmpty
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
