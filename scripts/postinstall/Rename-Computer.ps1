<#
.SYNOPSIS
    Setzt den Computernamen aus dem Deployment-Kontext.
.DESCRIPTION
    Wird in der SetupComplete-Phase ausgefuehrt. Der Name wurde bereits im WinPE aus dem
    Muster (z. B. %SERIAL%) aufgeloest und im Kontext hinterlegt. Ein Umbenennen erfordert
    ggf. einen Neustart; dieser wird der uebergeordneten OOBE/Enrollment-Phase ueberlassen.
.PARAMETER ContextPath
    Pfad zur DeploymentContext.json.
#>
[CmdletBinding()]
param(
    [string]$ContextPath = 'C:\OSDCloud\Scripts\DeploymentContext.json'
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $ContextPath)) { Write-Host 'Kein Kontext - ueberspringe Umbenennung.'; return }
$context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
$name = $context.ComputerName

if ([string]::IsNullOrWhiteSpace($name)) { Write-Host 'Kein Computername im Kontext.'; return }

$current = $env:COMPUTERNAME
if ($current -eq $name) {
    Write-Host "Computername ist bereits '$name'."
    return
}

Write-Host "Benenne Computer von '$current' nach '$name' um ..."
try {
    Rename-Computer -NewName $name -Force -ErrorAction Stop
    Write-Host "Umbenennung erfolgreich (wirksam nach Neustart)."
} catch {
    Write-Host "Umbenennung fehlgeschlagen: $($_.Exception.Message)"
}
