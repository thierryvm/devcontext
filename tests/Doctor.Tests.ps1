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

Describe 'Test-CtxDistroTechnique' {
    It 'ecarte <_>, qui est de la machinerie et pas un shell' -ForEach @(
        'docker-desktop', 'docker-desktop-data', 'Docker-Desktop', 'rancher-desktop'
    ) {
        InModuleScope DevContext -Parameters @{ n = $_ } { param($n)
            Test-CtxDistroTechnique $n | Should -BeTrue
        }
    }

    It 'garde <_>, ou quelqu un tape reellement des commandes' -ForEach @(
        'Ubuntu', 'Ubuntu-22.04', 'Debian', 'kali-linux', 'Arch'
    ) {
        InModuleScope DevContext -Parameters @{ n = $_ } { param($n)
            Test-CtxDistroTechnique $n | Should -BeFalse
        }
    }

    It 'ne prend pas un nom vide pour une vraie distribution' {
        InModuleScope DevContext {
            Test-CtxDistroTechnique '' | Should -BeTrue
            Test-CtxDistroTechnique $null | Should -BeTrue
        }
    }
}

Describe 'Test-CtxDoctorRemote' {
    It 'rend PROBLEME sur une URL qui porte un login' {
        # https://login@github.com/... ne matche pas la regle insteadOf, qui est
        # un prefixe de chaine. Le push part alors sur le compte gh global.
        InModuleScope DevContext {
            $r = Test-CtxDoctorRemote -UrlPush 'https://login@github.com/org/repo.git' -AliasAttendu 'github-perso'
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
            # Sur le NOMBRE, pas sur la prose : le libelle est traduit, et l'agent de CI
            # ne parle pas la meme langue que le poste qui a ecrit le test.
            $r.Detail  | Should -Match '\b2\b'
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
    # NEUTRALISE LA MACHINE QUI EXECUTE CES TESTS.
    #
    # Une machine de developpeur porte presque toujours un fichier de reglages
    # d'agent quelque part ; une machine neuve n'en a aucun. Sans cette
    # isolation, ces tests mesuraient la machine plutot que le code : verts ici
    # depuis le premier jour, rouges le 18 aout 2026 sur l'agent de CI, ou
    # l'absence totale de reglages faisait rendre $null la ou l'appelant lisait
    # un .Count. Le cas vierge est le plus banal qui soit, et c'etait le seul
    # que la suite ne construisait jamais.
    BeforeEach {
        $script:DoctorConfigAvant = $env:CLAUDE_CONFIG_DIR
        $script:DoctorConfigVide = Join-Path $TestDrive ('cfg-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:DoctorConfigVide -Force
        $env:CLAUDE_CONFIG_DIR = $script:DoctorConfigVide
    }
    AfterEach {
        # Restaurer, jamais supprimer : effacer une vraie variable a deja
        # desarme en silence un test de fuite dans ce depot.
        if ($null -ne $script:DoctorConfigAvant) { $env:CLAUDE_CONFIG_DIR = $script:DoctorConfigAvant }
        else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
    }

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

Describe 'Test-CtxDoctorShimsDevant' {
    # ETRE DANS LE PATH NE SUFFIT PAS : encore faut-il y etre EN PREMIER.
    #
    # Windows compose le PATH systeme AVANT le PATH utilisateur, et
    # l'installateur ecrit dans le second pour ne demander aucun droit
    # administrateur. Un binaire installe pour toute la machine est donc resolu
    # avant nos shims -- sans que rien ne le signale.
    #
    # Mesure le 16 aout 2026 : gh installe par winget dans
    # C:\Program Files\GitHub CLI arrivait a l'index 10, nos shims a l'index 19.
    # Le garde-fou etait pose, annonce actif, et jamais atteint.
    #
    # Le resolveur est injecte : la decision se verifie donc sans dependre du
    # PATH de la machine qui fait tourner les tests.

    BeforeAll {
        $script:NosDossiers = @('D:\module\shims', 'C:\Users\moi\AppData\Local\DevContext\current\shims')
    }

    It 'ne dit rien quand nos shims sont bien en tete' {
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("$($d[0])\$n.cmd", "C:\Program Files\Truc\$n.exe") }
            Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d -PathUtilisateur @() -Resolveur $faux |
                Should -BeNullOrEmpty
        }
    }

    It 'SIGNALE un binaire systeme resolu avant le shim' {
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("C:\Program Files\GitHub CLI\$n.exe", "$($d[1])\$n.cmd") }
            $c = Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d -PathUtilisateur @() -Resolveur $faux
            $c.Verdict | Should -Be 'PROBLEME'
            $c.Detail  | Should -Match 'gh'
            $c.Detail  | Should -Match 'GitHub CLI'
        }
    }

    It 'reconnait nos dossiers sous CHACUN de leurs noms' {
        # Le shim peut etre resolu par la jonction alors que la liste connait le
        # dossier du module. Cinquieme site du meme defaut si on l'oubliait ici.
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("$($d[1])\$n.cmd", "C:\Program Files\Truc\$n.exe") }
            Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d -PathUtilisateur @() -Resolveur $faux |
                Should -BeNullOrEmpty
        }
    }

    It 'se tait quand l outil n est pas installe du tout' {
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d -PathUtilisateur @() -Resolveur { param($n) @() } |
                Should -BeNullOrEmpty
        }
    }

    It 'se tait quand le PATH entier manque, que l autre controle rapporte deja' {
        # Aucun de nos dossiers dans la resolution : c'est Test-CtxDoctorGardeFou
        # qui le dit. Deux constats pour une cause apprennent a lire en diagonale.
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("C:\Program Files\GitHub CLI\$n.exe") }
            Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d -PathUtilisateur @() -Resolveur $faux |
                Should -BeNullOrEmpty
        }
    }

    It 'nomme TOUS les outils masques, pas seulement le premier' {
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("C:\Program Files\$n\$n.exe", "$($d[0])\$n.cmd") }
            $c = Test-CtxDoctorShimsDevant -Outils @('gh', 'vercel') -Dossiers $d -PathUtilisateur @() -Resolveur $faux
            $c.Detail | Should -Match 'gh'
            $c.Detail | Should -Match 'vercel'
        }
    }

    It 'propose le RETRAIT quand le dossier est deja dans le PATH utilisateur' {
        # Le cas mesure le 17 aout 2026. Le diagnostic conseillait une
        # reinstallation alors que le dossier figurait DEJA dans le PATH
        # utilisateur, derriere les shims : retirer l'entree systeme redondante
        # suffisait. Un correctif trop cher est un correctif qu'on n'applique pas.
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("C:\Program Files\GitHub CLI\$n.exe", "$($d[1])\$n.cmd") }
            $c = Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d `
                -PathUtilisateur @($d[1], 'C:\Program Files\GitHub CLI\') -Resolveur $faux
            $c.Verdict   | Should -Be 'PROBLEME'
            $c.Correctif | Should -Match 'PATH SYSTEME|SYSTEM PATH'
            # Sur le NOM D'UN GESTIONNAIRE DE PAQUETS, et non sur le mot
            # "reinstaller" : le message leger dit justement "Rien a
            # reinstaller", et une assertion sur le verbe rougissait sur la
            # phrase qui rassure. Ce qui doit etre absent, c'est la CONSIGNE
            # d'aller reinstaller quelque chose.
            $c.Correctif | Should -Not -Match 'winget|scoop|npm install'
        }
    }

    It 'propose la portee utilisateur quand le dossier n est QUE dans le PATH systeme' {
        InModuleScope DevContext -Parameters @{ d = $script:NosDossiers } { param($d)
            $faux = { param($n) @("C:\Program Files\GitHub CLI\$n.exe", "$($d[1])\$n.cmd") }
            $c = Test-CtxDoctorShimsDevant -Outils @('gh') -Dossiers $d `
                -PathUtilisateur @($d[1]) -Resolveur $faux
            $c.Correctif | Should -Match 'portee utilisateur|user scope'
        }
    }
}

