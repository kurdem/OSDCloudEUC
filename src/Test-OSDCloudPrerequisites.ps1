<#
.SYNOPSIS
    Prueft die Voraussetzungen fuer OSDCloudEUC auf einer Windows-Maschine.
.DESCRIPTION
    Ermittelt Betriebssystem, PowerShell-Version, Windows-ADK sowie die installierten
    Versionen der relevanten Module (OSD, optional OSDCloud/OSDeploy/OSD.Workspace) und
    prueft, ob die im Projekt verwendeten Cmdlets tatsaechlich vorhanden sind.

    WICHTIG: Dieses Skript ist die Referenz-Verifikation. Es "erfindet" keine Cmdlets,
    sondern meldet nur, was auf DIESER Maschine vorhanden ist. Bitte die Ausgabe mit der
    Cmdlet-Matrix in der README abgleichen.

.PARAMETER MinimumOSDVersion
    Erwartete Mindestversion des OSD-Moduls. Standard: 24.1.1.
.EXAMPLE
    .\Test-OSDCloudPrerequisites.ps1
#>
[CmdletBinding()]
param(
    [version]$MinimumOSDVersion = '24.1.1'
)

$report = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Check, [string]$Status, [string]$Detail)
    $report.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
}

# --- OS / PowerShell ---
$isWin = ($env:OS -eq 'Windows_NT')
Add-Result 'Betriebssystem' ($(if ($isWin) { 'OK' } else { 'FEHLER' })) ($(if ($isWin) { 'Windows erkannt' } else { 'Kein Windows - Build/Deployment nicht moeglich' }))
Add-Result 'PowerShell-Version' 'INFO' ($PSVersionTable.PSVersion.ToString())

# --- Windows ADK (DISM/oscdimg als Indikatoren) ---
$adkPaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
    "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
Add-Result 'Windows ADK' ($(if ($adkPaths) { 'OK' } else { 'WARNUNG' })) ($(if ($adkPaths) { $adkPaths[0] } else { 'ADK nicht gefunden - fuer Build erforderlich' }))

# --- Module ---
$modules = @(
    @{ Name = 'OSD';           Required = $true;  Min = $MinimumOSDVersion },
    @{ Name = 'OSDCloud';      Required = $false; Min = $null },
    @{ Name = 'OSDeploy';      Required = $false; Min = $null },
    @{ Name = 'OSD.Workspace'; Required = $false; Min = $null }
)
foreach ($m in $modules) {
    $installed = Get-Module -ListAvailable -Name $m.Name | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed) {
        $status = 'OK'
        if ($m.Min -and $installed.Version -lt $m.Min) { $status = 'WARNUNG' }
        Add-Result "Modul $($m.Name)" $status "Version $($installed.Version)$(if ($m.Min) { " (min. $($m.Min))" })"
    } else {
        Add-Result "Modul $($m.Name)" ($(if ($m.Required) { 'FEHLER' } else { 'INFO' })) ($(if ($m.Required) { 'Nicht installiert - Install-Module OSD -Force' } else { 'Optional, nicht installiert' }))
    }
}

# --- Verwendete Cmdlets (Soll-Liste, gegen Ist pruefen) ---
$expectedCmdlets = @(
    @{ Name = 'New-OSDCloudTemplate';  Module = 'OSD' },
    @{ Name = 'New-OSDCloudWorkspace'; Module = 'OSD' },
    @{ Name = 'Edit-OSDCloudWinPE';    Module = 'OSD' },
    @{ Name = 'New-OSDCloudISO';       Module = 'OSD' },
    @{ Name = 'New-OSDCloudUSB';       Module = 'OSD' },
    @{ Name = 'Update-OSDCloudUSB';    Module = 'OSD' },
    @{ Name = 'Invoke-OSDCloud';       Module = 'OSD' },
    @{ Name = 'Start-OSDCloud';        Module = 'OSD' }
)
foreach ($c in $expectedCmdlets) {
    $cmd = Get-Command -Name $c.Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Add-Result "Cmdlet $($c.Name)" 'OK' "gefunden in $($cmd.Source) $($cmd.Version)"
    } else {
        Add-Result "Cmdlet $($c.Name)" 'FEHLER' "nicht gefunden (erwartet aus $($c.Module))"
    }
}

# --- Ausgabe ---
$report | Format-Table -AutoSize

$errors = @($report | Where-Object { $_.Status -eq 'FEHLER' })
if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host "$($errors.Count) kritische(r) Fehler. Bitte beheben, bevor gebaut/deployt wird." -ForegroundColor Red
    exit 1
} else {
    Write-Host ''
    Write-Host 'Alle Pflicht-Voraussetzungen erfuellt.' -ForegroundColor Green
    exit 0
}
