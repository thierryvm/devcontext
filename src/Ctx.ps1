# ---------------------------------------------------------------------------
# ctx -- point d'entree unique, et repartiteur de sous-commandes
# ---------------------------------------------------------------------------
#
# THE PROBLEM
#
# The module shipped twelve commands spelled `ctx-doctor`, `ctx-list`,
# `ctx-new`. That hyphen is a PowerShell habit; every other CLI a developer
# touches -- git, docker, gh, npm, cargo, supabase, vercel -- separates the
# subcommand with a SPACE. So `ctx doctor` is what fingers type first.
#
# Until 1.5.0 it answered:
#
#     Test-DevContext: A positional parameter cannot be found that accepts
#     argument 'doctor'.
#
# Measured on 17 Aug 2026. Three things wrong with that sentence, and the
# third is the one that matters: it names `Test-DevContext`, an internal
# function the user has never seen, never typed, and cannot find in any
# document. A first contact that names your internals teaches the reader that
# the tool is not for them.
#
# THE RULE THIS FILE ESTABLISHES
#
#     ctx-<nom>  et  ctx <nom>  sont la MEME chose.
#
# Two spellings, one implementation, no second code path to keep in sync --
# the table below is the only place the mapping exists, and the hyphenated
# aliases are built FROM it in the psm1.
#
# WHY A WRAPPER RATHER THAN A PARAMETER ON Test-DevContext
#
# Adding `[Parameter(Position=0)][string]$Command` to an advanced function
# does not work: `ctx doctor -Live` would then fail on -Live, because an
# advanced function rejects a named parameter it does not declare, and
# ValueFromRemainingArguments collects only POSITIONAL leftovers. The subcommand
# would work and every one of its switches would break -- worse than today,
# because it fails halfway.
#
# So `ctx` becomes a function with no param() block at all, reading $args. Same
# doctrine as Invoke-DevGh / Invoke-DevVercel / Invoke-DevSupabase since 1.4.0,
# and pinned by the same AST test: a param() block here would silently claim
# -Verbose, -Debug and the other common parameters, making short options
# ambiguous. See tests/Alias.Tests.ps1.

# La table EST la definition. Les alias ctx-<nom> du psm1 en decoulent, donc
# ajouter une entree ici suffit pour que les deux orthographes existent.
$script:CtxSousCommandes = [ordered]@{
    'check'    = 'Assert-DevContext'
    'doctor'   = 'Get-DevContextDoctor'
    'editors'  = 'Get-DevEditorList'
    'end'      = 'Close-DevContext'
    'init'     = 'Invoke-DevContextInit'
    'list'     = 'Get-DevContextList'
    'mcp'      = 'New-DevProjectMcp'
    'new'      = 'New-DevContext'
    'off'      = 'Clear-DevContext'
    'root'     = 'Set-DevContextRoot'
    'sb'       = 'Get-DevSupabaseMap'
    'shortcut' = 'New-DevShortcut'
    'who'      = 'Resolve-DevContextForPath'
}

function Get-CtxSousCommandes {
    <#
      PURE. La table, copiee. Rendue en tant que fonction pour que les tests et
      les messages d'aide lisent UNE source, jamais une liste recopiee a la main
      qui se perimerait a la premiere sous-commande ajoutee.
    #>
    [CmdletBinding()]
    param()
    $copie = [ordered]@{}
    foreach ($k in $script:CtxSousCommandes.Keys) { $copie[$k] = $script:CtxSousCommandes[$k] }
    $copie
}

function Resolve-CtxSousCommande {
    <#
      PURE. Le premier argument de `ctx` designe-t-il une sous-commande ?

      Rend le nom de la fonction cible, ou $null -- et $null veut dire "ce
      n'est pas une sous-commande", pas "erreur". Trois cas rendent $null :

        - aucun argument            -> `ctx` tout court, le verdict
        - un argument commencant par - -> `ctx -Quiet`, un switch du verdict
        - un mot inconnu            -> l'appelant affiche l'aide

      Le test sur le tiret vient EN PREMIER : sans lui, `ctx -Quiet` serait lu
      comme la sous-commande "-quiet", introuvable, et le verdict -- la commande
      la plus utilisee du module -- afficherait une aide au lieu de repondre.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Mot)

    if ([string]::IsNullOrWhiteSpace($Mot)) { return $null }
    if ($Mot.StartsWith('-')) { return $null }

    $cle = $Mot.Trim().ToLowerInvariant()
    if ($script:CtxSousCommandes.Contains($cle)) { return $script:CtxSousCommandes[$cle] }
    $null
}

