<#
.SYNOPSIS
    WinPE-Startpunkt fuer OSDCloudEUC.
.DESCRIPTION
    Wird beim Start des angepassten OSDCloud-WinPE ausgefuehrt (via StartPSCommand in
    Edit-OSDCloudWinPE). Initialisiert Logging und Netzwerk und uebergibt an den
    GitHub-Bootstrap, der die Konfiguration laedt und Menue- oder Zero-Touch-Zweig startet.

    Erwartete Verzeichnisstruktur im WinPE (durch Build-OSDCloudMedia bereitgestellt):
      X:\OSDCloud\src           (Module + Einstiegsskripte)
      X:\OSDCloud\config        (lokale Fallback-Konfiguration)
      X:\OSDCloud\profiles      (lokale Fallback-Profile)
      X:\OSDCloud\Scripts\winpe (dieses Skript + Netz-Init + Bootstrap)
#>
[CmdletBinding()]
param(
    [string]$Root = 'X:\OSDCloud'
)

$ErrorActionPreference = 'Stop'

$srcModules = Join-Path $Root 'src\modules'
Import-Module (Join-Path $srcModules 'OSDCloud.Logging.psm1') -Force

$logFile = Initialize-OSDCloudLog -Path (Join-Path $Root 'Logs') -EnableTranscript
Write-OSDCloudLog -Level Information -Component 'WinPE' -Message "=== OSDCloudEUC WinPE gestartet === (Log: $logFile)"

try {
    # Netzwerk initialisieren.
    & (Join-Path $Root 'Scripts\winpe\Initialize-Network.ps1') -Root $Root

    # GitHub-Bootstrap starten (laedt Konfiguration und entscheidet Menue vs. Zero-Touch).
    & (Join-Path $Root 'Scripts\winpe\Invoke-GitHubBootstrap.ps1') -Root $Root
} catch {
    Write-OSDCloudLogException -ErrorRecord $_ -Component 'WinPE'
    Write-Host ''
    Write-Host 'Ein Fehler ist aufgetreten. Die Eingabeaufforderung bleibt fuer die Diagnose geoeffnet.' -ForegroundColor Red
    Write-Host "Log-Datei: $logFile" -ForegroundColor Yellow
} finally {
    Stop-OSDCloudLog
}
