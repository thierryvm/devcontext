# ---------------------------------------------------------------------------
# ctx exec -- une commande, sous le contexte du DOSSIER
# ---------------------------------------------------------------------------
#
# THE PROBLEM
#
# Two, and the second is the one that decided the design.
#
# The first: `work <ctx> -NoCd; <command>` works, and forgetting it is SILENT. A
# command typed without the prefix produces no signal at all -- it simply runs
# under whatever identity the shell happened to hold. `ctx exec` replaces "did
# I remember?" with an invariant that can be grepped in a transcript.
#
# The second, found on 25 August 2026 while answering an orchestrator: a child
# process INHERITS `DEVCTX_ALLOW_PROD`, this module's own documented bypass of
# the production guard. A human disarms the guard once, deliberately, in their
# session -- and everything launched from there carries the disarmed guard into
# folders that never consented to it. The incident this module exists to
# prevent, produced by the tool meant to prevent it.
#
# THE RULE
#
# The child's environment is BUILT, never copied from the parent and patched.
# Copy-then-patch always leaks the variable nobody thought of -- GITHUB_TOKEN
# outranks GH_CONFIG_DIR for gh, and nothing in this module sets it. So the
# child gets what a FRESH TERMINAL would get, plus `work <ctx>`:
#
#   1. the registry environment the way Windows composes it at logon: machine,
#      then the session's volatile values, then user -- Path being machine
#      THEN user;
#   2. from the parent, a CLOSED list of names that Windows computes rather
#      than stores, plus the ones describing the console -- never a credential,
#      never anything that steers identity or which code gets loaded;
#   3. the variables of the context that owns the FOLDER, and the root that
#      decided it;
#   4. minus the three bypasses, always, with no flag to keep them.
#
# The cost is stated rather than hidden: whatever the parent session added --
# an activated virtualenv, an `fnm env` Path, an exported NODE_ENV -- is not
# there. That is what "a fresh terminal" means, and it is the price of a
# guarantee that does not depend on what the caller happened to carry.
#
# A SEPARATE PROCESS, AND WHY THE FIRST VERSION WAS WRONG
#
# The first version ran the command in THIS process, with the environment
# swapped and restored in a `finally`. An environment belongs to the process
# and is shared by every runspace in it: two `ctx exec` in parallel handed each
# other the parent's bypass and token, and a script launched that way ran in
# the module's scope, able to read the parent's snapshot and call Get-CtxSecret.
# Measured by the security audit of 27 September 2026. The environment is now
# handed to a new `pwsh` at creation, through ProcessStartInfo, and this
# process's own is never written. See lancer-commande.ps1 for what the child
# does with it.
#
# Its output goes to the console the child inherits, not into the PowerShell
# pipeline: `$x = ctx exec ...` captures nothing. Across a process boundary --
# an agent's shell, `pwsh -c` -- the output is the process's stdout, as for any
# command.

# Ce qu'un enfant reprend du parent, et rien d'autre. Liste FERMEE.
#
# Ne figurent ici que des valeurs que Windows CALCULE a l'ouverture de session
# sans les ecrire dans le registre, et la description de la console. Tout ce
# qui designe l'utilisateur -- USERNAME, USERPROFILE, APPDATA, HOMEDRIVE -- vient
# de la cle Volatile Environment, que Windows remplit a l'ouverture de session,
# et non du parent : une session peut les avoir changees. HOME, que Windows ne
# pose jamais, n'y est pas : git y trouve ~/.gitconfig, donc les includeIf qui
# choisissent l'identite. PSModulePath non plus : il decide quel DevContext un
# pwsh enfant charge. Releves par l'audit du 27 septembre 2026.
$script:CtxExecHeritees = @(
    'SystemRoot', 'SystemDrive', 'COMPUTERNAME', 'SESSIONNAME',
    'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432',
    'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432',
    'ProgramData', 'ALLUSERSPROFILE', 'PUBLIC',
    # La console : l'enfant ecrit dans la meme que le parent.
    'TERM', 'COLORTERM', 'WT_SESSION', 'WT_PROFILE_ID', 'NO_COLOR', 'FORCE_COLOR', 'CI',
    # La langue dans laquelle l'enfant parle, s'il charge le module.
    'DEVCTX_LANG'
)

