#Requires -Version 7
<#
.SYNOPSIS
    Assembles the exact folder that gets published to PowerShell Gallery.

.DESCRIPTION
    Publish-PSResource packs EVERYTHING in the folder it is given, with no
    exclusion of its own. Pointed at a working repository it therefore ships
    .git -- measured on 15 Aug 2026 for this module: 825 KB out of 1060, 78% of
    the package, carrying .git/config (the author's push URL and SSH host alias)
    and .git/filter-repo/commit-map (the old-to-new commit table of a history
    rewrite).

    A published version cannot be deleted. It can only be UNLISTED, and an
    unlisted version stays downloadable by exact version number, forever. There
    is no "we will fix it in the next release": what ships once has shipped.

    So the package is assembled here instead, from `git ls-files`. The source is
    what git TRACKS, not what the folder CONTAINS -- which is the whole point:
    .git, build artifacts and every ignored file are excluded by construction,
    not by a list somebody has to remember to maintain.

    What remains to decide is the development-versus-user split, and that IS a
    list, because no mechanism can infer it. It sits in $script:ExclusPaquet,
    each entry with its reason.

.PARAMETER Destination
    Where to assemble. Defaults to a temporary folder. The module folder is
    created INSIDE it and is named DevContext -- PSResourceGet resolves the
    manifest by folder name, and a mismatched name fails at publish time with an
    error about a missing manifest.

.PARAMETER AsLibrary
    Loads the functions without assembling anything, so tests can exercise the
    pure selection logic without touching the filesystem.

.EXAMPLE
    pwsh -NoProfile -File .\tools\Build-Package.ps1

.EXAMPLE
    # Inspect before publishing anything -- this is the step that pays for
    # itself, because the mistake it catches is not correctable afterwards.
    $d = pwsh -NoProfile -File .\tools\Build-Package.ps1
    Get-ChildItem $d -Recurse -File
#>
[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$AsLibrary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Le nom du dossier n'est pas cosmetique : Publish-PSResource cherche
# <dossier>/<nom-du-dossier>.psd1. Un dossier "staging" echoue sur "manifeste
# introuvable", un message qui ne nomme pas la cause.
$script:NomModule = 'DevContext'

# CE QUI NE PART PAS, ET POURQUOI.
#
# Le critere n'est pas "utile / inutile" mais "sert a SE SERVIR du module /
# sert a le MODIFIER". Ce qui sert a le modifier vit sur GitHub, ou se trouvent
# aussi l'historique, les issues et la CI qui lui donnent son sens.
$script:ExclusPaquet = @(
    # --- Plomberie git ------------------------------------------------------
    #
    # Redondant avec `git ls-files`, qui ne peut pas rendre .git puisque .git
    # n'est pas suivi -- et garde deliberement. La protection structurelle
    # depend de la SOURCE de la liste ; celle-ci tient quelle que soit la
    # provenance, y compris le jour ou quelqu'un remplace la collecte par un
    # parcours de dossier en croyant simplifier.
    '^\.git($|/)'
    '(^|/)\.gitignore$'
    '^\.gitattributes$'

    # --- Outillage de developpement -----------------------------------------
    '^\.github/'                        # CI, gabarits d'issue, dependabot
    '^\.claude/'                        # definitions d'agents IA
    '^tools/'                           # ce script lui-meme
    '^\.editorconfig$'
    '^PSScriptAnalyzerSettings\.psd1$'
    '^AGENTS\.md$'                      # s'adresse aux agents qui MODIFIENT le module
    '^CONTRIBUTING\.md$'

    # --- Tests : deliberement absents, et ce n'est pas une economie de place.
    #
    # Deux d'entre eux derivent leur liste de fichiers de `git ls-files`. Sur une
    # copie installee sous Documents\PowerShell\Modules, hors de tout depot, ils
    # ne SAUTERAIENT pas : ils echoueraient. Un test faussement rouge apprend a
    # ignorer le rouge, et finit par couter un vrai -- c'est le defaut que
    # tests/README.md nomme explicitement.
    #
    # La suite tourne en CI dans les deux langues, et sur un clone pour qui veut
    # la relancer. README.md dit ou.
    '^tests/'

    # --- Documentation de conception ----------------------------------------
    # Le paquet garde ce qui aide a se servir de l'outil : GUIDE, INSTALLATION,
    # POURQUOI, SECURITY, ARCHITECTURE, CHANGELOG, ROADMAP. Ce qui raconte
    # comment une decision a ete prise un jour donne reste sur GitHub.
    '^docs/plans/'
    '^docs/specs/'
    '^docs/article/'
    '^docs/demo/'                       # illustrations du README, servies par GitHub
)

# ---------------------------------------------------------------------------
# Selection pure -- aucune entree/sortie, donc testable
# ---------------------------------------------------------------------------

function Select-CtxFichiersPublies {
    <#
      Prend la liste des fichiers SUIVIS et rend ceux qui partent dans le paquet.

      Separee de la collecte pour la meme raison que partout ailleurs dans ce
      module : la moitie interessante est la decision, et elle doit pouvoir se
      verifier sans depot git sous la main.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Fichiers,

        [string[]]$Exclus = $script:ExclusPaquet
    )

    $Fichiers |
        Where-Object { $_ } |
        ForEach-Object { $_ -replace '\\', '/' } |
        Where-Object {
            $chemin = $_
            -not ($Exclus | Where-Object { $chemin -match $_ })
        }
}

# ---------------------------------------------------------------------------
# Collecte et assemblage
# ---------------------------------------------------------------------------

function Get-CtxFichiersSuivis {
    <#
      `git ls-files` plutot que Get-ChildItem, et c'est LA decision de ce script.

      Un parcours du dossier voit .git, les artefacts de construction et tout ce
      que .gitignore ecarte ; il faudrait alors les exclure un par un, donc
      penser a chacun. La liste de git est deja la reponse a "qu'est-ce qui fait
      partie de ce projet".
    #>
    param([Parameter(Mandatory)][string]$Racine)

    $sortie = & git -C $Racine ls-files
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files a echoue dans '$Racine' -- ce script exige un depot git."
    }
    @($sortie)
}

