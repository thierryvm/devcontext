# ---------------------------------------------------------------------------
# ctx secret <cle> -- poser, remplacer ou retirer UN secret, plus tard
# ---------------------------------------------------------------------------
#
# THE GAP THIS CLOSES
#
# A token could be typed in one place only: the prompts of `ctx new`. Skipped
# there, or created later, it had to go in through a raw
#     Set-Secret -Vault DevContext -Name 'devctx/<ctx>/<key>' -SecureStringSecret $s
# which the module itself printed as the "non-interactive" advice. That line
# bypasses everything Read-CtxJeton exists for: on 8 November 2026 a masked
# paste reached the vault as ONE character, and the fix was a validated prompt.
# Advising a command that skips it would have kept the incident's door open,
# one documented step to the side.
#
# So: one key at a time, the same validated prompt, and the same refusal of a
# redirected input as `ctx new` -- a prompt nobody can answer is a hang.
#
# WHAT IT NEVER DOES
#
# Print the value, take it as an argument, or overwrite an existing value
# without asking. A value passed on the command line lands in the PSReadLine
# history file in clear; the only way in is the masked prompt.

# Le nom d'un contexte, tel que `ctx new` l'impose. Le nom entre dans le chemin
# du manifeste ET dans le nom du secret au coffre : un '..' ou un '/' y
# designerait autre chose que ce que l'utilisateur croit viser.
$script:CtxNomContexteMotif = '^[a-z0-9][a-z0-9-]*$'

function Get-CtxVerdictSecret {
    <#
      PURE. Peut-on demander ce secret ? Rend une table @{ Etat; Cle; Jeton } :

        cle-absente       aucune cle donnee : l'appelant affiche l'usage
        cle-inconnue      pas une cle de $script:SecretMap
        entree-redirigee  personne ne peut repondre a une invite
        sans-contexte     ni -Name ni contexte actif
        contexte-invalide le nom n'a pas la forme qu'impose `ctx new`
        ok                Cle porte l'orthographe canonique de la table

      Jeton : la cle inconnue RESSEMBLE a une valeur de secret. L'appelant ne
      la repete jamais -- une cle inconnue n'est jamais affichee, car c'est
      exactement la qu'atterrit un jeton colle au mauvais endroit.

      L'ordre compte : la cle se juge sans rien demander a personne, et la
      redirection passe AVANT tout acces au coffre, qui demanderait son mot de
      passe a une entree que personne ne lit.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Key,
        [Parameter(Mandatory)][string[]]$ClesValides,
        [AllowNull()][AllowEmptyString()][string]$Contexte,
        [bool]$EntreeRedirigee
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return @{ Etat = 'cle-absente'; Cle = $null; Jeton = $false } }

    $demande = $Key.Trim()
    $canonique = $null
    foreach ($c in $ClesValides) {
        if ([string]::Equals($c, $demande, [System.StringComparison]::OrdinalIgnoreCase)) { $canonique = $c; break }
    }
    if (-not $canonique) {
        # Une cle est un mot court en minuscules et tirets. Long, ou portant
        # autre chose, c'est presque surement une valeur collee a sa place.
        $jeton = ($demande.Length -ge 2 * $script:JetonLongueurMin) -or ($demande -cnotmatch '^[a-z0-9-]+$')
        return @{ Etat = 'cle-inconnue'; Cle = $null; Jeton = [bool]$jeton }
    }

    if ($EntreeRedirigee) { return @{ Etat = 'entree-redirigee'; Cle = $canonique; Jeton = $false } }
    if ([string]::IsNullOrWhiteSpace($Contexte)) { return @{ Etat = 'sans-contexte'; Cle = $canonique; Jeton = $false } }
    if ($Contexte -cnotmatch $script:CtxNomContexteMotif) { return @{ Etat = 'contexte-invalide'; Cle = $canonique; Jeton = $false } }

    @{ Etat = 'ok'; Cle = $canonique; Jeton = $false }
}

function Test-CtxEntreeRedirigee {
    # Un point d'injection, rien de plus : [Console]::IsInputRedirected ne se
    # simule pas, et la suite elle-meme tourne souvent avec une entree
    # redirigee -- sans ce relais, aucun test ne pourrait construire le cas
    # interactif.
    [Console]::IsInputRedirected
}

function Test-CtxSecretPresent {
    <#
      Le coffre porte-t-il deja cette cle pour ce contexte ? Lit les
      METADONNEES seulement, jamais la valeur.

      Une erreur de lecture REMONTE, elle n'est pas lue comme "absent" : une
      reponse "absent" par defaut ecraserait une valeur existante sans
      demander, ce qui est precisement ce que la confirmation empeche.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key
    )
    $complet = "devctx/$Name/$Key"
    # -Name accepte des jokers : seul le nom EXACT compte.
    $infos = @(Get-SecretInfo -Vault $script:VaultName -Name $complet -ErrorAction Stop)
    $trouves = @($infos | Where-Object { $_ -and "$($_.Name)" -eq $complet })
    $trouves.Count -gt 0
}

function Remove-CtxSecret {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Aide privee, non exportee : -WhatIf ne peut pas lui parvenir. La commande publique qui l appelle porte la confirmation.')]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Key
    )
    Remove-Secret -Vault $script:VaultName -Name "devctx/$Name/$Key" -ErrorAction Stop
}

