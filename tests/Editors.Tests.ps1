# Tests for editor isolation.
#
# Everything that DECIDES is exercised without an editor installed. That is the
# whole point of the pure/gathering split: this suite must give the same verdict
# on a CI runner with no GUI, on a machine carrying five editors, and on
# somebody else's laptop carrying two we have never heard of.
#
# The probe itself -- the half that runs a binary -- is covered by asserting the
# RULE it applies (a flag counts only when the directory it names appeared),
# never by running a real editor.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Find-CtxEditorCli ecarte nos shims sous TOUS leurs noms' {
    # POURQUOI CE BLOC EXISTE. Le 16 aout 2026, chaque raccourci du Bureau
    # laissait une fenetre PowerShell ouverte pour toute la session VS Code.
    #
    # Chaine complete : cette fonction ecartait les shims en comparant UN chemin,
    # celui du module. Depuis que PATH designe la jonction, le meme dossier porte
    # un autre nom -- les deux chaines different, le shim ne se reconnaissait plus
    # et devenait « le CLI de VS Code ». Find-CtxEditorExecutable remontait alors
    # depuis ...\current\shims sans y trouver de Code.exe, et Open-DevCode tombait
    # sur sa branche de repli, SYNCHRONE.
    #
    # Exactement le defaut corrige la veille sur Get-CtxSupabaseExe, et jamais
    # reporte ici : cette fonction n'avait aucun test, alors que sa seule raison
    # d'etre est « ne pas se prendre pour l'editeur ».

    It 'rend le vrai CLI quand les deux noms du dossier de shims sont dans PATH' {
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'code' } {
                @(
                    [pscustomobject]@{ Source = (Join-Path (Get-CtxShimStable) 'code.cmd') }
                    [pscustomobject]@{ Source = (Join-Path $script:ShimDir 'code.cmd') }
                    [pscustomobject]@{ Source = 'C:\Programs\Microsoft VS Code\bin\code.cmd' }
                )
            }
            Find-CtxEditorCli -Name 'code' | Should -Be 'C:\Programs\Microsoft VS Code\bin\code.cmd'
        }
    }

    It 'ecarte un dossier de shims atteint sous un troisieme nom' {
        # Celui qu'aucune liste ne peut prevoir : une entree PATH ecrite a la
        # main, un lecteur subst, un chemin UNC vers le meme dossier.
        $faux = Join-Path $TestDrive 'shims-par-un-autre-chemin'
        New-Item -ItemType Directory -Path $faux | Out-Null
        Set-Content -LiteralPath (Join-Path $faux 'editor.ps1')   -Value '# marqueur'
        Set-Content -LiteralPath (Join-Path $faux 'supabase.ps1') -Value '# marqueur'

        InModuleScope DevContext -Parameters @{ d = $faux } { param($d)
            Mock Get-Command -ParameterFilter { $Name -eq 'code' } {
                @(
                    [pscustomobject]@{ Source = (Join-Path $d 'code.cmd') }
                    [pscustomobject]@{ Source = 'C:\Programs\Microsoft VS Code\bin\code.cmd' }
                )
            }
            Find-CtxEditorCli -Name 'code' | Should -Be 'C:\Programs\Microsoft VS Code\bin\code.cmd'
        }
    }

    It 'ne rend rien plutot qu un shim quand il ne reste que les notres' {
        # Rendre un shim ici, c'est Open-DevCode qui appelle son propre shim :
        # l'editeur s'ouvre, mais la fenetre appelante ne se ferme plus.
        InModuleScope DevContext {
            Mock Get-Command -ParameterFilter { $Name -eq 'code' } {
                @([pscustomobject]@{ Source = (Join-Path (Get-CtxShimStable) 'code.cmd') })
            }
            Find-CtxEditorCli -Name 'code' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Resolve-CtxEditorTargetPath' {
    BeforeAll {
        # A fake filesystem. The function must never touch the real one, and a
        # test that needed a project on disk would prove nothing about someone
        # else's machine.
        $script:Faux = {
            param($p)
            $n = $p -replace '/', '\'
            if ($n -match '\\COMMIT_EDITMSG$' -or $n -match '\.ts$' -or $n -match '\.md$') { return 'file' }
            if ($n -match '^F:\\PROJECTS\\Apps(\\|$)') { return 'directory' }
            if ($n -match '^F:\\PROJECTS\\Clients(\\|$)') { return 'directory' }
            'absent'
        }
    }

    It 'prend le dossier courant quand aucun chemin n est donne' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('--version') -WorkingDirectory 'F:\PROJECTS\Apps\demo' -Classify $f |
                Should -Be 'F:\PROJECTS\Apps\demo'
        }
    }

    It 'resout un point sans laisser de segment relatif' {
        # `code .` donnait 'F:\projet\.', que chaque comparaison de prefixe du
        # module devait ensuite encaisser.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('.') -WorkingDirectory 'F:\PROJECTS\Apps\demo' -Classify $f |
                Should -Be 'F:\PROJECTS\Apps\demo'
        }
    }

    It 'remonte au dossier quand la cible est un fichier' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('F:\PROJECTS\Apps\demo\src\main.ts') `
                -WorkingDirectory 'C:\ailleurs' -Classify $f | Should -Be 'F:\PROJECTS\Apps\demo\src'
        }
    }

    It 'suit le projet OUVERT, pas le dossier depuis lequel on tape' {
        # LA propriete. Ouvrir un projet client depuis un dossier perso doit
        # charger l identite client, sans quoi ce shim reproduit exactement le
        # bug qu il existe pour corriger.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('F:\PROJECTS\Clients\acme\site') `
                -WorkingDirectory 'F:\PROJECTS\Apps\perso-a-moi' -Classify $f |
                Should -Be 'F:\PROJECTS\Clients\acme\site'
        }
    }

    It 'ne prend pas la valeur d un flag pour une cible : --log trace .' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('--log', 'trace', '.') `
                -WorkingDirectory 'F:\PROJECTS\Apps\demo' -Classify $f | Should -Be 'F:\PROJECTS\Apps\demo'
        }
    }

    It 'traite --flag=valeur sans avaler l argument suivant' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('--log=trace', 'F:\PROJECTS\Clients\acme') `
                -WorkingDirectory 'C:\ailleurs' -Classify $f | Should -Be 'F:\PROJECTS\Clients\acme'
        }
    }

    It 'retire le suffixe ligne:colonne de -g' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('-g', 'F:\PROJECTS\Apps\demo\a.ts:42:7') `
                -WorkingDirectory 'C:\ailleurs' -Classify $f | Should -Be 'F:\PROJECTS\Apps\demo'
        }
    }

    It 'gere le cas de git : --wait sur un fichier de message' {
        # `code --wait COMMIT_EDITMSG` est l editeur de git. Se tromper de
        # contexte ici, c est signer un commit avec la mauvaise identite.
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('--wait', '.git\COMMIT_EDITMSG') `
                -WorkingDirectory 'F:\PROJECTS\Clients\acme' -Classify $f |
                Should -Be 'F:\PROJECTS\Clients\acme\.git'
        }
    }

    It 'ignore un chemin inexistant plutot que de l inventer' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @('Z:\jamais\vu') `
                -WorkingDirectory 'F:\PROJECTS\Apps\demo' -Classify $f | Should -Be 'F:\PROJECTS\Apps\demo'
        }
    }

    It 'accepte une liste d arguments vide' {
        InModuleScope DevContext -Parameters @{ f = $script:Faux } { param($f)
            Resolve-CtxEditorTargetPath -Arguments @() -WorkingDirectory 'F:\PROJECTS\Apps\demo' -Classify $f |
                Should -Be 'F:\PROJECTS\Apps\demo'
        }
    }
}

Describe 'Resolve-CtxEditorArguments' {
    BeforeAll {
        $script:Plein  = [pscustomobject]@{ UserDataDir = $true;  ExtensionsDir = $true }
        $script:Profil = [pscustomobject]@{ UserDataDir = $true;  ExtensionsDir = $false }
        $script:Aucune = [pscustomobject]@{ UserDataDir = $false; ExtensionsDir = $false }
    }

    It 'injecte les deux flags quand ils sont supportes' {
        InModuleScope DevContext -Parameters @{ c = $script:Plein } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'vscode' -Arguments @('.')
            $r -join ' ' | Should -Be '--user-data-dir F:\CTX\perso\vscode --extensions-dir F:\CTX\perso\vscode-ext .'
        }
    }

    It 'n injecte PAS un flag que l editeur ignore' {
        # Antigravity accepte --user-data-dir et n a pas --extensions-dir.
        # Le passer quand meme se lit comme de l isolation dans le raccourci,
        # alors que les extensions restent partagees.
        InModuleScope DevContext -Parameters @{ c = $script:Profil } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'antigravity' -Arguments @('.')
            $r | Should -Not -Contain '--extensions-dir'
            $r | Should -Contain '--user-data-dir'
        }
    }

    It 'ne touche a rien quand l editeur ne supporte aucun flag' {
        InModuleScope DevContext -Parameters @{ c = $script:Aucune } { param($c)
            (Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'x' -Arguments @('--wait', '.')) -join ' ' |
                Should -Be '--wait .'
        }
    }

    It 'laisse gagner un appelant qui a pose le flag lui-meme' {
        InModuleScope DevContext -Parameters @{ c = $script:Plein } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'vscode' `
                -Arguments @('--user-data-dir', 'A_MOI', '.')
            @($r | Where-Object { $_ -eq '--user-data-dir' }).Count | Should -Be 1
            $r | Should -Contain 'A_MOI'
        }
    }

    It 'reconnait aussi la forme --flag=valeur de l appelant' {
        InModuleScope DevContext -Parameters @{ c = $script:Plein } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'vscode' `
                -Arguments @('--user-data-dir=A_MOI', '.')
            $r | Should -Not -Contain '--user-data-dir'
        }
    }

    It 'preserve l ordre et le contenu des arguments de l appelant' {
        # --wait, --diff, -g : git et les scripts en dependent au caractere pres.
        InModuleScope DevContext -Parameters @{ c = $script:Plein } { param($c)
            $depart = @('--wait', '--diff', 'a.txt', 'b.txt')
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'vscode' -Arguments $depart
            ($r[-4..-1]) -join ' ' | Should -Be ($depart -join ' ')
        }
    }

    It 'construit le chemin meme quand le lecteur n existe pas' {
        # LE piege. Join-Path est un cmdlet de FOURNISSEUR : il resout le
        # lecteur et echoue sur « Cannot find drive » quand il n'est pas monte.
        # Sans -ErrorAction Stop il ne leve pas — il rend une chaine VIDE, et la
        # commande partait avec « --user-data-dir --extensions-dir . », ou le
        # flag suivant est lu comme la valeur du precedent.
        #
        # Invisible ici, ou F: existe. Rouge sur l'agent de CI, ou il n'existe
        # pas. C'est exactement la classe de defaut qui n'apparait que chez
        # quelqu'un d'autre — et la raison d'etre de ce test : il echoue sur le
        # code d'avant, ici comme ailleurs.
        InModuleScope DevContext -Parameters @{ c = $script:Plein } { param($c)
            $lecteurAbsent = 'Q:\CTX\perso'
            Test-Path -LiteralPath 'Q:\' | Should -BeFalse -Because 'ce test suppose Q: non monte'

            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir $lecteurAbsent `
                -ProfileName 'vscode' -Arguments @('.')

            ($r -join ' ') | Should -Be `
                '--user-data-dir Q:\CTX\perso\vscode --extensions-dir Q:\CTX\perso\vscode-ext .'

            # Et la propriete qui rend le defaut dangereux, nommee explicitement :
            # un flag ne doit jamais etre suivi d'un autre flag, car le second
            # serait alors lu comme la valeur du premier.
            for ($i = 0; $i -lt $r.Count - 1; $i++) {
                if ("$($r[$i])".StartsWith('--')) {
                    "$($r[$i + 1])" | Should -Not -BeNullOrEmpty
                    "$($r[$i + 1])" | Should -Not -Match '^--'
                }
            }
        }
    }

    It 'resout une cible relative meme sur un lecteur absent' {
        InModuleScope DevContext {
            $faux = { param($p) if ($p -match 'Q:') { 'directory' } else { 'absent' } }
            Resolve-CtxEditorTargetPath -Arguments @('projet') -WorkingDirectory 'Q:\travail' -Classify $faux |
                Should -Be 'Q:\travail\projet'
        }
    }

    It 'place les flags injectes AVANT les arguments de l appelant' {
        InModuleScope DevContext -Parameters @{ c = $script:Profil } { param($c)
            (Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' -ProfileName 'vscode' -Arguments @('.'))[0] |
                Should -Be '--user-data-dir'
        }
    }
}

Describe 'Test-CtxEditorProbeResult' {
    It 'ne conclut au support QUE si le dossier est apparu' {
        # Le code de sortie ne prouve rien : tous ces editeurs acceptent un flag
        # inconnu et sortent 0. Antigravity l a fait avec --extensions-dir.
        InModuleScope DevContext {
            $r = Test-CtxEditorProbeResult -ExitCode 0 -ProfileCreated $true -ExtensionsCreated $false
            $r.UserDataDir   | Should -BeTrue
            $r.ExtensionsDir | Should -BeFalse
            $r.Method        | Should -Be 'measured'
        }
    }

    It 'ne conclut a rien sur une sortie 0 sans effet sur le disque' {
        InModuleScope DevContext {
            $r = Test-CtxEditorProbeResult -ExitCode 0 -ProfileCreated $false -ExtensionsCreated $false
            $r.UserDataDir | Should -BeFalse
        }
    }
}

Describe 'Test-CtxEditorDeclaredFlags' {
    It 'lit les flags presents dans le binaire' {
        InModuleScope DevContext {
            $r = Test-CtxEditorDeclaredFlags -Content 'blah --user-data-dir blah'
            $r.UserDataDir   | Should -BeTrue
            $r.ExtensionsDir | Should -BeFalse
            $r.Method        | Should -Be 'declared'
        }
    }

    It 'distingue declare de mesure' {
        # La distinction est le contrat : declare est plus faible que mesure, et
        # l afficher pareil reviendrait a promettre ce qu on n a pas verifie.
        InModuleScope DevContext {
            (Test-CtxEditorDeclaredFlags -Content 'x').Method | Should -Not -Be 'measured'
        }
    }

    It 'accepte un contenu nul sans lever' {
        InModuleScope DevContext {
            { Test-CtxEditorDeclaredFlags -Content $null } | Should -Not -Throw
            (Test-CtxEditorDeclaredFlags -Content $null).UserDataDir | Should -BeFalse
        }
    }
}

Describe 'Get-CtxEditorHints' {
    It 'porte des indices, pas une table de verite' {
        InModuleScope DevContext {
            $noms = @(Get-CtxEditorHints -ContextRoot $TestDrive | ForEach-Object Name)
            $noms | Should -Contain 'code'
            $noms | Should -Contain 'cursor'
        }
    }

    It 'laisse un editeur declare par l utilisateur passer devant' {
        # Quelqu un qui prend la peine de nommer sa propre installation veut
        # qu elle gagne sur un indice qui partage le nom.
        InModuleScope DevContext {
            $d = Join-Path $TestDrive 'racine-declare'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            '[{"name":"code","label":"Mon build","profile":"a-moi"}]' |
                Set-Content (Join-Path $d 'editors.json') -Encoding UTF8
            $code = @(Get-CtxEditorHints -ContextRoot $d | Where-Object Name -eq 'code')
            $code.Count      | Should -Be 1
            $code[0].Label   | Should -Be 'Mon build'
            $code[0].Profile | Should -Be 'a-moi'
        }
    }

    It 'survit a un editors.json illisible' {
        # Un fichier casse ne doit pas emporter les indices integres avec lui.
        InModuleScope DevContext {
            $d = Join-Path $TestDrive 'racine-cassee'
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            '{ ceci n est pas du json' | Set-Content (Join-Path $d 'editors.json') -Encoding UTF8
            @(Get-CtxEditorHints -ContextRoot $d).Count | Should -BeGreaterThan 0
        }
    }

    It 'garde vscode comme dossier de profil pour code' {
        # Open-DevCode y ecrit depuis aout 2026 et de vraies sessions y vivent.
        # Renommer le dossier pour faire propre deconnecterait tout le monde de
        # tous ses contextes d un coup — la panne meme que ce module previent,
        # provoquee par sa correction.
        InModuleScope DevContext {
            (Get-CtxEditorHints -ContextRoot $TestDrive | Where-Object Name -eq 'code').Profile |
                Should -Be 'vscode'
        }
    }
}

Describe 'Get-CtxEditorCacheKey' {
    It 'change quand l editeur est mis a jour' {
        # Sans l horodatage, un editeur qui gagne un flag en se mettant a jour
        # garderait pour toujours le verdict de sa version precedente.
        InModuleScope DevContext {
            $f = Join-Path $TestDrive 'faux-editeur.cmd'
            'rem' | Set-Content $f
            $e = [pscustomobject]@{ Name = 'faux'; Cli = $f; Exe = $null }
            $avant = Get-CtxEditorCacheKey -Editor $e
            (Get-Item $f).LastWriteTimeUtc = (Get-Item $f).LastWriteTimeUtc.AddHours(1)
            Get-CtxEditorCacheKey -Editor $e | Should -Not -Be $avant
        }
    }
}

Describe 'Get-CtxNormalizedPath' {
    It 'effondre <_> sans interroger le disque' -ForEach @(
        @{ Entree = 'F:\a\b\.';    Attendu = 'F:\a\b' }
        @{ Entree = 'F:\a\b\..\c'; Attendu = 'F:\a\c' }
        @{ Entree = 'F:\a\b';      Attendu = 'F:\a\b' }
    ) {
        InModuleScope DevContext -Parameters @{ e = $Entree; a = $Attendu } { param($e, $a)
            Get-CtxNormalizedPath $e | Should -Be $a
        }
    }
}

Describe 'points d entree generes' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..' 'installer-shims.ps1') -AsLibrary
    }

    It 'passe le nom de l editeur par l environnement, jamais par les arguments' {
        # Le flux d arguments appartient a l appelant et doit atteindre
        # l editeur intact : `code --wait COMMIT_EDITMSG` est l editeur de git.
        $c = New-CtxEntryPointContent -Nom 'cursor'
        $c.Cmd   | Should -Match 'DEVCTX_SHIM_EDITOR=cursor'
        $c.Cmd   | Should -Match '%\*'
        $c.Posix | Should -Match 'DEVCTX_SHIM_EDITOR=cursor'
        $c.Posix | Should -Match '"\$@"'
    }

    It 'cloisonne la variable dans le .cmd' {
        # Sans setlocal, DEVCTX_SHIM_EDITOR fuit dans la session cmd appelante
        # et le shim suivant heriterait du mauvais editeur.
        (New-CtxEntryPointContent -Nom 'code').Cmd | Should -Match 'setlocal'
    }

    It 'ecrit le .cmd en CRLF et le POSIX en LF' {
        # Un `#!/bin/sh` termine en CRLF echoue sur « bad interpreter: /bin/sh^M »,
        # une erreur qui nomme l interpreteur plutot que la cause.
        $c = New-CtxEntryPointContent -Nom 'code'
        $c.Cmd   | Should -Match "`r`n"
        $c.Posix | Should -Not -Match "`r"
    }

    It 'porte la marque qui autorise sa suppression' {
        (New-CtxEntryPointContent -Nom 'code').Cmd | Should -Match 'GENERE PAR DEVCONTEXT'
    }
}

