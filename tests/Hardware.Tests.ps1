<#
.SYNOPSIS
    Pester-Tests fuer die Hardware-Aufloesung (Pester v5).
    CIM-Aufrufe werden gemockt, daher lauffaehig auf jeder Plattform mit PowerShell.
#>
BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Logging.psm1') -Force
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Hardware.psm1') -Force
    Initialize-OSDCloudLog -Path (Join-Path $env:TEMP 'OSDCloudTests') | Out-Null
}

Describe 'Resolve-OSDCloudComputerName' {
    BeforeAll {
        $script:Hw = [pscustomobject]@{
            Manufacturer = 'Dell Inc.'
            Model        = 'Latitude 5450'
            SerialNumber = 'ABC-123-XYZ'
        }
    }
    It 'ersetzt %SERIAL% durch die bereinigte Seriennummer' {
        $name = Resolve-OSDCloudComputerName -Pattern 'PC-%SERIAL%' -Hardware $Hw
        $name | Should -Be 'PC-ABC123XYZ'
    }
    It 'kuerzt auf maximal 15 Zeichen' {
        $name = Resolve-OSDCloudComputerName -Pattern 'VERYLONGPREFIX-%SERIAL%' -Hardware $Hw
        $name.Length | Should -BeLessOrEqual 15
    }
    It 'liefert Grossbuchstaben' {
        $name = Resolve-OSDCloudComputerName -Pattern 'pc-%serial%'.Replace('%serial%','%SERIAL%') -Hardware $Hw
        $name | Should -MatchExactly '^[A-Z0-9-]+$'
    }
}

Describe 'Get-OSDCloudHardware (gemockt)' {
    BeforeAll {
        Mock -CommandName Get-CimInstance -ModuleName OSDCloud.Hardware -MockWith {
            param($ClassName, $Namespace)
            switch ($ClassName) {
                'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer = 'LENOVO'; Model = '21F6' } }
                'Win32_BIOS'           { [pscustomobject]@{ SerialNumber = 'PF-99887' } }
                default                { $null }
            }
        }
        Mock -CommandName Get-OSDCloudFirmwareType    -ModuleName OSDCloud.Hardware -MockWith { 'UEFI' }
        Mock -CommandName Get-OSDCloudSecureBootState -ModuleName OSDCloud.Hardware -MockWith { $true }
        Mock -CommandName Get-OSDCloudTpmInfo         -ModuleName OSDCloud.Hardware -MockWith { [pscustomobject]@{ Present = $true; SpecVersion = '2.0' } }
        Mock -CommandName Get-OSDCloudDisk            -ModuleName OSDCloud.Hardware -MockWith { @() }
    }
    It 'liefert die erwarteten Felder' {
        $hw = Get-OSDCloudHardware
        $hw.Manufacturer | Should -Be 'LENOVO'
        $hw.Model        | Should -Be '21F6'
        $hw.SerialNumber | Should -Be 'PF-99887'
        $hw.FirmwareType | Should -Be 'UEFI'
        $hw.SecureBoot   | Should -BeTrue
        $hw.TpmPresent   | Should -BeTrue
    }
}
