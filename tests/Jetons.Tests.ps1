BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Protect-CtxMessage' {
    It 'caviarde un jeton <_>' -ForEach @(
        'sbp_0102030405060708090a0b0c0d0e0f10'
        'ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        'github_pat_11ABCDEFG0abcdefghijklmnop'
        'sk-proj-abcdefghijklmnopqrstuvwxyz'
        'xoxb-123456789012-1234567890123-abcdefgh'
        'AKIAIOSFODNN7EXAMPLE'
    ) {
        InModuleScope DevContext -Parameters @{ j = $_ } { param($j)
            $m = Protect-CtxMessage "echec avec le jeton $j sur l API"
            $m | Should -Not -Match ([regex]::Escape($j))
            $m | Should -Match 'REDACTED'
        }
    }

    It 'caviarde une forme trouvee par l audit : <_>' -ForEach @(
        # L audit du 15 aout 2026 a mesure ces formes : toutes passaient intactes.
        # Les deux dernieres sont les plus graves — SUPABASE_DB_PASSWORD et
        # SENTRY_READ_TOKEN sont des secrets que ce module gere lui-meme.
        'postgresql://postgres.abcdefghijklmnopqrst:Sup3rS3cret!@aws-0.pooler.supabase.com:5432/postgres'
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signaturedelaclef'
        'SUPABASE_DB_PASSWORD=Sup3rS3cret-2026'
        'password: MonMotDePasse123'
        'glpat-abcdefghijklmnopqrst'
        'sntrys_abcdefghijklmnopqrstuvwx'
    ) {
        InModuleScope DevContext -Parameters @{ s = $_ } { param($s)
            $m = Protect-CtxMessage "echec : $s"
            $m | Should -Match 'REDACTED'
            # La partie sensible doit avoir disparu, pas seulement etre annotee.
            foreach ($morceau in @('Sup3rS3cret', 'MonMotDePasse123', 'signaturedelaclef',
                                   'abcdefghijklmnopqrst', 'abcdefghijklmnopqrstuvwx')) {
                if ($s -match [regex]::Escape($morceau)) {
                    $m | Should -Not -Match ([regex]::Escape($morceau))
                }
            }
        }
    }

    It 'caviarde un en-tete Bearer quel que soit l emetteur' {
        # La liste de prefixes aura toujours un emetteur de retard ; la FORME
        # « Bearer <quelque chose de long> », elle, ne change pas.
        InModuleScope DevContext {
            $m = Protect-CtxMessage 'Authorization: Bearer zzzzzzzzzzzzzzzzzzzzzzzzzzz'
            $m | Should -Not -Match 'zzzzzzzzzzzzzzzzzzzzzzzzzzz'
        }
    }

    It 'laisse un message ordinaire intact' {
        InModuleScope DevContext {
            Protect-CtxMessage 'Impossible de resoudre le nom api.supabase.com' |
                Should -Be 'Impossible de resoudre le nom api.supabase.com'
        }
    }

    It 'accepte null et vide sans lever' {
        InModuleScope DevContext {
            { Protect-CtxMessage $null } | Should -Not -Throw
            Protect-CtxMessage '' | Should -Be ''
        }
    }
}

