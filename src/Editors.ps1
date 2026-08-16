# ---------------------------------------------------------------------------
# Editors -- discovering them, measuring them, and isolating them
# ---------------------------------------------------------------------------
#
# THE PROBLEM
#
# An editor stores its sign-ins per profile directory. VS Code encrypts them
# with DPAPI into state.vscdb inside --user-data-dir; every VS Code descendant
# does the same. So one profile directory per context means independent GitHub,
# Copilot and marketplace sessions, live at the same time -- and no profile
# directory means they all share one, which is why signing into GitHub for a
# client project signs you out of your own.
#
# The module already knew this: Open-DevCode has passed --user-data-dir since
# August 2026. What it did not do is survive a launcher it did not write. A
# shortcut created by hand, `code .` typed in a terminal, "Open with" from the
# file explorer, an npm script, an agent -- none of those go through
# Open-DevCode, and all of them land on the shared profile.
#
# WHY THIS IS DISCOVERY AND NOT A LIST
#
# The first draft of this file was a table: name, executable, flags. It was
# wrong within the hour, on this very machine.
#
#   - Cursor ships resources/app/codeBin/code.cmd. A table keyed on the name
#     `code` would have isolated Cursor's profile and called it VS Code.
#   - Antigravity accepts --user-data-dir but has no --extensions-dir and no
#     --list-extensions at all. "It is a VS Code fork, therefore it takes the
#     VS Code flags" is exactly the kind of inference that produces a command
#     line the editor silently ignores.
#
# And a table is keyed on ONE machine. Someone else has Positron, or VSCodium,
# or a build of Cursor from a path we never guessed. So: the names below are
# search HINTS, never a truth table. What an editor supports is measured, and
# what cannot be measured is reported as unmeasured rather than assumed.
#
# WHY THE PROBE NEVER LAUNCHES A GUI
#
# Recorded on 15 Aug 2026, and the reason Test-CtxEditorCapabilities is built
# the way it is. Probing Antigravity by running its .exe with CLI flags did not
# print a version -- it opened the editor, which then relaunched itself after an
# update and threw "EPIPE: broken pipe" in a loop, because the console that
# started it had gone. A diagnostic that opens windows on someone's machine, or
# leaves an application crashing behind it, is not a diagnostic.
#
# So the probe runs a binary only when the install layout proves a command-line
# entry point exists -- a bin/<name>.cmd, the signature of the VS Code family.
# Otherwise it reads the application's own argument surface from disk and says
# so. Declared is weaker than measured, and the difference is reported, never
# smoothed over.

# ---------------------------------------------------------------------------
# Search hints
# ---------------------------------------------------------------------------
#
# Command name, human label, and the profile sub-directory inside the context.
#
# `code` maps to 'vscode' rather than 'code' because Open-DevCode has written
# there since August 2026 and real sign-ins live in it. Renaming the directory
# to be tidier would log every existing user out of every context at once --
# the precise failure this module exists to prevent, caused by the fix for it.

$script:EditorHints = @(
    [pscustomobject]@{ Name = 'code';          Label = 'Visual Studio Code'; Profile = 'vscode' }
    [pscustomobject]@{ Name = 'code-insiders'; Label = 'VS Code Insiders';   Profile = 'vscode-insiders' }
    [pscustomobject]@{ Name = 'codium';        Label = 'VSCodium';           Profile = 'vscodium' }
    [pscustomobject]@{ Name = 'cursor';        Label = 'Cursor';             Profile = 'cursor' }
    [pscustomobject]@{ Name = 'windsurf';      Label = 'Windsurf';           Profile = 'windsurf' }
    [pscustomobject]@{ Name = 'antigravity';   Label = 'Antigravity';        Profile = 'antigravity' }
    [pscustomobject]@{ Name = 'trae';          Label = 'Trae';               Profile = 'trae' }
    [pscustomobject]@{ Name = 'positron';      Label = 'Positron';           Profile = 'positron' }
    [pscustomobject]@{ Name = 'kiro';          Label = 'Kiro';               Profile = 'kiro' }
)

# The flags this module knows how to isolate with. Both belong to the VS Code
# command line and are inherited by its descendants; an editor from another
# family supports neither, which the probe reports rather than guesses.
$script:EditorIsolationFlags = @('--user-data-dir', '--extensions-dir')

