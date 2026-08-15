# Le mecanisme bilingue.
#
# Deux dangers, et ils sont symetriques. Une cle presente dans une langue et
# absente de l'autre produit un message a moitie traduit, que seul un lecteur de
# cette langue verra. Une cle orpheline dans une table gonfle la maintenance de
# quelque chose que plus personne n'affiche. Les deux se detectent ici, pas a
# l'usage.
#
# Aucun test ne change la culture de la machine : Get-CtxLangue prend ses
# sources en parametres, ce qui est toute la raison de la decouper ainsi.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force
    $script:Racine = Split-Path $PSScriptRoot -Parent
}

Describe 'Get-CtxLangue' {
    It 'DEVCTX_LANG a le dernier mot' {
        InModuleScope DevContext {
            Get-CtxLangue -Demandee 'en' -Culture 'fr-BE' | Should -Be 'en'
            Get-CtxLangue -Demandee 'fr' -Culture 'en-US' | Should -Be 'fr'
        }
    }

    It 'accepte une culture avec region : <_>' -ForEach @('fr-BE', 'fr-FR', 'fr_CA', 'FR-be') {
        # Une culture systeme porte presque toujours une region. Exiger le code
        # court reviendrait a ne reconnaitre personne.
        InModuleScope DevContext -Parameters @{ c = $_ } { param($c)
            Get-CtxLangue -Demandee '' -Culture $c | Should -Be 'fr'
        }
    }

    It 'retombe sur l anglais pour une langue non traduite' {
        InModuleScope DevContext {
            Get-CtxLangue -Demandee '' -Culture 'de-DE' | Should -Be 'en'
            Get-CtxLangue -Demandee 'ja' -Culture 'ja-JP' | Should -Be 'en'
        }
    }

    It 'ignore une valeur vide ou blanche sans lever' {
        InModuleScope DevContext {
            { Get-CtxLangue -Demandee $null -Culture $null } | Should -Not -Throw
            Get-CtxLangue -Demandee '  ' -Culture '' | Should -Be 'en'
        }
    }
}

Describe 'T' {
    AfterAll {
        # Rendre au processus la langue qu'il avait, sinon les fichiers de test
        # suivants heriteraient de la derniere langue posee ici.
        InModuleScope DevContext { Set-CtxLangue | Out-Null }
    }

    It 'rend le texte de la langue active' {
        InModuleScope DevContext {
            Set-CtxLangue 'fr' | Out-Null
            T 'ctx.noGo' | Should -Be 'NO-GO'
            Set-CtxLangue 'en' | Out-Null
            T 'ctx.go' | Should -Match 'agree'
        }
    }

    It 'substitue par position, pas par concatenation' {
        # {0}, {1} permettent a une traduction de REORDONNER. Une phrase
        # assemblee par morceaux ne survit pas au premier ordre different.
        InModuleScope DevContext {
            Set-CtxLangue 'fr' | Out-Null
            T 'ctx.pb.dossierAutre' 'client' 'perso' | Should -Match "'client'.*'perso'"
        }
    }

    It 'retombe sur l anglais quand la cle manque dans la langue active' {
        InModuleScope DevContext {
            Set-CtxLangue 'fr' | Out-Null
            $script:Textes = @{}                       # on vide la table francaise
            $script:TextesSecours = @{ 'essai' = 'fallback' }
            T 'essai' | Should -Be 'fallback'
        }
    }

    It 'rend la cle entre crochets, jamais une chaine vide' {
        # Un message vide se lit comme une commande qui n'a rien dit. Une cle
        # visible se lit comme un defaut, et se cherche.
        InModuleScope DevContext {
            Set-CtxLangue 'fr' | Out-Null
            T 'cle.qui.n.existe.pas' | Should -Be '[cle.qui.n.existe.pas]'
        }
    }
}

