# Ou vivent les shims, et pourquoi ce n'est plus le dossier du module.
#
# LE DEFAUT QUE CE FICHIER CORRIGE, RELEVE LE 15 AOUT 2026, LE JOUR DE LA
# PUBLICATION SUR POWERSHELL GALLERY.
#
# L'installateur posait dans PATH le dossier `shims` du module. Sur la machine de
# l'auteur, ou le module est un lien symbolique vers un depot, ce chemin ne bouge
# jamais. Installe depuis la Gallery, le module vit sous
#
#     ...\Documents\PowerShell\Modules\DevContext\1.3.0\
#
# et LE NUMERO DE VERSION EST DANS LE CHEMIN. A l'installation de la 1.4.0,
# PowerShell cree un dossier voisin ; PATH continue de designer 1.3.0. Le
# garde-fou tourne alors sur une logique perimee, puis disparait completement le
# jour ou l'ancienne version est desinstallee -- sans un message.
#
# C'est exactement la panne que cet outil existe pour empecher, et elle ne
# pouvait pas se voir avant la publication.
#
# CE QUE PATH RECOIT DESORMAIS
#
#     %LOCALAPPDATA%\DevContext\current\shims
#
# ou `current` est une JONCTION vers la racine du module installe. Le chemin ne
# porte aucun numero ; c'est la jonction qu'on repointe a chaque version.
#
# UNE JONCTION, ET NON UNE COPIE. Les shims resolvent le module par chemin
# relatif -- `Join-Path $PSScriptRoot '..' 'DevContext.psd1'` -- et ce chemin
# reste valide A TRAVERS une jonction. Copier les fichiers casserait cette
# resolution : `Import-Module` echouerait, le shim tomberait dans son `catch`, et
# il deleguerait au binaire reel. Silencieusement. Toujours. Un garde-fou qui ne
# garde plus rien tout en restant installe est pire que pas de garde-fou.
#
# Une jonction et non un lien symbolique : sous Windows, creer un lien
# symbolique demande soit des droits administrateur, soit le mode developpeur.
# Une jonction de dossier n'exige ni l'un ni l'autre. Un installateur qui reclame
# une elevation pour un outil "par utilisateur" ne s'installe pas.
#
# Fichier partage entre le module et installer-shims.ps1 : deux copies d'une meme
# regle de chemin, c'est le piege du 12 aout 2026 -- une correction appliquee a
# l'exemplaire qui n'etait pas execute, sans effet et sans erreur.

Set-StrictMode -Version Latest

$script:CtxShimLienNom = 'current'

function Get-CtxShimRacine {
    <#
      Sous LOCALAPPDATA : par utilisateur, sans droits administrateur, et hors de
      tout dossier que PowerShell renumerote a chaque version.
    #>
    param([string]$Base = $env:LOCALAPPDATA)

    if (-not $Base) { $Base = [Environment]::GetFolderPath('LocalApplicationData') }
    # [IO.Path]::Combine et non Join-Path : Join-Path est un applet de fournisseur
    # qui resout le lecteur, et rend une CHAINE VIDE sur un volume absent au lieu
    # de lever. Une chaine vide ici produirait une entree PATH vide -- le defaut
    # deja rencontre le 15 aout 2026 sur --user-data-dir.
    [System.IO.Path]::Combine($Base, 'DevContext')
}

function Get-CtxShimLien {
    # La jonction elle-meme : elle pointe sur la RACINE du module, pas sur shims.
    # C'est ce qui garde `..\DevContext.psd1` valide depuis l'interieur.
    param([string]$Racine = (Get-CtxShimRacine))
    [System.IO.Path]::Combine($Racine, $script:CtxShimLienNom)
}

function Get-CtxShimStable {
    # Ce que PATH recoit. Aucun numero de version, jamais.
    param([string]$Lien = (Get-CtxShimLien))
    [System.IO.Path]::Combine($Lien, 'shims')
}

