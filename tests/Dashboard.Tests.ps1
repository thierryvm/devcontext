# Le tableau de bord : le rendu pur.
#
# Ce fichier ne touche pas le disque, parce que la fonction qu'il teste n'y
# touche pas non plus. C'est tout l'interet de la separation : la moitie qui
# decide de ce qui s'affiche se verifie sans machine configuree, sans contexte
# actif, et sans jeton charge.
#
# Trois proprietes sont tenues ici, et elles viennent du plan de la tranche :
# l'echappement CHAMP PAR CHAMP, l'absence de toute ressource distante, et le
# fait que chaque section vide nomme la commande suivante.

BeforeAll {
    $script:Racine = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:Racine 'DevContext.psd1') -Force

    # Les cinq caracteres qui comptent, dans une seule charge. Un test par
    # caractere separe dirait moins : ce qui casse en vrai, c'est une valeur
    # reelle qui les melange.
    $script:Charge = '<script>alert("x")&' + "'" + '</script>'
}

Describe 'ConvertTo-CtxHtmlTexte' {
    It 'echappe l esperluette AVANT les autres substitutions' {
        # Si l'ordre s'inverse, '<' devient '&amp;lt;' : la page affiche le code
        # de l'entite au lieu du caractere, et le defaut ne se voit qu'a l'oeil.
        $r = InModuleScope DevContext { ConvertTo-CtxHtmlTexte '&<' }
        $r | Should -BeExactly '&amp;&lt;'
    }

    It 'echappe <_>' -ForEach @('<', '>', '&', '"', "'") {
        $r = InModuleScope DevContext -Parameters @{ c = $_ } { param($c) ConvertTo-CtxHtmlTexte $c }
        $r | Should -Not -BeExactly $_
        $r | Should -Match '^&[a-z#0-9]+;$'
    }

    It 'rend une chaine vide pour un null, jamais le mot null' {
        $r = InModuleScope DevContext { ConvertTo-CtxHtmlTexte $null }
        $r | Should -BeExactly ''
    }
}