Describe 'Sync-CtxEditorEntryPoints' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..' 'installer-shims.ps1') -AsLibrary
    }

    It 'ecrit les deux points d entree par editeur' {
        $d = Join-Path $TestDrive 'sync-ecrit'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $r = Sync-CtxEditorEntryPoints -Noms @('code', 'cursor') -Dossier $d
        $r.Ecrits.Count | Should -Be 4
        foreach ($f in 'code', 'code.cmd', 'cursor', 'cursor.cmd') {
            Test-Path (Join-Path $d $f) | Should -BeTrue
        }
    }

    It 'retire le point d entree d un editeur desinstalle' {
        $d = Join-Path $TestDrive 'sync-retire'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Sync-CtxEditorEntryPoints -Noms @('code', 'cursor') -Dossier $d | Out-Null
        $r = Sync-CtxEditorEntryPoints -Noms @('code') -Dossier $d
        Test-Path (Join-Path $d 'cursor.cmd') | Should -BeFalse
        Test-Path (Join-Path $d 'code.cmd')   | Should -BeTrue
        $r.Retires.Count | Should -Be 2
    }

    It 'ne supprime JAMAIS un fichier qu il n a pas ecrit' {
        # L installateur qui efface par motif de nom finit par effacer le
        # fichier de quelqu un d autre. Seule la marque autorise la suppression.
        $d = Join-Path $TestDrive 'sync-etranger'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Sync-CtxEditorEntryPoints -Noms @('code') -Dossier $d | Out-Null
        'un script a moi' | Set-Content (Join-Path $d 'perso.cmd')
        Sync-CtxEditorEntryPoints -Noms @() -Dossier $d | Out-Null
        Test-Path (Join-Path $d 'perso.cmd') | Should -BeTrue
        Test-Path (Join-Path $d 'code.cmd')  | Should -BeFalse
    }

    It 'ne touche pas aux fichiers livres avec le depot' {
        $d = Join-Path $TestDrive 'sync-livres'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        foreach ($f in 'supabase.ps1', 'supabase.cmd', 'supabase', 'editor.ps1') {
            "contenu livre : $f" | Set-Content (Join-Path $d $f)
        }
        Sync-CtxEditorEntryPoints -Noms @() -Dossier $d | Out-Null
        foreach ($f in 'supabase.ps1', 'supabase.cmd', 'supabase', 'editor.ps1') {
            Test-Path (Join-Path $d $f) | Should -BeTrue
        }
    }

    It 'est idempotent' {
        $d = Join-Path $TestDrive 'sync-idem'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Sync-CtxEditorEntryPoints -Noms @('code') -Dossier $d | Out-Null
        $avant = Get-Content (Join-Path $d 'code.cmd') -Raw
        $r = Sync-CtxEditorEntryPoints -Noms @('code') -Dossier $d
        $r.Retires.Count | Should -Be 0
        Get-Content (Join-Path $d 'code.cmd') -Raw | Should -Be $avant
    }
}

