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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Fonction pure : construit un objet de constat, ne modifie aucun etat.')]
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
            -Detail (T 'doc.bin.absent') -Correctif $CorrectifAbsent
    }

    $reels = @($Installations | Where-Object { -not $_.EstShim })
    if ($reels.Count -eq 0) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'PROBLEME' `
            -Detail (T 'doc.bin.shimSeul') `
            -Correctif $CorrectifAbsent
    }

    $versions = @($reels | ForEach-Object { $_.Version } | Where-Object { $_ } | Sort-Object -Unique)

    if ($reels.Count -eq 1) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'OK' `
            -Detail (T 'doc.bin.une' $reels[0].Version $reels[0].Chemin)
    }

    if ($versions.Count -le 1) {
        return New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'INFO' `
            -Detail (T 'doc.bin.memeVersion' $reels.Count ($versions -join ', '))
    }

    $ou = ($reels | ForEach-Object { "$($_.Version) ($(Split-Path $_.Chemin -Parent))" }) -join ' | '
    New-CtxCheck -Domaine $Nom -Sujet 'binaire' -Verdict 'ATTENTION' `
        -Detail (T 'doc.bin.versionsDiff' $reels.Count $ou) `
        -Correctif (T 'doc.bin.correctifDiff')
}

function Test-CtxDoctorIdentiteGit {
    param(
        [AllowNull()][string]$EmailAttendu,
        [AllowNull()][string]$EmailReel,
        [AllowNull()][string]$Origine
    )
    if (-not $EmailAttendu) {
        return New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'INFO' `
            -Detail (T 'doc.git.horsContexte')
    }
    if (-not $EmailReel) {
        return New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'PROBLEME' `
            -Detail (T 'doc.git.sansEmail') `
            -Correctif (T 'doc.git.sansEmailFix')
    }
    if ($EmailReel -ne $EmailAttendu) {
        return New-CtxCheck -Domaine 'git' -Sujet 'identite' -Verdict 'PROBLEME' `
            -Detail (T 'doc.git.mauvaisEmail' $EmailReel $EmailAttendu $Origine) `
            -Correctif (T 'doc.git.mauvaisEmailFix')
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
            -Detail (T 'doc.remote.aucun')
    }
    if ($UrlPush -match '^https://[^/@]+@') {
        return New-CtxCheck -Domaine 'git' -Sujet 'remote' -Verdict 'PROBLEME' `
            -Detail (T 'doc.remote.login') `
            -Correctif (T 'doc.remote.loginFix')
    }
    if ($AliasAttendu -and $UrlPush -notmatch [regex]::Escape($AliasAttendu)) {
        return New-CtxCheck -Domaine 'git' -Sujet 'remote' -Verdict 'ATTENTION' `
            -Detail (T 'doc.remote.sansAlias' $UrlPush $AliasAttendu) `
            -Correctif (T 'doc.remote.sansAliasFix')
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
        return New-CtxCheck -Domaine 'path' -Sujet 'entree vide' -Verdict 'OK' -Detail (T 'doc.path.aucune')
    }
    New-CtxCheck -Domaine 'path' -Sujet 'entree vide' -Verdict 'ATTENTION' `
        -Detail (T 'doc.path.vides' $vides.Count) `
        -Correctif (T 'doc.path.videsFix')
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
            -Detail (T 'doc.mcp.enClair' $Portee ($enDur -join ', ')) `
            -Correctif (T 'doc.mcp.enClairFix')
    }

    if ($url -or $type -eq 'http' -or $type -eq 'sse') {
        return New-CtxCheck -Domaine 'mcp' -Sujet $Nom -Verdict 'ATTENTION' `
            -Detail (T 'doc.mcp.distant' $Portee) `
            -Correctif (T 'doc.mcp.distantFix')
    }

    New-CtxCheck -Domaine 'mcp' -Sujet $Nom -Verdict 'OK' `
        -Detail (T 'doc.mcp.stdio' $Portee)
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

    # TOUS nos dossiers, pas un seul. Depuis que PATH designe une jonction, le
    # meme dossier porte deux noms ; n'en reconnaitre qu'un ferait passer notre
    # propre shim pour une installation concurrente de la CLI -- et le rapport
    # annoncerait un conflit qui n'existe pas, en tentant de l'interroger.
    $shimDirs = @(Get-CtxShimDirs)

    $vus = @{}
    foreach ($c in @(Get-Command $Nom -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $dossier = (Split-Path $c.Source -Parent).TrimEnd('\')
        if ($vus.ContainsKey($dossier.ToLowerInvariant())) { continue }

        $estShim = Test-CtxDossierEstShim -Dossier $dossier -Dossiers $shimDirs
        $version = $null
        if (-not $estShim) {
            # A version probe must never hang a diagnostic. Failure is data, so
            # it is recorded as an unknown version rather than swallowed.
            $version = try {
                $sortie = & $c.Source @ArgsVersion 2>&1 | Select-Object -First 1
                # Caviarde : la sortie d'un binaire arbitraire du PATH n'est
                # pas une source de confiance, et ce Detail finit dans un rapport.
                if ($LASTEXITCODE -eq 0 -and $sortie) { Protect-CtxMessage (([string]$sortie).Trim()) } else { $null }
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
        # (\Users\moi\desktop and ...\Desktop), which ConvertFrom-Json
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

    .PARAMETER Fix
        Applies the corrections this diagnostic already spells out, and NAMES the
        ones it will not touch, with the reason. Read-only becomes read-write
        only here, only on request, and only for repairs that can be proven and
        undone. Emits nothing on the pipeline: a fixer is an action, not a query.

    .EXAMPLE
        ctx-doctor -Json | ConvertFrom-Json

    .EXAMPLE
        ctx doctor -Fix -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = (Get-Location).Path,
        [switch]$Live,
        [switch]$Json,
        [switch]$Fix
    )

    # Refuse plutot que d'en ignorer un des deux en silence. -Json sert a un
    # programme, -Fix parle a un humain ; les melanger ne peut que decevoir
    # l'un des deux appelants, et le silence ferait croire que ca a marche.
    if ($Fix -and $Json) { throw (T 'fix.jsonIncompatible') }

    $dossier = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }
    $checks  = [System.Collections.Generic.List[object]]::new()

    # --- contexte ----------------------------------------------------------
    $manifeste = Resolve-DevContextForPath -Path $dossier
    $proprio   = if ($manifeste) { Get-CtxProp $manifeste 'name' } else { $null }
    $actif     = $env:DEVCTX

    if (-not $proprio) {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'INFO' `
                    -Detail (T 'doc.ctx.horsContexte')))
    }
    elseif (-not $actif) {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'ATTENTION' `
                    -Detail (T 'doc.ctx.sansActif' $proprio) `
                    -Correctif "work $proprio -NoCd"))
    }
    elseif ($actif -ne $proprio) {
        $checks.Add((New-CtxCheck -Domaine 'contexte' -Sujet 'proprietaire' -Verdict 'PROBLEME' `
                    -Detail (T 'doc.ctx.autreActif' $proprio $actif) `
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
                        -Detail (T 'doc.git.pasDepot')))
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
                        -Detail (T 'doc.gh.sansConfigDir') `
                        -Correctif "work $proprio -NoCd"))
        }
        elseif ($env:GH_CONFIG_DIR.TrimEnd('\') -ne $attendu.TrimEnd('\')) {
            $checks.Add((New-CtxCheck -Domaine 'gh' -Sujet 'compte' -Verdict 'PROBLEME' `
                        -Detail (T 'doc.gh.autreContexte') `
                        -Correctif "work $proprio -NoCd"))
        }
        else {
            $login = Get-CtxProp $manifeste 'github.login'
            $checks.Add((New-CtxCheck -Domaine 'gh' -Sujet 'compte' -Verdict 'OK' `
                        -Detail $(if ($login) { $login } else { T 'doc.gh.dedie' })))
        }
    }

    # --- supabase ----------------------------------------------------------
    $ref = Resolve-CtxSupabaseRef -Path $dossier
    if ($ref) {
        $envProjet = if ($proprio) { Get-CtxSupabaseEnv -Ref $ref -ContextName $proprio } else { $null }
        $cleAttendue = Resolve-CtxSupabaseKey -Path $dossier

        if (-not $envProjet) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'projet' -Verdict 'ATTENTION' `
                        -Detail (T 'doc.sb.horsIndex') `
                        -Correctif 'sb-index'))
        }
        elseif ($envProjet -eq 'prod') {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'projet' -Verdict 'ATTENTION' `
                        -Detail (T 'doc.sb.prod') `
                        -Correctif (T 'doc.sb.prodFix')))
        }
        else {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'projet' -Verdict 'OK' -Detail $envProjet))
        }

        if ($cleAttendue -and $env:DEVCTX_SUPABASE_KEY -and $env:DEVCTX_SUPABASE_KEY -ne $cleAttendue) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'compte' -Verdict 'PROBLEME' `
                        -Detail (T 'doc.sb.mauvaiseCle') `
                        -Correctif "work $proprio -NoCd"))
        }
        elseif ($cleAttendue -and -not $env:SUPABASE_ACCESS_TOKEN) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'compte' -Verdict 'ATTENTION' `
                        -Detail (T 'doc.sb.sansJeton') `
                        -Correctif "work $proprio -NoCd"))
        }
        elseif ($cleAttendue) {
            $checks.Add((New-CtxCheck -Domaine 'supabase' -Sujet 'compte' -Verdict 'OK' -Detail $cleAttendue))
        }
    }

    # --- garde-fou ---------------------------------------------------------
    $checks.Add((Test-CtxDoctorGardeFou))
    # Rend $null quand tous nos shims sont bien en tete : ne rien dire est la
    # bonne reponse quand tout va bien.
    $masques = Test-CtxDoctorShimsDevant
    if ($masques) { $checks.Add($masques) }
    # Rend $null quand aucune distribution WSL n'est installee : rien a signaler.
    $wsl = Test-CtxDoctorWsl
    if ($wsl) { $checks.Add($wsl) }

    # --- vercel ------------------------------------------------------------
    $vercelProjet = Join-Path $dossier '.vercel\project.json'
    if (Test-Path -LiteralPath $vercelProjet) {
        if ($proprio -and -not $env:DEVCTX_VERCEL_CONFIG) {
            $checks.Add((New-CtxCheck -Domaine 'vercel' -Sujet 'session' -Verdict 'PROBLEME' `
                        -Detail (T 'doc.vercel.sansSession') `
                        -Correctif "work $proprio -NoCd"))
        }
        else {
            $checks.Add((New-CtxCheck -Domaine 'vercel' -Sujet 'session' -Verdict 'OK' `
                        -Detail (T 'doc.vercel.ok')))
        }
    }

    # --- mcp ---------------------------------------------------------------
    $mcp = @(Get-CtxMcpFacts -Dossier $dossier)
    if ($mcp.Count -eq 0) {
        $checks.Add((New-CtxCheck -Domaine 'mcp' -Sujet 'serveurs' -Verdict 'INFO' `
                    -Detail (T 'doc.mcp.aucun')))
    }
    foreach ($s in $mcp) {
        $checks.Add((Test-CtxDoctorMcpServeur -Nom $s.Nom -Definition $s.Definition -Portee $s.Portee))
    }

    # --- editeurs ----------------------------------------------------------
    #
    # La question qu'un raccourci ne pose jamais : si j'ouvre ce projet avec cet
    # editeur, ai-je mes propres sessions, ou celles de tout le monde ?
    $editeurs = @(Get-DevEditorList)

    # Dit AVANT la liste : c'est la ligne qui explique pourquoi les suivantes,
    # toutes vertes, s'accompagnent quand meme d'une invite a se connecter.
    $connexions = Test-CtxDoctorEditeurConnexions -Editeurs $editeurs
    if ($connexions) { $checks.Add($connexions) }

    # Une identite d'un autre contexte s'est-elle installee dans ce profil ?
    # L'isolation empeche les sessions de s'ecraser ; elle n'empeche pas de se
    # connecter au mauvais compte DANS le bon profil.
    foreach ($c in (Test-CtxDoctorProfilComptes -Faits (Get-CtxProfilComptesFacts))) { $checks.Add($c) }

    foreach ($e in $editeurs) {
        # Sur le champ BOOLEEN, jamais sur le libelle affiche : celui-ci est
        # traduit, et le comparer a un litteral francais faisait rapporter
        # chaque editeur comme non isole des que la sortie passait en anglais.
        if ($e.Isole) {
            $detail = if ($e.ExtensionsIsolees) { T 'doc.editeur.complet' }
            else { T 'doc.editeur.profilSeul' }
            $checks.Add((New-CtxCheck -Domaine 'editeur' -Sujet $e.Commande -Verdict 'OK' `
                        -Detail (T 'doc.editeur.methode' $detail $e.Methode)))
        }
        else {
            $checks.Add((New-CtxCheck -Domaine 'editeur' -Sujet $e.Commande -Verdict 'ATTENTION' `
                        -Detail (T 'editeur.sansUserDataDir' $e.Editeur) `
                        -Correctif (T 'doc.editeur.limiteFix')))
        }
    }

    # --- agents ------------------------------------------------------------
    #
    # Le reste du module cloisonne QUI ON EST. Rien n'y regardait OU CA ECRIT --
    # alors que les agents portent deja une frontiere, et qu'elle s'elargit une
    # approbation ponctuelle a la fois, en portee utilisateur, sans que personne
    # ne relise jamais la liste.
    # Le @() n'est pas decoratif. Une fonction PowerShell ne peut pas RENDRE un
    # tableau vide : il se deplie en traversant la sortie, et l'appelant recoit
    # $null. Sous StrictMode, le $Faits.Count d'en face leve alors. Invisible sur
    # une machine de developpeur, qui a toujours un fichier de reglages quelque
    # part ; rouge sur un agent de CI, qui n'en a aucun. Meme defaut que le
    # $reste de Invoke-DevCtx et que Get-CtxVercelMots en 1.4.0 : un tableau qui
    # traverse une expression se deplie, et il faut le redemander a chaque fois.
    $faitsAgents = @(Get-CtxAgentConfianceFacts -Dossier $dossier)
    foreach ($c in (Test-CtxDoctorAgentConfiance -Faits $faitsAgents -Contexte $proprio)) {
        $checks.Add($c)
    }

    # --- raccourcis --------------------------------------------------------
    #
    # Le seul lanceur que le PATH ne peut pas atteindre. Un raccourci qui vise
    # l'executable en absolu court-circuite tout, et personne ne relit un
    # raccourci -- alors on le lit pour lui.
    foreach ($r in (Get-CtxRaccourciChecks)) { $checks.Add($r) }

    # --- path --------------------------------------------------------------
    $checks.Add((Test-CtxDoctorPathEntreeVide -Path $env:PATH))

    # --- jetons, sur demande ------------------------------------------------
    if ($Live) {
        foreach ($c in (Get-CtxJetonChecks -Manifeste $manifeste -Ref $ref)) { $checks.Add($c) }
    }

    if ($Json) { return ($checks | ConvertTo-Json -Depth 4) }

    # -Fix agit sur les constats qui viennent d'etre etablis, jamais sur un
    # diagnostic anterieur : reparer d'apres un etat perime est la facon la plus
    # sure de reparer ce qui va bien.
    if ($Fix) { return (Invoke-CtxDoctorFix -Checks @($checks)) }

    $checks
}

function Test-CtxDoctorGardeFou {
    <#
      Is the production guard reachable from every shell, or only from this one?
      An alias covers PowerShell; only a PATH entry covers git-bash, npm, Node
      and an agent's shell.
    #>
    $shimDir = try { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' 'shims') -ErrorAction Stop).Path.TrimEnd('\') }
    catch { return (New-CtxCheck -Domaine 'garde-fou' -Sujet 'shims' -Verdict 'ABSENT' -Detail (T 'doc.garde.sansDossier')) }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entrees  = @($userPath -split ';' | Where-Object { $_ })
    $stable   = Get-CtxShimStable
    $pose     = @($entrees | Where-Object { Test-CtxDossierEstShim -Dossier $_ -Dossiers @($stable, $shimDir) }).Count -gt 0

    # LA JONCTION POINTE-T-ELLE SUR LA VERSION CHARGEE ?
    #
    # C'est la question que la publication du 15 aout 2026 a rendue necessaire.
    # Installe depuis la Gallery, le module vit sous un chemin qui porte son
    # NUMERO DE VERSION. Installer la version suivante cree un dossier voisin ;
    # la jonction, elle, continue de designer l'ancienne. Le garde-fou tourne
    # alors sur une logique perimee, puis disparait le jour ou l'ancienne version
    # est desinstallee.
    #
    # Rien ne peut se reparer tout seul ici -- l'installateur doit etre relance.
    # Ce que le diagnostic peut faire, c'est empecher que la panne soit
    # silencieuse ; c'est la doctrine de tout ce fichier.
    $moduleBase = Split-Path $PSScriptRoot -Parent
    $cible = Get-CtxJonctionCible -Chemin (Get-CtxShimLien)
    if ($pose -and -not (Test-CtxJonctionSaine -Cible $cible -ModuleAttendu $moduleBase)) {
        if (-not $cible) {
            return New-CtxCheck -Domaine 'garde-fou' -Sujet 'jonction' -Verdict 'PROBLEME' `
                -Detail (T 'doc.garde.jonctionAbsente') `
                -Correctif (T 'doc.garde.jonctionFix')
        }
        return New-CtxCheck -Domaine 'garde-fou' -Sujet 'jonction' -Verdict 'PROBLEME' `
            -Detail (T 'doc.garde.jonctionPerimee' $cible $moduleBase) `
            -Correctif (T 'doc.garde.jonctionFix')
    }

    if (-not $pose) {
        return New-CtxCheck -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'PROBLEME' `
            -Detail (T 'doc.garde.horsPath') `
            -Correctif (T 'doc.garde.horsPathFix')
    }
    # LES TROIS DEROGATIONS, ET NON LA SEULE PREMIERE.
    #
    # Depuis la 1.4.0 il y a un garde-fou par outil, donc une variable par
    # outil. N'en surveiller qu'une rendrait « actif dans tous les shells » a
    # quelqu'un dont le garde-fou gh est desarme depuis son $PROFILE -- soit
    # exactement le mensonge que ce fichier existe pour empecher.
    $derogations = @(
        'DEVCTX_ALLOW_PROD'
        'DEVCTX_ALLOW_GH'
        'DEVCTX_ALLOW_VERCEL'
    )
    $desarmes = @($derogations | Where-Object { [Environment]::GetEnvironmentVariable($_) -eq '1' })
    if ($desarmes.Count -gt 0) {
        return New-CtxCheck -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'ATTENTION' `
            -Detail (T 'doc.garde.desarme' ($desarmes -join ', ')) `
            -Correctif (($desarmes | ForEach-Object { "Remove-Item Env:$_" }) -join ' ; ')
    }
    New-CtxCheck -Domaine 'garde-fou' -Sujet 'portee' -Verdict 'OK' -Detail (T 'doc.garde.ok')
}

function Test-CtxDoctorShimsDevant {
    <#
      NOS SHIMS SONT-ILS REELLEMENT DEVANT LES VRAIS BINAIRES ?

      Etre dans le PATH ne suffit pas : encore faut-il y etre EN PREMIER.
      Windows compose le PATH ainsi -- SYSTEME d'abord, UTILISATEUR ensuite --
      et l'installateur ecrit deliberement dans le PATH utilisateur, pour ne
      demander aucun droit administrateur. Un binaire installe pour toute la
      machine est donc resolu AVANT nos shims, sans que rien ne le signale.

      Mesure le 16 aout 2026 : `gh` installe par winget dans
      C:\Program Files\GitHub CLI arrivait a l'index 10, nos shims a l'index 19.
      Le garde-fou etait pose, annonce actif, et jamais atteint.

      `supabase` echappait au probleme par accident -- il vient de npm, donc du
      PATH utilisateur. Un accident n'est pas une architecture, et ce controle
      existe pour que le prochain ne passe pas inapercu.

      Le resolveur est injecte : la decision se verifie alors sans dependre du
      PATH de la machine qui fait tourner les tests.
    #>
    param(
        [string[]]$Outils = @('supabase', 'gh', 'vercel'),
        [string[]]$Dossiers = (Get-CtxShimDirs),
        [string[]]$PathUtilisateur = (Get-CtxPathUtilisateur),
        [scriptblock]$Resolveur = {
            param($nom)
            $trouves = Get-Command $nom -CommandType Application, ExternalScript -All -ErrorAction SilentlyContinue
            @($trouves | Select-Object -ExpandProperty Source)
        }
    )

    $masques = @()
    foreach ($outil in $Outils) {
        $sources = @(& $Resolveur $outil)
        # Absent de la machine : ce n'est pas notre sujet, et
        # Test-CtxDoctorBinaire le dit deja.
        if ($sources.Count -eq 0) { continue }

        $premier = $sources[0]
        if (Test-CtxDossierEstShimDevContext -Dossier (Split-Path $premier -Parent) -Dossiers $Dossiers) { continue }

        # Le binaire gagne-t-il alors qu'un shim existe pour lui ? Si aucun de
        # nos dossiers n'apparait du tout, c'est le PATH entier qui manque, et
        # Test-CtxDoctorGardeFou le rapporte deja -- ne pas le dire deux fois.
        $nousSommesLa = @($sources | Where-Object {
                Test-CtxDossierEstShimDevContext -Dossier (Split-Path $_ -Parent) -Dossiers $Dossiers
            }).Count -gt 0
        if (-not $nousSommesLa) { continue }

        $dossierGagnant = Split-Path $premier -Parent
        $masques += [pscustomobject]@{
            Outil     = $outil
            Gagnant   = $dossierGagnant
            Correctif = Resolve-CtxMasqueCorrectif -Dossier $dossierGagnant -PathUtilisateur $PathUtilisateur
        }
    }

    if ($masques.Count -eq 0) { return }

    $detail = ($masques | ForEach-Object { "$($_.Outil) -> $($_.Gagnant)" }) -join ' ; '

    # Nommer le correctif LEGER quand il suffit pour tous. Proposer une
    # reinstallation la ou une ligne de PATH regle le probleme fait payer au
    # lecteur un cout qu'il n'avait pas a payer -- et le decourage d'agir.
    $texte = if (@($masques | Where-Object { $_.Correctif -ne 'retrait-systeme' }).Count -eq 0) {
        T 'doc.garde.masqueFixRetrait'
    }
    else { T 'doc.garde.masqueFix' }

    New-CtxCheck -Domaine 'garde-fou' -Sujet 'priorite' -Verdict 'PROBLEME' `
        -Detail (T 'doc.garde.masque' $detail) `
        -Correctif $texte
}

function Test-CtxTexteContientCompte {
    <#
      PURE. Le texte contient-il la cle 'github-<login>', ce login EXACTEMENT ?

      LE PIEGE DE PREFIXE, TROISIEME OCCURRENCE DANS CE DEPOT

      Une recherche de sous-chaine repond OUI a 'github-thier' quand le texte
      porte 'github-thierryvm'. Le contexte 'thier' serait alors accuse d'avoir
      l'identite du contexte 'thierryvm' -- une fausse alerte sur la seule chose
      que ce controle doit dire avec certitude.

      C'est le meme defaut que la resolution de contexte a connu ('Apps' ne doit
      pas matcher 'Apps-Autre'), et il porte ici plus loin : un garde-fou qui
      crie au loup est un garde-fou qu'on desactive.

      La suite est donc bornee a droite : un login GitHub est fait de lettres,
      de chiffres et de tirets, donc le caractere suivant ne doit etre aucun des
      trois. Pas de borne a GAUCHE : la cle commence par 'github-', qui joue ce
      role.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Texte,
        [AllowNull()][AllowEmptyString()][string]$Login
    )

    if ([string]::IsNullOrEmpty($Texte) -or [string]::IsNullOrWhiteSpace($Login)) { return $false }
    $motif = 'github-' + [regex]::Escape($Login.Trim()) + '(?![A-Za-z0-9-])'
    [bool][regex]::IsMatch($Texte, $motif)
}

function Get-CtxProfilComptesFacts {
    <#
      GATHERING. Quels comptes GitHub CONNUS sont presents dans le profil
      d'editeur de chaque contexte ?

      POURQUOI CE CONTROLE EXISTE

      Mesure le 17 aout 2026 sur cette machine : le profil du contexte client
      portait le compte GitHub PERSONNEL, et le profil personnel portait celui
      du client. Les deux profils etaient pourtant bien isoles -- l'isolation
      empeche les sessions de s'ECRASER, elle n'empeche personne de se connecter
      au mauvais compte DANS le bon profil.

      C'est exactement la faute que ce module existe pour empecher, et rien ne
      la signalait. Une fenetre ouverte sur un projet client dont Copilot,
      l'extension Pull Request et GitLens agissent sous une identite perso est
      un incident qui ne se voit qu'apres coup.

      COMMENT, ET POURQUOI PAS AUTREMENT

      VS Code range ses sessions dans state.vscdb, une base SQLite. PowerShell
      n'a pas de pilote SQLite, et ce module n'a AUCUNE dependance -- en ajouter
      une, chargee a chaque `ctx doctor` pour une ligne, serait un mauvais
      echange.

      Alors on cherche le NOM des cles, qui sont du texte clair dans le fichier,
      par recherche EXACTE sur un ENSEMBLE FERME : les logins que les manifestes
      declarent deja. C'est volontairement l'inverse d'une extraction.

      L'extraction a ete essayee le meme jour, et jetee sur mesure : les pages
      SQLite collent des octets binaires aux chaines, et elle rendait
      'thierryvmn4', 'authenticationL', 'thie'. Chercher une chaine qu'on
      connait deja n'a aucun de ces defauts.

      Les VALEURS ne sont jamais lues : elles sont chiffrees, et un diagnostic
      n'a rien a y faire.

      Le fichier est ouvert en partage total : VS Code le tient ouvert, et un
      diagnostic qui echoue parce que l'editeur tourne ne servirait a rien.
    #>
    [CmdletBinding()]
    param(
        # Injectables pour les tests : sans cela ce controle ne serait verifiable
        # que sur une machine ayant exactement la configuration de l'auteur.
        [object[]]$Manifestes,
        [scriptblock]$LecteurProfil = {
            param($Contexte)
            [System.IO.Path]::Combine((Get-CtxPath $Contexte), 'vscode', 'User', 'globalStorage', 'state.vscdb')
        }
    )

    if (-not $PSBoundParameters.ContainsKey('Manifestes')) { $Manifestes = @(Get-CtxManifests) }

    # L'ensemble ferme : un login par contexte, ceux que les manifestes declarent.
    $connus = @{}
    foreach ($m in $Manifestes) {
        $nom = Get-CtxProp $m 'name'
        $gh = Get-CtxProp $m 'github'
        $login = if ($gh) { Get-CtxProp $gh 'login' } else { $null }
        if ($nom -and $login) { $connus[$nom] = $login }
    }
    if ($connus.Count -lt 2) { return @() }

    # TRI OBLIGATOIRE. Les cles d'une Hashtable ne sortent PAS dans un ordre
    # garanti, et le rapport en heritait : deux executions rendaient les memes
    # constats dans un ordre different. Le test qui compare la sortie `fr` a la
    # sortie `en` l'a attrape des la premiere execution -- il ne cherchait pas
    # cela, mais toute difference entre les deux passages le fait rougir, et un
    # ordre instable en est une.
    $faits = @()
    foreach ($nom in ($connus.Keys | Sort-Object)) {
        $chemin = & $LecteurProfil $nom
        if (-not $chemin -or -not (Test-Path -LiteralPath $chemin)) { continue }

        $texte = $null
        try {
            $flux = [System.IO.File]::Open($chemin, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $octets = New-Object byte[] $flux.Length
                $null = $flux.Read($octets, 0, $octets.Length)
                $texte = [System.Text.Encoding]::ASCII.GetString($octets)
            }
            finally { $flux.Dispose() }
        }
        catch { continue }   # illisible : on se tait plutot que d'accuser a tort

        $etrangers = @()
        foreach ($autre in ($connus.Keys | Sort-Object)) {
            if ($autre -eq $nom) { continue }
            if (Test-CtxTexteContientCompte -Texte $texte -Login $connus[$autre]) {
                $etrangers += [pscustomobject]@{ Contexte = $autre; Login = $connus[$autre] }
            }
        }

        $faits += [pscustomobject]@{
            Contexte  = $nom
            Attendu   = $connus[$nom]
            Etrangers = @($etrangers)
        }
    }
    @($faits)
}

function Test-CtxDoctorProfilComptes {
    <#
      PURE. Un profil d'editeur porte-t-il l'identite d'un AUTRE contexte ?

      Un constat par contexte concerne, et rien du tout quand tout est propre --
      un rapport qui felicite a chaque ligne finit lu en diagonale.

      Verdict PROBLEME et non ATTENTION, meme quand c'est delibere : le cas le
      plus courant est de se connecter avec son compte personnel pour la
      synchronisation des reglages, et le cout de ce choix est qu'une fenetre
      ouverte sur un projet client porte une identite perso authentifiee. Le
      correctif nomme l'alternative -- synchroniser via le compte Microsoft, que
      VS Code accepte aussi -- plutot que de demander de renoncer a la synchro.
    #>
    [CmdletBinding()]
    param([object[]]$Faits = @())

    $checks = @()
    foreach ($f in $Faits) {
        $etrangers = @(Get-CtxProp $f 'Etrangers')
        if ($etrangers.Count -eq 0) { continue }

        $liste = ($etrangers | ForEach-Object { "$($_.Login) ($($_.Contexte))" }) -join ', '
        $checks += New-CtxCheck -Domaine 'editeur' -Sujet "comptes/$($f.Contexte)" -Verdict 'PROBLEME' `
            -Detail (T 'doc.editeur.compteEtranger' $f.Contexte $liste $f.Attendu) `
            -Correctif (T 'doc.editeur.compteEtrangerFix')
    }
    @($checks)
}

function Test-CtxDoctorEditeurConnexions {
    <#
      PURE. La CONSEQUENCE d'un profil isole sur les connexions, enoncee une
      fois -- plutot que devinee editeur par editeur.

      LE PROBLEME QU'ELLE REGLE

      Le rapport disait "profil et extensions par contexte -- OK", ce qui se lit
      "tout est en place". VS Code affichait pourtant "Sign in to GitHub" dans la
      fenetre du contexte, et la conclusion naturelle etait que l'isolation avait
      echoue. Elle avait au contraire parfaitement fonctionne : un profil par
      contexte, c'est un magasin de secrets par contexte, donc une connexion a
      ouvrir une fois dans chacun. Mesure le 17 aout 2026 sur le contexte
      goldteam.

      POURQUOI L'ETAT REEL N'EST PAS MESURE

      Tentative faite le meme jour, et abandonnee sur mesure. VS Code chiffre ses
      sessions (DPAPI) dans le state.vscdb du profil, une base SQLite. La chaine
      'github-authentication' y apparait dans les DEUX cas -- profil connecte et
      profil qui ne l'a jamais ete -- car l'extension ecrit ses cles quoi qu'il
      arrive : 10 occurrences cote connecte, 11 cote non connecte. Le marqueur ne
      distingue donc rien.

      Lire la base pour de vrai demanderait un pilote SQLite, c'est-a-dire une
      dependance, dans un module qui n'en a aucune -- et elle serait chargee a
      chaque `ctx doctor` pour une ligne d'information.

      Alors on enonce ce qui est VRAI SANS MESURE, au lieu d'afficher un verdict
      auquel on ne pourrait pas se fier. Un diagnostic qui se trompe une fois sur
      deux est pire qu'un diagnostic absent : il enseigne a ne plus le lire.

      Rend $null quand aucun editeur n'est isole : la phrase serait alors fausse.
    #>
    [CmdletBinding()]
    param([object[]]$Editeurs = @())

    # Sur le champ BOOLEEN, jamais sur le libelle affiche : celui-ci est traduit.
    # Meme piege que la boucle appelante, et il a deja frappe quatre fois.
    if (@($Editeurs | Where-Object { $_.Isole }).Count -eq 0) { return }

    New-CtxCheck -Domaine 'editeur' -Sujet 'connexions' -Verdict 'INFO' `
        -Detail (T 'doc.editeur.connexions')
}

function Get-CtxPathUtilisateur {
    <#
      GATHERING. Les entrees du PATH UTILISATEUR, lues au registre.

      $env:PATH ne convient pas : il est la CONCATENATION du systeme et de
      l'utilisateur, et la question posee ici est precisement de savoir dans
      laquelle des deux moities un dossier se trouve.

      Lecture BRUTE (DoNotExpandEnvironmentNames) : un PATH utilisateur peut
      etre un REG_EXPAND_SZ contenant %USERPROFILE%, et le developper ici
      comparerait un chemin developpe a un chemin qui ne l'est pas.

      Rend un tableau vide plutot que de lever : un diagnostic qui plante est
      moins utile qu'un diagnostic qui repond "je ne sais pas".
    #>
    [CmdletBinding()]
    param()
    try {
        $cle = Get-Item 'HKCU:\Environment' -ErrorAction Stop
        $brut = $cle.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        @($brut -split ';' | Where-Object { $_.Trim() })
    }
    catch { @() }
}

function Resolve-CtxMasqueCorrectif {
    <#
      PURE. Quel correctif proposer pour un binaire qui masque notre shim ?

      Deux situations, et leurs couts n'ont rien de comparable :

        'retrait-systeme'    -- le dossier du binaire est AUSSI dans le PATH
            utilisateur, apres nos shims. Le retirer du PATH SYSTEME suffit
            alors : le shim passe premier, et le vrai binaire reste joignable
            par l'entree utilisateur. Rien n'est reinstalle, rien n'est
            desinstalle, et la manoeuvre s'annule en recollant une ligne.

        'portee-utilisateur' -- il n'est QUE dans le PATH systeme. Il faut
            alors reinstaller l'outil en portee utilisateur, ou ajouter son
            dossier au PATH utilisateur derriere nos shims.

      Le 17 aout 2026, `gh` etait dans le PREMIER cas et le diagnostic
      conseillait le second : une reinstallation pour un probleme que le retrait
      d'une entree redondante reglait. Un correctif trop cher est un correctif
      qu'on ne applique pas.

      Comparaison normalisee -- casse et barre oblique finale : Windows ecrit
      indifferemment 'C:\Program Files\GitHub CLI' et 'C:\Program Files\GitHub CLI\',
      et les deux designent le meme dossier.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Dossier,
        [string[]]$PathUtilisateur = @()
    )

    if ([string]::IsNullOrWhiteSpace($Dossier)) { return 'portee-utilisateur' }

    $cible = $Dossier.Trim().TrimEnd('\').ToLowerInvariant()
    $entrees = @($PathUtilisateur | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('\').ToLowerInvariant() })

    if ($entrees -contains $cible) { 'retrait-systeme' } else { 'portee-utilisateur' }
}

function Test-CtxDoctorWsl {
    <#
      WSL is a hole, and saying so is the only honest thing to do about it.

      A Linux distribution carries its own PATH and its own filesystem view --
      /mnt/c, not /c -- so the Windows shim is simply not on it. Anything run
      from a WSL shell reaches the real CLI directly, with no guard in the way.

      Nothing here can close that; the fix belongs on the Linux side. What this
      does is make a known limitation visible, because the dangerous version of
      this gap is the one nobody has been told about. Returns nothing at all
      when no distribution is installed: a warning about software you do not
      have is noise, and noise is how a report stops being read.
    #>
    $cle = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -LiteralPath $cle)) { return }

    $distros = @(Get-ChildItem -LiteralPath $cle -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^\{' })
    if ($distros.Count -eq 0) { return }

    $tous = @($distros | ForEach-Object {
            (Get-ItemProperty -LiteralPath $_.PSPath -Name 'DistributionName' -ErrorAction SilentlyContinue).DistributionName
        } | Where-Object { $_ })

    $noms = @($tous | Where-Object { -not (Test-CtxDistroTechnique $_) })
    if ($noms.Count -eq 0) { return }

    New-CtxCheck -Domaine 'garde-fou' -Sujet 'WSL' -Verdict 'ATTENTION' `
        -Detail (T 'doc.wsl.distros' $noms.Count ($noms -join ', ')) `
        -Correctif (T 'doc.wsl.fix')
}

function Test-CtxDistroTechnique {
    <#
      PURE. Cette distribution WSL est-elle une machinerie interne, ou un shell
      dans lequel quelqu'un tape des commandes ?

      Docker Desktop installe docker-desktop et docker-desktop-data. Personne n y
      ouvre un terminal pour lancer `supabase db reset`, et les compter revenait
      a dire « 2 distributions » a quelqu'un qui n en a installe qu'une. Un
      diagnostic qui gonfle ses chiffres perd la confiance qui le rend utile --
      la meme raison qui fait regrouper les raccourcis des editeurs.

      La liste est courte et nommee : mieux vaut laisser passer une distribution
      technique inconnue -- l'avertissement reste vrai, juste trop prudent -- que
      d'ecarter par heuristique le shell Ubuntu de quelqu'un.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Nom)

    if (-not $Nom) { return $true }
    $Nom.ToLowerInvariant() -in @(
        'docker-desktop', 'docker-desktop-data',
        'rancher-desktop', 'rancher-desktop-data',
        'podman-machine-default'
    )
}
