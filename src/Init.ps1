# ---------------------------------------------------------------------------
# ctx init -- la premiere commande, celle ou l'adoption se gagne ou se perd
# ---------------------------------------------------------------------------
#
# THE PROBLEM
#
# Until 1.8.0, a new user had to clone the repository, create a symlink, run an
# installer, then create contexts by hand from a command line with five
# parameters. Every one of those steps is a place to stop.
#
# Worse, the failure modes were silent. A virgin machine was simulated on 15
# August 2026 and the CLI walked into five dead ends in a row -- `ctx` answered
# a red NO-GO to someone who had done nothing wrong, `ctx-list` said "none"
# without saying what to do next, and two prompts hung forever on redirected
# input.
#
# WHAT THIS COMMAND IS, AND IS NOT
#
# It is a GUIDE, not a wizard that takes over. It reports what is in place, asks
# before each change, and every step it does not perform is printed as the exact
# command that performs it. Someone who prefers to drive by hand loses nothing
# by running it.
#
# It is IDEMPOTENT. Running it on a fully configured machine changes nothing and
# says so -- because the second most likely moment to run it is "something is
# off and I do not remember what I did".
#
# AND IT REFUSES TO ASK A QUESTION IT CANNOT HEAR THE ANSWER TO
#
# With redirected input -- an agent, a CI job, a script -- a prompt does not
# pause, it reads EOF and either loops or takes a default nobody chose. This
# module already paid that lesson: `ctx-new` hung on a passphrase prompt on a
# machine that could never answer, which is why -NoKey exists.
#
# So the interactivity is DETECTED, not assumed, and the non-interactive path is
# a full citizen: it prints the ordered list of commands and exits. Not a
# degraded mode -- the same information, in a form a script can act on.

function Invoke-DevContextInit {
    <#
    .SYNOPSIS
        Sets this machine up, one confirmed step at a time.

    .DESCRIPTION
        Reports what is already in place, then walks the missing pieces in
        order, asking before each change. Every step it does not perform is
        printed as the exact command that performs it -- so someone who prefers
        to drive by hand loses nothing by running this first.

        Idempotent: on a machine that is already set up it changes nothing and
        says so.

        With redirected input it does not prompt at all. It prints the ordered
        list of commands and exits, because a prompt nobody can answer is worse
        than no prompt.

    .PARAMETER Yes
        Answers yes to every confirmation. For a script that genuinely means it.

    .EXAMPLE
        ctx init
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Yes,
        # Injectables : les deux chemins doivent etre testables sans rediriger
        # l'entree du processus de test, et sans installer quoi que ce soit.
        [scriptblock]$SondeInteractive,
        $Faits
    )

    if (-not $Faits) { $Faits = Get-CtxInitFacts }
    $etapes = @(Resolve-CtxInitEtapes -Faits $Faits)
    $manquantes = @($etapes | Where-Object { -not $_.Fait })

    $peutDemander = if ($SondeInteractive) { Test-CtxPeutDemander -Sonde $SondeInteractive }
    else { Test-CtxPeutDemander }

    Write-Host ''
    Write-Host "  $(T 'init.titre')" -ForegroundColor Cyan
    Write-Host ''

    # L'etat, toujours affiche -- y compris ce qui va bien. C'est ce qui permet
    # de lancer cette commande quand "quelque chose cloche" sans savoir quoi.
    foreach ($e in $etapes) {
        $marque = if ($e.Fait) { '+' } else { '-' }
        $couleur = if ($e.Fait) { 'Green' } else { 'Yellow' }
        Write-Host ("    {0} {1}" -f $marque, (T "init.etape.$($e.Cle)")) -ForegroundColor $couleur
    }
    Write-Host ''
    Write-Host "  $(T 'init.racine' (Get-CtxProp $Faits 'Racine'))" -ForegroundColor DarkGray
    Write-Host "  $(T 'init.racineChanger')" -ForegroundColor DarkGray
    Write-Host ''

    if ($manquantes.Count -eq 0) {
        Write-Host "  $(T 'init.rienAFaire')" -ForegroundColor Green
        Write-Host "  $(T 'init.suite')" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # --- entree redirigee : on n'invente pas de reponse -----------------------
    if (-not $peutDemander -and -not $Yes) {
        Write-Host "  $(T 'init.nonInteractif')" -ForegroundColor Yellow
        Write-Host ''
        foreach ($e in $manquantes) {
            Write-Host ("    {0}" -f (T "init.etape.$($e.Cle)")) -ForegroundColor Yellow
            Write-Host ("      {0}" -f $e.Commande) -ForegroundColor Cyan
        }
        Write-Host ''
        Write-Host "  $(T 'init.suite')" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # --- chemin interactif ----------------------------------------------------
    foreach ($e in $manquantes) {
        Write-Host ("  {0}" -f (T "init.etape.$($e.Cle)")) -ForegroundColor Yellow

        if (-not $e.Auto) {
            # Rien a proposer d'executer : on nomme la commande et on passe.
            # Installer un module est une dependance nouvelle, et cela ne se
            # decide pas au nom de quelqu'un d'autre.
            Write-Host ("    {0}" -f (T 'init.manuel')) -ForegroundColor DarkGray
            Write-Host ("    {0}" -f $e.Commande) -ForegroundColor Cyan
            Write-Host ''
            continue
        }

        if (-not ($Yes -or $PSCmdlet.ShouldProcess($e.Cle, (T 'init.action')))) {
            Write-Host ("    {0}" -f $e.Commande) -ForegroundColor Cyan
            Write-Host ''
            continue
        }

        switch ($e.Cle) {
            'shims' {
                $r = Repair-CtxShims -Confirm:$false
                $couleur = if (Get-CtxProp $r 'Applique') { 'Green' } else { 'Red' }
                Write-Host ("    {0}" -f (Get-CtxProp $r 'Detail')) -ForegroundColor $couleur
            }
            'contexte' {
                # On ne cree RIEN sans les informations exactes : la commande est
                # affichee pre-remplie, et c'est l'utilisateur qui la lance. Creer
                # un contexte pose une cle SSH et un dossier ; le faire sur une
                # supposition serait le genre d'aide dont on se passe.
                Write-Host ("    {0}" -f (T 'init.contexteProposition')) -ForegroundColor DarkGray
                Write-Host ("    {0}" -f $e.Commande) -ForegroundColor Cyan
            }
        }
        Write-Host ''
    }

    Write-Host "  $(T 'init.suite')" -ForegroundColor DarkGray
    Write-Host ''
}

function Get-CtxGhComptesDepuisStatut {
    <#
      PURE. Les logins presents dans la sortie de `gh auth status`.

      Format reel, mesure le 17 aout 2026 :

          github.com
            v Logged in to github.com account octo-dev (keyring)
            - Active account: true

      On lit la ligne "Logged in to <hote> account <login>", et rien d'autre :
      les lignes voisines contiennent un jeton masque et des portees, dont ce
      code n'a aucun besoin.

      FAIL-SOFT PAR CONSTRUCTION. Ce resultat ne sert qu'a PRE-REMPLIR une
      proposition. Si gh change son libelle, la liste est vide, la proposition
      est moins bonne, et rien ne casse. Une detection cosmetique n'a pas le
      droit d'empecher la commande de fonctionner.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Texte)

    if ([string]::IsNullOrWhiteSpace($Texte)) { return @() }
    $trouves = [regex]::Matches($Texte, '(?im)^\s*.{0,3}\s*Logged in to \S+ account (\S+)')
    @($trouves | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ } | Select-Object -Unique)
}

