# ---------------------------------------------------------------------------
# ctx doctor -Live -- does this token work, and does it open the RIGHT account?
# ---------------------------------------------------------------------------
#
# Without the network, a diagnostic can only say a token is LOADED. That is the
# cheap half of the question. The expensive half -- is it still valid, does it
# belong to the account this folder expects, does it carry the rights the work
# needs -- has until now been answered by a command failing mid-task, or worse,
# by succeeding against the wrong account.
#
# Three rules hold everywhere below.
#
# 1. OPT-IN. A diagnostic that silently calls the network is a diagnostic people
#    stop running. -Live is explicit, and every call is a read-only identity
#    probe: whoami, list projects. Nothing is created, changed or deleted.
#
# 2. THE TOKEN NEVER COMES BACK OUT. Not in a verdict, not in an error, not in
#    a URL. Every message crosses Protect-CtxMessage on its way to the report,
#    because a report is pasted into chats and committed into logs.
#
# 3. FAILING IS AN ANSWER, NOT A CRASH. An unreachable network is INFO -- it
#    says nothing about the token. A 401 is a PROBLEM -- it says the token is
#    dead. Confusing the two would make the tool cry wolf on a train.

$script:JetonTimeout = 8

# ---------------------------------------------------------------------------
# Redaction
# ---------------------------------------------------------------------------

function Protect-CtxMessage {
    <#
      Removes anything that looks like a credential from a string on its way
      into a report.

      This is a last line, not the first: nothing here is supposed to put a
      token in a message. It exists because "supposed to" is what leaked the
      Vercel bypass token into a browser URL on 24 Apr 2026, and because an HTTP
      library is free to quote a request line we never inspected.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Message)

    if ([string]::IsNullOrEmpty($Message)) { return $Message }

    $motifs = @(
        'sbp_[A-Za-z0-9_\-]+', 'sbs_[A-Za-z0-9_\-]+', 'sb_secret_[A-Za-z0-9_\-]+',
        'gh[pousr]_[A-Za-z0-9_\-]+', 'github_pat_[A-Za-z0-9_\-]+',
        'sk-[A-Za-z0-9_\-]{16,}',
        'xox[baprs]-[A-Za-z0-9\-]+',
        'ya29\.[A-Za-z0-9_\-]+', 'AIza[A-Za-z0-9_\-]{20,}',
        '(AKIA|ASIA)[A-Z0-9]{12,}',
        # Bearer <anything>, whatever the issuer: the shape is the tell.
        '(?i)(bearer|token|access[_-]?token|api[_-]?key)\s*[:=]?\s*[A-Za-z0-9_\-\.]{16,}'
    )
    $sortie = $Message
    foreach ($m in $motifs) { $sortie = [regex]::Replace($sortie, $m, '<REDACTED>') }
    $sortie
}

# ---------------------------------------------------------------------------
# Pure decisions
# ---------------------------------------------------------------------------

