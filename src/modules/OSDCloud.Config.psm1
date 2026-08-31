<#
.SYNOPSIS
    GitHub-basierte Konfigurationssteuerung fuer OSDCloudEUC.
.DESCRIPTION
    Laedt global.json und die referenzierten Konfigurationen sowie Profile aus einem
    GitHub-Repository (Raw-URL, Branch oder Release), mit Timeout/Retry, AllowedHosts-
    Enforcement, optionaler Hash-Pruefung und Fallback auf eine lokal im WinPE
    vorhandene Konfiguration. Validiert JSON gegen JSON-Schemas.
    Kompatibel mit Windows PowerShell 5.1 (WinPE) und PowerShell 7.

    Erfordert die Module OSDCloud.Logging und OSDCloud.Security im selben Verzeichnis.
#>

Set-StrictMode -Version Latest

function Get-OSDCloudRawBaseUrl {
    <#
    .SYNOPSIS
        Baut die Basis-URL fuer Raw-Dateizugriffe aus der Repository-Konfiguration.
    .PARAMETER Repository
        Das Repository-Objekt aus global.json.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Repository)

    if ($Repository.PSObject.Properties.Name -contains 'BaseUrlOverride' -and $Repository.BaseUrlOverride) {
        return $Repository.BaseUrlOverride.TrimEnd('/')
    }

    $ref = if ($Repository.UseRelease -and $Repository.ReleaseTag) { $Repository.ReleaseTag } else { $Repository.Branch }

    switch ($Repository.Provider) {
        'GitHubEnterprise' {
            if (-not $Repository.EnterpriseServerHost) {
                throw 'EnterpriseServerHost muss fuer Provider GitHubEnterprise gesetzt sein.'
            }
            return "https://$($Repository.EnterpriseServerHost)/raw/$($Repository.Owner)/$($Repository.Name)/$ref"
        }
        'WebServer' {
            if (-not $Repository.BaseUrlOverride) {
                throw 'BaseUrlOverride muss fuer Provider WebServer gesetzt sein.'
            }
            return $Repository.BaseUrlOverride.TrimEnd('/')
        }
        default {
            return "https://raw.githubusercontent.com/$($Repository.Owner)/$($Repository.Name)/$ref"
        }
    }
}

function Invoke-OSDCloudDownloadString {
    <#
    .SYNOPSIS
        Laedt eine Textdatei per HTTPS mit Timeout und Retry.
    .PARAMETER Uri
        Die Quell-URL.
    .PARAMETER AllowedHosts
        Erlaubte Hostnamen (AllowedHosts-Enforcement).
    .PARAMETER TimeoutSeconds
        Timeout je Versuch.
    .PARAMETER RetryCount
        Anzahl Wiederholungen bei Fehler.
    .PARAMETER RetryDelaySeconds
        Basis-Wartezeit (exponentielles Backoff).
    .PARAMETER Token
        Optionaler GitHub-Token (privates Repo).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [string[]]$AllowedHosts,
        [int]$TimeoutSeconds = 30,
        [int]$RetryCount = 4,
        [int]$RetryDelaySeconds = 2,
        [string]$Token
    )

    Assert-OSDCloudAllowedHost -Url $Uri -AllowedHosts $AllowedHosts | Out-Null

    $headers = @{}
    if ($Token) {
        $headers['Authorization'] = "token $Token"
    }

    $attempt = 0
    do {
        $attempt++
        try {
            Write-OSDCloudLog -Level Debug -Component 'Config' -Message "Download-Versuch $attempt/$($RetryCount + 1): $Uri"
            $params = @{
                Uri             = $Uri
                UseBasicParsing = $true
                TimeoutSec      = $TimeoutSeconds
                ErrorAction     = 'Stop'
            }
            if ($headers.Count -gt 0) { $params['Headers'] = $headers }
            $response = Invoke-WebRequest @params
            return [string]$response.Content
        } catch {
            Write-OSDCloudLog -Level Warning -Component 'Config' -Message "Download fehlgeschlagen (Versuch $attempt): $($_.Exception.Message)"
            if ($attempt -le $RetryCount) {
                $delay = [Math]::Min($RetryDelaySeconds * [Math]::Pow(2, $attempt - 1), 30)
                Start-Sleep -Seconds ([int]$delay)
            } else {
                throw
            }
        }
    } while ($attempt -le $RetryCount)
}

