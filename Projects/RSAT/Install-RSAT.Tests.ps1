BeforeAll {
    . "$PSScriptRoot\Install-RSAT.ps1"
}

Describe 'Get-RsatCapabilityTable' {
    It 'loads the 9 capability entries from the real psd1 next to the script' {
        $table = Get-RsatCapabilityTable
        $table.Count | Should -Be 9
        $table[0].CapabilityName | Should -Be 'Rsat.ServerManager.Tools'
    }

    It 'throws when the data file is missing' {
        { Get-RsatCapabilityTable -DataFilePath (Join-Path $TestDrive 'nope.psd1') } | Should -Throw
    }

    It 'throws when the data file has no Capabilities' {
        $empty = Join-Path $TestDrive 'empty.psd1'
        Set-Content -LiteralPath $empty -Value '@{ Capabilities = @() }'
        { Get-RsatCapabilityTable -DataFilePath $empty } | Should -Throw
    }
}

Describe 'Resolve-RsatSourceFolder' {
    BeforeAll {
        $script:PackageRoot = Join-Path $TestDrive 'LanguagesAndOptionalFeatures'
        New-Item -ItemType Directory -Path (Join-Path $script:PackageRoot '22621') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:PackageRoot '26100') -Force | Out-Null
    }

    It 'returns the matching build subfolder when it exists' {
        Resolve-RsatSourceFolder -PackageRoot $script:PackageRoot -BuildNumber 22621 |
            Should -Be (Join-Path $script:PackageRoot '22621')
    }

    It 'returns null when no subfolder matches the build number' {
        Resolve-RsatSourceFolder -PackageRoot $script:PackageRoot -BuildNumber 99999 | Should -BeNullOrEmpty
    }
}
