# ---------------------------------------------------------------------------
# Shortcuts -- the one launcher PATH cannot reach
# ---------------------------------------------------------------------------
#
# The editor shim covers everything that resolves a command by name: a
# terminal, an npm script, an agent, "Open with", and any shortcut whose target
# is `code`. It cannot cover a shortcut whose target is
# C:\...\Microsoft VS Code\Code.exe, because nothing in that chain consults
# PATH. Neither can any other mechanism -- that is what an absolute path means.
#
# So this file does not try to prevent it. It makes it VISIBLE.
#
# A shortcut is created once and used for months; the day it silently stops
# isolating anything is not the day anybody looks at it. `ctx doctor` therefore
# reads the shortcuts that exist and says, for each one, which profile it will
# actually open -- and New-DevShortcut writes correct ones, so nobody has to
# assemble a command line by hand to get it right.
#
# These two functions are also the seam the dashboard plugs into later: listing
# and repairing shortcuts is a button on a screen calling the same code, never
# a second implementation of the same rules living in a UI.

# Le domaine que porte chaque constat de raccourci.
#
# NOMME UNE FOIS. Le tableau de bord partitionne le diagnostic sur cette valeur
# pour donner aux raccourcis leur propre section ; deux litteraux recopies se
# separeraient a la premiere renommee, sans la moindre erreur, avec une section
# qui s'affiche vide -- ce qui ressemble a « aucun raccourci ».
#
# Effet de bord mesure le 22 aout 2026 : le detecteur lexical de
# tests/Langue.Tests.ps1 signale toute comparaison a une valeur presente dans
# les tables de textes, et le libelle de colonne « Raccourci » venait d'y
# entrer. Il ne peut pas distinguer un identifiant de structure d'un libelle
# affiche -- son propre commentaire dit « presque surement ». Nommer la
# constante repond aux deux problemes d'une ligne, et le second n'etait pas le
# motif : un litteral recopie six fois etait deja le defaut.
$script:CtxDomaineRaccourci = 'raccourci'

