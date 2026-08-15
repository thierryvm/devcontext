BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Test-CtxSecretLitteral' {
    It 'reconnait un jeton <_> comme ecrit en clair' -ForEach @(
        'sbp_0102030405060708090a0b0c0d0e0f1011121314'
        'ghp_16CharsMinimumAAAAAAAAAAAAAAAAAAAAAA'
        'github_pat_11ABCDEFG0abcdefghijklmnop'
        'sk-proj-abcdefghijklmnopqrstuvwxyz0123'
        'xoxb-123456789012-1234567890123-abcdefgh'
        'AKIAIOSFODNN7EXAMPLE'
    ) {
        InModuleScope DevContext -Parameters @{ v = $_ } { param($v)
            Test-CtxSecretLitteral $v | Should -BeTrue
        }
    }

    It 'accepte une reference a une variable : <_>' -ForEach @(
        '${SUPABASE_ACCESS_TOKEN}', '%GH_TOKEN%', '$VERCEL_TOKEN', ' ${TOKEN} '
    ) {
        # C'est le BON cas, et le correctif que le rapport propose : deferer a
        # l'environnement, ou `work` a deja pose le jeton du bon compte.
        InModuleScope DevContext -Parameters @{ v = $_ } { param($v)
            Test-CtxSecretLitteral $v | Should -BeFalse
        }
    }

    It 'ne signale pas <_>' -ForEach @(
        '', ' ', 'true', '--project-ref', 'C:\Users\moi\AppData\Roaming\npm\serveur.js',
        '@supabase/mcp-server-supabase', 'npx', '-y'
    ) {
        InModuleScope DevContext -Parameters @{ v = $_ } { param($v)
            Test-CtxSecretLitteral $v | Should -BeFalse
        }
    }

    It 'signale une chaine opaque longue, meme sans prefixe connu' {
        # La liste de prefixes aura toujours un emetteur de retard. Un faux
        # positif coute un coup d'oeil ; un faux negatif, un jeton dans un
        # depot public.
        InModuleScope DevContext {
            Test-CtxSecretLitteral 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8' | Should -BeTrue
        }
    }
}

Describe 'Get-CtxPaires' {
    It 'enumere une table de hachage' {
        InModuleScope DevContext {
            $p = @(Get-CtxPaires @{ A = 1; B = 2 })
            $p.Count | Should -Be 2
            ($p | Where-Object Name -eq 'A').Value | Should -Be 1
        }
    }

    It 'enumere un objet' {
        InModuleScope DevContext {
            $p = @(Get-CtxPaires ([pscustomobject]@{ A = 1 }))
            $p[0].Name | Should -Be 'A'
        }
    }

    It 'ne rend rien sur null' {
        InModuleScope DevContext { @(Get-CtxPaires $null).Count | Should -Be 0 }
    }
}

Describe 'Test-CtxDoctorBinaire' {
    It 'rend ABSENT quand rien ne repond' {
        InModuleScope DevContext {
            (Test-CtxDoctorBinaire -Nom 'truc' -Installations @()).Verdict | Should -Be 'ABSENT'
        }
    }

    It 'rend OK sur une installation unique' {
        InModuleScope DevContext {
            $r = Test-CtxDoctorBinaire -Nom 'truc' -Installations @(
                [pscustomobject]@{ Chemin = 'C:\a\truc.exe'; Version = '1.0.0'; EstShim = $false })
            $r.Verdict | Should -Be 'OK'
            $r.Detail  | Should -Match '1\.0\.0'
        }
    }

    It 'rend ATTENTION sur deux versions differentes' {
        # Le cas mesure sur cette machine : supabase 2.84.2 sous PowerShell,
        # 2.109.1 via npm. « Quelle version tourne » depend alors du shell, et
        # un garde-fou eprouve sur l'une ne dit rien de l'autre.
        InModuleScope DevContext {
            $r = Test-CtxDoctorBinaire -Nom 'supabase' -Installations @(
                [pscustomobject]@{ Chemin = 'C:\a\supabase.exe'; Version = '2.84.2';  EstShim = $false }
                [pscustomobject]@{ Chemin = 'C:\b\supabase.cmd'; Version = '2.109.1'; EstShim = $false })
            $r.Verdict   | Should -Be 'ATTENTION'
            $r.Correctif | Should -Not -BeNullOrEmpty
        }
    }

    It 'rend INFO sur deux installations de meme version' {
        InModuleScope DevContext {
            (Test-CtxDoctorBinaire -Nom 'x' -Installations @(
                [pscustomobject]@{ Chemin = 'C:\a\x.exe'; Version = '1.0'; EstShim = $false }
                [pscustomobject]@{ Chemin = 'C:\b\x.exe'; Version = '1.0'; EstShim = $false })).Verdict |
                Should -Be 'INFO'
        }
    }

    It 'rend PROBLEME quand seul le shim repond' {
        # Le shim delegue au binaire reel : s'il est seul, toute commande
        # echoue en 127 et le garde-fou n'a plus rien a garder.
        InModuleScope DevContext {
            (Test-CtxDoctorBinaire -Nom 'supabase' -Installations @(
                [pscustomobject]@{ Chemin = 'F:\shims\supabase.cmd'; Version = $null; EstShim = $true })).Verdict |
                Should -Be 'PROBLEME'
        }
    }
}

