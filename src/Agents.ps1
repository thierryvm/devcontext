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

function Resolve-CtxGuardPlan {
    <#
      PURE. Ce qu'il faudrait changer a la liste des dossiers approuves.

      POURQUOI CE N'EST PAS UNE LISTE D'INTERDITS

      La conception d'origine ecrivait des regles `deny` visant les racines des
      autres contextes. Verification faite avant d'ecrire la moindre ligne : sous
      Windows, ces regles NE MATCHENT PAS. L'outil d'ecriture rend le chemin
      absolu avant le controle, et un chemin Windows absolu ne correspond a
      aucune forme de motif documentee -- anthropics/claude-code#67849, #34741,
      #22907, et #36884 pour l'extension VS Code.

      Un fichier de regles inertes est pire que pas de fichier : il a l'apparence
      d'une protection. C'est le meme defaut que ce depot nomme deja pour un
      drapeau silencieusement ignore -- "une isolation qu'on n'a pas".

      Le mecanisme qui FONCTIONNE est le positif : la frontiere du dossier de
      travail, elargie par additionalDirectories. On ne pose donc rien ; on
      retire ce qui n'a rien a faire en portee utilisateur.

      LA REGLE

      La portee utilisateur ne doit porter AUCUN dossier appartenant a un
      contexte. Un tel dossier vaut alors pour toutes les sessions, y compris
      celles d'un autre client -- c'est la definition meme de la fuite. Il se
      declare dans le projet qui en a besoin.

      Ce qui n'appartient a aucun contexte n'est pas tranche ici : c'est un
      arbitrage, pas une regle. On le liste pour qu'il soit relu.
    #>
    [CmdletBinding()]
    param([object[]]$Faits = @())

    $utilisateur = @($Faits | Where-Object { $_.Portee -eq 'utilisateur' })

    $aRetirer = @($utilisateur | Where-Object { $_.Proprietaire })
    $aRelire = @($utilisateur | Where-Object { -not $_.Proprietaire })

    [pscustomobject]@{
        ARetirer = @($aRetirer | Sort-Object Dossier)
        ARelire  = @($aRelire | Sort-Object Dossier)
        Fichiers = @(@($aRetirer | ForEach-Object { $_.Fichier }) | Sort-Object -Unique)
    }
}

function Set-CtxAgentDossiersApprouves {
    <#
      Retire des dossiers d'un fichier de reglages, et REFUSE d'ecrire si la
      transformation a touche autre chose.

      Rend un objet decrivant ce qui s'est passe. -Apply absent : rien n'est
      ecrit, tout est calcule -- la prevision et l'action suivent le meme chemin,
      donc ce qui est montre est ce qui sera fait.

      POURQUOI TANT DE PRECAUTIONS POUR SUPPRIMER TROIS LIGNES

      Ce fichier decide de ce que TOUS les agents ont le droit de faire. Il
      contient aussi des crochets, des serveurs MCP, une ligne de statut. Un
      aller-retour JSON qui reformaterait ou perdrait l'un d'eux serait une
      panne discrete dans le fichier le moins souvent relu de la machine.

      D'ou la verification apres coup : on compare les cles avant et apres, et
      on n'ecrit que si le seul changement est celui annonce.
    #>
    # SupportsShouldProcess : la fonction modifie l'etat de la machine, et
    # -WhatIf est exactement le reflexe qu'on veut laisser disponible sur un
    # fichier qui decide de ce que TOUS les agents ont le droit de faire.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Fichier,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Retirer,
        [switch]$Apply
    )

    $brut = Get-Content -LiteralPath $Fichier -Raw -ErrorAction Stop
    $data = $brut | ConvertFrom-Json -ErrorAction Stop

    $perm = Get-CtxProp $data 'permissions'
    if (-not $perm) { throw (T 'guard.sansPermissions' $Fichier) }

    $avant = @(Get-CtxProp $perm 'additionalDirectories')
    $apres = @($avant | Where-Object { $Retirer -notcontains $_ })
    $retires = @($avant | Where-Object { $Retirer -contains $_ })

    # Instantane AVANT mutation : ConvertTo-Json rend une chaine tout de suite.
    $texteAvant = $data | ConvertTo-Json -Depth 100
    $clesAvant = @($data.PSObject.Properties.Name | Sort-Object)
    $clesPermAvant = @($perm.PSObject.Properties.Name | Sort-Object)

    $perm.additionalDirectories = $apres
    $texteApres = $data | ConvertTo-Json -Depth 100

    # --- la transformation n'a-t-elle fait QUE ce qu'elle annoncait ? -------
    $relu = $texteApres | ConvertFrom-Json -ErrorAction Stop
    $permRelu = Get-CtxProp $relu 'permissions'

    $ecarts = @()
    if (@($relu.PSObject.Properties.Name | Sort-Object) -join '|' -ne ($clesAvant -join '|')) {
        $ecarts += 'cles de premier niveau'
    }
    if (@($permRelu.PSObject.Properties.Name | Sort-Object) -join '|' -ne ($clesPermAvant -join '|')) {
        $ecarts += 'cles de permissions'
    }
    $reluDossiers = @(Get-CtxProp $permRelu 'additionalDirectories')
    foreach ($r in $retires) {
        if ($reluDossiers -contains $r) { $ecarts += "non retire : $r" }
    }
    foreach ($g in $apres) {
        if ($reluDossiers -notcontains $g) { $ecarts += "perdu : $g" }
    }
    if ($ecarts.Count -gt 0) { throw (T 'guard.transformationSuspecte' ($ecarts -join ' ; ')) }

    $sauvegarde = $null
    $ecrit = $false
    if ($Apply -and $retires.Count -gt 0 -and $PSCmdlet.ShouldProcess($Fichier, (T 'guard.action' $retires.Count))) {
        # PAS DE SAUVEGARDE, PAS D'ECRITURE -- la regle de Fix.ps1, et elle vaut
        # d'autant plus ici. L'echec d'ecriture de la sauvegarde a deja ete
        # avale une fois dans ce depot ; il leve, maintenant.
        $horodatage = (Get-Date -Format 'yyyyMMdd-HHmmss')
        $sauvegarde = "$Fichier.devctx-$horodatage.bak"
        Set-Content -LiteralPath $sauvegarde -Value $brut -Encoding UTF8 -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $sauvegarde)) { throw (T 'guard.sauvegardeEchouee' $sauvegarde) }

        Set-Content -LiteralPath $Fichier -Value $texteApres -Encoding UTF8 -ErrorAction Stop
        $ecrit = $true
    }

    [pscustomobject]@{
        Fichier    = $Fichier
        Retires    = @($retires)
        Restants   = @($apres)
        # Mesure de ce qui S'EST PASSE, jamais de ce qui etait demande : sous
        # -WhatIf rien n'est ecrit, et annoncer le contraire serait le seul
        # mensonge qu'un mode d'essai ne peut pas se permettre.
        Ecrit      = [bool]$ecrit
        Sauvegarde = $sauvegarde
        Texte      = $texteApres
        TexteAvant = $texteAvant
    }
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