Describe 'Test-CtxDoctorJetonGitHub' {
    It 'rend PROBLEME sur un jeton refuse' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonGitHub -Code 401).Verdict | Should -Be 'PROBLEME'
        }
    }

    It 'rend PROBLEME quand le jeton ouvre un AUTRE compte' {
        # C'est l'echec interessant : un jeton parfaitement valide, sur le
        # mauvais compte. Une verification qui ne demanderait que « est-il
        # valide ? » benirait exactement le cas que ce module existe a empecher.
        #
        # Comptes FICTIFS a dessein. Ce depot est destine a etre public : y
        # ecrire un vrai identifiant de client, c'est publier une relation
        # commerciale dans un fichier de test.
        InModuleScope DevContext {
            $r = Test-CtxDoctorJetonGitHub -LoginAttendu 'compte-perso' -LoginReel 'compte-client'
            $r.Verdict | Should -Be 'PROBLEME'
            $r.Detail  | Should -Match 'compte-client'
            $r.Detail  | Should -Match 'compte-perso'
        }
    }

    It 'rend OK quand le compte concorde' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonGitHub -LoginAttendu 'thierryvm' -LoginReel 'thierryvm').Verdict |
                Should -Be 'OK'
        }
    }

    It 'rapporte les portees quand elles sont connues' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonGitHub -LoginAttendu 'a' -LoginReel 'a' -Portees 'repo, workflow').Detail |
                Should -Match 'repo, workflow'
        }
    }

    It 'rend INFO — et non PROBLEME — quand le reseau est injoignable' {
        # Un train dans un tunnel ne dit rien du jeton. Confondre les deux, c'est
        # crier au loup, et un outil qui crie au loup finit desinstalle.
        InModuleScope DevContext {
            (Test-CtxDoctorJetonGitHub -LoginAttendu 'a' -LoginReel $null -Code 0 `
                -Erreur 'nom de domaine introuvable').Verdict | Should -Be 'INFO'
        }
    }

    It 'caviarde un jeton present dans le message d erreur' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonGitHub -LoginReel $null -Erreur 'echec : ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA').Detail |
                Should -Not -Match 'ghp_A'
        }
    }
}

Describe 'Test-CtxDoctorJetonSupabase' {
    It 'rend PROBLEME sur 401 comme sur 403' -ForEach @(401, 403) {
        InModuleScope DevContext -Parameters @{ c = $_ } { param($c)
            (Test-CtxDoctorJetonSupabase -Code $c).Verdict | Should -Be 'PROBLEME'
        }
    }

    It 'rend OK quand le projet du dossier est visible' {
        InModuleScope DevContext {
            $r = Test-CtxDoctorJetonSupabase -RefAttendu 'refdeprod00000000000' -Code 200 -Projets @(
                [pscustomobject]@{ id = 'autre';     name = 'autre-projet' }
                [pscustomobject]@{ id = 'refdeprod00000000000'; name = 'demo-app-prod' })
            $r.Verdict | Should -Be 'OK'
            $r.Detail  | Should -Match 'demo-app-prod'
        }
    }

    It 'rend PROBLEME quand le jeton marche mais ne voit pas CE projet' {
        # Le scenario redoute dans l'autre sens : le jeton fonctionne, mais pas
        # sur le projet de ce dossier. La commande partirait sur un compte reel
        # avec un message d'erreur qui ne dit pas pourquoi.
        InModuleScope DevContext {
            $r = Test-CtxDoctorJetonSupabase -RefAttendu 'refdeprod00000000000' -Code 200 -Projets @(
                [pscustomobject]@{ id = 'autre'; name = 'autre-projet' })
            $r.Verdict   | Should -Be 'PROBLEME'
            $r.Correctif | Should -Match 'sb-index'
        }
    }

    It 'rend INFO sur une panne reseau' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonSupabase -Code 0 -Erreur 'delai depasse').Verdict | Should -Be 'INFO'
        }
    }
}

Describe 'Get-CtxProp — lecture defensive' {
    It 'rend le defaut sur un objet nul, au lieu de lever' {
        # Un dossier hors contexte n'a pas de manifeste. Sans ceci,
        # `ctx doctor -Live` y plantait sur une erreur de liaison de parametre,
        # pas sur la lecture qu'il tentait.
        InModuleScope DevContext {
            Get-CtxProp $null 'github.login' | Should -BeNullOrEmpty
            Get-CtxProp $null 'x' 'defaut'   | Should -Be 'defaut'
        }
    }

    It 'rend le defaut sur un champ absent' {
        InModuleScope DevContext {
            Get-CtxProp ([pscustomobject]@{ a = 1 }) 'b' 'defaut' | Should -Be 'defaut'
        }
    }

    It 'traverse un chemin imbrique' {
        InModuleScope DevContext {
            Get-CtxProp ([pscustomobject]@{ github = [pscustomobject]@{ login = 'x' } }) 'github.login' |
                Should -Be 'x'
        }
    }
}

Describe 'Test-CtxDoctorJetonVercel' {
    It 'rend OK avec le nom d utilisateur' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonVercel -Utilisateur 'thierryvm' -Code 200).Detail | Should -Match 'thierryvm'
        }
    }
    It 'rend PROBLEME sur 401' {
        InModuleScope DevContext {
            (Test-CtxDoctorJetonVercel -Code 401).Verdict | Should -Be 'PROBLEME'
        }
    }
}

Describe 'ctx doctor -Live' {
    It 'ne joint PAS le reseau sans -Live' {
        # La propriete qui rend l'appel par defaut utilisable partout, y compris
        # hors ligne et dans un hook git.
        InModuleScope DevContext {
            Mock Invoke-CtxApi { throw "le reseau ne doit pas etre joint" }
            Mock Get-CtxJetonChecks { throw "les jetons ne doivent pas etre sondes" }
            { Get-DevContextDoctor -Path $TestDrive } | Should -Not -Throw
        }
    }

    It 'sonde les jetons avec -Live' {
        InModuleScope DevContext {
            Mock Get-CtxJetonChecks { @(New-CtxCheck -Domaine 'gh' -Sujet 'jeton' -Verdict 'OK' -Detail 'faux') }
            $r = Get-DevContextDoctor -Path $TestDrive -Live
            ($r | Where-Object { $_.Sujet -eq 'jeton' }).Count | Should -BeGreaterThan 0
            Should -Invoke Get-CtxJetonChecks -Times 1
        }
    }

    It 'n imprime jamais un jeton, meme quand l API en renvoie un' {
        InModuleScope DevContext {
            Mock Invoke-CtxApi {
                [pscustomobject]@{ Ok = $false; Data = $null; Code = 500
                    Erreur = (Protect-CtxMessage 'echec : Bearer sbp_0102030405060708090a0b0c0d0e0f10') }
            }
            # RESTAURER, et non supprimer : ce shell porte peut-etre le vrai
            # jeton, et le retirer faisait sauter le test de securite de bout en
            # bout qui, lui, verifie qu'aucun VRAI jeton ne ressort. Un test qui
            # desarme un autre test est pire qu'un test absent : la suite reste
            # verte et la couverture, elle, a disparu.
            $avant = $env:SUPABASE_ACCESS_TOKEN
            $env:SUPABASE_ACCESS_TOKEN = 'sbp_0102030405060708090a0b0c0d0e0f10'
            try {
                $t = (Get-CtxJetonChecks -Manifeste $null -Ref $null | ConvertTo-Json -Depth 5)
                $t | Should -Not -Match 'sbp_0102'
            }
            finally {
                if ($null -ne $avant) { $env:SUPABASE_ACCESS_TOKEN = $avant }
                else { Remove-Item Env:SUPABASE_ACCESS_TOKEN -ErrorAction SilentlyContinue }
            }
        }
    }
}
