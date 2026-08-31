<#
.SYNOPSIS
    Hardwareerkennung fuer OSDCloudEUC.
.DESCRIPTION
    Ermittelt Hersteller, Modell, Seriennummer, Firmware-Typ (UEFI/BIOS), Secure Boot,
    TPM-Status und Zieldatentraeger via CIM/WMI. Kompatibel mit WinPE (PS 5.1) und PS7.
#>

Set-StrictMode -Version Latest

function Get-OSDCloudHardware {
    <#
    .SYNOPSIS
        Liefert ein Objekt mit den wichtigsten Hardware-Eigenschaften.
    .OUTPUTS
        [pscustomobject] mit Manufacturer, Model, SystemSku, SerialNumber, Chassis,
        IsVirtual, FirmwareType, SecureBoot, TpmPresent, TpmVersion, Disks.
    #>
    [CmdletBinding()]
    param()

    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $prod = Get-CimInstance -Namespace 'root\wmi' -ClassName MS_SystemInformation -ErrorAction SilentlyContinue

    $manufacturer = if ($cs) { $cs.Manufacturer } else { 'Unknown' }
    $model        = if ($cs) { $cs.Model } else { 'Unknown' }
    $serial       = if ($bios) { $bios.SerialNumber } else { 'Unknown' }
    $sku          = if ($prod) { $prod.SystemSKU } else { $null }

    $isVirtual = $false
    if ($model -match 'Virtual|VMware|KVM|Xen|Hyper-V' -or $manufacturer -match 'VMware|Microsoft Corporation|innotek|QEMU|Xen') {
        if ($model -match 'Virtual Machine|VMware|VirtualBox' -or $manufacturer -match 'VMware|innotek|QEMU|Xen') {
            $isVirtual = $true
        }
    }

    return [pscustomobject]@{
        Manufacturer = $manufacturer
        Model        = $model
        SystemSku    = $sku
        SerialNumber = $serial
        IsVirtual    = $isVirtual
        FirmwareType = Get-OSDCloudFirmwareType
        SecureBoot   = Get-OSDCloudSecureBootState
        TpmPresent   = (Get-OSDCloudTpmInfo).Present
        TpmVersion   = (Get-OSDCloudTpmInfo).SpecVersion
        Disks        = @(Get-OSDCloudDisk)
    }
}

function Get-OSDCloudFirmwareType {
    <#
    .SYNOPSIS
        Ermittelt, ob das System per UEFI oder BIOS/Legacy gestartet wurde.
    #>
    [CmdletBinding()]
    param()
    try {
        # $env:firmware_type wird von WinPE gesetzt.
        if ($env:firmware_type) {
            return $env:firmware_type  # 'UEFI' oder 'Legacy'
        }
        $secureBootReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
        if (Test-Path -LiteralPath $secureBootReg) { return 'UEFI' }
        return 'Unknown'
    } catch {
        return 'Unknown'
    }
}

function Get-OSDCloudSecureBootState {
    <#
    .SYNOPSIS
        Prueft, ob Secure Boot aktiviert ist.
    #>
    [CmdletBinding()]
    param()
    try {
        $cmd = Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        if ($cmd) {
            return [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        }
    } catch {
        # Confirm-SecureBootUEFI wirft auf Legacy-Systemen -> nicht aktiv.
        return $false
    }
    return $false
}

function Get-OSDCloudTpmInfo {
    <#
    .SYNOPSIS
        Liefert TPM-Praesenz und Spezifikationsversion.
    #>
    [CmdletBinding()]
    param()
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction Stop
        if ($tpm) {
            return [pscustomobject]@{
                Present     = $true
                SpecVersion = $tpm.SpecVersion
            }
        }
    } catch { }
    return [pscustomobject]@{ Present = $false; SpecVersion = $null }
}

function Get-OSDCloudDisk {
    <#
    .SYNOPSIS
        Liefert die internen Festplatten (ohne USB/Removable) als Kandidaten fuer die Installation.
    #>
    [CmdletBinding()]
    param()
    try {
        $disks = Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -ne 'USB' }
        return $disks | ForEach-Object {
            [pscustomobject]@{
                Number       = $_.Number
                FriendlyName = $_.FriendlyName
                SizeGB       = [Math]::Round($_.Size / 1GB, 1)
                BusType      = $_.BusType
                PartitionStyle = $_.PartitionStyle
            }
        }
    } catch {
        Write-OSDCloudLog -Level Warning -Component 'Hardware' -Message "Get-Disk nicht verfuegbar: $($_.Exception.Message)"
        return @()
    }
}

function Resolve-OSDCloudComputerName {
    <#
    .SYNOPSIS
        Loest Platzhalter (%SERIAL%, %MODEL%) im Computernamen auf und kuerzt auf 15 Zeichen.
    .PARAMETER Pattern
        Das Namensmuster.
    .PARAMETER Hardware
        Das von Get-OSDCloudHardware gelieferte Objekt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Pattern,
        [Parameter(Mandatory)] $Hardware
    )
    $name = $Pattern
    $serial = if ($Hardware.SerialNumber) { ($Hardware.SerialNumber -replace '[^A-Za-z0-9]', '') } else { 'UNKNOWN' }
    $modelShort = if ($Hardware.Model) { ($Hardware.Model -replace '[^A-Za-z0-9]', '') } else { 'PC' }
    $name = $name.Replace('%SERIAL%', $serial).Replace('%MODEL%', $modelShort)
    if ($name.Length -gt 15) { $name = $name.Substring(0, 15) }
    return $name.ToUpperInvariant()
}

Export-ModuleMember -Function Get-OSDCloudHardware, Get-OSDCloudFirmwareType, Get-OSDCloudSecureBootState, `
    Get-OSDCloudTpmInfo, Get-OSDCloudDisk, Resolve-OSDCloudComputerName
