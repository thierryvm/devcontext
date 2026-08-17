# La surface de confiance des agents IA.
#
# CE QUE CE FICHIER REGARDE, ET POURQUOI IL EXISTE
#
# Le reste du module cloisonne QUI ON EST : identite git, jetons, sessions.
# Il ne dit rien de OU CA ECRIT. Un agent lance dans un dossier client a les
# memes droits d'ecriture sur le disque que n'importe quel processus.
#
# Les agents ont pourtant deja une frontiere : le dossier de travail, elargi
# par une liste de dossiers approuves. Le probleme n'est donc pas l'absence de
# mecanisme -- c'est que cette liste s'ecrit en PORTEE UTILISATEUR, une
# approbation ponctuelle a la fois, et que personne ne la relit jamais.
#
# Mesure du 17 aout 2026 sur la machine de l'auteur : 14 dossiers approuves en
# portee utilisateur, dont la racine du contexte perso, le Bureau, un coffre de
# notes, et un dossier de session cree pour un besoin d'un jour. Tous actifs
# dans CHAQUE session, y compris dans un dossier client.
#
# C'est exactement la faute que ce module existe pour attraper -- le dossier
# decide, jamais la session -- sauf qu'ici les decisions d'une session sont
# devenues un etat global permanent.
#
# CE QUE CE FICHIER NE FAIT PAS
#
# Il n'impose rien. Une regle de permission est RESPECTEE par l'agent, pas
# IMPOSEE par le noyau ; un vrai confinement d'ecriture demanderait un pilote
# de filtre ou un conteneur, une autre classe de logiciel. C'est un garde-fou,
# pas une prison, au meme titre que le shim de PATH que SECURITY.md decrit
# comme contournable par un chemin absolu.
#
# Contre la maladresse -- le cas reel, et de tres loin le plus frequent -- il
# suffit. Contre un adversaire, non, et ce n'est pas dit a demi-mot.

# Les fichiers de reglages, du plus general au plus specifique. La portee est
# ce qui compte pour le verdict : approuve en portee UTILISATEUR, un dossier
# vaut pour tous les projets, y compris ceux d'un autre client.
$script:CtxAgentFichiers = @(
    @{ Portee = 'utilisateur'; Relatif = $false; Chemin = '.claude/settings.json' }
    @{ Portee = 'utilisateur'; Relatif = $false; Chemin = '.claude/settings.local.json' }
    @{ Portee = 'projet'; Relatif = $true; Chemin = '.claude/settings.json' }
    @{ Portee = 'projet'; Relatif = $true; Chemin = '.claude/settings.local.json' }
)

function Get-CtxAgentSettingsChemins {
    <#
      Ou vivent les reglages, pour ce dossier-ci. Collecte : touche au disque
      uniquement pour resoudre un chemin, jamais pour decider.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Dossier)

    # CLAUDE_CONFIG_DIR deplace le dossier utilisateur. L'ignorer ferait lire un
    # fichier qui n'est pas celui qui s'applique, et rendre un verdict rassurant
    # sur une liste que personne n'utilise.
    $base = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { $HOME }

    $chemins = @()
    foreach ($f in $script:CtxAgentFichiers) {
        $racine = if ($f.Relatif) { $Dossier } else { $base }
        if (-not $racine) { continue }
        # [System.IO.Path]::Combine et non Join-Path : celui-ci est un cmdlet de
        # PROVIDER, il resout le lecteur et rend une chaine VIDE quand il echoue
        # sans -ErrorAction Stop. Le piege est enregistre dans AGENTS.md.
        $relatif = $f.Chemin -replace '/', [System.IO.Path]::DirectorySeparatorChar
        # CLAUDE_CONFIG_DIR pointe deja sur le dossier de configuration : le
        # segment .claude ne s'y ajoute pas une seconde fois.
        if (-not $f.Relatif -and $env:CLAUDE_CONFIG_DIR) {
            $relatif = Split-Path $relatif -Leaf
        }
        $chemins += [pscustomobject]@{
            Portee  = $f.Portee
            Chemin  = [System.IO.Path]::Combine($racine, $relatif)
        }
    }
    @($chemins)
}

