<#
.SYNOPSIS
    Konsolenbasierte Menuefuehrung fuer OSDCloudEUC.
.DESCRIPTION
    Robustes, rein konsolenbasiertes Menue (kein Out-GridView-Zwang), das seine Eintraege
    und erlaubten Optionswerte ausschliesslich aus der deployments.json-Konfiguration
    aufbaut. Kompatibel mit WinPE (PS 5.1) und PS7.
#>

Set-StrictMode -Version Latest

function Show-OSDCloudBanner {
    <#
    .SYNOPSIS
        Zeigt den Kopfbereich mit erkannter Hardware.
    #>
    [CmdletBinding()]
    param($Hardware)
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '   OSDCloudEUC  -  Windows Deployment' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    if ($Hardware) {
        Write-Host ("   Hersteller : {0}" -f $Hardware.Manufacturer)
        Write-Host ("   Modell     : {0}" -f $Hardware.Model)
        Write-Host ("   Seriennr.  : {0}" -f $Hardware.SerialNumber)
        Write-Host ("   Firmware   : {0}  SecureBoot: {1}  TPM: {2}" -f $Hardware.FirmwareType, $Hardware.SecureBoot, $Hardware.TpmPresent)
    }
    Write-Host '------------------------------------------------------------'
}

function Select-OSDCloudOption {
    <#
    .SYNOPSIS
        Zeigt eine nummerierte Auswahlliste und liest eine gueltige Auswahl.
    .PARAMETER Title
        Ueberschrift der Auswahl.
    .PARAMETER Options
        Array von Objekten mit Label und Value.
    .PARAMETER CurrentValue
        Aktuell gesetzter Wert (wird markiert).
    .OUTPUTS
        Das gewaehlte Option-Objekt oder $null bei Abbruch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [array]$Options,
        $CurrentValue
    )

    while ($true) {
        Write-Host ''
        Write-Host $Title -ForegroundColor White
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $marker = if ($null -ne $CurrentValue -and $Options[$i].Value -eq $CurrentValue) { '*' } else { ' ' }
            Write-Host ("   [{0}]{1} {2}" -f ($i + 1), $marker, $Options[$i].Label)
        }
        Write-Host '   [0]  Zurueck'
        $answer = Read-Host 'Auswahl'

        if ($answer -eq '0') { return $null }
        $index = 0
        if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $Options.Count) {
            return $Options[$index - 1]
        }
        Write-Host '   Ungueltige Eingabe. Bitte erneut versuchen.' -ForegroundColor Yellow
    }
}

function Read-OSDCloudInput {
    <#
    .SYNOPSIS
        Liest einen Freitext mit optionaler Regex-Validierung.
    .PARAMETER Prompt
        Eingabeaufforderung.
    .PARAMETER Pattern
        Optionale Regex, die die Eingabe erfuellen muss.
    .PARAMETER Default
        Standardwert bei leerer Eingabe.
    .PARAMETER Hint
        Optionaler Hinweistext.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Prompt,
        [string]$Pattern,
        [string]$Default,
        [string]$Hint
    )

    if ($Hint) { Write-Host "   ($Hint)" -ForegroundColor DarkGray }
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "$Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($value) -and $Default) { $value = $Default }
        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host '   Eingabe darf nicht leer sein.' -ForegroundColor Yellow
            continue
        }
        if ($Pattern -and ($value -notmatch $Pattern)) {
            Write-Host "   Eingabe entspricht nicht dem erlaubten Muster ($Pattern)." -ForegroundColor Yellow
            continue
        }
        return $value
    }
}

function New-OSDCloudSelectionState {
    <#
    .SYNOPSIS
        Erzeugt den Anfangs-Auswahlzustand aus den Field-Defaults der deployments.json.
    .PARAMETER Deployments
        Das deployments.json-Objekt.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Deployments)

    $state = [ordered]@{}
    foreach ($fieldName in $Deployments.Fields.PSObject.Properties.Name) {
        $field = $Deployments.Fields.$fieldName
        $default = if ($field.PSObject.Properties.Name -contains 'Default') { $field.Default } else { $null }
        $state[$fieldName] = $default
    }
    return $state
}

