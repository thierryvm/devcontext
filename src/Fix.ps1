# ---------------------------------------------------------------------------
# ctx doctor -Fix -- appliquer la correction que le constat enonce deja
# ---------------------------------------------------------------------------
#
# THE IDEA
#
# The diagnostic already knows the answer. Every finding carries a Correctif
# field naming the exact command. Making the human retype it is friction for
# nothing -- and worse, it is friction at the moment they are least willing to
# read carefully.
#
# WHAT THIS DELIBERATELY DOES NOT DO
#
# It repairs only what it can PROVE and UNDO. Three repairs qualify today, and
# the list is short on purpose: a fixer that overreaches is uninstalled the
# first time it does something its owner did not expect, and it takes the
# useful two thirds with it.
#
# Everything else is NAMED, with the reason it is not automatic. That half
# matters as much as the repairs -- an unexplained silence reads as "nothing
# more to do", which is exactly the false reassurance the whole module exists
# to remove. Four families stay manual, for four different reasons:
#
#   - `gh/compte`, `supabase/compte` -- the fix is `work <ctx>`, which sets
#     environment variables IN THE CALLING SHELL. A child process cannot write
#     into its parent's environment; this is an OS property, not a missing
#     feature. Pretending otherwise would produce a repair that reports success
#     and changes nothing.
#   - `garde-fou/priorite` -- writes to HKLM, so it needs elevation. A tool that
#     silently asks for administrator rights is a tool people stop trusting.
#     The exact command is printed instead.
#   - a duplicated CLI -- uninstalling software is never a diagnostic's job.
#   - `garde-fou/WSL` -- nothing on the Windows side can close it.
#
# KEYING ON Domaine/Sujet IS SAFE, AND THAT IS NOT AN ACCIDENT
#
# Both fields are LITERALS everywhere in Doctor.ps1 -- never a translated
# lookup. Only Detail and Correctif are translated. So this table works
# identically under `fr` and `en`, and a test pins that property: the day
# someone passes a translated value as a Sujet, this file would silently stop
# repairing anything in the other language. That defect has already landed four
# times in this repository.

# La table EST le contrat. Une entree ici = une reparation possible.
$script:CtxReparations = [ordered]@{
    'path/entree vide'   = 'Repair-CtxPathEntreesVides'
    'garde-fou/portee'   = 'Repair-CtxShims'
    'garde-fou/jonction' = 'Repair-CtxShims'
}

# Les constats non reparables et LA RAISON. La cle du message est ici, le texte
# dans les fichiers de langue -- c'est une phrase lue par un humain.
$script:CtxNonReparables = [ordered]@{
    'gh/compte'           = 'fix.non.shell'
    'supabase/compte'     = 'fix.non.shell'
    'supabase/projet'     = 'fix.non.index'
    'vercel/session'      = 'fix.non.shell'
    'garde-fou/priorite'  = 'fix.non.admin'
    'garde-fou/WSL'       = 'fix.non.wsl'
    'gh/binaire'          = 'fix.non.paquet'
    'supabase/binaire'    = 'fix.non.paquet'
    'vercel/binaire'      = 'fix.non.paquet'
    'node/binaire'        = 'fix.non.paquet'
    'git/binaire'         = 'fix.non.paquet'
}

