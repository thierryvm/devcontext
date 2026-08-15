#Requires -Version 7
<#
.SYNOPSIS
    Serves the repository over http://127.0.0.1 so a browser can render it.

.DESCRIPTION
    Why this exists: browser automation refuses `file://` URLs. Anything visual
    in this repository -- an animated SVG, a rendered GUIDE.html, a future
    dashboard -- therefore cannot be checked by opening it directly, and
    "the XML parses" is not the same claim as "it displays".

    That gap is not academic. On 15 August 2026 the demo SVG parsed cleanly,
    passed every structural check, and animated in the wrong order: a rounding
    bug produced a CSS keyframe whose end step came before its start step, so
    the exit-code line appeared before the command that produced it. Nothing but
    looking at it would have caught that.

    Loopback only, no directory listing beyond the folder served, and the
    process dies with the terminal. Nothing here is meant to be reachable from
    another machine.

.PARAMETER Dossier
    Folder to serve. Defaults to the repository root.

.PARAMETER Port
    Defaults to 8791.

.EXAMPLE
    pwsh -NoProfile -File .\docs\demo\preview.ps1
    # then open http://127.0.0.1:8791/docs/demo/guard-refusal.svg
#>
[CmdletBinding()]
param(
    [string]$Dossier = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [int]$Port = 8791
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue |
          Select-Object -First 1
if (-not $python) {
    throw "python introuvable dans le PATH. Installer Python, ou servir le dossier autrement."
}

Write-Host ''
Write-Host "  Sert  : $Dossier" -ForegroundColor Cyan
Write-Host "  Sur   : http://127.0.0.1:$Port/" -ForegroundColor Green
Write-Host ''
Write-Host '  Exemples :' -ForegroundColor DarkGray
Write-Host "    http://127.0.0.1:$Port/docs/demo/guard-refusal.svg" -ForegroundColor DarkGray
Write-Host "    http://127.0.0.1:$Port/docs/demo/ctx-doctor.svg" -ForegroundColor DarkGray
Write-Host "    http://127.0.0.1:$Port/GUIDE.html" -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Ctrl+C pour arreter.' -ForegroundColor DarkGray
Write-Host ''

# --bind 127.0.0.1 : sur la boucle locale uniquement. Sans ce drapeau, le
# serveur ecoute sur toutes les interfaces et publie le depot sur le reseau.
& $python.Source -m http.server $Port --bind 127.0.0.1 --directory $Dossier
