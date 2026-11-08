BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

# 8 novembre 2026 : un jeton Supabase de 44 caracteres colle dans l'invite
# masquee de `ctx-new` n'a affiche qu'une etoile, et le coffre a recu UN
# caractere -- sans un mot. Ces tests fixent la regle : une saisie
# invraisemblable n'est jamais rendue pour stockage, le presse-papiers est la
# sortie de secours, et aucun message ne montre la valeur.
#
# Aucune valeur ci-dessous n'est un vrai jeton : elles sont FABRIQUEES a
# l'execution, pour qu'aucun motif de jeton n'apparaisse dans le depot.

Describe 'Test-CtxJetonPlausible' {
    It 'refuse une saisie contenant un caractere de controle : <Nom>' -ForEach @(
        @{ Nom = 'Ctrl+V lu comme une touche (0x16)'; Valeur = [string][char]0x16 }
        @{ Nom = 'retour a la ligne colle avec le jeton'; Valeur = "abcdefgh`r`nijkl" }
        @{ Nom = 'espace sans chasse (U+200B)'; Valeur = "abcdefgh$([char]0x200B)ijkl" }
        @{ Nom = 'controle C1 (U+0082)'; Valeur = "$([char]0x82)abcdefghijkl" }
    ) {
        InModuleScope DevContext -Parameters @{ v = $Valeur } { param($v)
            Test-CtxJetonPlausible -Key 'vercel-token' -Valeur $v | Should -Be 'controle'
        }
    }

    It 'refuse une saisie trop courte pour etre un secret : <_> caractere(s)' -ForEach @(1, 2, 7) {
        InModuleScope DevContext -Parameters @{ n = $_ } { param($n)
            Test-CtxJetonPlausible -Key 'github-token' -Valeur ('x' * $n) | Should -Be 'court'
        }
    }

    It 'rend vide pour une chaine vide' {
        InModuleScope DevContext {
            Test-CtxJetonPlausible -Key 'github-token' -Valeur '' | Should -Be 'vide'
        }
    }

    It 'accepte une valeur plausible pour une cle sans format connu' {
        InModuleScope DevContext {
            Test-CtxJetonPlausible -Key 'vercel-token' -Valeur ('Ab3' * 8) | Should -Be 'ok'
            Test-CtxJetonPlausible -Key 'supabase-db' -Valeur 'correct horse battery' | Should -Be 'ok'
        }
    }

    It 'accepte un jeton Supabase au format de la CLI : <Nom>' -ForEach @(
        @{ Nom = 'sbp_'; Prefixe = 'sbp_' }
        @{ Nom = 'sbp_oauth_'; Prefixe = 'sbp_oauth_' }
        @{ Nom = 'sbp_v0_'; Prefixe = 'sbp_v0_' }
    ) {
        InModuleScope DevContext -Parameters @{ p = $Prefixe } { param($p)
            $jeton = $p + ('0123456789abcdef' * 3).Substring(0, 40)
            Test-CtxJetonPlausible -Key 'supabase-token' -Valeur $jeton | Should -Be 'ok'
        }
    }

    It 'signale un jeton Supabase hors format : <Nom>' -ForEach @(
        @{ Nom = 'un caractere de moins'; Fabrique = { 'sbp_' + ('0123456789abcdef' * 3).Substring(0, 39) } }
        @{ Nom = 'hexadecimal en majuscules'; Fabrique = { 'sbp_' + ('0123456789ABCDEF' * 3).Substring(0, 40) } }
        @{ Nom = 'sans prefixe'; Fabrique = { ('0123456789abcdef' * 3).Substring(0, 44) } }
    ) {
        $jeton = & $Fabrique
        InModuleScope DevContext -Parameters @{ v = $jeton } { param($v)
            Test-CtxJetonPlausible -Key 'supabase-token' -Valeur $v | Should -Be 'format'
        }
    }
}

