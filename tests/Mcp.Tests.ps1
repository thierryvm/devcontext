BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'New-CtxMcpServeurSupabase' {
    It 'declare le serveur stdio local, pas le serveur heberge' {
        # C'est tout l'objet du generateur : le serveur heberge s'authentifie en
        # OAuth, donc au compte, machine entiere. Le stdio local prend son jeton
        # dans l'environnement, donc au dossier.
        InModuleScope DevContext {
            $s = New-CtxMcpServeurSupabase -Ref 'abcdefghijklmnop'
            $s.command  | Should -Be 'npx'
            $s.args     | Should -Contain '@supabase/mcp-server-supabase@latest'
            $s.Contains('url') | Should -BeFalse
        }
    }

    It 'transmet le project-ref du dossier' {
        InModuleScope DevContext {
            (New-CtxMcpServeurSupabase -Ref 'refduprojet').args | Should -Contain '--project-ref=refduprojet'
        }
    }

    It 'est en lecture seule par defaut' {
        InModuleScope DevContext {
            (New-CtxMcpServeurSupabase -Ref 'r').args | Should -Contain '--read-only'
        }
    }

    It 'accepte l ecriture quand elle est demandee' {
        InModuleScope DevContext {
            (New-CtxMcpServeurSupabase -Ref 'r' -Ecriture).args | Should -Not -Contain '--read-only'
        }
    }

    It 'reste en lecture seule sur un projet de production, meme avec -Ecriture' {
        # Meme doctrine que le garde-fou CLI : un agent qui peut ecrire en
        # production est un mauvais apres-midi qui attend son tour.
        InModuleScope DevContext {
            (New-CtxMcpServeurSupabase -Ref 'r' -Ecriture -Production).args | Should -Contain '--read-only'
        }
    }

    It 'n ecrit AUCUN secret' {
        InModuleScope DevContext {
            $j = New-CtxMcpServeurSupabase -Ref 'r' | ConvertTo-Json -Depth 5
            $j | Should -Not -Match 'sbp_'
            $j | Should -Not -Match 'SUPABASE_ACCESS_TOKEN'
        }
    }

    It 'ne declare pas de bloc env' {
        # "${SUPABASE_ACCESS_TOKEN}" se developpe en CHAINE VIDE quand la
        # variable est absente, et la CLI lit une chaine vide comme « jeton
        # fourni mais invalide » — le piege documente dans Set-CtxSupabaseToken.
        # L'heritage de processus, lui, rend un jeton absent absent.
        InModuleScope DevContext {
            (New-CtxMcpServeurSupabase -Ref 'r').Contains('env') | Should -BeFalse
        }
    }
}

Describe 'New-CtxMcpServeurGitHub' {
    It 'defere le jeton a l environnement, sans jamais l inscrire' {
        InModuleScope DevContext {
            $s = New-CtxMcpServeurGitHub
            $s.headers.Authorization | Should -Be 'Bearer ${GH_TOKEN}'
            ($s | ConvertTo-Json -Depth 5) | Should -Not -Match 'gh[pousr]_'
        }
    }
}

