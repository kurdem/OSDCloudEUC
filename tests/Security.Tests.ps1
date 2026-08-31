<#
.SYNOPSIS
    Pester-Tests fuer die Sicherheitsfunktionen (Pester v5).
#>
BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Logging.psm1') -Force
    Import-Module (Join-Path $RepoRoot 'src\modules\OSDCloud.Security.psm1') -Force
    Initialize-OSDCloudLog -Path (Join-Path $env:TEMP 'OSDCloudTests') | Out-Null
    $script:Allowed = @('raw.githubusercontent.com','github.com','api.github.com')
}

Describe 'Assert-OSDCloudAllowedHost' {
    It 'erlaubt einen Host aus der Liste ueber HTTPS' {
        Assert-OSDCloudAllowedHost -Url 'https://raw.githubusercontent.com/kurdem/OSDCloudEUC/main/config/global.json' -AllowedHosts $Allowed | Should -BeTrue
    }
    It 'lehnt einen nicht gelisteten Host ab' {
        { Assert-OSDCloudAllowedHost -Url 'https://evil.example.com/x' -AllowedHosts $Allowed } | Should -Throw
    }
    It 'lehnt HTTP (kein HTTPS) ab' {
        { Assert-OSDCloudAllowedHost -Url 'http://github.com/x' -AllowedHosts $Allowed } | Should -Throw
    }
}

Describe 'Test-OSDCloudHash' {
    BeforeAll {
        $script:TempFile = Join-Path $env:TEMP ('osd-hash-' + [guid]::NewGuid().ToString() + '.txt')
        Set-Content -LiteralPath $TempFile -Value 'OSDCloudEUC' -NoNewline
        $script:Expected = (Get-FileHash -LiteralPath $TempFile -Algorithm SHA256).Hash
    }
    AfterAll { Remove-Item -LiteralPath $TempFile -ErrorAction SilentlyContinue }

    It 'bestaetigt einen korrekten Hash' {
        (Test-OSDCloudHash -Path $TempFile -ExpectedHash $Expected).IsValid | Should -BeTrue
    }
    It 'erkennt einen falschen Hash' {
        (Test-OSDCloudHash -Path $TempFile -ExpectedHash 'DEADBEEF').IsValid | Should -BeFalse
    }
}

Describe 'Confirm-OSDCloudDiskWipe' {
    It 'gibt ohne Rueckfrage true zurueck wenn SkipConfirmation gesetzt ist' {
        Confirm-OSDCloudDiskWipe -SkipConfirmation | Should -BeTrue
    }
    It 'bestaetigt bei exakt passender Phrase' {
        Mock -CommandName Read-Host -MockWith { 'WIPE' } -ModuleName OSDCloud.Security
        Confirm-OSDCloudDiskWipe -ConfirmationPhrase 'WIPE' | Should -BeTrue
    }
    It 'lehnt bei abweichender Phrase ab' {
        Mock -CommandName Read-Host -MockWith { 'wipe' } -ModuleName OSDCloud.Security
        Confirm-OSDCloudDiskWipe -ConfirmationPhrase 'WIPE' | Should -BeFalse
    }
}

Describe 'Get-OSDCloudHashManifest' {
    BeforeAll {
        $script:Manifest = Join-Path $env:TEMP ('osd-manifest-' + [guid]::NewGuid().ToString() + '.sha256')
        Set-Content -LiteralPath $Manifest -Value @(
            '# Kommentar',
            'ABC123  config/global.json',
            'DEF456  config/deployments.json'
        )
    }
    AfterAll { Remove-Item -LiteralPath $Manifest -ErrorAction SilentlyContinue }

    It 'liest die Eintraege ohne Kommentarzeilen' {
        $m = Get-OSDCloudHashManifest -Path $Manifest
        $m['config/global.json'] | Should -Be 'ABC123'
        $m.Keys.Count | Should -Be 2
    }
}