function Assert-CtxArbrePropre {
    <#
      Un paquet doit correspondre a un commit. Assemble depuis un arbre modifie,
      il contient un etat qui n'existe nulle part ailleurs : ni sur GitHub, ni
      dans l'historique, ni chez personne. Le jour ou un utilisateur signale un
      comportement, la version publiee n'est plus reproductible.
    #>
    param([Parameter(Mandatory)][string]$Racine)

    $sale = @(& git -C $Racine status --porcelain)
    if ($sale) {
        $detail = $sale -join "`n"
        throw "L'arbre de travail n'est pas propre. Un paquet doit correspondre a un commit.`n$detail"
    }
}

function New-CtxDossierPaquet {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Racine,
        [Parameter(Mandatory)][string]$Destination
    )

    $module = Join-Path $Destination $script:NomModule

    if (Test-Path -LiteralPath $module) {
        if ($PSCmdlet.ShouldProcess($module, 'Supprimer le dossier de construction precedent')) {
            Remove-Item -LiteralPath $module -Recurse -Force
        }
    }
    if (-not $PSCmdlet.ShouldProcess($module, 'Assembler le paquet')) { return }

    New-Item -ItemType Directory -Path $module -Force | Out-Null

    $retenus = @(Select-CtxFichiersPublies -Fichiers (Get-CtxFichiersSuivis -Racine $Racine))
    foreach ($f in $retenus) {
        $source = Join-Path $Racine $f
        $cible  = Join-Path $module $f
        $parent = Split-Path $cible -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $cible -Force
    }

    $module
}

# ---------------------------------------------------------------------------

if ($AsLibrary) { return }

$racine = Split-Path $PSScriptRoot -Parent

Assert-CtxArbrePropre -Racine $racine

if (-not $Destination) {
    $Destination = Join-Path ([System.IO.Path]::GetTempPath()) "devcontext-paquet-$PID"
}

$dossier = New-CtxDossierPaquet -Racine $racine -Destination $Destination

$fichiers = @(Get-ChildItem -LiteralPath $dossier -Recurse -File)
$ko = [int](($fichiers | Measure-Object Length -Sum).Sum / 1kb)

Write-Host ''
Write-Host ("  Paquet assemble : {0}" -f $dossier)
Write-Host ("  {0} fichiers, {1} Ko" -f $fichiers.Count, $ko)
Write-Host ''
Write-Host '  A verifier avant publication :'
Write-Host ("    Get-ChildItem '{0}' -Recurse -File" -f $dossier)
Write-Host ''

# Rendu sur la sortie standard pour etre capturable ; les lignes ci-dessus
# passent par Write-Host justement pour ne pas polluer ce rendu.
$dossier
