# ===========================================================================
# A QUI APPARTIENT CE DOSSIER, quand la reponse n'est pas unique.
#
# Deux defauts releves par la revue de la PR #55 (ctx exec), tous deux dans
# Resolve-DevContextForPath -- la fonction que ctx, ctx doctor, ctx exec et les
# trois garde-fous partagent.
#
# 1. JONCTIONS ET LIENS. La resolution comparait le TEXTE du chemin aux racines.
#    Une jonction posee sous la racine A et pointant dans les fichiers de B
#    resolvait vers A : les commandes travaillaient les fichiers de B avec
#    l'identite et les jetons de A.
#
#    Ce que fait git dans le meme cas a ete MESURE, pas suppose (git
#    2.56.0.windows.4, 30 octobre 2026) : depuis A\lien, `git rev-parse
#    --absolute-git-dir` rend deja B/projet/.git, et seule la regle
#    `includeIf "gitdir:B/"` s'applique, quel que soit l'ordre des deux regles.
#    git juge donc sur la CIBLE. DevContext jugeait sur l'ALIAS : le jeton de A,
#    la signature de B.
#
# 2. RACINES DUPLIQUEES. Deux manifestes declarant la meme racine : la boucle
#    "la plus longue gagne" gardait celui que Get-CtxManifests enumerait en
#    premier, donc une identite arbitraire. `ctx new` refuse le doublon, mais un
#    manifeste edite a la main ou cree en parallele passe a cote.
#
# Le parti pris dans les deux cas : quand l'alias et la cible divergent, ou que
# deux contextes revendiquent la meme racine, on ne CHOISIT pas. Le dossier est
# ambigu, et une ambiguite se refuse -- "corriger quand la reponse est
# connaissable, refuser seulement quand elle ne l'est pas".
#
# Le monde factice est construit sous $TestDrive avec de VRAIES jonctions : la
# resolution physique est precisement ce qui est teste, et une simulation de
# Get-Item ne prouverait que la simulation.
# ===========================================================================

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force

    # La source d'une fonction privee de ses commentaires, remplaces par des
    # espaces de meme longueur -- meme outil que tests/VerdictsPartages.Tests.ps1.
    # Sans lui, un commentaire qui NOMME l'appel interdit fait rougir
    # l'assertion de non-presence. Mesure ici meme au premier passage.
    function Get-SourceSansCommentaires {
        param([Parameter(Mandatory)][string]$Nom)
        $src = (Get-Command $Nom).ScriptBlock.ToString()
        $jetons = $null
        $erreurs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$jetons, [ref]$erreurs)
        $sb = [System.Text.StringBuilder]::new($src)
        foreach ($t in @($jetons | Where-Object { $_.Kind -eq 'Comment' })) {
            $debut = $t.Extent.StartOffset
            $long = $t.Extent.EndOffset - $debut
            $null = $sb.Remove($debut, $long).Insert($debut, (' ' * $long))
        }
        $sb.ToString()
    }
}

