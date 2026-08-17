#Requires -Version 7
<#
.SYNOPSIS
    Proves a release is publishable, BEFORE anyone is asked to approve it.

.DESCRIPTION
    A published version cannot be deleted. It can only be UNLISTED, and an
    unlisted version stays downloadable by exact version number, forever. So
    every mistake this script can catch is a mistake that has no correction.

    The checks live here rather than inside the workflow, and that is the whole
    point of the file. A rule written in YAML can only be tried by running the
    workflow -- which, for a publishing workflow, means trying it by publishing.
    Written here, the interesting half is a pure function the test suite
    exercises on cases that must never reach a real release.

    Three questions, in the order that matters:

      1. Does the tag match the manifest? The version is bumped BY HAND, in a
         dedicated commit. Tagging without bumping is the failure this doctrine
         exists to make visible, and it is silent otherwise: the workflow would
         happily republish the previous number, or fail on the Gallery with an
         error naming a conflict rather than the forgotten edit.

      2. Is that version already on the Gallery? Asked before publishing rather
         than discovered during it.

      3. Does the assembled package contain only what it should? Verified on the
         assembled folder, not on the repository -- what ships is what was
         assembled.

.PARAMETER Dossier
    The assembled package folder, as produced by tools/Build-Package.ps1.

.PARAMETER Tag
    The release tag, e.g. v1.9.0. Omit to skip the tag/manifest comparison --
    which is only legitimate for a dry run, and the caller must say so.

.PARAMETER AsLibrary
    Loads the functions without checking anything, so tests can exercise the
    pure decisions with no package and no network.

.EXAMPLE
    $d = pwsh -NoProfile -File .\tools\Build-Package.ps1
    pwsh -NoProfile -File .\tools\Assert-Release.ps1 -Dossier $d -Tag v1.9.0
#>
[CmdletBinding()]
param(
    [string]$Dossier,
    [string]$Tag,
    [switch]$AsLibrary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Motifs de secrets -- source unique
# ---------------------------------------------------------------------------

function Get-CtxMotifsSecrets {
    <#
      La CI balaie l'HISTORIQUE, ce script balaie le PAQUET : deux entrees
      differentes, deux listes d'exceptions differentes -- mais UNE seule liste
      de motifs. Deux copies divergeraient, et celle qui divergerait serait
      decouverte le jour ou elle laisse passer quelque chose.

      C'est nommement le piege "deriver une liste et recopier sa jumelle" que
      AGENTS.md enregistre deja pour les alias.
    #>
    @(
        'sbp_[A-Za-z0-9]{30,}'
        'sb_secret_[A-Za-z0-9]{30,}'
        'gh[pousr]_[A-Za-z0-9]{36,}'
        'github_pat_[A-Za-z0-9_]{40,}'
        'sk-[A-Za-z0-9]{40,}'
        'xox[baprs]-[A-Za-z0-9-]{30,}'
        '(AKIA|ASIA)[A-Z0-9]{16}'
        'BEGIN [A-Z ]*PRIVATE KEY'
    )
}

# ---------------------------------------------------------------------------
# Decisions pures -- aucune entree/sortie, donc testables
# ---------------------------------------------------------------------------

function Get-CtxVersionDepuisTag {
    <#
      Rend la version portee par un tag, ou $null si le tag n'a pas la forme
      attendue. Rendre $null plutot que lever : l'appelant sait, lui, si un tag
      absent est une faute ou un essai a blanc.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Tag)

    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }

    # Ancre aux deux bouts : "v1.9.0-rc1" n'est pas "v1.9.0", et un tag de
    # pre-publication qui passerait pour une version finale publierait une
    # version finale.
    $m = [regex]::Match($Tag.Trim(), '^v(\d+(?:\.\d+){1,3})$')
    if (-not $m.Success) { return $null }
    $m.Groups[1].Value
}