Describe 'isolement du stockage PARTAGE (--shared-data-dir)' {
    # LA TROUVAILLE DU 19 AOUT 2026, sur la machine de l'auteur.
    #
    # VS Code 1.133 a sorti le stockage « application » du --user-data-dir. Les
    # SECRETS des extensions, la liste des dossiers recents et celle des
    # dossiers approuves vivent desormais dans un magasin COMMUN A LA MACHINE :
    #
    #   get appSharedDataHome() {
    #     const dir = this.args["shared-data-dir"];
    #     if (dir) return URI.file(resolve(dir));
    #     return joinPath(this.userHome, ".vscode-shared");
    #   }
    #
    # Le chiffrement, lui, est reste PAR PROFIL. Deux contextes ecrivent donc la
    # meme entree avec deux cles differentes ; le suivant n'arrive plus a la
    # lire, l'editeur jette l'entree et redemande une connexion. Mesure sur six
    # demarrages : les six ou « Error while decrypting the ciphertext » apparait
    # sont exactement les six ou zero session est relue. Le seul demarrage sans
    # cette erreur est le seul ou les connexions ont survecu.
    #
    # Le cout n'est pas que l'agacement. Le chemin d'un projet CLIENT se
    # retrouvait dans la liste des dossiers recents d'une fenetre PERSO, et un
    # dossier approuve dans un contexte l'etait dans tous.

    BeforeAll {
        $script:Tout = [pscustomobject]@{
            UserDataDir = $true; ExtensionsDir = $true; SharedDataDir = $true
        }
        $script:SansPartage = [pscustomobject]@{
            UserDataDir = $true; ExtensionsDir = $true; SharedDataDir = $false
        }
    }

    It 'injecte --shared-data-dir dans le contexte quand l editeur le supporte' {
        InModuleScope DevContext -Parameters @{ c = $script:Tout } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' `
                -ProfileName 'vscode' -Arguments @('.')
            $r -join ' ' | Should -Be ('--user-data-dir F:\CTX\perso\vscode ' +
                '--extensions-dir F:\CTX\perso\vscode-ext ' +
                '--shared-data-dir F:\CTX\perso\vscode-shared .')
        }
    }

    It 'n injecte rien quand l editeur ne connait pas le flag' {
        # Meme regle que pour --extensions-dir : un flag ignore se lit comme de
        # l'isolation dans le raccourci, alors que le magasin reste commun.
        InModuleScope DevContext -Parameters @{ c = $script:SansPartage } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' `
                -ProfileName 'vscode' -Arguments @('.')
            $r | Should -Not -Contain '--shared-data-dir'
        }
    }

    It 'n injecte rien pour une capacite ABSENTE de l objet' {
        # Le controle negatif qui protege les appelants d'avant ce champ : une
        # capacite absente n'est pas une capacite fausse, mais elle ne doit
        # surtout pas devenir une capacite VRAIE par defaut.
        InModuleScope DevContext {
            $ancien = [pscustomobject]@{ UserDataDir = $true; ExtensionsDir = $true }
            $r = Resolve-CtxEditorArguments -Capabilities $ancien -ContextDir 'F:\CTX\perso' `
                -ProfileName 'vscode' -Arguments @('.')
            $r | Should -Not -Contain '--shared-data-dir'
        }
    }

    It 'laisse gagner un appelant qui a pose le flag lui-meme' {
        InModuleScope DevContext -Parameters @{ c = $script:Tout } { param($c)
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'F:\CTX\perso' `
                -ProfileName 'vscode' -Arguments @('--shared-data-dir', 'A_MOI', '.')
            @($r | Where-Object { $_ -eq '--shared-data-dir' }).Count | Should -Be 1
            $r | Should -Contain 'A_MOI'
        }
    }

    It 'construit le chemin meme quand le lecteur n existe pas' {
        # Meme piege que pour les deux autres flags : Join-Path est un cmdlet de
        # FOURNISSEUR et rend une chaine VIDE sur un lecteur non monte, ce qui
        # ferait lire le flag suivant comme la valeur du precedent.
        InModuleScope DevContext -Parameters @{ c = $script:Tout } { param($c)
            Test-Path -LiteralPath 'Q:\' | Should -BeFalse -Because 'ce test suppose Q: non monte'
            $r = Resolve-CtxEditorArguments -Capabilities $c -ContextDir 'Q:\CTX\perso' `
                -ProfileName 'vscode' -Arguments @('.')
            $r | Should -Contain 'Q:\CTX\perso\vscode-shared'
            for ($i = 0; $i -lt $r.Count - 1; $i++) {
                if ($r[$i] -like '--*') {
                    $r[$i + 1] | Should -Not -BeLike '--*' -Because "le flag $($r[$i]) doit etre suivi de sa valeur"
                }
            }
        }
    }
}

Describe 'Test-CtxEditorDeclaredFlags, sur le flag de stockage partage' {
    It 'lit --shared-data-dir quand il est declare' {
        InModuleScope DevContext {
            (Test-CtxEditorDeclaredFlags -Content 'blah "shared-data-dir":{"type":"string"} blah').SharedDataDir |
                Should -BeTrue
        }
    }

    It 'ne deduit PAS le flag partage de la presence de --user-data-dir' {
        # Le controle negatif. Les deux chaines se ressemblent assez pour qu'une
        # recherche trop large les confonde, et un editeur qui n'a que le
        # premier serait alors declare isole sur une couche qu'il partage.
        InModuleScope DevContext {
            $r = Test-CtxEditorDeclaredFlags -Content 'user-data-dir extensions-dir extensions-download-dir'
            $r.UserDataDir   | Should -BeTrue
            $r.ExtensionsDir | Should -BeTrue
            $r.SharedDataDir | Should -BeFalse
        }
    }

    It 'accepte un contenu nul sans lever' {
        InModuleScope DevContext {
            (Test-CtxEditorDeclaredFlags -Content $null).SharedDataDir | Should -BeFalse
        }
    }
}

Describe 'Get-CtxEditorCapabilitiesCached, face a un cache ecrit AVANT ce champ' {
    # LE DEFAUT QUE CE TEST EXISTE POUR ATTRAPER, et il serait silencieux.
    #
    # Le cache est un JSON relu en table de hachage. Y lire une cle absente ne
    # LEVE pas : cela rend $null, que [bool] transforme en $false. Une entree
    # ecrite avant l'ajout de SharedDataDir aurait donc repondu « cet editeur ne
    # sait pas isoler son magasin partage » -- avec l'autorite d'une mesure, et
    # pour toujours, puisque rien dans la cle n'aurait change.
    #
    # La cle porte donc un numero de schema. Le prix d'un changement de schema
    # est une sonde de plus, une seule fois, par editeur.

    It 'ne sert pas une entree ecrite sous l ancienne forme de cle' {
        InModuleScope DevContext {
            $racine = Join-Path $TestDrive 'ctxroot'
            New-Item -ItemType Directory -Path $racine -Force | Out-Null

            $faux = Join-Path $TestDrive 'faux-editeur.cmd'
            'rem' | Set-Content -LiteralPath $faux
            $editeur = [pscustomobject]@{ Name = 'faux'; Cli = $faux; Exe = $null; Root = $null }

            # L'ancienne cle, telle qu'elle etait construite avant ce changement.
            $stamp = (Get-Item -LiteralPath $faux).LastWriteTimeUtc.ToString('o')
            $ancienneCle = '{0}|{1}|{2}' -f $editeur.Name, $faux, $stamp
            @{ $ancienneCle = @{
                    UserDataDir = $true; ExtensionsDir = $true; Method = 'measured'; ExitCode = 0
                }
            } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $racine 'editors.cache.json') -Encoding UTF8

            Mock Test-CtxEditorCapabilities {
                [pscustomobject]@{
                    UserDataDir = $true; ExtensionsDir = $true; SharedDataDir = $true
                    Method      = 'measured'; SharedDataMethod = 'declared'; ExitCode = 0
                }
            }

            $caps = Get-CtxEditorCapabilitiesCached -Editor $editeur -ContextRoot $racine

            $caps.SharedDataDir | Should -BeTrue -Because 'une entree sans ce champ doit etre ignoree, pas lue comme un refus'
            Should -Invoke Test-CtxEditorCapabilities -Times 1 -Exactly
        }
    }

    It 'sert bien une entree ecrite sous la forme courante' {
        # Le pendant : invalider TOUT le cache a chaque lecture couterait une
        # sonde par lancement d'editeur, ce que le cache existe precisement pour
        # eviter.
        InModuleScope DevContext {
            $racine = Join-Path $TestDrive 'ctxroot2'
            New-Item -ItemType Directory -Path $racine -Force | Out-Null

            $faux = Join-Path $TestDrive 'faux-editeur2.cmd'
            'rem' | Set-Content -LiteralPath $faux
            $editeur = [pscustomobject]@{ Name = 'faux2'; Cli = $faux; Exe = $null; Root = $null }

            @{ (Get-CtxEditorCacheKey -Editor $editeur) = @{
                    UserDataDir = $true; ExtensionsDir = $true; SharedDataDir = $true
                    Method      = 'measured'; SharedDataMethod = 'declared'; ExitCode = 0
                }
            } | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath (Join-Path $racine 'editors.cache.json') -Encoding UTF8

            Mock Test-CtxEditorCapabilities { throw 'le cache aurait du suffire' }

            (Get-CtxEditorCapabilitiesCached -Editor $editeur -ContextRoot $racine).SharedDataDir |
                Should -BeTrue
            Should -Invoke Test-CtxEditorCapabilities -Times 0 -Exactly
        }
    }
}

Describe 'Get-CtxEditorMagasinPartage' {
    # "Accepte --shared-data-dir" et "possede un magasin commun" sont deux
    # questions distinctes. La seconde se lit dans le product.json de
    # l'editeur, et c'est elle qui decide si le sujet le concerne.

    BeforeAll {
        $script:Poser = {
            param([string]$Nom, [string]$Json)
            $racine = Join-Path $TestDrive $Nom
            $app = Join-Path $racine 'build-4242/resources/app'
            New-Item -ItemType Directory -Path $app -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $app 'product.json') -Value $Json -Encoding UTF8
            $racine
        }
    }

    It 'lit le nom du magasin quand l editeur le declare' {
        # Et sous un dossier de VERSION : c'est la disposition reelle de VS Code
        # depuis aout 2026, celle qui avait rendu le lecteur de surface aveugle.
        $r = & $script:Poser 'avec' '{"dataFolderName":".vscode","sharedDataFolderName":".vscode-shared"}'
        InModuleScope DevContext -Parameters @{ r = $r } { param($r)
            Get-CtxEditorMagasinPartage -Root $r | Should -Be '.vscode-shared'
        }
    }

    It 'rend $null quand la cle est absente -- le cas des forks' {
        # Mesure du 19 aout 2026 : Cursor, Windsurf et Trae sont exactement ce
        # cas. Rendre autre chose que $null leur inventerait un probleme.
        $r = & $script:Poser 'sans' '{"dataFolderName":".cursor"}'
        InModuleScope DevContext -Parameters @{ r = $r } { param($r)
            Get-CtxEditorMagasinPartage -Root $r | Should -BeNullOrEmpty
        }
    }

    It 'rend $null sans lever sur une racine absente, vide ou illisible' {
        InModuleScope DevContext {
            Get-CtxEditorMagasinPartage -Root $null | Should -BeNullOrEmpty
            Get-CtxEditorMagasinPartage -Root '' | Should -BeNullOrEmpty
            Get-CtxEditorMagasinPartage -Root 'Q:\nexiste\pas' | Should -BeNullOrEmpty
        }
    }

    It 'rend $null sur un product.json qui n est pas du JSON' {
        # Un editeur inconnu ne doit jamais faire tomber un diagnostic.
        $r = & $script:Poser 'casse' 'ceci n est pas du json {{{'
        InModuleScope DevContext -Parameters @{ r = $r } { param($r)
            { Get-CtxEditorMagasinPartage -Root $r } | Should -Not -Throw
            Get-CtxEditorMagasinPartage -Root $r | Should -BeNullOrEmpty
        }
    }
}

Describe "Ce que l'editeur ne doit pas heriter" {
    # CE BLOC EXISTE POUR UN SYMPTOME QUI SURVIT A LA FERMETURE DU TERMINAL.
    #
    # Le 22 aout 2026, une fenetre VS Code ouverte depuis la session d'un agent
    # avait TOUS ses terminaux integres sans couleur, y compris apres
    # relancement. Cause : l'agent pose NO_COLOR=1 pour obtenir des sorties
    # propres, PowerShell 7 respecte cette convention en basculant
    # $PSStyle.OutputRendering sur PlainText, et la variable descendait jusqu'a
    # chaque terminal -- parce qu'elle vit dans le processus de la FENETRE, pas
    # dans celui du terminal.
    #
    # Le module s'appuie sur cet heritage pour transmettre le contexte. Il
    # transmettait donc aussi ce que l'appelant EST.

    Context 'La decision, sans processus a fabriquer' {
        It 'retire <Nom> quand il vaut <Valeur>' -ForEach @(
            @{ Nom = 'NO_COLOR'; Valeur = '1' }
            @{ Nom = 'FORCE_COLOR'; Valeur = '1' }
            @{ Nom = 'CI'; Valeur = 'true' }
            @{ Nom = 'TERM'; Valeur = 'dumb' }
        ) {
            $r = InModuleScope DevContext -Parameters @{ n = $Nom; v = $Valeur } {
                param($n, $v) @(Get-CtxVariablesNonInteractives -Environnement @{ $n = $v })
            }
            $r | Should -Contain $Nom
        }

        It 'ne touche pas un TERM legitime : <_>' -ForEach @('xterm-256color', 'xterm', 'screen') {
            # Retirer un TERM qui decrit de vraies capacites casserait ce qu'il
            # decrit. Seul 'dumb' dit « aucune capacite ».
            $r = InModuleScope DevContext -Parameters @{ v = $_ } {
                param($v) @(Get-CtxVariablesNonInteractives -Environnement @{ TERM = $v })
            }
            $r | Should -Not -Contain 'TERM'
        }

        It 'ignore une valeur vide : une variable declaree sans contenu ne dit rien' {
            $r = InModuleScope DevContext {
                @(Get-CtxVariablesNonInteractives -Environnement @{ NO_COLOR = ''; CI = '   ' })
            }
            $r | Should -BeNullOrEmpty
        }

        It 'NE TOUCHE JAMAIS ce qui porte le contexte' {
            # LE test de ce bloc. Un nettoyage qui emporterait GH_CONFIG_DIR ou
            # SUPABASE_ACCESS_TOKEN detruirait l'isolation que tout le module
            # existe pour tenir -- et le ferait en silence, puisque l'editeur
            # s'ouvrirait quand meme.
            $r = InModuleScope DevContext {
                @(Get-CtxVariablesNonInteractives -Environnement @{
                        GH_CONFIG_DIR         = 'F:\CTX\perso\gh'
                        SUPABASE_ACCESS_TOKEN = 'sbp_exemple'
                        DEVCTX                = 'perso'
                        DEVCTX_ROOT_PATH      = 'F:\PROJECTS\Apps'
                        VERCEL_TOKEN          = 'exemple'
                        PATH                  = 'C:\'
                    })
            }
            $r | Should -BeNullOrEmpty -Because 'le contexte voyage par heritage : le nettoyer serait detruire l isolation'
        }

        It 'accepte un environnement nul sans lever' {
            { InModuleScope DevContext { Get-CtxVariablesNonInteractives -Environnement $null } } |
                Should -Not -Throw
        }
    }

    Context 'La variable est absente AU MOMENT du lancement' {
        It "l'editeur est lance sans NO_COLOR, meme si l'appelant l'a" {
            # LE test qui prouve le correctif. Les autres verifient la decision
            # et la restauration ; celui-ci verifie ce que l'enfant recoit
            # REELLEMENT -- la seule chose qui compte pour la fenetre ouverte.
            $avant = $env:NO_COLOR
            try {
                $env:NO_COLOR = '1'
                $vu = InModuleScope DevContext {
                    $script:VuPendantLancement = '<non execute>'
                    Mock Find-CtxEditorExecutable { 'C:\faux\Code.exe' }
                    # Le lancement est remplace par une doublure : on ne lance
                    # jamais un vrai editeur dans la suite, et ce qu'on veut
                    # savoir est l'environnement au moment ou il partirait.
                    Mock Start-Process { $script:VuPendantLancement = [string]$env:NO_COLOR }
                    Open-DevCode -Name 'perso' -Path $TestDrive
                    $script:VuPendantLancement
                }
                $vu | Should -BeExactly '' -Because 'la fenetre herite de cet environnement pour toute sa vie'
            }
            finally {
                if ($null -eq $avant) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
                else { $env:NO_COLOR = $avant }
            }
        }
    }

    Context "L'environnement de l'appelant est rendu intact" {
        It 'restaure la variable retiree, meme si le lancement leve' {
            # L'appelant n'a pas demande qu'on modifie SON environnement. Et le
            # `finally` n'est pas decoratif : sans lui, un lancement qui echoue
            # laisserait le shell prive de NO_COLOR sans que rien ne le dise.
            $avant = $env:NO_COLOR
            try {
                $env:NO_COLOR = '1'
                InModuleScope DevContext {
                    Mock Find-CtxEditorExecutable { throw 'panne simulee' }
                    try { Open-DevCode -Name 'perso' -Path $TestDrive } catch { }
                }
                $env:NO_COLOR | Should -BeExactly '1' -Because 'le shell appelant doit retrouver son environnement'
            }
            finally {
                # Restaurer, jamais supprimer : effacer une vraie variable dans
                # un finally a deja desarme un test qui tournait apres.
                if ($null -eq $avant) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue }
                else { $env:NO_COLOR = $avant }
            }
        }
    }
}