Describe 'Test-CtxDoctorIdentiteGit' {
    It 'rend OK quand les deux emails concordent' {
        InModuleScope DevContext {
            (Test-CtxDoctorIdentiteGit -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' -Origine 'x').Verdict |
                Should -Be 'OK'
        }
    }

    It 'rend PROBLEME et nomme l origine quand ils different' {
        # Le piege documente : un user.email en dur dans .git/config prime sur
        # le includeIf, et rien ne le signale.
        InModuleScope DevContext {
            $r = Test-CtxDoctorIdentiteGit -EmailAttendu 'perso@x.be' -EmailReel 'pro@client.com' `
                -Origine 'C:\p\.git\config'
            $r.Verdict | Should -Be 'PROBLEME'
            $r.Detail  | Should -Match 'pro@client\.com'
            $r.Detail  | Should -Match '\.git\\config'
        }
    }

    It 'rend INFO hors de tout contexte' {
        InModuleScope DevContext {
            (Test-CtxDoctorIdentiteGit -EmailAttendu $null -EmailReel 'x@y.z' -Origine $null).Verdict |
                Should -Be 'INFO'
        }
    }
}

Describe 'Test-CtxDoctorRemote' {
    It 'rend PROBLEME sur une URL qui porte un login' {
        # https://login@github.com/... ne matche pas la regle insteadOf, qui est
        # un prefixe de chaine. Le push part alors sur le compte gh global.
        InModuleScope DevContext {
            $r = Test-CtxDoctorRemote -UrlPush 'https://thierryvm@github.com/org/repo.git' -AliasAttendu 'github-perso'
            $r.Verdict   | Should -Be 'PROBLEME'
            $r.Correctif | Should -Match 'set-url'
        }
    }

    It 'rend OK sur une URL qui emprunte l alias du contexte' {
        InModuleScope DevContext {
            (Test-CtxDoctorRemote -UrlPush 'git@github-perso:thierryvm/repo.git' -AliasAttendu 'github-perso').Verdict |
                Should -Be 'OK'
        }
    }

    It 'rend ATTENTION quand l alias attendu n apparait pas' {
        InModuleScope DevContext {
            (Test-CtxDoctorRemote -UrlPush 'git@github.com:org/repo.git' -AliasAttendu 'github-perso').Verdict |
                Should -Be 'ATTENTION'
        }
    }
}

Describe 'Test-CtxDoctorPathEntreeVide' {
    It 'rend OK sans entree vide' {
        InModuleScope DevContext {
            (Test-CtxDoctorPathEntreeVide -Path 'C:\a;C:\b').Verdict | Should -Be 'OK'
        }
    }

    It 'rend ATTENTION et compte les entrees vides' {
        # Une entree vide veut dire « le dossier courant » : n'importe quel
        # depot clone peut alors fournir un binaire qui masque une vraie commande.
        InModuleScope DevContext {
            $r = Test-CtxDoctorPathEntreeVide -Path 'C:\a;;C:\b;'
            $r.Verdict | Should -Be 'ATTENTION'
            $r.Detail  | Should -Match '2 entree'
        }
    }
}

Describe 'Test-CtxDoctorMcpServeur' {
    It 'rend PROBLEME sur un secret en clair, SANS jamais l imprimer' {
        InModuleScope DevContext {
            $secret = 'sbp_0102030405060708090a0b0c0d0e0f1011121314'
            $r = Test-CtxDoctorMcpServeur -Nom 'supabase' -Portee 'projet' -Definition ([pscustomobject]@{
                command = 'npx'
                env     = @{ SUPABASE_ACCESS_TOKEN = $secret }
            })
            $r.Verdict | Should -Be 'PROBLEME'
            $r.Detail  | Should -Match 'SUPABASE_ACCESS_TOKEN'
            # Le rapport finit dans des journaux et des conversations.
            $r.Detail    | Should -Not -Match ([regex]::Escape($secret))
            $r.Correctif | Should -Not -Match ([regex]::Escape($secret))
        }
    }

    It 'trouve un secret passe en argument et non en variable' {
        InModuleScope DevContext {
            $r = Test-CtxDoctorMcpServeur -Nom 'x' -Definition ([pscustomobject]@{
                command = 'npx'
                args    = @('-y', 'serveur', '--access-token', 'sbp_0102030405060708090a0b0c0d0e0f10111213')
            })
            $r.Verdict | Should -Be 'PROBLEME'
        }
    }

    It 'rend ATTENTION sur un serveur distant, lie au compte et non au dossier' {
        InModuleScope DevContext {
            (Test-CtxDoctorMcpServeur -Nom 'linear' -Definition ([pscustomobject]@{
                type = 'http'; url = 'https://mcp.linear.app/mcp' })).Verdict | Should -Be 'ATTENTION'
        }
    }

    It 'rend OK sur un serveur stdio qui defere a l environnement' {
        # La forme visee : le jeton vient de l'environnement, donc du contexte
        # du dossier, et le fichier peut etre commite sans rien exposer.
        InModuleScope DevContext {
            (Test-CtxDoctorMcpServeur -Nom 'supabase' -Portee 'projet' -Definition ([pscustomobject]@{
                command = 'npx'
                args    = @('-y', '@supabase/mcp-server-supabase', '--project-ref', 'abcdefghijklmnop')
                env     = @{ SUPABASE_ACCESS_TOKEN = '${SUPABASE_ACCESS_TOKEN}' }
            })).Verdict | Should -Be 'OK'
        }
    }
}

Describe 'Get-DevContextDoctor' {
    It 'rend des objets typés, affichables par le fichier de format' {
        (ctx-doctor)[0].PSObject.TypeNames | Should -Contain 'DevContext.DoctorCheck'
    }

    It 'ne rend que des verdicts connus' {
        $connus = @('OK', 'INFO', 'ATTENTION', 'PROBLEME', 'ABSENT')
        foreach ($c in (ctx-doctor)) { $c.Verdict | Should -BeIn $connus }
    }

    It 'produit un JSON valide pour un agent' {
        # C'est la sortie qu'un agent IA ou un job CI consomme : elle doit
        # s'analyser sans indulgence.
        $j = ctx-doctor -Json | ConvertFrom-Json
        $j.Count | Should -BeGreaterThan 0
        $j[0].PSObject.Properties.Name | Should -Contain 'Verdict'
        $j[0].PSObject.Properties.Name | Should -Contain 'Correctif'
    }

    It 'diagnostique un dossier arbitraire sans lever' {
        { ctx-doctor -Path $TestDrive } | Should -Not -Throw
    }

    It 'ne modifie pas le dossier courant' {
        $avant = (Get-Location).Path
        ctx-doctor -Path $TestDrive | Out-Null
        (Get-Location).Path | Should -Be $avant
    }

    It 'est expose comme alias ctx-doctor' {
        (Get-Alias 'ctx-doctor' -ErrorAction SilentlyContinue).ResolvedCommandName |
            Should -Be 'Get-DevContextDoctor'
    }
}
