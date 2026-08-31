<#
.SYNOPSIS
    Post-Deployment-Orchestrator (SetupComplete-Phase).
.DESCRIPTION
    Wird nach dem Anwenden von Windows im Rahmen der SetupComplete-Phase ausgefuehrt
    (Windows startet automatisch C:\Windows\Setup\Scripts\SetupComplete.cmd; dieser Wrapper
    ruft dieses PowerShell-Skript auf). Liest den vom WinPE-Deployment abgelegten
    Kontext (C:\OSDCloud\Scripts\DeploymentContext.json) und fuehrt die konfigurierten
    Post-Install-Skripte in definierter Reihenfolge aus.

    Reihenfolge: Treiber -> Updates -> Computername -> Enrollment (Domain/Entra/Workgroup).
#>
[CmdletBinding()]
param(
    [string]$ScriptRoot = 'C:\OSDCloud\Scripts',
    [string]$ContextPath = 'C:\OSDCloud\Scripts\DeploymentContext.json'
)

$ErrorActionPreference = 'Continue'  # Post-Install soll nicht am ersten Fehler abbrechen.

$logDir = 'C:\OSDCloud\Logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$log = Join-Path $logDir ("SetupComplete-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function Write-Log { param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $log -Value $line
    Write-Host $line
}

Write-Log '=== SetupComplete gestartet ==='

if (-not (Test-Path -LiteralPath $ContextPath)) {
    Write-Log "Kein Deployment-Kontext gefunden ($ContextPath). Ueberspringe Post-Install." 'WARN'
    return
}

try {
    $context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
} catch {
    Write-Log "Kontext konnte nicht gelesen werden: $($_.Exception.Message)" 'ERROR'
    return
}

# Reihenfolge der Post-Install-Schritte.
$steps = @(
    @{ Name = 'Treiber';     Script = 'postinstall\Install-Drivers.ps1' },
    @{ Name = 'Updates';     Script = 'postinstall\Install-Updates.ps1' },
    @{ Name = 'Computername';Script = 'postinstall\Rename-Computer.ps1' },
    @{ Name = 'Enrollment';  Script = 'postinstall\Invoke-Enrollment.ps1' }
)

foreach ($step in $steps) {
    $scriptPath = Join-Path $ScriptRoot $step.Script
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        Write-Log "Skript fuer '$($step.Name)' nicht gefunden: $scriptPath" 'WARN'
        continue
    }
    Write-Log "Starte Schritt: $($step.Name)"
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ContextPath $ContextPath
        Write-Log "Schritt '$($step.Name)' abgeschlossen (ExitCode $LASTEXITCODE)."
    } catch {
        Write-Log "Schritt '$($step.Name)' fehlgeschlagen: $($_.Exception.Message)" 'ERROR'
    }
}

Write-Log '=== SetupComplete beendet ==='