# Refus de `ctx exec` lui-meme, distincts de tout code d'un enfant ordinaire.
# Meme convention que `env`, `timeout` et `docker run` : 125 quand l'enveloppe
# refuse ou echoue, 127 quand la commande est introuvable (lancer-commande.ps1).
$script:CtxExecRefus = 125

function ConvertTo-CtxTableEnv {
    # [Environment]::GetEnvironmentVariables() rend une Hashtable .NET, SENSIBLE
    # a la casse. Les noms d'environnement Windows ne le sont pas : 'Path' et
    # 'PATH' sont la meme variable. Une table PowerShell l'est aussi.
    param([AllowNull()][System.Collections.IDictionary]$Source)
    $t = @{}
    if ($Source) { foreach ($k in $Source.Keys) { $t[[string]$k] = [string]$Source[$k] } }
    $t
}

function Get-CtxEnvironnementVolatile {
    <#
      HKCU\Volatile Environment : ce que Windows pose a l'ouverture de session
      -- USERNAME, USERPROFILE, APPDATA, LOCALAPPDATA, HOMEDRIVE, HOMEPATH --
      puis la sous-cle de CETTE session (SESSIONNAME, CLIENTNAME) -- et d'elle
      seule : il y en a une par session ouverte, et celle d'une session de
      bureau a distance n'a rien a faire ici.
    #>
    $t = @{}
    $cle = 'HKCU:\Volatile Environment'
    if (-not (Test-Path -LiteralPath $cle)) { return $t }
    $racine = Get-Item -LiteralPath $cle
    foreach ($n in $racine.GetValueNames()) { if ($n) { $t[$n] = [string]$racine.GetValue($n) } }
    $session = [System.IO.Path]::Combine($cle, [string](Get-Process -Id $PID).SessionId)
    if (Test-Path -LiteralPath $session) {
        $sous = Get-Item -LiteralPath $session
        foreach ($n in $sous.GetValueNames()) { if ($n) { $t[$n] = [string]$sous.GetValue($n) } }
    }
    $t
}

function Get-CtxEnvironnementDeBase {
    <#
      PURE. Ce qu'un terminal NEUF recevrait, avant tout contexte.

      Dans l'ordre ou Windows compose le bloc d'environnement a l'ouverture de
      session : les valeurs calculees (ici, prises au parent par liste fermee),
      puis le registre systeme, la cle Volatile, le registre utilisateur. Chaque
      source remplace la precedente, sauf Path, compose systeme PUIS
      utilisateur. C'est le PATH utilisateur qui porte les shims ; un Path pris
      au parent pourrait les avoir perdus, ou porter node_modules/.bin devant.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][hashtable]$Machine,
        [AllowNull()][hashtable]$Volatile,
        [AllowNull()][hashtable]$Utilisateur,
        [AllowNull()][hashtable]$Processus
    )

    $base = @{}
    if ($Processus) {
        foreach ($nom in $script:CtxExecHeritees) {
            if ($Processus.ContainsKey($nom) -and -not [string]::IsNullOrEmpty($Processus[$nom])) {
                $base[$nom] = $Processus[$nom]
            }
        }
    }
    foreach ($source in @($Machine, $Volatile)) {
        if ($source) { foreach ($k in $source.Keys) { $base[$k] = $source[$k] } }
    }
    if ($Utilisateur) {
        foreach ($k in $Utilisateur.Keys) {
            if ($k -eq 'Path' -and $base['Path']) {
                $base['Path'] = ($base['Path'].TrimEnd(';') + ';' + $Utilisateur[$k])
            }
            else { $base[$k] = $Utilisateur[$k] }
        }
    }
    $base
}