Describe 'Get-CtxVerdictProprietaire (decision pure)' {
    BeforeAll {
        $script:A = [pscustomobject]@{ name = 'alpha'; root = 'F:\P\A' }
        $script:B = [pscustomobject]@{ name = 'beta'; root = 'F:\P\B' }
        $script:C = [pscustomobject]@{ name = 'gamma'; root = 'F:\P\A\sous' }
        $script:Dbl = [pscustomobject]@{ name = 'doublon'; root = 'F:\P\A' }
        $script:R = {
            param($m, $phys)
            [pscustomobject]@{ Manifeste = $m; Racine = $m.root; RacinePhysique = $(if ($phys) { $phys } else { $m.root }) }
        }
    }

    It 'rend proprietaire quand le chemin et sa cible s accordent' {
        InModuleScope DevContext -Parameters @{ a = $script:A; b = $script:B; r = $script:R } { param($a, $b, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\projet' -CheminPhysique 'F:\P\A\projet' `
                -Racines @((& $r $a), (& $r $b))
            $v.Etat | Should -Be 'proprietaire'
            $v.Contexte | Should -Be 'alpha'
            [object]::ReferenceEquals($v.Manifeste, $a) | Should -BeTrue
            $v.Raison | Should -BeNullOrEmpty
        }
    }

    It 'rend aucun hors de toute racine' {
        InModuleScope DevContext -Parameters @{ a = $script:A; r = $script:R } { param($a, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'C:\ailleurs' -CheminPhysique 'C:\ailleurs' -Racines @((& $r $a))
            $v.Etat | Should -Be 'aucun'
            $v.Manifeste | Should -BeNullOrEmpty
        }
    }

    It 'rend ambigu, sans manifeste, quand deux contextes declarent la meme racine (ordre <_>)' -ForEach @('AD', 'DA') {
        # L'ordre est le defaut lui-meme : avant, le premier enumere gagnait.
        InModuleScope DevContext -Parameters @{ a = $script:A; d = $script:Dbl; r = $script:R; ordre = $_ } {
            param($a, $d, $r, $ordre)
            $racines = if ($ordre -eq 'AD') { @((& $r $a), (& $r $d)) } else { @((& $r $d), (& $r $a)) }
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\projet' -CheminPhysique 'F:\P\A\projet' -Racines $racines
            $v.Etat | Should -Be 'ambigu'
            $v.Raison | Should -Be 'racine-dupliquee'
            $v.Manifeste | Should -BeNullOrEmpty
            $v.Contexte | Should -BeNullOrEmpty
            @($v.Candidats) | Should -Be @('alpha', 'doublon')
        }
    }

    It 'ne juge l egalite qu a la longueur gagnante : une racine imbriquee l emporte sur un doublon plus court' {
        InModuleScope DevContext -Parameters @{ a = $script:A; d = $script:Dbl; c = $script:C; r = $script:R } {
            param($a, $d, $c, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\sous\x' -CheminPhysique 'F:\P\A\sous\x' `
                -Racines @((& $r $a), (& $r $d), (& $r $c))
            $v.Etat | Should -Be 'proprietaire'
            $v.Contexte | Should -Be 'gamma'
        }
    }

    It 'ignore un doublon qui ne porte pas sur ce chemin' {
        InModuleScope DevContext -Parameters @{ a = $script:A; d = $script:Dbl; b = $script:B; r = $script:R } {
            param($a, $d, $b, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\B\x' -CheminPhysique 'F:\P\B\x' `
                -Racines @((& $r $a), (& $r $d), (& $r $b))
            $v.Etat | Should -Be 'proprietaire'
            $v.Contexte | Should -Be 'beta'
        }
    }

    It 'ne donne rien a une racine-jonction : seule la racine declaree possede, comme pour git' {
        # B est une jonction vers A. git compare le chemin physique aux motifs
        # ECRITS : il applique A ici, jamais B. L'attente d'origine ('ambigu')
        # suivait un modele que la mesure du 30 octobre 2026 a dementi ; c'est
        # `ctx doctor` qui signale la racine-lien (Test-CtxDoctorRacinesLiens).
        InModuleScope DevContext -Parameters @{ a = $script:A; b = $script:B; r = $script:R } { param($a, $b, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\x' -CheminPhysique 'F:\P\A\x' `
                -Racines @((& $r $a), (& $r $b 'F:\P\A'))
            $v.Etat | Should -Be 'proprietaire'
            $v.Contexte | Should -Be 'alpha'
        }
    }

    It 'ne laisse pas une racine-jonction s emparer du sous-arbre d un autre contexte' {
        # Reproduction de l'audit du 30 octobre 2026 (H1). gamma declare
        # F:\P\Gsub, jonction vers F:\P\B\sub. Avec les deux formes de chaque
        # racine, F:\P\B\sub\repo rendait 'proprietaire gamma' sans un mot --
        # jetons de gamma, signature git de beta.
        InModuleScope DevContext -Parameters @{ b = $script:B; r = $script:R } { param($b, $r)
            $g = [pscustomobject]@{ name = 'gamma'; root = 'F:\P\Gsub' }
            $racines = @((& $r $b), (& $r $g 'F:\P\B\sub'))
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\B\sub\repo' -CheminPhysique 'F:\P\B\sub\repo' -Racines $racines
            $v.Etat | Should -Be 'proprietaire'
            $v.Contexte | Should -Be 'beta'
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\Gsub\repo' -CheminPhysique 'F:\P\B\sub\repo' -Racines $racines
            $v.Etat | Should -Be 'ambigu'
            $v.Raison | Should -Be 'alias-cible'
        }
    }

    It 'rend ambigu quand le chemin dit <Texte> et la cible <Cible>' -ForEach @(
        @{ Texte = 'alpha'; Cible = 'beta'; Chemin = 'F:\P\A\lien'; Physique = 'F:\P\B\projet'; Attendus = @('alpha', 'beta') }
        @{ Texte = 'alpha'; Cible = 'personne'; Chemin = 'F:\P\A\lien'; Physique = 'D:\dehors'; Attendus = @('alpha') }
        @{ Texte = 'personne'; Cible = 'beta'; Chemin = 'D:\lien'; Physique = 'F:\P\B\projet'; Attendus = @('beta') }
    ) {
        InModuleScope DevContext -Parameters @{ a = $script:A; b = $script:B; r = $script:R; c = $Chemin; p = $Physique; att = $Attendus } {
            param($a, $b, $r, $c, $p, $att)
            $v = Get-CtxVerdictProprietaire -Chemin $c -CheminPhysique $p -Racines @((& $r $a), (& $r $b))
            $v.Etat | Should -Be 'ambigu'
            $v.Raison | Should -Be 'alias-cible'
            $v.Manifeste | Should -BeNullOrEmpty
            @($v.Candidats) | Should -Be $att
            $v.CheminPhysique | Should -Be $p
        }
    }

    It 'rend ambigu quand la cible physique est inconnue' {
        # Un lien existe sur le chemin et ne se laisse pas lire : on ne sait pas
        # quels fichiers sont en jeu, donc on ne sait pas qui les possede.
        InModuleScope DevContext -Parameters @{ a = $script:A; r = $script:R } { param($a, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\x' -CheminPhysique $null -Racines @((& $r $a))
            $v.Etat | Should -Be 'ambigu'
            $v.Raison | Should -Be 'cible-inconnue'
        }
    }

    It 'tient pour ambigu un chemin pris sous une racine qui est elle-meme une jonction' {
        # F:\P\A pointe sur D:\vrai. Mesure du 30 octobre 2026 : git n'applique
        # `includeIf "gitdir:F:/P/A/"` ni depuis F:\P\A\x ni depuis D:\vrai\x.
        # Donner les jetons d'alpha ici, c'est signer avec une autre identite.
        # L'attente d'origine ('proprietaire') suivait le texte, pas git.
        InModuleScope DevContext -Parameters @{ a = $script:A; r = $script:R } { param($a, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\x' -CheminPhysique 'D:\vrai\x' -Racines @((& $r $a 'D:\vrai'))
            $v.Etat | Should -Be 'ambigu'
            $v.Raison | Should -Be 'alias-cible'
        }
    }

    It 'accepte une racine sans RacinePhysique, comme sa documentation le promet' {
        # Sous StrictMode, lire une propriete absente LEVE. Releve par la revue
        # du 30 octobre 2026 ; aucun appelant de production ne la construit
        # ainsi, mais c'est une fonction pure, et elle se teste seule.
        InModuleScope DevContext {
            $m = [pscustomobject]@{ name = 'alpha'; root = 'F:\P\A' }
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\x' -CheminPhysique 'F:\P\A\x' `
                -Racines @([pscustomobject]@{ Manifeste = $m; Racine = 'F:\P\A' })
            $v.Etat | Should -Be 'proprietaire'
        }
    }

    It 'accepte une racine ecrite avec des barres obliques' {
        # Sans cela, la racine physique (normalisee par le systeme) et la racine
        # texte divergeaient, et un dossier sain devenait ambigu.
        InModuleScope DevContext {
            $m = [pscustomobject]@{ name = 'alpha'; root = 'F:/P/A' }
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A\x' -CheminPhysique 'F:\P\A\x' `
                -Racines @([pscustomobject]@{ Manifeste = $m; Racine = 'F:/P/A'; RacinePhysique = 'F:\P\A' })
            $v.Etat | Should -Be 'proprietaire'
        }
    }

    It 'garde la protection du prefixe : Apps-Autre n appartient pas a Apps' {
        InModuleScope DevContext -Parameters @{ a = $script:A; r = $script:R } { param($a, $r)
            $v = Get-CtxVerdictProprietaire -Chemin 'F:\P\A-Autre' -CheminPhysique 'F:\P\A-Autre' -Racines @((& $r $a))
            $v.Etat | Should -Be 'aucun'
        }
    }

    It 'ne rend que des etats et des raisons connus' {
        InModuleScope DevContext -Parameters @{ a = $script:A; b = $script:B; d = $script:Dbl; r = $script:R } {
            param($a, $b, $d, $r)
            $racines = @((& $r $a), (& $r $b), (& $r $d))
            foreach ($c in @('F:\P\A\x', 'F:\P\B\x', 'C:\x', '')) {
                foreach ($p in @('F:\P\A\x', 'F:\P\B\x', 'C:\x', $null)) {
                    $v = Get-CtxVerdictProprietaire -Chemin $c -CheminPhysique $p -Racines $racines
                    $v.Etat | Should -BeIn @('proprietaire', 'aucun', 'ambigu')
                    if ($v.Etat -eq 'ambigu') {
                        $v.Raison | Should -BeIn @('racine-dupliquee', 'alias-cible', 'cible-inconnue')
                        $v.Manifeste | Should -BeNullOrEmpty
                    }
                }
            }
        }
    }
}

Describe 'Get-CtxRacinesDupliquees (decision pure)' {
    It 'regroupe les contextes qui revendiquent la meme racine, par le texte ou par la cible' {
        InModuleScope DevContext {
            $e = {
                param($n, $racine, $phys)
                [pscustomobject]@{ Manifeste = [pscustomobject]@{ name = $n; root = $racine }; Racine = $racine; RacinePhysique = $phys }
            }
            $groupes = @(Get-CtxRacinesDupliquees -Racines @(
                    (& $e 'alpha' 'F:\P\A' 'F:\P\A'),
                    (& $e 'doublon' 'f:\p\a\' 'F:\P\A'),
                    (& $e 'beta' 'F:\P\B' 'F:\P\B'),
                    (& $e 'jonction' 'F:\J' 'F:\P\B'),
                    (& $e 'seul' 'F:\P\C' 'F:\P\C')
                ))
            $groupes.Count | Should -Be 2
            @($groupes | ForEach-Object { ($_.Contextes -join ',') }) | Should -Be @('alpha,doublon', 'beta,jonction')
        }
    }

    It 'ne rend rien sans doublon, ni sur une liste vide' {
        InModuleScope DevContext {
            @(Get-CtxRacinesDupliquees -Racines @()).Count | Should -Be 0
            $m = [pscustomobject]@{ name = 'alpha'; root = 'F:\P\A' }
            @(Get-CtxRacinesDupliquees -Racines @([pscustomobject]@{ Manifeste = $m; Racine = 'F:\P\A'; RacinePhysique = 'F:\P\A' })).Count |
                Should -Be 0
        }
    }
}

Describe 'Un monde factice avec de vraies jonctions' {
    BeforeAll {
        $script:Monde = Join-Path $TestDrive 'monde'
        $script:RacineA = Join-Path $script:Monde 'A'
        $script:RacineB = Join-Path $script:Monde 'B'
        $script:Dehors = Join-Path $script:Monde 'dehors'
        $script:ProjetB = Join-Path $script:RacineB 'projet'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:ProjetB 'src'), $script:RacineA, $script:Dehors | Out-Null

        # A\lien -> B\projet : un dossier de A qui EST un dossier de B.
        $script:Lien = Join-Path $script:RacineA 'lien'
        New-Item -ItemType Junction -Path $script:Lien -Target $script:ProjetB | Out-Null

        # dehors\vers-b -> B\projet : un chemin hors de toute racine qui mene a B.
        $script:Entree = Join-Path $script:Dehors 'vers-b'
        New-Item -ItemType Junction -Path $script:Entree -Target $script:ProjetB | Out-Null

        # dehors\relais -> A : une jonction vers une jonction.
        $script:Relais = Join-Path $script:Dehors 'relais'
        New-Item -ItemType Junction -Path $script:Relais -Target $script:RacineA | Out-Null

        # racineC -> vraieC : une racine DECLAREE qui est elle-meme une jonction.
        $script:VraieC = Join-Path $script:Monde 'vraieC'
        $script:RacineC = Join-Path $script:Monde 'racineC'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:VraieC 'proj') | Out-Null
        New-Item -ItemType Junction -Path $script:RacineC -Target $script:VraieC | Out-Null

        $script:Manifestes = @(
            [pscustomobject]@{ name = 'alpha'; email = 'a@a.test'; root = $script:RacineA }
            [pscustomobject]@{ name = 'beta'; email = 'b@b.test'; root = $script:RacineB }
            [pscustomobject]@{ name = 'gamma'; email = 'g@g.test'; root = $script:RacineC }
        )
    }
    AfterAll {
        # Les jonctions sont retirees comme liens, jamais suivies : le
        # nettoyage de $TestDrive les parcourrait, et une cible serait videe
        # deux fois.
        foreach ($j in @($script:Lien, $script:Entree, $script:Relais, $script:RacineC, (Join-Path $script:RacineA 'interne'))) {
            if (Test-Path -LiteralPath $j) { [System.IO.Directory]::Delete($j, $false) }
        }
    }

    Context 'Resolve-CtxCheminPhysique' {
        It 'rend un chemin sans lien tel quel' {
            InModuleScope DevContext -Parameters @{ p = (Join-Path $script:ProjetB 'src') } { param($p)
                Resolve-CtxCheminPhysique $p | Should -Be $p
            }
        }

        It 'remplace une jonction par sa cible, et garde la suite' {
            InModuleScope DevContext -Parameters @{ l = $script:Lien; b = $script:ProjetB } { param($l, $b)
                Resolve-CtxCheminPhysique (Join-Path $l 'src') | Should -Be (Join-Path $b 'src')
            }
        }

        It 'suit une jonction vers une jonction' {
            InModuleScope DevContext -Parameters @{ r = $script:Relais; b = $script:ProjetB } { param($r, $b)
                Resolve-CtxCheminPhysique (Join-Path $r 'lien\src') | Should -Be (Join-Path $b 'src')
            }
        }

        It 'garde la partie qui n existe pas encore' {
            InModuleScope DevContext -Parameters @{ l = $script:Lien; b = $script:ProjetB } { param($l, $b)
                Resolve-CtxCheminPhysique (Join-Path $l 'jamais\cree') | Should -Be (Join-Path $b 'jamais\cree')
            }
        }

        It 'rend $null plutot que de boucler sans fin' {
            # boucle\x -> boucle : chaque composant 'x' est un saut de plus.
            InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
                $boucle = Join-Path $t 'boucle'
                New-Item -ItemType Directory -Force -Path $boucle | Out-Null
                New-Item -ItemType Junction -Path (Join-Path $boucle 'x') -Target $boucle | Out-Null
                $lien = Join-Path $boucle 'x'
                try {
                    $long = [System.IO.Path]::Combine([string[]](@($boucle) + @(1..50 | ForEach-Object { 'x' })))
                    Resolve-CtxCheminPhysique $long | Should -BeNullOrEmpty
                }
                finally {
                    # Retiree ICI, et sans la suivre : le nettoyage de $TestDrive
                    # par Pester parcourt les jonctions, et celle-ci n'a pas de
                    # fond. Mesure : 'Framework failed', et un dossier
                    # orphelin dans %TEMP%.
                    [System.IO.Directory]::Delete($lien, $false)
                }
            }
        }

        It 'ne leve pas sur un lecteur absent' {
            InModuleScope DevContext {
                { Resolve-CtxCheminPhysique 'Q:\nexiste\pas' } | Should -Not -Throw
            }
        }
    }

    Context 'Resolve-DevContextForPath, le contrat que tous les appelants lisent' {
        It 'ne rend PLUS le contexte de l alias quand la cible appartient a un autre' {
            # LE defaut. Avant : 'alpha', et les jetons d'alpha sur les fichiers
            # de beta.
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien } { param($f, $l)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                Resolve-DevContextForPath -Path (Join-Path $l 'src') | Should -BeNullOrEmpty
            }
        }

        It 'ne rend pas non plus le contexte de la cible a qui y entre par un chemin etranger' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; e = $script:Entree } { param($f, $e)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                Resolve-DevContextForPath -Path $e | Should -BeNullOrEmpty
            }
        }

        It 'rend toujours le contexte d un dossier qui n emprunte aucun lien' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; b = $script:ProjetB } { param($f, $b)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                (Resolve-DevContextForPath -Path (Join-Path $b 'src')).name | Should -Be 'beta'
            }
        }

        It 'rend le contexte quand le lien reste dans la meme racine' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; a = $script:RacineA; b = $script:ProjetB } {
                param($f, $a, $b)
                $interne = Join-Path $a 'interne'
                $cible = Join-Path $a 'vrai'
                New-Item -ItemType Directory -Force -Path $cible | Out-Null
                if (-not (Test-Path $interne)) { New-Item -ItemType Junction -Path $interne -Target $cible | Out-Null }
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                (Resolve-DevContextForPath -Path $interne).name | Should -Be 'alpha'
            }
        }

        It 'ne choisit pas entre deux manifestes de meme racine, dans aucun ordre' {
            InModuleScope DevContext -Parameters @{ b = $script:RacineB; p = $script:ProjetB } { param($b, $p)
                $un = [pscustomobject]@{ name = 'beta'; root = $b }
                $deux = [pscustomobject]@{ name = 'copie'; root = "$b\" }
                Mock Get-CtxManifests ({ @($un, $deux) }.GetNewClosure())
                Resolve-DevContextForPath -Path $p | Should -BeNullOrEmpty
                Mock Get-CtxManifests ({ @($deux, $un) }.GetNewClosure())
                Resolve-DevContextForPath -Path $p | Should -BeNullOrEmpty
            }
        }

        It 'une racine-jonction ne possede rien, ni sous son nom (<Dossier> : <Etat>)' -ForEach @(
            @{ Dossier = 'racineC'; Etat = 'ambigu' }
            @{ Dossier = 'vraieC'; Etat = 'aucun' }
        ) {
            # Comme git, mesure le 30 octobre 2026 : `includeIf` ne s'applique
            # ni par le lien ni par le vrai dossier. Sous le lien, on refuse ;
            # dans le vrai dossier, personne -- jamais le message circulaire
            # "travaillez depuis le vrai dossier" a qui y est deja. C'est
            # `ctx doctor` qui dit quoi corriger.
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; d = (Join-Path $script:Monde "$Dossier\proj"); e = $Etat } { param($f, $d, $e)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                (Get-CtxProprietaire -Path $d).Etat | Should -Be $e
            }
        }

        It 'doctor nomme la racine-jonction et le vrai dossier a declarer' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; v = $script:VraieC } { param($f, $v)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $checks = @(Test-CtxDoctorRacinesLiens -Racines @(Get-CtxRacinesConnues -Physique))
                $checks.Count | Should -Be 1
                $checks[0].Sujet | Should -Be 'lien'
                $checks[0].Verdict | Should -Be 'PROBLEME'
                $checks[0].Detail | Should -Match 'gamma'
                $checks[0].Correctif | Should -Match ([regex]::Escape($v))
                Resolve-CtxRaisonManuelle -Domaine 'contexte' -Sujet 'lien' | Should -Not -BeNullOrEmpty
            }
        }

        It 'la decision ne touche plus le disque des racines' {
            # 21 s par commande pour un partage reseau injoignable, mesure par
            # l'audit du 30 octobre 2026. Seuls doctor et ctx new demandent la
            # forme physique.
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; b = $script:ProjetB } { param($f, $b)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                Mock Resolve-CtxCheminPhysique { param($Chemin) $Chemin }
                $null = Get-CtxProprietaire -Path $b
                Should -Invoke Resolve-CtxCheminPhysique -Times 1 -Exactly
            }
        }

        It 'resout un chemin sous un lecteur PowerShell par son chemin de fournisseur' {
            # .Path rendrait 'CtxFaux:\projet', qu'aucune racine ne prefixe.
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; b = $script:RacineB } { param($f, $b)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $null = New-PSDrive -Name CtxFaux -PSProvider FileSystem -Root $b
                try { (Get-CtxProprietaire -Path 'CtxFaux:\projet').Contexte | Should -Be 'beta' }
                finally { Remove-PSDrive -Name CtxFaux }
            }
        }

        It 'Get-CtxProprietaire nomme la raison et les contextes en jeu' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien; b = $script:ProjetB } {
                param($f, $l, $b)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $v = Get-CtxProprietaire -Path $l
                $v.Etat | Should -Be 'ambigu'
                $v.Raison | Should -Be 'alias-cible'
                @($v.Candidats) | Should -Be @('alpha', 'beta')
                $v.CheminPhysique | Should -Be $b
            }
        }
    }

    Context 'ctx et doctor, executes et non lus' {
        It 'ctx nomme l ambiguite dans son NO-GO' {
            # Execute, pas lu dans la source : retirer -Ambigu de Test-DevContext
            # laissait le test de source vert, et `ctx` tenait le dossier pour
            # "sans proprietaire". Mesure par mutation, revue du 30 octobre 2026.
            # gh est neutralise : aucun appel reseau ne part d'ici.
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien } { param($f, $l)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                Mock Get-CtxGhExe { throw 'gh neutralise par le test' }
                Push-Location -LiteralPath $l
                try { $sortie = Test-DevContext 6>&1 | Out-String }
                finally { Pop-Location }
                $sortie | Should -Match 'NO-GO'
                $sortie | Should -Match 'alias-cible'
            }
        }

        It 'doctor signale un doublon de racine, ou qu on se tienne' {
            InModuleScope DevContext -Parameters @{ b = $script:RacineB; t = $TestDrive } { param($b, $t)
                $un = [pscustomobject]@{ name = 'beta'; root = $b }
                $deux = [pscustomobject]@{ name = 'copie'; root = $b }
                Mock Get-CtxManifests ({ @($un, $deux) }.GetNewClosure())
                $avant = $env:CLAUDE_CONFIG_DIR
                $env:CLAUDE_CONFIG_DIR = Join-Path $t 'cfg-vide'
                $null = New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR
                try { $checks = @(Get-DevContextDoctor -Path $t) }
                finally {
                    # Restaurer, jamais supprimer.
                    if ($null -ne $avant) { $env:CLAUDE_CONFIG_DIR = $avant } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
                }
                $r = @($checks | Where-Object { $_.Domaine -eq 'contexte' -and $_.Sujet -eq 'racines' })
                $r.Count | Should -Be 1
                $r[0].Verdict | Should -Be 'PROBLEME'
                $r[0].Detail | Should -Match 'beta, copie'
            }
        }
    }

    Context 'Les garde-fous refusent d ecrire dans un dossier ambigu' {
        BeforeEach {
            $script:Avant = @{}
            foreach ($n in 'DEVCTX_ALLOW_GH', 'DEVCTX_ALLOW_VERCEL', 'DEVCTX_ALLOW_PROD', 'GH_CONFIG_DIR') {
                $script:Avant[$n] = [Environment]::GetEnvironmentVariable($n)
                [Environment]::SetEnvironmentVariable($n, $null)
            }
        }
        AfterEach {
            # Restaurer, jamais supprimer.
            foreach ($n in $script:Avant.Keys) { [Environment]::SetEnvironmentVariable($n, $script:Avant[$n]) }
        }

        It 'gh : une ecriture est refusee' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien } { param($f, $l)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $v = Resolve-CtxGhVerdict -Arguments @('pr', 'create', '--fill') -Path $l
                $v.Allowed | Should -BeFalse
                $v.Rule | Should -Be 'proprietaire-ambigu'
                $v.Reason | Should -Match 'alias-cible'
            }
        }

        It 'gh : une lecture passe, sans redirection, avec un avertissement' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien } { param($f, $l)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $v = Resolve-CtxGhVerdict -Arguments @('pr', 'list') -Path $l
                $v.Allowed | Should -BeTrue
                $v.Redirection | Should -BeNullOrEmpty
                $v.Avertissement | Should -Match 'alias-cible'
            }
        }

        It 'vercel : un deploiement est refuse, et aucune configuration n est injectee' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien } { param($f, $l)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $r = Resolve-CtxVercelVerdict -Arguments @('deploy') -Path $l
                $r.Verdict.Allowed | Should -BeFalse
                $r.Verdict.Rule | Should -Be 'proprietaire-ambigu'
                $r.ConfigDir | Should -BeNullOrEmpty
            }
        }

        It 'supabase : une commande destructrice est refusee, production ou non' {
            InModuleScope DevContext -Parameters @{ f = $script:Manifestes; l = $script:Lien } { param($f, $l)
                Mock Get-CtxManifests ({ $f }.GetNewClosure())
                $r = Resolve-CtxSupabaseVerdict -Arguments @('db', 'reset') -Path $l
                $r.Verdict.Allowed | Should -BeFalse
                $r.Verdict.Rule | Should -Be 'proprietaire-ambigu'
            }
        }
    }
}

