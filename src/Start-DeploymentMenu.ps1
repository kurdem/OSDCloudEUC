<#
.SYNOPSIS
    Interaktiver Menue-Flow fuer OSDCloudEUC.
.DESCRIPTION
    Laedt die Konfiguration, erkennt die Hardware, zeigt das konsolenbasierte Menue
    (datengetrieben aus deployments.json) und startet nach Bestaetigung das Deployment.
.PARAMETER LocalConfigRoot
    Wurzelverzeichnis der lokal vorliegenden Konfiguration (Fallback / Bootstrapping).
.PARAMETER UseLocalConfig
    Erzwingt das Laden der Konfiguration aus dem lokalen Verzeichnis statt aus GitHub.
.PARAMETER Token
    Optionaler GitHub-Token fuer private Repositories.
.EXAMPLE
    .\Start-DeploymentMenu.ps1 -LocalConfigRoot X:\OSDCloud\Config
#>
[CmdletBinding()]
param(
    [string]$LocalConfigRoot = 'X:\OSDCloud\Config',
    [switch]$UseLocalConfig,
    [string]$Token
)

$ErrorActionPreference = 'Stop'

$moduleDir = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
foreach ($m in 'OSDCloud.Logging','OSDCloud.Security','OSDCloud.Config','OSDCloud.Menu','OSDCloud.Hardware','OSDCloud.Drivers','OSDCloud.Updates') {
    Import-Module (Join-Path -Path $moduleDir -ChildPath "$m.psm1") -Force
}

try {
    Write-OSDCloudLog -Level Information -Component 'Menu' -Message '=== Start-DeploymentMenu ==='

    $config = Get-OSDCloudConfig -LocalConfigRoot $LocalConfigRoot -UseLocalGlobal:$UseLocalConfig -Token $Token

    if (-not $config.Global.Deployment.EnableInteractiveMenu) {
        Write-OSDCloudLog -Level Warning -Component 'Menu' -Message 'Interaktives Menue ist in global.json deaktiviert. Verwende Standardprofil.'
        $profile = Resolve-OSDCloudProfile -Config $config -ProfileId $config.Global.Deployment.DefaultProfile -LocalConfigRoot $LocalConfigRoot -Token $Token
        & (Join-Path $PSScriptRoot 'Start-OSDCloudDeployment.ps1') -Config $config -ResolvedProfile $profile -LocalConfigRoot $LocalConfigRoot
        return
    }

    $hardware = Get-OSDCloudHardware

    # Startzustand aus dem Standardprofil vorbelegen.
    $initialState = New-OSDCloudSelectionState -Deployments $config.Deployments
    try {
        $defaultProfile = Resolve-OSDCloudProfile -Config $config -ProfileId $config.Global.Deployment.DefaultProfile -LocalConfigRoot $LocalConfigRoot -Token $Token
        foreach ($map in @{
            Profile        = $defaultProfile.ProfileId
            OperatingSystem= $defaultProfile.OperatingSystem.Id
            Language       = $defaultProfile.Language
            KeyboardLayout = $defaultProfile.KeyboardLayout
            Activation     = $defaultProfile.Activation
            InstallMode    = $defaultProfile.InstallMode
            DriverStrategy = $defaultProfile.DriverStrategy
            UpdateStrategy = $defaultProfile.UpdateStrategy
            Partitioning   = $defaultProfile.Partitioning
            JoinType       = $defaultProfile.JoinType
            ComputerName   = $defaultProfile.ComputerName
        }.GetEnumerator()) {
            if ($initialState.Contains($map.Key)) { $initialState[$map.Key] = $map.Value }
        }
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Menu' -Message "Standardprofil konnte nicht vorbelegt werden: $($_.Exception.Message)"
    }

    $result = Show-OSDCloudMenu -Deployments $config.Deployments -Hardware $hardware -InitialState $initialState

    switch ($result.Action) {
        'StartDeploy' {
            Write-OSDCloudLog -Level Information -Component 'Menu' -Message 'Menueauswahl bestaetigt. Starte Deployment.'
            & (Join-Path $PSScriptRoot 'Start-OSDCloudDeployment.ps1') -Config $config -Selection $result.State -LocalConfigRoot $LocalConfigRoot
        }
        'Reboot' {
            Write-OSDCloudLog -Level Information -Component 'Menu' -Message 'Neustart angefordert.'
            if (Get-Command wpeutil -ErrorAction SilentlyContinue) { & wpeutil reboot } else { Restart-Computer -Force }
        }
        'Shell' {
            Write-OSDCloudLog -Level Information -Component 'Menu' -Message 'PowerShell-Shell angefordert. Menue beendet.'
        }
        'Cancel' {
            Write-OSDCloudLog -Level Information -Component 'Menu' -Message 'Menue abgebrochen.'
        }
    }
} catch {
    Write-OSDCloudLogException -ErrorRecord $_ -Component 'Menu'
    throw
}