function Show-OSDCloudSummary {
    <#
    .SYNOPSIS
        Zeigt eine Zusammenfassung der aktuellen Auswahl.
    .PARAMETER Deployments
        Das deployments.json-Objekt (fuer Labels).
    .PARAMETER State
        Der Auswahlzustand (Feld -> Wert).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Deployments,
        [Parameter(Mandatory)] $State
    )
    Write-Host ''
    Write-Host '=== Zusammenfassung ===' -ForegroundColor Cyan
    foreach ($fieldName in $State.Keys) {
        $label = $Deployments.Fields.$fieldName.Label
        Write-Host ("   {0,-28}: {1}" -f $label, $State[$fieldName])
    }
    Write-Host ''
}

function Show-OSDCloudMenu {
    <#
    .SYNOPSIS
        Fuehrt das interaktive Hauptmenue aus und liefert die getroffene Auswahl.
    .DESCRIPTION
        Baut das Menue vollstaendig aus deployments.json auf. Liefert ein Objekt mit
        der Auswahl (State) und der Aktion (StartDeploy / Reboot / Shell / Cancel).
    .PARAMETER Deployments
        Das deployments.json-Objekt.
    .PARAMETER Hardware
        Optionales Hardware-Objekt fuer den Kopfbereich.
    .PARAMETER InitialState
        Optionaler vorbelegter Auswahlzustand (z. B. aus einem Profil).
    .OUTPUTS
        [pscustomobject] mit Action und State.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Deployments,
        $Hardware,
        $InitialState
    )

    $state = if ($InitialState) { $InitialState } else { New-OSDCloudSelectionState -Deployments $Deployments }

    while ($true) {
        Show-OSDCloudBanner -Hardware $Hardware
        Write-Host ''
        for ($i = 0; $i -lt $Deployments.MainMenu.Count; $i++) {
            Write-Host ("   {0,2}. {1}" -f ($i + 1), $Deployments.MainMenu[$i].Label)
        }
        Write-Host '    q. Abbrechen'
        Write-Host ''
        $answer = Read-Host 'Bitte Menuepunkt waehlen'

        if ($answer -eq 'q') {
            return [pscustomobject]@{ Action = 'Cancel'; State = $state }
        }

        $index = 0
        if (-not ([int]::TryParse($answer, [ref]$index)) -or $index -lt 1 -or $index -gt $Deployments.MainMenu.Count) {
            Write-Host '   Ungueltige Eingabe.' -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            continue
        }

        $item = $Deployments.MainMenu[$index - 1]
        switch ($item.Action) {
            'StartDefault' {
                return [pscustomobject]@{ Action = 'StartDeploy'; State = $state }
            }
            'ReviewAndDeploy' {
                Show-OSDCloudSummary -Deployments $Deployments -State $state
                $confirm = Read-Host 'Deployment mit dieser Auswahl starten? (j/N)'
                if ($confirm -match '^(j|J|y|Y)$') {
                    return [pscustomobject]@{ Action = 'StartDeploy'; State = $state }
                }
            }
            'Reboot' {
                return [pscustomobject]@{ Action = 'Reboot'; State = $state }
            }
            'Shell' {
                return [pscustomobject]@{ Action = 'Shell'; State = $state }
            }
            'SelectField' {
                $field = $Deployments.Fields.($item.Field)
                $selected = Select-OSDCloudOption -Title $field.Label -Options $field.Options -CurrentValue $state[$item.Field]
                if ($null -ne $selected) {
                    $state[$item.Field] = $selected.Value
                    # Sprachwahl kann Tastaturlayout mitziehen.
                    if ($item.Field -eq 'Language' -and ($selected.PSObject.Properties.Name -contains 'KeyboardLayout')) {
                        if ($state.Contains('KeyboardLayout')) { $state['KeyboardLayout'] = $selected.KeyboardLayout }
                    }
                }
            }
            'InputField' {
                $field = $Deployments.Fields.($item.Field)
                $pattern = if ($field.PSObject.Properties.Name -contains 'Pattern') { $field.Pattern } else { $null }
                $hint    = if ($field.PSObject.Properties.Name -contains 'Hint') { $field.Hint } else { $null }
                $value = Read-OSDCloudInput -Prompt $field.Label -Pattern $pattern -Default $state[$item.Field] -Hint $hint
                $state[$item.Field] = $value
            }
            default {
                Write-Host "   Unbekannte Aktion '$($item.Action)'." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    }
}

Export-ModuleMember -Function Show-OSDCloudBanner, Select-OSDCloudOption, Read-OSDCloudInput, `
    New-OSDCloudSelectionState, Show-OSDCloudSummary, Show-OSDCloudMenu