function Get-CtxEditorHints {
    <#
      The built-in hints, plus anything the user declared.

      Declared editors come first: someone who took the trouble to name their
      own build means it to win over a hint that happens to share the name.
    #>
    param([string]$ContextRoot = $script:CtxRoot)

    $declared = @()
    $file = [System.IO.Path]::Combine($ContextRoot, 'editors.json')
    if (Test-Path -LiteralPath $file) {
        try {
            $raw = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($e in @($raw)) {
                $name = Get-CtxProp $e 'name'
                if (-not $name) { continue }
                $declared += [pscustomobject]@{
                    Name    = $name
                    Label   = Get-CtxProp $e 'label' $name
                    Profile = Get-CtxProp $e 'profile' $name
                    Command = Get-CtxProp $e 'command'
                }
            }
        }
        catch {
            # An unreadable file must not take the built-in hints down with it.
            Write-Verbose "editors.json illisible : $($_.Exception.Message)"
        }
    }

    $seen = @{}
    foreach ($e in @($declared) + @($script:EditorHints)) {
        $key = $e.Name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $e
    }
}

# ---------------------------------------------------------------------------
# Discovery -- looking, never running
# ---------------------------------------------------------------------------

function Get-CtxEditorInstallRoots {
    <#
      Where editors of this family install themselves, per platform.

      Get-Command already covers anything on PATH, which is the common case.
      This exists for the rest: Antigravity installs no CLI launcher at all, so
      PATH knows nothing about it and only the install directory does.
    #>
    $roots = @()
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $roots += Join-Path $env:LOCALAPPDATA 'Programs'
        $roots += $env:ProgramFiles
        $roots += ${env:ProgramFiles(x86)}
    }
    elseif ($IsMacOS) { $roots += '/Applications', (Join-Path $HOME 'Applications') }
    else              { $roots += '/usr/share', '/opt', (Join-Path $HOME '.local/share') }

    $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}

function Find-CtxEditorCli {
    <#
      The command-line entry point, and it must not be one of our own shims.

      Same exclusion as the supabase shim, for the same reason: once shims sit
      first in PATH, resolving a name by PATH finds OURSELVES, and an editor
      shim that delegates to an editor shim never reaches an editor.

      Excluded through Test-CtxDossierEstShimDevContext, never against a single
      path. Comparing one name is what broke every desktop shortcut on
      16 Aug 2026: PATH named the junction, this function named the module, and
      the two strings differ though the folder is the same one. Open-DevCode then
      took our own shim for the editor CLI, found no Code.exe above it, and fell
      back to its SYNCHRONOUS branch -- so the launcher window stayed open for
      the whole editing session.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Dossiers = (Get-CtxShimDirs)
    )

    Get-Command $Name -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object {
            -not (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $_.Source -Parent) -Dossiers $Dossiers)
        } |
        Select-Object -First 1 -ExpandProperty Source
}

function Find-CtxEditorInstall {
    <#
      An installation directory carrying this editor, found by layout.

      Looks for <root>/<something>/bin/<name>.cmd first -- the VS Code family
      signature, and the only shape where running the binary is safe -- then
      falls back to a bare <root>/<something>/<Name>.exe.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Roots = (Get-CtxEditorInstallRoots)
    )

    foreach ($root in $Roots) {
        $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -replace '[\s_-]', '' -match ($Name -replace '[\s_-]', '') }

        foreach ($d in $dirs) {
            foreach ($candidate in @(
                    (Join-Path $d.FullName "bin/$Name.cmd"),
                    (Join-Path $d.FullName "resources/app/bin/$Name.cmd"),
                    (Join-Path $d.FullName "bin/$Name"))) {
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return [pscustomobject]@{ Cli = $candidate; Exe = $null; Root = $d.FullName }
                }
            }

            $exe = Get-ChildItem -LiteralPath $d.FullName -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -replace '[\s_-]', '' -eq ($Name -replace '[\s_-]', '') } |
                Select-Object -First 1
            if ($exe) {
                return [pscustomobject]@{ Cli = $null; Exe = $exe.FullName; Root = $d.FullName }
            }
        }
    }
}