function Invoke-CtxDoctorFix {
    <#
      Orchestration. Applique ce qui est reparable, ENONCE le reste.

      Ne rend rien sur le pipeline : `-Fix` est une action, pas une question. Un
      appelant qui veut des objets lance `ctx doctor` sans `-Fix`, avant et
      apres, et compare -- ce qui est aussi la seule facon honnete de verifier
      qu'une reparation a servi.

      L'ordre d'affichage est voulu : d'abord ce qui a ete fait, ensuite ce
      qui reste a la main. L'inverse ferait lire la liste des echecs a quelqu'un
      qui ne sait pas encore que le reste a marche.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = @'
Cette fonction DELEGUE la confirmation. Elle ne modifie rien elle-meme : chaque
Repair-Ctx* qu'elle appelle porte son propre SupportsShouldProcess et appelle
ShouldProcess sur le geste PRECIS qu'il va faire -- "retirer 2 entrees du PATH
utilisateur", et non "reparer des choses". C'est la formulation utile.

L'attribut reste declare ici pour que -WhatIf et -Confirm se posent sur la
commande que l'utilisateur tape, et se propagent par les preferences.
'@)]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Checks,
        # Injectable : les tests verifient la repartition sans rien reparer.
        [scriptblock]$Executeur = { param($Fonction) & $Fonction }
    )

    $faits = @()
    $manuels = @()

    # Un ensemble a part, et non `$faits.Fonction`. Sous StrictMode, lire une
    # propriete sur un TABLEAU VIDE leve -- et le tableau est forcement vide au
    # premier tour. Mesure le 17 aout 2026 : le rapport s'affichait en entier,
    # puis la commande se terminait sur une exception.
    $dejaLancees = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($c in $Checks) {
        $domaine = Get-CtxProp $c 'Domaine'
        $sujet = Get-CtxProp $c 'Sujet'
        $verdict = Get-CtxProp $c 'Verdict'

        $fonction = Resolve-CtxReparation -Domaine $domaine -Sujet $sujet -Verdict $verdict
        if ($fonction) {
            # Une meme reparation peut couvrir deux constats -- les shims et la
            # jonction sortent du meme installateur. La lancer deux fois serait
            # inoffensif (elle est idempotente) mais afficherait deux lignes pour
            # un seul geste, ce qui se lit comme deux problemes.
            if (-not $dejaLancees.Add($fonction)) { continue }

            $r = & $Executeur $fonction
            $faits += [pscustomobject]@{
                Sujet    = "$domaine/$sujet"
                Fonction = $fonction
                Applique = [bool](Get-CtxProp $r 'Applique')
                Detail   = [string](Get-CtxProp $r 'Detail')
            }
            continue
        }

        # Un constat sain n'a rien a reparer, et n'a rien a faire dans la liste
        # des choses restant a la main.
        if ($verdict -notin @('ATTENTION', 'PROBLEME')) { continue }

        $cle = Resolve-CtxRaisonManuelle -Domaine $domaine -Sujet $sujet
        $manuels += [pscustomobject]@{
            Sujet  = "$domaine/$sujet"
            Raison = if ($cle) { T $cle } else { '' }
            # A defaut de raison specifique, le constat porte deja sa commande :
            # la reafficher vaut mieux qu'un silence qui se lit "rien a faire".
            Correctif = [string](Get-CtxProp $c 'Correctif')
        }
    }

    Write-Host ''
    if ($faits.Count -eq 0 -and $manuels.Count -eq 0) {
        Write-Host "  $(T 'fix.rienAFaire')" -ForegroundColor Green
        Write-Host ''
        return
    }

    if ($faits.Count -gt 0) {
        Write-Host "  $(T 'fix.titreFaits')" -ForegroundColor Cyan
        foreach ($f in $faits) {
            $couleur = if ($f.Applique) { 'Green' } else { 'DarkGray' }
            $marque = if ($f.Applique) { '+' } else { '.' }
            Write-Host ("    {0} {1,-24} {2}" -f $marque, $f.Sujet, $f.Detail) -ForegroundColor $couleur
        }
        Write-Host ''
    }

    if ($manuels.Count -gt 0) {
        Write-Host "  $(T 'fix.titreManuels')" -ForegroundColor Yellow
        foreach ($m in $manuels) {
            Write-Host ("    - {0}" -f $m.Sujet) -ForegroundColor Yellow
            if ($m.Raison) { Write-Host ("        {0}" -f $m.Raison) -ForegroundColor DarkGray }
            elseif ($m.Correctif) { Write-Host ("        {0}" -f $m.Correctif) -ForegroundColor DarkGray }
        }
        Write-Host ''
    }

    Write-Host "  $(T 'fix.relancer')" -ForegroundColor DarkGray
    Write-Host ''
}

function Get-CtxReparations {
    <#
      PURE. La table des reparations, copiee. Les tests et l'aide lisent UNE
      source plutot qu'une liste recopiee qui se perimerait.
    #>
    [CmdletBinding()]
    param()
    $copie = [ordered]@{}
    foreach ($k in $script:CtxReparations.Keys) { $copie[$k] = $script:CtxReparations[$k] }
    $copie
}

