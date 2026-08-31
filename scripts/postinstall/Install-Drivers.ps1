<#
.SYNOPSIS
    Installiert Treiber gemaess der im Deployment-Kontext hinterlegten Strategie.
.DESCRIPTION
    Wird in der SetupComplete-Phase ausgefuehrt. Je nach DriverPlan.Source:
      DriverPack             -> von OSDCloud bereits in WinPE angewendet (hier nur Log).
      MicrosoftUpdateCatalog -> ueberlaesst Treiber dem Windows Update (Install-Updates).
      LocalFolder            -> installiert .inf-Treiber aus dem angegebenen Ordner via pnputil.
      None                   -> keine Aktion.
.PARAMETER ContextPath
    Pfad zur DeploymentContext.json.
#>
[CmdletBinding()]
param(
    [string]$ContextPath = 'C:\OSDCloud\Scripts\DeploymentContext.json'
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $ContextPath)) { Write-Host 'Kein Kontext - ueberspringe Treiber.'; return }
$context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
$plan = $context.DriverPlan

Write-Host "Treiberstrategie: $($plan.StrategyId) (Quelle: $($plan.Source))"

switch ($plan.Source) {
    'LocalFolder' {
        if ($plan.Path -and (Test-Path -LiteralPath $plan.Path)) {
            Write-Host "Installiere .inf-Treiber aus $($plan.Path) ..."
            & pnputil.exe /add-driver "$($plan.Path)\*.inf" /subdirs /install
        } else {
            Write-Host "Treiberordner nicht gefunden: $($plan.Path)"
        }
    }
    'MicrosoftUpdateCatalog' {
        Write-Host 'Treiber werden ueber Windows Update bezogen (siehe Install-Updates).'
    }
    'DriverPack' {
        Write-Host 'DriverPack wurde bereits waehrend WinPE durch OSDCloud angewendet.'
    }
    default {
        Write-Host 'Keine Treiberinstallation konfiguriert.'
    }
}
