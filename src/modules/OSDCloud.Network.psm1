<#
.SYNOPSIS
    Netzwerk-Initialisierung und Konnektivitaetspruefung fuer WinPE.
.DESCRIPTION
    Initialisiert Netzwerk (wpeinit), prueft DNS/Zeit und testet die Erreichbarkeit
    der konfigurierten Hosts. Kompatibel mit Windows PowerShell 5.1 (WinPE) und PS7.
#>

Set-StrictMode -Version Latest

function Initialize-OSDCloudNetwork {
    <#
    .SYNOPSIS
        Initialisiert die Netzwerkumgebung in WinPE.
    .DESCRIPTION
        Ruft wpeinit auf (falls in WinPE vorhanden) und wartet, bis eine IP-Adresse
        bezogen wurde. Ausserhalb von WinPE ist die Funktion ein No-Op mit Log-Hinweis.
    .PARAMETER WaitSeconds
        Maximale Wartezeit auf eine gueltige IP-Adresse.
    #>
    [CmdletBinding()]
    param([int]$WaitSeconds = 60)

    $wpeinit = Join-Path -Path $env:SystemRoot -ChildPath 'System32\wpeinit.exe'
    if (Test-Path -LiteralPath $wpeinit) {
        Write-OSDCloudLog -Level Information -Component 'Network' -Message 'Starte wpeinit...'
        try {
            Start-Process -FilePath $wpeinit -Wait -NoNewWindow -ErrorAction Stop
        } catch {
            Write-OSDCloudLog -Level Warning -Component 'Network' -Message "wpeinit fehlgeschlagen: $($_.Exception.Message)"
        }
    } else {
        Write-OSDCloudLog -Level Debug -Component 'Network' -Message 'wpeinit nicht gefunden (kein WinPE?). Ueberspringe.'
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-OSDCloudHasIpAddress) {
            Write-OSDCloudLog -Level Information -Component 'Network' -Message 'IP-Adresse bezogen.'
            return $true
        }
        Start-Sleep -Seconds 3
    }
    Write-OSDCloudLog -Level Warning -Component 'Network' -Message 'Keine gueltige IP-Adresse innerhalb der Wartezeit.'
    return $false
}

function Test-OSDCloudHasIpAddress {
    <#
    .SYNOPSIS
        Prueft, ob eine nicht-lokale IPv4-Adresse gebunden ist.
    #>
    [CmdletBinding()]
    param()
    try {
        $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' }
        return [bool]$addresses
    } catch {
        # Get-NetIPAddress evtl. nicht verfuegbar -> ipconfig-Fallback.
        $out = & ipconfig 2>$null | Select-String -SimpleMatch 'IPv4'
        return [bool]($out -and ($out -notmatch '169\.254\.'))
    }
}

function Test-OSDCloudConnectivity {
    <#
    .SYNOPSIS
        Testet die HTTPS-Erreichbarkeit der angegebenen Hosts.
    .PARAMETER TargetHosts
        Liste der zu pruefenden Hostnamen.
    .PARAMETER TimeoutSeconds
        Timeout je Host.
    .OUTPUTS
        [bool] $true wenn mindestens ein Host erreichbar ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$TargetHosts,
        [int]$TimeoutSeconds = 15
    )

    $anyReachable = $false
    foreach ($h in $TargetHosts) {
        try {
            $uri = "https://$h"
            $null = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            Write-OSDCloudLog -Level Information -Component 'Network' -Message "Host erreichbar: $h"
            $anyReachable = $true
        } catch {
            # Auch ein HTTP-Fehlercode (403/404) bedeutet Erreichbarkeit auf Transportebene.
            if ($_.Exception.Response) {
                Write-OSDCloudLog -Level Information -Component 'Network' -Message "Host erreichbar (HTTP-Antwort): $h"
                $anyReachable = $true
            } else {
                Write-OSDCloudLog -Level Warning -Component 'Network' -Message "Host nicht erreichbar: $h ($($_.Exception.Message))"
            }
        }
    }
    return $anyReachable
}

function Set-OSDCloudDnsServer {
    <#
    .SYNOPSIS
        Setzt bevorzugte DNS-Server auf allen aktiven IPv4-Adaptern.
    .PARAMETER Servers
        Liste der DNS-Server-Adressen.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]]$Servers)

    if (-not $Servers -or $Servers.Count -eq 0) { return }
    try {
        $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }
        foreach ($a in $adapters) {
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $Servers -ErrorAction Stop
            Write-OSDCloudLog -Level Information -Component 'Network' -Message "DNS gesetzt auf Adapter $($a.Name): $($Servers -join ', ')"
        }
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Network' -Message "DNS konnte nicht gesetzt werden: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Initialize-OSDCloudNetwork, Test-OSDCloudHasIpAddress, Test-OSDCloudConnectivity, Set-OSDCloudDnsServer
