# Ce que voit quelqu'un qui decouvre l'outil sur SA machine.
#
# Tous ces tests sont nes d'un seul exercice, le 15 aout 2026 : simuler une
# machine vierge -- pas de lecteur F:, pas de reglage, aucun contexte -- et
# taper les commandes qu'un nouvel utilisateur taperait. Le parcours s'arretait
# cinq fois, dont deux en BLOQUANT indefiniment.
#
# Rien de tout cela n'apparaissait sur la machine de l'auteur, et c'est
# exactement pourquoi ces tests existent : ils reconstituent l'absence.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
}

Describe 'Racine des contextes — resolution' {
    It 'la variable d environnement a le dernier mot' {
        InModuleScope DevContext {
            $avant = $env:DEVCTX_ROOT
            try {
                $env:DEVCTX_ROOT = 'X:\choisi'
                Get-CtxRootDefault | Should -Be 'X:\choisi'
            }
            finally {
                if ($null -ne $avant) { $env:DEVCTX_ROOT = $avant }
                else { Remove-Item Env:DEVCTX_ROOT -ErrorAction SilentlyContinue }
            }
        }
    }

    It 'le defaut ne mentionne aucun lecteur code en dur' {
        # Il valait 'F:\CTX' — le lecteur de l'auteur. Sur toute autre machine,
        # le module se chargeait sans erreur et ne trouvait rien, en silence.
        InModuleScope DevContext {
            $avant = $env:DEVCTX_ROOT
            $config = Get-CtxConfigPath
            try {
                Remove-Item Env:DEVCTX_ROOT -ErrorAction SilentlyContinue
                # On neutralise le reglage machine pour observer le vrai defaut.
                Mock Get-CtxConfigPath { Join-Path $TestDrive 'inexistant.json' }
                $defaut = Get-CtxRootDefault
                $defaut | Should -Not -Match '^[Ff]:'
                $defaut | Should -Match ([regex]::Escape($env:LOCALAPPDATA))
            }
            finally {
                if ($null -ne $avant) { $env:DEVCTX_ROOT = $avant }
                $null = $config
            }
        }
    }

    It 'le reglage machine est lu quand la variable est absente' {
        InModuleScope DevContext {
            $avant = $env:DEVCTX_ROOT
            try {
                Remove-Item Env:DEVCTX_ROOT -ErrorAction SilentlyContinue
                $faux = Join-Path $TestDrive 'config.json'
                '{ "root": "D:\\ailleurs\\CTX" }' | Set-Content $faux -Encoding UTF8
                Mock Get-CtxConfigPath { $faux }
                Get-CtxRootDefault | Should -Be 'D:\ailleurs\CTX'
            }
            finally {
                if ($null -ne $avant) { $env:DEVCTX_ROOT = $avant }
            }
        }
    }

    It 'un reglage illisible retombe sur le defaut au lieu de tout casser' {
        InModuleScope DevContext {
            $avant = $env:DEVCTX_ROOT
            try {
                Remove-Item Env:DEVCTX_ROOT -ErrorAction SilentlyContinue
                $faux = Join-Path $TestDrive 'casse.json'
                'ceci n est pas du json' | Set-Content $faux -Encoding UTF8
                Mock Get-CtxConfigPath { $faux }
                { Get-CtxRootDefault } | Should -Not -Throw
                Get-CtxRootDefault | Should -Not -BeNullOrEmpty
            }
            finally {
                if ($null -ne $avant) { $env:DEVCTX_ROOT = $avant }
            }
        }
    }

    It 'ne depend d aucun helper defini plus bas dans le module' {
        # Get-CtxRootDefault s'execute pendant le CHARGEMENT du module. Elle
        # appelait Get-CtxProp, definie plus loin : l'appel levait, le catch
        # avalait l'erreur, et le reglage etait ignore EN SILENCE — les contextes
        # d'une installation existante se seraient volatilises sans un mot.
        # Par l'ARBRE SYNTAXIQUE, pas par le texte : la premiere version de ce
        # test cherchait la chaine 'Get-CtxProp' dans le corps et la trouvait
        # dans le COMMENTAIRE qui explique pourquoi on ne l'appelle pas. Un test
        # qui lit du texte ne sait pas distinguer du code d'une explication.
        $fichier = (Resolve-Path (Join-Path $PSScriptRoot '..' 'DevContext.psm1')).Path
        $arbre = [System.Management.Automation.Language.Parser]::ParseFile($fichier, [ref]$null, [ref]$null)

        $fonction = $arbre.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $n.Name -eq 'Get-CtxRootDefault'
            }, $true) | Select-Object -First 1
        $fonction | Should -Not -BeNullOrEmpty

        $appels = $fonction.FindAll({
                param($n) $n -is [System.Management.Automation.Language.CommandAst]
            }, $true) | ForEach-Object { $_.GetCommandName() }

        # Ce qui est defini APRES elle dans le fichier ne doit pas etre appele.
        $appels | Should -Not -Contain 'Get-CtxProp'
        $appels | Should -Not -Contain 'Get-CtxManifests'
        $appels | Should -Not -Contain 'Read-CtxManifest'
    }
}