function Find-CtxEditorExecutable {
    <#
      The GUI executable behind a command-line launcher.

      Needed because launching detached goes through `start <exe>`, never
      through the .cmd -- the .cmd holds the calling console open for the whole
      editing session, which is fine in a terminal and wrong for a shortcut.

      Walks UP from the launcher rather than assuming a depth. VS Code puts
      bin/code.cmd two levels under Code.exe; Cursor puts
      resources/app/bin/cursor.cmd four levels under Cursor.exe. A fixed
      "two levels up" is right for exactly one editor and quietly wrong for the
      next -- which is how a table becomes a bug.
    #>
    param(
        [Parameter(Mandatory)]$Editor,
        [int]$MaxDepth = 5
    )

    if ($Editor.Exe -and (Test-Path -LiteralPath $Editor.Exe)) { return $Editor.Exe }
    if (-not $Editor.Cli) { return }

    $cible = ($Editor.Name -replace '[\s_-]', '')
    $dossier = Split-Path $Editor.Cli -Parent

    for ($i = 0; $i -lt $MaxDepth -and $dossier; $i++) {
        $exe = Get-ChildItem -LiteralPath $dossier -Filter '*.exe' -File -ErrorAction SilentlyContinue |
            Where-Object { ($_.BaseName -replace '[\s_-]', '') -eq $cible } |
            Select-Object -First 1
        if ($exe) { return $exe.FullName }
        $parent = Split-Path $dossier -Parent
        if ($parent -eq $dossier) { break }
        $dossier = $parent
    }
}

function Get-CtxEditorFacts {
    <#
      Every editor found on this machine, with how it was found.

      Runs nothing. The verdict on what each one supports is a separate step,
      because gathering that opens windows is not gathering.
    #>
    param([string]$ContextRoot = $script:CtxRoot)

    foreach ($hint in Get-CtxEditorHints -ContextRoot $ContextRoot) {
        $cli = $null
        $exe = $null
        $root = $null

        $declared = Get-CtxProp $hint 'Command'
        if ($declared -and (Test-Path -LiteralPath $declared)) {
            $cli = $declared
            $root = Split-Path $declared -Parent
        }
        else {
            $cli = Find-CtxEditorCli -Name $hint.Name
            if ($cli) { $root = Split-Path (Split-Path $cli -Parent) -Parent }
            else {
                $found = Find-CtxEditorInstall -Name $hint.Name
                if ($found) { $cli = $found.Cli; $exe = $found.Exe; $root = $found.Root }
            }
        }

        if (-not $cli -and -not $exe) { continue }

        [pscustomobject]@{
            PSTypeName = 'DevContext.Editor'
            Name       = $hint.Name
            Label      = $hint.Label
            Profile    = $hint.Profile
            Cli        = $cli
            Exe        = $exe
            Root       = $root
        }
    }
}

# ---------------------------------------------------------------------------
# Capabilities -- measured when it is safe, read when it is not
# ---------------------------------------------------------------------------

function Test-CtxEditorProbeResult {
    <#
      PURE. Turns a probe's observations into a capability verdict.

      Split out so the interesting half is testable without an editor
      installed, and so the rule -- a flag counts as supported only when the
      directory it names actually appeared -- is stated in one place.

      Exit code alone proves nothing. Every editor in this family accepts an
      unknown flag and exits 0; Antigravity did precisely that with
      --extensions-dir. Only the side effect on disk is evidence.
    #>
    param(
        [int]$ExitCode = 0,
        [bool]$ProfileCreated = $false,
        [bool]$ExtensionsCreated = $false
    )

    [pscustomobject]@{
        UserDataDir   = $ProfileCreated
        ExtensionsDir = $ExtensionsCreated
        Method        = 'measured'
        ExitCode      = $ExitCode
    }
}

function Test-CtxEditorDeclaredFlags {
    <#
      PURE. What an application's own files say it accepts.

      Second best, and labelled as such. A flag present in the binary is
      evidence it is parsed; it is not evidence it does what we want with it.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Content)

    [pscustomobject]@{
        UserDataDir   = [bool]($Content -and $Content.Contains('user-data-dir'))
        ExtensionsDir = [bool]($Content -and $Content.Contains('extensions-dir'))
        Method        = 'declared'
        ExitCode      = $null
    }
}