function Get-CtxShortcutLocations {
    <#
      Where a shortcut lives on Windows: both desktops, both start menus, and
      the pinned taskbar. The pinned one matters most and is looked at least --
      it is the one clicked every morning.
    #>
    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) { return @() }

    @(
        [Environment]::GetFolderPath('Desktop')
        [Environment]::GetFolderPath('CommonDesktopDirectory')
        [Environment]::GetFolderPath('Programs')
        [Environment]::GetFolderPath('CommonPrograms')
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Test-CtxShortcutIsolated {
    <#
      PURE. Does this command line already put the editor on its own profile?

      True for an explicit --user-data-dir, and true for anything routed
      through one of our own launchers or entry points -- those add the flag
      themselves, so demanding to see it written out would report every correct
      shortcut as broken. That is not a detail: a diagnostic whose false alarms
      outnumber its findings gets ignored, and then its real findings go with it.

      -ShimDirs is a LIST, and that is the whole point. Since PATH names a
      junction, one shims folder answers to several names; a shortcut may spell
      it any of them. Comparing against a single name reported a perfectly
      isolated shortcut as PROBLEME -- the third site of that defect, after
      Get-CtxSupabaseExe and Find-CtxEditorCli.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Target,
        [AllowNull()][AllowEmptyString()][string]$Arguments,
        [string[]]$ShimDirs = @()
    )

    if ($Arguments -match '(?i)--user-data-dir') { return $true }

    $inspected = "$Target $Arguments".ToLowerInvariant()
    foreach ($d in $ShimDirs) {
        if ($d -and $inspected.Contains($d.TrimEnd('\', '/').ToLowerInvariant())) { return $true }
    }

    # Les lanceurs du module. lancer-vscode.ps1 est l'historique -- les
    # raccourcis ecrits en aout 2026 le referencent tous -- et lancer-editeur.ps1
    # celui que ctx-shortcut ecrit aujourd'hui. Les deux appellent Open-DevCode,
    # qui pose le flag.
    if ($inspected -match '(?i)lancer-(vscode|editeur)\.ps1') { return $true }

    $false
}

function Get-CtxShortcutIcon {
    <#
      PURE. The icon a shortcut carries, given the editor's executable.

      An icon has to be an absolute path, which reads like a contradiction a
      hundred lines above a function that refuses one for the target. The
      difference is what going stale costs. A stale TARGET stops isolating, in
      silence, and that is the entire bug this file exists for. A stale ICON
      costs a picture: the shell falls back to the launcher's own and the
      shortcut keeps working.

      Returns an EMPTY string when no executable was found, never ',0'. Those
      two look alike and mean different things: ',0' names index 0 of a file it
      does not name. It is also exactly what the shortcut written on 22 August
      2026 carries -- the shape a shortcut has when nobody set an icon at all.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Executable)

    if ([string]::IsNullOrWhiteSpace($Executable)) { return '' }
    "$Executable,0"
}

function Test-CtxShortcutLaunchesEditor {
    <#
      PURE. Is this shortcut about an editor at all?

      Two shapes, and the second is the one that matters. A shortcut may target
      the editor's executable directly -- the shape everybody creates by hand --
      or it may target a shell that runs one of our launchers, which is the
      shape a CORRECT shortcut has. Recognising only the first would grade
      exactly the shortcuts that are already broken and stay silent on the ones
      worth confirming.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Target,
        [AllowNull()][AllowEmptyString()][string]$Arguments,
        [string[]]$EditeurExecutables = @(),
        [string[]]$ShimDirs = @()
    )

    $cible = if ($Target) { [System.IO.Path]::GetFileName($Target) } else { '' }
    if ($cible -and ($EditeurExecutables | Where-Object { $_ -and $cible.ToLowerInvariant() -eq $_.ToLowerInvariant() })) {
        return $true
    }

    $inspected = "$Target $Arguments"
    if ($inspected -match '(?i)lancer-(vscode|editeur)\.ps1') { return $true }
    $minuscule = $inspected.ToLowerInvariant()
    foreach ($d in $ShimDirs) {
        if ($d -and $minuscule.Contains($d.TrimEnd('\', '/').ToLowerInvariant())) { return $true }
    }

    $false
}

function Test-CtxDoctorRaccourci {
    <#
      PURE. What a shortcut will actually open, and on whose profile.

      Three verdicts, and the difference between them is whether anything is at
      stake:

        PROBLEME  -- it opens a folder owned by a context, on the shared
                     profile. Signing into GitHub there signs you out of the
                     other contexts. This is the daily-reconnection bug.
        ATTENTION -- it launches an editor with no folder. Where it lands
                     depends on what the editor last had open.
        OK        -- it isolates, or it is not an editor shortcut at all.

      -Contexte is the context owning the shortcut's folder, or nothing. It is
      passed in rather than resolved here: this function must stay decidable
      without a machine that happens to have contexts on it.
    #>
    param(
        [Parameter(Mandatory)][string]$Nom,
        [AllowNull()][AllowEmptyString()][string]$Target,
        [AllowNull()][AllowEmptyString()][string]$Arguments,
        [AllowNull()][AllowEmptyString()][string]$Contexte,
        [string[]]$EditeurExecutables = @(),
        [string[]]$ShimDirs = @()
    )

    # RIEN, et non un constat « OK, ne lance pas un editeur ».
    #
    # La version precedente rendait un constat que l'appelant reconnaissait en
    # comparant son texte : `if ($verdict.Detail -eq 'ne lance pas un editeur')`.
    # Le jour ou ce texte est devenu traduisible, le filtre ne matchait plus en
    # anglais et deux cents raccourcis sans rapport auraient inonde le rapport.
    # Troisieme occurrence du meme defaut dans ce depot : une valeur AFFICHEE ne
    # sert jamais de valeur de DECISION. L'absence de constat, elle, ne se
    # traduit pas.
    if (-not (Test-CtxShortcutLaunchesEditor -Target $Target -Arguments $Arguments `
                -EditeurExecutables $EditeurExecutables -ShimDirs $ShimDirs)) {
        return
    }

    if (Test-CtxShortcutIsolated -Target $Target -Arguments $Arguments -ShimDirs $ShimDirs) {
        $ou = if ($Contexte) { T 'rac.doc.dansContexte' $Contexte } else { T 'rac.doc.profilDedie' }
        return New-CtxCheck -Domaine $script:CtxDomaineRaccourci -Sujet $Nom -Verdict 'OK' -Detail (T 'rac.doc.isole' $ou)
    }

    if ($Contexte) {
        return New-CtxCheck -Domaine $script:CtxDomaineRaccourci -Sujet $Nom -Verdict 'PROBLEME' `
            -Detail (T 'rac.doc.partage' $Contexte) `
            -Correctif 'ctx-shortcut -Path <projet> -Force'
    }

    New-CtxCheck -Domaine $script:CtxDomaineRaccourci -Sujet $Nom -Verdict 'ATTENTION' `
        -Detail (T 'rac.doc.sansDossier') `
        -Correctif (T 'rac.doc.sansDossierFix')
}

function Get-CtxShortcutFacts {
    <#
      Every shortcut found, read through the shell COM object.

      Gathering, therefore untested and deliberately dull. Anything that
      DECIDES lives in Test-CtxDoctorRaccourci above.
    #>
    param([string[]]$Dossiers = (Get-CtxShortcutLocations))

    if (-not ($IsWindows -or $env:OS -eq 'Windows_NT')) { return }

    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop }
    catch { return }

    try {
        foreach ($dossier in $Dossiers) {
            $liens = Get-ChildItem -LiteralPath $dossier -Filter '*.lnk' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
            foreach ($lien in $liens) {
                try {
                    $raccourci = $shell.CreateShortcut($lien.FullName)
                    [pscustomobject]@{
                        Nom       = $lien.BaseName
                        Fichier   = $lien.FullName
                        Target    = $raccourci.TargetPath
                        Arguments = $raccourci.Arguments
                        Dossier   = $raccourci.WorkingDirectory
                    }
                }
                catch { continue }
            }
        }
    }
    finally {
        if ($shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
}

function Get-CtxRaccourciChecks {
    <#
      The shortcut section of `ctx doctor`.

      Only shortcuts that name an editor are reported. Someone with two hundred
      shortcuts on their desktop must not be handed two hundred lines saying
      "not an editor" -- a diagnostic nobody reads to the end is a diagnostic
      that hides its own findings.
    #>
    param([string[]]$ShimDirs = (Get-CtxShimDirs))

    $executables = @(Get-CtxEditorFacts | ForEach-Object {
            $chemin = if ($_.Exe) { $_.Exe } else { $_.Cli }
            if ($chemin) { [System.IO.Path]::GetFileName($chemin) }
            # bin/code.cmd sits next to Code.exe one level up; a shortcut points
            # at the .exe, never at the launcher, so both names are needed.
            if ($_.Root) {
                Get-ChildItem -LiteralPath $_.Root -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.BaseName -notmatch '(?i)unins|elevate|crash|update' } |
                    ForEach-Object { $_.Name }
                }
            }) | Where-Object { $_ } | Select-Object -Unique

        if (-not $executables) { return }

        # Get-CtxShimDirs rend TOUS les noms du meme dossier -- celui du module et
        # le chemin stable derriere la jonction. Un raccourci peut nommer l'un ou
        # l'autre, et n'en reconnaitre qu'un rendait PROBLEME sur du correct.
        $nosDossiers = @($ShimDirs | Where-Object { $_ })

        $vus = @{}
        $verdicts = foreach ($raccourci in Get-CtxShortcutFacts) {
            # Le meme raccourci vit souvent sur le Bureau ET au menu Demarrer. Le
            # compter deux fois transforme un constat en avalanche.
            $empreinte = "$($raccourci.Target)|$($raccourci.Arguments)".ToLowerInvariant()
            if ($vus.ContainsKey($empreinte)) { continue }
            $vus[$empreinte] = $true

            $cible = if ($raccourci.Dossier) { $raccourci.Dossier } else { '' }
            $contexte = ''
            if ($cible) {
                $manifeste = Resolve-DevContextForPath -Path $cible
                if ($manifeste) { $contexte = Get-CtxProp $manifeste 'name' }
            }

            $verdict = Test-CtxDoctorRaccourci -Nom $raccourci.Nom -Target $raccourci.Target `
                -Arguments $raccourci.Arguments -Contexte $contexte `
                -EditeurExecutables $executables -ShimDirs $nosDossiers

            # Un raccourci sans rapport ne rend RIEN : plus de filtre sur un
            # libelle, qui cessait de matcher des que la sortie changeait de
            # langue.
            if ($verdict) { $verdict }
        }

        # Les raccourcis SANS dossier sont, pour l'essentiel, les entrees que
        # l'editeur a lui-meme posees au menu Demarrer. Tout le monde en a, elles ne
        # sont pas une trouvaille, et les lister une par une enterre les vraies sous
        # le bruit. Une ligne, un decompte : le signal reste, l'avalanche disparait.
        $sansDossier = @($verdicts | Where-Object { $_.Verdict -eq 'ATTENTION' })
        foreach ($v in $verdicts) { if ($v.Verdict -ne 'ATTENTION') { $v } }

        if ($sansDossier.Count) {
            $noms = ($sansDossier | Select-Object -ExpandProperty Sujet -Unique | Sort-Object) -join ', '
            # Sujet reste un IDENTIFIANT stable, jamais traduit : c'est la
            # colonne par laquelle `ctx doctor -Json` est filtre par un agent ou
            # une CI, et une cle qui change avec la langue du poste ne serait
            # plus une cle. Detail et Correctif, eux, s'adressent a un humain.
            New-CtxCheck -Domaine $script:CtxDomaineRaccourci -Sujet 'lanceurs simples' -Verdict 'INFO' `
                -Detail (T 'rac.doc.regroupes' $sansDossier.Count $noms) `
                -Correctif 'ctx-shortcut -Path <projet>'
        }
    }

    # ---------------------------------------------------------------------------
    # Writing a correct one
    # ---------------------------------------------------------------------------

    function New-DevShortcut {
        <#
    .SYNOPSIS
        Writes a desktop shortcut that opens a project in its own context.

    .DESCRIPTION
        The shortcut targets the editor by NAME, through the shim, and never by
        absolute path. That is the whole point: a shortcut carrying a hard-coded
        path to Code.exe cannot be corrected by anything DevContext does later,
        while one going through the shim picks up every improvement -- and keeps
        working when the editor updates its install directory.

        Refuses to run when the folder belongs to no context. A shortcut that
        isolates nothing is exactly the shortcut this exists to replace, and
        writing one "for convenience" would put the bug back under our own name.

    .PARAMETER Path
        The project folder. Aim at the PROJECT, never at the context root:
        opening C:\Work\Apps makes the language server look for node_modules
        there, where there is none.

    .PARAMETER Editor
        Command name of the editor, as `ctx-editors` lists it. Defaults to the
        first one found that can be isolated.

    .PARAMETER Destination
        Folder to write into. Defaults to the desktop.

    .EXAMPLE
        ctx-shortcut -Path C:\Work\Clients\acme\site
    #>
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory, Position = 0)][string]$Path,
            [string]$Editor,
            [string]$Destination = ([Environment]::GetFolderPath('Desktop')),
            [string]$Name,
            [switch]$Force
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw (T 'rac.dossierAbsent' $Path)
        }
        $projet = (Resolve-Path -LiteralPath $Path).Path

        $manifeste = Resolve-DevContextForPath -Path $projet
        if (-not $manifeste) {
            throw (T 'rac.horsContexte' $projet)
        }
        $contexte = Get-CtxProp $manifeste 'name'

        $editeurs = @(Get-CtxEditorFacts | Where-Object { $_.Cli })
        if ($Editor) { $editeurs = @($editeurs | Where-Object Name -eq $Editor) }
        $choisi = $editeurs | Select-Object -First 1
        if (-not $choisi) {
            throw (T 'rac.aucunEditeur' $(if ($Editor) { T 'rac.sousLeNom' $Editor } else { '' }))
        }

        # Le raccourci vise le LANCEUR, pas le shim.
        #
        # Le shim est synchrone, et il le doit : `code --wait COMMIT_EDITMSG` est
        # l'editeur de git. Un raccourci a besoin de l'inverse -- le lanceur detache
        # l'editeur via `start`, sinon le processus appelant survit toute la session
        # de travail. Deux besoins opposes, deux chemins, la meme decision de
        # contexte derriere.
        $lanceur = Join-Path (Split-Path $PSScriptRoot -Parent) 'lancer-editeur.ps1'
        if (-not (Test-Path -LiteralPath $lanceur)) {
            throw (T 'rac.lanceurAbsent' $lanceur)
        }

        $pwsh = (Get-Process -Id $PID).Path
        if (-not $pwsh) { $pwsh = 'pwsh.exe' }

        if (-not $Name) { $Name = '{0} - {1}' -f $choisi.Label, (Split-Path $projet -Leaf) }
        $fichier = Join-Path $Destination "$Name.lnk"
        if ((Test-Path -LiteralPath $fichier) -and -not $Force) {
            throw (T 'rac.existeDeja' $fichier)
        }

        if (-not $PSCmdlet.ShouldProcess($fichier, "ecrire un raccourci vers $projet ($contexte)")) { return }

        $shell = New-Object -ComObject WScript.Shell
        try {
            $raccourci = $shell.CreateShortcut($fichier)
            $raccourci.TargetPath = $pwsh
            # Pas de -Context : le lanceur le deduit du dossier. Un contexte fige
            # dans un raccourci devient faux le jour ou le projet demenage, et
            # personne ne relit un raccourci.
            $raccourci.Arguments = '-NoLogo -ExecutionPolicy Bypass -File "{0}" -Path "{1}" -Editor {2}' -f $lanceur, $projet, $choisi.Name
            $raccourci.WorkingDirectory = $projet
            $raccourci.Description = "DevContext : $projet (contexte $contexte)"
            # L'executable est deja resolu ailleurs pour lancer l'editeur
            # detache : le raccourci reutilise cette reponse au lieu d'en
            # fabriquer une deuxieme, qui divergerait au premier editeur range
            # autrement. Un raccourci sans icone porte celle de pwsh et se perd
            # au milieu de ceux qu'il remplace -- assez pour ne pas etre clique.
            $raccourci.IconLocation = Get-CtxShortcutIcon (Find-CtxEditorExecutable -Editor $choisi)
            $raccourci.Save()
        }
        finally {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }

        Write-Host ''
        Write-Host "  $(T 'rac.ecrit' $fichier)" -ForegroundColor Green
        Write-Host "    $(T 'rac.projet' $projet)"
        Write-Host "    $(T 'rac.contexte' $contexte)"
        Write-Host "    $(T 'rac.editeur' $choisi.Label)" -ForegroundColor DarkGray
        Write-Host ''
    }
