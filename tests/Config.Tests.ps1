<#
.SYNOPSIS
    Pester-Tests fuer Konfiguration und Profile (Pester v5).
#>
BeforeAll {
    $script:RepoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $script:ConfigRoot = Join-Path $RepoRoot 'config'
    $script:SchemaRoot = Join-Path $ConfigRoot 'schema'
    $script:ProfileRoot= Join-Path $RepoRoot 'profiles'

    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Logging.psm1') -Force
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Security.psm1') -Force
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Config.psm1') -Force
    Initialize-OSDCloudLog -Path (Join-Path $env:TEMP 'OSDCloudTests') | Out-Null
}

Describe 'JSON-Konfigurationen sind wohlgeformt' {
    It 'Datei <_> ist gueltiges JSON' -ForEach @(
        (Get-ChildItem -Path $ConfigRoot -Filter *.json -Recurse).FullName +
        (Get-ChildItem -Path $ProfileRoot -Filter *.json).FullName
    ) {
        { Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'global.json' {
    BeforeAll { $script:Global = Get-Content -LiteralPath (Join-Path $ConfigRoot 'global.json') -Raw | ConvertFrom-Json }

    It 'enthaelt Repository Owner und Name' {
        $Global.Repository.Owner | Should -Not -BeNullOrEmpty
        $Global.Repository.Name  | Should -Not -BeNullOrEmpty
    }
    It 'DefaultProfile ist in AllowedProfiles enthalten' {
        $Global.Deployment.AllowedProfiles | Should -Contain $Global.Deployment.DefaultProfile
    }
    It 'AllowedHosts enthaelt raw.githubusercontent.com' {
        $Global.Security.AllowedHosts | Should -Contain 'raw.githubusercontent.com'
    }
    It 'entspricht dem global.schema.json (falls Test-Json -Schema verfuegbar)' {
        $json = Get-Content -LiteralPath (Join-Path $ConfigRoot 'global.json') -Raw
        Test-OSDCloudConfigSchema -Json $json -SchemaPath (Join-Path $SchemaRoot 'global.schema.json') | Should -BeTrue
    }
}

Describe 'deployments.json' {
    BeforeAll { $script:Dep = Get-Content -LiteralPath (Join-Path $ConfigRoot 'deployments.json') -Raw | ConvertFrom-Json }

    It 'hat mindestens einen Menueeintrag' {
        $Dep.MainMenu.Count | Should -BeGreaterThan 0
    }
    It 'jedes SelectField/InputField verweist auf ein existierendes Feld' {
        foreach ($item in $Dep.MainMenu) {
            if ($item.Action -in 'SelectField','InputField') {
                $Dep.Fields.PSObject.Properties.Name | Should -Contain $item.Field
            }
        }
    }
    It 'jedes select-Feld hat Optionen' {
        foreach ($fieldName in $Dep.Fields.PSObject.Properties.Name) {
            $field = $Dep.Fields.$fieldName
            if ($field.Type -eq 'select') {
                @($field.Options).Count | Should -BeGreaterThan 0
            }
        }
    }
    It 'entspricht dem deployments.schema.json (falls Test-Json -Schema verfuegbar)' {
        $json = Get-Content -LiteralPath (Join-Path $ConfigRoot 'deployments.json') -Raw
        Test-OSDCloudConfigSchema -Json $json -SchemaPath (Join-Path $SchemaRoot 'deployments.schema.json') | Should -BeTrue
    }
}

Describe 'Profile sind gegen die Kataloge aufloesbar' {
    BeforeAll {
        $script:Os = Get-Content -LiteralPath (Join-Path $ConfigRoot 'operating-systems.json') -Raw | ConvertFrom-Json
        $script:Dep = Get-Content -LiteralPath (Join-Path $ConfigRoot 'deployments.json') -Raw | ConvertFrom-Json
    }

    It 'Profil <_> referenziert ein existierendes OperatingSystem' -ForEach @((Get-ChildItem -Path $ProfileRoot -Filter *.json).FullName) {
        $prof = Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json
        $Os.OperatingSystems.Id | Should -Contain $prof.OperatingSystem
    }

    It 'Profil <_> nutzt gueltige DriverStrategy und UpdateStrategy' -ForEach @((Get-ChildItem -Path $ProfileRoot -Filter *.json).FullName) {
        $prof = Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json
        $Dep.Fields.DriverStrategy.Options.Value | Should -Contain $prof.DriverStrategy
        $Dep.Fields.UpdateStrategy.Options.Value | Should -Contain $prof.UpdateStrategy
    }
}
