#Requires -Version 7
<#
.SYNOPSIS
    Generates the animated terminal demos shown in README.md.

.DESCRIPTION
    Animated SVG rather than a GIF, and rather than a screen recording.

    A GIF of a terminal is a bitmap: it blurs on a high-DPI screen, weighs
    hundreds of kilobytes for twenty seconds, and cannot be corrected without
    re-recording the whole session. An SVG stays sharp at any zoom, weighs a few
    kilobytes, and -- because it is generated from the transcript below -- can be
    fixed by editing a line of text.

    It is also honest by construction: the transcript is right here, so anyone
    can check the demo shows what the tool actually does. A recording proves
    nothing about a build; a script that lies is a script someone can read.

    Every line carries its own CSS keyframes, all sharing one timeline that
    restarts at 0%. That is what makes the loop seamless: nothing depends on
    animation-delay, which would leave lines flickering on the second pass.

.EXAMPLE
    pwsh -NoProfile -File .\docs\demo\build-demo.ps1
#>
[CmdletBinding()]
param([string]$Sortie = $PSScriptRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Terminal palette. Fixed rather than theme-aware: a terminal is dark, on every
# screen, and a demo that changes colour with the reader's settings looks broken
# rather than clever.
$Couleurs = @{
    fond      = '#12141a'
    cadre     = '#262a33'
    barre     = '#1b1e26'
    texte     = '#d7dae0'
    faible    = '#6b7280'
    invite    = '#5eead4'
    rouge     = '#f87171'
    jaune     = '#fbbf24'
    vert      = '#4ade80'
    cyan      = '#67e8f9'
}

function ConvertTo-XmlTexte {
    param([string]$T)
    $T.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function New-CtxDemoSvg {
    <#
      $Lignes : @( @{ t = 'texte'; c = 'clef de couleur'; d = secondes avant la suivante } )
    #>
    param(
        [Parameter(Mandatory)][object[]]$Lignes,
        [Parameter(Mandatory)][string]$Titre,
        [int]$Largeur = 780,
        [double]$Pause = 2.5
    )

    $hLigne   = 21
    $hBarre   = 30
    $marge    = 18
    $hauteur  = $hBarre + $marge + ($Lignes.Count * $hLigne) + $marge

    # Timeline. Chaque ligne apparait a son instant, et TOUTES repartent de zero
    # au bouclage : c'est ce qui evite le clignotement au second tour.
    $instants = @()
    $t = 0.4
    foreach ($l in $Lignes) {
        $instants += $t
        $t += [double]$l.d
    }
    $total = [math]::Round($t + $Pause, 2)

    $css = [System.Text.StringBuilder]::new()
    [void]$css.AppendLine("    .m { font-family: ui-monospace, 'SF Mono', 'Cascadia Mono', Consolas, 'Liberation Mono', monospace; font-size: 13.5px; white-space: pre; }")
    for ($i = 0; $i -lt $Lignes.Count; $i++) {
        $pct = [math]::Round(($instants[$i] / $total) * 100, 3)
        # 100.0 et non 100 : avec un entier, PowerShell choisit la surcharge
        # [math]::Min(int, int), tronque 61.462 en 61, et produit une etape de
        # FIN anterieure a l'etape de DEBUT. Le navigateur reordonne alors les
        # arrets et la ligne reste visible du premier au dernier instant --
        # observe en vrai le 15 aout 2026 sur la ligne du code de sortie, qui
        # s'affichait avant la commande qui la produit.
        $pctFin = [math]::Round([math]::Min(100.0, $pct + 0.4), 3)
        if ($pctFin -le $pct) {
            throw "Etapes desordonnees sur la ligne $i ($pct% -> $pctFin%). L'animation serait cassee."
        }
        [void]$css.AppendLine("    @keyframes a$i { 0%,$pct% { opacity:0 } $pctFin%,100% { opacity:1 } }")
        [void]$css.AppendLine("    .l$i { opacity:0; animation: a$i ${total}s linear infinite; }")
    }
    # Curseur : clignote en permanence, y compris pendant les pauses.
    [void]$css.AppendLine("    @keyframes blink { 0%,49% { opacity:1 } 50%,100% { opacity:0 } }")
    [void]$css.AppendLine("    .cur { animation: blink 1s step-end infinite; }")

    $svg = [System.Text.StringBuilder]::new()
    [void]$svg.AppendLine("<svg xmlns='http://www.w3.org/2000/svg' width='$Largeur' height='$hauteur' viewBox='0 0 $Largeur $hauteur' role='img' aria-label='$(ConvertTo-XmlTexte $Titre)'>")
    [void]$svg.AppendLine("  <style>")
    [void]$svg.Append($css.ToString())
    [void]$svg.AppendLine("  </style>")
    [void]$svg.AppendLine("  <rect x='0' y='0' width='$Largeur' height='$hauteur' rx='10' fill='$($Couleurs.fond)' stroke='$($Couleurs.cadre)'/>")
    [void]$svg.AppendLine("  <path d='M0 10 a10 10 0 0 1 10 -10 h$($Largeur - 20) a10 10 0 0 1 10 10 v$($hBarre - 10) h-$Largeur z' fill='$($Couleurs.barre)'/>")
    foreach ($p in @(@(20, '#ff5f57'), @(38, '#febc2e'), @(56, '#28c840'))) {
        [void]$svg.AppendLine("  <circle cx='$($p[0])' cy='15' r='5' fill='$($p[1])'/>")
    }
    [void]$svg.AppendLine("  <text class='m' x='78' y='20' fill='$($Couleurs.faible)' font-size='12'>$(ConvertTo-XmlTexte $Titre)</text>")

    $y = $hBarre + $marge + 4
    for ($i = 0; $i -lt $Lignes.Count; $i++) {
        $l = $Lignes[$i]
        $couleur = $Couleurs[$l.c]
        [void]$svg.AppendLine("  <text class='m l$i' x='$marge' y='$y' fill='$couleur'>$(ConvertTo-XmlTexte $l.t)</text>")
        $y += $hLigne
    }
    # Le curseur suit la derniere ligne.
    [void]$svg.AppendLine("  <rect class='cur l$($Lignes.Count - 1)' x='$marge' y='$($y - 13)' width='8' height='15' fill='$($Couleurs.invite)'/>")
    [void]$svg.AppendLine("</svg>")
    $svg.ToString()
}

# ---------------------------------------------------------------------------
# Demo 1 -- the guard, from git-bash, with no context loaded
# ---------------------------------------------------------------------------
#
# git-bash on purpose: it is the shell where a PowerShell alias does nothing,
# and the one an AI agent actually uses. Showing PowerShell would demo the easy
# case.

$refus = @(
    @{ t = '$ cd ~/projects/demo-app'                              ; c = 'texte' ; d = 0.7 }
    @{ t = '$ echo $DEVCTX          # no context loaded at all'    ; c = 'texte' ; d = 0.9 }
    @{ t = ''                                                       ; c = 'faible'; d = 0.5 }
    @{ t = '$ supabase db reset --linked'                           ; c = 'texte' ; d = 1.4 }
    @{ t = ''                                                       ; c = 'faible'; d = 0.1 }
    @{ t = '  REFUSED - DevContext production guard'                ; c = 'rouge' ; d = 0.5 }
    @{ t = ''                                                       ; c = 'faible'; d = 0.1 }
    @{ t = '    Target : demo-app-prod'                             ; c = 'jaune' ; d = 0.4 }
    @{ t = "    Reason : 'db reset' drops and recreates the"        ; c = 'texte' ; d = 0.3 }
    @{ t = '             database. Refused on production.'          ; c = 'texte' ; d = 1.0 }
    @{ t = ''                                                       ; c = 'faible'; d = 0.1 }
    @{ t = '$ echo $?'                                              ; c = 'texte' ; d = 0.5 }
    @{ t = '1'                                                      ; c = 'texte' ; d = 1.2 }
    @{ t = ''                                                       ; c = 'faible'; d = 0.1 }
    @{ t = '# The real CLI was never reached.'                      ; c = 'faible'; d = 0.6 }
)

# ---------------------------------------------------------------------------
# Demo 2 -- the diagnostic
# ---------------------------------------------------------------------------

$doctor = @(
    @{ t = '$ ctx-doctor -Live'                                                        ; c = 'texte' ; d = 1.3 }
    @{ t = ''                                                                          ; c = 'faible'; d = 0.1 }
    @{ t = 'Verdict   Domain     Subject      Finding'                                 ; c = 'faible'; d = 0.3 }
    @{ t = '-------   ------     -------      -------'                                 ; c = 'faible'; d = 0.3 }
    @{ t = 'OK        context    owner        perso'                                   ; c = 'vert'  ; d = 0.35 }
    @{ t = 'OK        git        identity     me@example.com'                          ; c = 'vert'  ; d = 0.35 }
    @{ t = 'WARN      supabase   binary       2 installs, different versions'          ; c = 'jaune' ; d = 0.35 }
    @{ t = '                                    -> the version depends on the shell'   ; c = 'cyan'  ; d = 0.5 }
    @{ t = 'WARN      supabase   project      this folder targets PRODUCTION'          ; c = 'jaune' ; d = 0.5 }
    @{ t = 'OK        guard      coverage     active in every shell'                   ; c = 'vert'  ; d = 0.35 }
    @{ t = 'OK        gh         token        valid - myaccount (repo, workflow)'      ; c = 'vert'  ; d = 0.35 }
    @{ t = 'OK        supabase   token        valid - reaches demo-app-prod'           ; c = 'vert'  ; d = 1.2 }
    @{ t = ''                                                                          ; c = 'faible'; d = 0.1 }
    @{ t = '# No token value is ever printed. Only the key holding it.'                ; c = 'faible'; d = 0.6 }
)

New-CtxDemoSvg -Lignes $refus  -Titre 'git-bash  -  no context loaded' |
    Set-Content (Join-Path $Sortie 'guard-refusal.svg') -Encoding UTF8
New-CtxDemoSvg -Lignes $doctor -Titre 'pwsh  -  ctx-doctor -Live' -Largeur 820 |
    Set-Content (Join-Path $Sortie 'ctx-doctor.svg') -Encoding UTF8

foreach ($f in 'guard-refusal.svg', 'ctx-doctor.svg') {
    $p = Join-Path $Sortie $f
    $taille = [math]::Round((Get-Item $p).Length / 1kb, 1)
    # Un SVG mal forme s'affiche comme une image cassee dans le README, sans le
    # moindre message. On le valide ici plutot que de le decouvrir sur GitHub.
    $null = [xml](Get-Content $p -Raw)
    Write-Host ("  {0,-22} {1} ko  XML valide" -f $f, $taille) -ForegroundColor Green
}