function Read-CtxEditorArgvSurface {
    <#
      The literal strings of an application bundle, for a flag lookup.

      An .asar is a concatenation with a JSON header -- reading it as text is
      crude and entirely sufficient to answer "does this string occur". Capped,
      because some bundles are hundreds of megabytes and this runs inside a
      diagnostic somebody is waiting on.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$MaxBytes = 64MB
    )

    $candidates = @(
        Join-Path $Root 'resources/app.asar'
        Join-Path $Root 'resources/app/out/vs/code/node/cli.js'
        Join-Path $Root 'resources/app/package.json'
    )

    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c -PathType Leaf)) { continue }
        try {
            $info = Get-Item -LiteralPath $c
            if ($info.Length -gt $MaxBytes) { continue }
            return [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($c))
        }
        catch { continue }
    }
}

function Test-CtxEditorCapabilities {
    <#
      What this editor lets us isolate -- measured if that is safe, read if not.

      SAFE means: a bin/<name>.cmd exists. That launcher is the VS Code family's
      command-line front end; it parses arguments, does its work and exits. An
      .exe with no such launcher is a GUI, and running one to ask it a question
      opens a window on someone's screen -- see the header of this file for the
      afternoon that established the rule.
    #>
    param(
        [Parameter(Mandatory)]$Editor,
        [string]$ScratchRoot = ([System.IO.Path]::GetTempPath())
    )

    if ($Editor.Cli) {
        $stem = Join-Path $ScratchRoot ('devctx-probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profileDir = "$stem-profile"
        $extDir = "$stem-ext"
        try {
            $null = & $Editor.Cli --user-data-dir $profileDir --extensions-dir $extDir --list-extensions 2>&1
            $code = $LASTEXITCODE
            $result = Test-CtxEditorProbeResult -ExitCode $code `
                -ProfileCreated (Test-Path -LiteralPath $profileDir) `
                -ExtensionsCreated (Test-Path -LiteralPath $extDir)
        }
        catch {
            $result = [pscustomobject]@{
                UserDataDir = $false; ExtensionsDir = $false; Method = 'failed'; ExitCode = $null
            }
        }
        finally {
            foreach ($d in $profileDir, $extDir) {
                if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        return $result
    }

    $surface = if ($Editor.Root) { Read-CtxEditorArgvSurface -Root $Editor.Root }
    Test-CtxEditorDeclaredFlags -Content $surface
}

# ---------------------------------------------------------------------------
# The decision -- pure, and the heart of the shim
# ---------------------------------------------------------------------------

function Resolve-CtxEditorArguments {
    <#
      PURE. The command line to run, given what the editor supports.

      Injects only flags the probe established. Passing --extensions-dir to an
      editor that ignores it is not harmless: it reads as isolation to whoever
      wrote the shortcut, while the extensions stay shared.

      Order matters. Flags go BEFORE the caller's arguments, because a path
      argument ends the option list for some launchers. The caller's own
      arguments are never rewritten, reordered or deduplicated: --wait, --diff,
      -g file:line and --goto must arrive exactly as typed.

      A caller who passed --user-data-dir themselves wins. They said something
      explicit about where the profile goes, and second-guessing that would make
      this wrapper the thing that breaks a deliberate command.
    #>
    param(
        [Parameter(Mandatory)]$Capabilities,
        [Parameter(Mandatory)][string]$ContextDir,
        [Parameter(Mandatory)][string]$ProfileName,
        [string[]]$Arguments = @()
    )

    $injected = @()
    $already = @($Arguments | Where-Object { $_ } | ForEach-Object { "$_".Split('=')[0].ToLowerInvariant() })

    # [IO.Path]::Combine et NON Join-Path.
    #
    # Join-Path est un cmdlet de FOURNISSEUR : il resout le lecteur, et leve
    # « Cannot find drive » quand celui-ci n'est pas monte. Dans une fonction
    # pure sans -ErrorAction Stop, cela ne leve pas -- cela rend une chaine
    # VIDE, et la commande partait avec « --user-data-dir --extensions-dir . »,
    # ou le flag suivant est lu comme la valeur du precedent. Silencieux, donc.
    #
    # Mesure par la CI le 15 aout 2026 : les tests passaient ici, ou F: existe,
    # et echouaient sur un agent ou il n'existe pas. Exactement la classe de
    # defaut qui n'apparait que chez quelqu'un d'autre.
    if ((Get-CtxProp $Capabilities 'UserDataDir') -and '--user-data-dir' -notin $already) {
        $injected += '--user-data-dir', [System.IO.Path]::Combine($ContextDir, $ProfileName)
    }
    if ((Get-CtxProp $Capabilities 'ExtensionsDir') -and '--extensions-dir' -notin $already) {
        $injected += '--extensions-dir', [System.IO.Path]::Combine($ContextDir, $ProfileName + '-ext')
    }

    @($injected) + @($Arguments)
}

function Resolve-CtxEditorTargetPath {
    <#
      PURE. Which folder decides the context, given an editor's arguments.

      `code .`, `code C:\work\thing`, `code src/main.ts`, `code --wait
      COMMIT_EDITMSG`, `code --diff a b`, `code -g file.ts:42` -- the context
      comes from the FILE BEING OPENED, not from where the terminal happens to
      sit. Opening a client project from a personal folder must load the client
      identity, or the wrapper reproduces the bug it exists to fix.

      Values belonging to a preceding flag are skipped: in `--log trace src/`
      the target is src/, not trace. Anything unrecognised falls back to the
      working directory, which is the behaviour before this file existed.

      -Classify is the ONLY contact with the filesystem, and it answers
      'file' / 'directory' / 'absent' in one call. An earlier version injected
      an existence test but kept its own Test-Path -PathType Leaf: a test could
      then describe a path that exists, and the function would still ask the
      real disk whether it was a file. Half-injected is not injected.
    #>
    param(
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [scriptblock]$Classify = {
            param($p)
            if (-not (Test-Path -LiteralPath $p)) { return 'absent' }
            if (Test-Path -LiteralPath $p -PathType Leaf) { return 'file' }
            'directory'
        }
    )

    # Flags of the VS Code family that consume the next argument. An unknown
    # flag is assumed NOT to, because treating a path as a flag's value loses
    # the target entirely, while the reverse merely costs one extra candidate.
    $consumers = @(
        '--user-data-dir', '--extensions-dir', '--extension-development-path',
        '--extensions-download-dir', '--install-extension', '--uninstall-extension',
        '--locale', '--log', '--sync', '--profile', '--remote', '--folder-uri',
        '--file-uri', '--prof-startup-prefix', '--crash-reporter-directory'
    )

    $skipNext = $false
    foreach ($raw in @($Arguments)) {
        $arg = "$raw"
        if ($skipNext) { $skipNext = $false; continue }
        if ($arg.StartsWith('-')) {
            if ($arg -notmatch '=' -and $arg.ToLowerInvariant() -in $consumers) { $skipNext = $true }
            continue
        }

        # -g and --goto append :line:column, which is not part of the path.
        $candidate = $arg -replace '(?<=.):\d+(:\d+)?$', ''
        if (-not $candidate) { continue }

        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            # Combine, pas Join-Path : voir Resolve-CtxEditorArguments.
            $candidate = [System.IO.Path]::Combine($WorkingDirectory, $candidate)
        }

        # if/else and not switch: `continue` inside a switch continues the
        # ENCLOSING loop in PowerShell, which is right here and wrong the day
        # somebody moves this block. Not worth the reader's doubt.
        $kind = & $Classify $candidate
        # A file names its folder; the folder is what owns an identity.
        if ($kind -eq 'file')      { return Get-CtxNormalizedPath (Split-Path $candidate -Parent) }
        if ($kind -eq 'directory') { return Get-CtxNormalizedPath $candidate }
    }

    $WorkingDirectory
}

function Get-CtxNormalizedPath {
    <#
      PURE. Collapses '.' and '..' without asking the disk.

      `code .` yields 'F:\projet\.', which every prefix comparison in this
      module then has to cope with. GetFullPath does the collapsing and is
      purely textual -- Resolve-Path would fail on a path that does not exist,
      and a folder that does not exist is a case we still want an answer for.
    #>
    param([Parameter(Mandatory)][string]$Chemin)
    try { [System.IO.Path]::GetFullPath($Chemin) } catch { $Chemin }
}

# ---------------------------------------------------------------------------
# Cache -- so the probe runs once, not on every launch
# ---------------------------------------------------------------------------
#
# Keyed on the executable's path AND its last write time. An editor that
# updates itself gets re-probed; one that has not changed does not pay for a
# process launch every time somebody types `code .`.

function Get-CtxEditorCachePath {
    param([string]$ContextRoot = $script:CtxRoot)
    [System.IO.Path]::Combine($ContextRoot, 'editors.cache.json')
}

function Get-CtxEditorCacheKey {
    param([Parameter(Mandatory)]$Editor)
    $target = if ($Editor.Cli) { $Editor.Cli } else { $Editor.Exe }
    $stamp = ''
    if ($target -and (Test-Path -LiteralPath $target)) {
        $stamp = (Get-Item -LiteralPath $target).LastWriteTimeUtc.ToString('o')
    }
    '{0}|{1}|{2}' -f $Editor.Name, $target, $stamp
}

function Get-CtxEditorCapabilitiesCached {
    param(
        [Parameter(Mandatory)]$Editor,
        [string]$ContextRoot = $script:CtxRoot,
        [switch]$Refresh
    )

    $path = Get-CtxEditorCachePath -ContextRoot $ContextRoot
    $key = Get-CtxEditorCacheKey -Editor $Editor
    $cache = @{}

    if (-not $Refresh -and (Test-Path -LiteralPath $path)) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($raw -is [System.Collections.IDictionary]) { $cache = $raw }
        }
        catch { $cache = @{} }

        if ($cache.ContainsKey($key)) {
            $hit = $cache[$key]
            return [pscustomobject]@{
                UserDataDir   = [bool]$hit['UserDataDir']
                ExtensionsDir = [bool]$hit['ExtensionsDir']
                Method        = [string]$hit['Method']
                ExitCode      = $hit['ExitCode']
            }
        }
    }

    $caps = Test-CtxEditorCapabilities -Editor $Editor

    try {
        if (-not (Test-Path -LiteralPath $ContextRoot)) {
            New-Item -ItemType Directory -Path $ContextRoot -Force -ErrorAction Stop | Out-Null
        }
        $cache[$key] = @{
            UserDataDir = $caps.UserDataDir; ExtensionsDir = $caps.ExtensionsDir
            Method      = $caps.Method;      ExitCode      = $caps.ExitCode
        }
        $cache | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # A cache that cannot be written costs a probe next time. Nothing more.
        Write-Verbose "cache editeurs non ecrit : $($_.Exception.Message)"
    }

    $caps
}

