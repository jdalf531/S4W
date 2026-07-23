# Configure PBIRS SAN Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`, a PowerShell script that replaces a Power BI Report Server's stale SAN configuration with a new one entered at runtime, after validating prerequisites.

**Architecture:** A single `.ps1` file with pure, independently-testable helper functions (config XML parsing/mutation, netsh output parsing, certificate SAN validation, urlacl command building) plus a small set of system-integration wrappers (netsh execution, service restart, file backup), all orchestrated by one `Invoke-Main` function. A guard at the bottom of the file (`if ($MyInvocation.InvocationName -ne '.')`) means dot-sourcing the script (as the test file does) loads the functions without running `Invoke-Main`, while running it normally executes the full flow.

**Tech Stack:** Windows PowerShell 5.1, Pester 5.7.1 for tests (already installed — do not use the older Pester 3.4.0 also present on this machine).

## Global Constraints

- Target product is Power BI Report Server (PBIRS) only — not SSRS. Fixed values (from the spec, copied verbatim from the MS Learn doc):
  - Service name: `PowerBIReportServer`
  - Config path: `C:\Program Files\Microsoft Power BI Report Server\PBIRS\ReportServer\rsreportserver.config`
  - Account name: `NT SERVICE\PowerBIReportServer`
  - Account SID: `S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663`
  - urlacl paths: `ReportServer`, `Reports`, `PowerBI`, `wopi`
- Every step of the blocker-check sequence and the apply sequence must log via `Write-Log` (pattern matches `DailyAppUpdate\DailyAppUpdatev2.ps1`'s `Write-Log`: timestamped line appended to a log file next to the script).
- No self-signed certificates, no certs without a private key, and the bound cert's SAN list must include the requested hostname — all three are hard blockers, not warnings.
- Script must support a `-WhatIf` switch that prints a full preview and makes no changes.
- Before any file edit, back up `rsreportserver.config` to `rsreportserver.config.bak-<yyyyMMddHHmmss>` in the same folder.
- Run all Pester tests with: `Import-Module Pester -MinimumVersion 5.0 -Force` then `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`.

---

### Task 1: Script scaffold, logging, admin check

**Files:**
- Create: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`
- Test: `MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`

**Interfaces:**
- Produces: `Write-Log([string]$Message, [string]$LogFile = $script:LogFile)` → void, appends a timestamped line to `$LogFile` and writes it to host.
- Produces: `Test-IsAdministrator()` → `[bool]`.
- Produces script-scope constants: `$script:LogFile`, `$script:PbirsServiceName`, `$script:PbirsConfigPath`, `$script:PbirsAccountName`, `$script:PbirsAccountSid`, `$script:PbirsUrlAclPaths`.

- [ ] **Step 1: Write the failing test file**

```powershell
# MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
Import-Module Pester -MinimumVersion 5.0 -Force
Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed
```
Expected: FAIL — dot-sourcing an empty script leaves `Write-Log` and `Test-IsAdministrator` undefined, so both `It` blocks error with "The term 'Write-Log' is not recognized" / "'Test-IsAdministrator' is not recognized".

- [ ] **Step 3: Write the scaffold**

```powershell
<#
.SYNOPSIS
    Configures Power BI Report Server (PBIRS) to use a Subject Alternative Name (SAN),
    replacing any previously-configured SAN.
.DESCRIPTION
    Implements https://learn.microsoft.com/en-us/sql/reporting-services/report-server-sharepoint/configure-reporting-services-to-use-a-subject-alternative-name
    for Power BI Report Server specifically. Prompts for the SAN URL, validates
    prerequisites (admin rights, service/config present, TLS port + certificate valid
    for the hostname, no urlacl conflicts), then updates rsreportserver.config and the
    netsh http urlacl reservations, and restarts the service.
.NOTES
    Modified: 2026-07-23
#>

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$script:LogFile           = Join-Path $PSScriptRoot 'SAN-Config-Log.txt'
$script:PbirsServiceName  = 'PowerBIReportServer'
$script:PbirsConfigPath   = 'C:\Program Files\Microsoft Power BI Report Server\PBIRS\ReportServer\rsreportserver.config'
$script:PbirsAccountName  = 'NT SERVICE\PowerBIReportServer'
$script:PbirsAccountSid   = 'S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663'
$script:PbirsUrlAclPaths  = @('ReportServer', 'Reports', 'PowerBI', 'wopi')

# ==============================
# Logging
# ==============================
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogFile = $script:LogFile
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line
}

