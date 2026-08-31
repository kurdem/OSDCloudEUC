<#
.SYNOPSIS
    Pester-Tests fuer die Menuelogik (Pester v5).
#>
BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Logging.psm1') -Force
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Menu.psm1') -Force
    Initialize-OSDCloudLog -Path (Join-Path $env:TEMP 'OSDCloudTests') | Out-Null
    $script:Dep = Get-Content -LiteralPath (Join-Path $RepoRoot 'config\deployments.json') -Raw | ConvertFrom-Json
}

Describe 'New-OSDCloudSelectionState' {
    It 'erzeugt fuer jedes Feld einen Eintrag mit Default' {
        $state = New-OSDCloudSelectionState -Deployments $Dep
        foreach ($fieldName in $Dep.Fields.PSObject.Properties.Name) {
            $state.Contains($fieldName) | Should -BeTrue
        }
    }
    It 'setzt den Default fuer Profile korrekt' {
        $state = New-OSDCloudSelectionState -Deployments $Dep
        $state['Profile'] | Should -Be $Dep.Fields.Profile.Default
    }
}

Describe 'Read-OSDCloudInput Validierung' {
    It 'akzeptiert einen gueltigen Computernamen' {
        Mock -CommandName Read-Host -MockWith { 'PC-12345' } -ModuleName OSDCloud.Menu
        $result = Read-OSDCloudInput -Prompt 'Name' -Pattern '^[A-Za-z0-9%-]{1,15}$'
        $result | Should -Be 'PC-12345'
    }
    It 'nutzt den Default bei leerer Eingabe' {
        Mock -CommandName Read-Host -MockWith { '' } -ModuleName OSDCloud.Menu
        $result = Read-OSDCloudInput -Prompt 'Name' -Default 'DEFAULT01'
        $result | Should -Be 'DEFAULT01'
    }
}

Describe 'Select-OSDCloudOption' {
    It 'liefert die gewaehlte Option zurueck' {
        Mock -CommandName Read-Host -MockWith { '2' } -ModuleName OSDCloud.Menu
        $opts = $Dep.Fields.DriverStrategy.Options
        $sel = Select-OSDCloudOption -Title 'Treiber' -Options $opts
        $sel.Value | Should -Be $opts[1].Value
    }
    It 'liefert $null bei Auswahl 0 (Zurueck)' {
        Mock -CommandName Read-Host -MockWith { '0' } -ModuleName OSDCloud.Menu
        $opts = $Dep.Fields.DriverStrategy.Options
        Select-OSDCloudOption -Title 'Treiber' -Options $opts | Should -BeNullOrEmpty
    }
}
