BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
    Import-Module $script:Module -Force
}

# `ctx secret <key>` -- poser, remplacer ou retirer UN secret apres `ctx new`.
#
# Jusqu'ici, le module lui-meme conseillait, pour poser un jeton plus tard, un
# `Set-Secret` brut : la commande qui contourne la verification ajoutee apres
# l'incident du 8 novembre 2026 (un collage avale, stocke comme UN caractere).
# Ces tests fixent ce qui remplace ce conseil : la meme invite validee, aucun
# remplacement sans accord, aucune valeur affichee, et un refus net la ou
# personne ne peut repondre.
#
# Le VRAI coffre n'est jamais atteint : Get-Secret, Set-Secret et
# Remove-Secret sont simules pour LEVER. Le vrai SecretStore est protege par un
# mot de passe ; un appel reel attendrait une reponse que personne ne tape.
#
# Aucune valeur ci-dessous n'est un vrai jeton : elles sont FABRIQUEES a
# l'execution, pour qu'aucun motif de jeton n'apparaisse dans le depot.

Describe 'Set-DevContextSecret' {
    BeforeAll {
        $script:Valide = 'sbp_' + ('0123456789abcdef' * 3).Substring(0, 40)
    }

    BeforeEach {
        # Restaurer, jamais retirer : voir tests/README.md, 15 aout 2026.
        $script:DevctxAvant = $env:DEVCTX
        $env:DEVCTX = 'autre'

        InModuleScope DevContext {
            $script:TestSecret = @{
                Saisies       = [System.Collections.Generic.Queue[string]]::new()
                Reponses      = [System.Collections.Generic.Queue[string]]::new()
                PressePapiers = $null
                Existant      = $null
                Sortie        = [System.Collections.Generic.List[string]]::new()
                Stockes       = [System.Collections.Generic.List[object]]::new()
                Retires       = [System.Collections.Generic.List[string]]::new()
                # Le proprietaire du dossier courant, tel que Get-CtxProprietaire
                # le rendrait. Personne par defaut : le resultat ne doit jamais
                # dependre des contextes de la machine qui lance la suite.
                Proprio       = $null
                ProprioAmbigu = $false
            }
            Mock Test-CtxEntreeRedirigee { $false }
            Mock Get-CtxProprietaire {
                $p = $script:TestSecret.Proprio
                if ($script:TestSecret.ProprioAmbigu) {
                    [pscustomobject]@{ Etat = 'ambigu'; Manifeste = $null; Contexte = $null; Raison = 'racine-dupliquee'; Candidats = @('autre', 'perso'); CheminPhysique = 'C:\x' }
                }
                elseif ($p) {
                    [pscustomobject]@{ Etat = 'proprietaire'; Manifeste = [pscustomobject]@{ name = $p }; Contexte = $p; Raison = $null; Candidats = @($p); CheminPhysique = 'C:\x' }
                }
                else {
                    [pscustomobject]@{ Etat = 'aucun'; Manifeste = $null; Contexte = $null; Raison = $null; Candidats = @(); CheminPhysique = 'C:\x' }
                }
            }
            Mock Read-CtxManifest { [pscustomobject]@{ name = 'perso' } }
            Mock Test-CtxVault { }
            # Le coffre rend les METADONNEES de ce qui existe, rien d'autre.
            Mock Get-SecretInfo {
                if ($script:TestSecret.Existant) { [pscustomobject]@{ Name = $script:TestSecret.Existant } }
            }
            Mock Set-CtxSecret {
                $script:TestSecret.Stockes.Add([pscustomobject]@{
                        Name = $Name; Key = $Key; Valeur = (ConvertFrom-CtxSecureString $Value) })
            }
            Mock Remove-CtxSecret { $script:TestSecret.Retires.Add("$Name/$Key") }
            Mock Read-Host -ParameterFilter { $AsSecureString } {
                ConvertTo-CtxSecureString $script:TestSecret.Saisies.Dequeue()
            }
            Mock Read-Host -ParameterFilter { -not $AsSecureString } {
                if ($script:TestSecret.Reponses.Count) { $script:TestSecret.Reponses.Dequeue() } else { '' }
            }
            Mock Get-Clipboard -ParameterFilter { $Raw } { $script:TestSecret.PressePapiers }
            Mock Get-Clipboard -ParameterFilter { -not $Raw } {
                if ($null -ne $script:TestSecret.PressePapiers) { $script:TestSecret.PressePapiers -split '\r?\n' }
            }
            Mock Set-Clipboard { }
            Mock Write-Host { $script:TestSecret.Sortie.Add("$Object") }
            # Fils pieges : si l'un d'eux part, un test a atteint le vrai coffre.
            Mock Get-Secret { throw 'TEST : le vrai coffre a ete atteint (Get-Secret)' }
            Mock Set-Secret { throw 'TEST : le vrai coffre a ete atteint (Set-Secret)' }
            Mock Remove-Secret { throw 'TEST : le vrai coffre a ete atteint (Remove-Secret)' }
        }
    }

    AfterEach {
        InModuleScope DevContext { Remove-Variable -Name TestSecret -Scope Script -ErrorAction SilentlyContinue }
        if ($null -eq $script:DevctxAvant) { Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue }
        else { $env:DEVCTX = $script:DevctxAvant }
    }

    Context 'refus avant toute question' {
        It 'refuse une cle inconnue en listant les cles valides, sans rien demander ni toucher au coffre' {
            InModuleScope DevContext {
                $e = { Set-DevContextSecret -Key 'githb-token' -Name 'perso' } | Should -Throw -PassThru
                foreach ($k in $script:SecretMap.Keys) { $e.Exception.Message | Should -Match ([regex]::Escape($k)) }
                Should -Invoke Read-Host -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
                Should -Invoke Test-CtxVault -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'ne repete jamais une cle inconnue : une valeur collee a sa place n est pas affichee, et l historique est signale' {
            # Le premier endroit ou atterrit un jeton colle trop tot, c'est la
            # ligne de commande. Le message d'erreur ne doit pas le recopier.
            InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
                $e = { Set-DevContextSecret -Key $v -Name 'perso' } | Should -Throw -PassThru
                $e.Exception.Message | Should -Not -Match ([regex]::Escape($v))
                $e.Exception.Message | Should -Not -Match ([regex]::Escape($v.Substring(4, 12)))
                $e.Exception.Message | Should -Match ([regex]::Escape((T 'secret.cleRessembleJeton')))
            }
        }

        It 'une simple faute de frappe n est pas traitee comme une valeur de secret' {
            InModuleScope DevContext {
                $e = { Set-DevContextSecret -Key 'githb-token' -Name 'perso' } | Should -Throw -PassThru
                $e.Exception.Message | Should -Not -Match ([regex]::Escape((T 'secret.cleRessembleJeton')))
            }
        }

        It 'une faute de frappe courte, proche d une cle valide, ne crie pas au loup : <_>' -ForEach @(
            'githubtoken', 'gh-token', 'supabasedb', 'vercel-tokn', 'sentry'
        ) {
            InModuleScope DevContext -Parameters @{ k = $_ } { param($k)
                $v = Get-CtxVerdictSecret -Key $k -ClesValides @($script:SecretMap.Keys) -Contexte 'perso'
                $v.Etat | Should -Be 'cle-inconnue'
                $v.Jeton | Should -BeFalse
            }
        }

        It 'un mot de passe court en forme de cle, loin de toute cle valide, est signale : <_>' -ForEach @(
            'motdepasse26', 'azertyuiop'
        ) {
            # Minuscules et chiffres, moins de 16 caracteres : la forme d'une
            # cle. Seule la distance aux cles valides le distingue d'une faute
            # de frappe, et c'est lui qui finit dans l'historique.
            InModuleScope DevContext -Parameters @{ k = $_ } { param($k)
                $v = Get-CtxVerdictSecret -Key $k -ClesValides @($script:SecretMap.Keys) -Contexte 'perso'
                $v.Etat | Should -Be 'cle-inconnue'
                $v.Jeton | Should -BeTrue
                $e = { Set-DevContextSecret -Key $k -Name 'perso' } | Should -Throw -PassThru
                $e.Exception.Message | Should -Match ([regex]::Escape((T 'secret.cleRessembleJeton')))
                $e.Exception.Message | Should -Not -Match ([regex]::Escape($k))
            }
        }

        It 'Get-CtxDistanceEdition compte insertions, suppressions et substitutions' {
            InModuleScope DevContext {
                Get-CtxDistanceEdition -A '' -B '' | Should -Be 0
                Get-CtxDistanceEdition -A 'abc' -B '' | Should -Be 3
                Get-CtxDistanceEdition -A 'githb-token' -B 'github-token' | Should -Be 1
                Get-CtxDistanceEdition -A 'kitten' -B 'sitting' | Should -Be 3
                Get-CtxDistanceEdition -A 'Ab' -B 'ab' | Should -Be 1
            }
        }

        It 'refuse une entree redirigee avant toute question et tout acces au coffre' {
            # Une invite que personne ne lit ne rend jamais la main, et le
            # coffre lui-meme demanderait son mot de passe.
            InModuleScope DevContext {
                Mock Test-CtxEntreeRedirigee { $true }
                { Set-DevContextSecret -Key 'github-token' -Name 'perso' } |
                    Should -Throw -ExpectedMessage (T 'secret.redirige' 'github-token')
                Should -Invoke Read-Host -Times 0 -Exactly
                Should -Invoke Test-CtxVault -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'sans -Name ni contexte actif, refuse en disant comment le nommer' {
            $env:DEVCTX = ''
            InModuleScope DevContext {
                { Set-DevContextSecret -Key 'github-token' } |
                    Should -Throw -ExpectedMessage (T 'secret.sansContexte' 'github-token')
                Should -Invoke Read-CtxManifest -Times 0 -Exactly
            }
        }

        It 'refuse un nom de contexte qui designerait autre chose : <_>' -ForEach @('..\perso', 'perso/x', 'Perso') {
            InModuleScope DevContext -Parameters @{ n = $_ } { param($n)
                { Set-DevContextSecret -Key 'github-token' -Name $n } |
                    Should -Throw -ExpectedMessage (T 'secret.contexteInvalide')
                Should -Invoke Read-CtxManifest -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
            }
        }

        It 'sans cle, liste les cles valides au lieu d echouer' {
            InModuleScope DevContext {
                Set-DevContextSecret | Should -BeNullOrEmpty
                ($script:TestSecret.Sortie -join "`n") | Should -Match 'supabase-token'
                Should -Invoke Read-Host -Times 0 -Exactly
            }
        }
    }

    Context 'poser une cle' {
        It 'pose une cle absente par Read-CtxJeton et Set-CtxSecret, sans demander de confirmation' {
            InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
                $script:TestSecret.Saisies.Enqueue($v)
                Set-DevContextSecret -Key 'supabase-token' -Name 'perso' | Should -BeNullOrEmpty
                $script:TestSecret.Stockes.Count | Should -Be 1
                $script:TestSecret.Stockes[0].Name | Should -BeExactly 'perso'
                $script:TestSecret.Stockes[0].Key | Should -BeExactly 'supabase-token'
                $script:TestSecret.Stockes[0].Valeur | Should -BeExactly $v
                Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times 0 -Exactly
                ($script:TestSecret.Sortie -join "`n") |
                    Should -Match ([regex]::Escape((T 'secret.enregistre' 'supabase-token' 'perso' $v.Length)))
            }
        }

        It 'range la cle sous son orthographe canonique, quelle que soit la casse tapee' {
            InModuleScope DevContext {
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'GitHub-Token' -Name 'perso'
                $script:TestSecret.Stockes[0].Key | Should -BeExactly 'github-token'
            }
        }

        It 'sans -Name, agit sur le contexte qui possede le dossier quand la session s accorde' {
            # Ce test disait auparavant "agit sur le contexte ACTIF" et ne
            # construisait que le cas ou session et dossier coincident -- le
            # seul ou les deux lectures donnent la meme reponse. L'attente
            # elle-meme contredisait la doctrine du module (le dossier decide) ;
            # elle est corrigee ici, a voix haute, et les cas ou les deux
            # divergent sont construits dans le Context suivant.
            $env:DEVCTX = 'perso'
            InModuleScope DevContext {
                $script:TestSecret.Proprio = 'perso'
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'vercel-token'
                $script:TestSecret.Stockes[0].Name | Should -BeExactly 'perso'
            }
        }

        It 'ne stocke jamais un collage avale : le refus de Read-CtxJeton tient ici aussi' {
            InModuleScope DevContext {
                $script:TestSecret.Saisies.Enqueue([string][char]0x16)
                $script:TestSecret.Reponses.Enqueue('3')
                Set-DevContextSecret -Key 'supabase-token' -Name 'perso'
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'offre la sortie par le presse-papiers, valide puis ecrase' {
            InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
                $script:TestSecret.Saisies.Enqueue([string][char]0x16)
                $script:TestSecret.Reponses.Enqueue('2')
                $script:TestSecret.PressePapiers = "$v`r`n"
                Set-DevContextSecret -Key 'supabase-token' -Name 'perso'
                $script:TestSecret.Stockes[0].Valeur | Should -BeExactly $v
                Should -Invoke Set-Clipboard -ParameterFilter { $Value -eq ' ' } -Times 1 -Exactly
            }
        }

        It 'une Entree vide ne pose rien' {
            InModuleScope DevContext {
                $script:TestSecret.Saisies.Enqueue('')
                Set-DevContextSecret -Key 'sentry-token' -Name 'perso'
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'n affiche jamais la valeur, ni saisie, ni lue dans le presse-papiers, ni rendue' {
            InModuleScope DevContext -Parameters @{ v = $script:Valide } { param($v)
                $tape = 'sbp_' + ('fedcba9876543210' * 2).Substring(0, 30)
                $script:TestSecret.Existant = 'devctx/perso/supabase-token'
                $script:TestSecret.Reponses.Enqueue('o')
                $script:TestSecret.Saisies.Enqueue($tape)
                $script:TestSecret.Reponses.Enqueue('2')
                $script:TestSecret.PressePapiers = $v
                $rendu = Set-DevContextSecret -Key 'supabase-token' -Name 'perso'
                $rendu | Should -BeNullOrEmpty
                $script:TestSecret.Stockes.Count | Should -Be 1
                $tout = $script:TestSecret.Sortie -join "`n"
                $tout | Should -Not -BeNullOrEmpty
                foreach ($secret in @($tape, $v)) {
                    $tout | Should -Not -Match ([regex]::Escape($secret))
                    $tout | Should -Not -Match ([regex]::Escape($secret.Substring(4, 12)))
                }
            }
        }
    }

    Context 'remplacer une valeur existante' {
        It 'demande avant de remplacer, et ne demande meme pas la valeur sur un refus : <Nom>' -ForEach @(
            @{ Nom = 'n'; Reponse = 'n' }
            @{ Nom = 'Entree vide (non par defaut)'; Reponse = '' }
            @{ Nom = 'reponse quelconque'; Reponse = 'peut-etre' }
        ) {
            InModuleScope DevContext -Parameters @{ r = $Reponse } { param($r)
                $script:TestSecret.Existant = 'devctx/perso/github-token'
                $script:TestSecret.Reponses.Enqueue($r)
                Set-DevContextSecret -Key 'github-token' -Name 'perso'
                Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times 1 -Exactly
                Should -Invoke Read-Host -ParameterFilter { $AsSecureString } -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
                ($script:TestSecret.Sortie -join "`n") | Should -Match ([regex]::Escape((T 'secret.inchange' 'github-token')))
            }
        }

        It 'remplace sur un oui explicite, dans l une ou l autre langue : <_>' -ForEach @('o', 'oui', 'y', 'YES') {
            InModuleScope DevContext -Parameters @{ r = $_ } { param($r)
                $script:TestSecret.Existant = 'devctx/perso/github-token'
                $script:TestSecret.Reponses.Enqueue($r)
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'github-token' -Name 'perso'
                $script:TestSecret.Stockes.Count | Should -Be 1
            }
        }

        It 'une cle voisine au coffre ne compte pas comme la cle visee' {
            # Get-SecretInfo -Name accepte des jokers : seul le nom EXACT compte.
            InModuleScope DevContext {
                $script:TestSecret.Existant = 'devctx/perso/supabase-token-autre'
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'supabase-db' -Name 'perso'
                Should -Invoke Read-Host -ParameterFilter { -not $AsSecureString } -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 1
            }
        }

        It 'une erreur de lecture du coffre n est pas lue comme une absence' {
            # "absent" par defaut ecraserait une valeur sans demander.
            InModuleScope DevContext {
                Mock Get-SecretInfo { throw 'coffre verrouille' }
                { Set-DevContextSecret -Key 'github-token' -Name 'perso' } | Should -Throw
                Should -Invoke Read-Host -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'une valeur apparue pendant la saisie n est pas ecrasee sans accord' {
            # La presence se lit avant l'invite ; une autre fenetre peut poser
            # la cle pendant que l'utilisateur tape. Premiere lecture : absente.
            # Relecture juste avant l'ecriture : presente.
            InModuleScope DevContext {
                $script:TestSecret.Lectures = 0
                Mock Get-SecretInfo {
                    $script:TestSecret.Lectures++
                    if ($script:TestSecret.Lectures -ge 2) { [pscustomobject]@{ Name = 'devctx/perso/github-token' } }
                }
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                { Set-DevContextSecret -Key 'github-token' -Name 'perso' } |
                    Should -Throw -ExpectedMessage (T 'secret.apparu' 'github-token' 'perso')
                $script:TestSecret.Stockes.Count | Should -Be 0
                ($script:TestSecret.Sortie -join "`n") |
                    Should -Not -Match ([regex]::Escape((T 'secret.enregistre' 'github-token' 'perso' 24)))
            }
        }

        It 'sans valeur apparue, la relecture laisse passer l ecriture' {
            InModuleScope DevContext {
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'github-token' -Name 'perso'
                $script:TestSecret.Stockes.Count | Should -Be 1
                Should -Invoke Get-SecretInfo -Times 2 -Exactly
            }
        }
    }

    Context 'sans -Name, le dossier decide, jamais la session' {
        It 'dossier possede, aucun contexte actif : le secret va au proprietaire du dossier' {
            $env:DEVCTX = ''
            InModuleScope DevContext {
                $script:TestSecret.Proprio = 'perso'
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'github-token'
                $script:TestSecret.Stockes.Count | Should -Be 1
                $script:TestSecret.Stockes[0].Name | Should -BeExactly 'perso'
                Should -Invoke Get-CtxProprietaire -Times 1 -Exactly
            }
        }

        It 'dossier a personne, session active : refuse au lieu de prendre la session' {
            # LE defaut corrige. L'ancienne lecture de $env:DEVCTX rangeait ici
            # le jeton sous 'perso', pour un dossier que 'perso' ne possede pas.
            $env:DEVCTX = 'perso'
            InModuleScope DevContext {
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                { Set-DevContextSecret -Key 'github-token' } |
                    Should -Throw -ExpectedMessage (T 'secret.sansContexte' 'github-token')
                Should -Invoke Read-CtxManifest -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
                Should -Invoke Read-Host -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'dossier d un contexte, session d un autre : refuse en nommant les deux, sans toucher au coffre' {
            $env:DEVCTX = 'autre'
            InModuleScope DevContext {
                $script:TestSecret.Proprio = 'perso'
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                { Set-DevContextSecret -Key 'github-token' } |
                    Should -Throw -ExpectedMessage (T 'secret.dossierAutre' 'github-token' 'perso' 'autre')
                Should -Invoke Read-CtxManifest -Times 0 -Exactly
                Should -Invoke Test-CtxVault -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
                Should -Invoke Read-Host -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'proprietaire ambigu : refuse avec le message d ambiguite, meme quand la session pourrait trancher' {
            $env:DEVCTX = 'perso'
            InModuleScope DevContext {
                $script:TestSecret.ProprioAmbigu = $true
                $attendu = T 'secret.dossierAmbigu' 'github-token' (T 'proprietaire.ambigu.racines' 'autre, perso')
                { Set-DevContextSecret -Key 'github-token' } | Should -Throw -ExpectedMessage $attendu
                Should -Invoke Read-CtxManifest -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'avec -Name, le dossier n est meme pas consulte' {
            InModuleScope DevContext {
                $script:TestSecret.Proprio = 'autre'
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'github-token' -Name 'perso'
                $script:TestSecret.Stockes[0].Name | Should -BeExactly 'perso'
                Should -Invoke Get-CtxProprietaire -Times 0 -Exactly
            }
        }
    }

    Context 'le shell courant' {
        It 'dit de relancer work quand le contexte modifie est actif dans ce shell' {
            $env:DEVCTX = 'perso'
            InModuleScope DevContext {
                $script:TestSecret.Proprio = 'perso'
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'github-token'
                ($script:TestSecret.Sortie -join "`n") | Should -Match ([regex]::Escape((T 'secret.recharger' 'GH_TOKEN' 'perso')))
            }
        }

        It 'ne le dit pas pour un autre contexte que celui du shell' {
            InModuleScope DevContext {
                $script:TestSecret.Saisies.Enqueue('Ab3' * 8)
                Set-DevContextSecret -Key 'github-token' -Name 'perso'
                ($script:TestSecret.Sortie -join "`n") | Should -Not -Match ([regex]::Escape((T 'secret.recharger' 'GH_TOKEN' 'perso')))
            }
        }
    }

    Context '-Remove' {
        It 'retire apres un oui, sans jamais demander de valeur' {
            InModuleScope DevContext {
                $script:TestSecret.Existant = 'devctx/perso/vercel-token'
                $script:TestSecret.Reponses.Enqueue('o')
                Set-DevContextSecret -Key 'vercel-token' -Name 'perso' -Remove
                $script:TestSecret.Retires | Should -Be @('perso/vercel-token')
                Should -Invoke Read-Host -ParameterFilter { $AsSecureString } -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }

        It 'ne retire rien sur un refus' {
            InModuleScope DevContext {
                $script:TestSecret.Existant = 'devctx/perso/vercel-token'
                $script:TestSecret.Reponses.Enqueue('n')
                Set-DevContextSecret -Key 'vercel-token' -Name 'perso' -Remove
                $script:TestSecret.Retires.Count | Should -Be 0
            }
        }

        It 'dit qu il n y a rien a retirer, sans poser de question' {
            InModuleScope DevContext {
                Set-DevContextSecret -Key 'vercel-token' -Name 'perso' -Remove
                $script:TestSecret.Retires.Count | Should -Be 0
                Should -Invoke Read-Host -Times 0 -Exactly
                ($script:TestSecret.Sortie -join "`n") | Should -Match ([regex]::Escape((T 'secret.rienARetirer' 'vercel-token' 'perso')))
            }
        }
    }

    Context '-WhatIf' {
        It 'ne demande rien et ne touche pas au coffre' {
            InModuleScope DevContext {
                Set-DevContextSecret -Key 'github-token' -Name 'perso' -WhatIf
                Should -Invoke Test-CtxVault -Times 0 -Exactly
                Should -Invoke Get-SecretInfo -Times 0 -Exactly
                Should -Invoke Read-Host -Times 0 -Exactly
                $script:TestSecret.Stockes.Count | Should -Be 0
            }
        }
    }
}

Describe 'Set-DevContextSecret jusqu au coffre' {
    # Les autres tests simulent Set-CtxSecret et Remove-CtxSecret ; ceux-ci les
    # laissent s'executer, pour qu'un stockage ou une suppression qui les
    # contournerait -- ou viserait un autre nom -- se voie.
    #
    # Set-Secret et Remove-Secret n'y sont PAS simules par Mock : un module de
    # remplacement n'a pas la signature du vrai, et un Mock copie la signature
    # de ce qu'il remplace, donc ses arguments nommes deviendraient illisibles.
    # Chaque test definit a la place, DANS son bloc, une doublure portant les
    # parametres du vrai SecretManagement ; la portee dynamique de PowerShell la
    # fait trouver par Set-CtxSecret avant toute commande importee. Un appel qui
    # passerait un parametre que le vrai module n'a pas echouerait a la liaison.
    # Pas de Mock sur ces deux noms ici : un Mock Pester est un ALIAS, qui
    # passerait devant la doublure.
    BeforeEach {
        $script:DevctxAvant = $env:DEVCTX
        $env:DEVCTX = 'autre'
        InModuleScope DevContext {
            $script:TestCoffre = @{
                Saisie   = 'Ab3' * 8
                Reponse  = ''
                Existant = $null
                Sortie   = [System.Collections.Generic.List[string]]::new()
            }
            Mock Test-CtxEntreeRedirigee { $false }
            Mock Read-CtxManifest { [pscustomobject]@{ name = 'perso' } }
            Mock Test-CtxVault { }
            Mock Get-SecretInfo { if ($script:TestCoffre.Existant) { [pscustomobject]@{ Name = $script:TestCoffre.Existant } } }
            Mock Get-Secret { throw 'TEST : le vrai coffre a ete atteint (Get-Secret)' }
            Mock Read-Host -ParameterFilter { $AsSecureString } { ConvertTo-CtxSecureString $script:TestCoffre.Saisie }
            Mock Read-Host -ParameterFilter { -not $AsSecureString } { $script:TestCoffre.Reponse }
            Mock Write-Host { $script:TestCoffre.Sortie.Add("$Object") }
        }
    }

    AfterEach {
        InModuleScope DevContext { Remove-Variable -Name TestCoffre -Scope Script -ErrorAction SilentlyContinue }
        if ($null -eq $script:DevctxAvant) { Remove-Item Env:DEVCTX -ErrorAction SilentlyContinue }
        else { $env:DEVCTX = $script:DevctxAvant }
    }

    It 'Set-Secret recoit le coffre DevContext, le nom complet et la valeur saisie en SecureString' {
        InModuleScope DevContext {
            $poses = [System.Collections.Generic.List[object]]::new()
            function Set-Secret {
                [CmdletBinding()]
                param([string]$Vault, [string]$Name, [securestring]$SecureStringSecret)
                $poses.Add([pscustomobject]@{ Vault = $Vault; Name = $Name; Valeur = $SecureStringSecret })
            }
            function Remove-Secret { throw 'TEST : Remove-Secret appele pendant une pose' }

            Set-DevContextSecret -Key 'github-token' -Name 'perso'

            $poses.Count | Should -Be 1
            $poses[0].Vault | Should -BeExactly 'DevContext'
            $poses[0].Name | Should -BeExactly 'devctx/perso/github-token'
            $poses[0].Valeur | Should -BeOfType [securestring]
            ConvertFrom-CtxSecureString $poses[0].Valeur | Should -BeExactly $script:TestCoffre.Saisie
            ($script:TestCoffre.Sortie -join "`n") |
                Should -Match ([regex]::Escape((T 'secret.enregistre' 'github-token' 'perso' 24)))
        }
    }

    It 'une erreur NON bloquante du coffre leve, et le succes n est jamais annonce' {
        # Un fournisseur de coffre peut signaler un echec d'ecriture par
        # Write-Error, sans lever. Sans -ErrorAction Stop dans Set-CtxSecret,
        # l'erreur s'affichait puis "enregistre" suivait, en vert.
        InModuleScope DevContext {
            function Set-Secret {
                [CmdletBinding()]
                param([string]$Vault, [string]$Name, [securestring]$SecureStringSecret)
                Write-Error 'TEST : le fournisseur refuse l ecriture'
            }
            function Remove-Secret { throw 'TEST : Remove-Secret appele pendant une pose' }

            $e = { Set-DevContextSecret -Key 'github-token' -Name 'perso' } | Should -Throw -PassThru
            $e.Exception.Message | Should -Match ([regex]::Escape((T 'secret.echecEcriture' 'github-token' 'perso' 'X').TrimEnd('X')))
            ($script:TestCoffre.Sortie -join "`n") |
                Should -Not -Match ([regex]::Escape((T 'secret.enregistre' 'github-token' 'perso' 24)))
        }
    }

    It '-Remove passe par le vrai Remove-CtxSecret : coffre DevContext et nom complet' {
        InModuleScope DevContext {
            $retires = [System.Collections.Generic.List[object]]::new()
            function Remove-Secret {
                [CmdletBinding()]
                param([string]$Vault, [string]$Name)
                $retires.Add([pscustomobject]@{ Vault = $Vault; Name = $Name })
            }
            function Set-Secret { throw 'TEST : Set-Secret appele pendant un retrait' }
            $script:TestCoffre.Existant = 'devctx/perso/vercel-token'
            $script:TestCoffre.Reponse = 'o'

            Set-DevContextSecret -Key 'vercel-token' -Name 'perso' -Remove

            $retires.Count | Should -Be 1
            $retires[0].Vault | Should -BeExactly 'DevContext'
            $retires[0].Name | Should -BeExactly 'devctx/perso/vercel-token'
            Should -Invoke Read-Host -ParameterFilter { $AsSecureString } -Times 0 -Exactly
            ($script:TestCoffre.Sortie -join "`n") |
                Should -Match ([regex]::Escape((T 'secret.retire' 'vercel-token' 'perso')))
        }
    }

    It '-Remove : un refus du coffre leve, et le retrait n est jamais annonce' {
        InModuleScope DevContext {
            function Remove-Secret {
                [CmdletBinding()]
                param([string]$Vault, [string]$Name)
                Write-Error 'TEST : le fournisseur refuse la suppression'
            }
            function Set-Secret { throw 'TEST : Set-Secret appele pendant un retrait' }
            $script:TestCoffre.Existant = 'devctx/perso/vercel-token'
            $script:TestCoffre.Reponse = 'o'

            { Set-DevContextSecret -Key 'vercel-token' -Name 'perso' -Remove } | Should -Throw
            ($script:TestCoffre.Sortie -join "`n") |
                Should -Not -Match ([regex]::Escape((T 'secret.retire' 'vercel-token' 'perso')))
        }
    }
}

Describe 'ctx new : un echec d ecriture au coffre se dit' {
    BeforeEach {
        InModuleScope DevContext {
            $script:TestNew = [System.Collections.Generic.List[string]]::new()
            Mock Write-Host { $script:TestNew.Add("$Object") }
            Mock Get-Secret { throw 'TEST : le vrai coffre a ete atteint (Get-Secret)' }
        }
    }

    AfterEach {
        InModuleScope DevContext { Remove-Variable -Name TestNew -Scope Script -ErrorAction SilentlyContinue }
    }

    It 'Save-CtxJetonSaisi dit NON enregistre sur une erreur non bloquante, sans lever ni annoncer un succes' {
        InModuleScope DevContext {
            function Set-Secret {
                [CmdletBinding()]
                param([string]$Vault, [string]$Name, [securestring]$SecureStringSecret)
                Write-Error 'TEST : le fournisseur refuse l ecriture'
            }
            $valeur = ConvertTo-CtxSecureString ('Ab3' * 8)
            $r = Save-CtxJetonSaisi -Name 'perso' -Key 'github-token' -Value $valeur
            $r | Should -BeFalse
            $tout = $script:TestNew -join "`n"
            $tout | Should -Match ([regex]::Escape((T 'jeton.echecEcriture' 'github-token' 'perso' 'X').TrimEnd('X')))
            $tout | Should -Not -Match ([regex]::Escape((T 'jeton.enregistre' 'github-token' 24)))
        }
    }

    It 'Save-CtxJetonSaisi annonce le succes apres une ecriture reussie, au bon nom' {
        InModuleScope DevContext {
            $poses = [System.Collections.Generic.List[string]]::new()
            function Set-Secret {
                [CmdletBinding()]
                param([string]$Vault, [string]$Name, [securestring]$SecureStringSecret)
                $poses.Add("$Vault|$Name")
            }
            $r = Save-CtxJetonSaisi -Name 'perso' -Key 'github-token' -Value (ConvertTo-CtxSecureString ('Ab3' * 8))
            $r | Should -BeTrue
            $poses | Should -Be @('DevContext|devctx/perso/github-token')
            ($script:TestNew -join "`n") | Should -Match ([regex]::Escape((T 'jeton.enregistre' 'github-token' 24)))
        }
    }

    It 'New-DevContext stocke chaque jeton par Save-CtxJetonSaisi, jamais par Set-CtxSecret en direct' {
        # Un appel direct a Set-CtxSecret suivi d'un "enregistre" est
        # exactement la forme du defaut : l'annonce ne depend pas du resultat.
        $ast = InModuleScope DevContext { (Get-Command New-DevContext).ScriptBlock.Ast }
        $noms = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() })
        $noms | Should -Contain 'Save-CtxJetonSaisi'
        $noms | Should -Not -Contain 'Set-CtxSecret'
        $noms | Should -Not -Contain 'Set-Secret'
    }
}

Describe 'ctx secret : commande, alias et conseil non interactif' {
    It 'Set-DevContextSecret et ctx-secret sortent du module CHARGE, vers la meme fonction que ctx secret' {
        # Cree n'est pas exporte : seul l'objet module dit lequel des deux.
        $m = Get-Module DevContext
        $m.ExportedCommands.Keys | Should -Contain 'Set-DevContextSecret'
        $m.ExportedAliases.Keys | Should -Contain 'ctx-secret'
        $m.ExportedAliases['ctx-secret'].Definition | Should -Be 'Set-DevContextSecret'
        InModuleScope DevContext { Resolve-CtxSousCommande -Mot 'secret' } | Should -Be 'Set-DevContextSecret'
    }

    It 'ctx secret et ctx-secret refusent une entree redirigee dans un shell neuf : <_>' -ForEach @('ctx secret github-token', 'ctx-secret github-token') {
        # Le vrai [Console]::IsInputRedirected, sans simulacre : l'entree de
        # l'enfant est un tube. Aucun contexte n'est necessaire, et le coffre
        # n'est pas atteint -- le refus passe avant.
        $attendu = InModuleScope DevContext { T 'secret.redirige' 'github-token' }
        $code = "Import-Module '$script:Module'; try { $_ ; 'AUCUN-REFUS' } catch { 'MSG=' + `$_.Exception.Message }"
        $sortie = ('' | pwsh -NoProfile -NonInteractive -Command $code 2>&1) -join "`n"
        $sortie | Should -Match ([regex]::Escape("MSG=$attendu"))
        $sortie | Should -Not -Match 'AUCUN-REFUS'
    }

    It 'le conseil non interactif de ctx new designe ctx secret, plus le Set-Secret brut' {
        # Le Set-Secret brut contournait toute la verification de Read-CtxJeton.
        foreach ($langue in 'fr', 'en') {
            $t = (Import-PowerShellDataFile (Join-Path $PSScriptRoot '..' 'lang' "$langue.psd1"))['new.jetonsCommande']
            $t | Should -Match 'ctx secret <\w+> -Name \{0\}' -Because "lang/$langue.psd1"
            $t | Should -Not -Match 'Set-Secret' -Because "lang/$langue.psd1"
        }
    }

    It 'Set-DevContextSecret confie la saisie a Read-CtxJeton et le stockage a Set-CtxSecret' {
        $ast = (Get-Command Set-DevContextSecret).ScriptBlock.Ast
        $noms = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() })
        $noms | Should -Contain 'Read-CtxJeton'
        $noms | Should -Contain 'Set-CtxSecret'
        $noms | Should -Not -Contain 'Set-Secret'
        $noms | Should -Not -Contain 'Read-Host'
    }
}