function Get-CtxEnvironnementExec {
    <#
      PURE. L'environnement complet de l'enfant : la base, les variables du
      contexte par-dessus -- $null retire -- puis les derogations retirees.

      Retirees EN DERNIER, et sans exception : ni le registre ni le contexte ne
      peuvent en faire passer une. Une derogation est un geste delibere dans UNE
      session ; en heriter n'est pas ce geste.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][hashtable]$Base,
        [Parameter(Mandatory)][AllowNull()][System.Collections.IDictionary]$Contexte
    )

    $resultat = @{}
    if ($Base) { foreach ($k in $Base.Keys) { $resultat[$k] = $Base[$k] } }
    if ($Contexte) {
        foreach ($k in $Contexte.Keys) {
            if ([string]::IsNullOrEmpty([string]$Contexte[$k])) { $resultat.Remove([string]$k) }
            else { $resultat[[string]$k] = [string]$Contexte[$k] }
        }
    }
    foreach ($d in $script:CtxDerogations) { $resultat.Remove($d) }
    $resultat
}

function Write-CtxExecLigne {
    # Sur stderr : un orchestrateur lit la sortie de l'ENFANT sur stdout, et une
    # ligne de `ctx exec` melee a un JSON le rendrait illisible.
    param([string]$Texte)
    [Console]::Error.WriteLine("  $Texte")
}

