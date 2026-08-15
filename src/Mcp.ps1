# ---------------------------------------------------------------------------
# ctx mcp -- give a project its own MCP servers, bound to the folder's account
# ---------------------------------------------------------------------------
#
# THE PROBLEM
#
# MCP servers are declared machine-wide, and the popular ones authenticate by
# OAuth. Both facts point the same way: every project inherits whichever account
# the human connected last. Working on a personal project therefore meant going
# to claude.ai and reconnecting Supabase and Vercel, then reconnecting them back
# for client work. The connection is a property of the account, so no amount of
# care with folders changes it.
#
# THE WAY OUT
#
# The Supabase MCP server still ships a local stdio transport, and it resolves
# its token like this (packages/mcp-server-supabase/src/transports/stdio.ts):
#
#     const accessToken = cliAccessToken ?? process.env.SUPABASE_ACCESS_TOKEN;
#
# That environment variable is exactly what `work` exports, resolved from the
# FOLDER by Sync-CtxSupabaseEnv. So a project-scoped .mcp.json can carry no
# secret at all and still reach the right account: the token arrives through
# process inheritance, decided by where you stand.
#
# WHY NO env BLOCK IS WRITTEN
#
# Writing "env": { "SUPABASE_ACCESS_TOKEN": "${SUPABASE_ACCESS_TOKEN}" } looks
# more explicit, and is worse. When the variable is unset the expansion yields
# an EMPTY STRING, which the CLI reads as "a token was supplied and it is
# invalid" -- the precise trap Set-CtxSupabaseToken documents in this module.
# Plain inheritance makes an absent token absent, and the error then names the
# real problem.
#
# Claude Code expands ${VAR} and ${VAR:-default} in command, args, env, url and
# headers, which is what makes the header form below safe to commit.

# ---------------------------------------------------------------------------
# Where each client keeps its project-scoped MCP configuration
# ---------------------------------------------------------------------------
#
# MCP is an open standard; the file that declares it is not. Each client picked
# its own location and its own root key, so a generator that only wrote
# .mcp.json would tie this module to one assistant -- which is the exact kind of
# lock-in it exists to remove. The identity belongs to the FOLDER, and so must
# work whichever assistant the developer opens it with, this year or next.
#
# Only PROJECT-scoped files appear here. A client that stores its servers in a
# machine-wide profile cannot be bound to a folder, and listing it would promise
# something this module cannot deliver.

$script:McpClients = [ordered]@{
    'claude' = @{
        Fichier = '.mcp.json'
        Cle     = 'mcpServers'
        Libelle = 'Claude Code'
    }
    'vscode' = @{
        Fichier = '.vscode/mcp.json'
        Cle     = 'servers'      # VS Code says "servers", not "mcpServers"
        Libelle = 'VS Code'
    }
    'cursor' = @{
        Fichier = '.cursor/mcp.json'
        Cle     = 'mcpServers'
        Libelle = 'Cursor'
    }
}

# ---------------------------------------------------------------------------
# Pure builders
# ---------------------------------------------------------------------------

function New-CtxMcpServeurSupabase {
    <#
      Read-only unless asked otherwise, and read-only WITHOUT APPEAL on a
      project marked production. Same doctrine as the CLI guard: an agent that
      can write to production is a bad afternoon waiting for its turn, and here
      the cost of the restriction is close to nothing.
    #>
    param(
        [Parameter(Mandatory)][string]$Ref,
        [switch]$Ecriture,
        [switch]$Production
    )
    $arguments = @('-y', '@supabase/mcp-server-supabase@latest', "--project-ref=$Ref")
    if ($Production -or -not $Ecriture) { $arguments += '--read-only' }
    [ordered]@{ command = 'npx'; args = $arguments }
}

function New-CtxMcpServeurGitHub {
    <#
      The token is deferred to the environment, which `work` fills from the
      context vault, so the file itself holds no secret and can be committed.

      The expansion SYNTAX differs per client, and getting it wrong is silent:
      Claude Code reads ${VAR}, while VS Code and Cursor read ${env:VAR} and
      would send the literal text as a bearer token. Nothing complains -- the
      request simply comes back 401, with an error blaming the credential rather
      than the notation. Caught by the audit of 15 Aug 2026.
    #>
    param([string]$Client = 'claude')

    $reference = if ($Client -eq 'claude') { '${GH_TOKEN}' } else { '${env:GH_TOKEN}' }
    [ordered]@{
        type    = 'http'
        url     = 'https://api.githubcopilot.com/mcp/'
        headers = [ordered]@{ Authorization = "Bearer $reference" }
    }
}

