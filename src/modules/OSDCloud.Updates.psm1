<#
.SYNOPSIS
    Windows-Update-Strategie-Aufloesung fuer OSDCloudEUC.
.DESCRIPTION
    Loest die updates.json-Strategie in konkrete Aktionen auf, die von den
    Post-Install-Skripten (postinstall/Install-Updates.ps1) ausgefuehrt werden.
    Kompatibel mit WinPE (PS 5.1) und PS7.
#>

Set-StrictMode -Version Latest

function Resolve-OSDCloudUpdates {
    <#
    .SYNOPSIS
        Loest die Update-Strategie in eine ausfuehrbare Beschreibung auf.
    .PARAMETER UpdatesConfig
        Das updates.json-Objekt.
    .PARAMETER RequestedStrategy
        Gewuenschte Strategie-Id (AllUpdates, SecurityOnly, DefenderOnly, None).
    .OUTPUTS
        [pscustomobject] mit StrategyId, Categories, IncludeDrivers, Method, Fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $UpdatesConfig,
        [Parameter(Mandatory)] [string]$RequestedStrategy
    )

    $strategyId = $RequestedStrategy
    if (-not ($UpdatesConfig.Strategies.PSObject.Properties.Name -contains $strategyId)) {
        Write-OSDCloudLog -Level Warning -Component 'Updates' -Message "Unbekannte Update-Strategie '$strategyId'. Verwende 'None'."
        $strategyId = 'None'
    }

    $strategy = $UpdatesConfig.Strategies.$strategyId
    $fallbackMethod = if ($UpdatesConfig.PSObject.Properties.Name -contains 'Fallback') { $UpdatesConfig.Fallback.Method } else { 'None' }

    return [pscustomobject]@{
        StrategyId     = $strategyId
        Categories     = @($strategy.Categories)
        IncludeDrivers = [bool]$strategy.IncludeDrivers
        Method         = $strategy.Method
        FallbackMethod = $fallbackMethod
        Description    = $strategy.Description
    }
}

Export-ModuleMember -Function Resolve-OSDCloudUpdates
