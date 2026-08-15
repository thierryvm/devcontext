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

# Script autonome : T est interne au module, il faut sourcer la langue soi-meme.
. (Join-Path $PSScriptRoot 'src' 'Langue.ps1')
Set-CtxLangue | Out-Null

$SousCle = 'Software\Classes\vscode\shell\open\command'
$Key     = "HKCU:\$SousCle"
$Routeur = Join-Path $PSScriptRoot 'vscode-uri-router.ps1'

# Resolution des executables : JAMAIS de chemin en dur.
#
# Ces deux lignes portaient le chemin de profil d'un utilisateur precis.
# Le script ne fonctionnait donc que sur une seule machine, et publiait au
# passage le nom d'utilisateur Windows de son auteur. Releve le 15 aout 2026.
function Resolve-CtxExe {
    param([string[]]$Candidats, [string]$Commande)
    foreach ($c in $Candidats) { if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c } }
    if ($Commande) {
        # Depuis le lanceur bin/<nom>.cmd, remonter jusqu'a l'executable.
        $cli = Get-Command $Commande -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty Source
        $dossier = if ($cli) { Split-Path $cli -Parent }
        for ($i = 0; $i -lt 4 -and $dossier; $i++) {
            $exe = Get-ChildItem -LiteralPath $dossier -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -eq $Commande } | Select-Object -First 1
            if ($exe) { return $exe.FullName }
            $parent = Split-Path $dossier -Parent
            if ($parent -eq $dossier) { break }
            $dossier = $parent
        }
    }
}

$PwshExe = Resolve-CtxExe -Commande 'pwsh' -Candidats @(
    (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
)
$CodeExe = Resolve-CtxExe -Commande 'code' -Candidats @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
    (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe')
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')
)

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
    # Modifie les ACL d'une cle de registre : l'operation la moins reversible
    # de ce depot, et celle qui merite le plus un -WhatIf.
    [CmdletBinding(SupportsShouldProcess)]
    param([bool]$Actif)
    $action = if ($Actif) { 'poser le refus d ecriture' } else { 'retirer le refus d ecriture' }
    if (-not $PSCmdlet.ShouldProcess($Key, $action)) { return }
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
    Write-Host "  $(T 'uri.cle' $Key)"
    Write-Host "  $(T 'uri.valeur' $actuel)"
    Write-Host ""
    if ($actuel -eq $Attendu) {
        Write-Host "  $(T 'uri.actif')" -ForegroundColor Green
        if ($verrou) { Write-Host "  $(T 'uri.verrouActif')" -ForegroundColor Green }
        else         { Write-Host "  $(T 'uri.verrouAbsent')" -ForegroundColor Yellow }
    }
    elseif ($actuel -eq $Origine) { Write-Host "  $(T 'uri.origine')" -ForegroundColor Yellow }
    else                          { Write-Host "  $(T 'uri.inconnue')" -ForegroundColor Yellow }
    exit 0
}

if ($Restaurer) {
    if (Test-Verrou) { Set-Verrou $false }
    Set-ItemProperty -LiteralPath $Key -Name '(default)' -Value $Origine
    Write-Host "  $(T 'uri.restaure')" -ForegroundColor Green
    exit 0
}

foreach ($f in @($PwshExe, $Routeur, $CodeExe)) {
    if (-not (Test-Path -LiteralPath $f)) { throw (T 'uri.introuvable' $f) }
}

if (-not (Test-Path -LiteralPath $Key)) {
    New-Item -Path $Key -Force | Out-Null
}

if ($actuel -eq $Attendu -and (Test-Verrou)) {
    Write-Host "  $(T 'uri.dejaEnPlace')" -ForegroundColor Green
    exit 0
}

# Une valeur qui n'est ni l'origine ni la nôtre mérite d'être conservée : un
# autre outil a pu s'approprier le protocole entre-temps.
if ($actuel -and $actuel -ne $Origine -and $actuel -ne $Attendu) {
    $sauv = Join-Path $env:LOCALAPPDATA ('DevContext\vscode-handler-remplace-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path (Split-Path $sauv -Parent) | Out-Null
    Set-Content -LiteralPath $sauv -Value $actuel -Encoding UTF8
    Write-Host "  $(T 'uri.valeurConservee')" -ForegroundColor Yellow
    Write-Host "    $sauv" -ForegroundColor Yellow
}

# Le verrou bloque notre propre écriture : le retirer avant, le reposer après.
if (Test-Verrou) { Set-Verrou $false }
Set-ItemProperty -LiteralPath $Key -Name '(default)' -Value $Attendu
Set-Verrou $true

Write-Host "  $(T 'uri.installe')" -ForegroundColor Green
Write-Host "  $(T 'uri.verifier')"
