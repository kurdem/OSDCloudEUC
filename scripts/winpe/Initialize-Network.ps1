<#
.SYNOPSIS
    Initialisiert das Netzwerk in WinPE und prueft die Konnektivitaet.
.DESCRIPTION
    Startet wpeinit, wartet auf eine IP-Adresse, setzt optional DNS-Server aus networks.json
    (lokale Kopie) und testet die Erreichbarkeit der AllowedHosts aus global.json.
.PARAMETER Root
    Wurzelverzeichnis der WinPE-Ablage.
#>
[CmdletBinding()]
param(
    [string]$Root = 'X:\OSDCloud'
)

$ErrorActionPreference = 'Stop'

$srcModules = Join-Path $Root 'src\modules'
Import-Module (Join-Path $srcModules 'OSDCloud.Logging.psm1') -Force
Import-Module (Join-Path $srcModules 'OSDCloud.Network.psm1') -Force

Write-OSDCloudLog -Level Information -Component 'Network' -Message 'Initialisiere Netzwerk...'
$null = Initialize-OSDCloudNetwork -WaitSeconds 60

# Optional DNS aus lokaler networks.json setzen.
$networksPath = Join-Path $Root 'config\networks.json'
if (Test-Path -LiteralPath $networksPath) {
    try {
        $networks = Get-Content -LiteralPath $networksPath -Raw | ConvertFrom-Json
        if ($networks.Dns -and -not $networks.Dns.UseDhcp -and $networks.Dns.PreferredServers.Count -gt 0) {
            Set-OSDCloudDnsServer -Servers $networks.Dns.PreferredServers
        }
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Network' -Message "networks.json konnte nicht gelesen werden: $($_.Exception.Message)"
    }
}

# Konnektivitaet gegen AllowedHosts pruefen.
$globalPath = Join-Path $Root 'config\global.json'
if (Test-Path -LiteralPath $globalPath) {
    try {
        $global = Get-Content -LiteralPath $globalPath -Raw | ConvertFrom-Json
        $reachable = Test-OSDCloudConnectivity -TargetHosts $global.Security.AllowedHosts -TimeoutSeconds ($global.Network.TimeoutSeconds)
        if (-not $reachable) {
            Write-OSDCloudLog -Level Warning -Component 'Network' -Message 'Keiner der AllowedHosts erreichbar. Es wird auf lokale Konfiguration zurueckgegriffen.'
        }
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Network' -Message "Konnektivitaetspruefung fehlgeschlagen: $($_.Exception.Message)"
    }
}
