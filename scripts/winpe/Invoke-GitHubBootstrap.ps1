<#
.SYNOPSIS
    Laedt die Konfiguration aus GitHub und startet Menue- oder Zero-Touch-Deployment.
.DESCRIPTION
    Liest zuerst die lokale global.json (Bootstrapping), um Repository- und Fallback-
    Einstellungen zu kennen. Ist Konnektivitaet vorhanden, wird die Konfiguration aus
    GitHub geladen; andernfalls greift der Fallback auf die lokal eingebettete Konfiguration.
    Anhand von Deployment.EnableZeroTouch wird der passende Zweig gestartet.
.PARAMETER Root
    Wurzelverzeichnis der WinPE-Ablage.
.PARAMETER Token
    Optionaler GitHub-Token fuer private Repositories (z. B. aus Umgebungsvariable).
#>
[CmdletBinding()]
param(
    [string]$Root = 'X:\OSDCloud',
    [string]$Token = $env:OSDCLOUD_GITHUB_TOKEN
)

$ErrorActionPreference = 'Stop'

$src        = Join-Path $Root 'src'
$srcModules = Join-Path $src 'modules'
$configRoot = Join-Path $Root 'config'

foreach ($m in 'OSDCloud.Logging','OSDCloud.Security','OSDCloud.Config','OSDCloud.Network') {
    Import-Module (Join-Path $srcModules "$m.psm1") -Force
}

Write-OSDCloudLog -Level Information -Component 'Bootstrap' -Message '=== GitHub-Bootstrap ==='

# Konnektivitaet bestimmt, ob GitHub oder lokal geladen wird.
$global = Get-Content -LiteralPath (Join-Path $configRoot 'global.json') -Raw | ConvertFrom-Json
$online = Test-OSDCloudConnectivity -TargetHosts $global.Security.AllowedHosts -TimeoutSeconds $global.Network.TimeoutSeconds

$useLocal = -not $online
if ($useLocal) {
    Write-OSDCloudLog -Level Warning -Component 'Bootstrap' -Message 'Offline: verwende lokal eingebettete Konfiguration.'
} else {
    Write-OSDCloudLog -Level Information -Component 'Bootstrap' -Message 'Online: lade Konfiguration aus GitHub.'
}

try {
    $config = Get-OSDCloudConfig -LocalConfigRoot $configRoot -UseLocalGlobal:$useLocal -Token $Token
} catch {
    Write-OSDCloudLog -Level Warning -Component 'Bootstrap' -Message "GitHub-Laden fehlgeschlagen ($($_.Exception.Message)). Fallback auf lokale Konfiguration."
    $config = Get-OSDCloudConfig -LocalConfigRoot $configRoot -UseLocalGlobal -Token $Token
}

# Entscheidung: Zero-Touch oder interaktives Menue.
$zeroTouch = [bool]$config.Global.Deployment.EnableZeroTouch
if ($zeroTouch) {
    Write-OSDCloudLog -Level Information -Component 'Bootstrap' -Message 'Zero-Touch aktiviert. Starte automatisches Deployment.'
    & (Join-Path $src 'Start-ZeroTouchDeployment.ps1') -LocalConfigRoot $configRoot -UseLocalConfig:$useLocal -Token $Token
} else {
    Write-OSDCloudLog -Level Information -Component 'Bootstrap' -Message 'Starte interaktives Menue.'
    & (Join-Path $src 'Start-DeploymentMenu.ps1') -LocalConfigRoot $configRoot -UseLocalConfig:$useLocal -Token $Token
}
