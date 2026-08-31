<#
.SYNOPSIS
    Zentrales Logging fuer OSDCloudEUC.
.DESCRIPTION
    Stellt strukturierte Log-Funktionen fuer WinPE und das laufende Windows bereit.
    Schreibt gleichzeitig in Konsole (farbig) und in eine Log-Datei, optional als Transcript.
    Kompatibel mit Windows PowerShell 5.1 (WinPE) und PowerShell 7.
#>

Set-StrictMode -Version Latest

$script:OSDCloudLogState = [ordered]@{
    Initialized    = $false
    LogFile        = $null
    Level          = 'Information'
    TranscriptOn   = $false
}

$script:OSDCloudLogLevels = @{
    'Debug'       = 0
    'Information' = 1
    'Warning'     = 2
    'Error'       = 3
}

function Initialize-OSDCloudLog {
    <#
    .SYNOPSIS
        Initialisiert das Logging (Zielordner, Datei, optional Transcript).
    .PARAMETER Path
        Zielordner fuer Logs. Standard: X:\OSDCloud\Logs in WinPE, sonst $env:TEMP\OSDCloud.
    .PARAMETER Level
        Minimaler Log-Level der ausgegeben wird (Debug, Information, Warning, Error).
    .PARAMETER EnableTranscript
        Aktiviert Start-Transcript zusaetzlich zur Datei.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [ValidateSet('Debug','Information','Warning','Error')]
        [string]$Level = 'Information',
        [switch]$EnableTranscript
    )

    if (-not $Path) {
        if (Test-Path -LiteralPath 'X:\') {
            $Path = 'X:\OSDCloud\Logs'
        } else {
            $Path = Join-Path -Path $env:TEMP -ChildPath 'OSDCloud\Logs'
        }
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    } catch {
        Write-Warning "Log-Ordner '$Path' konnte nicht erstellt werden: $($_.Exception.Message)"
        $Path = $env:TEMP
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:OSDCloudLogState.LogFile      = Join-Path -Path $Path -ChildPath "OSDCloudEUC-$timestamp.log"
    $script:OSDCloudLogState.Level        = $Level
    $script:OSDCloudLogState.Initialized  = $true

    if ($EnableTranscript) {
        try {
            $transcriptFile = Join-Path -Path $Path -ChildPath "OSDCloudEUC-$timestamp.transcript.log"
            Start-Transcript -Path $transcriptFile -Force -ErrorAction Stop | Out-Null
            $script:OSDCloudLogState.TranscriptOn = $true
        } catch {
            Write-Warning "Transcript konnte nicht gestartet werden: $($_.Exception.Message)"
        }
    }

    Write-OSDCloudLog -Level Information -Message "Logging initialisiert. Datei: $($script:OSDCloudLogState.LogFile)"
    return $script:OSDCloudLogState.LogFile
}

function Write-OSDCloudLog {
    <#
    .SYNOPSIS
        Schreibt eine Log-Zeile in Konsole und Datei.
    .PARAMETER Message
        Der Log-Text.
    .PARAMETER Level
        Log-Level: Debug, Information, Warning, Error.
    .PARAMETER Component
        Optionaler Komponentenname (z. B. 'Config', 'Menu').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Debug','Information','Warning','Error')]
        [string]$Level = 'Information',

        [string]$Component = 'General'
    )

    if (-not $script:OSDCloudLogState.Initialized) {
        # Auto-Init mit Standardwerten, damit Logging nie fehlschlaegt.
        Initialize-OSDCloudLog | Out-Null
    }

    $minLevel = $script:OSDCloudLogLevels[$script:OSDCloudLogState.Level]
    $thisLevel = $script:OSDCloudLogLevels[$Level]
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1,-11}] [{2}] {3}" -f $timestamp, $Level, $Component, $Message

    # Datei immer schreiben (auch Debug), Konsole gemaess Level.
    if ($script:OSDCloudLogState.LogFile) {
        try {
            Add-Content -LiteralPath $script:OSDCloudLogState.LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
        } catch {
            # Fallback still: Datei nicht schreibbar, nur Konsole.
        }
    }

    if ($thisLevel -ge $minLevel) {
        switch ($Level) {
            'Debug'       { Write-Host $line -ForegroundColor DarkGray }
            'Information' { Write-Host $line -ForegroundColor Gray }
            'Warning'     { Write-Host $line -ForegroundColor Yellow }
            'Error'       { Write-Host $line -ForegroundColor Red }
        }
    }
}

function Write-OSDCloudLogException {
    <#
    .SYNOPSIS
        Protokolliert eine Ausnahme inkl. Stacktrace als Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Component = 'General'
    )
    Write-OSDCloudLog -Level Error -Component $Component -Message $ErrorRecord.Exception.Message
    if ($ErrorRecord.ScriptStackTrace) {
        Write-OSDCloudLog -Level Debug -Component $Component -Message ("StackTrace: " + $ErrorRecord.ScriptStackTrace)
    }
}

function Stop-OSDCloudLog {
    <#
    .SYNOPSIS
        Beendet ein laufendes Transcript.
    #>
    [CmdletBinding()]
    param()
    if ($script:OSDCloudLogState.TranscriptOn) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:OSDCloudLogState.TranscriptOn = $false
    }
}

function Get-OSDCloudLogFile {
    <#
    .SYNOPSIS
        Liefert den Pfad der aktuellen Log-Datei.
    #>
    [CmdletBinding()]
    param()
    return $script:OSDCloudLogState.LogFile
}

Export-ModuleMember -Function Initialize-OSDCloudLog, Write-OSDCloudLog, Write-OSDCloudLogException, Stop-OSDCloudLog, Get-OSDCloudLogFile
