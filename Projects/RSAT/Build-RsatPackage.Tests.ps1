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

Describe 'Get-BuildFromPackageManifest' {
    It 'reads the build number from a package manifest version string' {
        $xml = '<assemblyIdentity name="Microsoft-Windows-DNS-Tools-FoD-Package" version="10.0.28000.1" processorArchitecture="amd64" language="neutral" />'
        Get-BuildFromPackageManifest -ManifestXml $xml | Should -Be 28000
    }

    It 'reads 22621 / 26100 style builds too' {
        Get-BuildFromPackageManifest -ManifestXml 'foo version="10.0.22621.1" bar' | Should -Be 22621
        Get-BuildFromPackageManifest -ManifestXml 'foo version="10.0.26100.1" bar' | Should -Be 26100
    }

    It 'ignores non-10.0 version strings and reads the OS build' {
        $xml = '<package version="1.0" /><assemblyIdentity version="10.0.26200.2" />'
        Get-BuildFromPackageManifest -ManifestXml $xml | Should -Be 26200
    }

    It 'throws when no 10.0.<build>.<revision> version is present' {
        { Get-BuildFromPackageManifest -ManifestXml '<node version="1.2.3" />' } | Should -Throw
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
