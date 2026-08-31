<#
.SYNOPSIS
    Treiberstrategie-Aufloesung fuer OSDCloudEUC.
.DESCRIPTION
    Bestimmt anhand der drivers.json-Konfiguration und der erkannten Hardware, welche
    Treiberquelle verwendet wird, und liefert die passenden Invoke-OSDCloud-Parameter.
    Kompatibel mit WinPE (PS 5.1) und PS7.
#>

Set-StrictMode -Version Latest

function Resolve-OSDCloudDrivers {
    <#
    .SYNOPSIS
        Loest die Treiberstrategie fuer die gegebene Hardware auf.
    .PARAMETER DriversConfig
        Das drivers.json-Objekt.
    .PARAMETER Hardware
        Das von Get-OSDCloudHardware gelieferte Objekt.
    .PARAMETER RequestedStrategy
        Vom Profil/Menue gewuenschte Strategie. Ein Modell-Mapping kann sie ueberschreiben.
    .OUTPUTS
        [pscustomobject] mit StrategyId, Source, ApplyDuringWinPE, Path, Description.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $DriversConfig,
        [Parameter(Mandatory)] $Hardware,
        [Parameter(Mandatory)] [string]$RequestedStrategy
    )

    $strategyId = $RequestedStrategy

    # Modell-Mapping pruefen (spezifischer als die Profil-Vorgabe).
    $mapping = $DriversConfig.ModelMappings | Where-Object {
        ($_.Manufacturer -eq '*' -or $_.Manufacturer -eq $Hardware.Manufacturer) -and
        ($_.Model -eq '*' -or $Hardware.Model -like "*$($_.Model)*")
    } | Select-Object -First 1

    if ($mapping) {
        Write-OSDCloudLog -Level Information -Component 'Drivers' -Message "Modell-Mapping getroffen: $($Hardware.Manufacturer) / $($Hardware.Model) -> Strategie $($mapping.Strategy)"
        $strategyId = $mapping.Strategy
    }

    if (-not ($DriversConfig.Strategies.PSObject.Properties.Name -contains $strategyId)) {
        Write-OSDCloudLog -Level Warning -Component 'Drivers' -Message "Unbekannte Treiberstrategie '$strategyId'. Verwende 'None'."
        $strategyId = 'None'
    }

    $strategy = $DriversConfig.Strategies.$strategyId
    $path = if ($strategy.PSObject.Properties.Name -contains 'Path') { $strategy.Path } else { $null }

    return [pscustomobject]@{
        StrategyId       = $strategyId
        Source           = $strategy.Source
        ApplyDuringWinPE = [bool]$strategy.ApplyDuringWinPE
        Path             = $path
        Description      = $strategy.Description
    }
}

function Get-OSDCloudDriverInvokeArgs {
    <#
    .SYNOPSIS
        Uebersetzt eine aufgeloeste Treiberstrategie in ergaenzende Invoke-OSDCloud-Optionen.
    .DESCRIPTION
        Liefert eine Hashtable, die vom Orchestrator in das $Global:MyOSDCloud-Objekt bzw.
        die Invoke-OSDCloud-Aufrufparameter gemergt wird. OSDCloud waehlt DriverPacks anhand
        des Modells automatisch; 'None' unterdrueckt DriverPacks.
    .PARAMETER Resolved
        Ergebnis von Resolve-OSDCloudDrivers.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Resolved)

    $args = @{}
    switch ($Resolved.Source) {
        'DriverPack' {
            # OSDCloud laedt DriverPack automatisch anhand Hersteller/Modell.
            $args['DriverPackName'] = 'auto'
        }
        'MicrosoftUpdateCatalog' {
            $args['DriverPackName'] = 'None'  # keine DriverPacks; Treiber via Windows Update / Catalog nach OOBE.
        }
        'LocalFolder' {
            $args['DriverPath'] = $Resolved.Path
        }
        'None' {
            $args['DriverPackName'] = 'None'
        }
    }
    return $args
}

Export-ModuleMember -Function Resolve-OSDCloudDrivers, Get-OSDCloudDriverInvokeArgs
