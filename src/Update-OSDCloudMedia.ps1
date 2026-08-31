<#
.SYNOPSIS
    Erstellt oder aktualisiert einen bootfaehigen OSDCloud-USB-Stick.
.DESCRIPTION
    Muss auf einer Windows-Maschine mit dem OSD-Modul und einem vorhandenen
    OSDCloud-Workspace laufen. Nutzt die dokumentierten Cmdlets:
      New-OSDCloudUSB    -> erstellt einen neuen OSDCloud-USB (WinPE + Datenpartition)
      Update-OSDCloudUSB -> aktualisiert WinPE und optional OS/DriverPacks auf dem USB

    Kopiert anschliessend die aktuelle OSDCloudEUC-Konfiguration auf die USB-Datenpartition,
    sodass ein lokaler Fallback verfuegbar ist.

.PARAMETER Mode
    'New' erstellt einen neuen USB, 'Update' aktualisiert einen vorhandenen.
.PARAMETER WorkspacePath
    Pfad zum OSDCloud-Workspace.
.PARAMETER DriveLabel
    Label der WinPE-Partition (fuer das Auffinden des USB).
.EXAMPLE
    .\Update-OSDCloudMedia.ps1 -Mode New
.EXAMPLE
    .\Update-OSDCloudMedia.ps1 -Mode Update
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('New','Update')]
    [string]$Mode = 'Update',
    [string]$WorkspacePath = 'C:\OSDCloud\Workspace',
    [string]$DriveLabel = 'WinPE'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

Import-Module (Join-Path $PSScriptRoot 'modules\OSDCloud.Logging.psm1') -Force
Initialize-OSDCloudLog | Out-Null

function Assert-Command {
    param([string]$Name, [string]$Module)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Cmdlet '$Name' (Modul $Module) nicht gefunden. Bitte OSD-Modul installieren: Install-Module OSD -Force"
    }
}

Write-OSDCloudLog -Level Information -Component 'USB' -Message "=== Update-OSDCloudMedia (Mode=$Mode) ==="

if ($Mode -eq 'New') {
    Assert-Command -Name 'New-OSDCloudUSB' -Module 'OSD'
    if ($PSCmdlet.ShouldProcess('USB', 'New-OSDCloudUSB')) {
        Write-OSDCloudLog -Level Information -Component 'USB' -Message 'Erstelle neuen OSDCloud-USB.'
        New-OSDCloudUSB -WorkspacePath $WorkspacePath
    }
} else {
    Assert-Command -Name 'Update-OSDCloudUSB' -Module 'OSD'
    if ($PSCmdlet.ShouldProcess('USB', 'Update-OSDCloudUSB')) {
        Write-OSDCloudLog -Level Information -Component 'USB' -Message 'Aktualisiere WinPE auf dem OSDCloud-USB.'
        Update-OSDCloudUSB
    }
}

# --- Konfiguration auf die USB-Datenpartition (OSDCloud) kopieren ---
$usbVolume = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' } | Select-Object -First 1
if ($usbVolume -and $usbVolume.DriveLetter) {
    $target = "$($usbVolume.DriveLetter):\OSDCloud"
    if ($PSCmdlet.ShouldProcess($target, 'Konfiguration kopieren')) {
        foreach ($sub in 'config','profiles') {
            $dest = Join-Path $target (Split-Path $sub -Leaf)
            New-Item -Path $dest -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $repoRoot "$sub\*") -Destination $dest -Recurse -Force
        }
        Copy-Item -Path (Join-Path $repoRoot 'src') -Destination $target -Recurse -Force
        Copy-Item -Path (Join-Path $repoRoot 'scripts') -Destination $target -Recurse -Force
        Write-OSDCloudLog -Level Information -Component 'USB' -Message "Konfiguration nach $target kopiert."
    }
} else {
    Write-OSDCloudLog -Level Warning -Component 'USB' -Message 'OSDCloud-Datenpartition nicht gefunden. Konfiguration nicht kopiert.'
}

Write-OSDCloudLog -Level Information -Component 'USB' -Message 'USB-Vorgang abgeschlossen.'
