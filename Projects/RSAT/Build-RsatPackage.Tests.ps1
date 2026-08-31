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

Describe 'Get-RsatCabFileName' {
    It 'builds the language-neutral cab filename from a stem' {
        Get-RsatCabFileName -CabStem 'Microsoft-Windows-DNS-Tools-FoD-Package' |
            Should -Be 'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~~.cab'
    }
}

Describe 'Find-MissingCabFileName' {
    It 'returns an empty array when every expected cab is present' {
        $stems = @('Microsoft-Windows-DNS-Tools-FoD-Package', 'OpenSSH-Client-Package')
        $available = $stems | ForEach-Object { Get-RsatCabFileName -CabStem $_ }
        (Find-MissingCabFileName -AvailableFileName $available -CabStem $stems).Count | Should -Be 0
    }

    It 'names the cab that is missing' {
        $stems = @('Microsoft-Windows-DNS-Tools-FoD-Package', 'OpenSSH-Client-Package')
        $available = @((Get-RsatCabFileName -CabStem 'Microsoft-Windows-DNS-Tools-FoD-Package'))
        $missing = Find-MissingCabFileName -AvailableFileName $available -CabStem $stems
        $missing | Should -Be @('OpenSSH-Client-Package~31bf3856ad364e35~amd64~~.cab')
    }

    It 'matches case-insensitively (FoD vs FOD)' {
        $stem = 'Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package'
        $available = @('microsoft-windows-failovercluster-management-tools-fod-package~31bf3856ad364e35~amd64~~.cab')
        (Find-MissingCabFileName -AvailableFileName $available -CabStem @($stem)).Count | Should -Be 0
    }
}

Describe 'Get-RsatCabToCopy' {
    BeforeAll {
        $script:Stems = @(
            'Microsoft-Windows-DNS-Tools-FoD-Package'
            'Microsoft-Windows-DHCP-Tools-FoD-Package'
            'OpenSSH-Client-Package'
        )
    }

    It 'returns one full path per stem when all cabs exist' {
        $src = Join-Path $TestDrive 'lof-ok'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $src 'Some-Unrelated-Feature~31bf3856ad364e35~amd64~~.cab') -Force | Out-Null
        foreach ($s in $script:Stems) {
            New-Item -ItemType File -Path (Join-Path $src (Get-RsatCabFileName -CabStem $s)) -Force | Out-Null
        }

        $result = Get-RsatCabToCopy -SourceFolder $src -CabStem $script:Stems

        $result.Count | Should -Be 3
        $result | ForEach-Object { Test-Path -LiteralPath $_ | Should -BeTrue }
        ($result | Split-Path -Leaf) | Should -Contain 'OpenSSH-Client-Package~31bf3856ad364e35~amd64~~.cab'
    }

    It 'throws and names the missing cab when one is absent' {
        $src = Join-Path $TestDrive 'lof-missing'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $src (Get-RsatCabFileName -CabStem 'Microsoft-Windows-DNS-Tools-FoD-Package')) -Force | Out-Null

        { Get-RsatCabToCopy -SourceFolder $src -CabStem $script:Stems } |
            Should -Throw -ExpectedMessage '*OpenSSH-Client-Package*'
    }
}