Describe 'Read-CtxJeton' {
    BeforeAll {
        $script:Valide = 'sbp_' + ('0123456789abcdef' * 3).Substring(0, 40)
    }

    BeforeEach {
        # Les reponses sont rangees dans la portee du MODULE : c'est la que
        # s'executent les simulacres, et une fonction ou une variable du
        # BeforeAll n'y existe pas.
        InModuleScope DevContext {
            $script:TestJeton = @{
                Saisies       = [System.Collections.Generic.Queue[string]]::new()
                Choix         = [System.Collections.Generic.Queue[string]]::new()
                PressePapiers = $null
                Sortie        = [System.Collections.Generic.List[string]]::new()
            }
            Mock Read-Host -ParameterFilter { $AsSecureString } {
                ConvertTo-CtxSecureString $script:TestJeton.Saisies.Dequeue()
            }
            # Plus de reponse = une reponse inconnue : le plafond de tours
            # doit alors terminer la boucle, jamais une exception du test.
            Mock Read-Host -ParameterFilter { -not $AsSecureString } {
                if ($script:TestJeton.Choix.Count) { $script:TestJeton.Choix.Dequeue() } else { '' }
            }
            Mock Get-Clipboard { $script:TestJeton.PressePapiers }
            Mock Set-Clipboard { }
            Mock Write-Host { $script:TestJeton.Sortie.Add("$Object") }
        }
    }

    AfterEach {
        InModuleScope DevContext { Remove-Variable -Name TestJeton -Scope Script -ErrorAction SilentlyContinue }
    }

    It 'ne rend JAMAIS pour stockage un collage avale en un caractere de controle' {
        # Le test de regression de l'incident : l'ancienne boucle stockait tout
        # ce qui n'etait pas vide.
        InModuleScope DevContext {
            $script:TestJeton.Saisies.Enqueue([string][char]0x16)
            $script:TestJeton.Choix.Enqueue('3')
            Read-CtxJeton -Key 'supabase-token' | Should -BeNullOrEmpty
            Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times 1 -Exactly
            Should -Invoke Get-Clipboard -Times 0 -Exactly
            ($script:TestJeton.Sortie -join "`n") | Should -Match 'supabase-token'
        }
    }

    It 'ne rend pas non plus une saisie d un seul caractere imprimable' {
        InModuleScope DevContext {
            $script:TestJeton.Saisies.Enqueue('x')
            $script:TestJeton.Choix.Enqueue('3')
            Read-CtxJeton -Key 'github-token' | Should -BeNullOrEmpty
        }
    }

    It 'passe la cle sur une Entree vide, sans poser d autre question' {
        InModuleScope DevContext {
            $script:TestJeton.Saisies.Enqueue('')
            Read-CtxJeton -Key 'github-token' | Should -BeNullOrEmpty
            Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times 0 -Exactly
            Should -Invoke Get-Clipboard -Times 0 -Exactly
        }
    }

    It 'rend une saisie valide telle quelle, sans menu ni presse-papiers' {
        InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
            $script:TestJeton.Saisies.Enqueue($v)
            $s = Read-CtxJeton -Key 'supabase-token'
            $s | Should -BeOfType [securestring]
            ConvertFrom-CtxSecureString $s | Should -BeExactly $v
            Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times 0 -Exactly
            Should -Invoke Get-Clipboard -Times 0 -Exactly
            Should -Invoke Set-Clipboard -Times 0 -Exactly
        }
    }

    It 'importe le jeton depuis le presse-papiers apres un collage avale, puis l ecrase' {
        InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
            $script:TestJeton.Saisies.Enqueue([string][char]0x16)
            $script:TestJeton.Choix.Enqueue('2')
            # Tel qu'un tableau de bord le copie : avec un retour a la ligne.
            $script:TestJeton.PressePapiers = "  $v`r`n"
            $s = Read-CtxJeton -Key 'supabase-token'
            ConvertFrom-CtxSecureString $s | Should -BeExactly $v
            Should -Invoke Set-Clipboard -ParameterFilter { $Value -eq ' ' } -Times 1 -Exactly
        }
    }

    It 'n importe ni n ecrase un presse-papiers invraisemblable : <Nom>' -ForEach @(
        @{ Nom = 'vide'; Contenu = $null }
        @{ Nom = 'un caractere'; Contenu = 'x' }
        @{ Nom = 'plusieurs lignes'; Contenu = "premiere ligne`nseconde ligne" }
    ) {
        InModuleScope DevContext -Parameters @{ c = $Contenu } { param($c)
            $script:TestJeton.Saisies.Enqueue([string][char]0x16)
            $script:TestJeton.Choix.Enqueue('2')
            $script:TestJeton.Choix.Enqueue('3')
            $script:TestJeton.PressePapiers = $c
            Read-CtxJeton -Key 'github-token' | Should -BeNullOrEmpty
            Should -Invoke Get-Clipboard -Times 1 -Exactly
            # Ce n'etait pas un jeton : peut-etre autre chose qui compte pour
            # l'utilisateur. On n'y touche pas.
            Should -Invoke Set-Clipboard -Times 0 -Exactly
        }
    }

    It 'garde un format inattendu seulement sur choix explicite (4)' {
        InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
            $proche = $v.Substring(0, 43)
            $script:TestJeton.Saisies.Enqueue($proche)
            $script:TestJeton.Choix.Enqueue('4')
            ConvertFrom-CtxSecureString (Read-CtxJeton -Key 'supabase-token') | Should -BeExactly $proche
        }
    }

    It 'ne laisse pas garder par 4 une saisie refusee, et finit par passer la cle' {
        InModuleScope DevContext {
            $script:TestJeton.Saisies.Enqueue([string][char]0x16)
            1..10 | ForEach-Object { $script:TestJeton.Choix.Enqueue('4') }
            Read-CtxJeton -Key 'github-token' | Should -BeNullOrEmpty
            Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times $script:JetonToursMax -Exactly
        }
    }

    It 'n affiche jamais la valeur, ni saisie ni lue dans le presse-papiers' {
        InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
            # Une saisie hors format (affichee par sa longueur), puis l'import.
            $tape = 'sbp_' + ('fedcba9876543210' * 2).Substring(0, 30)
            $script:TestJeton.Saisies.Enqueue($tape)
            $script:TestJeton.Choix.Enqueue('2')
            $script:TestJeton.PressePapiers = $v
            Read-CtxJeton -Key 'supabase-token' | Out-Null
            $tout = $script:TestJeton.Sortie -join "`n"
            $tout | Should -Not -BeNullOrEmpty
            foreach ($secret in @($tape, $v)) {
                $tout | Should -Not -Match ([regex]::Escape($secret))
                $tout | Should -Not -Match ([regex]::Escape($secret.Substring(4, 12)))
            }
        }
    }
}

