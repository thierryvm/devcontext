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

function Get-CtxDashboardSections {
    <#
      PURE. La table des sections : leur ordre, leurs textes, et QUEL CHAMP
      chaque colonne lit.

      UNE SEULE SOURCE, et c'est tout l'objet de cette fonction. Le rendu la
      parcourt ; le test qui confronte ces champs aux objets REELLEMENT rendus
      par le module la parcourt aussi. Une liste recopiee se perime a la
      premiere renommee -- et elle se perime en SILENCE : une colonne qui lit un
      champ disparu s'affiche vide, ce qui ressemble a une donnee absente.

      Mesure du 22 aout 2026, et c'est pourquoi cette table existe : la
      premiere version du rendu lisait 'Nom', 'Compte', 'Cle' et 'Libelle', des
      noms qui n'existaient sur aucun des objets. Les tests passaient parce
      qu'ils injectaient les memes noms inventes : ils validaient le rendu
      contre sa propre hypothese.

      Verdict = l'indice de la colonne qui porte un verdict, ou -1. Booleen
      marque une colonne qui porte un booleen a traduire en oui/non -- jamais un
      libelle deja traduit, dont la comparaison est le piege du 15 aout 2026.
    #>
    [CmdletBinding()]
    param()
    [ordered]@{
        Checks     = @{
            Titre = 'dash.diag.titre'; Vide = 'dash.diag.vide'; Verdict = 2
            Colonnes = @(
                @{ Cle = 'dash.col.domaine'; Champ = 'Domaine' }
                @{ Cle = 'dash.col.sujet'; Champ = 'Sujet' }
                @{ Cle = 'dash.col.verdict'; Champ = 'Verdict' }
                @{ Cle = 'dash.col.detail'; Champ = 'Detail' }
                @{ Cle = 'dash.col.correctif'; Champ = 'Correctif' }
            )
        }
        Contextes  = @{
            Titre = 'dash.ctx.titre'; Vide = 'dash.ctx.vide'; Verdict = -1
            Colonnes = @(
                @{ Cle = 'dash.col.contexte'; Champ = 'Contexte' }
                @{ Cle = 'dash.col.racine'; Champ = 'Racine' }
                @{ Cle = 'dash.col.compte'; Champ = 'Email' }
            )
        }
        Editeurs   = @{
            Titre = 'dash.editeur.titre'; Vide = 'dash.editeur.vide'; Verdict = -1
            Colonnes = @(
                @{ Cle = 'dash.col.editeur'; Champ = 'Editeur' }
                @{ Cle = 'dash.col.isolable'; Champ = 'Isole'; Booleen = $true }
                @{ Cle = 'dash.col.chemin'; Champ = 'Chemin' }
            )
        }
        Raccourcis = @{
            Titre = 'dash.raccourci.titre'; Vide = 'dash.raccourci.vide'; Verdict = 1
            Colonnes = @(
                @{ Cle = 'dash.col.raccourci'; Champ = 'Sujet' }
                @{ Cle = 'dash.col.verdict'; Champ = 'Verdict' }
                @{ Cle = 'dash.col.detail'; Champ = 'Detail' }
            )
        }
        Supabase   = @{
            Titre = 'dash.supabase.titre'; Vide = 'dash.supabase.vide'; Verdict = -1
            Colonnes = @(
                @{ Cle = 'dash.col.projet'; Champ = 'Projet' }
                @{ Cle = 'dash.col.compte'; Champ = 'Compte' }
                @{ Cle = 'dash.col.ref'; Champ = 'Ref' }
                @{ Cle = 'dash.col.env'; Champ = 'Env' }
            )
        }
        Mcp        = @{
            Titre = 'dash.mcp.titre'; Vide = 'dash.mcp.vide'; Verdict = -1
            Colonnes = @(
                @{ Cle = 'dash.col.serveur'; Champ = 'Nom' }
                @{ Cle = 'dash.col.portee'; Champ = 'Portee' }
            )
        }
    }
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

    # Une boucle sur la table, et non six blocs jumeaux. L'ordre des sections
    # est celui de la table ; l'ordre des constats DANS le diagnostic est celui
    # que `ctx doctor` a produit -- le retrier serait une decision, donc une
    # seconde implementation.
    foreach ($nom in (Get-CtxDashboardSections).Keys) {
        $def = (Get-CtxDashboardSections)[$nom]
        $elements = @(Get-CtxProp $Faits $nom @() | Where-Object { $null -ne $_ })
        $section = @{
            Titre          = T $def.Titre
            Vide           = T $def.Vide
            ColonneVerdict = $def.Verdict
            Entetes        = @($def.Colonnes | ForEach-Object { T $_.Cle })
            Lignes         = @($elements | ForEach-Object {
                    $element = $_
                    , @($def.Colonnes | ForEach-Object {
                            $valeur = Get-CtxProp $element $_.Champ ''
                            if ($_.ContainsKey('Booleen')) {
                                # Le BOOLEEN, jamais le libelle deja traduit :
                                # comparer un libelle affiche rendait chaque
                                # editeur non isole en anglais, le 15 aout 2026.
                                if ($valeur) { T 'dash.oui' } else { T 'dash.non' }
                            }
                            else { $valeur }
                        })
                })
        }
        [void]$sb.Append((Format-CtxDashboardSection @section))
    }

    [void]$sb.AppendLine('<footer>' + (ConvertTo-CtxHtmlTexte (T 'dash.pied' $Genere)) + '</footer>')
    [void]$sb.AppendLine('</main></body></html>')
    $sb.ToString()
}


