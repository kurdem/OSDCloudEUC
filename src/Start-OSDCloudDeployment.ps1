<#
.SYNOPSIS
    Orchestriert ein OSDCloud-Deployment aus einer aufgeloesten Auswahl/Profil.
.DESCRIPTION
    Zentraler Einstiegspunkt, der in WinPE laeuft. Laedt die Module, ermittelt die
    Hardware, loest Treiber-/Update-Strategie auf, baut die Invoke-OSDCloud-Parameter
    (ueber $Global:MyOSDCloud) und startet das eigentliche Deployment. Anschliessend
    werden die Post-Install-Skripte fuer die Specialize-/OOBE-Phase bereitgestellt.

    Verwendet ausschliesslich dokumentierte Cmdlets des OSD-Moduls (Invoke-OSDCloud).
    Siehe README (Cmdlet-Matrix) und Test-OSDCloudPrerequisites.ps1.

.PARAMETER Selection
    Hashtable/Objekt mit der Feldauswahl (aus dem Menue) ODER
.PARAMETER ResolvedProfile
    Ein von Resolve-OSDCloudProfile geliefertes Profil-Objekt.
.PARAMETER Config
    Das von Get-OSDCloudConfig gelieferte Konfigurationsobjekt.
.PARAMETER WhatIf
    Fuehrt keine echten Aenderungen aus, zeigt nur die geplanten Aktionen.
.EXAMPLE
    .\Start-OSDCloudDeployment.ps1 -Config $cfg -ResolvedProfile $profile
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)] $Config,
    $Selection,
    $ResolvedProfile,
    [string]$LocalConfigRoot = 'X:\OSDCloud\Config'
)

$ErrorActionPreference = 'Stop'

# --- Module laden ---
$moduleDir = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
foreach ($m in 'OSDCloud.Logging','OSDCloud.Security','OSDCloud.Config','OSDCloud.Hardware','OSDCloud.Drivers','OSDCloud.Updates') {
    Import-Module (Join-Path -Path $moduleDir -ChildPath "$m.psm1") -Force
}

function Stage-OSDCloudPostInstall {
    <#
    .SYNOPSIS
        Kopiert Post-Install-Skripte und den Deployment-Kontext auf die Zielpartition.
    .DESCRIPTION
        OSDCloud stellt das OS unter C: bereit. Skripte werden nach
        C:\Windows\Setup\Scripts (SetupComplete) und C:\OSDCloud\Scripts kopiert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Context,
        [Parameter(Mandatory)] [string]$ScriptRoot
    )
    $targetOsdCloud = 'C:\OSDCloud\Scripts'
    $targetSetup    = 'C:\Windows\Setup\Scripts'
    foreach ($t in $targetOsdCloud, $targetSetup) {
        if (-not (Test-Path -LiteralPath $t)) {
            try { New-Item -Path $t -ItemType Directory -Force | Out-Null } catch {
                Write-OSDCloudLog -Level Warning -Component 'Deploy' -Message "Zielordner '$t' noch nicht verfuegbar (OS evtl. noch nicht angewendet)."
            }
        }
    }
    try {
        $Context | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $targetOsdCloud 'DeploymentContext.json') -Encoding UTF8
        # Post-Install-Skripte nach C:\OSDCloud\Scripts\postinstall spiegeln.
        $postDest = Join-Path $targetOsdCloud 'postinstall'
        if (-not (Test-Path -LiteralPath $postDest)) { New-Item -Path $postDest -ItemType Directory -Force | Out-Null }
        Copy-Item -Path (Join-Path $ScriptRoot 'scripts\postinstall\*') -Destination $postDest -Recurse -Force -ErrorAction SilentlyContinue
        # SetupComplete-Wrapper (.cmd) + Orchestrator (.ps1) nach C:\Windows\Setup\Scripts.
        Copy-Item -Path (Join-Path $ScriptRoot 'scripts\specialize\SetupComplete.cmd') -Destination $targetSetup -Force -ErrorAction SilentlyContinue
        Copy-Item -Path (Join-Path $ScriptRoot 'scripts\specialize\SetupComplete.ps1') -Destination $targetSetup -Force -ErrorAction SilentlyContinue
        Write-OSDCloudLog -Level Information -Component 'Deploy' -Message 'Post-Install-Skripte bereitgestellt.'
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Deploy' -Message "Post-Install-Bereitstellung teilweise fehlgeschlagen: $($_.Exception.Message)"
    }
}

Write-OSDCloudLog -Level Information -Component 'Deploy' -Message '=== Start-OSDCloudDeployment ==='

# --- Auswahl bestimmen: entweder Profil oder Menue-Auswahl ---
if (-not $ResolvedProfile -and -not $Selection) {
    throw 'Es muss entweder -ResolvedProfile oder -Selection uebergeben werden.'
}

# Hardware erkennen
$hardware = Get-OSDCloudHardware
Write-OSDCloudLog -Level Information -Component 'Deploy' -Message "Hardware: $($hardware.Manufacturer) / $($hardware.Model) (Virtuell: $($hardware.IsVirtual))"