function Confirm-CtxSecretAction {
    # Oui seulement sur un oui explicite, dans l'une ou l'autre langue : la
    # reponse se compare a une liste fixe, jamais a un libelle traduit, pour
    # qu'un "y" tape sous une interface francaise ne soit pas lu comme un non.
    param([Parameter(Mandatory)][string]$Question)
    $r = "$(Read-Host "    $Question")".Trim()
    $r -match '^(o|oui|y|yes)$'
}

function Set-DevContextSecret {
    <#
    .SYNOPSIS
        Sets, replaces or removes one secret of a context, through the validated masked prompt.

    .DESCRIPTION
        The way to add a token after `ctx new`, or to replace one that expired or
        was revoked. The value is asked for with the same masked prompt as
        `ctx new`: an entry holding control or invisible characters, or shorter
        than 8 characters, is refused, a Supabase token in an unexpected format is
        stored only on explicit choice, and a swallowed paste can be read from the
        clipboard instead (validated, never displayed, then overwritten).

        The value is never taken as an argument: it would land in clear in the
        PSReadLine history file. Only the key NAME is typed on the command line.

        Acts on the active context ($env:DEVCTX) unless -Name says otherwise.
        Refuses a key that is not one the module manages, and refuses to run
        when input is redirected (a script, a CI job, an AI agent's shell),
        since nobody could answer the prompt. When the key already holds a
        value, asks before replacing it.

        The current shell keeps the value it loaded: after a change to the active
        context, run `work <context> -NoCd` to load the new one.

    .PARAMETER Key
        The secret's name: github-token, vercel-token, supabase-token,
        supabase-db or sentry-token. Without it, the valid keys are listed.

    .PARAMETER Name
        The context. Defaults to the active one.

    .PARAMETER Remove
        Delete the key from the vault instead of setting it, after confirmation.

    .EXAMPLE
        ctx secret supabase-token

    .EXAMPLE
        ctx secret vercel-token -Name acme

    .EXAMPLE
        ctx secret sentry-token -Remove
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)][string]$Key,
        [string]$Name,
        [switch]$Remove
    )

    $cles = @($script:SecretMap.Keys)
    $contexte = if ($Name) { $Name } else { $env:DEVCTX }
    $verdict = Get-CtxVerdictSecret -Key $Key -ClesValides $cles -Contexte $contexte -EntreeRedirigee (Test-CtxEntreeRedirigee)

    if ($verdict.Etat -eq 'cle-absente') {
        Write-Host ''
        Write-Host "  $(T 'secret.usage')" -ForegroundColor Cyan
        Write-Host "    $(T 'new.jetonsCles' ($cles -join ', '))" -ForegroundColor DarkGray
        Write-Host ''
        return
    }
    if ($verdict.Etat -eq 'cle-inconnue') {
        $message = T 'secret.cleInconnue' ($cles -join ', ')
        if ($verdict.Jeton) { $message += "`n" + (T 'secret.cleRessembleJeton') }
        throw $message
    }
    if ($verdict.Etat -eq 'entree-redirigee') { throw (T 'secret.redirige' $verdict.Cle) }
    if ($verdict.Etat -eq 'sans-contexte') { throw (T 'secret.sansContexte' $verdict.Cle) }
    if ($verdict.Etat -eq 'contexte-invalide') { throw (T 'secret.contexteInvalide') }

    $cle = $verdict.Cle
    # Leve si le contexte n'existe pas : poser un secret pour un contexte que
    # rien n'utilisera est une faute de frappe, pas une intention.
    $null = Read-CtxManifest $contexte

    $cible = "devctx/$contexte/$cle"
    $action = if ($Remove) { T 'secret.actionRetirer' } else { T 'secret.actionPoser' }
    if (-not $PSCmdlet.ShouldProcess($cible, $action)) { return }

    Test-CtxVault
    $present = Test-CtxSecretPresent -Name $contexte -Key $cle
    $variable = $script:SecretMap[$cle]
    $actifIci = ($env:DEVCTX -eq $contexte)

    Write-Host ''
    if ($Remove) {
        if (-not $present) {
            Write-Host "  $(T 'secret.rienARetirer' $cle $contexte)" -ForegroundColor DarkGray
            Write-Host ''
            return
        }
        if (-not (Confirm-CtxSecretAction (T 'secret.confirmerRetrait' $cle $contexte))) {
            Write-Host "  $(T 'secret.inchange' $cle)" -ForegroundColor DarkGray
            Write-Host ''
            return
        }
        Remove-CtxSecret -Name $contexte -Key $cle
        Write-Host "  $(T 'secret.retire' $cle $contexte)" -ForegroundColor Green
        if ($actifIci) { Write-Host "  $(T 'secret.recharger' $variable $contexte)" -ForegroundColor Yellow }
        Write-Host ''
        return
    }

    if ($present -and -not (Confirm-CtxSecretAction (T 'secret.confirmerRemplacement' $cle $contexte))) {
        Write-Host "  $(T 'secret.inchange' $cle)" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host "  $(T 'secret.saisie' $cle $contexte)" -ForegroundColor Cyan
    Write-Host "  $(T 'new.jetonsCollage')" -ForegroundColor DarkGray
    $secure = Read-CtxJeton -Key $cle
    if ($null -eq $secure) {
        $suite = if ($present) { T 'secret.inchange' $cle } else { T 'jeton.passe' $cle }
        Write-Host "  $suite" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Set-CtxSecret -Name $contexte -Key $cle -Value $secure
    Write-Host "  $(T 'secret.enregistre' $cle $contexte $secure.Length)" -ForegroundColor Green
    if ($actifIci) { Write-Host "  $(T 'secret.recharger' $variable $contexte)" -ForegroundColor Yellow }
    Write-Host ''
}
