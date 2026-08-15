# ---------------------------------------------------------------------------
# ctx doctor -- what can I actually do in THIS folder, and where will it land?
# ---------------------------------------------------------------------------
#
# `ctx` answers "who am I". That was never the whole question. The one that
# costs time is "is this tool installed, authenticated as the right account, and
# aimed at the right project" -- and until now it was answered by failing.
#
# Three symptoms, one cause, all recorded on this machine:
#   - two `supabase` binaries, 2.84.2 and 2.109.1, resolved differently
#     depending on the shell;
#   - MCP servers declared globally, so every project inherits whichever
#     account was connected last;
#   - four VS Code profiles, so a GitHub sign-in in one means nothing in the
#     next.
#
# Every check is a decision on facts gathered elsewhere. The decisions live in
# Test-CtxDoctor* and touch nothing; the gathering lives in Get-Ctx*Facts. That
# split is what makes the interesting half testable without a machine that
# happens to be misconfigured.

# ---------------------------------------------------------------------------
# The check object
# ---------------------------------------------------------------------------

$script:DoctorVerdicts = @('OK', 'INFO', 'ATTENTION', 'PROBLEME', 'ABSENT')

function New-CtxCheck {
    param(
        [Parameter(Mandatory)][string]$Domaine,
        [Parameter(Mandatory)][string]$Sujet,
        [Parameter(Mandatory)][ValidateSet('OK', 'INFO', 'ATTENTION', 'PROBLEME', 'ABSENT')][string]$Verdict,
        [string]$Detail = '',
        [string]$Correctif = ''
    )
    [pscustomobject]@{
        PSTypeName = 'DevContext.DoctorCheck'
        Domaine    = $Domaine
        Sujet      = $Sujet
        Verdict    = $Verdict
        Detail     = $Detail
        Correctif  = $Correctif
    }
}

# ---------------------------------------------------------------------------
# Pure decisions
# ---------------------------------------------------------------------------

function Get-CtxPaires {
    <#
      Yields Name/Value pairs from either a hashtable or an object.

      Reading .claude.json requires ConvertFrom-Json -AsHashtable, because it
      holds keys that differ only by case. Casting the top level to a
      pscustomobject leaves every nested block a Hashtable, whose
      PSObject.Properties are Count and Keys -- not the entries. Iterating the
      wrong one finds no secret and reports all clear.
    #>
    param([AllowNull()]$Bloc)
    if ($null -eq $Bloc) { return }
    if ($Bloc -is [System.Collections.IDictionary]) {
        foreach ($k in $Bloc.Keys) { [pscustomobject]@{ Name = [string]$k; Value = $Bloc[$k] } }
        return
    }
    foreach ($p in $Bloc.PSObject.Properties) { [pscustomobject]@{ Name = $p.Name; Value = $p.Value } }
}

function Test-CtxSecretLitteral {
    <#
      Is this configuration value a secret written in clear text?

      A reference -- ${TOKEN}, %TOKEN%, $TOKEN -- is the good case: it defers to
      the environment, which is where DevContext puts the right token for the
      folder. A literal is the bad case, and the bad case travels: .mcp.json is
      meant to be committed.

      Deliberately biased towards flagging. A false positive costs one glance;
      a false negative is a token in a public repository. What never happens is
      printing the value back.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Valeur)

    if ([string]::IsNullOrWhiteSpace($Valeur)) { return $false }
    # Deferred to the environment, in any of the three usual notations.
    if ($Valeur -match '^\s*\$\{[^}]+\}\s*$') { return $false }
    if ($Valeur -match '^\s*%[^%]+%\s*$')     { return $false }
    if ($Valeur -match '^\s*\$[A-Za-z_][A-Za-z0-9_]*\s*$') { return $false }

    # Known prefixes, in issuer order: Supabase, GitHub, OpenAI, Slack, Google, AWS.
    $prefixes = @(
        '^sbp_', '^sbs_', '^sb_secret_',
        '^ghp_', '^gho_', '^ghu_', '^ghs_', '^ghr_', '^github_pat_',
        '^sk-', '^sk_live_', '^rk_live_',
        '^xox[baprs]-',
        '^AIza', '^ya29\.',
        '^AKIA', '^ASIA'
    )
    foreach ($p in $prefixes) { if ($Valeur -match $p) { return $true } }

    # Unknown issuer: long, dense, no path separator and no space. Catches the
    # opaque blobs the prefix list will always be one issuer behind on.
    if ($Valeur.Length -ge 32 -and
        $Valeur -notmatch '[\\/\s]' -and
        $Valeur -match '[A-Za-z]' -and
        $Valeur -match '[0-9]') { return $true }

    $false
}

