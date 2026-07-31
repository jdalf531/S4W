BeforeAll {
    . "$PSScriptRoot\Set-OsdAppSetting.ps1"

    $script:FixtureContent = @'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",

  // IMPORTANT: Replace this with a securely generated random string before deployment.
  // Generate with: [System.Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }) -as [byte[]])
  "ApiKey": "REPLACE-WITH-A-STRONG-RANDOM-KEY",

  "LogStorage": {
    // Absolute path on the IIS server where uploaded zip files will be stored.
    // The IIS application pool identity must have Modify rights on this folder.
    "BasePath": "C:\\OSDLogs"
  },

  "Mecm": {
    // Hostname or FQDN of the MECM primary/CAS site server running the SMS Provider.
    "SiteServer": "MECM-SERVER-FQDN",
    // Three-character MECM site code (e.g. "PS1").
    "SiteCode": "PS1"
  }
}
'@

    function ConvertFrom-CommentedJson([string] $Text) {
        ($Text -replace '(?m)^\s*//.*$', '') | ConvertFrom-Json
    }
}

Describe 'Set-OsdAppSetting' {
    BeforeEach {
        $script:FixturePath = Join-Path $TestDrive 'appsettings.json'
        Set-Content -LiteralPath $script:FixturePath -Value $script:FixtureContent -NoNewline
    }
    It 'replaces the ApiKey value' {
        Set-OsdAppSetting -Path $script:FixturePath -Key 'ApiKey' -Value 'abc123=='

        $json = ConvertFrom-CommentedJson (Get-Content -LiteralPath $script:FixturePath -Raw)
        $json.ApiKey | Should -Be 'abc123=='
    }

    It 'replaces the LogStorage BasePath value and round-trips a backslash path' {
        Set-OsdAppSetting -Path $script:FixturePath -Key 'BasePath' -Value 'D:\Logs\OSD'

        $json = ConvertFrom-CommentedJson (Get-Content -LiteralPath $script:FixturePath -Raw)
        $json.LogStorage.BasePath | Should -Be 'D:\Logs\OSD'
    }

    It 'replaces the Mecm SiteServer value' {
        Set-OsdAppSetting -Path $script:FixturePath -Key 'SiteServer' -Value 'cm01.corp.contoso.com'

        $json = ConvertFrom-CommentedJson (Get-Content -LiteralPath $script:FixturePath -Raw)
        $json.Mecm.SiteServer | Should -Be 'cm01.corp.contoso.com'
    }

    It 'replaces the Mecm SiteCode value' {
        Set-OsdAppSetting -Path $script:FixturePath -Key 'SiteCode' -Value 'LAB'

        $json = ConvertFrom-CommentedJson (Get-Content -LiteralPath $script:FixturePath -Raw)
        $json.Mecm.SiteCode | Should -Be 'LAB'
    }

    It 'preserves comments and untouched keys' {
        Set-OsdAppSetting -Path $script:FixturePath -Key 'ApiKey' -Value 'abc123=='

        $updated = Get-Content -LiteralPath $script:FixturePath -Raw
        $updated | Should -Match '// IMPORTANT: Replace this with a securely generated random string before deployment\.'
        $updated | Should -Match '"SiteCode":\s*"PS1"'
        $updated | Should -Match '"Default":\s*"Information"'
    }

    It 'throws when the key is not found' {
        { Set-OsdAppSetting -Path $script:FixturePath -Key 'NoSuchKey' -Value 'x' } | Should -Throw
    }
}
