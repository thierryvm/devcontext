# Le tableau de bord : rendu.
#
# TOUT CE FICHIER EST PUR. Il ne lit rien, n'ecrit rien, ne resout aucun chemin
# et ne connait pas l'heure. Il prend des faits et rend une chaine.
#
# Ce n'est pas de l'elegance : c'est ce qui rend la moitie interessante
# testable sans machine configuree. La collecte et l'ecriture arrivent dans les
# tranches suivantes, dans leurs propres fonctions.
#
# Trois contraintes viennent du ROADMAP et de SECURITY.md, et elles ne se
# negocient pas :
#
#   AUCUNE REQUETE SORTANTE depuis la page. Pas de CDN, pas de police distante,
#   pas d'image externe. Une page qui appelle le reseau depuis un outil
#   d'identifiants annonce la topologie de son porteur a qui heberge la
#   ressource -- et le rapport se regarde precisement quand on doute de
#   quelque chose.
#
#   ECHAPPEMENT SYSTEMATIQUE. Un nom de dossier, de branche, de compte ou de
#   projet est une DONNEE. Ici l'echappement vit dans le rendu des cellules, de
#   sorte qu'un appelant ne PUISSE pas l'oublier : il ne fournit jamais de
#   balisage.
#
#   AUCUNE DECISION NOUVELLE. Le rapport ne juge rien. Il rend les verdicts que
#   `ctx doctor` a deja rendus. Deux implementations divergent, et celle qu'on
#   croit est celle qu'on a ouverte.

function ConvertTo-CtxHtmlTexte {
    <#
      PURE. Une valeur quelconque en texte HTML sur.

      L'esperluette PASSE EN PREMIER, sans quoi elle re-echapperait les entites
      produites par les substitutions suivantes et `<` deviendrait `&amp;lt;`.

      L'apostrophe et le guillemet sont echappes bien que ce rendu ne place
      aucune valeur dans un attribut : le jour ou quelqu'un en placera une, la
      fonction sera deja correcte. Une protection qui depend de l'endroit ou on
      l'appelle n'en est pas une.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$Valeur)

    if ($null -eq $Valeur) { return '' }
    $texte = [string]$Valeur
    $texte = $texte.Replace('&', '&amp;')
    $texte = $texte.Replace('<', '&lt;')
    $texte = $texte.Replace('>', '&gt;')
    $texte = $texte.Replace('"', '&quot;')
    $texte.Replace("'", '&#39;')
}

