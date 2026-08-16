# vercel -- meme dispositif que gh, sur une CLI qui n'offre pas la meme prise.
#
# CE QUI DIFFERE DE gh
#
# `vercel` n'a pas d'equivalent de GH_CONFIG_DIR : son dossier de configuration
# ne se choisit QUE par l'option `-Q, --global-config DIR`. L'isolation ne peut
# donc pas se poser dans l'environnement -- elle doit s'ecrire dans la ligne de
# commande, a chaque appel. C'est exactement ce que faisait deja
# Invoke-DevVercel, et qui n'existait que dans PowerShell.
#
# CE QUI EST GARDE, ET CE QUI NE L'EST PAS
#
# Deux refus seulement, et ils sont ceux de la feuille de route :
#
#   deploiement `--prod` depuis une branche qui n'est pas la branche par defaut
#   `env rm` visant explicitement l'environnement production
#
# Ne sont delibrement PAS gardes :
#
#   `vercel rollback` -- c'est un geste de REPARATION. Le refuser tombe toujours
#     au pire moment : pendant un incident, depuis une branche de correctif.
#   `vercel promote` -- promouvoir un deploiement deja construit depuis une
#     branche laterale est un correctif a chaud legitime.
#   `vercel rm` -- ce qu'il supprime n'est pas identifiable comme production
#     depuis la ligne de commande seule. Refuser sur un doute, c'est refuser au
#     hasard.
#
# Cette liste courte est un choix. Un garde-fou dont on peut enoncer la regle en
# une phrase est un garde-fou qu'on garde ; SECURITY.md la reprend telle quelle.

function Get-CtxVercelMots {
    <#
      Les mots d'une ligne `vercel`, options ecartees. Rendus tous, et pas
      seulement les deux premiers : `vercel env rm CLE production` porte sa
      cible en quatrieme position.

      A ENVELOPPER DANS @() A L'APPEL. PowerShell deballe un tableau d'un seul
      element en le rendant, et `.Count` sur la chaine obtenue leve sous
      StrictMode. Mesure ici meme : `vercel build --prod` etait alors REFUSE,
      parce que la verification qui l'ecarte tombait avant d'avoir lieu. Un
      garde-fou qui se trompe de sens en cas d'erreur interne est pire qu'un
      garde-fou absent.
    #>
    param([string[]]$Arguments = @())
    @(
        $Arguments |
            Where-Object { $_ -and -not "$_".StartsWith('-') } |
            ForEach-Object { "$_".ToLowerInvariant() }
    )
}

function Test-CtxVercelGuard {
    <#
      DECISION PURE. Ni disque, ni reseau, ni git : tout arrive en parametre.

      Toute incertitude laisse passer. Une branche inconnue -- hors depot, HEAD
      detachee -- n'est pas une raison de bloquer un deploiement.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Arguments = @(),
        [AllowNull()][string]$CurrentBranch,
        [AllowNull()][string]$DefaultBranch,
        [switch]$Override
    )

    $passe = { param($regle) [pscustomobject]@{ Allowed = $true; Rule = $regle; Reason = '' } }

    if ($Override) { return (& $passe 'derogation') }

    $mots = @(Get-CtxVercelMots -Arguments $Arguments)

    # --- env rm sur la production -------------------------------------------
    #
    # Seulement quand 'production' est ECRIT. Sans cible, la CLI ouvre une
    # invite et l'humain voit ce qu'il choisit ; refuser la ferait disparaitre
    # pour les environnements de developpement aussi, ou l'operation est banale.
    if ($mots.Count -ge 2 -and $mots[0] -eq 'env' -and $mots[1] -eq 'rm' -and 'production' -in $mots) {
        return [pscustomobject]@{
            Allowed = $false
            Rule    = 'env-rm-production'
            Reason  = (T 'vercel.raison.envRm')
        }
    }

    # --- deploiement de production hors branche par defaut -------------------
    $cible = Get-CtxArgumentValeur -Arguments $Arguments -Nom 'target'
    $prod  = ('--prod' -in @($Arguments | ForEach-Object { "$_" })) -or ($cible -eq 'production')
    if (-not $prod) { return (& $passe 'non-garde') }

    # `vercel build --prod` construit en local sans rien deployer : le refuser
    # serait un faux refus sur une commande sans effet distant. Un `vercel` nu
    # deploie, lui, et ne porte aucun mot.
    $commande = if ($mots.Count -ge 1) { $mots[0] } else { '' }
    if ($commande -and $commande -notin @('deploy', 'redeploy')) { return (& $passe 'non-deploiement') }

    if (-not $CurrentBranch -or -not $DefaultBranch) { return (& $passe 'branche-inconnue') }
    if ($CurrentBranch -eq $DefaultBranch)           { return (& $passe 'branche-par-defaut') }

    [pscustomobject]@{
        Allowed = $false
        Rule    = 'prod-hors-branche'
        Reason  = (T 'vercel.raison.prodBranche' $CurrentBranch $DefaultBranch)
    }
}

