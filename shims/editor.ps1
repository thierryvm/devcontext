#Requires -Version 7
<#
    Context isolation for code editors, from any launcher.

    WHY THIS EXISTS

    Open-DevCode already passes --user-data-dir, so an editor opened through it
    gets its own sign-ins. The trouble is everything that does NOT go through
    it: a shortcut somebody made by hand, `code .` typed in a terminal, "Open
    with" from the file explorer, an npm script, an agent. All of those land on
    the shared profile, and a GitHub sign-in there logs you out everywhere else.

    Sitting in PATH is the only position every one of those callers passes
    through. Same reasoning, and the same three entry points, as the supabase
    guard next door.

    ONE SCRIPT, MANY EDITORS

    The editor's name arrives in DEVCTX_SHIM_EDITOR, set by the .cmd or the
    POSIX sibling that called us -- not as a parameter, because the argument
    stream belongs to the caller and must reach the editor untouched. `code
    --wait COMMIT_EDITMSG` is git's editor; anything that reorders, swallows or
    re-quotes an argument there breaks committing.

    CONTRACT

    Adds flags, never removes any, and delegates unchanged whenever it is not
    certain: no context owning the folder, no editor found, an unreadable
    module, an unexpected error. The behaviour without this shim is the
    behaviour when it hesitates -- which is also why the failure mode is
    "isolation you did not get" rather than "editor that will not start".

    Synchronous on purpose. Open-DevCode detaches through `start`, which is
    right for a shortcut and catastrophic here: git would see its editor return
    immediately and commit an empty message.

    Exit code is the editor's.

    DEVCTX_SHIM_TRACE=1 prints, on stderr, what was decided and why. "My editor
    opened on the wrong account" has no answer otherwise: the flags are injected
    where nobody can see them, and two contexts can be indistinguishable from
    the outside. stderr, so it never contaminates a caller parsing stdout --
    `code --list-extensions` is read by scripts.

    The trace names a context and prints paths. It never prints an environment
    variable, an argument of the command, or anything from the vault: a trace
    gets pasted into an issue.
#>

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$ShimDir = $PSScriptRoot
$Arguments = @($args)
$EditorName = $env:DEVCTX_SHIM_EDITOR
if (-not $EditorName) { $EditorName = 'code' }

# Meme garde-fou anti-boucle que shims/supabase.ps1, et meme raison : depuis que
# PATH designe une jonction vers le module, un meme dossier porte deux noms. Si
# les deux se retrouvent dans PATH, chaque shim ecarte le sien, trouve l'autre,
# et l'appelle sans fin.
#
# Le cas est plus visible ici que pour supabase : un editeur qui ne s'ouvre pas
# ne donne aucun message, et l'utilisateur reclique. Une erreur qui nomme la
# cause vaut mieux qu'une fenetre qui n'arrive jamais.
$Profondeur = 0
if ($env:DEVCTX_SHIM_DEPTH) { $Profondeur = [int]$env:DEVCTX_SHIM_DEPTH }
if ($Profondeur -ge 3) {
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine("  DevContext: shim loop detected for '$EditorName'.")
    [Console]::Error.WriteLine('  Two DevContext shim directories are probably both in PATH.')
    [Console]::Error.WriteLine('  Fix: pwsh -File installer-shims.ps1 -Verifier')
    [Console]::Error.WriteLine('')
    exit 1
}
$env:DEVCTX_SHIM_DEPTH = $Profondeur + 1

# --- delegation -------------------------------------------------------------

function Resolve-RealExe {
    # Duplicated from the module rather than imported, deliberately: this has to
    # work when the module is missing or broken, which is exactly when
    # delegating matters most.
    $here = $ShimDir.TrimEnd('\', '/')
    Get-Command $EditorName -CommandType Application -All -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path $_.Source -Parent).TrimEnd('\', '/') -ne $here } |
        Select-Object -First 1 -ExpandProperty Source
}

$RealExe = Resolve-RealExe

function Write-Trace {
    param([string]$Message)
    if ($env:DEVCTX_SHIM_TRACE) { [Console]::Error.WriteLine("  [devctx:$EditorName] $Message") }
}

function Invoke-Real {
    param([string[]]$Final = $Arguments, [string]$Motif = 'delegation nue')
    if (-not $RealExe) {
        Write-Error "$EditorName introuvable dans le PATH (hors shims)."
        exit 127
    }
    Write-Trace "$Motif -> $RealExe"
    & $RealExe @Final
    exit $LASTEXITCODE
}

# --- decide -----------------------------------------------------------------

$finalArguments = $Arguments

try {
    $module = Import-Module (Join-Path $PSScriptRoot '..' 'DevContext.psd1') -Force -PassThru -ErrorAction Stop

    # LE DOSSIER DECIDE, JAMAIS LA SESSION -- et ici le dossier est celui qu'on
    # OUVRE, pas celui d'ou l'on tape. Ouvrir un projet client depuis un dossier
    # perso doit charger l'identite client, sans quoi ce shim reproduit
    # exactement le bug qu'il existe pour corriger.
    $target = & $module { param($a, $w) Resolve-CtxEditorTargetPath -Arguments $a -WorkingDirectory $w } $Arguments $PWD.Path
    Write-Trace "cible : $target"

    $manifest = & $module { param($p) Resolve-DevContextForPath -Path $p } $target
    if (-not $manifest) { Invoke-Real -Motif 'aucun contexte ne possede ce dossier' }

    $contextName = & $module { param($m) Get-CtxProp $m 'name' } $manifest
    $contextDir = & $module { param($n) Get-CtxPath $n } $contextName

    $editor = & $module { param($n) Get-CtxEditorFacts | Where-Object Name -eq $n | Select-Object -First 1 } $EditorName
    if (-not $editor) { Invoke-Real -Motif "editeur '$EditorName' non reconnu" }

    $caps = & $module { param($e) Get-CtxEditorCapabilitiesCached -Editor $e } $editor
    Write-Trace "contexte : $contextName | profil isole : $($caps.UserDataDir) | extensions isolees : $($caps.ExtensionsDir) ($($caps.Method))"

    $finalArguments = & $module {
        param($c, $d, $p, $a) Resolve-CtxEditorArguments -Capabilities $c -ContextDir $d -ProfileName $p -Arguments $a
    } $caps $contextDir $editor.Profile $Arguments

    # L'environnement du contexte, pour le terminal integre et pour l'assistant
    # qui y tourne : sans GH_CONFIG_DIR, `gh` repart sur le dernier compte
    # connecte de la machine. C'est un BONUS -- l'isolation du profil, elle, est
    # deja acquise ci-dessus. Un coffre verrouille ne doit pas empecher
    # l'editeur de s'ouvrir.
    try { & $module { param($n) Use-DevContext -Name $n -NoCd } $contextName 6>$null | Out-Null }
    catch { Write-Trace "identite non chargee : $($_.Exception.Message)" }
}
catch {
    Write-Trace "erreur inattendue, delegation : $($_.Exception.Message)"
    Invoke-Real
}

Invoke-Real -Final $finalArguments -Motif 'lancement isole'
