<#
.SYNOPSIS
    Sicherheitsfunktionen fuer OSDCloudEUC.
.DESCRIPTION
    - AllowedHosts-Enforcement fuer Download-Ziele
    - SHA256-Hash-Validierung heruntergeladener Dateien gegen ein Manifest
    - Authenticode-Signaturpruefung von PowerShell-Skripten
    - Bestaetigung vor dem Loeschen der Zieldisk
    Kompatibel mit Windows PowerShell 5.1 und PowerShell 7.
#>

Set-StrictMode -Version Latest

function Assert-OSDCloudAllowedHost {
    <#
    .SYNOPSIS
        Prueft, ob der Host einer URL in der AllowedHosts-Liste steht.
    .PARAMETER Url
        Die zu pruefende URL.
    .PARAMETER AllowedHosts
        Liste erlaubter Hostnamen.
    .OUTPUTS
        [bool] $true wenn erlaubt. Wirft eine Ausnahme wenn nicht erlaubt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string[]]$AllowedHosts
    )

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
        throw "Ungueltige URL: '$Url'."
    }

    if ($uri.Scheme -ne 'https') {
        throw "Nur HTTPS ist erlaubt. Abgelehnt: '$Url' (Schema '$($uri.Scheme)')."
    }

    if ($AllowedHosts -notcontains $uri.Host) {
        throw "Host '$($uri.Host)' steht nicht in der AllowedHosts-Liste. URL abgelehnt: '$Url'."
    }

    return $true
}

function Test-OSDCloudHash {
    <#
    .SYNOPSIS
        Vergleicht den SHA256-Hash einer Datei mit einem erwarteten Wert.
    .PARAMETER Path
        Pfad zur Datei.
    .PARAMETER ExpectedHash
        Erwarteter Hashwert (Hex, Gross-/Kleinschreibung egal).
    .PARAMETER Algorithm
        Hash-Algorithmus. Standard SHA256.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$ExpectedHash,
        [ValidateSet('SHA256','SHA384','SHA512')]
        [string]$Algorithm = 'SHA256'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Datei fuer Hash-Pruefung nicht gefunden: '$Path'."
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
    $match = $actual.Trim().ToUpperInvariant() -eq $ExpectedHash.Trim().ToUpperInvariant()
    return [pscustomobject]@{
        Path         = $Path
        Algorithm    = $Algorithm
        ExpectedHash = $ExpectedHash.Trim().ToUpperInvariant()
        ActualHash   = $actual
        IsValid      = $match
    }
}

function Get-OSDCloudHashManifest {
    <#
    .SYNOPSIS
        Liest ein Hash-Manifest im Format 'HASH  relativer/Pfad' (eine Zeile je Datei).
    .PARAMETER Path
        Pfad zur Manifest-Datei.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Path)

    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        # Trennung: erster Whitespace-Block trennt Hash von Pfad.
        $parts = $trimmed -split '\s+', 2
        if ($parts.Count -eq 2) {
            $result[$parts[1].Trim()] = $parts[0].Trim()
        }
    }
    return $result
}

function Test-OSDCloudSignature {
    <#
    .SYNOPSIS
        Prueft die Authenticode-Signatur eines Skripts.
    .PARAMETER Path
        Pfad zum Skript.
    .PARAMETER TrustedThumbprints
        Optionale Liste vertrauenswuerdiger Zertifikat-Thumbprints. Ist sie gesetzt,
        muss der Signatur-Thumbprint enthalten sein.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string[]]$TrustedThumbprints = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Skript fuer Signaturpruefung nicht gefunden: '$Path'."
    }

    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    $valid = $sig.Status -eq 'Valid'
    $trusted = $true
    if ($TrustedThumbprints.Count -gt 0) {
        $thumb = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { $null }
        $trusted = ($null -ne $thumb) -and ($TrustedThumbprints -contains $thumb)
    }

    return [pscustomobject]@{
        Path       = $Path
        Status     = $sig.Status
        Thumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { $null }
        IsValid    = ($valid -and $trusted)
    }
}

function Confirm-OSDCloudDiskWipe {
    <#
    .SYNOPSIS
        Fordert eine Bestaetigung vor dem Loeschen der Zieldisk an.
    .PARAMETER ConfirmationPhrase
        Phrase, die der Benutzer exakt eingeben muss (z. B. 'WIPE').
    .PARAMETER SkipConfirmation
        Ueberspringt die Bestaetigung (nur fuer Zero-Touch mit explizitem Override).
    .OUTPUTS
        [bool] $true wenn bestaetigt.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfirmationPhrase = 'WIPE',
        [switch]$SkipConfirmation
    )

    if ($SkipConfirmation) {
        return $true
    }

    Write-Host ''
    Write-Host '  ############################################################' -ForegroundColor Red
    Write-Host '  #  WARNUNG: Die Zieldisk wird vollstaendig GELOESCHT.      #' -ForegroundColor Red
    Write-Host '  #  Alle Daten gehen unwiderruflich verloren.              #' -ForegroundColor Red
    Write-Host '  ############################################################' -ForegroundColor Red
    Write-Host ''
    $answer = Read-Host "  Zum Fortfahren '$ConfirmationPhrase' eingeben (sonst Abbruch)"
    return ($answer -ceq $ConfirmationPhrase)
}

Export-ModuleMember -Function Assert-OSDCloudAllowedHost, Test-OSDCloudHash, Get-OSDCloudHashManifest, Test-OSDCloudSignature, Confirm-OSDCloudDiskWipe
