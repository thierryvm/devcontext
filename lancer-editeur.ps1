<#
.SYNOPSIS
    Ouvre un editeur dans un contexte DevContext, identite chargee.

.DESCRIPTION
    Ce que fait un raccourci qui vise directement l'executable : il ouvre
    l'editeur, et rien d'autre. Pas de --user-data-dir, donc les sessions
    GitHub, Copilot et marketplace sont communes a tous les projets ; pas de
    variables d'environnement, donc le terminal integre et l'assistant qui y
    tourne demarrent sans GH_CONFIG_DIR ni jeton, et `gh` repart sur le dernier
    compte connecte de la machine.

    Ce script retablit l'ordre correct :
      1. `work <contexte>`  pose les variables d'environnement
      2. `Set-Location`     declenche la resolution de la cle Supabase du dossier
      3. `ctx`              verifie que dossier, identite et compte concordent
      4. l'editeur          herite de tout ce qui precede

    L'editeur n'est PAS lance si la verification echoue : la fenetre reste
    ouverte avec le motif affiche. Un NO-GO signifie que l'identite du dossier
    et celle de la session divergent, et c'est exactement l'etat qui fait partir
    un commit client sous une identite perso.

    Le contexte n'est pas demande : il est DEDUIT DU DOSSIER. C'est la doctrine
    du module, et elle vaut ici aussi -- un raccourci porte un -Context ecrit une
    fois puis jamais relu, qui devient faux le jour ou le projet demenage.

.PARAMETER Path
    Dossier a ouvrir. Viser le PROJET, jamais la racine du contexte : ouvrir
    F:\PROJECTS\Apps fait chercher tsserver dans F:\PROJECTS\Apps\node_modules,
    qui n'existe pas.

.PARAMETER Editor
    Nom de commande de l'editeur, tel que `ctx-editors` le liste. VS Code par
    defaut.

.PARAMETER Context
    Force le contexte au lieu de le deduire. A n'utiliser que pour un dossier
    qu'aucune racine ne couvre.

.EXAMPLE
    .\lancer-editeur.ps1 -Path 'F:\PROJECTS\Clients\acme\site'

.EXAMPLE
    .\lancer-editeur.ps1 -Path 'F:\PROJECTS\Apps\demo' -Editor cursor

.NOTES
    Cree le 15 aout 2026, en generalisant lancer-vscode.ps1 a tous les editeurs
    de la famille VS Code. Appele par les raccourcis ecrits par ctx-shortcut.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [string]$Editor = 'code',
    [string]$Context
)

$ErrorActionPreference = 'Stop'

# T n'est pas EXPORTEE par le module -- elle lui est interne. Un script qui
# tourne a cote doit donc sourcer le fichier de langue directement, comme le
# fait le shim. L'oublier ne casse rien de visible : chaque message devient
# « [lanceur.go] », ce qui est precisement pourquoi une cle manquante s'affiche
# plutot que de disparaitre.
. (Join-Path $PSScriptRoot 'src' 'Langue.ps1')
Set-CtxLangue | Out-Null

function Stop-WithMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Affiche un motif et termine le script ; ne modifie aucun etat.')]
    param([string]$Message)
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Red
    Write-Host ""
    Read-Host ("  " + (T 'lanceur.fermer'))
    exit 1
}

# Le profil PowerShell charge normalement DevContext. S'il ne l'a pas fait
# (profil desactive, module deplace), l'import explicite le dit clairement au
# lieu d'echouer sur un « work : terme non reconnu ».
if (-not (Get-Command work -ErrorAction SilentlyContinue)) {
    try { Import-Module (Join-Path $PSScriptRoot 'DevContext.psd1') -ErrorAction Stop }
    catch { Stop-WithMessage (T 'lanceur.moduleAbsent' $_.Exception.Message) }
}

if (-not (Test-Path -LiteralPath $Path)) {
    Stop-WithMessage (T 'lanceur.dossierAbsent' $Path)
}

if (-not $Context) {
    $manifeste = Resolve-DevContextForPath -Path $Path
    if (-not $manifeste) {
        Stop-WithMessage (T 'lanceur.horsContexte' $Path)
    }
    $Context = $manifeste.name
}

# -NoCd : on se place ensuite sur le PROJET, pas sur la racine du contexte.
Use-DevContext -Name $Context -NoCd

# Le changement de dossier declenche le hook qui aligne SUPABASE_ACCESS_TOKEN
# sur le project-ref trouve dans le dossier — indispensable quand un contexte
# porte plusieurs comptes Supabase.
Set-Location -LiteralPath $Path

if (-not (Test-DevContext -Quiet)) {
    Test-DevContext | Out-Null
    Stop-WithMessage (T 'lanceur.noGo')
}

Write-Host "  $(T 'lanceur.go')" -ForegroundColor Green
Open-DevCode -Name $Context -Path $Path -Editor $Editor
