<#
.SYNOPSIS
    Installiert Windows-Updates gemaess der im Deployment-Kontext hinterlegten Strategie.
.DESCRIPTION
    Wird in der SetupComplete-Phase ausgefuehrt. Nutzt bevorzugt das Modul PSWindowsUpdate,
    faellt sonst auf USOClient (Windows Update Agent) bzw. Defender-Signatur-Update zurueck.
      AllUpdates   -> alle Kategorien (inkl. Treiber, falls IncludeDrivers).
      SecurityOnly -> nur Sicherheits-/kritische Updates.
      DefenderOnly -> nur Defender-Definitionen.
      None         -> keine Aktion.
.PARAMETER ContextPath
    Pfad zur DeploymentContext.json.
#>
[CmdletBinding()]
param(
    [string]$ContextPath = 'C:\OSDCloud\Scripts\DeploymentContext.json'
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $ContextPath)) { Write-Host 'Kein Kontext - ueberspringe Updates.'; return }
$context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
$plan = $context.UpdatePlan

Write-Host "Update-Strategie: $($plan.StrategyId) (Methode: $($plan.Method))"

if ($plan.Method -eq 'None') { Write-Host 'Keine Updates konfiguriert.'; return }

function Update-DefenderSignatures {
    $mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (Test-Path -LiteralPath $mp) {
        Write-Host 'Aktualisiere Microsoft-Defender-Signaturen ...'
        & $mp -SignatureUpdate
    } else {
        try { Update-MpSignature -ErrorAction Stop; Write-Host 'Defender-Signaturen via Update-MpSignature aktualisiert.' }
        catch { Write-Host "Defender-Signaturupdate nicht moeglich: $($_.Exception.Message)" }
    }
}

if ($plan.Method -eq 'DefenderSignature') {
    Update-DefenderSignatures
    return
}

# PSWindowsUpdate bevorzugen.
$pswu = Get-Module -ListAvailable -Name PSWindowsUpdate | Select-Object -First 1
if ($pswu) {
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        $criteria = if ($plan.Categories -contains 'Feature') { '' } else { "CategoryIDs" }
        Write-Host 'Installiere Updates via PSWindowsUpdate ...'
        if ($plan.StrategyId -eq 'SecurityOnly') {
            Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Category 'Security Updates','Critical Updates' -ErrorAction Stop
        } else {
            $params = @{ AcceptAll = $true; Install = $true; IgnoreReboot = $true }
            if (-not $plan.IncludeDrivers) { $params['NotCategory'] = 'Drivers' }
            Get-WindowsUpdate @params -ErrorAction Stop
        }
        Write-Host 'PSWindowsUpdate abgeschlossen.'
        return
    } catch {
        Write-Host "PSWindowsUpdate fehlgeschlagen: $($_.Exception.Message). Fallback auf USOClient."
    }
}

# Fallback: Windows Update Agent anstossen.
Write-Host 'Starte Windows Update ueber USOClient (Fallback) ...'
& usoclient.exe StartScan
& usoclient.exe StartDownload
& usoclient.exe StartInstall