# ---------------------------------------------------------------------------
# Rassemblement -- au-dela de cette ligne, on lit la machine
# ---------------------------------------------------------------------------

function Get-CtxDashboardFacts {
    <#
      RASSEMBLEMENT. Les faits du tableau de bord, pour un dossier.

      Cette fonction NE DECIDE RIEN. Elle appelle les fonctions qui decident
      deja, et se contente de les mettre cote a cote. C'est la contrainte
      centrale du 2.0 : deux implementations divergent, et celle qu'on croit est
      celle qu'on a ouverte.

      Un seul appel au diagnostic, partitionne ensuite. Les constats des
      raccourcis ont leur propre section a l'ecran, mais ils viennent de la MEME
      source que le reste -- pas d'un second balayage qui pourrait, un jour,
      repondre autre chose que celui affiche juste au-dessus.

      Reseau : aucun. `Get-DevContextDoctor` n'est pas appele avec -Live, donc
      ce rapport reste produisible hors ligne, dans un train, et dans un hook.
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)

    $dossier = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }

    $manifeste = Resolve-DevContextForPath -Path $dossier
    $proprio = if ($manifeste) { [string](Get-CtxProp $manifeste 'name' '') } else { '' }

    # Le @() au SITE D'APPEL, jamais dans la fonction appelee : PowerShell
    # deplie un tableau en traversant le flux de sortie, donc zero element
    # arrive en $null et un seul element arrive en scalaire -- silencieusement.
    $checks = @(Get-DevContextDoctor -Path $dossier)

    # LE DOSSIER DECIDE, PAS LA SESSION -- et ici ce n'est pas une formule.
    # Get-DevSupabaseMap retombe par defaut sur $env:DEVCTX et LEVE quand il est
    # vide. Un rapport produit depuis un dossier qu'aucun contexte ne gouverne
    # mourait donc sur cette ligne : precisement le rapport qu'on ouvre pour
    # comprendre POURQUOI on est hors contexte. Mesure le 22 aout 2026 -- la
    # suite passait sur cette machine et aurait rougi en CI, qui n'a jamais de
    # contexte actif.
    #
    # Le contexte PROPRIETAIRE du dossier est donc passe explicitement. Aucun
    # repli sur la session : si aucun contexte ne gouverne ce dossier, il n'y a
    # pas de parc Supabase a montrer pour lui, et la section le dit.
    $supabase = @()
    if ($proprio) { $supabase = @(Get-DevSupabaseMap -Name $proprio) }

    [pscustomobject]@{
        Dossier      = $dossier
        Proprietaire = $proprio
        Actif        = [string]$env:DEVCTX
        Checks       = @($checks | Where-Object { $_.Domaine -ne $script:CtxDomaineRaccourci })
        Raccourcis   = @($checks | Where-Object { $_.Domaine -eq $script:CtxDomaineRaccourci })
        Contextes    = @(Get-DevContextList)
        Editeurs     = @(Get-DevEditorList)
        Supabase     = $supabase
        Mcp          = @(Get-CtxMcpFacts -Dossier $dossier)
    }
}
