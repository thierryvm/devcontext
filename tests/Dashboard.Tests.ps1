# Le tableau de bord : le rendu pur, puis le rassemblement.
#
# La premiere moitie ne touche pas le disque, parce que la fonction qu'elle
# teste n'y touche pas non plus. C'est tout l'interet de la separation : ce qui
# decide de l'affichage se verifie sans machine configuree, sans contexte actif
# et sans jeton charge.
#
# La seconde moitie confronte les champs DECLARES aux objets REELLEMENT rendus
# par le module. Elle existe parce que la premiere version du rendu lisait des
# noms de champs inventes -- 'Nom', 'Compte', 'Cle', 'Libelle' -- qui
# n'existaient sur aucun objet. Les tests etaient verts : ils injectaient les
# memes noms inventes, donc ils validaient le rendu contre sa propre hypothese.

# --- DECOUVERTE -------------------------------------------------------------
#
# La liste des champs est DERIVEE de la table du module, jamais recopiee ici.
# Ajouter une colonne ajoute donc son test tout seul -- et renommer un champ
# sans toucher la table fait rougir, au lieu d'afficher une colonne vide.
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'DevContext.psd1') -Force
$ChampsDeclares = & (Get-Module DevContext) {
    $table = Get-CtxDashboardSections
    foreach ($nom in $table.Keys) {
        foreach ($c in $table[$nom].Colonnes) {
            @{ Section = $nom; Champ = $c.Champ; Booleen = $c.ContainsKey('Booleen') }
        }
    }
}
$SectionsDeclarees = & (Get-Module DevContext) { (Get-CtxDashboardSections).Keys }

BeforeAll {
    $script:Racine = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force

    # Les cinq caracteres qui comptent, dans une seule charge. Un test par
    # caractere dirait moins : ce qui casse en vrai, c'est une valeur reelle qui
    # les melange.
    $script:Charge = '<script>alert("x")&' + "'" + '</script>'
}

Describe 'ConvertTo-CtxHtmlTexte' {
    It 'echappe l esperluette AVANT les autres substitutions' {
        # Si l'ordre s'inverse, '<' devient '&amp;lt;' : la page affiche le code
        # de l'entite au lieu du caractere, et le defaut ne se voit qu'a l'oeil.
        $r = InModuleScope DevContext { ConvertTo-CtxHtmlTexte '&<' }
        $r | Should -BeExactly '&amp;&lt;'
    }

    It 'echappe <_>' -ForEach @('<', '>', '&', '"', "'") {
        $r = InModuleScope DevContext -Parameters @{ c = $_ } { param($c) ConvertTo-CtxHtmlTexte $c }
        $r | Should -Not -BeExactly $_
        $r | Should -Match '^&[a-z#0-9]+;$'
    }

    It 'rend une chaine vide pour un null, jamais le mot null' {
        $r = InModuleScope DevContext { ConvertTo-CtxHtmlTexte $null }
        $r | Should -BeExactly ''
    }
}