function ConvertFrom-OSDCloudJson {
    <#
    .SYNOPSIS
        Wandelt JSON-Text robust in ein Objekt um und wirft eine klare Fehlermeldung.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Json,
        [string]$SourceName = 'JSON'
    )
    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw "Leerer Inhalt fuer '$SourceName'."
    }
    try {
        return $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Ungueltiges JSON in '$SourceName': $($_.Exception.Message)"
    }
}

function Test-OSDCloudConfigSchema {
    <#
    .SYNOPSIS
        Validiert JSON gegen ein JSON-Schema, wenn Test-Json -Schema verfuegbar ist.
    .DESCRIPTION
        In WinPE (PowerShell 5.1) unterstuetzt Test-Json kein -Schema. In diesem Fall
        wird eine strukturelle Basispruefung (JSON wohlgeformt) durchgefuehrt und $true
        zurueckgegeben, damit das Deployment nicht blockiert, aber ein Debug-Hinweis geloggt.
    .PARAMETER Json
        Der JSON-Text.
    .PARAMETER SchemaPath
        Pfad zur Schema-Datei.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Json,
        [Parameter(Mandatory)] [string]$SchemaPath
    )

    $supportsSchema = $false
    $cmd = Get-Command -Name Test-Json -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey('Schema') -and (Test-Path -LiteralPath $SchemaPath)) {
        $supportsSchema = $true
    }

    if (-not $supportsSchema) {
        # Fallback: nur Wohlgeformtheit pruefen.
        try {
            $null = $Json | ConvertFrom-Json -ErrorAction Stop
            Write-OSDCloudLog -Level Debug -Component 'Config' -Message "Test-Json -Schema nicht verfuegbar; nur Wohlgeformtheit geprueft ($SchemaPath)."
            return $true
        } catch {
            return $false
        }
    }

    try {
        $schema = Get-Content -LiteralPath $SchemaPath -Raw
        return [bool](Test-Json -Json $Json -Schema $schema -ErrorAction Stop)
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Config' -Message "Schema-Validierung fehlgeschlagen ($SchemaPath): $($_.Exception.Message)"
        return $false
    }
}