function Test-CtxDoctorBinaire {
    <#
      Decides on an executable from its resolved locations.

      Several installations is not a detail: this machine carries supabase
      2.84.2 under PowerShell and 2.109.1 under npm, so "which version am I
      running" depends on the shell. A guard tested against one of them says
      nothing about the other.
    #>
    param(
        [Parameter(Mandatory)][string]$Nom,
        [object[]]$Installations = @(),
        [string]$CorrectifAbsent = ''
    )

    if (-not $Installations -or $Installations.Count -eq 0) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'ABSENT' `
            -Detail "introuvable dans le PATH" -Correctif $CorrectifAbsent
    }

    $reels = @($Installations | Where-Object { -not $_.EstShim })
    if ($reels.Count -eq 0) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'PROBLEME' `
            -Detail "seul le shim DevContext repond : le binaire reel est introuvable" `
            -Correctif $CorrectifAbsent
    }

    $versions = @($reels | ForEach-Object { $_.Version } | Where-Object { $_ } | Sort-Object -Unique)

    if ($reels.Count -eq 1) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'OK' `
            -Detail "$($reels[0].Version) — $($reels[0].Chemin)"
    }

    if ($versions.Count -le 1) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'INFO' `
            -Detail "$($reels.Count) installations, meme version ($($versions -join ', '))"
    }

    New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'ATTENTION' `
        -Detail ("$($reels.Count) installations de versions differentes : " +
                 (($reels | ForEach-Object { "$($_.Version) ($(Split-Path $_.Chemin -Parent))" }) -join ' | ')) `
        -Correctif "n'en garder qu'une — la version depend sinon du shell appelant"
}

function Test-CtxDoctorIdentiteGit {
    param(
        [AllowNull()][string]$EmailAttendu,
        [AllowNull()][string]$EmailReel,
        [AllowNull()][string]$Origine
    )
    if (-not $EmailAttendu) {
        return New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'INFO' `
            -Detail 'ce dossier n appartient a aucun contexte'
    }
    if (-not $EmailReel) {
        return New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'PROBLEME' `
            -Detail 'aucun user.email resolu' `
            -Correctif 'verifier le includeIf de ~/.gitconfig'
    }
    if ($EmailReel -ne $EmailAttendu) {
        return New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'PROBLEME' `
            -Detail "$EmailReel au lieu de $EmailAttendu (defini par $Origine)" `
            -Correctif 'un user.email en dur dans .git/config prime sur le includeIf'
    }
    New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'OK' -Detail $EmailReel
}

