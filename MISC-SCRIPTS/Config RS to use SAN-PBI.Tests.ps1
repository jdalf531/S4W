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