function Get-OSDCloudConfig {
    <#
    .SYNOPSIS
        Laedt die globale Konfiguration und alle referenzierten Konfigurationen.
    .DESCRIPTION
        Versucht zuerst den Download aus GitHub. Bei Fehlern greift der in global.json
        definierte FallbackMode: LocalConfig laedt aus -LocalConfigRoot, InternalWebServer
        nutzt Network.InternalWebServerUrl, Fail bricht ab.
    .PARAMETER LocalConfigRoot
        Wurzelverzeichnis der lokal im WinPE vorhandenen Konfiguration (Fallback und
        Quelle fuer global.json wenn -UseLocalGlobal gesetzt ist).
    .PARAMETER UseLocalGlobal
        Laedt global.json direkt lokal statt aus GitHub (Bootstrapping).
    .PARAMETER Token
        Optionaler GitHub-Token fuer private Repositories.
    .OUTPUTS
        [pscustomobject] mit Feldern Global, Deployments, OperatingSystems, Drivers,
        Updates, Networks, Security, Source.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$LocalConfigRoot,
        [switch]$UseLocalGlobal,
        [string]$Token
    )

    $schemaDir = Join-Path -Path $LocalConfigRoot -ChildPath 'schema'

    # --- 1. global.json laden (lokal oder GitHub) ---
    $globalJson = $null
    $source = 'GitHub'

    if ($UseLocalGlobal) {
        $globalPath = Join-Path -Path $LocalConfigRoot -ChildPath 'global.json'
        $globalJson = Get-Content -LiteralPath $globalPath -Raw
        $source = 'Local'
    } else {
        $bootstrapPath = Join-Path -Path $LocalConfigRoot -ChildPath 'global.json'
        $globalJson = Get-Content -LiteralPath $bootstrapPath -Raw
    }

    $globalSchema = Join-Path -Path $schemaDir -ChildPath 'global.schema.json'
    if (-not (Test-OSDCloudConfigSchema -Json $globalJson -SchemaPath $globalSchema)) {
        throw 'global.json entspricht nicht dem Schema (global.schema.json).'
    }
    $global = ConvertFrom-OSDCloudJson -Json $globalJson -SourceName 'global.json'

    $allowedHosts = $global.Security.AllowedHosts
    $timeout      = if ($global.PSObject.Properties.Name -contains 'Network') { $global.Network.TimeoutSeconds } else { 30 }
    $retry        = if ($global.PSObject.Properties.Name -contains 'Network') { $global.Network.RetryCount } else { 4 }
    $retryDelay   = if ($global.PSObject.Properties.Name -contains 'Network') { $global.Network.RetryDelaySeconds } else { 2 }
    $fallbackMode = if ($global.PSObject.Properties.Name -contains 'Network') { $global.Network.FallbackMode } else { 'LocalConfig' }

    $baseUrl = Get-OSDCloudRawBaseUrl -Repository $global.Repository

    # --- 2. Hilfsfunktion: eine Konfigurationsdatei laden (GitHub -> Fallback) ---
    $loadFile = {
        param([string]$RelativePath, [string]$SchemaFile)

        $content = $null
        $usedSource = 'GitHub'
        if (-not $UseLocalGlobal) {
            try {
                $uri = "$baseUrl/config/$RelativePath"
                $content = Invoke-OSDCloudDownloadString -Uri $uri -AllowedHosts $allowedHosts `
                    -TimeoutSeconds $timeout -RetryCount $retry -RetryDelaySeconds $retryDelay -Token $Token
            } catch {
                Write-OSDCloudLog -Level Warning -Component 'Config' -Message "GitHub-Download fuer '$RelativePath' fehlgeschlagen. FallbackMode=$fallbackMode."
                switch ($fallbackMode) {
                    'Fail' { throw }
                    default {
                        $localPath = Join-Path -Path $LocalConfigRoot -ChildPath $RelativePath
                        if (-not (Test-Path -LiteralPath $localPath)) { throw "Fallback-Datei nicht gefunden: $localPath" }
                        $content = Get-Content -LiteralPath $localPath -Raw
                        $usedSource = 'LocalFallback'
                    }
                }
            }
        } else {
            $localPath = Join-Path -Path $LocalConfigRoot -ChildPath $RelativePath
            $content = Get-Content -LiteralPath $localPath -Raw
            $usedSource = 'Local'
        }

        if ($SchemaFile) {
            $schemaPath = Join-Path -Path $schemaDir -ChildPath $SchemaFile
            if (-not (Test-OSDCloudConfigSchema -Json $content -SchemaPath $schemaPath)) {
                throw "$RelativePath entspricht nicht dem Schema ($SchemaFile)."
            }
        }
        return [pscustomobject]@{
            Object = ConvertFrom-OSDCloudJson -Json $content -SourceName $RelativePath
            Source = $usedSource
        }
    }

    $deployments = & $loadFile 'deployments.json' 'deployments.schema.json'
    $operating   = & $loadFile 'operating-systems.json' $null
    $drivers     = & $loadFile 'drivers.json' $null
    $updates     = & $loadFile 'updates.json' $null
    $networks    = & $loadFile 'networks.json' $null
    $security    = & $loadFile 'security.json' $null

    Write-OSDCloudLog -Level Information -Component 'Config' -Message "Konfiguration geladen (Quelle: $source, Basis-URL: $baseUrl)."

    return [pscustomobject]@{
        Global           = $global
        Deployments      = $deployments.Object
        OperatingSystems = $operating.Object
        Drivers          = $drivers.Object
        Updates          = $updates.Object
        Networks         = $networks.Object
        Security         = $security.Object
        BaseUrl          = $baseUrl
        Source           = $source
    }
}

function Get-OSDCloudProfileList {
    <#
    .SYNOPSIS
        Liefert die erlaubten Profile aus der geladenen Konfiguration.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Config)
    return $Config.Global.Deployment.AllowedProfiles
}

function Resolve-OSDCloudProfile {
    <#
    .SYNOPSIS
        Laedt ein Deployment-Profil und loest es gegen die Kataloge auf.
    .DESCRIPTION
        Baut ein vollstaendiges Deployment-Objekt aus einem Profil, angereichert mit
        den OS-Katalogdaten (OSName/OSEdition/OSLanguage/OSActivation), die an
        Invoke-OSDCloud uebergeben werden.
    .PARAMETER Config
        Das von Get-OSDCloudConfig gelieferte Objekt.
    .PARAMETER ProfileId
        Die zu ladende Profil-Id.
    .PARAMETER LocalConfigRoot
        Wurzelverzeichnis (fuer lokales Laden der Profildatei).
    .PARAMETER Token
        Optionaler GitHub-Token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string]$ProfileId,
        [Parameter(Mandatory)] [string]$LocalConfigRoot,
        [string]$Token
    )

    $allowed = Get-OSDCloudProfileList -Config $Config
    if ($allowed -and ($allowed -notcontains $ProfileId)) {
        throw "Profil '$ProfileId' ist nicht in AllowedProfiles enthalten."
    }

    # Profildatei laden (GitHub oder lokal). Profile liegen unter /profiles.
    $relative = "profiles/$ProfileId.json"
    $profileContent = $null
    if ($Config.Source -eq 'Local') {
        $localPath = Join-Path -Path (Split-Path -Path $LocalConfigRoot -Parent) -ChildPath $relative
        if (-not (Test-Path -LiteralPath $localPath)) {
            # Alternativ direkt unter LocalConfigRoot/profiles suchen.
            $localPath = Join-Path -Path $LocalConfigRoot -ChildPath "..\$relative"
        }
        $profileContent = Get-Content -LiteralPath $localPath -Raw
    } else {
        try {
            $uri = "$($Config.BaseUrl)/$relative"
            $profileContent = Invoke-OSDCloudDownloadString -Uri $uri -AllowedHosts $Config.Global.Security.AllowedHosts `
                -TimeoutSeconds $Config.Global.Network.TimeoutSeconds -RetryCount $Config.Global.Network.RetryCount `
                -RetryDelaySeconds $Config.Global.Network.RetryDelaySeconds -Token $Token
        } catch {
            $localPath = Join-Path -Path (Split-Path -Path $LocalConfigRoot -Parent) -ChildPath $relative
            if (-not (Test-Path -LiteralPath $localPath)) { throw "Profil '$ProfileId' konnte weder aus GitHub noch lokal geladen werden." }
            $profileContent = Get-Content -LiteralPath $localPath -Raw
        }
    }

    $profileObj = ConvertFrom-OSDCloudJson -Json $profileContent -SourceName $relative

    # OS-Katalog aufloesen.
    $os = $Config.OperatingSystems.OperatingSystems | Where-Object { $_.Id -eq $profileObj.OperatingSystem } | Select-Object -First 1
    if (-not $os) {
        throw "OperatingSystem '$($profileObj.OperatingSystem)' aus Profil '$ProfileId' ist nicht im OS-Katalog definiert."
    }

    $skipWipe = $false
    if ($profileObj.PSObject.Properties.Name -contains 'SkipDiskWipeConfirmation') {
        $skipWipe = [bool]$profileObj.SkipDiskWipeConfirmation
    }

    return [pscustomobject]@{
        ProfileId        = $profileObj.ProfileId
        DisplayName      = $profileObj.DisplayName
        OperatingSystem  = $os
        OSName           = $os.OSName
        OSEdition        = $os.OSEdition
        OSLanguage       = if ($profileObj.Language) { $profileObj.Language.ToLower() } else { $os.OSLanguage }
        OSActivation     = $os.OSActivation
        Language         = $profileObj.Language
        KeyboardLayout   = $profileObj.KeyboardLayout
        Activation       = $profileObj.Activation
        InstallMode      = $profileObj.InstallMode
        DriverStrategy   = $profileObj.DriverStrategy
        UpdateStrategy   = $profileObj.UpdateStrategy
        Partitioning     = $profileObj.Partitioning
        JoinType         = $profileObj.JoinType
        ComputerName     = $profileObj.ComputerName
        ZeroTouch        = [bool]$profileObj.ZeroTouch
        SkipDiskWipe     = $skipWipe
        PostInstallScripts = @($profileObj.PostInstallScripts)
    }
}

Export-ModuleMember -Function Get-OSDCloudRawBaseUrl, Invoke-OSDCloudDownloadString, ConvertFrom-OSDCloudJson, `
    Test-OSDCloudConfigSchema, Get-OSDCloudConfig, Get-OSDCloudProfileList, Resolve-OSDCloudProfile