function Test-CtxDoctorRemote {
    <#
      The trap documented on 5 Aug 2026: a remote written
      https://login@github.com/... does not match the insteadOf rule, which is a
      string prefix. The push then leaves over HTTPS on whichever account `gh`
      last logged into -- silently, and under the wrong identity.
    #>
    param(
        [AllowNull()][string]$UrlPush,
        [AllowNull()][string]$AliasAttendu
    )
    if (-not $UrlPush) {
        return New-CtxCheck -Domaine 'git' -Sujet 'remote' -Verdict 'INFO' `
            -Detail 'aucun remote origin'
    }
    if ($UrlPush -match '^https://[^/@]+@') {
        return New-CtxCheck -Domaine 'git' -Sujet 'remote' -Verdict 'PROBLEME' `
            -Detail 'le remote porte un login dans son URL : la regle insteadOf ne matche pas' `
            -Correctif 'git remote set-url origin https://github.com/<org>/<repo>.git'
    }
    if ($AliasAttendu -and $UrlPush -notmatch [regex]::Escape($AliasAttendu)) {
        return New-CtxCheck -Domaine 'git' -Sujet 'remote' -Verdict 'ATTENTION' `
            -Detail "$UrlPush n emprunte pas la cle SSH $AliasAttendu" `
            -Correctif "verifier la regle insteadOf du contexte"
    }
    New-CtxCheck -Domaine 'git' -Sujet 'remote' -Verdict 'OK' -Detail $UrlPush
}

function Test-CtxDoctorPathEntreeVide {
    <#
      An empty PATH entry means "the current directory" on Windows. Any folder
      you cd into can then supply a binary that shadows a real command --
      including inside a repository cloned from elsewhere.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Path)
    $entrees = @(($Path -split ';'))
    $vides = @($entrees | Where-Object { $_ -eq '' })
    if ($vides.Count -eq 0) {
        return New-CtxCheck -Domaine 'path' -Sujet 'entree vide' -Verdict 'OK' -Detail 'aucune'
    }
    New-CtxCheck -Domaine 'path' -Sujet 'entree vide' -Verdict 'ATTENTION' `
        -Detail "$($vides.Count) entree(s) vide(s) : le dossier courant est dans le chemin de recherche" `
        -Correctif 'retirer les ;; du PATH utilisateur'
}

function Test-CtxDoctorMcpServeur {
    <#
      Decides on one MCP server declaration.

      Three shapes matter, and they are not equally good:
        - a literal secret   -> travels with the file, which is meant to be committed
        - an OAuth/http server -> bound to whichever account the human connected,
          machine-wide; that is precisely the switching this tool exists to end
        - an env reference   -> resolved per folder by `work`, which is the goal
    #>
    param(
        [Parameter(Mandatory)][string]$Nom,
        [AllowNull()]$Definition,
        [string]$Portee = 'global'
    )

    $type = Get-CtxProp $Definition 'type'
    $url  = Get-CtxProp $Definition 'url'

    $enDur = @()
    foreach ($p in (Get-CtxPaires (Get-CtxProp $Definition 'env'))) {
        if (Test-CtxSecretLitteral ([string]$p.Value)) { $enDur += $p.Name }
    }
    $arguments = Get-CtxProp $Definition 'args'
    if ($arguments) {
        foreach ($a in $arguments) {
            if (Test-CtxSecretLitteral ([string]$a)) { $enDur += '(argument)' }
        }
    }

    if ($enDur.Count) {
        # The names of the offending keys, never their values.
        return New-CtxCheck -Domaine 'mcp' -Sujet $Nom -Verdict 'PROBLEME' `
            -Detail "secret en clair dans la configuration ($Portee) : $($enDur -join ', ')" `
            -Correctif 'remplacer par ${NOM_DE_VARIABLE} — work exporte deja le bon jeton'
    }

    if ($url -or $type -eq 'http' -or $type -eq 'sse') {
        return New-CtxCheck -Domaine 'mcp' -Sujet $Nom -Verdict 'ATTENTION' `
            -Detail "serveur distant ($Portee) : authentifie par OAuth, donc lie au compte connecte, pas au dossier" `
            -Correctif 'un serveur stdio local avec un jeton pris dans l environnement suit le contexte'
    }

    New-CtxCheck -Domaine 'mcp' -Sujet $Nom -Verdict 'OK' `
        -Detail "stdio ($Portee)"
}

# ---------------------------------------------------------------------------
# Gathering
# ---------------------------------------------------------------------------

function Get-CtxBinaireFacts {
    <#
      Locates an executable and reads its version, once per FOLDER: the .cmd and
      its extensionless sibling are the same install seen by two shells, and
      counting them twice would report a conflict that does not exist.
    #>
    param(
        [Parameter(Mandatory)][string]$Nom,
        [string[]]$ArgsVersion = @('--version')
    )

    $shimDir = (Join-Path $PSScriptRoot '..' 'shims')
    $shimDir = try { (Resolve-Path -LiteralPath $shimDir -ErrorAction Stop).Path.TrimEnd('\') } catch { $shimDir }

    $vus = @{}
    foreach ($c in @(Get-Command $Nom -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $dossier = (Split-Path $c.Source -Parent).TrimEnd('\')
        if ($vus.ContainsKey($dossier.ToLowerInvariant())) { continue }

        $estShim = $dossier.ToLowerInvariant() -eq $shimDir.ToLowerInvariant()
        $version = $null
        if (-not $estShim) {
            # A version probe must never hang a diagnostic. Failure is data, so
            # it is recorded as an unknown version rather than swallowed.
            $version = try {
                $sortie = & $c.Source @ArgsVersion 2>&1 | Select-Object -First 1
                if ($LASTEXITCODE -eq 0 -and $sortie) { ([string]$sortie).Trim() } else { $null }
            }
            catch { $null }
        }

        $vus[$dossier.ToLowerInvariant()] = $true
        [pscustomobject]@{ Chemin = $c.Source; Version = $version; EstShim = $estShim }
    }
}

function Get-CtxMcpFacts {
    <#
      Every MCP declaration that applies to this folder, and where it comes
      from. Four sources, because four tools each invented their own:
        ~/.claude.json      mcpServers            -> Claude Code, all folders
        ~/.claude.json      projects.<p>.mcpServers -> Claude Code, this folder
        <projet>/.mcp.json                        -> Claude Code, committed
        <projet>/.vscode/mcp.json                 -> VS Code, committed
    #>
    param([string]$Dossier = (Get-Location).Path)

    $trouves = [System.Collections.Generic.List[object]]::new()

    $claude = Join-Path $HOME '.claude.json'
    if (Test-Path -LiteralPath $claude) {
        # -AsHashtable is required: the file holds keys that differ only by case
        # (C:\Users\moi\desktop and ...\Desktop), which ConvertFrom-Json
        # refuses outright without it.
        $j = try { Get-Content -LiteralPath $claude -Raw | ConvertFrom-Json -AsHashtable } catch { $null }
        if ($j) {
            if ($j['mcpServers']) {
                foreach ($k in $j['mcpServers'].Keys) {
                    $trouves.Add([pscustomobject]@{ Nom = $k; Definition = [pscustomobject]$j['mcpServers'][$k]; Portee = 'global' })
                }
            }
            if ($j['projects']) {
                $cle = @($j['projects'].Keys | Where-Object {
                    $_.Replace('/', '\').TrimEnd('\') -ieq $Dossier.Replace('/', '\').TrimEnd('\')
                }) | Select-Object -First 1
                if ($cle -and $j['projects'][$cle]['mcpServers']) {
                    foreach ($k in $j['projects'][$cle]['mcpServers'].Keys) {
                        $trouves.Add([pscustomobject]@{ Nom = $k; Definition = [pscustomobject]$j['projects'][$cle]['mcpServers'][$k]; Portee = 'ce dossier' })
                    }
                }
            }
        }
    }

    foreach ($paire in @(@('.mcp.json', 'projet'), @('.vscode\mcp.json', 'vscode'))) {
        $p = Join-Path $Dossier $paire[0]
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $j = try { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -AsHashtable } catch { $null }
        $bloc = if ($j -and $j['mcpServers']) { $j['mcpServers'] } elseif ($j -and $j['servers']) { $j['servers'] } else { $null }
        if (-not $bloc) { continue }
        foreach ($k in $bloc.Keys) {
            $trouves.Add([pscustomobject]@{ Nom = $k; Definition = [pscustomobject]$bloc[$k]; Portee = $paire[1] })
        }
    }

    $trouves
}

# ---------------------------------------------------------------------------
# Get-DevContextDoctor -- assembles the report
# ---------------------------------------------------------------------------

function Get-DevContextDoctor {
    <#
    .SYNOPSIS
        Diagnoses what is usable in the current folder, and on which account.

    .DESCRIPTION
        `ctx` says who you are. This says what you can do here, whether each
        tool is installed, authenticated as the right account, and aimed at the
        right project -- so that the answer stops arriving in the form of a
        failure halfway through a task.

        Read-only. Runs no outgoing command, changes nothing, and never prints
        the value of a secret.

    .PARAMETER Path
        Folder to diagnose. Defaults to the current one.

    .PARAMETER Live
        Also probes each loaded token against its service, to check it is still
        valid AND opens the account this folder expects. Read-only calls only:
        whoami, list projects. Off by default, because a diagnostic that reaches
        the network without being asked is one people stop running.

    .PARAMETER Json
        Emits JSON, for an agent or a CI job to consume.

    .EXAMPLE
        ctx-doctor

    .EXAMPLE
        ctx-doctor -Live

    .EXAMPLE
        ctx-doctor -Json | ConvertFrom-Json
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path,
        [switch]$Live,
        [switch]$Json
    )

    $dossier = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }
    $checks  = [System.Collections.Generic.List[object]]::new()

    # --- contexte ----------------------------------------------------------
    $manifeste = Resolve-DevContextForPath -Path $dossier
    $proprio   = if ($manifeste) { Get-CtxProp $manifeste 'name' } else { $null }
    $actif     = $env:DEVCTX

    if (-not $proprio) {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'INFO' `
            -Detail 'ce dossier n appartient a aucun contexte'))
    }
    elseif (-not $actif) {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'ATTENTION' `
            -Detail "dossier du contexte '$proprio', mais aucun contexte actif dans ce shell" `
            -Correctif "work $proprio -NoCd"))
    }
    elseif ($actif -ne $proprio) {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'PROBLEME' `
            -Detail "dossier du contexte '$proprio', identite active '$actif'" `
            -Correctif "work $proprio -NoCd"))
    }
    else {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'OK' -Detail $proprio))
    }

    # --- git ---------------------------------------------------------------
    Push-Location -LiteralPath $dossier
    try {
        $estDepot = (git rev-parse --is-inside-work-tree 2>$null) -eq 'true'
        if ($estDepot) {
            $emailReel = (git config user.email 2>$null)
            $origine   = (git config --show-origin user.email 2>$null) -replace '\s.*$', '' -replace '^file:', ''
            $emailAttendu = if ($manifeste) { Get-CtxProp $manifeste 'email' } else { $null }
            $checks.Add((Test-CtxDoctorIdentiteGit -EmailAttendu $emailAttendu `
                -EmailReel $emailReel -Origine $origine))

            $push = (git remote get-url --push origin 2>$null)
            $checks.Add((Test-CtxDoctorRemote -UrlPush $push `
                -AliasAttendu $(if ($proprio) { "github-$proprio" } else { $null })))
        }
        else {
            $checks.Add((New-CtxCheck -Domaine 'git' -Sujet 'depot' -Verdict 'INFO' `
                -Detail 'pas un depot git'))
        }
    }
    finally { Pop-Location }

    # --- binaires ----------------------------------------------------------
    $checks.Add((Test-CtxDoctorBinaire -Nom 'git' -Installations @(Get-CtxBinaireFacts 'git') `
        -CorrectifAbsent 'winget install Git.Git'))
    $checks.Add((Test-CtxDoctorBinaire -Nom 'gh' -Installations @(Get-CtxBinaireFacts 'gh') `
        -CorrectifAbsent 'winget install GitHub.cli'))
    $checks.Add((Test-CtxDoctorBinaire -Nom 'supabase' -Installations @(Get-CtxBinaireFacts 'supabase') `
        -CorrectifAbsent 'npm i -g supabase'))
    $checks.Add((Test-CtxDoctorBinaire -Nom 'vercel' -Installations @(Get-CtxBinaireFacts 'vercel') `
        -CorrectifAbsent 'npm i -g vercel'))
    $checks.Add((Test-CtxDoctorBinaire -Nom 'node' -Installations @(Get-CtxBinaireFacts 'node') `
        -CorrectifAbsent 'winget install OpenJS.NodeJS.LTS'))

    # --- gh ----------------------------------------------------------------
    if ($proprio) {
        $attendu = Join-Path (Get-CtxPath $proprio) 'gh'
        if (-not $env:GH_CONFIG_DIR) {
            $checks.Add((New-CtxCheck -Domaine 'gh' -Sujet 'compte' -Verdict 'PROBLEME' `
                -Detail 'GH_CONFIG_DIR absent : gh utilise la config globale, donc le dernier compte connecte' `
                -Correctif "work $proprio -NoCd"))
        }
        elseif ($env:GH_CONFIG_DIR.TrimEnd('\') -ne $attendu.TrimEnd('\')) {
            $checks.Add((New-CtxCheck -Domaine 'gh' -Sujet 'compte' -Verdict 'PROBLEME' `
                -Detail "GH_CONFIG_DIR pointe sur un autre contexte" `
                -Correctif "work $proprio -NoCd"))
        }
        else {
            $login = Get-CtxProp $manifeste 'github.login'
            $checks.Add((New-CtxCheck -Domaine 'gh' -Sujet 'compte' -Verdict 'OK' `
                -Detail $(if ($login) { $login } else { 'config dediee au contexte' })))
        }
    }

    # --- supabase ----------------------------------------------------------
    $ref = Resolve-CtxSupabaseRef -Path $dossier
    if ($ref) {
        $envProjet = if ($proprio) { Get-CtxSupabaseEnv -Ref $ref -ContextName $proprio } else { $null }
        $cleAttendue = Resolve-CtxSupabaseKey -Path $dossier

        if (-not $envProjet) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'projet' -Verdict 'ATTENTION' `
                -Detail "projet lie mais absent de l index, ou environnement non marque" `
                -Correctif 'sb-index'))
        }
        elseif ($envProjet -eq 'prod') {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'projet' -Verdict 'ATTENTION' `
                -Detail 'ce dossier vise un projet de PRODUCTION' `
                -Correctif 'db reset y est refuse, db push hors branche par defaut aussi'))
        }
        else {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'projet' -Verdict 'OK' -Detail $envProjet))
        }

        if ($cleAttendue -and $env:DEVCTX_SUPABASE_KEY -and $env:DEVCTX_SUPABASE_KEY -ne $cleAttendue) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'compte' -Verdict 'PROBLEME' `
                -Detail "le jeton charge n est pas celui que ce projet attend" `
                -Correctif "work $proprio -NoCd"))
        }
        elseif ($cleAttendue -and -not $env:SUPABASE_ACCESS_TOKEN) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'compte' -Verdict 'ATTENTION' `
                -Detail 'aucun jeton charge dans ce shell' `
                -Correctif "work $proprio -NoCd"))
        }
        elseif ($cleAttendue) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'compte' -Verdict 'OK' -Detail $cleAttendue))
        }
    }

    # --- garde-fou ---------------------------------------------------------
    $checks.Add((Test-CtxDoctorGardeFou))

    # --- vercel ------------------------------------------------------------
    $vercelProjet = Join-Path $dossier '.vercel\project.json'
    if (Test-Path -LiteralPath $vercelProjet) {
        if ($proprio -and -not $env:DEVCTX_VERCEL_CONFIG) {
            $checks.Add((New-CtxCheck -Domaine 'vercel' -Sujet 'session' -Verdict 'PROBLEME' `
                -Detail 'projet Vercel lie, mais aucune session de contexte chargee' `
                -Correctif "work $proprio -NoCd"))
        }
        else {
            $checks.Add((New-CtxCheck -Domaine 'vercel' -Sujet 'session' -Verdict 'OK' `
                -Detail 'projet lie, session dediee au contexte'))
        }
    }

    # --- mcp ---------------------------------------------------------------
    $mcp = @(Get-CtxMcpFacts -Dossier $dossier)
    if ($mcp.Count -eq 0) {
        $checks.Add((New-CtxCheck -Domaine 'mcp' -Sujet 'serveurs' -Verdict 'INFO' `
            -Detail 'aucun serveur MCP declare pour ce dossier'))
    }
    foreach ($s in $mcp) {
        $checks.Add((Test-CtxDoctorMcpServeur -Nom $s.Nom -Definition $s.Definition -Portee $s.Portee))
    }

    # --- path --------------------------------------------------------------
    $checks.Add((Test-CtxDoctorPathEntreeVide -Path $env:PATH))

    # --- jetons, sur demande ------------------------------------------------
    if ($Live) {
        foreach ($c in (Get-CtxJetonChecks -Manifeste $manifeste -Ref $ref)) { $checks.Add($c) }
    }

    if ($Json) { return ($checks | ConvertTo-Json -Depth 4) }
    $checks
}