function Test-CtxDoctorJetonGitHub {
    <#
      The interesting failure is not "the token is dead". It is "the token is
      alive and belongs to someone else" -- a working credential for the wrong
      account is exactly what this whole module exists to prevent, and it is the
      one case a token check that only asks "is it valid" would bless.
    #>
    param(
        [AllowNull()][string]$LoginAttendu,
        [AllowNull()][string]$LoginReel,
        [AllowNull()][string]$Portees,
        [int]$Code = 0,
        [AllowNull()][string]$Erreur
    )

    if ($Code -eq 401) {
        return New-CtxCheck -Domaine 'gh' -Sujet 'jeton' -Verdict 'PROBLEME' `
            -Detail 'jeton refuse (401) : expire ou revoque' `
            -Correctif 'gh auth login  (dans un terminal ou work a ete execute)'
    }
    if (-not $LoginReel) {
        return New-CtxCheck -Domaine 'gh' -Sujet 'jeton' -Verdict 'INFO' `
            -Detail ('non verifie : ' + (Protect-CtxMessage $Erreur))
    }
    if ($LoginAttendu -and $LoginReel -ne $LoginAttendu) {
        return New-CtxCheck -Domaine 'gh' -Sujet 'jeton' -Verdict 'PROBLEME' `
            -Detail "le jeton ouvre le compte '$LoginReel', ce dossier attend '$LoginAttendu'" `
            -Correctif 'GH_CONFIG_DIR pointe sur le mauvais contexte, ou ce contexte est connecte au mauvais compte'
    }

    $detail = "valide — $LoginReel"
    if ($Portees) { $detail += " (portees : $Portees)" }
    New-CtxCheck -Domaine 'gh' -Sujet 'jeton' -Verdict 'OK' -Detail $detail
}

function Test-CtxDoctorJetonSupabase {
    <#
      Listing the projects a token can see answers three questions at once: the
      token is valid, it belongs to a given account, and that account owns the
      project THIS folder is linked to. A whoami would only answer the first.
    #>
    param(
        [AllowNull()][string]$RefAttendu,
        [object[]]$Projets = @(),
        [int]$Code = 0,
        [AllowNull()][string]$Erreur
    )

    if ($Code -eq 401 -or $Code -eq 403) {
        return New-CtxCheck -Domaine 'supabase' -Sujet 'jeton' -Verdict 'PROBLEME' `
            -Detail "jeton refuse ($Code) : expire, revoque, ou sans droit sur l organisation" `
            -Correctif 'regenerer le jeton sur supabase.com/dashboard/account/tokens, puis le poser dans le coffre'
    }
    if ($Code -eq 0 -and $Erreur) {
        return New-CtxCheck -Domaine 'supabase' -Sujet 'jeton' -Verdict 'INFO' `
            -Detail ('non verifie : ' + (Protect-CtxMessage $Erreur))
    }
    if (-not $RefAttendu) {
        return New-CtxCheck -Domaine 'supabase' -Sujet 'jeton' -Verdict 'OK' `
            -Detail "valide — $($Projets.Count) projet(s) visible(s)"
    }

    $vise = @($Projets | Where-Object { (Get-CtxProp $_ 'id') -eq $RefAttendu }) | Select-Object -First 1
    if (-not $vise) {
        # Ce cas EST le scenario redoute, dans l'autre sens : le jeton marche,
        # mais pas sur le projet de ce dossier. Une commande partirait alors sur
        # un compte reel, avec un message d'erreur qui ne dit pas pourquoi.
        return New-CtxCheck -Domaine 'supabase' -Sujet 'jeton' -Verdict 'PROBLEME' `
            -Detail "jeton valide, mais le projet lie a ce dossier n y est pas visible" `
            -Correctif 'sb-index — puis work <contexte> pour recharger la bonne cle'
    }
    New-CtxCheck -Domaine 'supabase' -Sujet 'jeton' -Verdict 'OK' `
        -Detail "valide — acces confirme a $(Get-CtxProp $vise 'name' $RefAttendu)"
}

function Test-CtxDoctorJetonVercel {
    param(
        [AllowNull()][string]$Utilisateur,
        [int]$Code = 0,
        [AllowNull()][string]$Erreur
    )
    if ($Code -eq 401 -or $Code -eq 403) {
        return New-CtxCheck -Domaine 'vercel' -Sujet 'jeton' -Verdict 'PROBLEME' `
            -Detail "jeton refuse ($Code)" `
            -Correctif 'vercel login  (dans un terminal ou work a ete execute)'
    }
    if (-not $Utilisateur) {
        return New-CtxCheck -Domaine 'vercel' -Sujet 'jeton' -Verdict 'INFO' `
            -Detail ('non verifie : ' + (Protect-CtxMessage $Erreur))
    }
    New-CtxCheck -Domaine 'vercel' -Sujet 'jeton' -Verdict 'OK' -Detail "valide — $Utilisateur"
}

# ---------------------------------------------------------------------------
# Network access
# ---------------------------------------------------------------------------

function Invoke-CtxApi {
    <#
      One read-only GET, with a timeout, returning a verdict-shaped object
      instead of throwing.

      The status code is what the decisions branch on, so it is carried
      separately from the message: 401 means the token is dead, a timeout means
      only that a train went into a tunnel. Treating both as failure would make
      the tool untrustworthy in exactly the situation where trust matters.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = $script:JetonTimeout
    )
    try {
        $data = Invoke-RestMethod -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec `
            -Method Get -ErrorAction Stop
        [pscustomobject]@{ Ok = $true; Data = $data; Code = 200; Erreur = $null }
    }
    catch {
        $code = 0
        $reponse = $_.Exception.PSObject.Properties['Response']
        if ($reponse -and $_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
        }
        [pscustomobject]@{
            Ok = $false; Data = $null; Code = $code
            Erreur = (Protect-CtxMessage $_.Exception.Message)
        }
    }
}

function Get-CtxJetonChecks {
    <#
      Probes every token loaded in this shell. Absent tokens are skipped in
      silence: the non-live pass has already said they are missing, and saying
      it twice trains the reader to skim.
    #>
    param(
        [AllowNull()]$Manifeste,
        [AllowNull()][string]$Ref
    )

    $checks = [System.Collections.Generic.List[object]]::new()

    # --- GitHub ------------------------------------------------------------
    # Via la CLI et non l'API brute : elle lit GH_CONFIG_DIR, donc elle prouve
    # ce qui compte vraiment — l'identite que `gh` utilisera reellement ici.
    if (Get-Command gh -CommandType Application -ErrorAction SilentlyContinue) {
        $login = $null; $portees = $null; $code = 0; $erreur = $null
        $brut = & gh api user --jq '.login' 2>&1
        if ($LASTEXITCODE -eq 0) {
            $login = ([string]$brut).Trim()
            $entetes = & gh api -i user 2>&1 | Select-String -Pattern '^X-OAuth-Scopes:' | Select-Object -First 1
            if ($entetes) { $portees = ($entetes.Line -replace '^X-OAuth-Scopes:\s*', '').Trim() }
        }
        else {
            $erreur = Protect-CtxMessage (($brut | Out-String).Trim())
            if ($erreur -match 'HTTP 401|Bad credentials') { $code = 401 }
        }
        $checks.Add((Test-CtxDoctorJetonGitHub `
            -LoginAttendu (Get-CtxProp $Manifeste 'github.login') `
            -LoginReel $login -Portees $portees -Code $code -Erreur $erreur))
    }

    # --- Supabase ----------------------------------------------------------
    if ($env:SUPABASE_ACCESS_TOKEN) {
        $r = Invoke-CtxApi -Uri 'https://api.supabase.com/v1/projects' `
            -Headers @{ Authorization = "Bearer $env:SUPABASE_ACCESS_TOKEN" }
        $checks.Add((Test-CtxDoctorJetonSupabase -RefAttendu $Ref `
            -Projets @($r.Data) -Code $r.Code -Erreur $r.Erreur))
    }

    # --- Vercel ------------------------------------------------------------
    if ($env:VERCEL_TOKEN) {
        $r = Invoke-CtxApi -Uri 'https://api.vercel.com/v2/user' `
            -Headers @{ Authorization = "Bearer $env:VERCEL_TOKEN" }
        $utilisateur = if ($r.Ok) { Get-CtxProp $r.Data 'user.username' } else { $null }
        $checks.Add((Test-CtxDoctorJetonVercel -Utilisateur $utilisateur -Code $r.Code -Erreur $r.Erreur))
    }

    $checks
}