Describe 'Merge-CtxMcpConfig' {
    It 'ajoute un serveur absent' {
        InModuleScope DevContext {
            $r = Merge-CtxMcpConfig -Existant $null -Nouveaux ([ordered]@{ supabase = @{ command = 'npx' } })
            $r.Ajoutes | Should -Contain 'supabase'
            $r.Config.mcpServers.Contains('supabase') | Should -BeTrue
        }
    }

    It 'conserve un serveur existant sans -Force' {
        # Un generateur qui mange les entrees ecrites a la main est un
        # generateur qu on ne relance jamais.
        InModuleScope DevContext {
            $existant = @{ mcpServers = @{ supabase = @{ command = 'a-moi' } } }
            $r = Merge-CtxMcpConfig -Existant $existant -Nouveaux ([ordered]@{ supabase = @{ command = 'npx' } })
            $r.Conserves | Should -Contain 'supabase'
            $r.Config.mcpServers['supabase'].command | Should -Be 'a-moi'
        }
    }

    It 'remplace avec -Force' {
        InModuleScope DevContext {
            $existant = @{ mcpServers = @{ supabase = @{ command = 'a-moi' } } }
            $r = Merge-CtxMcpConfig -Existant $existant -Nouveaux ([ordered]@{ supabase = @{ command = 'npx' } }) -Force
            $r.Remplaces | Should -Contain 'supabase'
            $r.Config.mcpServers['supabase'].command | Should -Be 'npx'
        }
    }

    It 'preserve les serveurs qu il ne connait pas' {
        InModuleScope DevContext {
            $existant = @{ mcpServers = @{ maison = @{ command = 'x' } } }
            $r = Merge-CtxMcpConfig -Existant $existant -Nouveaux ([ordered]@{ supabase = @{ command = 'npx' } })
            $r.Config.mcpServers.Contains('maison') | Should -BeTrue
        }
    }

    It 'preserve les cles racine qu il ne connait pas' {
        InModuleScope DevContext {
            $existant = @{ mcpServers = @{}; unChampAMoi = 'garde-moi' }
            $r = Merge-CtxMcpConfig -Existant $existant -Nouveaux ([ordered]@{ supabase = @{} })
            $r.Config['unChampAMoi'] | Should -Be 'garde-moi'
        }
    }
}

Describe 'New-DevProjectMcp' {
    BeforeAll {
        $script:projet = Join-Path $TestDrive 'appli'
        New-Item -ItemType Directory -Path (Join-Path $script:projet 'supabase\.temp') -Force | Out-Null
        Set-Content (Join-Path $script:projet 'supabase\.temp\project-ref') 'refdutest' -NoNewline
    }

    It 'ecrit un fichier dont le JSON est valide' {
        New-DevProjectMcp -Path $script:projet -Confirm:$false | Out-Null
        $p = Join-Path $script:projet '.mcp.json'
        Test-Path $p | Should -BeTrue
        { Get-Content $p -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'declare supabase avec le ref lu dans le dossier' {
        $c = Get-Content (Join-Path $script:projet '.mcp.json') -Raw | ConvertFrom-Json
        $c.mcpServers.supabase.args | Should -Contain '--project-ref=refdutest'
    }

    It 'n ecrit aucun secret dans le fichier' {
        # Ce fichier est fait pour etre commite. C'est la propriete qui le permet.
        $brut = Get-Content (Join-Path $script:projet '.mcp.json') -Raw
        $brut | Should -Not -Match 'sbp_|sbs_|gh[pousr]_|github_pat_'
    }

    It 'ne touche a rien avec -WhatIf' {
        $vierge = Join-Path $TestDrive 'vierge'
        New-Item -ItemType Directory -Path (Join-Path $vierge 'supabase\.temp') -Force | Out-Null
        Set-Content (Join-Path $vierge 'supabase\.temp\project-ref') 'r' -NoNewline
        New-DevProjectMcp -Path $vierge -WhatIf | Out-Null
        Test-Path (Join-Path $vierge '.mcp.json') | Should -BeFalse
    }

    It 'leve plutot que d ecraser un fichier illisible' {
        # Ecraser silencieusement un .mcp.json casse ferait disparaitre une
        # configuration ecrite a la main, sans la moindre trace.
        $casse = Join-Path $TestDrive 'casse'
        New-Item -ItemType Directory -Path (Join-Path $casse 'supabase\.temp') -Force | Out-Null
        Set-Content (Join-Path $casse 'supabase\.temp\project-ref') 'r' -NoNewline
        Set-Content (Join-Path $casse '.mcp.json') '{ ceci nest pas du json'
        { New-DevProjectMcp -Path $casse -Confirm:$false } | Should -Throw '*illisible*'
    }

    It 'est expose comme alias ctx-mcp' {
        (Get-Alias 'ctx-mcp' -ErrorAction SilentlyContinue).ResolvedCommandName |
            Should -Be 'New-DevProjectMcp'
    }
}
