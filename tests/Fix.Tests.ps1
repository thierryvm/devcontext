# `ctx doctor -Fix` -- appliquer ce que le constat enonce deja.
#
# CE QUE CES TESTS TIENNENT
#
# Un reparateur qui deborde est desinstalle la premiere fois qu'il fait quelque
# chose que son proprietaire n'attendait pas, et il emporte les deux tiers
# utiles avec lui. La moitie de ce fichier verifie donc ce qu'il NE fait PAS :
# ne pas toucher a un constat sain, ne pas lancer deux fois la meme reparation,
# ne pas se taire sur ce qu'il laisse a la main.
#
# Le test du PATH ecrit dans une cle de registre JETABLE, jamais dans le vrai
# PATH utilisateur. Une suite de tests qui modifie la machine qui la fait
# tourner est une suite qu'on n'ose plus lancer.

BeforeAll {
    $script:Module = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psd1')).Path
    Import-Module $script:Module -Force
}

Describe 'Resolve-CtxReparation' {
    It 'rend la fonction de reparation pour un constat reparable' -ForEach @(
        @{ D = 'path'; S = 'entree vide'; V = 'ATTENTION'; Attendu = 'Repair-CtxPathEntreesVides' }
        @{ D = 'garde-fou'; S = 'portee'; V = 'PROBLEME'; Attendu = 'Repair-CtxShims' }
        @{ D = 'garde-fou'; S = 'jonction'; V = 'PROBLEME'; Attendu = 'Repair-CtxShims' }
    ) {
        InModuleScope DevContext -Parameters @{ D = $D; S = $S; V = $V; A = $Attendu } { param($D, $S, $V, $A)
            Resolve-CtxReparation -Domaine $D -Sujet $S -Verdict $V | Should -Be $A
        }
    }

    It 'ne repare JAMAIS un constat sain' {
        # Le verdict compte autant que le sujet. "Reparer" un etat sain est la
        # meilleure facon de casser une machine qui allait bien -- et le meme
        # couple domaine/sujet existe en OK comme en ATTENTION.
        InModuleScope DevContext {
            Resolve-CtxReparation -Domaine 'path' -Sujet 'entree vide' -Verdict 'OK' | Should -BeNullOrEmpty
            Resolve-CtxReparation -Domaine 'path' -Sujet 'entree vide' -Verdict 'INFO' | Should -BeNullOrEmpty
            Resolve-CtxReparation -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'OK' | Should -BeNullOrEmpty
        }
    }

    It 'rend $null sur un constat inconnu, sans lever' {
        InModuleScope DevContext {
            Resolve-CtxReparation -Domaine 'inconnu' -Sujet 'quelconque' -Verdict 'PROBLEME' | Should -BeNullOrEmpty
            Resolve-CtxReparation -Domaine '' -Sujet '' -Verdict 'PROBLEME' | Should -BeNullOrEmpty
        }
    }

    It 'chaque fonction de la table existe reellement' {
        # Une entree qui pointe sur un nom mal orthographie ne se verrait qu'au
        # moment de reparer, c'est-a-dire au pire moment.
        InModuleScope DevContext {
            foreach ($f in (Get-CtxReparations).Values) {
                Get-Command $f -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty -Because "$f doit exister"
            }
        }
    }
}

Describe 'Resolve-CtxRaisonManuelle' {
    It 'explique POURQUOI un constat reste manuel' {
        InModuleScope DevContext {
            $cle = Resolve-CtxRaisonManuelle -Domaine 'gh' -Sujet 'compte'
            $cle | Should -Not -BeNullOrEmpty
            # La raison doit exister dans les deux langues, sinon elle
            # s'afficherait sous la forme [la.cle] chez la moitie des lecteurs.
            (T $cle) | Should -Not -Match '^\['
        }
    }

    It 'rend $null quand il n y a rien de precis a dire' {
        # L'appelant se rabat alors sur le Correctif porte par le constat, plutot
        # que d'afficher une explication generique qui n'apprend rien.
        InModuleScope DevContext {
            Resolve-CtxRaisonManuelle -Domaine 'contexte' -Sujet 'proprietaire' | Should -BeNullOrEmpty
        }
    }

    It 'chaque raison declaree a bien sa cle dans les deux langues' {
        InModuleScope DevContext {
            foreach ($cle in $script:CtxNonReparables.Values) {
                (T $cle) | Should -Not -Match '^\[' -Because "$cle doit etre traduite"
            }
        }
    }
}