function Test-CtxDossierEstShim {
    <#
      PURE. Ce dossier est-il l'un des notres ?

      Sans egard pour la casse ni pour un separateur final : Windows resout PATH
      sans tenir compte de l'un ni de l'autre, et une comparaison de chaines
      brutes rejetterait 'C:\...\Shims\' tout en acceptant 'C:\...\shims'.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Dossier,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Dossiers
    )
    if (-not $Dossier) { return $false }
    $cible = $Dossier.TrimEnd('\', '/').ToLowerInvariant()
    foreach ($d in $Dossiers) {
        if ($d -and $d.TrimEnd('\', '/').ToLowerInvariant() -eq $cible) { return $true }
    }
    $false
}

# ---------------------------------------------------------------------------
# La jonction : lecture, pose, retrait
# ---------------------------------------------------------------------------

function Get-CtxJonctionCible {
    <#
      Vers ou pointe la jonction, ou $null si elle n'existe pas.

      Rend aussi $null quand le chemin existe mais N'EST PAS un point d'analyse :
      un vrai dossier a cet emplacement n'est pas une jonction mal reglee, c'est
      quelque chose que nous n'avons pas pose -- et que nous n'avons donc pas le
      droit de supprimer.
    #>
    param([Parameter(Mandatory)][string]$Chemin)

    if (-not (Test-Path -LiteralPath $Chemin)) { return $null }
    $item = Get-Item -LiteralPath $Chemin -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    if ($item.LinkType -notin 'Junction', 'SymbolicLink') { return $null }
    @($item.Target)[0]
}

function Test-CtxJonctionSaine {
    <#
      PURE. La jonction designe-t-elle bien le module attendu ?

      Separee de la lecture disque pour que le doctor puisse la verifier sans
      dependre de l'etat de la machine qui execute les tests.
    #>
    param(
        [AllowEmptyString()][AllowNull()][string]$Cible,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ModuleAttendu
    )
    if (-not $Cible) { return $false }
    $Cible.TrimEnd('\', '/').ToLowerInvariant() -eq $ModuleAttendu.TrimEnd('\', '/').ToLowerInvariant()
}

function Set-CtxJonction {
    <#
      Pose ou repointe la jonction vers $Cible.

      REFUSE de toucher a un vrai dossier. Si quelque chose occupe l'emplacement
      sans etre une jonction, on leve plutot que de supprimer : nous ne l'avons
      pas pose, et un installateur qui efface ce qu'il n'a pas ecrit finit un
      jour par effacer autre chose. Meme regle que les points d'entree, reconnus
      a leur marque et jamais a leur nom.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Chemin,
        [Parameter(Mandatory)][string]$Cible
    )

    if (-not (Test-Path -LiteralPath $Cible)) {
        throw "La cible de la jonction n'existe pas : $Cible"
    }

    if (Test-Path -LiteralPath $Chemin) {
        $item = Get-Item -LiteralPath $Chemin -Force
        if ($item.LinkType -notin 'Junction', 'SymbolicLink') {
            $quoi = "Un dossier occupe deja '$Chemin' sans etre une jonction."
            $suite = "DevContext ne supprime pas ce qu'il n'a pas pose : deplacez-le ou supprimez-le vous-meme."
            throw "$quoi $suite"
        }
        if ((Get-CtxJonctionCible -Chemin $Chemin) -eq $Cible.TrimEnd('\', '/')) { return $Chemin }
        if (-not $PSCmdlet.ShouldProcess($Chemin, 'repointer la jonction')) { return }
        # Directory.Delete($p, $false) retire le point d'analyse SANS descendre
        # dedans. Un Remove-Item -Recurse sur une jonction a deja, dans
        # l'histoire de PowerShell, supprime le contenu de la CIBLE.
        [System.IO.Directory]::Delete($Chemin, $false)
    }
    elseif (-not $PSCmdlet.ShouldProcess($Chemin, 'poser la jonction')) { return }

    $parent = Split-Path $Chemin -Parent
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    New-Item -ItemType Junction -Path $Chemin -Target $Cible -ErrorAction Stop | Out-Null
    $Chemin
}

function Remove-CtxJonction {
    <#
      Retire la jonction, et seulement si c'en est une. Rend $true si quelque
      chose a ete retire.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Chemin)

    if (-not (Test-Path -LiteralPath $Chemin)) { return $false }
    $item = Get-Item -LiteralPath $Chemin -Force
    if ($item.LinkType -notin 'Junction', 'SymbolicLink') { return $false }
    if (-not $PSCmdlet.ShouldProcess($Chemin, 'retirer la jonction')) { return $false }
    [System.IO.Directory]::Delete($Chemin, $false)
    $true
}