function Resolve-CtxVercelVerdict {
    <#
      RASSEMBLE, puis decide. Rend aussi le dossier de configuration a injecter,
      quand il y en a un a injecter.

      Meme lecon que le garde-fou Supabase le 16 aout 2026 : la regle vit dans
      le module, parce qu'elle a deux appelants -- le shim du PATH et l'alias
      PowerShell, ce dernier passant AVANT le shim dans une session qui a
      importe le module.
    #>
    param(
        [string[]]$Arguments = @(),
        [string]$Path
    )

    $dossier = if ($Path) { $Path } else { (Get-Location).Path }

    $branches = Get-CtxBranchesPour -Dossier $dossier
    $verdict  = Test-CtxVercelGuard -Arguments $Arguments `
        -CurrentBranch $branches.Courante -DefaultBranch $branches.Defaut `
        -Override:($env:DEVCTX_ALLOW_VERCEL -eq '1')

    $config = $null
    $avertissement = $null
    $manifeste = Resolve-DevContextForPath -Path $dossier
    if ($manifeste) {
        $contexte = Get-CtxProp $manifeste 'name'
        $attendu  = [System.IO.Path]::Combine((Get-CtxPath $contexte), 'vercel')
        $mots     = @(Get-CtxVercelMots -Arguments $Arguments)

        # Un `--global-config` deja present a ete ecrit volontairement. On ne
        # l'ecrase pas : un outil qui defait un choix explicite devient
        # imprevisible, et c'est la meme regle que pour GH_CONFIG_DIR.
        $dejaPose = @($Arguments | Where-Object {
                "$_" -eq '--global-config' -or "$_" -eq '-Q' -or "$_".StartsWith('--global-config=')
            }).Count -gt 0

        if (-not $dejaPose) {
            $connecte = Test-Path -LiteralPath ([System.IO.Path]::Combine($attendu, 'auth.json'))
            if ($mots.Count -ge 1 -and $mots[0] -in @('login', 'logout', 'switch')) {
                # Ces commandes ont le dossier de configuration pour SUJET. Les
                # rediriger fait qu'un `vercel login` tape dans le contexte
                # connecte CE contexte -- et c'est la sortie du cas "pas encore
                # de session", donc elle doit marcher avant qu'il y en ait une.
                if (-not (Test-Path -LiteralPath $attendu)) {
                    New-Item -ItemType Directory -Force -Path $attendu | Out-Null
                }
                $config = $attendu
                $avertissement = T 'vercel.avert.session' $contexte
            }
            elseif ($connecte) {
                $config = $attendu
            }
            # Ni session ni commande de session : on ne redirige pas. Pointer
            # vers un dossier vide rendrait "non connecte" la ou `vercel`
            # fonctionnait, ce qui est une regression, pas une protection.
        }
    }
    elseif ($env:DEVCTX_VERCEL_CONFIG) {
        # Hors de toute racine de contexte, mais un `work` est passe par la. On
        # honore ce qu'il a pose : c'est le comportement d'Invoke-DevVercel
        # depuis toujours, et le retirer casserait les dossiers qui vivent en
        # dehors des racines declarees.
        $sessionPosee = [System.IO.Path]::Combine($env:DEVCTX_VERCEL_CONFIG, 'auth.json')
        if (Test-Path -LiteralPath $sessionPosee) { $config = $env:DEVCTX_VERCEL_CONFIG }
    }

    [pscustomobject]@{ Verdict = $verdict; ConfigDir = $config; Avertissement = $avertissement }
}

function Get-CtxVercelExe {
    <#
      Le VRAI binaire vercel, en ecartant tous nos dossiers de shims.

      Indispensable depuis qu'un shim `vercel` existe : sans cette exclusion,
      `Get-Command vercel` trouve le shim, qui se rappelle lui-meme. Le module
      a paye cette lecon trois fois -- Get-CtxSupabaseExe (1.3.1),
      Find-CtxEditorCli (1.3.2), l'audit des raccourcis (1.3.4) -- et la
      comparaison porte donc sur TOUS les noms du dossier, jamais un seul.
    #>
    $exclus = Get-CtxShimDirs
    $tous = @(Get-Command vercel -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)
    $candidat = $tous | Where-Object {
        -not (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $_.Source -Parent) -Dossiers $exclus)
    } | Select-Object -First 1

    if (-not $candidat) { throw (T 'bin.vercelAbsent') }
    $candidat.Source
}

function Write-CtxVercelRefus {
    <#
      N'imprime ni jeton, ni variable d'environnement, ni les arguments : un
      refus finit dans les journaux et se colle dans les conversations.
    #>
    param([Parameter(Mandatory)]$Verdict)

    Write-Host ''
    Write-Host "  $(T 'vercel.refuse')" -ForegroundColor Red
    Write-Host ''
    Write-Host "    $(T 'garde.raison' $Verdict.Reason)"
    Write-Host ''
    Write-Host "    $(T 'vercel.derogation')" -ForegroundColor DarkGray
    Write-Host '      $env:DEVCTX_ALLOW_VERCEL = 1' -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil1')" -ForegroundColor DarkGray
    Write-Host "    $(T 'garde.jamaisProfil2')" -ForegroundColor DarkGray
    Write-Host ''
}
