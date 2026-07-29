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

Describe 'Get-OldSanUrlNodes / Update-ReportServerConfigXml' {
    BeforeAll {
        function New-FixtureConfig {
            [xml]@'
<Configuration>
  <UrlReservations>
    <Application>ReportServerWebService</Application>
    <URLs>
      <URL>
        <UrlString>https://+:443</UrlString>
        <AccountSid>S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663</AccountSid>
        <AccountName>NT SERVICE\PowerBIReportServer</AccountName>
      </URL>
      <URL>
        <UrlString>https://old.contoso.com:443</UrlString>
        <AccountSid>S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663</AccountSid>
        <AccountName>NT SERVICE\PowerBIReportServer</AccountName>
      </URL>
    </URLs>
  </UrlReservations>
  <UrlReservations>
    <Application>ReportServerWebApp</Application>
    <URLs>
      <URL>
        <UrlString>https://+:443</UrlString>
        <AccountSid>S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663</AccountSid>
        <AccountName>NT SERVICE\PowerBIReportServer</AccountName>
      </URL>
    </URLs>
  </UrlReservations>
</Configuration>
'@
        }
    }

    It 'finds the one old SAN entry in ReportServerWebService' {
        $config = New-FixtureConfig

        $nodes = Get-OldSanUrlNodes -ConfigXml $config -Application 'ReportServerWebService'

        $nodes.Count | Should -Be 1
        $nodes[0].UrlString | Should -Be 'https://old.contoso.com:443'
    }

    It 'finds no old SAN entries in ReportServerWebApp' {
        $config = New-FixtureConfig

        (Get-OldSanUrlNodes -ConfigXml $config -Application 'ReportServerWebApp').Count | Should -Be 0
    }

    It 'replaces the old SAN entry and reports the removed hostname' {
        $config = New-FixtureConfig

        $removed = Update-ReportServerConfigXml -ConfigXml $config -NewHostname 'new.contoso.com' -Port 443

        $removed | Should -Be @('old.contoso.com')
    }

    It 'adds the new URL to both sections and preserves the wildcard listener' {
        $config = New-FixtureConfig

        Update-ReportServerConfigXml -ConfigXml $config -NewHostname 'new.contoso.com' -Port 443 | Out-Null

        $webServiceUrls = $config.SelectNodes("//UrlReservations[Application='ReportServerWebService']/URLs/URL") | ForEach-Object UrlString
        $webAppUrls = $config.SelectNodes("//UrlReservations[Application='ReportServerWebApp']/URLs/URL") | ForEach-Object UrlString

        $webServiceUrls | Should -Be @('https://+:443', 'https://new.contoso.com:443')
        $webAppUrls | Should -Be @('https://+:443', 'https://new.contoso.com:443')
    }

    It 'copies the AccountSid and AccountName from the wildcard entry onto the new node' {
        $config = New-FixtureConfig

        Update-ReportServerConfigXml -ConfigXml $config -NewHostname 'new.contoso.com' -Port 443 | Out-Null

        $newNode = $config.SelectSingleNode("//UrlReservations[Application='ReportServerWebService']/URLs/URL[UrlString='https://new.contoso.com:443']")
        $newNode.AccountName | Should -Be 'NT SERVICE\PowerBIReportServer'
        $newNode.AccountSid | Should -Be 'S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663'
    }
}

Describe 'Invoke-NetshCommand' {
    It 'runs a real read-only netsh command and captures exit code 0' {
        $result = Invoke-NetshCommand -Args @('http', 'show', 'urlacl')

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Not -BeNullOrEmpty
    }
}

Describe 'Backup-ReportServerConfig' {
    It 'copies the config file to a timestamped .bak file next to it' {
        $sourcePath = Join-Path $TestDrive 'rsreportserver.config'
        Set-Content -LiteralPath $sourcePath -Value '<Configuration></Configuration>'

        $backupPath = Backup-ReportServerConfig -ConfigPath $sourcePath

        # Note: the regex concatenation must be parenthesized. In PowerShell's
        # "command argument mode" (bare args to a cmdlet, not already inside an
        # expression), `-Match [regex]::Escape($sourcePath) + '...'` is NOT
        # combined via the `+` operator - it gets split into separate positional
        # arguments, which breaks Should's pipeline binding for $backupPath.
        $backupPath | Should -Match ([regex]::Escape($sourcePath) + '\.bak-\d{14}$')
        Test-Path -LiteralPath $backupPath | Should -BeTrue
        Get-Content -LiteralPath $backupPath -Raw | Should -Be (Get-Content -LiteralPath $sourcePath -Raw)
    }
}