Describe 'Format-CtxDashboardHtml' {
    BeforeAll {
        # Arrange dans la portee du TEST, jamais dans InModuleScope : une
        # fonction definie dans un BeforeAll n'existe pas dans la portee du
        # module, et l'appeler de la-bas rend un CommandNotFoundException qui
        # se lit comme une fonction de src/ manquante. Piege consigne dans
        # AGENTS.md, cinq tests rouges le 19 aout 2026.
        function New-FaitsAvecCharge {
            param(
                [Parameter(Mandatory)][AllowEmptyString()][string]$Section,
                [Parameter(Mandatory)][string]$Champ,
                [Parameter(Mandatory)][string]$Charge
            )
            # Une base inoffensive, puis la charge a UN seul endroit : ce qui
            # rougit nomme alors le champ, pas la page.
            $faits = @{ Dossier = 'D'; Proprietaire = 'p'; Actif = 'a' }
            if (-not $Section) {
                $faits[$Champ] = $Charge
                return [pscustomobject]$faits
            }
            $element = switch ($Section) {
                'Checks' { @{ Domaine = 'd'; Sujet = 's'; Verdict = 'OK'; Detail = ''; Correctif = '' } }
                'Contextes' { @{ Nom = 'n'; Racine = 'r'; Compte = 'c' } }
                'Editeurs' { @{ Nom = 'n'; Isolable = $true; Chemin = 'c' } }
                'Raccourcis' { @{ Sujet = 's'; Verdict = 'OK'; Detail = '' } }
                'Supabase' { @{ Projet = 'p'; Contexte = 'c'; Cle = 'k'; Env = 'e' } }
                'Mcp' { @{ Nom = 'n'; Libelle = 'l'; Chemin = 'c' } }
            }
            $element[$Champ] = $Charge
            $faits[$Section] = @([pscustomobject]$element)
            [pscustomobject]$faits
        }

        function Get-Html {
            param([Parameter(Mandatory)][AllowNull()]$Faits)
            InModuleScope DevContext -Parameters @{ f = $Faits } {
                param($f) Format-CtxDashboardHtml -Faits $f -Genere '2026-01-01 00:00'
            }
        }
    }

    Context 'Echappement, champ par champ' {
        # UN TEST PAR CHAMP, et non un test global sur une page ou tout est
        # rempli. Le test global passerait au vert le jour ou un seul champ
        # cesserait d'etre echappe, tant que les autres le sont encore -- et
        # c'est exactement le champ qu'on aurait ajoute sans y penser.
        It '<Section>/<Champ>' -ForEach @(
            @{ Section = ''; Champ = 'Dossier' }
            @{ Section = ''; Champ = 'Proprietaire' }
            @{ Section = ''; Champ = 'Actif' }
            @{ Section = 'Checks'; Champ = 'Domaine' }
            @{ Section = 'Checks'; Champ = 'Sujet' }
            @{ Section = 'Checks'; Champ = 'Detail' }
            @{ Section = 'Checks'; Champ = 'Correctif' }
            @{ Section = 'Contextes'; Champ = 'Nom' }
            @{ Section = 'Contextes'; Champ = 'Racine' }
            @{ Section = 'Contextes'; Champ = 'Compte' }
            @{ Section = 'Editeurs'; Champ = 'Nom' }
            @{ Section = 'Editeurs'; Champ = 'Chemin' }
            @{ Section = 'Raccourcis'; Champ = 'Sujet' }
            @{ Section = 'Raccourcis'; Champ = 'Detail' }
            @{ Section = 'Supabase'; Champ = 'Projet' }
            @{ Section = 'Supabase'; Champ = 'Contexte' }
            @{ Section = 'Supabase'; Champ = 'Cle' }
            @{ Section = 'Supabase'; Champ = 'Env' }
            @{ Section = 'Mcp'; Champ = 'Nom' }
            @{ Section = 'Mcp'; Champ = 'Libelle' }
            @{ Section = 'Mcp'; Champ = 'Chemin' }
        ) {
            $html = Get-Html (New-FaitsAvecCharge -Section $Section -Champ $Champ -Charge $script:Charge)

            $html | Should -Not -BeLike '*<script>*' -Because "le champ $Section/$Champ n est pas echappe"
            $html | Should -BeLike '*&lt;script&gt;*' -Because 'la valeur doit rester LISIBLE, pas disparaitre'
            $html | Should -BeLike '*&quot;*'
            $html | Should -BeLike '*&#39;*'
        }
    }

    Context 'Autonomie de la page' {
        BeforeAll {
            $script:Page = Get-Html ([pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p'; Actif = 'a' })
        }

        It 'ne reference aucune ressource distante' {
            # Contrainte du plan : une page qui appelle le reseau depuis un
            # outil d'identifiants annonce la topologie de son porteur a qui
            # heberge la ressource. Verifie sur la SORTIE, pas sur l'intention.
            foreach ($motif in @('http://', 'https://', 'src="//', 'href="//', '@import')) {
                $script:Page | Should -Not -BeLike "*$motif*" -Because "'$motif' est une requete sortante"
            }
        }

        It 'ne contient ni script ni feuille de style liee' {
            $script:Page | Should -Not -BeLike '*<script*'
            $script:Page | Should -Not -BeLike '*<link*'
        }

        It 'declare une politique de securite qui interdit tout par defaut' {
            # La page peut DECLARER ce qu'elle s'interdit, et le navigateur le
            # fait respecter. L'intention ne protege pas ; la declaration, si.
            $script:Page | Should -BeLike '*Content-Security-Policy*'
            $script:Page | Should -BeLike "*default-src 'none'*"
        }
    }

    Context 'Les etats vides nomment la commande suivante' {
        BeforeAll {
            # Aucune section fournie : c'est la machine vierge, et c'est l'ecran
            # le plus important du produit.
            $script:Nue = Get-Html ([pscustomobject]@{ Dossier = 'D' })
        }

        It 'la section vide propose <_>' -ForEach @(
            'ctx doctor', 'ctx init', 'ctx editors', 'ctx shortcut', 'sb-index', 'ctx mcp'
        ) {
            # L'assertion porte sur la COMMANDE, jamais sur la phrase : la
            # phrase est traduite, la commande ne l'est pas. Decider sur du
            # texte affiche est le piege que ce depot a paye quatre fois.
            $script:Nue | Should -BeLike "*$_*" -Because 'une section vide qui ne dit pas quoi faire est une impasse'
        }

        It 'ne rend aucun tableau vide' {
            $script:Nue | Should -Not -BeLike '*<tbody></tbody>*'
        }
    }

    Context 'Purete' {
        It 'rend le meme octet pour les memes faits et le meme horodatage' {
            $faits = [pscustomobject]@{ Dossier = 'D'; Proprietaire = 'p' }
            (Get-Html $faits) | Should -BeExactly (Get-Html $faits)
        }

        It 'ne lit pas l horloge : sans horodatage fourni, deux appels restent identiques' {
            # CE TEST EXISTE PARCE QUE LE PRECEDENT NE SUFFISAIT PAS, et la
            # preuve de morsure l'a dit. Il s'appelait « ne connait pas
            # l heure » et passait -Genere : une fonction qui aurait lu
            # l'horloge en repli, quand l'horodatage manque, serait passee au
            # vert. Mesure le 22 aout 2026 en remettant exactement ce
            # defaut-la. Le titre promettait ce que l'appel empechait de
            # verifier -- consigne ici plutot que corrige en silence.
            $faits = [pscustomobject]@{ Dossier = 'D' }
            $a = InModuleScope DevContext -Parameters @{ f = $faits } {
                param($f) Format-CtxDashboardHtml -Faits $f
            }
            $b = InModuleScope DevContext -Parameters @{ f = $faits } {
                param($f) Format-CtxDashboardHtml -Faits $f
            }
            $a | Should -BeExactly $b -Because 'une fonction pure ne connait pas l heure'
        }

        It 'accepte des faits nuls sans lever, et rend quand meme une page' {
            $html = Get-Html $null
            $html | Should -BeLike '*<!DOCTYPE html>*'
            $html | Should -BeLike '*ctx init*'
        }

        It 'colore le verdict d apres sa valeur brute, jamais d apres un libelle' {
            # Le libelle est traduit ; la valeur appartient a un ValidateSet
            # ferme. Une classe CSS derivee du libelle changerait de nom entre
            # les deux langues, et la mise en forme disparaitrait dans l une.
            $faits = [pscustomobject]@{
                Dossier = 'D'
                Checks  = @([pscustomobject]@{ Domaine = 'gh'; Sujet = 'global'; Verdict = 'PROBLEME'; Detail = ''; Correctif = '' })
            }
            (Get-Html $faits) | Should -BeLike '*v-PROBLEME*'
        }
    }
}
