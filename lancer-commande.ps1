#Requires -Version 7
<#
    What `ctx exec` runs in the CHILD process. Never invoked by hand.

    WHY A SEPARATE PROCESS

    The first `ctx exec` swapped the environment of its own process, ran the
    command, and restored it. An environment belongs to the PROCESS, and every
    runspace in it shares it: two `ctx exec` running in parallel handed each
    other the parent's bypass and token, and a script run that way executed
    inside the module's scope, where it could read the parent's environment
    snapshot and call private functions such as Get-CtxSecret. Measured by the
    security audit of 27 September 2026, and not fixable while the command
    shares the caller's process.

    So the module starts THIS script in a fresh `pwsh`, with an environment it
    built itself and handed to the process at creation. The caller's
    environment is never touched, not even for an instant.

    WHY THE ARGUMENTS DO NOT TRAVEL ON THE COMMAND LINE

    They did, after `-File`, and pwsh re-read them with its own parameter
    parser: '--title=fix(exec): x' reached the command in two pieces, and
    '--output=C:\x' became '--output=C' then '\x'. Measured by the second audit
    the same day. The module now hands the argument vector over in
    DEVCTX_EXEC_ARGV -- base64 of a JSON array, so no parser reads it -- and
    this script removes that variable from its own environment before running
    anything, so the command never inherits it.

    WHY THIS SCRIPT IS NOT RUN WITH -File

    It was, under `-ExecutionPolicy Bypass`, so that a signing policy could not
    refuse it. But a policy applies to the process, and this process then runs
    the command asked for: a script the user's policy would have blocked --
    unsigned, marked as downloaded -- ran anyway (Sourcery review of PR #55).
    The module now hands this file's path in DEVCTX_EXEC_LANCEUR and starts pwsh
    with a fixed bootstrap that reads it as a script block. This file runs as
    the module code it is, and the command it launches meets the policy that is
    configured -- the process scope stays empty.

    HOW THEY ARE PASSED ON

    Plain strings, splatted, arrive exactly as typed -- for a native program,
    and for a script or function that declares no parameters, which is what the
    gh, supabase and vercel shims are. A command that DOES declare parameters
    needs '-LiteralPath' to stay a parameter NAME, which a plain string never
    becomes. For those, the call is built as text, and only its SHAPE is text: a
    token shaped exactly like a parameter name goes in bare, and every other
    argument goes in as a reference to its slot in an array handed over as
    data -- `$argv[3]`, never the value itself. No argument ever becomes source
    code, so there is no quoting to get right, and a script block log records
    the references rather than the values.

    THE EXIT CODE

    A native command sets $LASTEXITCODE, and that code is returned unchanged. A
    cmdlet sets none, so a failure there is translated to 1, which is what
    `pwsh -Command` would return. 127 means that no command of that name exists
    in the child's environment, 125 that the hand-over itself is broken.

    Console messages stay pure ASCII and in English, like the shims: this
    process does not load the module, so it has neither the language tables
    nor anything it would need to use them.
#>

$encode = $env:DEVCTX_EXEC_ARGV
[Environment]::SetEnvironmentVariable('DEVCTX_EXEC_ARGV', [NullString]::Value)
# The path this script was read from, for the bootstrap only: nothing the
# command runs needs it.
[Environment]::SetEnvironmentVariable('DEVCTX_EXEC_LANCEUR', [NullString]::Value)

$tous = @()
try {
    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$encode))
    # System.Text.Json, never ConvertFrom-Json: the latter turns an ISO 8601 or
    # /Date(...)/ string into a DateTime by default, which [string] then prints
    # in the current culture -- '2026-01-01T00:00:00' arrived as
    # '01/01/2026 00:00:00', its 'Z' lost. Measured by the third audit on
    # 29 October 2026. An array read as strings interprets nothing.
    $tous = @([System.Text.Json.JsonSerializer]::Deserialize($json, [string[]], [System.Text.Json.JsonSerializerOptions]$null))
}
catch { $tous = @() }
if ($tous.Count -eq 0) {
    [Console]::Error.WriteLine('  ctx exec: no command reached the child process.')
    exit 125
}

$commande = $tous[0]
$reste = @()
if ($tous.Count -gt 1) { $reste = @($tous[1..($tous.Count - 1)]) }

