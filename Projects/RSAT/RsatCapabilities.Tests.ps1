BeforeAll {
    $script:DataFilePath = "$PSScriptRoot\RsatCapabilities.psd1"
    $script:Data = Import-PowerShellDataFile -LiteralPath $script:DataFilePath
}

Describe 'RsatCapabilities.psd1' {
    It 'loads as a PowerShell data file' {
        $script:Data | Should -Not -BeNullOrEmpty
        $script:Data.Capabilities | Should -Not -BeNullOrEmpty
    }

    It 'has exactly 9 capability entries' {
        $script:Data.Capabilities.Count | Should -Be 9
    }

    It 'gives every entry a non-empty CapabilityName and CabStem' {
        foreach ($entry in $script:Data.Capabilities) {
            $entry.CapabilityName | Should -Not -BeNullOrEmpty
            $entry.CabStem        | Should -Not -BeNullOrEmpty
        }
    }

    It 'lists the three dependency-root capabilities first, in order' {
        $names = @($script:Data.Capabilities.CapabilityName)
        $names[0] | Should -Be 'Rsat.ServerManager.Tools'
        $names[1] | Should -Be 'Rsat.FileServices.Tools'
        $names[2] | Should -Be 'Rsat.ActiveDirectory.DS-LDS.Tools'
    }

    It 'includes the non-RSAT and BitLocker capabilities' {
        $names = @($script:Data.Capabilities.CapabilityName)
        $names | Should -Contain 'OpenSSH.Client'
        $names | Should -Contain 'Rsat.BitLocker.Recovery.Tools'
    }

    It 'maps 25H2 (build 26200) to the 26100 source folder' {
        $script:Data.BuildSourceMap | Should -Not -BeNullOrEmpty
        $script:Data.BuildSourceMap['26200'] | Should -Be '26100'
    }

    It 'only aliases builds to a source folder that a real ISO produces' {
        $isoBuilds = @('22621', '26100')
        foreach ($target in $script:Data.BuildSourceMap.Values) {
            $isoBuilds | Should -Contain $target
        }
    }
}
