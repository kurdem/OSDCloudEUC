<#
.SYNOPSIS
    Zero-Touch-Deployment fuer OSDCloudEUC (ohne Interaktion).
.DESCRIPTION
    Laedt die Konfiguration und ein Profil und startet das Deployment vollautomatisch.
    Die Disk-Wipe-Bestaetigung wird nur uebersprungen, wenn das Profil
    SkipDiskWipeConfirmation=true setzt oder -Force angegeben wird.
.PARAMETER ProfileId
    Zu verwendendes Profil. Standard: DefaultProfile aus global.json.
.PARAMETER LocalConfigRoot
    Wurzelverzeichnis der lokal vorliegenden Konfiguration.
.PARAMETER UseLocalConfig
    Erzwingt lokale Konfiguration statt GitHub.
.PARAMETER Force
    Ueberspringt die Disk-Wipe-Bestaetigung explizit.
.PARAMETER Token
    Optionaler GitHub-Token.
.EXAMPLE
    .\Start-ZeroTouchDeployment.ps1 -ProfileId Windows11-Test
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProfileId,
    [string]$LocalConfigRoot = 'X:\OSDCloud\Config',
    [switch]$UseLocalConfig,
    [switch]$Force,
    [string]$Token
)

$ErrorActionPreference = 'Stop'

$moduleDir = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
foreach ($m in 'OSDCloud.Logging','OSDCloud.Security','OSDCloud.Config','OSDCloud.Hardware','OSDCloud.Drivers','OSDCloud.Updates') {
    Import-Module (Join-Path -Path $moduleDir -ChildPath "$m.psm1") -Force
}

try {
    Write-OSDCloudLog -Level Information -Component 'ZeroTouch' -Message '=== Start-ZeroTouchDeployment ==='

    $config = Get-OSDCloudConfig -LocalConfigRoot $LocalConfigRoot -UseLocalGlobal:$UseLocalConfig -Token $Token

    if (-not $ProfileId) { $ProfileId = $config.Global.Deployment.DefaultProfile }
    Write-OSDCloudLog -Level Information -Component 'ZeroTouch' -Message "Verwende Profil: $ProfileId"

    $profile = Resolve-OSDCloudProfile -Config $config -ProfileId $ProfileId -LocalConfigRoot $LocalConfigRoot -Token $Token

    # Disk-Wipe-Bestaetigung: bei Zero-Touch nur ueberspringen wenn Profil oder -Force es erlaubt.
    $skipWipe = $Force.IsPresent -or $profile.SkipDiskWipe
    $requireConfirm = $config.Global.Deployment.RequireConfirmationBeforeDiskWipe
    if ($requireConfirm -and -not $skipWipe) {
        $phrase = $config.Security.DiskWipe.ConfirmationPhrase
        if (-not (Confirm-OSDCloudDiskWipe -ConfirmationPhrase $phrase)) {
            Write-OSDCloudLog -Level Warning -Component 'ZeroTouch' -Message 'Disk-Wipe nicht bestaetigt. Abbruch.'
            return
        }
    } else {
        Write-OSDCloudLog -Level Information -Component 'ZeroTouch' -Message 'Disk-Wipe-Bestaetigung uebersprungen (Zero-Touch/Force).'
    }

    & (Join-Path $PSScriptRoot 'Start-OSDCloudDeployment.ps1') -Config $config -ResolvedProfile $profile -LocalConfigRoot $LocalConfigRoot
} catch {
    Write-OSDCloudLogException -ErrorRecord $_ -Component 'ZeroTouch'
    throw
}