function Merge-CtxMcpConfig {
    <#
      Merges generated servers into an existing configuration.

      Never overwrites without -Force, and never drops a key it does not
      understand: this file belongs to the project, and a generator that eats
      hand-written entries is a generator nobody runs twice.

      Returns the merged object plus what was added, kept and replaced, so the
      caller can say what it did rather than claim success.
    #>
    param(
        [AllowNull()]$Existant,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Nouveaux,
        [string]$Cle = 'mcpServers',
        [switch]$Force
    )

    $fusion = [ordered]@{}
    $serveurs = [ordered]@{}

    # Get-CtxPaires des deux cotes, et surtout PAS Get-CtxProp : celui-ci
    # navigue par PSObject.Properties, qui ne voit aucune entree dans une table
    # de hachage — or ConvertFrom-Json -AsHashtable en rend une, et c'est la
    # seule lecture possible d'un .claude.json. La fusion aurait ignore en
    # silence tous les serveurs deja declares, puis les aurait ecrases.
    if ($Existant) {
        $blocServeurs = $null
        foreach ($p in (Get-CtxPaires $Existant)) {
            if ($p.Name -eq $Cle) { $blocServeurs = $p.Value; continue }
            $fusion[$p.Name] = $p.Value
        }
        foreach ($p in (Get-CtxPaires $blocServeurs)) { $serveurs[$p.Name] = $p.Value }
    }

    $ajoutes = @(); $conserves = @(); $remplaces = @()
    foreach ($k in $Nouveaux.Keys) {
        if (-not $serveurs.Contains($k)) { $serveurs[$k] = $Nouveaux[$k]; $ajoutes += $k }
        elseif ($Force)                  { $serveurs[$k] = $Nouveaux[$k]; $remplaces += $k }
        else                             { $conserves += $k }
    }

    $fusion[$Cle] = $serveurs
    [pscustomobject]@{
        Config    = $fusion
        Ajoutes   = $ajoutes
        Conserves = $conserves
        Remplaces = $remplaces
    }
}

# ---------------------------------------------------------------------------
# New-DevProjectMcp
# ---------------------------------------------------------------------------