Describe 'Resolve-CtxPathSansVides' {
    It 'retire les entrees vides' {
        # Une entree vide n'est PAS cosmetique : Windows lit ';;' comme le
        # dossier COURANT. Un git.exe hostile pose dans un depot clone serait
        # alors lance avant le vrai.
        InModuleScope DevContext {
            $r = Resolve-CtxPathSansVides -Path 'C:\a;;C:\b;'
            $r.Valeur | Should -Be 'C:\a;C:\b'
            $r.Change | Should -BeTrue
        }
    }

    It 'retire les doublons exacts, casse et barre finale confondues' {
        InModuleScope DevContext {
            $r = Resolve-CtxPathSansVides -Path 'C:\a;C:\A\;c:\a'
            $r.Valeur | Should -Be 'C:\a'
            @($r.Retires).Count | Should -Be 2
        }
    }

    It 'garde le PREMIER exemplaire, et donc l ordre de recherche' {
        # Retirer le premier au lieu du second changerait quel binaire gagne.
        InModuleScope DevContext {
            (Resolve-CtxPathSansVides -Path 'C:\shims;C:\autre;C:\shims').Valeur |
                Should -Be 'C:\shims;C:\autre'
        }
    }

    It 'ecrit la valeur D ORIGINE, pas une forme normalisee' {
        # La comparaison est insensible a la casse ; l'ecriture ne doit pas
        # reecrire ce que l'utilisateur avait tape.
        InModuleScope DevContext {
            (Resolve-CtxPathSansVides -Path 'C:\Program Files\Truc\').Valeur |
                Should -Be 'C:\Program Files\Truc\'
        }
    }

    It 'ne signale aucun changement sur un PATH deja propre' {
        InModuleScope DevContext {
            $r = Resolve-CtxPathSansVides -Path 'C:\a;C:\b'
            $r.Change | Should -BeFalse
            $r.Valeur | Should -Be 'C:\a;C:\b'
        }
    }

    It 'ne leve pas sur une entree vide ou nulle' {
        InModuleScope DevContext {
            { Resolve-CtxPathSansVides -Path '' } | Should -Not -Throw
            { Resolve-CtxPathSansVides -Path $null } | Should -Not -Throw
        }
    }
}

Describe 'Repair-CtxPathEntreesVides' {
    # ECRIT DANS UNE CLE JETABLE. Le vrai PATH utilisateur n'est jamais touche :
    # une suite qui modifie la machine qui la fait tourner est une suite qu'on
    # n'ose plus lancer, et celle-ci tourne aussi en CI.
    BeforeAll {
        $script:CleTest = 'Software\DevContextTests\Env'
    }
    BeforeEach {
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:CleTest, $true)
        $k.SetValue('Path', 'C:\a;;C:\b;C:\a', [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $k.Close()
        $script:Sauvegarde = Join-Path $TestDrive 'sauvegardes'
    }
    AfterAll {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\DevContextTests', $false)
    }

    It 'retire les entrees vides et les doublons' {
        InModuleScope DevContext -Parameters @{ C = $script:CleTest; S = $script:Sauvegarde } { param($C, $S)
            $r = Repair-CtxPathEntreesVides -Cle $C -DossierSauvegarde $S -Confirm:$false
            $r.Applique | Should -BeTrue
            $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($C)
            try { $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
            finally { $k.Close() }
        } | Should -Be 'C:\a;C:\b'
    }

    It 'PRESERVE le type de registre' {
        # LE PIEGE, deja documente par l'installateur.
        # [Environment]::SetEnvironmentVariable rend la valeur DEVELOPPEE ; la
        # reecrire fige %USERPROFILE% en chemin litteral ET retrograde un
        # REG_EXPAND_SZ en REG_SZ. En silence, et pour de bon. Cette machine a un
        # PATH REG_SZ, donc le defaut ne s'y verrait jamais -- il ne casserait
        # que chez quelqu'un d'autre. D'ou la cle jetable en ExpandString.
        InModuleScope DevContext -Parameters @{ C = $script:CleTest; S = $script:Sauvegarde } { param($C, $S)
            Repair-CtxPathEntreesVides -Cle $C -DossierSauvegarde $S -Confirm:$false | Out-Null
            $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($C)
            try { $k.GetValueKind('Path') } finally { $k.Close() }
        } | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It 'ecrit une sauvegarde AVANT de modifier' {
        InModuleScope DevContext -Parameters @{ C = $script:CleTest; S = $script:Sauvegarde } { param($C, $S)
            $r = Repair-CtxPathEntreesVides -Cle $C -DossierSauvegarde $S -Confirm:$false
            $r.Sauvegarde | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $r.Sauvegarde | Should -BeTrue
            (Get-Content -LiteralPath $r.Sauvegarde -Raw).Trim() | Should -Be 'C:\a;;C:\b;C:\a'
        }
    }

    It 'est idempotent : une seconde passe ne change plus rien' {
        InModuleScope DevContext -Parameters @{ C = $script:CleTest; S = $script:Sauvegarde } { param($C, $S)
            Repair-CtxPathEntreesVides -Cle $C -DossierSauvegarde $S -Confirm:$false | Out-Null
            $second = Repair-CtxPathEntreesVides -Cle $C -DossierSauvegarde $S -Confirm:$false
            $second.Applique | Should -BeFalse
        }
    }

    It 'ne modifie RIEN sous -WhatIf' {
        InModuleScope DevContext -Parameters @{ C = $script:CleTest; S = $script:Sauvegarde } { param($C, $S)
            Repair-CtxPathEntreesVides -Cle $C -DossierSauvegarde $S -WhatIf | Out-Null
            $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($C)
            try { $k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
            finally { $k.Close() }
        } | Should -Be 'C:\a;;C:\b;C:\a'
    }
}

Describe 'Invoke-CtxDoctorFix -- repartition' {
    BeforeAll {
        $script:Constat = {
            param($D, $S, $V, $Correctif = '')
            [pscustomobject]@{ Domaine = $D; Sujet = $S; Verdict = $V; Detail = ''; Correctif = $Correctif }
        }
    }

    It 'appelle la reparation d un constat reparable' {
        InModuleScope DevContext -Parameters @{ N = $script:Constat } { param($N)
            $script:appels = @()
            $faux = { param($F) $script:appels += $F; [pscustomobject]@{ Applique = $true; Detail = 'ok' } }
            Invoke-CtxDoctorFix -Checks @((& $N 'path' 'entree vide' 'ATTENTION')) -Executeur $faux -Confirm:$false | Out-Null
            $script:appels | Should -Contain 'Repair-CtxPathEntreesVides'
        }
    }

    It 'ne lance PAS deux fois la meme reparation pour deux constats' {
        # `garde-fou/portee` et `garde-fou/jonction` sortent du meme installateur.
        # La relancer serait inoffensif -- elle est idempotente -- mais afficher
        # deux lignes pour un seul geste se lit comme deux problemes.
        InModuleScope DevContext -Parameters @{ N = $script:Constat } { param($N)
            $script:appels = @()
            $faux = { param($F) $script:appels += $F; [pscustomobject]@{ Applique = $true; Detail = 'ok' } }
            Invoke-CtxDoctorFix -Checks @(
                (& $N 'garde-fou' 'portee' 'PROBLEME')
                (& $N 'garde-fou' 'jonction' 'PROBLEME')
            ) -Executeur $faux -Confirm:$false | Out-Null
            @($script:appels).Count | Should -Be 1
        }
    }

    It 'ne touche a aucun constat sain' {
        InModuleScope DevContext -Parameters @{ N = $script:Constat } { param($N)
            $script:appels = @()
            $faux = { param($F) $script:appels += $F; [pscustomobject]@{ Applique = $true; Detail = 'ok' } }
            Invoke-CtxDoctorFix -Checks @(
                (& $N 'path' 'entree vide' 'OK')
                (& $N 'garde-fou' 'portee' 'OK')
                (& $N 'editeur' 'connexions' 'INFO')
            ) -Executeur $faux -Confirm:$false | Out-Null
            @($script:appels).Count | Should -Be 0
        }
    }

    It 'ne leve pas sur une liste de constats VIDE' {
        # Le premier tour lisait une propriete sur un tableau vide, ce que
        # StrictMode refuse : le rapport s'affichait en entier puis la commande
        # se terminait sur une exception. Mesure le 17 aout 2026.
        InModuleScope DevContext {
            { Invoke-CtxDoctorFix -Checks @() -Confirm:$false } | Should -Not -Throw
        }
    }

    It 'ne leve pas quand AUCUN constat n est reparable' {
        InModuleScope DevContext -Parameters @{ N = $script:Constat } { param($N)
            { Invoke-CtxDoctorFix -Checks @((& $N 'gh' 'compte' 'PROBLEME')) -Confirm:$false } | Should -Not -Throw
        }
    }
}

Describe 'ctx doctor -Fix -- garde-fous de la commande' {
    It 'REFUSE -Json et -Fix ensemble plutot que d en ignorer un' {
        # -Json sert a un programme, -Fix parle a un humain. En ignorer un en
        # silence ferait croire a l'appelant que ca a marche.
        { Get-DevContextDoctor -Fix -Json -Confirm:$false } | Should -Throw
    }

    It 'accepte -WhatIf et ne rend rien sur le pipeline' {
        # -Fix est une action, pas une question : un appelant qui veut des objets
        # lance `ctx doctor` sans -Fix, avant et apres, et compare.
        Get-DevContextDoctor -Fix -WhatIf | Should -BeNullOrEmpty
    }
}
