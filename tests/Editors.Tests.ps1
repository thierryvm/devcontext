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
