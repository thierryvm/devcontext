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

$script:McpFichier = '.mcp.json'

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
    # ${GH_TOKEN} is expanded by Claude Code from the environment, which `work`
    # fills from the context vault. The file itself stays free of any secret and
    # can be committed.
    [ordered]@{
        type    = 'http'
        url     = 'https://api.githubcopilot.com/mcp/'
        headers = [ordered]@{ Authorization = 'Bearer ${GH_TOKEN}' }
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
            if ($p.Name -eq 'mcpServers') { $blocServeurs = $p.Value; continue }
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

    $fusion['mcpServers'] = $serveurs
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
        Writes a project-scoped .mcp.json bound to this folder's account.

    .DESCRIPTION
        Declares the MCP servers this project can reach, taking their
        credentials from the environment DevContext already fills from the
        folder. No secret is written, so the file can be committed, and the
        account follows the project instead of following whoever logged in last.

        Only servers whose prerequisites are actually present are declared:
        Supabase when the folder is linked to a project, GitHub when a token is
        loaded. A server that cannot authenticate is worse than an absent one --
        it fails later, and less clearly.

        Existing entries are kept unless -Force is given.

    .PARAMETER Path
        Project folder. Defaults to the current one.

    .PARAMETER Ecriture
        Allows the Supabase server to mutate. Ignored on a production project,
        which stays read-only.

    .PARAMETER Force
        Replaces servers of the same name that are already declared.

    .EXAMPLE
        ctx-mcp

    .EXAMPLE
        ctx-mcp -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = (Get-Location).Path,
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
    if ($env:GH_TOKEN) { $nouveaux['github'] = New-CtxMcpServeurGitHub }
    else { $ignores.Add('github : aucun GH_TOKEN charge — `work <contexte>` d abord, ou le coffre n a pas de cle github-token') }

    if ($nouveaux.Count -eq 0) {
        Write-Warning "Rien a declarer pour ce dossier."
        foreach ($i in $ignores) { Write-Host "    $i" -ForegroundColor DarkGray }
        return
    }

    $cible    = Join-Path $dossier $script:McpFichier
    $existant = $null
    if (Test-Path -LiteralPath $cible) {
        $existant = try { Get-Content -LiteralPath $cible -Raw | ConvertFrom-Json -AsHashtable }
                    catch { throw "$script:McpFichier existant illisible : $($_.Exception.Message). Le corriger ou le deplacer avant de regenerer." }
    }

    $resultat = Merge-CtxMcpConfig -Existant $existant -Nouveaux $nouveaux -Force:$Force
    $json = $resultat.Config | ConvertTo-Json -Depth 8

    # Avant la bifurcation ShouldProcess : ce qui a ete ECARTE est la moitie
    # utile du rapport, et -WhatIf est precisement le mode ou on veut la lire.
    foreach ($i in $ignores) { Write-Host "  ignore : $i" -ForegroundColor DarkGray }

    if (-not $PSCmdlet.ShouldProcess($cible, 'ecrire la configuration MCP du projet')) {
        Write-Host ''
        Write-Host $json
        return
    }

    Set-Content -LiteralPath $cible -Value $json -Encoding UTF8

    Write-Host ''
    Write-Host "  $script:McpFichier ecrit" -ForegroundColor Green
    Write-Host "    $cible"
    if ($resultat.Ajoutes.Count)   { Write-Host "    ajoutes   : $($resultat.Ajoutes -join ', ')" -ForegroundColor Green }
    if ($resultat.Remplaces.Count) { Write-Host "    remplaces : $($resultat.Remplaces -join ', ')" -ForegroundColor Yellow }
    if ($resultat.Conserves.Count) {
        Write-Host "    conserves : $($resultat.Conserves -join ', ')" -ForegroundColor DarkGray
        Write-Host "                (-Force pour les remplacer)" -ForegroundColor DarkGray
    }
    foreach ($i in $ignores) { Write-Host "    ignore    : $i" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '  Aucun secret dans ce fichier : les jetons viennent de l environnement,' -ForegroundColor DarkGray
    Write-Host '  donc du contexte du dossier. Il peut etre commite.' -ForegroundColor DarkGray
    Write-Host '  Lancer Claude Code depuis un terminal ou `work` a ete execute.' -ForegroundColor DarkGray
    Write-Host ''
}
