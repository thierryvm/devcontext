# ===========================================================================
# 24 aout 2026 -- retour d'usage d'un agent, docs/retours/2026-08-24-usage-agent.md
#
# Mesure ce jour-la, meme dossier, meme processus :
#
#     ctx         ->  GO - identite, dossier et compte concordent.
#     ctx doctor  ->  PROBLEME  git  identite  <adresse A> au lieu de <attendue>
#
# Un seul fait, deux verdicts, dont un faux. C'est la DEUXIEME fois : le
# 19 aout 2026, Get-CtxVerdictDossier corrigeait exactement cette forme sur
# l'axe du proprietaire. Meme cause de fond -- une regle ecrite a deux endroits
# finit toujours par diverger, et c'est celle qu'on croit qui ment.
#
# Ce fichier eprouve la FAMILLE, pas seulement le cas trouve : les decisions
# partagees entre `ctx` et `ctx doctor`, et la regle qui les lie.
# ===========================================================================

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force

    # La source d'une fonction, PRIVEE DE SES COMMENTAIRES.
    #
    # Sans cela ces tests se mentent a eux-memes dans les deux sens : un
    # commentaire qui NOMME le piege ('jamais remote.origin.url') declenche une
    # assertion de non-presence, et un commentaire qui cite la bonne commande
    # SATISFAIT une assertion de presence sans qu'une ligne de code existe.
    # Mesure le 24 aout 2026 : le premier cas, sur ce fichier meme.
    #
    # Les commentaires sont remplaces par des espaces de MEME longueur, jamais
    # supprimes : les motifs qui portent sur des mots adjacents
    # ('$problems.Count -eq $problemsHorsWork') survivent intacts.
    function Get-CtxSourceSansCommentaires {
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

Describe 'Get-CtxVerdictGitIdentite' {
    It 'rend <Attendu> quand attendu=<A>, reel=<R>, origine=<O>' -ForEach @(
        @{ A = ''; R = 'x@y.z'; O = '.git/config'; Attendu = 'horsContexte' }
        @{ A = 'a@b.c'; R = ''; O = ''; Attendu = 'sansEmail' }
        @{ A = 'a@b.c'; R = 'autre@b.c'; O = 'C:/Users/x/.gitconfig'; Attendu = 'mauvaisEmail' }
        @{ A = 'a@b.c'; R = 'a@b.c'; O = 'C:/depot/.git/config'; Attendu = 'emailEnDur' }
        @{ A = 'a@b.c'; R = 'a@b.c'; O = 'F:/CTX/perso/gitconfig'; Attendu = 'accord' }
    ) {
        InModuleScope DevContext -Parameters @{ a = $A; r = $R; o = $O; att = $Attendu } {
            param($a, $r, $o, $att)
            Get-CtxVerdictGitIdentite -EmailAttendu $a -EmailReel $r -Origine $o | Should -Be $att
        }
    }

    It 'reconnait le .git/config quel que soit le separateur' {
        # git rend des slashes sur Windows AUJOURD'HUI. Faire dependre un
        # controle de cette habitude est le genre d'hypothese qui casse ailleurs.
        InModuleScope DevContext {
            foreach ($o in @('C:\depot\.git\config', 'C:/depot/.git/config', '.git/config', '.git\config')) {
                Get-CtxVerdictGitIdentite -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' -Origine $o |
                    Should -Be 'emailEnDur' -Because "origine '$o'"
            }
        }
    }

    It 'ne confond pas un fichier nomme gitconfig avec le .git/config d un depot' {
        InModuleScope DevContext {
            Get-CtxVerdictGitIdentite -EmailAttendu 'a@b.c' -EmailReel 'a@b.c' `
                -Origine 'F:/CTX/perso/gitconfig' | Should -Be 'accord'
        }
    }

    It 'ne rend jamais un etat absent de la table des verdicts' {
        # Un etat inconnu ne tomberait dans aucune branche : ni refus, ni
        # remarque, ni rien -- un silence qu'aucun test ne verrait.
        InModuleScope DevContext {
            foreach ($a in @('', $null, 'a@b.c')) {
                foreach ($r in @('', $null, 'a@b.c', 'autre@b.c')) {
                    foreach ($o in @('', $null, '.git/config', '~/.gitconfig')) {
                        $etat = Get-CtxVerdictGitIdentite -EmailAttendu $a -EmailReel $r -Origine $o
                        @($script:CtxAxeGitIdentite.Keys) | Should -Contain $etat
                    }
                }
            }
        }
    }
}

Describe 'la table des verdicts n est pas decorative' {
    It 'ctx doctor rend <V> pour <Etat>' -ForEach @(
        @{ Etat = 'horsContexte'; V = 'INFO'; A = ''; R = 'x@y.z'; O = '' }
        @{ Etat = 'sansEmail'; V = 'PROBLEME'; A = 'a@b.c'; R = ''; O = '' }
        @{ Etat = 'mauvaisEmail'; V = 'PROBLEME'; A = 'a@b.c'; R = 'autre@b.c'; O = '~/.gitconfig' }
        @{ Etat = 'emailEnDur'; V = 'ATTENTION'; A = 'a@b.c'; R = 'a@b.c'; O = '.git/config' }
        @{ Etat = 'accord'; V = 'OK'; A = 'a@b.c'; R = 'a@b.c'; O = '~/.gitconfig' }
    ) {
        # Le verdict attendu est ECRIT ICI, pas relu dans la table.
        #
        # Le comparer a la table serait une tautologie : Test-CtxDoctorIdentiteGit
        # LIT cette table, donc les deux cotes bougeraient ensemble et le test ne
        # pourrait plus jamais rougir. Ecrit en clair, il tient les deux moitiees :
        # doctor consulte bien la decision partagee (il rougit si un verdict
        # revient en dur dans Doctor.ps1), ET la doctrine elle-meme ne change pas
        # par accident (il rougit si une ligne de la table est modifiee).
        InModuleScope DevContext -Parameters @{ etat = $Etat; v = $V; a = $A; r = $R; o = $O } {
            param($etat, $v, $a, $r, $o)
            $c = Test-CtxDoctorIdentiteGit -EmailAttendu $a -EmailReel $r -Origine $o
            $c.Verdict | Should -Be $v
            $c.Domaine | Should -Be 'git'
            $c.Sujet   | Should -Be 'identite'

            # ... et la table annonce la meme chose que ce que doctor a rendu.
            $script:CtxAxeGitIdentite[$etat].Doctor | Should -Be $v
        }
    }

    It 'un PROBLEME chez doctor ne peut pas etre un silence chez ctx' {
        # LA regle du retour, en une assertion. Un ATTENTION peut n'etre qu'une
        # remarque -- la valeur est juste, il n'y a aucun degat -- mais il ne
        # peut pas etre muet non plus.
        InModuleScope DevContext {
            foreach ($etat in $script:CtxAxeGitIdentite.Keys) {
                $e = $script:CtxAxeGitIdentite[$etat]
                switch ($e.Doctor) {
                    'PROBLEME' { $e.Ctx | Should -Be 'probleme' -Because "etat '$etat'" }
                    'ATTENTION' { $e.Ctx | Should -Not -Be 'rien' -Because "etat '$etat'" }
                    default { $e.Ctx | Should -Be 'rien' -Because "etat '$etat'" }
                }
            }
        }
    }
}

Describe 'aucune ligne affichee par ctx n echappe a un verdict' {
    # Les DEUX cotes sont derives : les lignes affichees viennent des fichiers
    # de langue, les decisions appelees de la source de Test-DevContext. Seul
    # l'appariement est declare, dans $script:CtxAxesAffiches.
    #
    # Ce test aurait attrape les trois defauts du 24 aout 2026 d'un coup :
    # ctx.git, ctx.remote et ctx.vercel etaient affiches sans qu'aucune
    # decision ne soit appelee pour eux.
    #
    # CE QU'IL NE COUVRE PAS, et il faut le dire aussi : il verifie qu'une
    # decision est APPELEE, pas que le canal choisi est le bon. C'est la table
    # $script:CtxAxeGitIdentite, eprouvee juste au-dessus, qui tient cette
    # seconde moitie -- et seulement pour l'axe de l'identite git.

    It 'toute ligne de fait affichee est inscrite dans la table des axes' {
        $source = Get-CtxSourceSansCommentaires 'Test-DevContext'
        InModuleScope DevContext -Parameters @{ source = $source } {
            param($source)
            $lang = Import-PowerShellDataFile -LiteralPath (
                Join-Path (Split-Path (Get-Module DevContext).Path -Parent) 'lang/fr.psd1')

            # Une ligne de FAIT est alignee en colonne dans cet ecran : c'est ce
            # qui la distingue d'un correctif ('Correctif : {0}', une seule
            # espace avant le deux-points) ou d'un titre.
            $lignesDeFait = @($lang.Keys | Where-Object {
                    $_ -like 'ctx.*' -and "$($lang[$_])" -match '^\S.*\s{2,}:\s\{0\}$' })

            $affichees = @($lignesDeFait | Where-Object { $source -match [regex]::Escape("T '$_'") })

            $affichees.Count | Should -BeGreaterThan 3 -Because 'sinon le filtre ne mesure plus rien'
            foreach ($cle in $affichees) {
                @($script:CtxAxesAffiches.Keys) | Should -Contain $cle `
                    -Because "'$cle' est affichee par ctx sans etre inscrite comme axe juge"
            }
        }
    }

    It 'tout axe inscrit appelle reellement la decision qu il annonce' {
        # Sans ceci, la table pourrait nommer une decision que plus personne
        # n'appelle -- et elle aurait l'air de fonctionner.
        $source = Get-CtxSourceSansCommentaires 'Test-DevContext'
        InModuleScope DevContext -Parameters @{ source = $source } {
            param($source)
            foreach ($cle in $script:CtxAxesAffiches.Keys) {
                $decision = $script:CtxAxesAffiches[$cle]
                if ($null -eq $decision) { continue }

                # Le nom doit etre ENTIER. Mesure du 25 aout 2026 : sans les
                # bornes, renommer l'appel en 'Get-CtxVerdictGitIdentiteJAMAIS'
                # laissait ce test vert -- le nom inscrit restait une
                # sous-chaine de celui appele. Le test attrapait donc tout sauf
                # la faute la plus probable, une faute de frappe.
                # Bornes explicites plutot que \b : un nom de fonction
                # PowerShell contient des tirets, et \b les prend pour des
                # frontieres.
                $source | Should -Match "(?<![\w-])$([regex]::Escape($decision))(?![\w-])" `
                    -Because "l'axe '$cle' annonce la decision '$decision'"
            }
        }
    }

    It 'les decisions nommees existent vraiment' {
        InModuleScope DevContext {
            foreach ($cle in $script:CtxAxesAffiches.Keys) {
                $decision = $script:CtxAxesAffiches[$cle]
                if ($null -eq $decision) { continue }
                Get-Command $decision -ErrorAction SilentlyContinue |
                    Should -Not -BeNullOrEmpty -Because "l'axe '$cle' nomme '$decision'"
            }
        }
    }
}

Describe 'Get-CtxVerdictRemoteSansContexte' {
    # Section 3 du retour : hors de toute racine, l'identite ET le remote echappent au
    # contexte. La remarque existante ne disait que la premiere moitie, la plus
    # inoffensive.

    It 'rend <Attendu> pour "<U>" (assistant=<H>)' -ForEach @(
        @{ U = ''; H = $false; Attendu = 'pasDepot' }
        @{ U = 'git@github-perso:org/depot.git'; H = $false; Attendu = 'ssh' }
        @{ U = 'ssh://git@github.com/org/depot.git'; H = $false; Attendu = 'ssh' }
        @{ U = 'https://github.com/org/depot.git'; H = $true; Attendu = 'httpsAssiste' }
        @{ U = 'https://github.com/org/depot.git'; H = $false; Attendu = 'httpsNu' }
        # Le piege du 5 aout 2026 : un login dans l'URL reste du HTTPS, et la
        # regle insteadOf -- un prefixe de chaine -- ne s'y applique pas.
        @{ U = 'https://login@github.com/org/depot.git'; H = $true; Attendu = 'httpsAssiste' }
        @{ U = 'https://login@github.com/org/depot.git'; H = $false; Attendu = 'httpsNu' }
    ) {
        InModuleScope DevContext -Parameters @{ u = $U; h = $H; att = $Attendu } {
            param($u, $h, $att)
            Get-CtxVerdictRemoteSansContexte -UrlPush $u -AssistantIdentifiants:$h | Should -Be $att
        }
    }
}

Describe 'les pieges de redaction nommes par le retour du 24 aout 2026' {
    It 'ctx lit le remote de PUSH, jamais remote.origin.url' {
        # `insteadOf` reecrit l'URL au moment de l'usage : la valeur STOCKEE
        # peut rester https://github.com/... alors que le push part par la cle
        # SSH du contexte. Un controle bati sur elle serait vert des DEUX cotes
        # de la frontiere -- et il aurait l'air de marcher.
        $source = Get-CtxSourceSansCommentaires 'Test-DevContext'
        $source | Should -Match 'remote get-url --push'
        $source | Should -Not -Match 'remote\.origin\.url'
    }

    It 'ctx resout l assistant d identifiants par URL, pas par la cle globale' {
        # Mesure du 24 aout 2026 : `git config --get-all credential.helper` ne
        # rend RIEN sur la machine de l'auteur, alors qu'un assistant existe
        # bel et bien sous `credential.https://github.com.helper`. Lire la cle
        # globale ferait annoncer une invite bloquante la ou le push part en
        # silence sous le compte global : un diagnostic faux dans les deux sens.
        Get-CtxSourceSansCommentaires 'Test-DevContext' |
            Should -Match '--get-urlmatch credential\.helper'
    }
}

Describe 'Get-CtxVerdictVercelSession' {
    It 'rend <Attendu> (dossier=<D>, proprietaire=<P>, session=<S>)' -ForEach @(
        @{ D = $false; P = 'perso'; S = ''; Attendu = 'sansProjet' }
        @{ D = $true; P = 'perso'; S = ''; Attendu = 'sansSession' }
        @{ D = $true; P = 'perso'; S = 'F:\CTX\perso\vercel'; Attendu = 'ok' }
        # Sans proprietaire, aucune session dediee n'est attendue : le dire
        # serait reprocher une absence normale.
        @{ D = $true; P = ''; S = ''; Attendu = 'ok' }
    ) {
        InModuleScope DevContext -Parameters @{ d = $D; p = $P; s = $S; att = $Attendu } {
            param($d, $p, $s, $att)
            Get-CtxVerdictVercelSession -ADossierVercel:$d -Proprietaire $p -ConfigSession $s |
                Should -Be $att
        }
    }

    It 'est cherche avec Join-Path, sans separateur en dur' {
        # '.vercel\project.json' ne designe rien sur macOS ni Linux : le
        # controle y serait MUET au lieu d'etre faux, ce qui est pire.
        #
        # `Get-DevContextDoctor` -- et non `Invoke-...` : ecrire un nom qui
        # n'existe pas ferait echouer ce test sur Get-Command, en donnant
        # l'illusion d'avoir mesure le second cote.
        foreach ($f in @('Test-DevContext', 'Get-DevContextDoctor')) {
            Get-CtxSourceSansCommentaires $f |
                Should -Not -Match '\.vercel\\project\.json' -Because "dans $f"
        }
    }
}

Describe 'un NO-GO ne propose pas une commande sans effet' {
    It 'work n est propose que si au moins un probleme s en trouve regle' {
        # `work <ctx> -NoCd` ne retire pas un user.email ecrit en dur, ni un
        # login dans une URL de remote. Proposer quand meme cette commande
        # serait le cri au loup retourne contre le module -- exactement ce qui
        # a ete corrige le 19 aout 2026 sur un autre axe.
        $source = Get-CtxSourceSansCommentaires 'Test-DevContext'
        $source | Should -Match '\$problems\.Count -eq \$problemsHorsWork'
        $source | Should -Match '\$problemsHorsWork\+\+'
    }
}

Describe 'Get-CtxOrigineConfigGit' {
    # Le separateur de `git config --show-origin` est une TABULATION. Deux
    # ecritures maison le decoupaient sur '\s', et tronquaient donc tout chemin
    # portant une espace -- 'C:/Users/John Doe/.gitconfig' devenait
    # 'C:/Users/John', un fichier qui n'existe pas.
    It 'rend "<Attendu>" pour <Cas>' -ForEach @(
        @{ Cas = 'un chemin ordinaire'
            L = "file:C:/Users/x/.gitconfig`tx@y.z"; Attendu = 'C:/Users/x/.gitconfig' }
        @{ Cas = 'un chemin AVEC UNE ESPACE'
            L = "file:C:/Users/John Doe/.gitconfig`tx@y.z"; Attendu = 'C:/Users/John Doe/.gitconfig' }
        @{ Cas = 'le config relatif d un depot'
            L = "file:.git/config`tx@y.z"; Attendu = '.git/config' }
        # Une valeur peut elle aussi porter des espaces : le decoupage ne doit
        # regarder que la PREMIERE tabulation.
        @{ Cas = 'une valeur contenant des espaces'
            L = "file:F:/CTX/perso/gitconfig`tJohn Doe <j@d.z>"; Attendu = 'F:/CTX/perso/gitconfig' }
        @{ Cas = 'rien du tout'; L = ''; Attendu = '' }
        @{ Cas = 'null'; L = $null; Attendu = '' }
    ) {
        InModuleScope DevContext -Parameters @{ l = $L; att = $Attendu } {
            param($l, $att)
            Get-CtxOrigineConfigGit $l | Should -BeExactly $att
        }
    }

    It 'est la SEULE ecriture de ce decoupage' {
        # Deux exemplaires d'une meme regle finissent toujours par diverger --
        # c'est le sujet meme de ce fichier. Celui-ci a diverge en fragilite
        # identique plutot qu'en comportement, ce qui est encore plus discret.
        foreach ($f in @('Test-DevContext', 'Get-DevContextDoctor')) {
            $src = Get-CtxSourceSansCommentaires $f
            $src | Should -Not -Match 'show-origin[^\r\n]*-split' -Because "dans $f"
            $src | Should -Not -Match 'show-origin[^\r\n]*-replace' -Because "dans $f"
        }
    }
}