function Resolve-CtxNomPropose {
    <#
      PURE. Un nom de contexte valide, propose a partir de ce qu'on sait deja.

      New-DevContext exige ^[a-z0-9][a-z0-9-]*$. Proposer un nom qu'il refusera
      ensuite est la pire des aides : l'utilisateur croit avoir suivi la
      consigne et se prend un rejet.

      Ordre de preference : le login GitHub, puis la partie locale de l'email,
      puis 'perso'. Le login d'abord parce que c'est le nom sous lequel le
      travail sortira reellement.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Login,
        [AllowNull()][AllowEmptyString()][string]$Email
    )

    foreach ($source in @($Login, ($Email -split '@')[0])) {
        if ([string]::IsNullOrWhiteSpace($source)) { continue }
        # Minuscules, et tout ce qui n'est ni lettre ni chiffre devient un tiret.
        $n = ($source.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        if ($n -match '^[a-z0-9][a-z0-9-]*$') { return $n }
    }
    'perso'
}

function Get-CtxInitFacts {
    <#
      GATHERING. Ce qui est deja en place sur cette machine.

      Aucun jugement ici : la question "que faut-il faire" est repondue par
      Resolve-CtxInitEtapes, qui est pure et donc verifiable sans machine.

      Chaque source est protegee par un try : `ctx init` s'adresse par
      definition a une machine mal configuree, et il serait absurde qu'il tombe
      sur la premiere chose qui manque.
    #>
    [CmdletBinding()]
    param(
        [scriptblock]$LecteurGh = {
            $exe = try { Get-CtxGhExe } catch { $null }
            if (-not $exe) { return '' }
            try { (& $exe auth status 2>&1 | Out-String) } catch { '' }
        },
        [scriptblock]$LecteurGit = {
            # try/catch est une INSTRUCTION, pas une expression : il ne peut pas
            # vivre dans un litteral de table de hachage. D'ou les variables
            # intermediaires ici et plus bas -- ce n'est pas de la verbosite.
            $n = $null; $e = $null
            try { $n = git config --global user.name 2>$null } catch { $n = $null }
            try { $e = git config --global user.email 2>$null } catch { $e = $null }
            [pscustomobject]@{ Nom = $n; Email = $e }
        }
    )

    $racine = $script:CtxRoot

    $git = $null
    try { $git = & $LecteurGit } catch { $git = $null }

    $contextes = @()
    try { $contextes = @(Get-CtxManifests) } catch { $contextes = @() }

    $statutGh = ''
    try { $statutGh = & $LecteurGh } catch { $statutGh = '' }

    $coffre = $false
    try { $coffre = [bool](Get-Module -ListAvailable Microsoft.PowerShell.SecretManagement -ErrorAction SilentlyContinue) }
    catch { $coffre = $false }

    [pscustomobject]@{
        Coffre        = $coffre
        ShimsDansPath = [bool](Test-CtxShimsDansPath)
        Racine        = $racine
        RacineExiste  = [bool]($racine -and (Test-Path -LiteralPath $racine))
        NbContextes   = $contextes.Count
        GitNom        = Get-CtxProp $git 'Nom'
        GitEmail      = Get-CtxProp $git 'Email'
        ComptesGh     = @(Get-CtxGhComptesDepuisStatut -Texte $statutGh)
    }
}