# Escaped: Get-Command accepts wildcards, so 'Get-Dat*' would be "found" here
# and then fail at the call, returning 0.
$cible = Get-Command -Name ([WildcardPattern]::Escape($commande)) -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cible) {
    [Console]::Error.WriteLine("  ctx exec: command not found in the context's environment: '$commande'")
    exit 127
}
if ($cible.CommandType -eq 'Alias' -and $cible.ResolvedCommand) { $cible = $cible.ResolvedCommand }

# Does the target bind named parameters? For a SCRIPT the answer is read from
# its syntax tree, never from .Parameters: reading that property evaluates the
# script's dynamicparam block, which then ran twice for one call -- measured by
# the third audit. Cmdlets and built-in functions keep .Parameters.
$parametres = 0
if ($cible.CommandType -eq 'ExternalScript') {
    try {
        $ast = $cible.ScriptBlock.Ast
        if ($ast.DynamicParamBlock) { $parametres = 1 }
        elseif ($ast.ParamBlock -and ($ast.ParamBlock.Parameters.Count -gt 0 -or $ast.ParamBlock.Attributes.Count -gt 0)) { $parametres = 1 }
    }
    # A script that does not parse is left to fail at the call, with
    # PowerShell's own message.
    catch { $parametres = 0 }
}
elseif ($cible.CommandType -ne 'Application') {
    try { $parametres = @($cible.Parameters.Keys).Count } catch { $parametres = 0 }
}

# $? read right after the command itself, never after the block that wraps it:
# a script block that ran a failing cmdlet still reports success.
$etat = @{ Reussi = $true }
$global:LASTEXITCODE = 0
if ($parametres -eq 0) {
    & $cible @reste
    $etat.Reussi = $?
}
else {
    # Names no argument can name. A fixed `$__etat` was replaced by
    # `-ErrorVariable __etat`, the status assignment then failed, and a failing
    # cmdlet returned 0 -- the third audit again. A fresh GUID per run cannot
    # collide by accident, and the caller who could guess it owns the argv.
    $suffixe = [guid]::NewGuid().ToString('N')
    $vCible = "c$suffixe"
    $vEtat = "e$suffixe"
    $vArgv = "a$suffixe"

    # The VALUES never enter the text: each one is named by its index in an
    # array passed as data. The first version quoted them into single-quoted
    # literals; three audits found no escape from that quoting, but a reference
    # needs none, and an event log that records script blocks sees `$argv[3]`
    # instead of whatever the caller passed. Only the two shapes below are text,
    # and both are matched whole against a closed pattern.
    #
    # The attached form `-Name:value` reaches this script already split, as
    # '-Name:' followed by the value -- PowerShell split it at the caller. The
    # value is glued back onto its parameter, still by reference; passed as a
    # separate positional value it bound to the wrong parameter (Sourcery review
    # of PR #55). It is also the only way to hand a parameter a value that starts
    # with a dash: once in $args, a quoted '-x' and a bare -x are the same string.
    # A switch refuses the string 'True', which is what [string] made of the
    # boolean, so True and False after a colon go back to being booleans.
    $morceaux = for ($i = 0; $i -lt $reste.Count; $i++) {
        $a = $reste[$i]
        # \z et non $ : en .NET, $ accepte un saut de ligne final, qui entrait
        # dans le texte genere et coupait l'instruction -- un cmdlet en echec
        # rendait 0 (audit du 30 octobre 2026). -ceq : seul un vrai booleen
        # aplati donne exactement 'True' ou 'False' ; 'tRuE' reste du texte.
        if ($a -cmatch '^-[A-Za-z][A-Za-z0-9_]*:\z' -and $i + 1 -lt $reste.Count) {
            $i++
            if ($reste[$i] -ceq 'True') { $a + '$true' }
            elseif ($reste[$i] -ceq 'False') { $a + '$false' }
            else { $a + "`$$vArgv[$i]" }
        }
        elseif ($a -cmatch '^-[A-Za-z][A-Za-z0-9_]*\z') { $a }
        else { "`$$vArgv[$i]" }
    }
    $appel = [scriptblock]::Create("param(`$$vCible, `$$vEtat, `$$vArgv) & `$$vCible " + ($morceaux -join ' ') + "; `$$vEtat.Reussi = `$?")
    & $appel $cible $etat $reste
}

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not $etat.Reussi) { exit 1 }
exit 0
