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

Describe 'Couverture des commandes par la documentation' {
    # CE BLOC EXISTE PARCE QUE LA DOC AVAIT SEPT COMMANDES DE RETARD, et que
    # personne ne l'a su avant que Thierry ne demande, le 22 aout 2026. Mesure
    # de ce jour-la : le README ignorait `ctx check`, `ctx end`, `ctx guard` et
    # `ctx off` ; le guide en ignorait sept, dont `ctx dashboard` -- ajoute au
    # README le matin meme et oublie ici l'apres-midi.
    #
    # C'est la meme famille que partout ailleurs dans ce depot : une liste
    # DERIVEE -- la table des sous-commandes -- et une prose ECRITE A LA MAIN
    # qui s'en separe en silence. `ctx guard` etait le cas qui coute : sorti en
    # 1.9.0, il traite les autorisations d'ECRITURE des agents, et il n'etait
    # documente nulle part.
    #
    # CE QUE CE TEST NE GARANTIT PAS, a dire aussi : il verifie la PRESENCE,
    # jamais la qualite. Une commande jetee dans un tableau le satisfait. Il
    # ferme la porte du « on a completement oublie », pas celle du « c'est mal
    # explique ».
    BeforeAll {
        Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force
        $script:SousCommandes = @(InModuleScope DevContext { (Get-CtxSousCommandes).Keys })
    }

    It 'la table des sous-commandes est trouvee, et elle n est pas vide' {
        # Sans cette garde, le test suivant passerait sur zero commande et
        # dirait « tout est documente » sans avoir rien regarde.
        $script:SousCommandes.Count | Should -BeGreaterThan 10
    }

    It 'chaque sous-commande est citee dans <_>' -ForEach @('README.md', 'docs/GUIDE.md') {
        $contenu = Get-Content (Join-Path $script:Racine $_) -Raw
        $doc = $_

        $absentes = foreach ($k in $script:SousCommandes) {
            # Les deux orthographes comptent : la doc emploie l'une ou l'autre
            # selon le contexte de la phrase, et les deux sont vraies.
            if ($contenu -notmatch "ctx[- ]$([regex]::Escape($k))(?![a-z])") { "$doc : ctx $k" }
        }
        ($absentes | Sort-Object -Unique) | Should -BeNullOrEmpty -Because 'une commande absente de la doc n existe pas pour le lecteur'
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

                # Deux colonnes par rangee : ce qui LIT, et ce par quoi on AGIT.
                $roles = @(
                    @{ Noms = 2; Verdict = 3; Role = 'lit' }
                    @{ Noms = 4; Verdict = 5; Role = 'agit' }
                )
                foreach ($paire in $roles) {
                    # Le premier mot de chaque nom entre accents graves : `ctx
                    # doctor -Json` et `New-DevShortcut -Force` designent une
                    # commande, pas une invocation complete.
                    $trouves = [regex]::Matches($cellules[$paire.Noms], '`([^`]+)`')
                    $commandes = @($trouves | ForEach-Object { ($_.Groups[1].Value -split '\s+')[0] })
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
                $interne = [bool](& (Get-Module DevContext) {
                        param($x) Get-Command $x -ErrorAction SilentlyContinue
                    } $c)
                $connue = ($c -in $script:Joignables) -or $interne
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

Describe 'Aucun caractere avale par un echappement' {
    # AGENTS.md consigne ce piege depuis le 19 aout 2026 : dans un heredoc, un
    # printf ou une chaine Python non brute, `\e` `\v` `\a` `\t` `\n` deviennent
    # des CARACTERES DE CONTROLE. Invisible dans un diff, invisible dans la
    # plupart des editeurs.
    #
    # Le controle qu'il recommandait -- grep -P '[\x00-\x08\x0b\x0c\x0e-\x1f]' --
    # ne couvre pas \x09. Deux documents portaient donc TAB + "hird-app" depuis
    # le 13 aout 2026, a la place de "third-app", et ce controle ne pouvait pas
    # les voir. Un garde-fou avec un trou de la taille du cas le plus courant.
    #
    # DEUXIEME TROU, mesure le 25 aout 2026 : la plage s'arretait a \x1f et
    # laissait passer les caracteres de controle C1, \x7f-\x9f. Ce jour-la, un
    # chemin Windows ecrit dans une chaine Python non brute a transforme
    # `\Backups\2026` en un echappement OCTAL : `\202` a produit U+0082, un C1,
    # au milieu d'un chemin. Le balayage cense l'attraper a rendu « aucun » --
    # il a EU L'AIR d'avoir regarde. Un octal a trois chiffres depasse \x1f des
    # que son premier chiffre vaut 1 ou plus, donc la plage d'origine ne pouvait
    # structurellement pas voir cette famille.
    #
    # CE QU'IL NE COUVRE PAS, a dire aussi fort : un `\n` avale devient un vrai
    # saut de ligne et un `\` avale devient une barre simple. Les deux sont des
    # caracteres parfaitement ordinaires ; rien ici ne peut les distinguer d'une
    # frappe voulue. Ce test attrape les caracteres qui n'ont AUCUNE raison
    # d'etre la, pas la classe entiere.
    BeforeAll {
        # Tous les fichiers suivis sont du texte -- verifie le 22 aout 2026 :
        # .ps1 .psd1 .psm1 .ps1xml .md .yml .cmd .svg .gitignore .gitattributes
        # .editorconfig et cinq shims sans extension. Aucun binaire, donc aucune
        # exclusion a maintenir. Le jour ou un binaire est ajoute, ce test le
        # signalera -- bruyamment, ce qui est le bon sens de l'erreur.
        $script:Suivis = @(& git -C $script:Racine ls-files)
    }

    It 'aucun caractere de controle dans un fichier suivi' {
        $suspects = foreach ($f in $script:Suivis) {
            $contenu = Get-Content (Join-Path $script:Racine $f) -Raw -ErrorAction SilentlyContinue
            if (-not $contenu) { continue }
            if ($contenu -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]') { $f }
        }
        ($suspects | Sort-Object -Unique) | Should -BeNullOrEmpty
    }

    It 'aucune tabulation ailleurs qu en tete de ligne, signature du \t avale' {
        # LA REGLE : une tabulation APRES le debut du contenu de la ligne.
        # ^\t* laisse passer l'indentation, [^\t\r\n] exige que le contenu ait
        # commence, et le \t final est celui qui n'a rien a faire la.
        #
        # La premiere version de CE test disait '\S\t' -- non blanc, puis
        # tabulation -- et elle est restee VERTE avec le vrai defaut remis en
        # place, parce que le caractere qui precedait la tabulation etait une
        # ESPACE (`other-app, ` + TAB). Elle n'aurait jamais attrape le cas pour
        # lequel elle etait ecrite. C'est la preuve de morsure qui l'a dit, pas
        # la relecture : un test vert ne prouve rien tant qu'on ne l'a pas vu
        # rougir. Consigne ici plutot que corrige en silence.
        #
        # DevContext.psm1 indente par tabulation les here-strings qui produisent
        # .gitconfig et le config SSH, ou la tabulation est la convention du
        # format. Elles sont en TETE de ligne, donc laissees.
        $suspects = foreach ($f in $script:Suivis) {
            $contenu = Get-Content (Join-Path $script:Racine $f) -Raw -ErrorAction SilentlyContinue
            if (-not $contenu) { continue }
            if ($contenu -match '(?m)^\t*[^\t\r\n][^\r\n]*\t') { $f }
        }
        ($suspects | Sort-Object -Unique) | Should -BeNullOrEmpty
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
