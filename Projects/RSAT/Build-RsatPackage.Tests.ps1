BeforeAll {
    . "$PSScriptRoot\Build-RsatPackage.ps1"
}

Describe 'Get-RsatCapabilityTable (builder copy)' {
    It 'loads the 9 entries from the real psd1' {
        (Get-RsatCapabilityTable).Count | Should -Be 9
    }

    It 'matches the Install-RSAT.ps1 copy exactly (name + stem, same order)' {
        $builderTable = Get-RsatCapabilityTable | ForEach-Object { "$($_.CapabilityName)|$($_.CabStem)" }
        $installerTable = & {
            . "$PSScriptRoot\Install-RSAT.ps1"
            Get-RsatCapabilityTable | ForEach-Object { "$($_.CapabilityName)|$($_.CabStem)" }
        }
        $builderTable | Should -Be $installerTable
    }
}

Describe 'Get-IsoBuildNumber' {
    It 'parses the build number from a 22H2 ISO filename' {
        Get-IsoBuildNumber -IsoFileName 'C:\isos\22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso' | Should -Be 22621
    }

    It 'parses the build number from a 24H2 ISO filename' {
        Get-IsoBuildNumber -IsoFileName '26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso' | Should -Be 26100
    }

    It 'throws when the filename does not start with a build number' {
        { Get-IsoBuildNumber -IsoFileName 'not-an-iso-name.iso' } | Should -Throw
    }
}