function Resolve-CtxReparation {
    <#
      PURE. Ce constat est-il reparable automatiquement ?

      Rend le nom de la fonction de reparation, ou $null.

      Le VERDICT compte autant que le sujet : un constat OK ou INFO n'est pas un
      probleme, et "reparer" un etat sain est la meilleure facon de casser une
      machine qui allait bien. Seuls ATTENTION et PROBLEME sont candidats.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Domaine,
        [AllowNull()][AllowEmptyString()][string]$Sujet,
        [AllowNull()][AllowEmptyString()][string]$Verdict
    )

    if ($Verdict -notin @('ATTENTION', 'PROBLEME')) { return $null }
    if (-not $Domaine -or -not $Sujet) { return $null }

    $cle = "$Domaine/$Sujet"
    if ($script:CtxReparations.Contains($cle)) { return $script:CtxReparations[$cle] }
    $null
}

function Resolve-CtxRaisonManuelle {
    <#
      PURE. Pourquoi ce constat n'est-il PAS repare automatiquement ?

      Rend une cle de message, ou $null quand on n'a rien de precis a dire --
      auquel cas l'appelant se rabat sur le Correctif deja porte par le constat.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Domaine,
        [AllowNull()][AllowEmptyString()][string]$Sujet
    )
    $cle = "$Domaine/$Sujet"
    if ($script:CtxNonReparables.Contains($cle)) { return $script:CtxNonReparables[$cle] }
    $null
}

function Resolve-CtxPathSansVides {
    <#
      PURE. Le PATH, debarrasse de ses entrees vides et de ses doublons exacts.

      Rend un objet portant la nouvelle valeur ET ce qui a ete retire, pour que
      l'appelant puisse le DIRE plutot que d'agir en silence.

      Normalisation pour comparer, valeur d'origine pour ecrire : casse et barre
      oblique finale ne font pas deux dossiers, mais reecrire l'entree sous une
      forme normalisee changerait ce que l'utilisateur avait tape.

      Ce qui n'est PAS fait ici : retirer une entree utilisateur qui doublonne
      le PATH SYSTEME. C'est pourtant du poids mort -- le PATH systeme precede
      toujours -- mais cela demanderait de lire HKLM, et une reparation qui
      depend d'une seconde source peut se tromper de facon invisible. Le
      diagnostic le signale ; l'humain tranche.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Path)

    $retires = @()
    $gardes = @()
    $vus = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($e in ("$Path" -split ';')) {
        if ([string]::IsNullOrWhiteSpace($e)) { $retires += '(vide)'; continue }
        $n = $e.Trim().TrimEnd('\').ToLowerInvariant()
        if (-not $vus.Add($n)) { $retires += $e.Trim(); continue }
        $gardes += $e.Trim()
    }

    [pscustomobject]@{
        Valeur  = ($gardes -join ';')
        Retires = @($retires)
        Change  = $retires.Count -gt 0
    }
}

function Repair-CtxPathEntreesVides {
    <#
      ACTION. Retire les entrees vides et les doublons du PATH UTILISATEUR.

      UNE ENTREE VIDE N'EST PAS COSMETIQUE : Windows lit ';;' comme le dossier
      COURANT. Toute commande tapee depuis un dossier contenant un git.exe, un
      node.exe ou un supabase.exe hostile le lancerait avant le vrai. C'est la
      raison pour laquelle le diagnostic la signale, et elle merite mieux qu'un
      haussement d'epaules.

      TROIS PRECAUTIONS, TOUTES DEJA PAYEES DANS CE DEPOT

      1. Sauvegarde du PATH d'origine sur disque AVANT d'ecrire. Une valeur de
         PATH perdue est une machine a reparer a la main.
      2. Lecture BRUTE (DoNotExpandEnvironmentNames) et ecriture du MEME type de
         registre. [Environment]::SetEnvironmentVariable rend la valeur
         DEVELOPPEE ; la reecrire fige %USERPROFILE% en chemin litteral et
         retrograde un REG_EXPAND_SZ en REG_SZ, en silence et pour de bon.
      3. HKCU uniquement. Le PATH systeme demande l'elevation, et ce n'est pas
         a un diagnostic de la reclamer.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Injectable pour les tests : la cle ou lire et ecrire.
        [string]$Cle = 'Environment',
        [string]$DossierSauvegarde
    )

    $reg = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Cle, $true)
    if (-not $reg) { throw (T 'fix.pathIllisible') }

    try {
        # LA VALEUR PEUT NE PAS EXISTER. GetValue rend son defaut sans broncher,
        # mais GetValueKind LEVE -- et une machine ou le PATH utilisateur n'a
        # jamais ete pose est parfaitement normale. Le defaut est invisible ici,
        # ou cette valeur existe depuis toujours ; il ne casserait que chez
        # quelqu'un d'autre. Releve par la revue automatique le 17 aout 2026.
        $brut = $reg.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $brut) {
            return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.pathAbsent') }
        }

        $type = $reg.GetValueKind('Path')
        $calcul = Resolve-CtxPathSansVides -Path $brut

        if (-not $calcul.Change) {
            return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.pathRien') }
        }

        $cible = "$($calcul.Retires.Count) " + (T 'fix.pathEntrees')
        if (-not $PSCmdlet.ShouldProcess($cible, (T 'fix.pathAction'))) {
            return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.ignore') }
        }

        # LA SAUVEGARDE EST UNE CONDITION, PAS UN CONFORT.
        #
        # Tout l'argument de surete de cette reparation est "reversible parce
        # que sauvegardee". Une ecriture de sauvegarde qui echoue en silence
        # retire la reversibilite ET laisse croire qu'elle est la -- ce qui est
        # pire que de ne pas sauvegarder du tout, puisque personne ne le sait.
        #
        # Donc : pas de sauvegarde, pas d'ecriture. Meme dossier que celle posee
        # par installer-shims.ps1, pour que "ou est mon ancien PATH" n'ait qu'une
        # seule reponse.
        if (-not $DossierSauvegarde) { $DossierSauvegarde = Get-CtxShimRacine }
        if (-not $DossierSauvegarde) {
            return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.sauvegardeSansDossier') }
        }

        $sauvegarde = Join-Path $DossierSauvegarde 'path-utilisateur-avant-fix.txt'
        try {
            if (-not (Test-Path -LiteralPath $DossierSauvegarde)) {
                New-Item -ItemType Directory -Path $DossierSauvegarde -Force -ErrorAction Stop | Out-Null
            }
            Set-Content -LiteralPath $sauvegarde -Value $brut -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.sauvegardeEchec' $sauvegarde) }
        }

        # Le type d'origine est repose explicitement. Voir precaution 2.
        $reg.SetValue('Path', $calcul.Valeur, $type)

        [pscustomobject]@{
            Applique   = $true
            Detail     = (T 'fix.pathFait' $calcul.Retires.Count)
            Retires    = $calcul.Retires
            Sauvegarde = $sauvegarde
        }
    }
    finally { $reg.Close() }
}