Describe 'Format-CtxDashboardHtml' {
    BeforeAll {
        # Arrange dans la portee du TEST, jamais dans InModuleScope : une
        # fonction definie dans un BeforeAll n'existe pas dans la portee du
        # module, et l'appeler de la-bas rend un CommandNotFoundException qui se
        # lit comme une fonction de src/ manquante. Piege consigne dans
        # AGENTS.md, cinq tests rouges le 19 aout 2026.
        function New-FaitsAvecCharge {
            param(
                [Parameter(Mandatory)][AllowEmptyString()][string]$Section,
                [Parameter(Mandatory)][string]$Champ,
                [Parameter(Mandatory)][string]$Charge
            )
            # Une base inoffensive, puis la charge a UN seul endroit : ce qui
            # rougit nomme alors le champ, pas la page.
            $faits = @{ Dossier = 'D'; Proprietaire = 'p'; Actif = 'a' }
            if (-not $Section) {
                $faits[$Champ] = $Charge
                return [pscustomobject]$faits
            }
            $element = @{ $Champ = $Charge }
            $faits[$Section] = @([pscustomobject]$element)
            [pscustomobject]$faits
        }

        function Get-Html {
            param([Parameter(Mandatory)][AllowNull()]$Faits)
            InModuleScope DevContext -Parameters @{ f = $Faits } {
                param($f) Format-CtxDashboardHtml -Faits $f -Genere '2026-01-01 00:00'
            }
        }
    }

    Context 'Echappement, champ par champ' {
        # UN TEST PAR CHAMP, et non un test global sur une page ou tout est
        # rempli. Le test global passerait au vert le jour ou un SEUL champ
        # cesserait d'etre echappe, tant que les autres le sont -- et c'est
        # exactement le champ qu'on aurait ajoute sans y penser.
        #
        # Preuve de morsure du 22 aout 2026 : retirer l'echappement de l'en-tete
        # fait rougir exactement les trois champs d'en-tete et laisse les autres
        # verts ; le retirer des cellules fait l'inverse.
        It 'en-tete / <_>' -ForEach @('Dossier', 'Proprietaire', 'Actif') {
            $html = Get-Html (New-FaitsAvecCharge -Section '' -Champ $_ -Charge $script:Charge)
            $html | Should -Not -BeLike '*<script>*' -Because "l en-tete $_ n est pas echappe"
            $html | Should -BeLike '*&lt;script&gt;*'
        }

        It '<Section>/<Champ>' -ForEach ($ChampsDeclares | Where-Object { -not $_.Booleen }) {
            $html = Get-Html (New-FaitsAvecCharge -Section $Section -Champ $Champ -Charge $script:Charge)

            $html | Should -Not -BeLike '*<script>*' -Because "le champ $Section/$Champ n est pas echappe"
            $html | Should -BeLike '*&lt;script&gt;*' -Because 'la valeur doit rester LISIBLE, pas disparaitre'
            $html | Should -BeLike '*&quot;*'
            $html | Should -BeLike '*&#39;*'
        }
    }

    Context 'Autonomie de la page' {
        BeforeAll {
            $script:Page = Get-Html ([pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p'; Actif = 'a' })
        }

        It 'ne reference aucune ressource distante' {
            # Une page qui appelle le reseau depuis un outil d'identifiants
            # annonce la topologie de son porteur a qui heberge la ressource --
            # et ce rapport s'ouvre precisement quand on doute deja de quelque
            # chose. Verifie sur la SORTIE, pas sur l'intention.
            foreach ($motif in @('http://', 'https://', 'src="//', 'href="//', '@import')) {
                $script:Page | Should -Not -BeLike "*$motif*" -Because "'$motif' est une requete sortante"
            }
        }

        It 'ne contient ni script ni feuille de style liee' {
            $script:Page | Should -Not -BeLike '*<script*'
            $script:Page | Should -Not -BeLike '*<link*'
        }

        It 'declare une politique de securite qui interdit tout par defaut' {
            # La page peut DECLARER ce qu'elle s'interdit, et le navigateur le
            # fait respecter. L'intention ne protege pas ; la declaration, si.
            $script:Page | Should -BeLike '*Content-Security-Policy*'
            $script:Page | Should -BeLike "*default-src 'none'*"
        }
    }

    Context 'Les etats vides nomment la commande suivante' {
        BeforeAll {
            # Aucune section fournie : c'est la machine vierge, et c'est l'ecran
            # le plus important du produit.
            $script:Nue = Get-Html ([pscustomobject]@{ Dossier = 'D' })
        }

        It 'la section vide propose <_>' -ForEach @(
            'ctx doctor', 'ctx init', 'ctx editors', 'ctx shortcut', 'sb-index', 'ctx mcp'
        ) {
            # L'assertion porte sur la COMMANDE, jamais sur la phrase : la phrase
            # est traduite, la commande ne l'est pas. Decider sur du texte
            # affiche est le piege que ce depot a paye quatre fois.
            $script:Nue | Should -BeLike "*$_*" -Because 'une section vide qui ne dit pas quoi faire est une impasse'
        }

        It 'ne rend aucun tableau vide' {
            $script:Nue | Should -Not -BeLike '*<tbody></tbody>*'
        }
    }

    Context 'Purete' {
        It 'rend le meme octet pour les memes faits et le meme horodatage' {
            $faits = [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' }
            (Get-Html $faits) | Should -BeExactly (Get-Html $faits)
        }

        It 'ne lit pas l horloge : sans horodatage fourni, deux appels restent identiques' {
            # CE TEST EXISTE PARCE QUE LE PRECEDENT NE SUFFISAIT PAS, et c'est la
            # preuve de morsure qui l'a dit. Il s'appelait « ne connait pas
            # l heure » et passait -Genere : une fonction lisant l'horloge EN
            # REPLI, quand l'horodatage manque, serait passee au vert. Mesure le
            # 22 aout 2026 en remettant exactement ce defaut. Consigne ici
            # plutot que corrige en silence.
            $faits = [pscustomobject]@{ Dossier = 'D' }
            $a = InModuleScope DevContext -Parameters @{ f = $faits } {
                param($f) Format-CtxDashboardHtml -Faits $f
            }
            $b = InModuleScope DevContext -Parameters @{ f = $faits } {
                param($f) Format-CtxDashboardHtml -Faits $f
            }
            $a | Should -BeExactly $b -Because 'une fonction pure ne connait pas l heure'
        }

        It 'accepte des faits nuls sans lever, et rend quand meme une page' {
            $html = Get-Html $null
            $html | Should -BeLike '*<!DOCTYPE html>*'
            $html | Should -BeLike '*ctx init*'
        }

        It 'colore le verdict d apres sa valeur brute, jamais d apres un libelle' {
            # Le libelle est traduit ; la valeur appartient a un ValidateSet
            # ferme. Une classe CSS derivee du libelle changerait de nom entre
            # les deux langues, et la mise en forme disparaitrait dans l une.
            $faits = [pscustomobject]@{
                Dossier = 'D'
                Checks  = @([pscustomobject]@{ Domaine = 'gh'; Sujet = 'global'; Verdict = 'PROBLEME' })
            }
            (Get-Html $faits) | Should -BeLike '*v-PROBLEME*'
        }
    }
}

Describe 'Get-CtxDashboardFacts' {
    # ICI ON LIT LA MACHINE. Aucun reseau : le diagnostic est appele sans -Live,
    # donc ce rapport reste produisible hors ligne.
    BeforeAll {
        $script:Dossier = Split-Path $PSScriptRoot -Parent
        $script:Faits = InModuleScope DevContext -Parameters @{ d = $script:Dossier } {
            param($d) Get-CtxDashboardFacts -Path $d
        }
    }

    It 'ne leve pas quand aucun contexte n est actif' {
        # CE TEST EXISTE PARCE QUE LA SUITE ETAIT VERTE ICI ET AURAIT ROUGI EN
        # CI. Get-DevSupabaseMap retombe par defaut sur $env:DEVCTX et LEVE
        # quand il est vide ; le rassemblement mourait donc sur un dossier
        # qu'aucun contexte ne gouverne -- exactement le rapport qu'on ouvre
        # pour comprendre pourquoi on est hors contexte. Trouve le 22 aout 2026
        # en constatant que le resultat de la suite DEPENDAIT de la presence
        # d'un contexte dans le shell : 66 verts avec, 23 rouges sans.
        #
        # RESTAURER, jamais supprimer : effacer une variable reelle dans un
        # finally a deja desarme le test de fuite qui tournait apres.
        $sauvegarde = $env:DEVCTX
        try {
            Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue
            {
                InModuleScope DevContext -Parameters @{ d = $script:Dossier } {
                    param($d) Get-CtxDashboardFacts -Path $d
                }
            } | Should -Not -Throw -Because 'un rapport doit se produire hors contexte, c est la qu il sert'
        }
        finally {
            if ($null -eq $sauvegarde) { Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue }
            else { $env:DEVCTX = $sauvegarde }
        }
    }

    It 'rend une propriete pour chaque section que la table declare' {
        foreach ($nom in $SectionsDeclarees) {
            $script:Faits.PSObject.Properties.Name |
                Should -Contain $nom -Because 'une section declaree sans faits s afficherait vide, pour toujours'
        }
    }

    It 'le champ <Champ> existe sur les objets de <Section>' -ForEach $ChampsDeclares {
        $elements = @($script:Faits.$Section)
        if ($elements.Count -eq 0) {
            # DIT A VOIX HAUTE plutot que passe en silence. Une machine sans
            # contexte, sans index Supabase ou sans serveur MCP ne peut pas
            # repondre a cette question -- et un vert qui n'a rien mesure est
            # pire qu'un rouge.
            Set-ItResult -Skipped -Because "aucun element dans $Section sur cette machine"
            return
        }
        $elements[0].PSObject.Properties.Name |
            Should -Contain $Champ -Because "le rendu lit $Section.$Champ ; s il n existe pas, la colonne s affiche VIDE"
    }

    It 'ne rend aucun verdict que le diagnostic n a pas rendu' {
        # LE garde-fou de la contrainte centrale : le rapport ne decide rien. Si
        # ces deux ensembles divergent un jour, c'est qu'une seconde
        # implementation est apparue quelque part.
        $duDiagnostic = @(InModuleScope DevContext -Parameters @{ d = $script:Dossier } {
                param($d) Get-DevContextDoctor -Path $d
            }) | ForEach-Object { '{0}/{1}={2}' -f $_.Domaine, $_.Sujet, $_.Verdict }

        $duRapport = @(@($script:Faits.Checks) + @($script:Faits.Raccourcis)) |
            ForEach-Object { '{0}/{1}={2}' -f $_.Domaine, $_.Sujet, $_.Verdict }

        ($duRapport | Sort-Object) | Should -Be ($duDiagnostic | Sort-Object)
    }

    It 'partitionne les raccourcis sans en perdre ni en dupliquer' {
        $tous = @(@($script:Faits.Checks) + @($script:Faits.Raccourcis))
        @($script:Faits.Checks | Where-Object { $_.Domaine -eq 'raccourci' }) | Should -BeNullOrEmpty
        @($script:Faits.Raccourcis | Where-Object { $_.Domaine -ne 'raccourci' }) | Should -BeNullOrEmpty
        $tous.Count | Should -BeGreaterThan 0
    }
}


Describe 'Get-CtxDashboardPath' {
    It 'vit dans les donnees applicatives, jamais dans le dossier courant' {
        # Le rapport porte la topologie des comptes. Ecrit dans un depot, il
        # partirait au premier `git add -A` -- et ce depot a deja retire un
        # document de ce genre de son arbre ET de son historique le 15/08/2026.
        $chemin = InModuleScope DevContext { Get-CtxDashboardPath -Base 'B:\ailleurs' }
        $chemin | Should -BeLike '*ailleurs*'
        $chemin | Should -BeLike '*DevContext*'
        $chemin | Should -Not -BeLike "$PWD*"
    }

    It 'ne compose pas le chemin avec Join-Path' {
        # Join-Path est une applet de FOURNISSEUR : elle resout le lecteur et
        # rend une CHAINE VIDE quand il n'est pas monte, sans lever. Le module a
        # deja expedie un `--user-data-dir --extensions-dir .` par ce chemin.
        $source = Get-Content (Join-Path $script:Racine 'src/Dashboard.ps1') -Raw
        $fonction = [regex]::Match($source, '(?s)function Get-CtxDashboardPath \{.*?\n\}').Value
        $fonction | Should -Not -BeLike '*Join-Path*'
        $fonction | Should -BeLike '*System.IO.Path*'
    }
}

Describe 'Invoke-DevContextDashboard' {
    It 'ecrit a l emplacement d etat et rend son chemin' {
        $cible = Join-Path $TestDrive 'etat/rapport.html'
        $r = InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            # Le rassemblement est teste ailleurs. L'appeler ici ferait tourner
            # un `ctx doctor` complet par assertion -- 46 s pour ce fichier,
            # mesure le 22 aout 2026 -- et un test lent devient un test saute.
            Mock Get-CtxDashboardFacts { [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' } }
            Invoke-DevContextDashboard -Path $d -NoOpen
        }
        $r | Should -BeExactly $cible
        Test-Path -LiteralPath $cible | Should -BeTrue
        (Get-Content -LiteralPath $cible -Raw) | Should -BeLike '*<!DOCTYPE html>*'
    }

    It 'reecrit au meme endroit : deux appels laissent UN fichier' {
        # Chaque copie laissee derriere est une photographie de plus de la
        # topologie, a oublier quelque part.
        $dossier = Join-Path $TestDrive 'unique'
        $cible = Join-Path $dossier 'rapport.html'
        InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            # Le rassemblement est teste ailleurs. L'appeler ici ferait tourner
            # un `ctx doctor` complet par assertion -- 46 s pour ce fichier,
            # mesure le 22 aout 2026 -- et un test lent devient un test saute.
            Mock Get-CtxDashboardFacts { [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' } }
            $null = Invoke-DevContextDashboard -Path $d -NoOpen
            $null = Invoke-DevContextDashboard -Path $d -NoOpen
        }
        @(Get-ChildItem -LiteralPath $dossier -File).Count | Should -Be 1
    }

    It 'restreint le fichier a son proprietaire, et le refait a chaque appel' -Skip:(-not ($IsWindows -or $env:OS -eq 'Windows_NT')) {
        # PRECONDITION DECLAREE : les listes de controle d'acces sont une notion
        # Windows. Un test qui les verifie ailleurs mesurerait autre chose.
        #
        # « A chaque appel » n'est pas decoratif : Set-Acl reussissait la
        # PREMIERE fois puis echouait sur le meme fichier, mesure le 22 aout
        # 2026. Un test a un seul appel serait passe.
        $cible = Join-Path $TestDrive 'perms/rapport.html'
        InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            # Le rassemblement est teste ailleurs. L'appeler ici ferait tourner
            # un `ctx doctor` complet par assertion -- 46 s pour ce fichier,
            # mesure le 22 aout 2026 -- et un test lent devient un test saute.
            Mock Get-CtxDashboardFacts { [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' } }
            $null = Invoke-DevContextDashboard -Path $d -NoOpen
            $null = Invoke-DevContextDashboard -Path $d -NoOpen
        }
        $acl = Get-Acl -LiteralPath $cible
        $acl.AreAccessRulesProtected | Should -BeTrue -Because 'un heritage conserve annule la restriction'
        @($acl.Access).Count | Should -Be 1
        $acl.Access[0].IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) |
            Should -Be ([System.Security.Principal.WindowsIdentity]::GetCurrent().User)
    }

    It 'ouvre le navigateur, sauf avec -NoOpen' {
        $cible = Join-Path $TestDrive 'ouvre/rapport.html'
        InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            # Le rassemblement est teste ailleurs. L'appeler ici ferait tourner
            # un `ctx doctor` complet par assertion -- 46 s pour ce fichier,
            # mesure le 22 aout 2026 -- et un test lent devient un test saute.
            Mock Get-CtxDashboardFacts { [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' } }

            $null = Invoke-DevContextDashboard -Path $d -NoOpen
            Should -Invoke Start-Process -Times 0 -Exactly

            $null = Invoke-DevContextDashboard -Path $d
            Should -Invoke Start-Process -Times 1 -Exactly
        }
    }

    It 'avec -WhatIf, ne lit meme pas la machine' {
        # LA PREMIERE VERSION DE CE TEST NE MORDAIT PAS, et la preuve l'a dit :
        # elle verifiait seulement que le fichier n'existe pas, or PowerShell
        # propage -WhatIf a Set-Content et New-Item tout seul. Retirer la garde
        # ShouldProcess laissait donc le test vert -- il mesurait le moteur, pas
        # le code. Mesure le 22 aout 2026.
        #
        # Ce que la garde apporte VRAIMENT est ici : sous -WhatIf, on ne
        # rassemble pas. Le rassemblement fait tourner un diagnostic complet ;
        # un essai a blanc qui coute quinze secondes de lecture machine n'est
        # plus un essai a blanc.
        $cible = Join-Path $TestDrive 'whatif/rapport.html'
        InModuleScope DevContext -Parameters @{ c = $cible; d = $script:Racine } {
            param($c, $d)
            Mock Get-CtxDashboardPath { $c }
            Mock Start-Process { }
            Mock Get-CtxDashboardFacts { [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' } }

            $null = Invoke-DevContextDashboard -Path $d -NoOpen -WhatIf

            Should -Invoke Get-CtxDashboardFacts -Times 0 -Exactly
            Should -Invoke Start-Process -Times 0 -Exactly
        }
        Test-Path -LiteralPath $cible | Should -BeFalse
    }
}

Describe 'La commande, sous ses deux orthographes' {
    It 'la table declare la sous-commande, donc l alias en decoule' {
        $table = InModuleScope DevContext { Get-CtxSousCommandes }
        $table.Keys | Should -Contain 'dashboard'
        $table['dashboard'] | Should -BeExactly 'Invoke-DevContextDashboard'
    }

    It 'les deux orthographes existent pour l appelant' {
        # L'export REEL est l'intersection du psd1 et du psm1 : une commande
        # ajoutee a une seule des deux listes devient invisible sans erreur.
        # Mesure le 22 aout 2026 : l'alias etait bien CREE par le psm1 depuis la
        # table, et absent de la liste ecrite a la main du manifeste. La forme
        # espacee marchait, la forme a trait d'union n'existait pas.
        $m = Get-Module DevContext
        $m.ExportedFunctions.Keys | Should -Contain 'Invoke-DevContextDashboard'
        $m.ExportedAliases.Keys | Should -Contain 'ctx-dashboard'
    }
}
