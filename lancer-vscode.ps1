<#
.SYNOPSIS
    Ouvre VS Code dans un contexte DevContext, identité chargée.

.DESCRIPTION
    Un raccourci qui lance VS Code directement l'isole (--user-data-dir) mais
    ne pose AUCUNE variable d'environnement : le terminal intégré et Claude
    Code démarrent alors sans GH_CONFIG_DIR, sans SUPABASE_ACCESS_TOKEN et
    sans la configuration Vercel du contexte. `gh` repartirait sur le dernier
    compte connecté de la machine — précisément ce que DevContext empêche.

    Ce script rétablit l'ordre correct :
      1. `work <contexte>`  pose les variables d'environnement
      2. `Set-Location`     déclenche la résolution de la clé Supabase du dossier
      3. `ctx`              vérifie que dossier, identité et compte concordent
      4. VS Code            hérite de tout ce qui précède

    VS Code n'est PAS lancé si la vérification échoue : la fenêtre reste
    ouverte avec le motif affiché.

.PARAMETER Context
    Nom du contexte DevContext (`perso`, `client-a`, …). Voir `ctx-list`.

.PARAMETER Path
    Dossier à ouvrir. Viser le PROJET, jamais la racine du contexte :
    ouvrir `F:\PROJECTS\Apps` fait chercher tsserver dans
    `F:\PROJECTS\Apps\node_modules`, qui n'existe pas.

.EXAMPLE
    .\lancer-vscode.ps1 -Context client-a -Path 'F:\PROJECTS\Clients\client-a\projet'

.NOTES
    Créé le 8 août 2026. Appelé par les raccourcis de Desktop\Raccourcis-outils.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Context,
    [Parameter(Mandatory)][string]$Path
)

$ErrorActionPreference = 'Stop'

function Stop-WithMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Affiche un motif et termine le script ; ne modifie aucun etat.')]
    param([string]$Message)
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Red
    Write-Host ""
    Read-Host "  Entree pour fermer"
    exit 1
}

# Le profil PowerShell charge normalement DevContext. S'il ne l'a pas fait
# (profil désactivé, module déplacé), l'import explicite le dit clairement au
# lieu d'échouer sur un « work : terme non reconnu ».
if (-not (Get-Command work -ErrorAction SilentlyContinue)) {
    try { Import-Module DevContext -ErrorAction Stop }
    catch { Stop-WithMessage "Module DevContext introuvable. Verifier ~\Documents\PowerShell\Modules\DevContext\." }
}

if (-not (Test-Path -LiteralPath $Path)) {
    Stop-WithMessage "Dossier introuvable : $Path"
}

# -NoCd : on se place ensuite sur le PROJET, pas sur la racine du contexte.
Use-DevContext -Name $Context -NoCd

# Le changement de dossier déclenche le hook qui aligne SUPABASE_ACCESS_TOKEN
# sur le project-ref trouvé dans le dossier — indispensable quand un contexte
# porte plusieurs comptes Supabase.
Set-Location -LiteralPath $Path

if (-not (Test-DevContext -Quiet)) {
    Test-DevContext | Out-Null
    Stop-WithMessage "NO-GO — VS Code n'a pas ete lance. Corriger avant de pousser ou deployer."
}

Write-Host "  GO" -ForegroundColor Green
Open-DevCode $Context $Path