function Test-CtxDoctorGardeFou {
    <#
      Is the production guard reachable from every shell, or only from this one?
      An alias covers PowerShell; only a PATH entry covers git-bash, npm, Node
      and an agent's shell.
    #>
    $shimDir = try { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' 'shims') -ErrorAction Stop).Path.TrimEnd('\') }
               catch { return (New-CtxCheck -Domaine 'garde-fou' -Sujet 'shims' -Verdict 'ABSENT' -Detail 'dossier shims introuvable') }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pose = @($userPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\').ToLowerInvariant() -eq $shimDir.ToLowerInvariant() }).Count -gt 0

    if (-not $pose) {
        return New-CtxCheck -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'PROBLEME' `
            -Detail 'shims absents du PATH : la protection ne couvre que PowerShell' `
            -Correctif 'pwsh -File installer-shims.ps1'
    }
    if ($env:DEVCTX_ALLOW_PROD -eq '1') {
        return New-CtxCheck -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'ATTENTION' `
            -Detail 'DEVCTX_ALLOW_PROD=1 : le garde-fou est desarme dans ce shell' `
            -Correctif 'Remove-Item Env:DEVCTX_ALLOW_PROD'
    }
    New-CtxCheck -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'OK' -Detail 'actif dans tous les shells'
}