function Get-CtxDashboardStyle {
    <#
      PURE. La feuille de style, en ligne.

      En ligne et non dans un fichier a cote : le rapport doit rester lisible
      apres avoir ete deplace, joint a un message ou ouvert depuis une cle USB.
      Un rapport dont la mise en forme depend d'un voisin est un rapport qui
      s'abime en silence.

      Pile de polices systeme uniquement -- voir la contrainte du haut : une
      police distante est une requete sortante, donc une fuite de topologie.
    #>
    [CmdletBinding()]
    param()
    @'
:root {
  --fond: #fbfbfa; --encre: #1c1c1a; --doux: #6b6b66; --trait: #e2e2dd;
  --carte: #ffffff; --pb: #b3261e; --att: #9a6700; --ok: #1a7f37; --info: #4b5563;
}
@media (prefers-color-scheme: dark) {
  :root {
    --fond: #16161a; --encre: #ececeb; --doux: #9a9a95; --trait: #2c2c31;
    --carte: #1d1d22; --pb: #ff6b60; --att: #d9a441; --ok: #4ac26b; --info: #9ca3af;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1.25rem 4rem; background: var(--fond); color: var(--encre);
  font: 15px/1.55 ui-sans-serif, system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}
main { max-width: 62rem; margin: 0 auto; }
h1 { font-size: 1.45rem; margin: 0 0 .25rem; letter-spacing: -.01em; }
h2 { font-size: 1rem; margin: 2.5rem 0 .75rem; letter-spacing: .04em; text-transform: uppercase; color: var(--doux); }
.sous { color: var(--doux); margin: 0 0 2rem; font-size: .9rem; }
.carte { background: var(--carte); border: 1px solid var(--trait); border-radius: 10px; overflow: hidden; }
.defile { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: .9rem; }
th, td { text-align: left; padding: .55rem .85rem; border-bottom: 1px solid var(--trait); vertical-align: top; }
th { font-weight: 600; color: var(--doux); font-size: .78rem; text-transform: uppercase; letter-spacing: .04em; }
tr:last-child td { border-bottom: 0; }
td.enveloppe { white-space: normal; }
.vide { padding: 1rem .85rem; color: var(--doux); font-size: .9rem; }
.vide code, code { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: .86em;
  background: rgba(127,127,127,.13); padding: .1em .38em; border-radius: 4px; }
.v { font-weight: 600; font-size: .78rem; letter-spacing: .04em; white-space: nowrap; }
.v-PROBLEME { color: var(--pb); }
.v-ATTENTION { color: var(--att); }
.v-OK { color: var(--ok); }
.v-INFO, .v-ABSENT { color: var(--info); }
footer { margin-top: 3rem; color: var(--doux); font-size: .82rem; }
'@
}

function Format-CtxDashboardSection {
    <#
      PURE. Une section : un titre, puis un tableau ou une phrase.

      LES CELLULES SONT ECHAPPEES ICI, et nulle part ailleurs. L'appelant passe
      des valeurs brutes et n'a aucun moyen de fournir du balisage -- c'est
      volontaire. Un echappement que chaque appelant doit penser a faire est un
      echappement qu'un appelant oubliera.

      $Vide n'est pas decoratif. Une section sans contenu doit NOMMER LA
      COMMANDE SUIVANTE : sur une machine vierge, le 15 aout 2026, la CLI a
      enchaine cinq impasses qui disaient toutes "aucun" sans dire quoi faire.
      L'ecran vide est le plus important du produit.

      $Verdicts, quand il est fourni, donne l'indice de la colonne qui porte un
      verdict, pour la colorer. C'est un INDICE et non le texte : le libelle est
      traduit, et decider sur du texte affiche est le piege que ce depot a paye
      quatre fois.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Titre,
        [Parameter(Mandatory)][string]$Vide,
        [AllowNull()][string[]]$Entetes,
        [AllowNull()][object[]]$Lignes,
        [int]$ColonneVerdict = -1
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<h2>' + (ConvertTo-CtxHtmlTexte $Titre) + '</h2>')
    [void]$sb.AppendLine('<div class="carte">')

    $lignes = @($Lignes | Where-Object { $null -ne $_ })
    if ($lignes.Count -eq 0) {
        [void]$sb.AppendLine('<p class="vide">' + (ConvertTo-CtxHtmlTexte $Vide) + '</p>')
        [void]$sb.AppendLine('</div>')
        return $sb.ToString()
    }

    [void]$sb.AppendLine('<div class="defile"><table>')
    if ($Entetes) {
        [void]$sb.Append('<thead><tr>')
        foreach ($e in $Entetes) { [void]$sb.Append('<th>' + (ConvertTo-CtxHtmlTexte $e) + '</th>') }
        [void]$sb.AppendLine('</tr></thead>')
    }
    [void]$sb.AppendLine('<tbody>')
    foreach ($ligne in $lignes) {
        [void]$sb.Append('<tr>')
        $cellules = @($ligne)
        for ($i = 0; $i -lt $cellules.Count; $i++) {
            $texte = ConvertTo-CtxHtmlTexte $cellules[$i]
            if ($i -eq $ColonneVerdict) {
                # La classe vient de la VALEUR BRUTE, qui appartient a un
                # ValidateSet ferme -- jamais d'un libelle traduit.
                $classe = ConvertTo-CtxHtmlTexte ('v v-' + [string]$cellules[$i])
                [void]$sb.Append('<td class="' + $classe + '">' + $texte + '</td>')
            }
            else {
                [void]$sb.Append('<td class="enveloppe">' + $texte + '</td>')
            }
        }
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</tbody></table></div>')
    [void]$sb.AppendLine('</div>')
    $sb.ToString()
}

function Format-CtxDashboardHtml {
    <#
      PURE. Les faits en entree, une page HTML autonome en sortie.

      $Genere est PASSE et non lu : une fonction pure ne connait pas l'heure, et
      une sortie deterministe est ce qui rend le test possible. C'est aussi la
      contrainte que le moteur de workflow de ce depot applique a ses scripts,
      pour la meme raison.

      Chaque champ de $Faits est lu par Get-CtxProp : sous StrictMode, lire une
      propriete absente leve, et un appelant a le droit de ne fournir que ce
      qu'il a. Une section sans faits n'est pas une erreur, c'est un etat vide
      -- et il a sa phrase.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Faits,
        [string]$Genere = ''
    )

    $dossier = [string](Get-CtxProp $Faits 'Dossier' '')
    $proprio = [string](Get-CtxProp $Faits 'Proprietaire' '')
    $actif = [string](Get-CtxProp $Faits 'Actif' '')

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="fr"><head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    # Une page qui ne doit rien chercher dehors peut le DECLARER, et le
    # navigateur le fait respecter. C'est la meme doctrine que partout ici :
    # l'intention ne protege pas, la mesure protege.
    [void]$sb.AppendLine('<meta http-equiv="Content-Security-Policy" ' +
        'content="default-src ' + "'none'" + '; style-src ' + "'unsafe-inline'" + '; img-src data:;">')
    [void]$sb.AppendLine('<meta name="referrer" content="no-referrer">')
    [void]$sb.AppendLine('<title>' + (ConvertTo-CtxHtmlTexte (T 'dash.titre')) + '</title>')
    [void]$sb.AppendLine('<style>' + (Get-CtxDashboardStyle) + '</style>')
    [void]$sb.AppendLine('</head><body><main>')

    [void]$sb.AppendLine('<h1>' + (ConvertTo-CtxHtmlTexte (T 'dash.titre')) + '</h1>')

    $entete = if ($proprio) { T 'dash.entete.dossier' $dossier $proprio }
    else { T 'dash.entete.dossierSansProprietaire' $dossier }
    if ($actif) { $entete = $entete + ' ' + (T 'dash.entete.actif' $actif) }
    [void]$sb.AppendLine('<p class="sous">' + (ConvertTo-CtxHtmlTexte $entete) + '</p>')

    # Chaque section est decrite par une table, puis eclatee en parametres.
    # Pas de continuation de ligne : PSScriptAnalyzer refuse l'alignement qui
    # en decoule, et le depot a deja paye deux fois pour l'avoir ecrit ainsi.
    #
    # L'ordre des sections est celui du plan, et l'ordre des constats DANS le
    # diagnostic est celui que `ctx doctor` a produit. Le retrier serait une
    # decision -- donc une seconde implementation.
    $checks = @(Get-CtxProp $Faits 'Checks' @() | Where-Object { $null -ne $_ })
    $diagnostic = @{
        Titre          = T 'dash.diag.titre'
        Vide           = T 'dash.diag.vide'
        ColonneVerdict = 2
        Entetes        = @(
            (T 'dash.col.domaine'), (T 'dash.col.sujet'), (T 'dash.col.verdict')
            (T 'dash.col.detail'), (T 'dash.col.correctif')
        )
        Lignes         = @($checks | ForEach-Object {
                , @(
                    (Get-CtxProp $_ 'Domaine' ''), (Get-CtxProp $_ 'Sujet' ''), (Get-CtxProp $_ 'Verdict' '')
                    (Get-CtxProp $_ 'Detail' ''), (Get-CtxProp $_ 'Correctif' '')
                )
            })
    }
    [void]$sb.Append((Format-CtxDashboardSection @diagnostic))

    $contextes = @(Get-CtxProp $Faits 'Contextes' @() | Where-Object { $null -ne $_ })
    $sectionContextes = @{
        Titre   = T 'dash.ctx.titre'
        Vide    = T 'dash.ctx.vide'
        Entetes = @((T 'dash.col.contexte'), (T 'dash.col.racine'), (T 'dash.col.compte'))
        Lignes  = @($contextes | ForEach-Object {
                , @((Get-CtxProp $_ 'Nom' ''), (Get-CtxProp $_ 'Racine' ''), (Get-CtxProp $_ 'Compte' ''))
            })
    }
    [void]$sb.Append((Format-CtxDashboardSection @sectionContextes))

    $editeurs = @(Get-CtxProp $Faits 'Editeurs' @() | Where-Object { $null -ne $_ })
    $sectionEditeurs = @{
        Titre   = T 'dash.editeur.titre'
        Vide    = T 'dash.editeur.vide'
        Entetes = @((T 'dash.col.editeur'), (T 'dash.col.isolable'), (T 'dash.col.chemin'))
        Lignes  = @($editeurs | ForEach-Object {
                # Le BOOLEEN, jamais le libelle traduit : c'est le piege du
                # 15 aout 2026, ou une comparaison a un litteral francais
                # rendait chaque editeur non isole en anglais.
                $isolable = if (Get-CtxProp $_ 'Isolable' $false) { T 'dash.oui' } else { T 'dash.non' }
                , @((Get-CtxProp $_ 'Nom' ''), $isolable, (Get-CtxProp $_ 'Chemin' ''))
            })
    }
    [void]$sb.Append((Format-CtxDashboardSection @sectionEditeurs))

    $raccourcis = @(Get-CtxProp $Faits 'Raccourcis' @() | Where-Object { $null -ne $_ })
    $sectionRaccourcis = @{
        Titre          = T 'dash.raccourci.titre'
        Vide           = T 'dash.raccourci.vide'
        ColonneVerdict = 1
        Entetes        = @((T 'dash.col.raccourci'), (T 'dash.col.verdict'), (T 'dash.col.detail'))
        Lignes         = @($raccourcis | ForEach-Object {
                , @((Get-CtxProp $_ 'Sujet' ''), (Get-CtxProp $_ 'Verdict' ''), (Get-CtxProp $_ 'Detail' ''))
            })
    }
    [void]$sb.Append((Format-CtxDashboardSection @sectionRaccourcis))

    $supabase = @(Get-CtxProp $Faits 'Supabase' @() | Where-Object { $null -ne $_ })
    $sectionSupabase = @{
        Titre   = T 'dash.supabase.titre'
        Vide    = T 'dash.supabase.vide'
        Entetes = @(
            (T 'dash.col.projet'), (T 'dash.col.contexte'), (T 'dash.col.cle'), (T 'dash.col.env')
        )
        Lignes  = @($supabase | ForEach-Object {
                , @(
                    (Get-CtxProp $_ 'Projet' ''), (Get-CtxProp $_ 'Contexte' '')
                    (Get-CtxProp $_ 'Cle' ''), (Get-CtxProp $_ 'Env' '')
                )
            })
    }
    [void]$sb.Append((Format-CtxDashboardSection @sectionSupabase))

    $mcp = @(Get-CtxProp $Faits 'Mcp' @() | Where-Object { $null -ne $_ })
    $sectionMcp = @{
        Titre   = T 'dash.mcp.titre'
        Vide    = T 'dash.mcp.vide'
        Entetes = @((T 'dash.col.serveur'), (T 'dash.col.client'), (T 'dash.col.chemin'))
        Lignes  = @($mcp | ForEach-Object {
                , @((Get-CtxProp $_ 'Nom' ''), (Get-CtxProp $_ 'Libelle' ''), (Get-CtxProp $_ 'Chemin' ''))
            })
    }
    [void]$sb.Append((Format-CtxDashboardSection @sectionMcp))

    [void]$sb.AppendLine('<footer>' + (ConvertTo-CtxHtmlTexte (T 'dash.pied' $Genere)) + '</footer>')
    [void]$sb.AppendLine('</main></body></html>')
    $sb.ToString()
}