function Invoke-DevContextGuard {
    <#
      `ctx guard` -- montre, puis retire sur demande, les dossiers approuves en
      portee utilisateur qui appartiennent a un contexte.

      PREVISUALISATION PAR DEFAUT. Ce fichier decide de ce que tous les agents
      ont le droit de faire ; une commande qui le modifie sans montrer d'abord
      demande une confiance qu'elle n'a pas encore meritee.
    #>
    [CmdletBinding()]
    param([switch]$Apply, [string]$Path = (Get-Location).Path)

    $faits = @(Get-CtxAgentConfianceFacts -Dossier $Path)
    $plan = Resolve-CtxGuardPlan -Faits $faits

    Write-Host ''
    Write-Host ('  ' + (T 'guard.titre'))
    Write-Host ''

    if ($plan.ARetirer.Count -eq 0 -and $plan.ARelire.Count -eq 0) {
        Write-Host ('  ' + (T 'guard.rien'))
        Write-Host ''
        return
    }

    if ($plan.ARetirer.Count -gt 0) {
        Write-Host ('  ' + (T 'guard.aRetirer' $plan.ARetirer.Count))
        foreach ($f in $plan.ARetirer) {
            Write-Host ('    - ' + (T 'guard.aRetirerLigne' $f.Dossier $f.Proprietaire))
        }
        Write-Host ''
        Write-Host ('  ' + (T 'guard.pourquoi'))
        Write-Host ''
    }

    if ($plan.ARelire.Count -gt 0) {
        Write-Host ('  ' + (T 'guard.aRelire' $plan.ARelire.Count))
        foreach ($f in $plan.ARelire) {
            Write-Host ('    ? ' + $f.Dossier)
        }
        Write-Host ''
    }

    # Dit une fois, et pas a demi-mot : ce que cette commande ne peut pas faire.
    Write-Host ('  ' + (T 'guard.denyInerte'))
    Write-Host ''

    if (-not $Apply) {
        if ($plan.ARetirer.Count -gt 0) {
            Write-Host ('  ' + (T 'guard.apercu'))
            Write-Host ''
        }
        return
    }

    if ($plan.ARetirer.Count -eq 0) { return }

    $aRetirer = @($plan.ARetirer | ForEach-Object { $_.Dossier })
    foreach ($fichier in $plan.Fichiers) {
        $r = Set-CtxAgentDossiersApprouves -Fichier $fichier -Retirer $aRetirer -Apply
        if ($r.Ecrit) {
            Write-Host ('  ' + (T 'guard.ecrit' $r.Fichier $r.Retires.Count))
            Write-Host ('  ' + (T 'guard.sauvegarde' $r.Sauvegarde))
        }
    }
    Write-Host ''
}
