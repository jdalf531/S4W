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
