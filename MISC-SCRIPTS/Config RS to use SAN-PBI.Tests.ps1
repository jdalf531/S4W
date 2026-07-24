BeforeAll {
    . "$PSScriptRoot\Config RS to use SAN-PBI.ps1"
}

Describe 'Write-Log' {
    It 'appends a timestamped line to the given log file' {
        $tempLog = Join-Path $TestDrive 'test.log'

        Write-Log -Message 'hello world' -LogFile $tempLog

        Get-Content -LiteralPath $tempLog | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - hello world$'
    }
}

Describe 'Test-IsAdministrator' {
    It 'returns a boolean' {
        $result = Test-IsAdministrator

        $result | Should -BeOfType [bool]
    }
}

Describe 'Get-PbirsServiceInfo' {
    It 'reports IsReady true when the service and config file both exist' {
        Mock Get-Service { [PSCustomObject]@{ Name = 'PowerBIReportServer' } }
        Mock Test-Path { $true }

        $result = Get-PbirsServiceInfo

        $result.IsReady | Should -BeTrue
        $result.ConfigPath | Should -Be $script:PbirsConfigPath
    }

    It 'reports IsReady false when the service is missing' {
        Mock Get-Service { $null }
        Mock Test-Path { $true }

        (Get-PbirsServiceInfo).IsReady | Should -BeFalse
    }

    It 'reports IsReady false when the config file is missing' {
        Mock Get-Service { [PSCustomObject]@{ Name = 'PowerBIReportServer' } }
        Mock Test-Path { $false }

        (Get-PbirsServiceInfo).IsReady | Should -BeFalse
    }
}

Describe 'Get-TlsPortFromConfig' {
    BeforeAll {
        [xml]$script:ConfigWithPort = @'
<Configuration>
  <UrlReservations>
    <Application>ReportServerWebService</Application>
    <URLs>
      <URL><UrlString>https://+:8443</UrlString></URL>
    </URLs>
  </UrlReservations>
</Configuration>
'@
        [xml]$script:ConfigWithoutPort = @'
<Configuration>
  <UrlReservations>
    <Application>ReportServerWebService</Application>
    <URLs>
      <URL><UrlString>https://old.contoso.com:443</UrlString></URL>
    </URLs>
  </UrlReservations>
</Configuration>
'@
    }

    It 'extracts the port from the wildcard listener' {
        Get-TlsPortFromConfig -ConfigXml $script:ConfigWithPort | Should -Be 8443
    }

    It 'returns null when there is no wildcard listener' {
        Get-TlsPortFromConfig -ConfigXml $script:ConfigWithoutPort | Should -BeNullOrEmpty
    }
}

Describe 'Get-ReservedUrlsFromNetshOutput / Test-UrlAclConflict' {
    BeforeAll {
        $script:UrlAclFixture = @(
            'URL Reservations:'
            '-----------------'
            ''
            '    Reserved URL            : https://+:443/ReportServer/'
            '        User: NT SERVICE\PowerBIReportServer'
            '            Listen: Yes'
            ''
            '    Reserved URL            : https://old.contoso.com:443/ReportServer/'
            '        User: NT SERVICE\PowerBIReportServer'
            '            Listen: Yes'
        )
    }

    It 'extracts reserved URLs with trailing slash trimmed' {
        $urls = Get-ReservedUrlsFromNetshOutput -NetshOutput $script:UrlAclFixture

        $urls | Should -Contain 'https://old.contoso.com:443/ReportServer'
        $urls | Should -Contain 'https://+:443/ReportServer'
    }

    It 'detects a conflict for a URL that is already reserved' {
        Test-UrlAclConflict -NetshOutput $script:UrlAclFixture -Url 'https://old.contoso.com:443/ReportServer' | Should -BeTrue
    }

    It 'reports no conflict for a URL that is not reserved' {
        Test-UrlAclConflict -NetshOutput $script:UrlAclFixture -Url 'https://new.contoso.com:443/ReportServer' | Should -BeFalse
    }
}

Describe 'New-UrlAclCommandArgs' {
    It 'builds add commands for all four PBIRS paths with user/sddl' {
        $commands = New-UrlAclCommandArgs -Action add -Hostname 'reports.contoso.com' -Port 443

        $commands.Count | Should -Be 4
        ($commands | Select-Object -ExpandProperty Path) | Should -Be @('ReportServer', 'Reports', 'PowerBI', 'wopi')

        $reportServerCmd = $commands | Where-Object Path -eq 'ReportServer'
        $reportServerCmd.Url | Should -Be 'https://reports.contoso.com:443/ReportServer'
        $reportServerCmd.Args | Should -Be @(
            'http', 'add', 'urlacl',
            'url=https://reports.contoso.com:443/ReportServer',
            'user=NT SERVICE\PowerBIReportServer',
            'sddl=D:(A;;GX;;;S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663)'
        )
    }

    It 'builds delete commands without user/sddl arguments' {
        $commands = New-UrlAclCommandArgs -Action delete -Hostname 'old.contoso.com' -Port 443

        $wopiCmd = $commands | Where-Object Path -eq 'wopi'
        $wopiCmd.Args | Should -Be @('http', 'delete', 'urlacl', 'url=https://old.contoso.com:443/wopi')
    }
}

Describe 'Get-CertHashFromSslCertOutput' {
    It 'extracts the certificate hash line' {
        $fixture = @(
            '    SSL Certificate bound to IP:port                  : 0.0.0.0:443'
            '    Application ID                                    : {00000000-0000-0000-0000-000000000000}'
            '    Certificate Hash                                   : a1b2c3d4e5f60718293a4b5c6d7e8f901234567'
            '    Certificate Store Name                             : MY'
        )

        Get-CertHashFromSslCertOutput -NetshOutput $fixture | Should -Be 'a1b2c3d4e5f60718293a4b5c6d7e8f901234567'
    }

    It 'returns null when there is no bound certificate' {
        Get-CertHashFromSslCertOutput -NetshOutput @('The system cannot find the file specified.') | Should -BeNullOrEmpty
    }
}

Describe 'Test-CertificateForSan' {
    BeforeAll {
        $script:TestCert = New-SelfSignedCertificate -DnsName 'reports.contoso.com', 'alt.contoso.com' `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -NotAfter (Get-Date).AddDays(1)
    }

    AfterAll {
        Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($script:TestCert.Thumbprint)" -Force -ErrorAction SilentlyContinue
    }

    It 'flags a self-signed certificate as invalid' {
        $result = Test-CertificateForSan -Certificate $script:TestCert -Hostname 'reports.contoso.com'

        $result.IsValid | Should -BeFalse
        $result.Failures | Should -Contain 'Certificate appears to be self-signed (Issuer equals Subject).'
    }

    It 'reports when the hostname is missing from the SAN list' {
        $result = Test-CertificateForSan -Certificate $script:TestCert -Hostname 'nomatch.contoso.com'

        ($result.Failures -join ' ') | Should -Match "does not include 'nomatch.contoso.com'"
    }

    It 'lists the SAN names it found on the certificate' {
        $result = Test-CertificateForSan -Certificate $script:TestCert -Hostname 'alt.contoso.com'

        $result.SanNames | Should -Contain 'reports.contoso.com'
        $result.SanNames | Should -Contain 'alt.contoso.com'
    }

    It 'flags a certificate with no private key as invalid' {
        $publicOnlyBytes = $script:TestCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $publicOnlyCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($publicOnlyBytes)

        $result = Test-CertificateForSan -Certificate $publicOnlyCert -Hostname 'reports.contoso.com'

        $result.Failures | Should -Contain 'Certificate has no private key.'
    }
}
