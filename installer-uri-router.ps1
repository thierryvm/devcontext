<#
.SYNOPSIS
    Installe, vérifie ou retire le routeur d'URI vscode://, et verrouille la clé
    de registre pour que VS Code ne puisse plus la reprendre.

.DESCRIPTION
    VS Code enregistre le protocole vscode:// au nom de l'utilisateur, sans
    --user-data-dir. Mesuré le 10 août 2026 : il ne le fait pas seulement à
    l'installation, il réécrit la clé à CHAQUE démarrage d'instance. Poser une
    valeur ne suffit donc pas — elle ne survit pas au prochain lancement.

    La parade est une ACL : on refuse à l'utilisateur courant les droits
    SetValue et Delete sur la clé. VS Code tente sa réécriture, échoue en
    silence, et le routeur reste en place. L'utilisateur restant propriétaire
    de la clé, il conserve ChangePermissions : ce script peut toujours
    déverrouiller, et le verrou est réversible à tout moment.

.PARAMETER Verifier
    N'écrit rien : affiche la valeur de la clé et l'état du verrou.

.PARAMETER Restaurer
    Déverrouille et remet le gestionnaire d'origine livré par VS Code.

.EXAMPLE
    .\installer-uri-router.ps1 -Verifier

.EXAMPLE
    .\installer-uri-router.ps1

.NOTES
    Créé le 9 août 2026, verrou ACL ajouté le 10 août 2026.
    HKCU uniquement, aucun droit administrateur requis.
    Sauvegarde de la valeur d'origine :
    F:\Backups\vscode-uri-handler-2026-08-09\vscode-protocol-AVANT.reg
#>
[CmdletBinding(DefaultParameterSetName = 'Installer')]
param(
    [Parameter(ParameterSetName = 'Verifier')][switch]$Verifier,
    [Parameter(ParameterSetName = 'Restaurer')][switch]$Restaurer
)

$ErrorActionPreference = 'Stop'

$SousCle = 'Software\Classes\vscode\shell\open\command'
$Key     = "HKCU:\$SousCle"
$PwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
$Routeur = Join-Path $PSScriptRoot 'vscode-uri-router.ps1'
$CodeExe = 'C:\Users\thier\AppData\Local\Programs\Microsoft VS Code\Code.exe'

$Attendu = '"{0}" -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Uri "%1"' -f $PwshExe, $Routeur
$Origine = '"{0}" --open-url -- "%1"' -f $CodeExe

# Droits refusés à VS Code. Delete est là au cas où une version future
# tenterait de supprimer la clé plutôt que d'en réécrire la valeur.
$DroitsBloques = @(
    [System.Security.AccessControl.RegistryRights]::SetValue,
    [System.Security.AccessControl.RegistryRights]::Delete
)

function Get-Sid {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().User
}

function Open-CleAcl {
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        $SousCle, 'ReadWriteSubTree',
        [System.Security.AccessControl.RegistryRights]'ChangePermissions,ReadPermissions')
}

function Test-Verrou {
    if (-not (Test-Path -LiteralPath $Key)) { return $false }
    $k = Open-CleAcl
    try {
        $sid = Get-Sid
        $acl = $k.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        foreach ($r in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($r.AccessControlType -eq 'Deny' -and $r.IdentityReference -eq $sid -and
                ($r.RegistryRights -band [System.Security.AccessControl.RegistryRights]::SetValue)) {
                return $true
            }
        }
        return $false
    }
    finally { $k.Close() }
}

function Set-Verrou {
    param([bool]$Actif)
    $k = Open-CleAcl
    try {
        $sid = Get-Sid
        $acl = $k.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        foreach ($d in $DroitsBloques) {
            $regle = New-Object System.Security.AccessControl.RegistryAccessRule(
                $sid, $d,
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Deny)
            if ($Actif) { $acl.AddAccessRule($regle) } else { $acl.RemoveAccessRuleAll($regle) }
        }
        $k.SetAccessControl($acl)
    }
    finally { $k.Close() }
}

function Get-Actuel {
    if (-not (Test-Path -LiteralPath $Key)) { return $null }
    (Get-ItemProperty -LiteralPath $Key).'(default)'
}

$actuel = Get-Actuel

if ($Verifier) {
    $verrou = if (Test-Path -LiteralPath $Key) { Test-Verrou } else { $false }
    Write-Host ""
    Write-Host "  cle    : $Key"
    Write-Host "  valeur : $actuel"
    Write-Host ""
    if ($actuel -eq $Attendu) {
        Write-Host "  ROUTEUR ACTIF" -ForegroundColor Green
        if ($verrou) { Write-Host "  VERROU ACTIF - VS Code ne peut pas reprendre la cle" -ForegroundColor Green }
        else         { Write-Host "  VERROU ABSENT - la cle sera ecrasee au prochain lancement de VS Code" -ForegroundColor Yellow }
    }
    elseif ($actuel -eq $Origine) { Write-Host "  gestionnaire d'origine (bug present) - relancer sans -Verifier" -ForegroundColor Yellow }
    else                          { Write-Host "  valeur inconnue - inspecter avant d'ecraser" -ForegroundColor Yellow }
    exit 0
}

if ($Restaurer) {
    if (Test-Verrou) { Set-Verrou $false }
    Set-ItemProperty -LiteralPath $Key -Name '(default)' -Value $Origine
    Write-Host "  Verrou retire, gestionnaire d'origine restaure." -ForegroundColor Green
    exit 0
}

foreach ($f in @($PwshExe, $Routeur, $CodeExe)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Introuvable : $f" }
}

if (-not (Test-Path -LiteralPath $Key)) {
    New-Item -Path $Key -Force | Out-Null
}

if ($actuel -eq $Attendu -and (Test-Verrou)) {
    Write-Host "  Deja en place et verrouille, rien a faire." -ForegroundColor Green
    exit 0
}

# Une valeur qui n'est ni l'origine ni la nôtre mérite d'être conservée : un
# autre outil a pu s'approprier le protocole entre-temps.
if ($actuel -and $actuel -ne $Origine -and $actuel -ne $Attendu) {
    $sauv = Join-Path $env:LOCALAPPDATA ('DevContext\vscode-handler-remplace-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path (Split-Path $sauv -Parent) | Out-Null
    Set-Content -LiteralPath $sauv -Value $actuel -Encoding UTF8
    Write-Host "  Valeur precedente inattendue, conservee dans :" -ForegroundColor Yellow
    Write-Host "    $sauv" -ForegroundColor Yellow
}

# Le verrou bloque notre propre écriture : le retirer avant, le reposer après.
if (Test-Verrou) { Set-Verrou $false }
Set-ItemProperty -LiteralPath $Key -Name '(default)' -Value $Attendu
Set-Verrou $true

Write-Host "  Routeur installe et cle verrouillee." -ForegroundColor Green
Write-Host "  Verifier : .\installer-uri-router.ps1 -Verifier"