Describe 'Tables de textes' {
    BeforeAll {
        $script:Fr = Import-PowerShellDataFile (Join-Path $script:Racine 'lang/fr.psd1')
        $script:En = Import-PowerShellDataFile (Join-Path $script:Racine 'lang/en.psd1')
    }

    It 'les deux langues portent exactement les memes cles' {
        # Une cle presente d un cote seulement produit un message a moitie
        # traduit, que seul un lecteur de cette langue verra.
        $manquantesEn = @($script:Fr.Keys | Where-Object { $_ -notin $script:En.Keys })
        $manquantesFr = @($script:En.Keys | Where-Object { $_ -notin $script:Fr.Keys })
        $manquantesEn | Should -BeNullOrEmpty -Because 'ces cles existent en francais et pas en anglais'
        $manquantesFr | Should -BeNullOrEmpty -Because 'ces cles existent en anglais et pas en francais'
    }

    It 'aucun texte n est vide' {
        foreach ($table in $script:Fr, $script:En) {
            foreach ($k in $table.Keys) {
                $table[$k] | Should -Not -BeNullOrEmpty -Because "la cle '$k' n a pas de texte"
            }
        }
    }

    It 'les substitutions concordent entre les deux langues' {
        # Un {1} present en anglais et absent en francais produit une exception
        # de formatage a l execution, dans une seule langue -- donc chez une
        # partie des utilisateurs seulement.
        foreach ($k in $script:Fr.Keys) {
            $numeros = { param($s) ([regex]::Matches($s, '\{(\d+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ',' }
            (& $numeros $script:Fr[$k]) | Should -Be (& $numeros $script:En[$k]) -Because "la cle '$k' n a pas les memes substitutions dans les deux langues"
        }
    }

    It 'les textes restent en ASCII' {
        # Affiches dans un terminal dont on ignore l encodage : un accent devient
        # un caractere de remplacement sous git-bash, et un message de refus est
        # la sortie qui doit se lire correctement sur une machine inconnue.
        foreach ($nom in 'Fr', 'En') {
            $table = Get-Variable -Name $nom -Scope Script -ValueOnly
            foreach ($k in $table.Keys) {
                $table[$k] | Should -Not -Match '[^\x00-\x7F]' -Because "la cle '$k' ($nom) contient un caractere non-ASCII"
            }
        }
    }
}

Describe 'Aucune decision prise sur du texte affiche' {
    AfterAll {
        InModuleScope DevContext { Set-CtxLangue | Out-Null }
    }

    It 'ctx doctor rend le meme verdict dans les deux langues' {
        # LE piege structurel de toute traduction, et il a mordu ici le 15 aout
        # 2026 : le doctor comparait `$e.Profil -eq 'isole'`, un litteral
        # francais, alors que ce champ venait de devenir traduit. En anglais la
        # comparaison echouait et CHAQUE editeur etait rapporte comme non isole
        # -- un faux avertissement visible seulement pour les lecteurs anglais,
        # donc invisible sur la machine qui l'a introduit.
        #
        # Une valeur affichee ne sert jamais de valeur de decision. Ce test le
        # verifie sur la sortie complete, pas sur un champ en particulier :
        # traduire un libelle ne doit deplacer aucun verdict.
        $verdicts = @{}
        foreach ($langue in 'fr', 'en') {
            $sortie = pwsh -NoProfile -Command "
                `$env:DEVCTX_LANG='$langue'
                Import-Module '$(Join-Path (Split-Path $PSScriptRoot -Parent) 'DevContext.psd1')' -Force
                Get-DevContextDoctor -Path '$PSScriptRoot' |
                    ForEach-Object { `$_.Domaine + '|' + `$_.Sujet + '|' + `$_.Verdict }
            "
            $verdicts[$langue] = @($sortie) -join "`n"
        }
        $verdicts['fr'] | Should -Not -BeNullOrEmpty
        $verdicts['en'] | Should -Be $verdicts['fr']
    }

    It 'Get-DevEditorList expose un champ booleen a cote du libelle traduit' {
        # Le correctif structurel : le code decide sur Isole/ExtensionsIsolees,
        # l'humain lit Profil/Extensions. Retirer les booleens ferait revenir le
        # bug par la porte qu'il a deja empruntee.
        InModuleScope DevContext {
            $proprietes = (Get-Command Get-DevEditorList).ScriptBlock.ToString()
            $proprietes | Should -Match 'Isole\s*='
            $proprietes | Should -Match 'ExtensionsIsolees\s*='
        }
    }

    It 'aucun code ne compare a un libelle traduit' {
        # Filet plus large : si une comparaison porte sur une valeur qui existe
        # dans les tables de textes, c'est presque surement le meme defaut.
        $racine = Split-Path $PSScriptRoot -Parent
        # Les libelles AVEC espaces comptent aussi. Les exclure a laisse passer
        # une troisieme occurrence du defaut -- un filtre sur
        # « ne lance pas un editeur », qui aurait cesse de matcher en anglais et
        # noye le rapport sous deux cents raccourcis sans rapport.
        $textes = (Import-PowerShellDataFile (Join-Path $racine 'lang/fr.psd1')).Values |
            Where-Object { $_ -and $_.Length -ge 4 -and $_ -notmatch '\{' }

        # Sur les JETONS, pas sur le texte brut. La premiere version signalait le
        # commentaire qui DECRIT le bug -- exactement la meme confusion entre
        # code et prose que le test corrige plus haut. Un test qui lit du texte
        # ne sait pas distinguer une comparaison d'une explication.
        $fautifs = foreach ($f in @(& git -C $racine ls-files '*.ps1' '*.psm1')) {
            if ($f -like 'tests/*' -or $f -like 'lang/*') { continue }
            $jetons = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $racine $f), [ref]$jetons, [ref]$null)
            $code = ($jetons |
                    Where-Object { $_.Kind -ne 'Comment' } |
                    ForEach-Object { $_.Text }) -join ' '

            foreach ($valeur in $textes) {
                if ($code -match "-eq\s+'$([regex]::Escape($valeur))'") { "$f : -eq '$valeur'" }
            }
        }
        ($fautifs | Sort-Object -Unique) | Should -BeNullOrEmpty
    }
}

Describe 'Cles utilisees et cles declarees' {
    It 'toute cle appelee dans le code existe dans les deux tables' {
        $fr = Import-PowerShellDataFile (Join-Path $script:Racine 'lang/fr.psd1')
        $en = Import-PowerShellDataFile (Join-Path $script:Racine 'lang/en.psd1')

        $sources = @(& git -C $script:Racine ls-files '*.ps1' '*.psm1') |
            Where-Object { $_ -notlike 'tests/*' }

        $inconnues = foreach ($f in $sources) {
            $contenu = Get-Content (Join-Path $script:Racine $f) -Raw
            foreach ($m in [regex]::Matches($contenu, "(?<![\w-])T\s+'([a-z][a-zA-Z0-9.]+)'")) {
                $cle = $m.Groups[1].Value
                if ($cle -notin $fr.Keys -or $cle -notin $en.Keys) { "$f : $cle" }
            }
        }
        ($inconnues | Sort-Object -Unique) | Should -BeNullOrEmpty
    }
}