Describe 'Resolve-CtxMasqueCorrectif' {
    It 'reconnait le dossier malgre la casse et la barre finale' -ForEach @(
        @{ Dossier = 'C:\Program Files\GitHub CLI'; Entree = 'C:\Program Files\GitHub CLI\' }
        @{ Dossier = 'C:\Program Files\GitHub CLI\'; Entree = 'c:\program files\github cli' }
        @{ Dossier = 'C:\PROGRAM FILES\GITHUB CLI'; Entree = 'C:\Program Files\GitHub CLI' }
    ) {
        # Windows ecrit ces trois formes indifferemment, et les trois designent
        # le meme dossier. Comparer les chaines brutes conseillerait une
        # reinstallation a cause d'une barre obliques finale.
        InModuleScope DevContext -Parameters @{ D = $Dossier; E = $Entree } { param($D, $E)
            Resolve-CtxMasqueCorrectif -Dossier $D -PathUtilisateur @($E) | Should -Be 'retrait-systeme'
        }
    }

    It 'rend portee-utilisateur quand le dossier est absent du PATH utilisateur' {
        InModuleScope DevContext {
            Resolve-CtxMasqueCorrectif -Dossier 'C:\Program Files\GitHub CLI' `
                -PathUtilisateur @('C:\autre', 'D:\encore') | Should -Be 'portee-utilisateur'
        }
    }

    It 'ne suppose rien sur un dossier vide ou un PATH utilisateur absent' {
        InModuleScope DevContext {
            Resolve-CtxMasqueCorrectif -Dossier '' -PathUtilisateur @('C:\x') | Should -Be 'portee-utilisateur'
            Resolve-CtxMasqueCorrectif -Dossier 'C:\x' | Should -Be 'portee-utilisateur'
            Resolve-CtxMasqueCorrectif -Dossier 'C:\x' -PathUtilisateur @($null, '') | Should -Be 'portee-utilisateur'
        }
    }
}

Describe 'Test-CtxDoctorEditeurConnexions' {
    # Le rapport disait "profil par contexte -- OK", et VS Code demandait quand
    # meme de se connecter. Les deux etaient vrais : un profil isole EST un
    # magasin de secrets isole, donc une connexion a ouvrir dans chaque contexte.
    # Ce que le rapport ne disait pas, c'est la seconde moitie.

    It 'enonce la consequence des qu au moins un editeur est isole' {
        InModuleScope DevContext {
            $c = Test-CtxDoctorEditeurConnexions -Editeurs @(
                [pscustomobject]@{ Isole = $true; Commande = 'code' }
                [pscustomobject]@{ Isole = $false; Commande = 'trae' }
            )
            $c.Verdict | Should -Be 'INFO'
            $c.Domaine | Should -Be 'editeur'
            $c.Sujet   | Should -Be 'connexions'
            $c.Detail  | Should -Not -BeNullOrEmpty
        }
    }

    It 'se tait quand AUCUN editeur n est isole -- la phrase serait fausse' {
        InModuleScope DevContext {
            Test-CtxDoctorEditeurConnexions -Editeurs @(
                [pscustomobject]@{ Isole = $false; Commande = 'code' }
            ) | Should -BeNullOrEmpty

            Test-CtxDoctorEditeurConnexions -Editeurs @() | Should -BeNullOrEmpty
        }
    }

    It 'juge sur le booleen Isole, jamais sur un libelle traduit' {
        # Quatre occurrences de ce defaut dans ce depot : du code qui compare un
        # litteral francais a un champ devenu traduit, et qui devient faux des
        # que la sortie passe en anglais.
        InModuleScope DevContext {
            $c = Test-CtxDoctorEditeurConnexions -Editeurs @(
                [pscustomobject]@{ Isole = $true; Profil = 'isolated profile'; Commande = 'code' }
            )
            $c | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Test-CtxDoctorIdentiteGit, quand la BONNE valeur vient du mauvais endroit' {
    # LA TROUVAILLE DU 18 AOUT 2026, remontee par l'agent d'un projet client.
    #
    # Un `user.email` ecrit dans le .git/config d'un depot PRIME sur la regle
    # `includeIf` par chemin. Tant qu'il porte la bonne adresse, rien ne se voit
    # -- et c'est le probleme : ce qui protege ce depot est une ligne recopiee a
    # la main, pas le mecanisme dont ce module fait sa promesse.
    #
    # Mesure sur la machine de l'auteur le meme jour : SIX depots dans ce cas.
    # Cinq portaient la bonne valeur, un portait l'adresse d'un autre compte --
    # et `ctx` repondait GO sur les six, parce qu'il ne comparait que la valeur.
    # La regle par dossier etait morte dans un quart des depots, en silence.

    It 'rend ATTENTION quand l email est bon mais ecrit en dur dans le depot' {
        InModuleScope DevContext {
            $r = Test-CtxDoctorIdentiteGit -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' `
                -Origine '.git/config'
            $r.Verdict | Should -Be 'ATTENTION'
            $r.Detail  | Should -Match 'a@b\.c'
            $r.Correctif | Should -Match 'unset'
        }
    }

    It 'reconnait les deux separateurs de chemin' {
        # git rend des slashes sur Windows aujourd'hui. Faire dependre un
        # controle de cette habitude est le genre d'hypothese qui casse ailleurs.
        InModuleScope DevContext {
            foreach ($o in 'C:/projets/monapp/.git/config', 'C:\projets\monapp\.git\config', '.git\config') {
                (Test-CtxDoctorIdentiteGit -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' -Origine $o).Verdict |
                    Should -Be 'ATTENTION' -Because "l origine '$o' designe le .git/config du depot"
            }
        }
    }

    It 'reste OK quand l email vient du fichier du contexte' {
        # LE CONTROLE NEGATIF. Un correctif qui rendrait ATTENTION partout ne
        # serait pas un correctif : ce serait un bruit de fond, et un bruit de
        # fond finit ignore comme un verdict qu'on ne peut pas effacer.
        InModuleScope DevContext {
            foreach ($o in 'F:/CTX/perso/gitconfig', 'C:/Users/thier/.gitconfig', 'x') {
                (Test-CtxDoctorIdentiteGit -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' -Origine $o).Verdict |
                    Should -Be 'OK' -Because "l origine '$o' n est pas le .git/config d un depot"
            }
        }
    }

    It 'ne se laisse pas prendre par un chemin qui RESSEMBLE au .git/config' {
        InModuleScope DevContext {
            foreach ($o in 'C:/x/.git/config.bak', 'C:/x/git/config', 'C:/x/.gitconfig') {
                (Test-CtxDoctorIdentiteGit -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' -Origine $o).Verdict |
                    Should -Be 'OK' -Because "'$o' n est pas le .git/config d un depot"
            }
        }
    }

    It 'laisse PROBLEME l emporter quand la valeur est fausse' {
        # L'ordre compte : une mauvaise valeur reste un PROBLEME, meme ecrite au
        # meme endroit. Le nouveau verdict ne parle que du cas ou tout va bien.
        InModuleScope DevContext {
            (Test-CtxDoctorIdentiteGit -EmailAttendu 'perso@x.be' -EmailReel 'pro@client.com' `
                -Origine '.git/config').Verdict | Should -Be 'PROBLEME'
        }
    }
}
