<#
.SYNOPSIS
    Erstellt das OSDCloud-WinPE, bettet die OSDCloudEUC-Konfiguration ein und baut ein ISO.
.DESCRIPTION
    Muss auf einer Windows-Maschine mit installiertem Windows ADK und dem OSD-Modul laufen
    (NICHT in WinPE). Fuehrt die dokumentierten OSD-Cmdlets aus:
      New-OSDCloudTemplate  -> Basis-Template inkl. WinRE/WLAN
      New-OSDCloudWorkspace -> Arbeitsverzeichnis fuer Medien
      (Kopiert config/, profiles/, scripts/, src/modules/ als lokale Fallback-Quelle in die Media)
      Edit-OSDCloudWinPE    -> Treiber, OSD-Modul und Start-Befehl injizieren
      New-OSDCloudISO       -> bootfaehiges ISO erzeugen

    Alle OSD-Cmdlets werden vor der Verwendung auf Verfuegbarkeit geprueft. Ohne das
    OSD-Modul bricht das Skript mit einer klaren Meldung ab (siehe Test-OSDCloudPrerequisites.ps1).

.PARAMETER WorkspacePath
    Zielverzeichnis fuer den OSDCloud-Workspace.
.PARAMETER TemplateName
    Name des OSDCloud-Templates.
.PARAMETER StartMode
    Was WinPE beim Start ausfuehrt: 'Bootstrap' (GitHub-Bootstrap-Skript) oder 'Menu' (lokales Menue).
.PARAMETER WirelessConnect
    Aktiviert die WLAN-Verbindungshilfe im WinPE.
.EXAMPLE
    .\Build-OSDCloudMedia.ps1 -WorkspacePath C:\OSDCloud\Workspace
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$WorkspacePath = 'C:\OSDCloud\Workspace',
    [string]$TemplateName = 'OSDCloudEUC',
    [ValidateSet('Bootstrap','Menu')]
    [string]$StartMode = 'Bootstrap',
    [switch]$WirelessConnect
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

Write-OSDCloudLog -Level Information -Component 'Build' -Message '=== Build-OSDCloudMedia ==='

if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw 'Build-OSDCloudMedia muss unter Windows mit installiertem ADK ausgefuehrt werden.'
}

foreach ($c in @(
    @{ Name = 'New-OSDCloudTemplate';  Module = 'OSD' },
    @{ Name = 'New-OSDCloudWorkspace'; Module = 'OSD' },
    @{ Name = 'Edit-OSDCloudWinPE';    Module = 'OSD' },
    @{ Name = 'New-OSDCloudISO';       Module = 'OSD' }
)) { Assert-Command -Name $c.Name -Module $c.Module }

# --- 1. Template erstellen ---
if ($PSCmdlet.ShouldProcess($TemplateName, 'New-OSDCloudTemplate')) {
    Write-OSDCloudLog -Level Information -Component 'Build' -Message "Erstelle OSDCloud-Template '$TemplateName' (WinRE)."
    New-OSDCloudTemplate -Name $TemplateName -WinRE
}

# --- 2. Workspace erstellen ---
if ($PSCmdlet.ShouldProcess($WorkspacePath, 'New-OSDCloudWorkspace')) {
    Write-OSDCloudLog -Level Information -Component 'Build' -Message "Erstelle Workspace unter '$WorkspacePath'."
    New-OSDCloudWorkspace -WorkspacePath $WorkspacePath
}

# --- 3. Konfiguration als lokale Fallback-Quelle in die Media kopieren ---
$mediaConfigRoot = Join-Path $WorkspacePath 'Media\OSDCloud'
if ($PSCmdlet.ShouldProcess($mediaConfigRoot, 'Konfiguration einbetten')) {
    foreach ($sub in 'config','profiles') {
        $dest = Join-Path $mediaConfigRoot (Split-Path $sub -Leaf)
        New-Item -Path $dest -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $repoRoot "$sub\*") -Destination $dest -Recurse -Force
    }
    # Skripte und Module fuer den WinPE-Ablauf.
    $destScripts = Join-Path $mediaConfigRoot 'Scripts'
    New-Item -Path $destScripts -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'scripts\*') -Destination $destScripts -Recurse -Force
    Copy-Item -Path (Join-Path $repoRoot 'src') -Destination $mediaConfigRoot -Recurse -Force
    Write-OSDCloudLog -Level Information -Component 'Build' -Message 'Konfiguration, Profile, Skripte und Module eingebettet.'
}

# --- 4. WinPE anpassen: Treiber, OSD-Modul, Start-Befehl ---
# Der Start-Befehl ruft unseren WinPE-Startnet-Ablauf auf (Netz + Bootstrap/Menue).
$startPs = if ($StartMode -eq 'Menu') {
    'powershell -NoL -ExecutionPolicy Bypass -File X:\OSDCloud\src\Start-DeploymentMenu.ps1 -LocalConfigRoot X:\OSDCloud\config -UseLocalConfig'
} else {
    'powershell -NoL -ExecutionPolicy Bypass -File X:\OSDCloud\Scripts\winpe\Startnet.ps1'
}

if ($PSCmdlet.ShouldProcess('boot.wim', 'Edit-OSDCloudWinPE')) {
    Write-OSDCloudLog -Level Information -Component 'Build' -Message 'Passe WinPE an (Treiber, OSD-Modul, Startbefehl).'
    $editParams = @{
        CloudDriver     = '*'
        PSModuleInstall = 'OSD'
        StartPSCommand  = $startPs
    }
    if ($WirelessConnect) { $editParams['WirelessConnect'] = $true }
    Edit-OSDCloudWinPE @editParams
}

# --- 5. ISO bauen ---
if ($PSCmdlet.ShouldProcess($WorkspacePath, 'New-OSDCloudISO')) {
    Write-OSDCloudLog -Level Information -Component 'Build' -Message 'Erzeuge bootfaehiges ISO.'
    $iso = New-OSDCloudISO
    Write-OSDCloudLog -Level Information -Component 'Build' -Message "ISO erstellt: $($iso.FullName)"
}

Write-OSDCloudLog -Level Information -Component 'Build' -Message 'Build abgeschlossen.'