function Test-CtxTagCorrespondManifeste {
    <#
      Rend la faute a signaler, ou $null quand tout concorde.

      Le cas qui compte n'est pas le tag mal ecrit -- il se voit -- mais le tag
      BIEN ecrit sur un manifeste qu'on a oublie de faire monter : v1.9.0 sur un
      manifeste encore a 1.8.0. Sans cette comparaison, la Gallery repond "cette
      version existe deja", un message qui nomme le symptome et pas la cause.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Tag,
        [AllowNull()][AllowEmptyString()][string]$VersionManifeste
    )

    if ([string]::IsNullOrWhiteSpace($VersionManifeste)) {
        return 'Le manifeste ne porte aucune version.'
    }

    $duTag = Get-CtxVersionDepuisTag -Tag $Tag
    if (-not $duTag) {
        return "Tag '$Tag' : forme attendue vX.Y.Z (sans suffixe)."
    }

    # [version] sert a VALIDER la forme, pas a comparer. La comparaison est faite
    # sur les chaines, a l'identique, et cette severite est voulue : 1.9.0 et
    # 1.9.0.0 sont deux numeros DIFFERENTS sur la Gallery, et un numero publie ne
    # se reprend jamais. Sur une action irreversible, l'egalite approchee n'a
    # aucun benefice a offrir contre ce risque-la.
    #
    # (Ecrit d'abord en comparant des [version], sur la croyance que .NET les
    # tenait pour egales. Il ne le fait pas -- Revision vaut -1 contre 0 -- et
    # l'intention affichee contredisait donc le code. Rendue explicite.)
    $man = $VersionManifeste.Trim()
    $vRien = $null
    if (-not [version]::TryParse($duTag, [ref]$vRien) -or
        -not [version]::TryParse($man, [ref]$vRien)) {
        return "Version illisible -- tag '$duTag', manifeste '$man'."
    }
    if ($duTag -ne $man) {
        return "Le tag annonce $duTag, le manifeste porte $man. Le manifeste se met a jour A LA MAIN, dans un commit chore(release) dedie."
    }
    $null
}

function Find-CtxFautesPaquet {
    <#
      Rend la liste des fautes trouvees dans un paquet assemble. Liste vide =
      publiable.

      Le contenu est LU PAR L'APPELANT, via -LireContenu. Injection complete et
      non a moitie : une fonction qui recevrait la liste des fichiers mais irait
      quand meme interroger le disque laisserait un test decrire un paquet que la
      fonction n'examinerait pas. Ce piege est deja enregistre dans AGENTS.md.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Fichiers,

        [Parameter(Mandatory)]
        [scriptblock]$LireContenu
    )

    $fautes = [System.Collections.Generic.List[string]]::new()
    $chemins = @($Fichiers | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' })

    if ($chemins.Count -eq 0) {
        $fautes.Add('Le paquet est vide.')
        return $fautes.ToArray()
    }

    # --- Ce qui ne doit pas s'y trouver ------------------------------------
    #
    # Mesure du 15 aout 2026 : pointe sur un depot de travail, Publish-PSResource
    # emportait .git en entier -- 78 % du paquet, dont l'URL de push de l'auteur
    # et la table de correspondance d'une reecriture d'historique.
    $interdits = @{
        '(^|/)\.git($|/)'              = 'plomberie git'
        '^tests/'                      = 'suite de tests (deux tests derivent leur liste de git ls-files et ECHOUERAIENT hors depot)'
        '^\.github/'                   = 'outillage de CI'
        '^\.claude/'                   = 'definitions d agents'
        '^tools/'                      = 'outillage de construction'
        '(^|/)AGENTS\.md$'             = 's adresse a qui MODIFIE le module'
        '(^|/)CONTRIBUTING\.md$'       = 'outillage de contribution'
    }
    foreach ($c in $chemins) {
        foreach ($motif in $interdits.Keys | Sort-Object) {
            if ($c -match $motif) {
                $fautes.Add("Fichier a ne pas publier : $c ($($interdits[$motif]))")
            }
        }
    }

    # --- Ce qui doit s'y trouver -------------------------------------------
    foreach ($requis in @('DevContext.psd1', 'DevContext.psm1', 'LICENSE', 'README.md')) {
        if ($chemins -notcontains $requis) {
            $fautes.Add("Fichier manquant dans le paquet : $requis")
        }
    }

    # --- Contenu ------------------------------------------------------------
    $motifsSecrets = Get-CtxMotifsSecrets
    foreach ($c in $chemins) {
        $texte = & $LireContenu $c
        if ([string]::IsNullOrEmpty($texte)) { continue }

        foreach ($m in $motifsSecrets) {
            if ($texte -match $m) {
                # On nomme le FICHIER et le MOTIF, jamais la valeur trouvee : un
                # rapport de CI est public, et publier le secret pour annoncer
                # qu'on en a trouve un serait la faute qu'on cherchait a eviter.
                $fautes.Add("Chaine ressemblant a un secret dans $c (motif : $m)")
            }
        }

        # Un chemin de profil ne marche que chez son proprietaire, et publie son
        # nom d'utilisateur Windows au passage.
        #
        # La liste d'exemptions est celle de tests/Documentation.Tests.ps1, au
        # nom pres : moi, vous, <...>, %VAR% et $VAR sont de la documentation.
        # Elle omettait "vous" a l'ecriture, ce qui faisait de ce scanner-ci le
        # plus severe des deux -- deux regles pour une meme question, donc une
        # qui finit par surprendre.
        if ($texte -match '(?i)[A-Za-z]:\\Users\\(?!moi\b|vous\b|<|%|\$)[A-Za-z0-9._-]+\\') {
            $fautes.Add("Chemin de profil utilisateur dans $c")
        }
    }

    $fautes.ToArray()
}