function Repair-CtxShims {
    <#
      ACTION. Relance l'installateur des shims.

      Il porte deja toute la logique -- ecrire les points d'entree, poser la
      jonction, mettre le dossier en tete du PATH utilisateur -- et il est
      idempotent. Le recrire ici en donnerait deux versions, dont une seule
      serait corrigee le jour ou un defaut apparait.

      Couvre donc DEUX constats d'un coup : `garde-fou/portee` (shims absents du
      PATH) et `garde-fou/jonction` (jonction absente ou perimee).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Installateur)

    if (-not $Installateur) {
        $Installateur = Join-Path (Split-Path $PSScriptRoot -Parent) 'installer-shims.ps1'
    }
    if (-not (Test-Path -LiteralPath $Installateur)) {
        return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.installateurAbsent' $Installateur) }
    }

    if (-not $PSCmdlet.ShouldProcess($Installateur, (T 'fix.shimsAction'))) {
        return [pscustomobject]@{ Applique = $false; Detail = (T 'fix.ignore') }
    }

    # Processus separe, sans profil : l'installateur touche au PATH, et le faire
    # dans la session qui vient de lire ce PATH melangerait deux etats.
    $sortie = & pwsh -NoProfile -File $Installateur 2>&1
    $code = $LASTEXITCODE

    [pscustomobject]@{
        Applique = ($code -eq 0)
        Detail   = if ($code -eq 0) { T 'fix.shimsFait' } else { T 'fix.shimsEchec' $code }
        Sortie   = ($sortie | Out-String).Trim()
    }
}