Describe 'Chemins — aucun lecteur code en dur dans les defauts' {
    It 'aucun fichier livre ne contient un chemin de profil utilisateur' {
        $racine = Split-Path $PSScriptRoot -Parent
        $suivis = @(& git -C $racine ls-files '*.ps1' '*.psm1' '*.psd1')
        $fautifs = foreach ($f in $suivis) {
            $t = Get-Content (Join-Path $racine $f) -Raw -ErrorAction SilentlyContinue
            # On cherche un chemin de profil REEL, pas les exemples neutres.
            if ($t -match 'C:\\Users\\(?!moi\b|<|%|\$)[A-Za-z0-9._-]+\\A(ppData|pplication)') { $f }
        }
        $fautifs | Should -BeNullOrEmpty -Because 'un chemin de profil ne marche que chez son proprietaire, et publie son nom'
    }

    It 'le defaut de -Root de ctx-new ne vise pas un lecteur precis' {
        $source = Get-Content (Join-Path $PSScriptRoot '..' 'DevContext.psm1') -Raw
        $source | Should -Not -Match "Root = ""[A-Za-z]:\\\\"
    }

    It 'ctx-new ne signe pas les commits au nom de quelqu un d autre' {
        # Le defaut de -GitUserName valait le nom de l auteur du module. Tout
        # contexte cree ailleurs aurait signe les commits de son proprietaire
        # avec ce nom-la.
        InModuleScope DevContext {
            (Get-Command New-DevContext).Parameters['GitUserName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } |
                Should -BeNullOrEmpty
        }
        $source = Get-Content (Join-Path $PSScriptRoot '..' 'DevContext.psm1') -Raw
        $source | Should -Not -Match '\$GitUserName\s*=\s*''[A-Z]'
    }
}

Describe 'Premier contact — la commande suivante est toujours donnee' {
    It 'ctx-new n exige plus -Label' {
        # Le message d accueil proposait une commande qui echouait aussitot sur
        # « missing mandatory parameters: Label ». Un premier pas qui ne marche
        # pas est pire qu un premier pas absent.
        InModuleScope DevContext {
            (Get-Command New-DevContext).Parameters['Label'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } |
                Should -BeNullOrEmpty
        }
    }

    It 'ctx-new expose -NoKey pour un appelant non interactif' {
        InModuleScope DevContext {
            (Get-Command New-DevContext).Parameters.ContainsKey('NoKey') | Should -BeTrue
        }
    }

    It 'aucune invite ne peut bloquer une entree redirigee' {
        # ssh-keygen et Read-Host attendaient une reponse que personne ne
        # taperait jamais : la commande ne rendait plus la main du tout.
        # Chaque invite doit etre gardee par un test sur l entree standard.
        $source = Get-Content (Join-Path $PSScriptRoot '..' 'DevContext.psm1') -Raw
        $corps = [regex]::Match($source, '(?s)function New-DevContext \{.*?\n\}\r?\n\r?\n').Value
        $corps | Should -Match 'IsInputRedirected'
        # Autant de gardes que d endroits qui demandent quelque chose.
        $invites = ([regex]::Matches($corps, 'Read-Host|ssh-keygen')).Count
        $gardes = ([regex]::Matches($corps, 'IsInputRedirected')).Count
        $gardes | Should -BeGreaterOrEqual 2 -Because "il y a $invites invite(s) a garder"
    }
}