Describe 'Les decisions des garde-fous, devant une ambiguite' {
    It 'gh : <Cas>' -ForEach @(
        @{ Cas = 'ecriture refusee'; Mots = @('pr', 'merge', '1'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'lecture permise'; Mots = @('repo', 'view'); Override = $false; Permis = $true; Regle = 'lecture-ambigue' }
        @{ Cas = 'derogation'; Mots = @('pr', 'merge', '1'); Override = $true; Permis = $true; Regle = 'derogation' }
        # Audit du 30 octobre 2026 : ces ecritures passaient pour des lectures.
        @{ Cas = 'pr new, alias de create'; Mots = @('pr', 'new'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'issue develop'; Mots = @('issue', 'develop', '3'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'api -XPOST colle'; Mots = @('api', '-XPOST', 'repos/o/r/issues'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'option devant le verbe'; Mots = @('-R', 'list', 'pr', 'merge'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'pr list'; Mots = @('pr', 'list', '--state', 'open'); Override = $false; Permis = $true; Regle = 'lecture-ambigue' }
        @{ Cas = 'version'; Mots = @('--version'); Override = $false; Permis = $true; Regle = 'lecture-ambigue' }
        # Contre-audit du 1er novembre 2026.
        @{ Cas = 'casse differente'; Mots = @('PR', 'LIST'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'auth status --show-token'; Mots = @('auth', 'status', '--show-token'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'auth status -t'; Mots = @('auth', 'status', '-t'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        # Audit final du 1er novembre 2026 : d'autres orthographes du meme drapeau.
        @{ Cas = 'auth status --show-token=true'; Mots = @('auth', 'status', '--show-token=true'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'auth status -at (groupe)'; Mots = @('auth', 'status', '-at'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'auth status -ta (groupe)'; Mots = @('auth', 'status', '-ta'); Override = $false; Permis = $false; Regle = 'proprietaire-ambigu' }
        @{ Cas = 'auth status'; Mots = @('auth', 'status'); Override = $false; Permis = $true; Regle = 'lecture-ambigue' }
    ) {
        InModuleScope DevContext -Parameters @{ a = $Mots; o = $Override; p = $Permis; r = $Regle } { param($a, $o, $p, $r)
            $v = Test-CtxGhGuard -Arguments $a -Ambiguite 'motif (alias-cible)' -Override:$o
            $v.Allowed | Should -Be $p
            $v.Rule | Should -Be $r
            $v.Redirection | Should -BeNullOrEmpty
        }
    }

    It 'vercel : <Cas>' -ForEach @(
        @{ Cas = 'vercel nu deploie'; Mots = @(); Permis = $false }
        @{ Cas = 'deploy'; Mots = @('deploy'); Permis = $false }
        @{ Cas = 'env add'; Mots = @('env', 'add', 'CLE'); Permis = $false }
        @{ Cas = 'commande inconnue'; Mots = @('nouveaute'); Permis = $false }
        @{ Cas = 'whoami'; Mots = @('whoami'); Permis = $true }
        @{ Cas = 'ls'; Mots = @('ls'); Permis = $true }
        @{ Cas = 'version'; Mots = @('--version'); Permis = $true }
        # Audit du 30 octobre 2026 : la valeur d'une option passait pour la commande.
        @{ Cas = 'valeur de --cwd'; Mots = @('--cwd', 'ls', '--prod'); Permis = $false }
        @{ Cas = 'valeur de -A'; Mots = @('-A', 'whoami', '--prod'); Permis = $false }
        @{ Cas = 'valeur de --scope'; Mots = @('--scope', 'help', '--prod'); Permis = $false }
        # Contre-audit du 1er novembre 2026 : la CLI prend `Logs` pour un dossier a deployer.
        @{ Cas = 'casse differente'; Mots = @('Logs', '--prod'); Permis = $false }
    ) {
        InModuleScope DevContext -Parameters @{ a = $Mots; p = $Permis } { param($a, $p)
            $v = Test-CtxVercelGuard -Arguments $a -Ambiguite 'motif (alias-cible)'
            $v.Allowed | Should -Be $p
            if (-not $p) { $v.Rule | Should -Be 'proprietaire-ambigu' }
        }
    }

    It 'vercel : la derogation passe' {
        InModuleScope DevContext {
            (Test-CtxVercelGuard -Arguments @('deploy') -Ambiguite 'motif' -Override).Allowed | Should -BeTrue
        }
    }

    It 'supabase : <Cas>' -ForEach @(
        @{ Cas = 'reset hors production'; Mots = @('db', 'reset'); Env = 'dev'; Permis = $false }
        @{ Cas = 'push sans environnement connu'; Mots = @('db', 'push'); Env = $null; Permis = $false }
        @{ Cas = 'lecture'; Mots = @('projects', 'list'); Env = $null; Permis = $true }
    ) {
        InModuleScope DevContext -Parameters @{ a = $Mots; e = $Env; p = $Permis } { param($a, $e, $p)
            $v = Test-CtxSupabaseGuard -Arguments $a -Environment $e -Ambiguite 'motif (racine-dupliquee)'
            $v.Allowed | Should -Be $p
            if (-not $p) { $v.Rule | Should -Be 'proprietaire-ambigu' }
        }
    }

    It 'supabase : la derogation passe' {
        InModuleScope DevContext {
            (Test-CtxSupabaseGuard -Arguments @('db', 'reset') -Ambiguite 'motif' -Override).Allowed | Should -BeTrue
        }
    }
}

Describe 'Les autres lecteurs de la propriete' {
    It 'l etiquette d un dossier ambigu n est jamais vide' {
        InModuleScope DevContext {
            Get-CtxEtiquetteProprietaire -Verdict ([pscustomobject]@{ Etat = 'ambigu'; Contexte = $null; Candidats = @('beta', 'perso') }) |
                Should -Be 'ambigu:beta+perso'
            Get-CtxEtiquetteProprietaire -Verdict ([pscustomobject]@{ Etat = 'ambigu'; Contexte = $null; Candidats = @() }) |
                Should -Be 'ambigu:?'
            Get-CtxEtiquetteProprietaire -Verdict ([pscustomobject]@{ Etat = 'proprietaire'; Contexte = 'perso'; Candidats = @('perso') }) |
                Should -Be 'perso'
            Get-CtxEtiquetteProprietaire -Verdict ([pscustomobject]@{ Etat = 'aucun'; Contexte = $null; Candidats = @() }) |
                Should -BeNullOrEmpty
        }
    }

    It 'ctx mcp refuse d ecrire dans un dossier ambigu' {
        # Audit du 30 octobre 2026 (H2) : sans index a lire, le projet passait
        # pour non-production et -Ecriture retirait --read-only, dans un
        # fichier fait pour etre commite.
        InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
            $d = Join-Path $t 'mcp-ambigu'
            New-Item -ItemType Directory -Force -Path (Join-Path $d 'proj') | Out-Null
            $un = [pscustomobject]@{ name = 'eps'; root = $d }
            $deux = [pscustomobject]@{ name = 'zeta'; root = $d }
            Mock Get-CtxManifests ({ @($un, $deux) }.GetNewClosure())
            { New-DevProjectMcp -Path (Join-Path $d 'proj') -Client claude -Ecriture -WhatIf } |
                Should -Throw -ExpectedMessage '*racine-dupliquee*'
        }
    }
}

Describe 'ctx et ctx doctor rendent le meme verdict sur un dossier ambigu' {
    It 'Get-CtxVerdictDossier fait passer l ambiguite avant tout le reste' {
        InModuleScope DevContext {
            foreach ($p in @('', 'alpha')) {
                foreach ($a in @('', 'alpha', 'beta')) {
                    Get-CtxVerdictDossier -Proprietaire $p -Actif $a -Ambigu | Should -Be 'proprietaireAmbigu'
                }
            }
        }
    }

    It 'la table de l axe proprietaire couvre chaque etat, et un PROBLEME n y est jamais muet chez ctx' {
        InModuleScope DevContext {
            foreach ($etat in @('accord', 'dossierSansActif', 'dossierAutre', 'sansProprietaire', 'neutre', 'proprietaireAmbigu')) {
                @($script:CtxAxeProprietaire.Keys) | Should -Contain $etat
            }
            $script:CtxAxeProprietaire['proprietaireAmbigu'].Doctor | Should -Be 'PROBLEME'
            foreach ($etat in $script:CtxAxeProprietaire.Keys) {
                $e = $script:CtxAxeProprietaire[$etat]
                if ($e.Doctor -eq 'PROBLEME') { $e.Ctx | Should -Be 'probleme' -Because "etat '$etat'" }
                if ($e.Doctor -eq 'ATTENTION') { $e.Ctx | Should -Not -Be 'rien' -Because "etat '$etat'" }
            }
        }
    }

    It 'doctor rend, pour chaque etat, le verdict que la table annonce' {
        # Le verdict attendu de l'etat ambigu est ECRIT en clair dans le test
        # precedent ; celui-ci tient l'autre moitie : doctor LIT la table.
        InModuleScope DevContext {
            $ambigu = [pscustomobject]@{ Etat = 'ambigu'; Manifeste = $null; Contexte = $null; Raison = 'racine-dupliquee'; Candidats = @('alpha', 'copie'); CheminPhysique = 'F:\P\A' }
            $sain = [pscustomobject]@{ Etat = 'proprietaire'; Manifeste = [pscustomobject]@{ name = 'alpha' }; Contexte = 'alpha'; Raison = $null; Candidats = @('alpha'); CheminPhysique = 'F:\P\A' }
            $aucun = [pscustomobject]@{ Etat = 'aucun'; Manifeste = $null; Contexte = $null; Raison = $null; Candidats = @(); CheminPhysique = 'C:\x' }
            foreach ($cas in @(
                    @{ V = $ambigu; A = 'alpha'; E = 'proprietaireAmbigu' }
                    @{ V = $sain; A = 'alpha'; E = 'accord' }
                    @{ V = $sain; A = 'beta'; E = 'dossierAutre' }
                    @{ V = $sain; A = ''; E = 'dossierSansActif' }
                    @{ V = $aucun; A = 'alpha'; E = 'sansProprietaire' }
                    @{ V = $aucun; A = ''; E = 'neutre' }
                )) {
                $c = Test-CtxDoctorProprietaire -Verdict $cas.V -Actif $cas.A
                $c.Domaine | Should -Be 'contexte'
                $c.Sujet | Should -Be 'proprietaire'
                $c.Verdict | Should -Be $script:CtxAxeProprietaire[$cas.E].Doctor -Because "etat '$($cas.E)'"
            }
            $c = Test-CtxDoctorProprietaire -Verdict $ambigu -Actif 'alpha'
            $c.Detail | Should -Match 'racine-dupliquee'
            $c.Detail | Should -Match 'alpha, copie'
        }
    }

    It 'doctor propose une commande qui survit a une apostrophe dans le chemin' {
        InModuleScope DevContext {
            $v = [pscustomobject]@{ Etat = 'ambigu'; Manifeste = $null; Contexte = $null; Raison = 'alias-cible'; Candidats = @('alpha'); CheminPhysique = "C:\O'Brien\x" }
            (Test-CtxDoctorProprietaire -Verdict $v -Actif 'alpha').Correctif |
                Should -Be "Set-Location -LiteralPath 'C:\O''Brien\x'"
        }
    }

    It 'doctor signale chaque groupe de racines dupliquees, et -Fix sait pourquoi il n y touche pas' {
        InModuleScope DevContext {
            $checks = @(Test-CtxDoctorRacines -Groupes @([pscustomobject]@{ Racine = 'F:\P\A'; Contextes = @('alpha', 'copie') }))
            $checks.Count | Should -Be 1
            $checks[0].Domaine | Should -Be 'contexte'
            $checks[0].Sujet | Should -Be 'racines'
            $checks[0].Verdict | Should -Be 'PROBLEME'
            $checks[0].Detail | Should -Match 'alpha, copie'
            Resolve-CtxRaisonManuelle -Domaine 'contexte' -Sujet 'racines' | Should -Not -BeNullOrEmpty
            @(Test-CtxDoctorRacines -Groupes @()).Count | Should -Be 0
        }
    }

    It 'doctor et ctx consomment la meme resolution' {
        foreach ($f in @('Test-DevContext', 'Get-DevContextDoctor')) {
            $src = Get-SourceSansCommentaires $f
            $src | Should -Match '(?<![\w-])Get-CtxProprietaire(?![\w-])' -Because "dans $f"
            $src | Should -Not -Match '(?<![\w-])Resolve-DevContextForPath(?![\w-])' -Because "$f doit voir l'ambiguite, pas un `$null"
        }
        (Get-SourceSansCommentaires Get-DevContextDoctor) | Should -Match '(?<![\w-])Test-CtxDoctorProprietaire(?![\w-])'
        (Get-SourceSansCommentaires Get-DevContextDoctor) | Should -Match '(?<![\w-])Test-CtxDoctorRacines(?![\w-])'
        (Get-SourceSansCommentaires Get-DevContextDoctor) | Should -Match '(?<![\w-])Test-CtxDoctorRacinesLiens(?![\w-])'
    }

    It 'ctx range l etat ambigu dans les problemes qu un work ne regle pas' {
        $src = Get-SourceSansCommentaires Test-DevContext
        $src | Should -Match "'proprietaireAmbigu'\s*\{\s*\`$problems\s*\+="
        $src | Should -Match "'proprietaireAmbigu'\s*\{[^}]*\`$problemsHorsWork\+\+"
    }
}

Describe 'ctx new et doctor devant une racine qu on ne peut pas lire' {
    It 'ctx new dit "illisible", pas "lien vers ?"' {
        InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
            $racine = Join-Path $t 'injoignable'
            Mock Get-CtxManifests { @() }
            Mock Test-CtxVault { }
            Mock Get-CtxPath ({ [System.IO.Path]::Combine($t, 'ctx-illisible') }.GetNewClosure())
            Mock Resolve-CtxCheminPhysique { $null }
            { New-DevContext -Name 'illisible' -Email 'i@i.test' -Root $racine -GitUserName 'i' -NoKey -WhatIf } |
                Should -Throw -ExpectedMessage (T 'new.racineIllisible' $racine)
        }
    }

    It 'doctor ne resout pas une racine UNC (21 s par partage injoignable)' {
        InModuleScope DevContext {
            $m = [pscustomobject]@{ name = 'nas'; root = '\\192.0.2.1\share\clients' }
            Mock Get-CtxManifests ({ @($m) }.GetNewClosure())
            Mock Resolve-CtxCheminPhysique { 'ne-devait-pas-etre-appele' }
            $r = @(Get-CtxRacinesConnues -Physique)
            Should -Invoke Resolve-CtxCheminPhysique -Times 0 -Exactly
            $r[0].RacinePhysique | Should -Be '\\192.0.2.1\share\clients'
        }
    }
}

Describe 'ctx new refuse une racine deja prise, physiquement' {
    It 'refuse une racine qui est elle-meme une jonction, en nommant le vrai dossier' {
        InModuleScope DevContext -Parameters @{ t = $TestDrive } { param($t)
            $vraie = Join-Path $t 'new-vraie'
            $alias = Join-Path $t 'new-alias'
            New-Item -ItemType Directory -Force -Path $vraie | Out-Null
            New-Item -ItemType Junction -Path $alias -Target $vraie | Out-Null
            $existant = [pscustomobject]@{ name = 'existant'; root = $vraie }
            Mock Get-CtxManifests ({ @($existant) }.GetNewClosure())
            Mock Test-CtxVault { }
            Mock Get-CtxPath ({ [System.IO.Path]::Combine($t, 'ctx-nouveau') }.GetNewClosure())
            try {
                # -WhatIf : si le controle manquait, rien ne serait cree pour autant.
                { New-DevContext -Name 'nouveau' -Email 'n@n.test' -Root $alias -GitUserName 'n' -NoKey -WhatIf } |
                    Should -Throw -ExpectedMessage "*$vraie*"
            }
            finally { [System.IO.Directory]::Delete($alias, $false) }
        }
    }
}