function New-DevProjectMcp {
    <#
    .SYNOPSIS
        Writes project-scoped MCP configuration bound to this folder's account.

    .DESCRIPTION
        Declares the MCP servers this project can reach, taking their
        credentials from the environment DevContext already fills from the
        folder. No secret is written, so the files can be committed, and the
        account follows the project instead of following whoever logged in last.

        Assistant-agnostic on purpose. MCP is an open standard, and being tied
        to one vendor's account is the problem this module exists to remove --
        so being tied to one vendor's TOOL would be the same mistake wearing a
        different hat. Claude Code, VS Code and Cursor each get their own file,
        in their own format.

        Only servers whose prerequisites are actually present are declared:
        Supabase when the folder is linked to a project, GitHub when a token is
        loaded. A server that cannot authenticate is worse than an absent one --
        it fails later, and less clearly.

        Existing entries are kept unless -Force is given.

    .PARAMETER Path
        Project folder. Defaults to the current one.

    .PARAMETER Client
        Which assistants to configure: claude, vscode, cursor. Without it, the
        folder decides -- clients already present are refreshed, absent ones are
        left alone rather than installed on someone's behalf.

    .PARAMETER Ecriture
        Allows the Supabase server to mutate. Ignored on a production project,
        which stays read-only.

    .PARAMETER Force
        Replaces servers of the same name that are already declared.

    .EXAMPLE
        ctx-mcp -Client claude

    .EXAMPLE
        ctx-mcp -Client claude, cursor -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = (Get-Location).Path,
        [ValidateSet('claude', 'vscode', 'cursor')][string[]]$Client,
        [switch]$Ecriture,
        [switch]$Force
    )

    $dossier = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $manifeste = Resolve-DevContextForPath -Path $dossier
    $contexte  = if ($manifeste) { Get-CtxProp $manifeste 'name' } else { $null }

    $nouveaux = [ordered]@{}
    $ignores  = [System.Collections.Generic.List[string]]::new()

    # --- Supabase ----------------------------------------------------------
    $ref = Resolve-CtxSupabaseRef -Path $dossier
    if (-not $ref) {
        $ignores.Add('supabase : ce dossier n est lie a aucun projet (supabase link)')
    }
    else {
        $envProjet = if ($contexte) { Get-CtxSupabaseEnv -Ref $ref -ContextName $contexte } else { $null }
        $estProd = $envProjet -eq 'prod'
        $nouveaux['supabase'] = New-CtxMcpServeurSupabase -Ref $ref -Ecriture:$Ecriture -Production:$estProd
        if ($estProd -and $Ecriture) {
            Write-Warning "Projet de production : le serveur reste en lecture seule malgre -Ecriture."
        }
    }

    # --- GitHub ------------------------------------------------------------
    # Construit par client plus bas : la syntaxe d'expansion n'est pas la meme
    # partout. Ici on note seulement s'il y a lieu de le declarer.
    $avecGitHub = [bool]$env:GH_TOKEN
    if (-not $avecGitHub) {
        $ignores.Add('github : aucun GH_TOKEN charge — `work <contexte>` d abord, ou le coffre n a pas de cle github-token')
    }

    if ($nouveaux.Count -eq 0 -and -not $avecGitHub) {
        Write-Warning "Rien a declarer pour ce dossier."
        foreach ($i in $ignores) { Write-Host "    $i" -ForegroundColor DarkGray }
        return
    }

    # Avant la bifurcation ShouldProcess : ce qui a ete ECARTE est la moitie
    # utile du rapport, et -WhatIf est precisement le mode ou on veut la lire.
    foreach ($i in $ignores) { Write-Host "  ignore : $i" -ForegroundColor DarkGray }

    # @() obligatoire : sans client detecte la fonction ne rend RIEN, et sous
    # StrictMode lire .Count sur $null leve — donc le cas « rien a faire »
    # plantait au lieu de le dire.
    $cibles = @(Resolve-CtxMcpCibles -Dossier $dossier -Client $Client)
    if ($cibles.Count -eq 0) {
        Write-Warning "Aucun client MCP detecte dans ce dossier. Preciser -Client pour en creer un : $($script:McpClients.Keys -join ', ')"
        return
    }

    Write-Host ''
    foreach ($c in $cibles) {
        $existant = $null
        if (Test-Path -LiteralPath $c.Chemin) {
            $existant = try { Get-Content -LiteralPath $c.Chemin -Raw | ConvertFrom-Json -AsHashtable }
                        catch { throw "$($c.Chemin) existant illisible : $(Protect-CtxMessage $_.Exception.Message). Le corriger ou le deplacer avant de regenerer." }
        }

        # Copie par client : le serveur GitHub porte une syntaxe d'expansion
        # differente selon l'assistant.
        $pourCeClient = [ordered]@{}
        foreach ($k in $nouveaux.Keys) { $pourCeClient[$k] = $nouveaux[$k] }
        if ($avecGitHub) { $pourCeClient['github'] = New-CtxMcpServeurGitHub -Client $c.Nom }

        $resultat = Merge-CtxMcpConfig -Existant $existant -Nouveaux $pourCeClient -Cle $c.Cle -Force:$Force
        $json = $resultat.Config | ConvertTo-Json -Depth 8

        if (-not $PSCmdlet.ShouldProcess($c.Chemin, "ecrire la configuration MCP ($($c.Libelle))")) {
            Write-Host "  $($c.Libelle) — $($c.Chemin)" -ForegroundColor Cyan
            Write-Host $json
            Write-Host ''
            continue
        }

        New-Item -ItemType Directory -Path (Split-Path $c.Chemin -Parent) -Force | Out-Null
        Set-Content -LiteralPath $c.Chemin -Value $json -Encoding UTF8

        Write-Host "  $($c.Libelle) — $($c.Chemin)" -ForegroundColor Green
        if ($resultat.Ajoutes.Count)   { Write-Host "    ajoutes   : $($resultat.Ajoutes -join ', ')" -ForegroundColor Green }
        if ($resultat.Remplaces.Count) { Write-Host "    remplaces : $($resultat.Remplaces -join ', ')" -ForegroundColor Yellow }
        if ($resultat.Conserves.Count) {
            Write-Host "    conserves : $($resultat.Conserves -join ', ') (-Force pour les remplacer)" -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host '  Aucun secret dans ces fichiers : les jetons viennent de l environnement,' -ForegroundColor DarkGray
    Write-Host '  donc du contexte du dossier. Ils peuvent etre commites.' -ForegroundColor DarkGray
    Write-Host '  Lancer l assistant depuis un terminal ou `work` a ete execute.' -ForegroundColor DarkGray
    Write-Host ''
}

function Resolve-CtxMcpCibles {
    <#
      Which client configurations to write.

      Without -Client, the folder decides: a client already present gets its
      file refreshed, and one that is not present is left alone. Writing a
      .cursor/ into a repository whose team does not use Cursor would be this
      module littering someone else's project -- and it is a shared, committed
      file, so the mess spreads on the next pull.

      When nothing is detected, nothing is written and the caller is told to
      name a client. Guessing would install an assistant's configuration on
      behalf of a developer who never asked for that assistant.
    #>
    param(
        [Parameter(Mandatory)][string]$Dossier,
        [string[]]$Client
    )

    $noms = if ($Client) { $Client } else { $script:McpClients.Keys }

    foreach ($nom in $noms) {
        $def = $script:McpClients[$nom]
        if (-not $def) { throw "Client MCP inconnu : '$nom'. Connus : $($script:McpClients.Keys -join ', ')" }

        $chemin = Join-Path $Dossier ($def.Fichier -replace '/', '\')
        # Sans -Client, on ne sert que les clients deja presents dans le dossier.
        if (-not $Client -and -not (Test-Path -LiteralPath $chemin)) { continue }

        [pscustomobject]@{
            Nom = $nom; Chemin = $chemin; Cle = $def.Cle; Libelle = $def.Libelle
        }
    }
}
