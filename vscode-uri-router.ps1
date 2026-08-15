<#
.SYNOPSIS
    Route une URI vscode:// vers l'instance VS Code qui l'attend.

.DESCRIPTION
    Windows enregistre un seul gestionnaire pour le protocole vscode://, et
    celui livré par VS Code ne porte pas de --user-data-dir. Chaque instance ne
    dialoguant qu'avec celles qui partagent son user-data-dir, un callback
    d'authentification GitHub démarrait donc un VS Code sur le profil par
    défaut : une fenêtre inutile s'ouvrait et la fenêtre qui attendait son jeton
    ne le recevait jamais.

    Ce script s'intercale devant Code.exe et choisit la cible :

      0 instance isolée   -> profil par défaut (comportement d'origine)
      1 instance isolée   -> celle-là, sans autre vérification
      2 et plus           -> la fenêtre VS Code la plus proche du premier plan

    Dans le dernier cas, l'ordre Z des fenêtres fait foi : au moment du callback
    c'est le navigateur qui a le focus, donc la première fenêtre VS Code
    rencontrée est celle qui était active juste avant — celle qui a lancé la
    connexion.

    Toute erreur retombe sur le comportement d'origine : un lien vscode://
    légitime ne doit jamais casser à cause de ce script.

.PARAMETER Uri
    L'URI transmise par Windows (le "%1" du registre).

.PARAMETER DryRun
    Affiche la cible retenue sans rien lancer. Pour tester le routage.

.EXAMPLE
    .\vscode-uri-router.ps1 -Uri 'vscode://file/F:/PROJECTS/Apps/demo-app/README.md' -DryRun

.NOTES
    Créé le 9 août 2026. Installé dans
    HKCU\Software\Classes\vscode\shell\open\command.
    Sauvegarde de la valeur d'origine :
    F:\Backups\vscode-uri-handler-2026-08-09\vscode-protocol-AVANT.reg
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Uri et DryRun sont lus par Get-UriSafe et Send-Uri, qui les voient par heritage de portee. La regle n inspecte que la portee du parametre.')]
param(
    [Parameter(Mandatory, Position = 0)][string]$Uri,
    [switch]$DryRun
)

# Script autonome : T est interne au module, il faut sourcer la langue soi-meme.
. (Join-Path $PSScriptRoot 'src' 'Langue.ps1')
Set-CtxLangue | Out-Null

# JAMAIS de chemin en dur : ce fichier portait un chemin de profil, donc il ne
# fonctionnait que sur une machine et publiait un nom d'utilisateur Windows.
$CodeExe = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
    (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe')
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
$LogFile = Join-Path $env:LOCALAPPDATA 'DevContext\vscode-uri-router.log'

# L'URI de callback OAuth porte le code d'autorisation dans sa query. On ne
# journalise donc QUE le schéma et le chemin — jamais les paramètres.
function Get-UriSafe {
    if ($Uri -match '^([^?#]*)') { return $Matches[1] }
    return '(illisible)'
}

# Le JOURNAL n'est PAS traduit, et c'est deliberé : une trace qui change de
# langue selon le poste n'est plus recherchable. Deux utilisateurs signalant le
# meme incident produiraient deux textes differents, et aucune recherche ne les
# rapprocherait. Seule la ligne AFFICHEE par -DryRun passe par T.
function Write-RouteurLog {
    param([string]$Message)
    try {
        $d = Split-Path $LogFile -Parent
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Force -Path $d | Out-Null
        }
        if ((Test-Path -LiteralPath $LogFile) -and
            (Get-Item -LiteralPath $LogFile).Length -gt 100KB) {
            Set-Content -LiteralPath $LogFile -Value '' -Encoding UTF8
        }
        Add-Content -LiteralPath $LogFile -Encoding UTF8 `
            -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    }
    catch {
        # Circulaire : on ne peut pas journaliser l'echec du journal. Et un
        # journal qui echoue ne doit jamais empecher une fenetre de s'ouvrir.
        $null = $_
    }
}

function Send-Uri {
    param([string]$UserDataDir)

    $cible = if ($UserDataDir) { $UserDataDir } else { T 'uri.profilDefaut' }
    if ($DryRun) {
        Write-Host "  $(T 'uri.cible' $cible)" -ForegroundColor Cyan
        return
    }

    $a = @()
    if ($UserDataDir) { $a += @('--user-data-dir', $UserDataDir) }
    $a += @('--open-url', '--', $Uri)
    Start-Process -FilePath $CodeExe -ArgumentList $a -WindowStyle Hidden
}

try {
    if (-not (Test-Path -LiteralPath $CodeExe)) {
        throw (T 'uri.codeAbsent' $CodeExe)
    }

    # Instances racine uniquement. Les processus enfants d'Electron (renderer,
    # gpu, utility) portent une ligne de commande sans --user-data-dir : les
    # compter fausserait le décompte.
    $all   = @(Get-CimInstance Win32_Process -Filter "Name='Code.exe'")
    $ids   = $all.ProcessId
    $roots = @($all | Where-Object { $_.ParentProcessId -notin $ids })

    $uddByPid = @{}
    foreach ($p in $roots) {
        if ($p.CommandLine -match '--user-data-dir[=\s]+"?([A-Za-z]:[^"]*?)"?(\s+--|\s*$)') {
            $uddByPid[[uint32]$p.ProcessId] = $Matches[1].TrimEnd('\')
        }
    }

    if ($uddByPid.Count -eq 0) {
        Write-RouteurLog ('aucune instance isolee -> profil par defaut | {0}' -f (Get-UriSafe))
        Send-Uri $null
        return
    }

    $distinct = @($uddByPid.Values | Sort-Object -Unique)
    if ($distinct.Count -eq 1) {
        Write-RouteurLog ('1 instance isolee -> {0} | {1}' -f $distinct[0], (Get-UriSafe))
        Send-Uri $distinct[0]
        return
    }

    # Plusieurs contextes ouverts : départager par l'ordre Z. EnumWindows
    # parcourt les fenêtres du premier plan vers l'arrière.
    if (-not ('WinZ' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class WinZ {
    private delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static uint[] PidsByZOrder() {
        List<uint> list = new List<uint>();
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (IsWindowVisible(h) && GetWindowTextLength(h) > 0) {
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                list.Add(pid);
            }
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
}
'@
    }

    $target = $null
    foreach ($procId in [WinZ]::PidsByZOrder()) {
        if ($uddByPid.ContainsKey($procId)) { $target = $uddByPid[$procId]; break }
    }

    if ($target) {
        Write-RouteurLog ('{0} instances -> ordre Z -> {1} | {2}' -f $distinct.Count, $target, (Get-UriSafe))
    }
    else {
        # Aucune fenêtre visible reconnue (toutes minimisées ?). Faute de mieux,
        # l'instance démarrée en dernier est le pari le moins mauvais.
        $dernier = $roots |
            Where-Object { $uddByPid.ContainsKey([uint32]$_.ProcessId) } |
            Sort-Object CreationDate -Descending | Select-Object -First 1
        $target = $uddByPid[[uint32]$dernier.ProcessId]
        Write-RouteurLog ('{0} instances, aucune fenetre visible -> derniere lancee -> {1} | {2}' -f $distinct.Count, $target, (Get-UriSafe))
    }

    Send-Uri $target
}
catch {
    Write-RouteurLog ('ERREUR: {0} -> repli profil par defaut | {1}' -f $_.Exception.Message, (Get-UriSafe))
    # Dernier recours : on est deja dans le rattrapage. Lever ici priverait
    # l'utilisateur de sa fenetre pour lui offrir une trace que personne ne lit.
    try { Send-Uri $null }
    catch { Write-RouteurLog ("repli par defaut en echec : " + $_.Exception.Message) }
}