# ==============================
# Blocker checks
# ==============================
function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (2/2 tests).

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1" "MISC-SCRIPTS/Config RS to use SAN-PBI.Tests.ps1"
git commit -m "feat: scaffold PBIRS SAN config script with logging and admin check"
```

---

### Task 2: PBIRS discovery and TLS port parsing

**Files:**
- Modify: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`
- Test: `MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`

**Interfaces:**
- Consumes: `$script:PbirsServiceName`, `$script:PbirsConfigPath` (Task 1).
- Produces: `Get-PbirsServiceInfo()` → `[PSCustomObject]@{ ServiceFound=[bool]; Service; ConfigPath=[string]; ConfigExists=[bool]; IsReady=[bool] }`.
- Produces: `Get-TlsPortFromConfig([xml]$ConfigXml)` → `[int]` or `$null` if no `https://+:<port>` wildcard entry exists under the `ReportServerWebService` `UrlReservations`.

- [ ] **Step 1: Add the failing tests**

```powershell
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: FAIL — `Get-PbirsServiceInfo` and `Get-TlsPortFromConfig` not recognized.

- [ ] **Step 3: Implement**

Add below the `Test-IsAdministrator` function in the `.ps1`:

```powershell
function Get-PbirsServiceInfo {
    $service = Get-Service -Name $script:PbirsServiceName -ErrorAction SilentlyContinue
    $configExists = Test-Path -LiteralPath $script:PbirsConfigPath

    return [PSCustomObject]@{
        ServiceFound = [bool]$service
        Service      = $service
        ConfigPath   = $script:PbirsConfigPath
        ConfigExists = $configExists
        IsReady      = ([bool]$service -and $configExists)
    }
}