# ---------------------------------------------------------------------------
# Public surface
# ---------------------------------------------------------------------------

function Get-DevEditorList {
    <#
    .SYNOPSIS
        Editors found on this machine, and whether each can be isolated.

    .DESCRIPTION
        Answers the question a shortcut cannot: if I open this project with
        this editor, does it get its own sign-ins, or does it share yours?

        Isolation is measured where a command-line entry point exists, and read
        from the application's own files where it does not. The two are
        reported differently on purpose -- see Methode.

    .PARAMETER Refresh
        Ignore the cache and probe again. Use after installing or updating an
        editor, though a changed timestamp already invalidates its entry.

    .EXAMPLE
        ctx-editors
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    foreach ($editor in Get-CtxEditorFacts) {
        $caps = Get-CtxEditorCapabilitiesCached -Editor $editor -Refresh:$Refresh
        # Isole et ExtensionsIsolees sont les champs sur lesquels le CODE decide.
        # Profil et Extensions sont ceux que l'HUMAIN lit, et ils sont traduits.
        #
        # Les deux existent parce que confondre les deux est un bug reel : le
        # doctor comparait `$e.Profil -eq 'isole'`, un litteral francais. Des que
        # la sortie est passee en anglais, la comparaison a echoue et CHAQUE
        # editeur a ete rapporte comme non isole -- un faux avertissement, en
        # anglais seulement, donc invisible sur la machine qui l'a introduit.
        # Une valeur affichee ne doit jamais servir de valeur de decision.
        [pscustomobject]@{
            PSTypeName        = 'DevContext.EditorStatus'
            Editeur           = $editor.Label
            Commande          = $editor.Name
            Isole             = [bool]$caps.UserDataDir
            ExtensionsIsolees = [bool]$caps.ExtensionsDir
            Profil     = if ($caps.UserDataDir) { T 'editeur.profil.isole' } else { T 'editeur.profil.partage' }
            Extensions = if ($caps.ExtensionsDir) { T 'editeur.ext.isolees' } else { T 'editeur.ext.partagees' }
            Methode    = $caps.Method
            Chemin     = if ($editor.Cli) { $editor.Cli } else { $editor.Exe }
        }
    }
}