# Auswahl in ein einheitliches Deployment-Objekt normalisieren.
if ($ResolvedProfile) {
    $deploy = $ResolvedProfile
} else {
    # Aus Menue-State ein Profil-artiges Objekt bauen (OS-Katalog aufloesen).
    $os = $Config.OperatingSystems.OperatingSystems | Where-Object { $_.Id -eq $Selection['OperatingSystem'] } | Select-Object -First 1
    if (-not $os) { throw "OperatingSystem '$($Selection['OperatingSystem'])' nicht im Katalog." }
    $deploy = [pscustomobject]@{
        ProfileId       = 'Interactive'
        DisplayName     = 'Interaktive Auswahl'
        OperatingSystem = $os
        OSName          = $os.OSName
        OSEdition       = $os.OSEdition
        OSLanguage      = if ($Selection['Language']) { $Selection['Language'].ToLower() } else { $os.OSLanguage }
        OSActivation    = $os.OSActivation
        Language        = $Selection['Language']
        KeyboardLayout  = $Selection['KeyboardLayout']
        Activation      = $Selection['Activation']
        InstallMode     = $Selection['InstallMode']
        DriverStrategy  = $Selection['DriverStrategy']
        UpdateStrategy  = $Selection['UpdateStrategy']
        Partitioning    = $Selection['Partitioning']
        JoinType        = $Selection['JoinType']
        ComputerName    = $Selection['ComputerName']
        ZeroTouch       = [bool]$Selection['ZeroTouch']
        SkipDiskWipe    = $false
        PostInstallScripts = @()
    }
}

# --- Treiber- und Update-Strategie aufloesen ---
$driverPlan = Resolve-OSDCloudDrivers -DriversConfig $Config.Drivers -Hardware $hardware -RequestedStrategy $deploy.DriverStrategy
$updatePlan = Resolve-OSDCloudUpdates -UpdatesConfig $Config.Updates -RequestedStrategy $deploy.UpdateStrategy
$driverArgs = Get-OSDCloudDriverInvokeArgs -Resolved $driverPlan

$computerName = Resolve-OSDCloudComputerName -Pattern $deploy.ComputerName -Hardware $hardware
Write-OSDCloudLog -Level Information -Component 'Deploy' -Message "Computername: $computerName"
Write-OSDCloudLog -Level Information -Component 'Deploy' -Message "Treiberstrategie: $($driverPlan.StrategyId), Update: $($updatePlan.StrategyId)"

# --- $Global:MyOSDCloud fuer Invoke-OSDCloud vorbereiten (dokumentierte Automatisierung) ---
$Global:MyOSDCloud = [ordered]@{
    OSName       = $deploy.OSName
    OSEdition    = $deploy.OSEdition
    OSLanguage   = $deploy.OSLanguage
    OSActivation = $deploy.OSActivation
    Restart      = $false
    ZTI          = [bool]$deploy.ZeroTouch
}
foreach ($k in $driverArgs.Keys) { $Global:MyOSDCloud[$k] = $driverArgs[$k] }

# Deployment-Kontext fuer Post-Install-Phase persistieren.
$context = [pscustomobject]@{
    ComputerName   = $computerName
    JoinType       = $deploy.JoinType
    UpdatePlan     = $updatePlan
    DriverPlan     = $driverPlan
    Language       = $deploy.Language
    KeyboardLayout = $deploy.KeyboardLayout
    PostInstallScripts = $deploy.PostInstallScripts
    NetworksConfig = $Config.Networks
}

# --- OSDCloud aufrufen ---
$invokeCmd = Get-Command -Name Invoke-OSDCloud -ErrorAction SilentlyContinue
if (-not $invokeCmd) {
    Write-OSDCloudLog -Level Error -Component 'Deploy' -Message 'Invoke-OSDCloud (OSD-Modul) ist nicht verfuegbar. Deployment kann nicht gestartet werden.'
    throw 'OSD-Modul mit Invoke-OSDCloud nicht gefunden. Bitte Test-OSDCloudPrerequisites.ps1 ausfuehren.'
}

Write-OSDCloudLog -Level Information -Component 'Deploy' -Message "MyOSDCloud: $($Global:MyOSDCloud | ConvertTo-Json -Compress)"

# Post-Install-Kontext bereitstellen, bevor OSDCloud das OS anwendet.
Stage-OSDCloudPostInstall -Context $context -ScriptRoot (Split-Path -Path $PSScriptRoot -Parent)

if ($PSCmdlet.ShouldProcess('Zieldatentraeger', 'Invoke-OSDCloud (Windows anwenden)')) {
    Write-OSDCloudLog -Level Information -Component 'Deploy' -Message 'Starte Invoke-OSDCloud...'
    Invoke-OSDCloud
    Write-OSDCloudLog -Level Information -Component 'Deploy' -Message 'Invoke-OSDCloud abgeschlossen.'
} else {
    Write-OSDCloudLog -Level Information -Component 'Deploy' -Message 'WhatIf: Invoke-OSDCloud wuerde jetzt ausgefuehrt.'
}