function Get-TlsPortFromConfig {
    param([Parameter(Mandatory)][xml]$ConfigXml)

    $wildcardUrl = $ConfigXml.SelectSingleNode("//UrlReservations[Application='ReportServerWebService']/URLs/URL[starts-with(UrlString, 'https://+:')]")

    if (-not $wildcardUrl) {
        return $null
    }

    if ($wildcardUrl.UrlString -match ':(?<port>\d+)$') {
        return [int]$Matches['port']
    }

    return $null
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (7/7 tests).

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1" "MISC-SCRIPTS/Config RS to use SAN-PBI.Tests.ps1"
git commit -m "feat: add PBIRS service discovery and TLS port parsing"
```

---

### Task 3: urlacl parsing and command building

**Files:**
- Modify: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`
- Test: `MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`

**Interfaces:**
- Consumes: `$script:PbirsAccountName`, `$script:PbirsAccountSid`, `$script:PbirsUrlAclPaths` (Task 1).
- Produces: `Get-ReservedUrlsFromNetshOutput([string[]]$NetshOutput)` → `[string[]]` of reserved URLs (trailing slash trimmed).
- Produces: `Test-UrlAclConflict([string[]]$NetshOutput, [string]$Url)` → `[bool]`.
- Produces: `New-UrlAclCommandArgs([string]$Action, [string]$Hostname, [int]$Port)` → array of `[PSCustomObject]@{ Path; Url; Args=[string[]] }`, one per `$script:PbirsUrlAclPaths` entry. `$Action` is `'add'` or `'delete'`; `'add'` includes `user=` and `sddl=` args, `'delete'` does not.

- [ ] **Step 1: Add the failing tests**

```powershell
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: FAIL — the three new functions are not recognized.

- [ ] **Step 3: Implement**

Add below `Get-TlsPortFromConfig`:

```powershell
function Get-ReservedUrlsFromNetshOutput {
    param([Parameter(Mandatory)][string[]]$NetshOutput)

    $reserved = foreach ($line in $NetshOutput) {
        if ($line -match '^\s*Reserved URL\s*:\s*(?<url>\S+)') {
            $Matches['url'].TrimEnd('/')
        }
    }
    return $reserved
}

function Test-UrlAclConflict {
    param(
        [Parameter(Mandatory)][string[]]$NetshOutput,
        [Parameter(Mandatory)][string]$Url
    )

    $reserved = Get-ReservedUrlsFromNetshOutput -NetshOutput $NetshOutput
    return ($reserved | Where-Object { $_ -ieq $Url.TrimEnd('/') }).Count -gt 0
}

function New-UrlAclCommandArgs {
    param(
        [Parameter(Mandatory)][ValidateSet('add', 'delete')][string]$Action,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][int]$Port
    )

    return $script:PbirsUrlAclPaths | ForEach-Object {
        $url = "https://$($Hostname):$($Port)/$_"
        if ($Action -eq 'add') {
            [PSCustomObject]@{
                Path = $_
                Url  = $url
                Args = @(
                    'http', 'add', 'urlacl',
                    "url=$url",
                    "user=$script:PbirsAccountName",
                    "sddl=D:(A;;GX;;;$script:PbirsAccountSid)"
                )
            }
        }
        else {
            [PSCustomObject]@{
                Path = $_
                Url  = $url
                Args = @('http', 'delete', 'urlacl', "url=$url")
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (12/12 tests).

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1" "MISC-SCRIPTS/Config RS to use SAN-PBI.Tests.ps1"
git commit -m "feat: add urlacl parsing, conflict detection, and command builders"
```

---

### Task 4: Certificate SAN validation

**Files:**
- Modify: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`
- Test: `MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`

**Interfaces:**
- Produces: `Get-CertHashFromSslCertOutput([string[]]$NetshOutput)` → `[string]` thumbprint or `$null`.
- Produces: `Test-CertificateForSan([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate, [string]$Hostname)` → `[PSCustomObject]@{ IsValid=[bool]; Failures=[string[]]; SanNames=[string[]] }`.

- [ ] **Step 1: Add the failing tests**

```powershell
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: FAIL — `Get-CertHashFromSslCertOutput` and `Test-CertificateForSan` not recognized.

- [ ] **Step 3: Implement**

Add below `New-UrlAclCommandArgs`:

```powershell
function Get-CertHashFromSslCertOutput {
    param([Parameter(Mandatory)][string[]]$NetshOutput)

    foreach ($line in $NetshOutput) {
        if ($line -match '^\s*Certificate Hash\s*:\s*(?<hash>[0-9a-fA-F]+)') {
            return $Matches['hash']
        }
    }
    return $null
}

function Test-CertificateForSan {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][string]$Hostname
    )

    $failures = [System.Collections.Generic.List[string]]::new()

    if (-not $Certificate.HasPrivateKey) {
        $failures.Add('Certificate has no private key.')
    }

    if ($Certificate.Issuer -eq $Certificate.Subject) {
        $failures.Add('Certificate appears to be self-signed (Issuer equals Subject).')
    }

    $sanExtension = $Certificate.Extensions | Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' } | Select-Object -First 1
    $sanNames = @()
    if ($sanExtension) {
        $sanText = $sanExtension.Format($true)
        $sanNames = [regex]::Matches($sanText, 'DNS Name=(?<name>\S+)') | ForEach-Object { $_.Groups['name'].Value }
    }

    if ($Hostname -notin $sanNames) {
        $failures.Add("Certificate SAN list does not include '$Hostname'. Found: $($sanNames -join ', ')")
    }

    return [PSCustomObject]@{
        IsValid  = ($failures.Count -eq 0)
        Failures = $failures
        SanNames = $sanNames
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (18/18 tests).

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1" "MISC-SCRIPTS/Config RS to use SAN-PBI.Tests.ps1"
git commit -m "feat: add certificate SAN validation"
```

---

### Task 5: Config XML old-SAN detection and mutation

**Files:**
- Modify: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`
- Test: `MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`

**Interfaces:**
- Produces: `Get-OldSanUrlNodes([xml]$ConfigXml, [string]$Application)` → array of `XmlElement` (the `<URL>` nodes whose `UrlString` host is not `+`).
- Produces: `Update-ReportServerConfigXml([xml]$ConfigXml, [string]$NewHostname, [int]$Port)` → `[string[]]` of hostnames removed (unique), mutates `$ConfigXml` in place: removes old-SAN nodes and appends a new `<URL>` node (same `AccountSid`/`AccountName` as the wildcard sibling) to both `ReportServerWebService` and `ReportServerWebApp` sections.

- [ ] **Step 1: Add the failing tests**

```powershell
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: FAIL — `Get-OldSanUrlNodes` and `Update-ReportServerConfigXml` not recognized.

- [ ] **Step 3: Implement**

Add below `Test-CertificateForSan`:

```powershell
function Get-OldSanUrlNodes {
    param(
        [Parameter(Mandatory)][xml]$ConfigXml,
        [Parameter(Mandatory)][string]$Application
    )

    $urlNodes = $ConfigXml.SelectNodes("//UrlReservations[Application='$Application']/URLs/URL")
    return @($urlNodes | Where-Object { $_.UrlString -notmatch '^https?://\+:' })
}

function Update-ReportServerConfigXml {
    param(
        [Parameter(Mandatory)][xml]$ConfigXml,
        [Parameter(Mandatory)][string]$NewHostname,
        [Parameter(Mandatory)][int]$Port
    )

    $applications = 'ReportServerWebService', 'ReportServerWebApp'
    $removedHostnames = [System.Collections.Generic.List[string]]::new()

    foreach ($app in $applications) {
        $urlsNode = $ConfigXml.SelectSingleNode("//UrlReservations[Application='$app']/URLs")
        if (-not $urlsNode) {
            throw "Could not find URLs section for application '$app' in rsreportserver.config."
        }

        $wildcardNode = $urlsNode.URL | Where-Object { $_.UrlString -match '^https?://\+:' } | Select-Object -First 1
        if (-not $wildcardNode) {
            throw "Could not find default 'https://+:$Port' listener for application '$app'."
        }

        foreach ($oldNode in (Get-OldSanUrlNodes -ConfigXml $ConfigXml -Application $app)) {
            if ($oldNode.UrlString -match '^https?://([^:/]+):') {
                $removedHostnames.Add($Matches[1])
            }
            [void]$urlsNode.RemoveChild($oldNode)
        }

        $newNode = $ConfigXml.CreateElement('URL')

        $urlStringEl = $ConfigXml.CreateElement('UrlString')
        $urlStringEl.InnerText = "https://$($NewHostname):$($Port)"
        [void]$newNode.AppendChild($urlStringEl)

        $sidEl = $ConfigXml.CreateElement('AccountSid')
        $sidEl.InnerText = $wildcardNode.AccountSid
        [void]$newNode.AppendChild($sidEl)

        $nameEl = $ConfigXml.CreateElement('AccountName')
        $nameEl.InnerText = $wildcardNode.AccountName
        [void]$newNode.AppendChild($nameEl)

        [void]$urlsNode.AppendChild($newNode)
    }

    return ($removedHostnames | Select-Object -Unique)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (23/23 tests).

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1" "MISC-SCRIPTS/Config RS to use SAN-PBI.Tests.ps1"
git commit -m "feat: add config XML old-SAN detection and replacement"
```

---

### Task 6: System integration wrappers (netsh execution, backup, restart)

**Files:**
- Modify: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`
- Test: `MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`

**Interfaces:**
- Consumes: `$script:PbirsServiceName` (Task 1).
- Produces: `Invoke-NetshCommand([string[]]$Args)` → `[PSCustomObject]@{ ExitCode=[int]; Output=[string[]] }`.
- Produces: `Backup-ReportServerConfig([string]$ConfigPath)` → `[string]` path to the created backup file.
- Produces: `Restart-PbirsService()` → void; restarts `$script:PbirsServiceName` and waits (up to 60s) for it to report `Running`. Not unit tested — it acts on a real Windows service and would either no-op-fail or restart something unrelated on a dev machine; verified manually on the target server in Task 7.

- [ ] **Step 1: Add the failing tests**

`Invoke-NetshCommand` is tested against the real, read-only `netsh http show urlacl` (no admin rights required, safe on any Windows machine). `Backup-ReportServerConfig` is tested against a file in Pester's `$TestDrive`.

```powershell
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

        $backupPath | Should -Match [regex]::Escape($sourcePath) + '\.bak-\d{14}$'
        Test-Path -LiteralPath $backupPath | Should -BeTrue
        Get-Content -LiteralPath $backupPath -Raw | Should -Be (Get-Content -LiteralPath $sourcePath -Raw)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: FAIL — `Invoke-NetshCommand` and `Backup-ReportServerConfig` not recognized.

- [ ] **Step 3: Implement**

Add below `Update-ReportServerConfigXml`:

```powershell
function Invoke-NetshCommand {
    param([Parameter(Mandatory)][string[]]$Args)

    $output = & netsh.exe @Args 2>&1
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Backup-ReportServerConfig {
    param([Parameter(Mandatory)][string]$ConfigPath)

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backupPath = "$ConfigPath.bak-$timestamp"
    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    return $backupPath
}

function Restart-PbirsService {
    Restart-Service -Name $script:PbirsServiceName -Force
    $service = Get-Service -Name $script:PbirsServiceName
    $service.WaitForStatus('Running', (New-TimeSpan -Seconds 60))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (25/25 tests).

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1" "MISC-SCRIPTS/Config RS to use SAN-PBI.Tests.ps1"
git commit -m "feat: add netsh execution, config backup, and service restart wrappers"
```

---

### Task 7: Main orchestration and manual verification

**Files:**
- Modify: `MISC-SCRIPTS\Config RS to use SAN-PBI.ps1`

**Interfaces:**
- Consumes every function/constant produced in Tasks 1–6.
- Produces: `Invoke-Main([switch]$WhatIf)` → void; runs the full blocker-check → prompt → (preview | apply) flow described in the spec, and the bottom-of-file execution guard.

This task is not unit tested — it's the orchestration of already-tested pieces plus interactive `Read-Host` and real system state (service, cert store, live `rsreportserver.config`), which isn't meaningfully mockable end-to-end. It's verified manually: first on this dev machine (which correctly has no PBIRS installed, proving blocker checks fail closed), then via a checklist for the actual PBIRS server.

- [ ] **Step 1: Implement `Invoke-Main`**

Add at the end of the `.ps1`, after `Restart-PbirsService`:

```powershell
# ==============================
# Orchestration
# ==============================
function Invoke-Main {
    param([switch]$WhatIf)

    Write-Log 'Starting PBIRS SAN configuration.'

    if (-not (Test-IsAdministrator)) {
        Write-Log 'BLOCKED: This script must be run as Administrator.'
        throw 'This script must be run as Administrator.'
    }
    Write-Log 'CHECK PASSED: Running as Administrator.'

    $serviceInfo = Get-PbirsServiceInfo
    if (-not $serviceInfo.IsReady) {
        Write-Log "BLOCKED: PowerBI Report Server service or config file not found. ServiceFound=$($serviceInfo.ServiceFound) ConfigExists=$($serviceInfo.ConfigExists)"
        throw 'PowerBI Report Server is not installed on this machine (service or config file missing).'
    }
    Write-Log "CHECK PASSED: PowerBIReportServer service and config found at $($serviceInfo.ConfigPath)."

    [xml]$configXml = Get-Content -LiteralPath $serviceInfo.ConfigPath -Raw

    $port = Get-TlsPortFromConfig -ConfigXml $configXml
    if (-not $port) {
        Write-Log 'BLOCKED: No https://+:<port> wildcard listener found in rsreportserver.config. Bind a certificate to a port using Report Server Configuration Manager first.'
        throw 'No TLS port configured yet. Bind a certificate via Report Server Configuration Manager before running this script.'
    }
    Write-Log "CHECK PASSED: TLS port $port discovered from config."

    $urlInput = Read-Host 'Enter the full URL for the SAN (e.g. https://reports.contoso.com)'
    $parsedUri = $null
    if (-not [Uri]::TryCreate($urlInput, [UriKind]::Absolute, [ref]$parsedUri) -or $parsedUri.Scheme -ne 'https') {
        Write-Log "BLOCKED: '$urlInput' is not a valid https URL."
        throw "'$urlInput' is not a valid https URL."
    }
    $newHostname = $parsedUri.Host
    Write-Log "Target SAN hostname: $newHostname (port $port)."

    $sslCertOutput = (Invoke-NetshCommand -Args @('http', 'show', 'sslcert', "ipport=0.0.0.0:$port")).Output
    $certHash = Get-CertHashFromSslCertOutput -NetshOutput $sslCertOutput
    if (-not $certHash) {
        Write-Log "BLOCKED: No certificate bound to port $port (netsh http show sslcert returned nothing usable)."
        throw "No certificate is bound to port $port. Bind one via Report Server Configuration Manager first."
    }

    $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$certHash" -ErrorAction SilentlyContinue
    if (-not $certificate) {
        Write-Log "BLOCKED: Certificate with thumbprint $certHash not found in Cert:\LocalMachine\My."
        throw "Certificate $certHash bound to port $port was not found in the LocalMachine\My store."
    }

    $certCheck = Test-CertificateForSan -Certificate $certificate -Hostname $newHostname
    if (-not $certCheck.IsValid) {
        foreach ($failure in $certCheck.Failures) {
            Write-Log "BLOCKED: $failure"
        }
        throw "Certificate bound to port $port is not valid for SAN '$newHostname': $($certCheck.Failures -join ' ')"
    }
    Write-Log "CHECK PASSED: Certificate $certHash is signed, has a private key, and covers '$newHostname'."

    $urlAclOutput = (Invoke-NetshCommand -Args @('http', 'show', 'urlacl')).Output
    $addCommands = New-UrlAclCommandArgs -Action add -Hostname $newHostname -Port $port
    $conflicts = @($addCommands | Where-Object { Test-UrlAclConflict -NetshOutput $urlAclOutput -Url $_.Url } | ForEach-Object Url)
    if ($conflicts) {
        Write-Log "BLOCKED: urlacl reservation(s) already exist for: $($conflicts -join ', ')"
        throw "urlacl reservations already exist for: $($conflicts -join ', '). Resolve manually before re-running."
    }
    Write-Log 'CHECK PASSED: No existing urlacl conflicts for the new hostname.'

    $oldHostnames = @(
        (Get-OldSanUrlNodes -ConfigXml $configXml -Application 'ReportServerWebService') +
        (Get-OldSanUrlNodes -ConfigXml $configXml -Application 'ReportServerWebApp')
    ) | ForEach-Object {
        if ($_.UrlString -match '^https?://([^:/]+):') { $Matches[1] }
    } | Select-Object -Unique

    $deleteCommands = @()
    foreach ($oldHostname in $oldHostnames) {
        $deleteCommands += New-UrlAclCommandArgs -Action delete -Hostname $oldHostname -Port $port
    }

    if ($WhatIf) {
        Write-Log '--- WHATIF PREVIEW (no changes made) ---'
        Write-Log "Old SAN hostname(s) found: $(if ($oldHostnames) { $oldHostnames -join ', ' } else { 'none' })"
        Write-Log "New SAN URL to add: https://$($newHostname):$($port)"
        foreach ($cmd in $deleteCommands) { Write-Log "Would run: netsh $($cmd.Args -join ' ')" }
        foreach ($cmd in $addCommands) { Write-Log "Would run: netsh $($cmd.Args -join ' ')" }
        Write-Log "Would restart service: $script:PbirsServiceName"
        return
    }

    $backupPath = Backup-ReportServerConfig -ConfigPath $serviceInfo.ConfigPath
    Write-Log "Backed up config to $backupPath."

    $removedHostnames = Update-ReportServerConfigXml -ConfigXml $configXml -NewHostname $newHostname -Port $port
    $configXml.Save($serviceInfo.ConfigPath)
    Write-Log "Updated rsreportserver.config. Removed old SAN entries for: $(if ($removedHostnames) { $removedHostnames -join ', ' } else { 'none' })."

    foreach ($cmd in $deleteCommands) {
        Invoke-NetshCommand -Args $cmd.Args | Out-Null
        Write-Log "Deleted urlacl: $($cmd.Url)"
    }
    foreach ($cmd in $addCommands) {
        $result = Invoke-NetshCommand -Args $cmd.Args
        if ($result.ExitCode -ne 0) {
            Write-Log "FAILED to add urlacl $($cmd.Url): $($result.Output -join ' ')"
            throw "Failed to add urlacl $($cmd.Url). See $backupPath to restore the previous config if needed."
        }
        Write-Log "Added urlacl: $($cmd.Url)"
    }

    Restart-PbirsService
    Write-Log 'PowerBIReportServer service restarted successfully.'
    Write-Log 'SAN configuration complete.'
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -WhatIf:$WhatIf
}
```

- [ ] **Step 2: Confirm the full test suite still passes**

Run: `Invoke-Pester -Path "MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1" -Output Detailed`
Expected: PASS (25/25 tests) — Task 7 adds no new automated tests, this just confirms adding `Invoke-Main` and the execution guard didn't break dot-sourcing.

- [ ] **Step 3: Manual verification on this dev machine (proves blocker checks fail closed)**

This machine does not have Power BI Report Server installed, so running the script for real should stop at the service/config blocker check without prompting for a URL or touching anything.

Run:
```
powershell.exe -NoProfile -File "MISC-SCRIPTS\Config RS to use SAN-PBI.ps1"
```
Expected: The script prints `CHECK PASSED: Running as Administrator.` (if elevated) or throws immediately on the admin check (if not), then — once elevated — throws `PowerBI Report Server is not installed on this machine (service or config file missing).` It must NOT reach the `Read-Host` prompt. Confirm `MISC-SCRIPTS\SAN-Config-Log.txt` was created and contains the corresponding `BLOCKED:` line, then delete that log file (it's a local test artifact, not something to commit).

- [ ] **Step 4: Manual verification checklist for the actual PBIRS server (perform when deploying)**

Document this checklist in the commit for whoever runs it on the real server — not automatable from this dev machine since it requires a live PBIRS install, a real bound certificate, and admin rights on that box:

1. Copy the script to the PBIRS server.
2. Run elevated with `-WhatIf` first: `.\Config RS to use SAN-PBI.ps1 -WhatIf`, enter the desired SAN URL when prompted.
3. Confirm the printed preview correctly shows the existing old SAN hostname (if any), the new URL, the exact `netsh` delete/add commands, and that no file was modified (`rsreportserver.config` timestamp unchanged, no new `.bak-` file).
4. If the cert-SAN blocker fires, confirm it's correct by checking the bound cert's SAN list manually (`certlm.msc` → find the cert bound to the port → Details → Subject Alternative Name) before treating it as a script bug.
5. Re-run without `-WhatIf`. Confirm: a `.bak-<timestamp>` file was created, `rsreportserver.config` now shows only the wildcard and new SAN `<URL>` entries in both sections, `netsh http show urlacl` shows the 4 new reservations and none for the old hostname, and the Web Service/Web Portal URLs are reachable at the new hostname after the service restart.

- [ ] **Step 5: Commit**

```bash
git add "MISC-SCRIPTS/Config RS to use SAN-PBI.ps1"
git commit -m "feat: wire up PBIRS SAN config orchestration and execution guard"
```
