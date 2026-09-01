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

Describe 'Get-NeutralFeatureCabName' {
    It 'builds the neutral amd64 FeaturePackage cab filename for a stem' {
        Get-NeutralFeatureCabName -CabStem 'Microsoft-Windows-DNS-Tools-FoD-Package' |
            Should -Be 'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~~.cab'
    }
}

Describe 'Find-MissingFeatureCab' {
    It 'returns an empty array when every neutral FeaturePackage cab is present' {
        $stems = @('Microsoft-Windows-DNS-Tools-FoD-Package', 'OpenSSH-Client-Package')
        $available = $stems | ForEach-Object { Get-NeutralFeatureCabName -CabStem $_ }
        (Find-MissingFeatureCab -AvailableFileName $available -CabStem $stems).Count | Should -Be 0
    }

    It 'names the neutral cab that is missing' {
        $stems = @('Microsoft-Windows-DNS-Tools-FoD-Package', 'OpenSSH-Client-Package')
        $available = @((Get-NeutralFeatureCabName -CabStem 'Microsoft-Windows-DNS-Tools-FoD-Package'))
        $missing = Find-MissingFeatureCab -AvailableFileName $available -CabStem $stems
        $missing | Should -Be @('OpenSSH-Client-Package~31bf3856ad364e35~amd64~~.cab')
    }

    It 'ignores language and wow64 cabs - only the neutral amd64 one counts' {
        $stems = @('Microsoft-Windows-DNS-Tools-FoD-Package')
        $available = @(
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~en-US~.cab'
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~wow64~~.cab'
        )   # no neutral amd64 -> still reported missing
        (Find-MissingFeatureCab -AvailableFileName $available -CabStem $stems).Count | Should -Be 1
    }

    It 'matches case-insensitively (FoD vs FOD)' {
        $stem = 'Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package'
        $available = @('microsoft-windows-failovercluster-management-tools-fod-package~31bf3856ad364e35~amd64~~.cab')
        (Find-MissingFeatureCab -AvailableFileName $available -CabStem @($stem)).Count | Should -Be 0
    }
}

Describe 'Get-RsatCabToCopy' {
    It 'returns every cab for each stem - all arches and languages' {
        $src = Join-Path $TestDrive 'lof-ok'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $dnsCabs = @(
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~~.cab'
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~en-US~.cab'
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~de-DE~.cab'
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~wow64~~.cab'
            'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~wow64~en-US~.cab'
        )
        foreach ($n in $dnsCabs + @('OpenSSH-Client-Package~31bf3856ad364e35~amd64~~.cab', 'Some-Unrelated-Feature~31bf3856ad364e35~amd64~~.cab')) {
            New-Item -ItemType File -Path (Join-Path $src $n) -Force | Out-Null
        }

        $names = @(Get-RsatCabToCopy -SourceFolder $src -CabStem @('Microsoft-Windows-DNS-Tools-FoD-Package', 'OpenSSH-Client-Package') | Split-Path -Leaf)

        $names.Count | Should -Be 6                       # 5 DNS + 1 OpenSSH
        foreach ($n in $dnsCabs) { $names | Should -Contain $n }
        $names | Should -Contain 'OpenSSH-Client-Package~31bf3856ad364e35~amd64~~.cab'
        $names | Should -Not -Contain 'Some-Unrelated-Feature~31bf3856ad364e35~amd64~~.cab'
    }

    It 'preserves the ISO filename casing (FOD vs FoD)' {
        $src = Join-Path $TestDrive 'lof-case'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $src 'Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package~31bf3856ad364e35~amd64~~.cab') -Force | Out-Null

        $leaf = Get-RsatCabToCopy -SourceFolder $src -CabStem @('Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package') | Split-Path -Leaf
        $leaf | Should -BeExactly 'Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package~31bf3856ad364e35~amd64~~.cab'
    }

    It 'throws when a stem has no cabs at all' {
        $src = Join-Path $TestDrive 'lof-missing'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $src 'Microsoft-Windows-DNS-Tools-FoD-Package~31bf3856ad364e35~amd64~~.cab') -Force | Out-Null

        { Get-RsatCabToCopy -SourceFolder $src -CabStem @('Microsoft-Windows-DNS-Tools-FoD-Package', 'OpenSSH-Client-Package') } |
            Should -Throw -ExpectedMessage '*OpenSSH-Client-Package*'
    }
}