Describe 'Une seule invite masquee dans le module' {
    BeforeAll {
        # L'AST plutot que le texte : un commentaire qui cite
        # `Read-Host -AsSecureString` ne doit ni declencher ni satisfaire le test.
        $racine = Join-Path $PSScriptRoot '..'
        $fichiers = @(Get-ChildItem $racine -Filter 'DevContext.psm1') + @(Get-ChildItem (Join-Path $racine 'src') -Filter '*.ps1')
        $script:Commandes = foreach ($f in $fichiers) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $fonction = $c.Parent
                while ($fonction -and $fonction -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) {
                    $fonction = $fonction.Parent
                }
                [pscustomobject]@{
                    Commande = $c.GetCommandName()
                    Masquee  = [bool]@($c.CommandElements | Where-Object {
                            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                            $_.ParameterName -eq 'AsSecureString' })
                    Fonction = if ($fonction) { $fonction.Name } else { '' }
                }
            }
        }
    }

    It 'aucune invite -AsSecureString hors de Read-CtxJeton' {
        # Une deuxieme invite masquee serait une deuxieme reponse a la meme
        # question -- et la seule qui n'aurait pas la verification.
        $horsSaisie = @($script:Commandes | Where-Object {
                $_.Commande -eq 'Read-Host' -and $_.Masquee -and $_.Fonction -ne 'Read-CtxJeton' })
        $horsSaisie.Fonction | Should -BeNullOrEmpty
        @($script:Commandes | Where-Object { $_.Commande -eq 'Read-Host' -and $_.Masquee }).Count |
            Should -BeGreaterThan 0
    }

    It 'New-DevContext confie la saisie des jetons a Read-CtxJeton' {
        $creation = @($script:Commandes | Where-Object Fonction -eq 'New-DevContext')
        $creation.Commande | Should -Contain 'Read-CtxJeton'
        $creation.Commande | Should -Not -Contain 'Read-Host'
    }
}