function Test-CtxShimsDansPath {
    <#
      Les shims sont-ils joignables par le PATH de CE processus ?

      On interroge la COMMANDE, jamais le fichier. Un shim present sur disque et
      jamais atteint est le defaut exact du 16 aout 2026 : le garde-fou etait
      pose, annonce actif, et un binaire du PATH systeme passait devant.
      Verifier l'existence du fichier aurait repondu "oui" tout du long.
    #>
    [CmdletBinding()]
    param([string[]]$Dossiers = (Get-CtxShimDirs))

    $trouves = Get-Command 'supabase' -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue
    foreach ($t in @($trouves)) {
        if (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $t.Source -Parent) -Dossiers $Dossiers) { return $true }
    }
    $false
}

function Resolve-CtxInitEtapes {
    <#
      PURE. Que reste-t-il a faire, et dans quel ordre ?

      Chaque etape porte SA commande. C'est ce qui permet au mode non interactif
      d'etre un citoyen a part entiere plutot qu'un mode degrade : il affiche
      exactement ce que le mode interactif aurait execute.

      L'ordre n'est pas cosmetique. Le coffre d'abord, parce que creer un
      contexte sans lui echoue a mi-chemin en laissant un dossier derriere.
      Les shims ensuite, parce qu'ils ne dependent d'aucun contexte. Le contexte
      en dernier, parce qu'il est le seul a demander des informations.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Faits)

    $etapes = @()

    # 1. Le coffre. NON automatisable : installer un module est une dependance
    #    nouvelle, et cela ne se fait pas au nom de quelqu'un sans son accord.
    $etapes += [pscustomobject]@{
        Cle       = 'coffre'
        Fait      = [bool](Get-CtxProp $Faits 'Coffre')
        Auto      = $false
        Commande  = 'Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser'
    }

    # 2. Les shims. Automatisable : l'installateur est idempotent et reversible.
    $etapes += [pscustomobject]@{
        Cle       = 'shims'
        Fait      = [bool](Get-CtxProp $Faits 'ShimsDansPath')
        Auto      = $true
        Commande  = 'pwsh -File installer-shims.ps1'
    }

    # 3. Un premier contexte. Automatisable, mais il faut des informations --
    #    c'est la seule etape qui exige vraiment de pouvoir poser des questions.
    $nb = [int](Get-CtxProp $Faits 'NbContextes' 0)

    # [0] sur un tableau VIDE leve "Index was outside the bounds of the array" --
    # et une machine vierge, qui est precisement la cible de cette commande, n'a
    # aucun compte gh. Get-CtxProp rend bien le tableau vide plutot que $null,
    # donc c'est l'INDEXATION qu'il faut garder, pas la lecture.
    $comptes = @(Get-CtxProp $Faits 'ComptesGh')
    $login = if ($comptes.Count -gt 0) { $comptes[0] } else { '' }

    $nom = Resolve-CtxNomPropose -Login $login -Email (Get-CtxProp $Faits 'GitEmail')
    $email = Get-CtxProp $Faits 'GitEmail'
    $exemple = if ($email) { "ctx-new -Name $nom -Email $email -Root <dossier>" }
    else { 'ctx-new -Name perso -Email vous@exemple.com -Root <dossier>' }

    $etapes += [pscustomobject]@{
        Cle       = 'contexte'
        Fait      = ($nb -gt 0)
        Auto      = $true
        Commande  = $exemple
        Propose   = [pscustomobject]@{ Nom = $nom; Email = $email }
    }

    @($etapes)
}

function Test-CtxPeutDemander {
    <#
      Peut-on poser une question et en entendre la reponse ?

      Sur une entree redirigee, une invite ne met pas en pause : elle lit une fin
      de fichier, et selon le cmdlet elle boucle ou prend un defaut que personne
      n'a choisi. Un agent, une tache planifiee et un `|` sont tous dans ce cas.

      Injectable pour que les deux chemins soient testables sans avoir a rediriger
      l'entree du processus de test.
    #>
    [CmdletBinding()]
    param([scriptblock]$Sonde = { -not [Console]::IsInputRedirected })
    try { [bool](& $Sonde) } catch { $false }
}