function Show-CtxAide {
    <#
      L'ecran que voit quelqu'un qui s'est trompe de mot, ou qui tape `ctx help`.

      Ecrit avec Write-Host et non `throw` : un throw affiche une trace
      d'exception au-dessus du message utile, et c'est l'inverse de ce qu'il
      faut a quelqu'un dont la seule faute est d'avoir mal orthographie un mot.
      Meme parti pris que l'ecran "aucun contexte" de Test-DevContext.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Affiche une aide ; ne modifie aucun etat.')]
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Inconnu)

    Write-Host ''
    if ($Inconnu) {
        Write-Host "  $(T 'ctx.sc.inconnue' $Inconnu)" -ForegroundColor Red
        Write-Host ''
    }
    Write-Host "  $(T 'ctx.sc.titre')" -ForegroundColor Cyan
    Write-Host ''
    Write-Host "    ctx" -ForegroundColor Green -NoNewline
    Write-Host "                     $(T 'ctx.sc.verdict')" -ForegroundColor DarkGray
    foreach ($k in $script:CtxSousCommandes.Keys) {
        Write-Host ("    ctx {0}" -f $k) -ForegroundColor Green -NoNewline
        $pad = ' ' * [Math]::Max(1, 20 - $k.Length)
        Write-Host ("{0}{1}" -f $pad, (T ("ctx.sc.aide.$k"))) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host "  $(T 'ctx.sc.tiret')" -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-DevCtx {
    <#
      Le point d'entree de l'alias `ctx`.

      AUCUN param() ni [CmdletBinding()] -- volontaire, et verifie par un test
      AST. Un bloc param ferait de cette fonction une fonction avancee : elle
      reclamerait alors -Verbose, -Debug, -ErrorAction et consorts, et toute
      option courte des sous-commandes deviendrait ambigue. C'est exactement la
      panne mesuree le 16 aout 2026 sur `gh api -i user`.

      Consequence : la repartition se fait a la main sur $args.
    #>
    $tous = @($args)
    $premier = if ($tous.Count -gt 0) { "$($tous[0])" } else { '' }

    # `ctx help` et `ctx -?` : l'aide, demandee explicitement.
    if ($premier -and ($premier.ToLowerInvariant() -in @('help', '-?', '--help'))) {
        Show-CtxAide
        return
    }

    $cible = Resolve-CtxSousCommande -Mot $premier

    if ($cible) {
        # Splat du reste : PowerShell relit alors -Live, -Force, etc. comme des
        # noms de parametres de la fonction cible.
        #
        # Le @() explicite n'est PAS decoratif. Ecrit
        #     $reste = if ($n -gt 1) { ... } else { @() }
        # la branche vide est ENUMEREE par le pipeline, ne produit aucun objet,
        # et $reste vaut $null -- pas un tableau vide. Le splat passe alors un
        # argument positionnel $null, et `ctx list` echoue sur
        # "A positional parameter cannot be found that accepts argument $null".
        # Mesure le 17 aout 2026. Meme classe de defaut que Get-CtxVercelMots en
        # 1.4.0 : en PowerShell, un tableau qui traverse une expression se
        # deplie, et il faut le redemander a chaque fois.
        $reste = @()
        if ($tous.Count -gt 1) { $reste = @($tous[1..($tous.Count - 1)]) }

        # L'appel et le `return` sont deux instructions distinctes a dessein : en
        # "return & $cible @reste", une erreur de liaison dans l'appel empeche
        # le return de s'executer, et le flot tombait dans l'aide -- affichant
        # "sous-commande inconnue : list" juste apres avoir trouve `list`.
        & $cible @reste
        return
    }

    # Pas un mot connu. Deux cas seulement, et ils ne doivent PAS etre confondus.
    if ($premier -and -not $premier.StartsWith('-')) {
        # Un mot, mais pas des notres : l'utilisateur visait une sous-commande.
        Show-CtxAide -Inconnu $premier
        return
    }

    # Rien, ou uniquement des switches : c'est le verdict, comportement historique.
    Test-DevContext @tous
}