# ---------------------------------------------------------------------------
# Collecte et verdict
# ---------------------------------------------------------------------------

if ($AsLibrary) { return }

if (-not $Dossier) { throw 'Assert-Release.ps1 : -Dossier est requis (ou -AsLibrary).' }
if (-not (Test-Path -LiteralPath $Dossier)) { throw "Dossier introuvable : $Dossier" }

$racinePaquet = (Resolve-Path -LiteralPath $Dossier).Path
$manifeste = Join-Path $racinePaquet 'DevContext.psd1'
if (-not (Test-Path -LiteralPath $manifeste)) {
    throw "Aucun DevContext.psd1 dans '$racinePaquet' -- ce n'est pas un paquet assemble."
}

# Import-PowerShellDataFile et non Test-ModuleManifest : celui-ci resout
# RequiredModules et echouerait la ou les dependances ne sont pas installees,
# sur une question qui n'a rien a voir avec la version.
$version = (Import-PowerShellDataFile -LiteralPath $manifeste).ModuleVersion

$fichiers = @(
    Get-ChildItem -LiteralPath $racinePaquet -Recurse -File |
        ForEach-Object { $_.FullName.Substring($racinePaquet.Length).TrimStart('\', '/') }
)

$lire = {
    param($relatif)
    $p = Join-Path $racinePaquet $relatif
    # Les binaires eventuels ne sont pas du texte ; -Raw sur un binaire rend une
    # chaine inexploitable plutot qu'une erreur, ce qui convient : aucun motif
    # ne matchera, et l'absence de faute est le bon verdict pour un binaire.
    Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
}

$fautes = @()
if ($Tag) {
    $ecart = Test-CtxTagCorrespondManifeste -Tag $Tag -VersionManifeste $version
    if ($ecart) { $fautes += $ecart }
}
$fautes += @(Find-CtxFautesPaquet -Fichiers $fichiers -LireContenu $lire)

# Tout le compte rendu part sur stderr, pour la raison mesuree le 17 aout 2026
# et expliquee dans Build-Package.ps1 : a travers `pwsh -File`, ce qui passe par
# Write-Host arrive sur la sortie standard du parent et pollue ce qu'on voulait
# capturer. Ici cela compte doublement -- la valeur rendue est une VERSION, et
# une version contaminee par des lignes de progression est ce qu'on irait ensuite
# publier.
function Write-CtxProgres {
    param([AllowEmptyString()][string]$Ligne)
    [Console]::Error.WriteLine($Ligne)
}

Write-CtxProgres ''
Write-CtxProgres "  Paquet   : $racinePaquet"
Write-CtxProgres "  Version  : $version"
Write-CtxProgres ("  Tag      : {0}" -f $(if ($Tag) { $Tag } else { '(aucun -- essai a blanc)' }))
Write-CtxProgres "  Fichiers : $($fichiers.Count)"
Write-CtxProgres ''

if ($fautes.Count -gt 0) {
    foreach ($f in $fautes) { Write-CtxProgres "  REFUS : $f" }
    Write-CtxProgres ''
    throw "$($fautes.Count) probleme(s) -- rien n'est publie."
}

Write-CtxProgres '  Publiable.'
Write-CtxProgres ''

# Seul rendu sur la sortie standard : la version, capturable telle quelle.
$version