function Invoke-DevContextExec {
    <#
    .SYNOPSIS
        Lance une commande sous le contexte qui possede le dossier courant.

    .DESCRIPTION
        Comme un terminal neuf dans lequel on aurait tape `work <contexte>` : le
        contexte vient du DOSSIER, jamais de $env:DEVCTX, et l'environnement de
        la commande est construit plutot qu'herite. Les derogations
        DEVCTX_ALLOW_PROD, DEVCTX_ALLOW_GH et DEVCTX_ALLOW_VERCEL n'y sont
        jamais.

        La commande tourne dans un processus a part. La session appelante n'est
        pas modifiee, et sa sortie va a la console : `$x = ctx exec ...` ne
        capture rien.

        Code de sortie ($LASTEXITCODE) : celui de la commande, inchange ; 1 pour
        un script ou un cmdlet en echec ; 125 si `ctx exec` refuse (aucun
        contexte ne possede ce dossier, ou aucune commande) ; 127 si la commande
        est introuvable dans l'environnement du contexte.

        Depuis un autre shell, `pwsh -c` ne rend PAS le code d'une fonction :
        ecrire `pwsh -c 'ctx exec gh pr create; exit $LASTEXITCODE'`.

    .EXAMPLE
        ctx exec gh pr create --fill

    .EXAMPLE
        ctx exec supabase db push
    #>
    # AUCUN param() ni [CmdletBinding()] : meme doctrine que Invoke-DevCtx et les
    # trois wrappers, et meme test AST. Un bloc param reclamerait -Verbose,
    # -Debug et consorts, et `ctx exec gh api -i user` perdrait son -i.

    # 125 d'abord : tout chemin qui n'atteint pas l'enfant -- une exception, un
    # refus -- doit le dire, et non laisser le code d'une commande precedente.
    $global:LASTEXITCODE = $script:CtxExecRefus

    # Aplatis, et sans $null : [string] d'un tableau rendrait '1 2' la ou
    # PowerShell passerait '1,2', et $null deviendrait un argument vide.
    $tous = @(foreach ($a in $args) { foreach ($e in @($a)) { if ($null -ne $e) { [string]$e } } })

    if ($tous.Count -eq 0) {
        Write-CtxExecLigne (T 'exec.usage')
        $global:LASTEXITCODE = $script:CtxExecRefus
        return
    }

    $ici = (Get-Location).ProviderPath
    $m = if ((Get-Location).Provider.Name -eq 'FileSystem') { Resolve-DevContextForPath -Path $ici }
    if (-not $m) {
        Write-CtxExecLigne (T 'exec.horsContexte' $ici)
        Write-CtxExecLigne (T 'exec.horsContexteFix')
        $global:LASTEXITCODE = $script:CtxExecRefus
        return
    }

    $nom = [string]$m.name
    $lire = { param($Contexte, $Cle) Get-CtxSecret -Name $Contexte -Key $Cle }
    $variables = Get-CtxVariablesContexte -Manifeste $m -DossierContexte (Get-CtxPath $nom) -LireSecret $lire
    $supabase = Get-CtxVariablesSupabase -Contexte $nom -Chemin $ici -LireSecret $lire
    foreach ($k in $supabase.Keys) { $variables[$k] = $supabase[$k] }

    # La racine qui vient de DECIDER, et non le DEVCTX_ROOT de la session : une
    # session qui l'a change apres l'import pointerait l'enfant sur un autre
    # magasin, et son garde-fou production ne trouverait plus le projet marque
    # prod. Mesure par l'audit : un leurre `db reset` est passe.
    $variables['DEVCTX_ROOT'] = $script:CtxRoot

    $base = Get-CtxEnvironnementDeBase `
        -Machine (ConvertTo-CtxTableEnv ([Environment]::GetEnvironmentVariables('Machine'))) `
        -Volatile (Get-CtxEnvironnementVolatile) `
        -Utilisateur (ConvertTo-CtxTableEnv ([Environment]::GetEnvironmentVariables('User'))) `
        -Processus (ConvertTo-CtxTableEnv ([Environment]::GetEnvironmentVariables()))
    $enfant = Get-CtxEnvironnementExec -Base $base -Contexte $variables

    # Le NOM des secrets que le COFFRE a fournis, jamais leur valeur : la ligne
    # finit dans des transcriptions d'agent, c'est-a-dire dans des journaux
    # conserves. Compte sur $variables et non sur $enfant, qui porte aussi ce
    # que le registre aurait pose -- le compter la attribuerait au coffre un
    # jeton qui n'en vient pas.
    $charges = @($script:SecretMap.Values | Where-Object { $variables[$_] })
    $liste = if ($charges.Count) { $charges -join ', ' } else { T 'exec.aucunSecret' }
    Write-CtxExecLigne (T 'exec.tampon' $nom $liste)

    # Le pwsh de CETTE installation, et non [Environment]::ProcessPath : le
    # module peut etre charge par un autre hote que pwsh.exe.
    $pwsh = [System.IO.Path]::Combine($PSHOME, $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' }))
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwsh)
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $ici
    # -ExecutionPolicy Bypass, comme les shims : sans lui, une strategie
    # AllSigned ou une marque "venu d'Internet" sur le module refusait le
    # lanceur, et l'orchestrateur lisait 1 -- "la commande a echoue" -- pour
    # une commande jamais lancee. Une strategie posee par GPO l'emporte encore.
    $lanceur = [System.IO.Path]::Combine($PSScriptRoot, '..', 'lancer-commande.ps1')
    foreach ($a in @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lanceur)) { $psi.ArgumentList.Add($a) }

    # Les arguments NE passent PAS par la ligne de commande : derriere -File,
    # pwsh les relisait comme ses propres parametres, et '--output=C:\x'
    # devenait '--output=C' puis '\x'. Ils voyagent encodes dans
    # l'environnement de l'enfant, que le lanceur vide avant tout.
    # -InputObject, jamais le pipeline : un tableau d'un seul element y serait
    # deplie en chaine. Et sans -AsArray, qui l'envelopperait une seconde fois.
    $json = ConvertTo-Json -InputObject $tous -Compress
    $enfant['DEVCTX_EXEC_ARGV'] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))

    $psi.Environment.Clear()
    foreach ($k in $enfant.Keys) { $psi.Environment[$k] = $enfant[$k] }

    try { $processus = [System.Diagnostics.Process]::Start($psi) }
    catch {
        Write-CtxExecLigne (T 'exec.demarrage' (Protect-CtxMessage $_.Exception.Message))
        return
    }
    try {
        $processus.WaitForExit()
        $global:LASTEXITCODE = $processus.ExitCode
    }
    finally { $processus.Dispose() }
}
