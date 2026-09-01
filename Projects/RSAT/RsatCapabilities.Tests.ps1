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

    It 'declares a BuildSourceMap hashtable' {
        $script:Data.Keys | Should -Contain 'BuildSourceMap'
        ,$script:Data.BuildSourceMap | Should -BeOfType [hashtable]
    }

    It 'aliases 23H2 (22631) and 25H2 (26200) to their paired base build' {
        # Microsoft ships one LOF ISO per release pair (22H2+23H2, 24H2+25H2);
        # the FoD CompDB carries no version lock on the RSAT Features.
        $script:Data.BuildSourceMap['22631'] | Should -Be '22621'
        $script:Data.BuildSourceMap['26200'] | Should -Be '26100'
    }
}
