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

Describe 'Get-RsatBuildSourceMap' {
    It 'returns a hashtable from the real psd1 (currently empty - no aliases)' {
        $map = Get-RsatBuildSourceMap
        ,$map | Should -BeOfType [hashtable]
        $map.ContainsKey('26200') | Should -BeFalse
    }

    It 'returns an empty hashtable when the psd1 has no BuildSourceMap' {
        $noMap = Join-Path $TestDrive 'nomap.psd1'
        Set-Content -LiteralPath $noMap -Value "@{ Capabilities = @(@{ CapabilityName = 'X'; CabStem = 'Y' }) }"
        $result = Get-RsatBuildSourceMap -DataFilePath $noMap
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
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

    It 'returns null when no subfolder matches and there is no alias' {
        Resolve-RsatSourceFolder -PackageRoot $script:PackageRoot -BuildNumber 99999 | Should -BeNullOrEmpty
    }

    It 'follows the alias map when the build has no dedicated subfolder' {
        Resolve-RsatSourceFolder -PackageRoot $script:PackageRoot -BuildNumber 26200 -BuildSourceMap @{ '26200' = '26100' } |
            Should -Be (Join-Path $script:PackageRoot '26100')
    }

    It 'prefers an exact subfolder over an alias' {
        New-Item -ItemType Directory -Path (Join-Path $script:PackageRoot '26200') -Force | Out-Null
        Resolve-RsatSourceFolder -PackageRoot $script:PackageRoot -BuildNumber 26200 -BuildSourceMap @{ '26200' = '26100' } |
            Should -Be (Join-Path $script:PackageRoot '26200')
        Remove-Item -LiteralPath (Join-Path $script:PackageRoot '26200') -Recurse -Force
    }

    It 'returns null when the alias target subfolder itself is missing' {
        Resolve-RsatSourceFolder -PackageRoot $script:PackageRoot -BuildNumber 26200 -BuildSourceMap @{ '26200' = '99999' } |
            Should -BeNullOrEmpty
    }
}

Describe 'Select-CapabilitiesToInstall' {
    BeforeAll {
        $script:Targets = @(
            @{ CapabilityName = 'Rsat.Dns.Tools' }
            @{ CapabilityName = 'Rsat.DHCP.Tools' }
            @{ CapabilityName = 'OpenSSH.Client' }
            @{ CapabilityName = 'Rsat.ServerManager.Tools' }
        )
    }

    It 'classifies each target as Install / AlreadyInstalled / NotOffered' {
        $available = @(
            [PSCustomObject]@{ Name = 'Rsat.Dns.Tools~~~~0.0.1.0';    State = 'NotPresent' }
            [PSCustomObject]@{ Name = 'Rsat.DHCP.Tools~~~~0.0.1.0';   State = 'Installed' }
            [PSCustomObject]@{ Name = 'OpenSSH.Client~~~~0.0.1.0';    State = 'NotPresent' }
        )

        $result = Select-CapabilitiesToInstall -TargetCapability $script:Targets -AvailableCapability $available

        $result.Count | Should -Be 4
        ($result | Where-Object CapabilityName -eq 'Rsat.Dns.Tools').Action           | Should -Be 'Install'
        ($result | Where-Object CapabilityName -eq 'Rsat.Dns.Tools').FullName         | Should -Be 'Rsat.Dns.Tools~~~~0.0.1.0'
        ($result | Where-Object CapabilityName -eq 'Rsat.DHCP.Tools').Action          | Should -Be 'AlreadyInstalled'
        ($result | Where-Object CapabilityName -eq 'OpenSSH.Client').Action           | Should -Be 'Install'
        ($result | Where-Object CapabilityName -eq 'Rsat.ServerManager.Tools').Action | Should -Be 'NotOffered'
        ($result | Where-Object CapabilityName -eq 'Rsat.ServerManager.Tools').FullName | Should -BeNullOrEmpty
    }

    It 'matches capability names case-insensitively' {
        $available = @([PSCustomObject]@{ Name = 'rsat.dns.TOOLS~~~~0.0.1.0'; State = 'NotPresent' })
        $result = Select-CapabilitiesToInstall -TargetCapability @(@{ CapabilityName = 'Rsat.Dns.Tools' }) -AvailableCapability $available
        $result[0].Action | Should -Be 'Install'
    }

    It 'treats an empty available list as everything NotOffered' {
        $result = Select-CapabilitiesToInstall -TargetCapability $script:Targets -AvailableCapability @()
        @($result | Where-Object Action -ne 'NotOffered').Count | Should -Be 0
    }
}

Describe 'Get-CapabilityInstallOrder' {
    It 'moves the three dependency roots to the front in the required order, keeping the rest stable' {
        $capabilityInput = @(
            [PSCustomObject]@{ CapabilityName = 'Rsat.Dns.Tools' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.ActiveDirectory.DS-LDS.Tools' }
            [PSCustomObject]@{ CapabilityName = 'OpenSSH.Client' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.ServerManager.Tools' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.FileServices.Tools' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.DHCP.Tools' }
        )

        $ordered = @(Get-CapabilityInstallOrder -Capability $capabilityInput | ForEach-Object CapabilityName)

        $ordered[0] | Should -Be 'Rsat.ServerManager.Tools'
        $ordered[1] | Should -Be 'Rsat.FileServices.Tools'
        $ordered[2] | Should -Be 'Rsat.ActiveDirectory.DS-LDS.Tools'
        $ordered[3] | Should -Be 'Rsat.Dns.Tools'
        $ordered[4] | Should -Be 'OpenSSH.Client'
        $ordered[5] | Should -Be 'Rsat.DHCP.Tools'
    }
}

Describe 'Test-RunningInWinPE' {
    It 'returns true when the MiniNT key is present' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*MiniNT*' }
        Test-RunningInWinPE | Should -BeTrue
    }

    It 'returns false when the MiniNT key is absent' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*MiniNT*' }
        Test-RunningInWinPE | Should -BeFalse
    }
}

Describe 'Get-InstallRunContext' {
    It 'is quiet inside a task sequence even when interactive' {
        (Get-InstallRunContext -IsTaskSequence $true -IsInteractive $true).Quiet | Should -BeTrue
    }

    It 'is quiet when unattended outside a task sequence' {
        (Get-InstallRunContext -IsTaskSequence $false -IsInteractive $false).Quiet | Should -BeTrue
    }

    It 'is not quiet when interactive and outside a task sequence' {
        (Get-InstallRunContext -IsTaskSequence $false -IsInteractive $true).Quiet | Should -BeFalse
    }

    It 'echoes its inputs back on the result object' {
        $ctx = Get-InstallRunContext -IsTaskSequence $true -IsInteractive $false
        $ctx.IsTaskSequence | Should -BeTrue
        $ctx.IsInteractive  | Should -BeFalse
    }
}

Describe 'Get-ExitCodeForResult' {
    It 'returns 3 when not elevated, regardless of other inputs' {
        Get-ExitCodeForResult -IsElevated $false -SourceFolderFound $true -FailedCount 5 -RebootRequired $true | Should -Be 3
    }

    It 'returns 2 when elevated but no matching source folder' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $false -FailedCount 0 -RebootRequired $false | Should -Be 2
    }

    It 'returns 1 when one or more capabilities failed' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount 1 -RebootRequired $false | Should -Be 1
    }

    It 'returns 3010 when everything succeeded but a reboot is needed' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount 0 -RebootRequired $true | Should -Be 3010
    }

    It 'returns 0 when everything succeeded and no reboot is needed' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount 0 -RebootRequired $false | Should -Be 0
    }
}

Describe 'Write-Log' {
    It 'appends a timestamped line to the given log file' {
        $tempLog = Join-Path $TestDrive 'test.log'
        Write-Log -Message 'hello world' -LogFile $tempLog
        Get-Content -LiteralPath $tempLog | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - hello world$'
    }

    It 'is silent on the host when QuietMode is set' {
        $tempLog = Join-Path $TestDrive 'quiet.log'
        $script:QuietMode = $true
        try {
            Write-Log -Message 'quiet line' -LogFile $tempLog 6>&1 | Should -BeNullOrEmpty
        }
        finally {
            $script:QuietMode = $false
        }
        Get-Content -LiteralPath $tempLog | Should -Match 'quiet line$'
    }
}

Describe 'Test-IsAdministrator' {
    It 'returns a boolean' {
        Test-IsAdministrator | Should -BeOfType [bool]
    }
}

Describe 'Get-TsEnvironmentObject' {
    It 'returns null outside of a task sequence' {
        Get-TsEnvironmentObject | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSBuildNumberOnline' {
    It 'returns a positive integer build number for the running OS' {
        $result = Get-OSBuildNumberOnline
        $result | Should -BeOfType [int]
        $result | Should -BeGreaterThan 0
    }
}