function Get-CtxAgentConfianceFacts {
    <#
      COLLECTE. Rend un fait par dossier approuve : sa portee, le fichier qui
      l'accorde, et le contexte qui le possede -- resolu par
      Resolve-DevContextForPath, la fonction qui arme deja `ctx`.

      La reutiliser n'est pas une economie de lignes : c'est elle qui porte le
      piege de prefixe (Apps ne doit pas matcher Apps-Autre), deja paye trois
      fois dans ce depot. Une quatrieme comparaison de chemins ecrite a la main
      serait une quatrieme occasion de le repayer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Dossier)

    $faits = @()
    foreach ($src in (Get-CtxAgentSettingsChemins -Dossier $Dossier)) {
        if (-not (Test-Path -LiteralPath $src.Chemin)) { continue }

        $data = $null
        try {
            $brut = Get-Content -LiteralPath $src.Chemin -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($brut)) { continue }
            $data = $brut | ConvertFrom-Json -ErrorAction Stop
        }
        catch { continue }   # illisible : se taire plutot qu'accuser a tort

        # ConvertFrom-Json rend un PSObject : Get-CtxProp est la bonne lecture.
        # Sous StrictMode, lire une propriete absente LEVE.
        $perm = Get-CtxProp $data 'permissions'
        if (-not $perm) { continue }
        $dossiers = @(Get-CtxProp $perm 'additionalDirectories')

        foreach ($d in $dossiers) {
            if ([string]::IsNullOrWhiteSpace($d)) { continue }
            $manifeste = Resolve-DevContextForPath -Path $d
            $faits += [pscustomobject]@{
                Portee       = $src.Portee
                Fichier      = $src.Chemin
                Dossier      = $d
                Proprietaire = if ($manifeste) { Get-CtxProp $manifeste 'name' } else { $null }
            }
        }
    }
    @($faits)
}

function Test-CtxDoctorAgentConfiance {
    <#
      PURE. Un dossier approuve appartient-il a un AUTRE contexte ?

      Meme famille de constat que Test-CtxDoctorProfilComptes, et meme verdict :
      PROBLEME, pas ATTENTION. Un dossier client ouvert dans une session qui
      peut ecrire dans l'arborescence d'un autre client n'est pas un desordre,
      c'est une question de confidentialite.

      Rien du tout quand tout est propre : un rapport qui felicite a chaque
      ligne finit lu en diagonale.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Faits = @(),
        [AllowNull()][AllowEmptyString()][string]$Contexte
    )

    $checks = @()
    if ($Faits.Count -eq 0) { return @($checks) }

    # --- dossiers appartenant a un autre contexte ---------------------------
    #
    # Sans contexte courant, "etranger" ne veut rien dire : il n'y a rien a
    # traverser. On se tait plutot que d'inventer une reference.
    if ($Contexte) {
        $etrangers = @($Faits | Where-Object {
                $_.Proprietaire -and $_.Proprietaire -ne $Contexte
            })

        # Groupe par contexte proprietaire, pour que le constat nomme QUI est
        # atteint plutot que d'aligner des chemins.
        $parContexte = @{}
        foreach ($f in $etrangers) {
            if (-not $parContexte.ContainsKey($f.Proprietaire)) {
                $parContexte[$f.Proprietaire] = @()
            }
            $parContexte[$f.Proprietaire] += $f
        }

        # Sort-Object : les cles d'une table de hachage n'ont pas d'ordre
        # garanti, et une sortie dont l'ordre varie rend deux executions
        # incomparables. Le piege est deja enregistre dans AGENTS.md.
        foreach ($autre in ($parContexte.Keys | Sort-Object)) {
            $liste = (@($parContexte[$autre] | ForEach-Object { $_.Dossier }) |
                    Sort-Object -Unique) -join ', '
            $portees = (@($parContexte[$autre] | ForEach-Object { $_.Portee }) |
                    Sort-Object -Unique) -join ', '
            $checks += New-CtxCheck -Domaine 'agent' -Sujet "confiance/$autre" -Verdict 'PROBLEME' `
                -Detail (T 'doc.agent.confianceEtrangere' $Contexte $autre $liste $portees) `
                -Correctif (T 'doc.agent.confianceEtrangereFix')
        }
    }

    # --- dossiers hors de tout contexte, accordes pour TOUS les projets ------
    $orphelins = @($Faits | Where-Object {
            -not $_.Proprietaire -and $_.Portee -eq 'utilisateur'
        })
    if ($orphelins.Count -gt 0) {
        $liste = (@($orphelins | ForEach-Object { $_.Dossier }) | Sort-Object -Unique) -join ', '
        $checks += New-CtxCheck -Domaine 'agent' -Sujet 'confiance/globale' -Verdict 'ATTENTION' `
            -Detail (T 'doc.agent.confianceHorsContexte' $orphelins.Count $liste) `
            -Correctif (T 'doc.agent.confianceHorsContexteFix')
    }

    @($checks)
}
