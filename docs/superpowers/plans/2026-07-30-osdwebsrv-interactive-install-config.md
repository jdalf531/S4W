# OSDWebSRV-MPN Interactive Install Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Install-OsdWebService.ps1` collects the MECM site server, MECM site code, and API key (auto-generating the key if omitted), and writes all four environment-specific `appsettings.json` values into the published app itself, eliminating the manual JSON-editing step documented today.

**Architecture:** A new standalone, unit-testable function `Set-OsdAppSetting` performs targeted regex substitution on known JSON key lines (preserving the file's `//` comments, which a full `ConvertFrom-Json`/`ConvertTo-Json` round-trip would strip). `Install-OsdWebService.ps1` dot-sources this function, moves publish-path/appsettings.json validation to the very start of the script (before any system changes), collects the three values (prompting for any left blank), calls `Set-OsdAppSetting` four times, and updates its closing summary banner to drop the now-obsolete manual-edit instructions.

**Tech Stack:** PowerShell 5.1/7, Pester (unit tests for the extracted function only — no IIS server is available for end-to-end testing of the rest of the script).

## Global Constraints

- New optional parameters on `Install-OsdWebService.ps1`: `-MecmSiteServer` (string), `-MecmSiteCode` (string), `-ApiKey` (string). All default to blank/auto-generate.
- `-LogStoragePath` is unchanged — already parameter-driven with a default of `C:\OSDLogs`; out of scope for this change.
- Validate that `-PublishPath` exists and contains an `appsettings.json` file **before any system changes** (before IIS feature installation, app pool, or website steps) — abort with a clear error otherwise.
- For each of `-MecmSiteServer` / `-MecmSiteCode` left blank at invocation, prompt via `Read-Host`, re-prompting on invalid input. Site code must match `^[A-Za-z0-9]{3}$`.
- If `-ApiKey` is blank, auto-generate via `[System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))` (same method already documented in the README) and print it once with a "record this now — it will not be shown again" warning.
- `appsettings.json` is updated via targeted regex substitution on the four known, unique key lines (`ApiKey`, `LogStorage.BasePath`, `Mecm.SiteServer`, `Mecm.SiteCode`) — **not** a `ConvertFrom-Json`/`ConvertTo-Json` round-trip, because that would strip the file's inline `//` comments.
- Values are JSON-escaped (backslash then double-quote, in that order) before substitution so a Windows path like `C:\OSDLogs` round-trips correctly.
- The substitution logic lives in a standalone function `Set-OsdAppSetting -Path -Key -Value` so it can be unit tested with Pester independent of the IIS-dependent install script, matching the existing Pester pattern for `S4W/Projects/MISC-SCRIPTS/Config RS to use SAN-PBI.ps1` (sibling `.Tests.ps1` file that dot-sources the implementation via `$PSScriptRoot`).
- The closing summary must no longer instruct the operator to hand-edit `appsettings.json`; it must still cover restarting the app pool and hitting `/health`, plus reprint the ApiKey once more.
- Out of scope: validating that the supplied MECM site server is reachable or that the site code matches a real MECM site; encrypting/protecting the ApiKey at rest beyond today's plaintext config file.

---

### Task 1: Extract `Set-OsdAppSetting` with Pester coverage

**Files:**
- Create: `S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.ps1`
- Test: `S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.Tests.ps1`

**Interfaces:**
- Produces: `Set-OsdAppSetting -Path <string> -Key <string> -Value <string>` — reads the file at `-Path`, replaces the value of the JSON property named `-Key` (matched via `"<Key>"\s*:\s*"..."`, first occurrence only) with the JSON-escaped `-Value`, writes the file back in place (no return value). Throws if `-Key` is not found in the file.

- [ ] **Step 1: Write the failing Pester tests**

Create `S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.Tests.ps1`:

```powershell
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

BeforeEach {
    $script:FixturePath = Join-Path $TestDrive 'appsettings.json'
    Set-Content -LiteralPath $script:FixturePath -Value $script:FixtureContent -NoNewline
}

Describe 'Set-OsdAppSetting' {
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester "S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.Tests.ps1" -Output Detailed`
Expected: FAIL — dot-sourcing `Set-OsdAppSetting.ps1` errors because the file does not exist yet (`Set-OsdAppSetting.ps1: The system cannot find the file specified` or similar).

- [ ] **Step 3: Write the minimal implementation**

Create `S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.ps1`:

```powershell
<#
.SYNOPSIS
    Replaces a single string value in a JSON config file via targeted regex
    substitution, preserving any `//` comments a full parse/re-serialize
    round-trip would strip.
#>
function Set-OsdAppSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $content = Get-Content -LiteralPath $Path -Raw

    # JSON-escape the value: backslashes first, then double quotes, so an
    # escape backslash inserted by the second replace is never itself
    # re-escaped by a later pass.
    $jsonEscaped = $Value -replace '\\', '\\' -replace '"', '\"'

    # [regex]::Replace treats '$' specially in the replacement string;
    # escape any literal '$' in the value so it passes through unchanged.
    $replacementValue = $jsonEscaped.Replace('$', '$$')

    $pattern     = '("' + [regex]::Escape($Key) + '"\s*:\s*)"(?:[^"\\]|\\.)*"'
    $replacement = '${1}"' + $replacementValue + '"'

    $updated = [regex]::Replace($content, $pattern, $replacement, 1)

    if ($updated -eq $content) {
        throw "Key '$Key' not found in '$Path'."
    }

    Set-Content -LiteralPath $Path -Value $updated -NoNewline
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester "S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.Tests.ps1" -Output Detailed`
Expected: PASS — all 6 `It` blocks green.

- [ ] **Step 5: Commit**

```bash
git add "S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.ps1" "S4W/Projects/OSDWebSRV-MPN/install/Set-OsdAppSetting.Tests.ps1"
git commit -m "feat(osdwebsrv): add Set-OsdAppSetting for regex-based appsettings.json updates"
```

---

### Task 2: Wire interactive collection + config writing into `Install-OsdWebService.ps1`

**Files:**
- Modify: `S4W/Projects/OSDWebSRV-MPN/install/Install-OsdWebService.ps1`

**Interfaces:**
- Consumes: `Set-OsdAppSetting -Path <string> -Key <string> -Value <string>` from Task 1 (dot-sourced from `Set-OsdAppSetting.ps1` in the same folder).
- Produces: three new script parameters (`$MecmSiteServer`, `$MecmSiteCode`, `$ApiKey`) and a resolved `$ApiKey` value available to the closing summary banner.

- [ ] **Step 1: Add the new parameters**

In the `param()` block (currently lines 66-82), add the three new parameters after `$UrlRewriteMsiPath`:

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $PublishPath,

    [string] $SiteName              = 'OsdWebService',
    [string] $AppPoolName           = 'OsdWebService',
    [int]    $HttpsPort             = 443,

    [Parameter(Mandatory)]
    [string] $CertificateThumbprint,

    [string]       $LogStoragePath     = 'C:\OSDLogs',
    [string]       $AppPoolIdentity    = '',
    [SecureString] $AppPoolPassword    = $null,
    [string]       $UrlRewriteMsiPath  = '',

    [string] $MecmSiteServer = '',
    [string] $MecmSiteCode   = '',
    [string] $ApiKey         = ''
)
```

- [ ] **Step 2: Dot-source `Set-OsdAppSetting` and add the new validate/collect/write section**

Immediately after the existing `Write-Step` helper function (directly below its closing `}`, currently around line 93, before the `# 1. IIS features` comment block), insert:

```powershell
# -----------------------------------------------------------------------
# Load Set-OsdAppSetting (regex-based appsettings.json value substitution)
# -----------------------------------------------------------------------
. (Join-Path $PSScriptRoot 'Set-OsdAppSetting.ps1')

# -----------------------------------------------------------------------
# 1. Validate publish folder, collect MECM/API config, write appsettings.json
#    (done first, before any system changes, so a bad input fails fast)
# -----------------------------------------------------------------------
Write-Step "Validating publish folder"

if (-not (Test-Path $PublishPath)) {
    throw "PublishPath '$PublishPath' not found.  Run 'dotnet publish' first."
}

$appSettingsPath = Join-Path $PublishPath 'appsettings.json'
if (-not (Test-Path $appSettingsPath)) {
    throw "appsettings.json not found in '$PublishPath'.  Run 'dotnet publish' first."
}

Write-Step "Collecting MECM configuration"

if (-not $MecmSiteServer) {
    do {
        $MecmSiteServer = Read-Host "Enter your MECM site server (hostname or FQDN)"
    } while ([string]::IsNullOrWhiteSpace($MecmSiteServer))
}

if (-not $MecmSiteCode) {
    do {
        $MecmSiteCode = Read-Host "Enter your MECM site code (3 characters)"
    } while ($MecmSiteCode -notmatch '^[A-Za-z0-9]{3}$')
}

if (-not $ApiKey) {
    $ApiKey = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    Write-Host "`nGenerated API key: $ApiKey" -ForegroundColor Yellow
    Write-Warning "Record this API key now - it will not be shown again until the closing summary. It is required to configure Submit-OSDLogs.ps1 / Get-DriverPackages.ps1 on WinPE clients."
}

Write-Step "Writing configuration into appsettings.json"

Set-OsdAppSetting -Path $appSettingsPath -Key 'ApiKey'      -Value $ApiKey
Set-OsdAppSetting -Path $appSettingsPath -Key 'BasePath'    -Value $LogStoragePath
Set-OsdAppSetting -Path $appSettingsPath -Key 'SiteServer'  -Value $MecmSiteServer
Set-OsdAppSetting -Path $appSettingsPath -Key 'SiteCode'    -Value $MecmSiteCode

Write-Host "appsettings.json updated."
```

- [ ] **Step 3: Renumber the existing section comments**

The five existing `# N. ...` section-header comments (`# 1. IIS features`, `# 2. Log storage folder`, `# 3. Application Pool`, `# 4. IIS Website`, `# 5. IIS permissions on the publish folder`) each shift up by one. Update them to `# 2.` through `# 6.` respectively, matching the new section 1 added in Step 2.

- [ ] **Step 4: Remove the now-redundant PublishPath check under the IIS Website section**

In the section that is now `# 4. IIS Website` (was `# 4. IIS Website` at line 216 originally), remove these lines that duplicate the validation now done in section 1:

```powershell
# Validate publish path
if (-not (Test-Path $PublishPath)) {
    throw "PublishPath '$PublishPath' not found.  Run 'dotnet publish' first."
}
```

The section should now start directly with the certificate lookup (`$cert = Get-ChildItem Cert:\LocalMachine\My | ...`).

- [ ] **Step 5: Update the closing summary banner**

Replace the current "Done" block (currently lines 279-299):

```powershell
Write-Host "`n" -NoNewline
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Edit appsettings.json in '$PublishPath' and set:"
Write-Host "       ApiKey           - a strong random string"
Write-Host "       LogStorage:BasePath - $LogStoragePath (already created)"
Write-Host "       Mecm:SiteServer  - your MECM site server FQDN"
Write-Host "       Mecm:SiteCode    - your three-character site code"
Write-Host "  2. Restart the application pool:"
Write-Host "       Restart-WebAppPool -Name $AppPoolName"
Write-Host "  3. Test the health endpoint:"
Write-Host "       Invoke-RestMethod https://localhost:$HttpsPort/health"
Write-Host ""
Write-Host "MECM WMI access note:"
Write-Host "  The identity '$identity' must be a member of the 'SMS Admins'"
$siteServerNote = if ($Env:COMPUTERNAME -eq 'MECM-SERVER-FQDN') { 'this server' } else { 'the MECM site server' }
Write-Host "  local security group on $siteServerNote."
```

with:

```powershell
Write-Host "`n" -NoNewline
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Restart the application pool:"
Write-Host "       Restart-WebAppPool -Name $AppPoolName"
Write-Host "  2. Test the health endpoint:"
Write-Host "       Invoke-RestMethod https://localhost:$HttpsPort/health"
Write-Host ""
Write-Host "API key (record this if you have not already):"
Write-Host "  $ApiKey"
Write-Host ""
Write-Host "MECM WMI access note:"
Write-Host "  The identity '$identity' must be a member of the 'SMS Admins'"
$siteServerNote = if ($Env:COMPUTERNAME -eq 'MECM-SERVER-FQDN') { 'this server' } else { 'the MECM site server' }
Write-Host "  local security group on $siteServerNote."
```

- [ ] **Step 6: Verify the script still parses cleanly**

No IIS server is available to run this script end-to-end, so the safety net here is a PowerShell parser check (a real syntax check, not a smoke test of behavior).

Run:

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    "S4W/Projects/OSDWebSRV-MPN/install/Install-OsdWebService.ps1", [ref]$null, [ref]$errors
) | Out-Null
$errors
```

Expected: no output (empty `$errors` array — no parse errors).

- [ ] **Step 7: Commit**

```bash
git add "S4W/Projects/OSDWebSRV-MPN/install/Install-OsdWebService.ps1"
git commit -m "feat(osdwebsrv): collect MECM/API config interactively and write it into appsettings.json"
```

---

### Task 3: Update README to drop the manual-edit step

**Files:**
- Modify: `S4W/Projects/OSDWebSRV-MPN/README.md:107-150`

**Interfaces:**
- None — documentation only.

- [ ] **Step 1: Replace the "Configuration (`appsettings.json`)" section**

Replace (currently lines 107-129):

```markdown
## Configuration (`appsettings.json`)

Edit `C:\inetpub\OsdWebService\appsettings.json` **before starting the service**:

```json
{
  "ApiKey": "REPLACE-WITH-A-STRONG-RANDOM-KEY",
  "LogStorage": {
    "BasePath": "C:\\OSDLogs"
  },
  "Mecm": {
    "SiteServer": "cm01.corp.contoso.com",
    "SiteCode":   "PS1"
  }
}
```

**Generate a strong API key:**
```powershell
[System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
```

---
```

with:

```markdown
## Configuration (`appsettings.json`)

`Install-OsdWebService.ps1` (below) writes `ApiKey`, `LogStorage:BasePath`,
`Mecm:SiteServer`, and `Mecm:SiteCode` into the published `appsettings.json`
for you — prompting for the MECM site server/site code if you don't pass
them as parameters, and auto-generating the API key if you don't supply
one. There is no manual JSON edit needed after the script completes.

If you ever need to generate an API key by hand (e.g. to rotate one later):
```powershell
[System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
```

---
```

- [ ] **Step 2: Update the "IIS installation" example command**

Replace (currently lines 133-150):

```markdown
Run as a local administrator on the IIS server:

```powershell
.\install\Install-OsdWebService.ps1 `
    -PublishPath           C:\inetpub\OsdWebService `
    -CertificateThumbprint 'AB12CD34EF56...' `
    -LogStoragePath        C:\OSDLogs `
    -AppPoolIdentity       'CORP\svc-osdweb' `
    -UrlRewriteMsiPath     '\\fileserver\software\IIS\rewrite_amd64_en-US.msi'
    # Script will prompt securely for the password
```

`-UrlRewriteMsiPath` is optional and only used if the URL Rewrite module
isn't already installed. The script never downloads it - point this at a
copy staged on an internal file share or software repository. If omitted
and the module is missing, the script warns and continues (the HTTP->HTTPS
redirect rule in `web.config` won't function until the module is installed
by some other means).
```

with:

```markdown
Run as a local administrator on the IIS server:

```powershell
.\install\Install-OsdWebService.ps1 `
    -PublishPath           C:\inetpub\OsdWebService `
    -CertificateThumbprint 'AB12CD34EF56...' `
    -LogStoragePath        C:\OSDLogs `
    -AppPoolIdentity       'CORP\svc-osdweb' `
    -UrlRewriteMsiPath     '\\fileserver\software\IIS\rewrite_amd64_en-US.msi' `
    -MecmSiteServer        cm01.corp.contoso.com `
    -MecmSiteCode          PS1
    # Script will prompt securely for the app pool password.
    # Omit -MecmSiteServer/-MecmSiteCode to be prompted for them instead.
    # Omit -ApiKey to have one generated and printed for you.
```

`-UrlRewriteMsiPath` is optional and only used if the URL Rewrite module
isn't already installed. The script never downloads it - point this at a
copy staged on an internal file share or software repository. If omitted
and the module is missing, the script warns and continues (the HTTP->HTTPS
redirect rule in `web.config` won't function until the module is installed
by some other means).

`-MecmSiteServer`, `-MecmSiteCode`, and `-ApiKey` are all optional: leave
any of them off the command line and the script will prompt for it (or, for
`-ApiKey`, generate one and print it once).
```

- [ ] **Step 3: Commit**

```bash
git add "S4W/Projects/OSDWebSRV-MPN/README.md"
git commit -m "docs(osdwebsrv): drop manual appsettings.json edit step from install instructions"
```

---

## Self-Review

**Spec coverage:**
- New/changed parameters (`-MecmSiteServer`, `-MecmSiteCode`, `-ApiKey`) → Task 2, Step 1.
- Validate + collect before any system changes → Task 2, Step 2.
- Auto-generate ApiKey with "record this now" warning → Task 2, Step 2.
- Write values via targeted regex substitution, not full JSON round-trip → Task 1 (`Set-OsdAppSetting`).
- JSON-escaping of values (backslash/quote, path round-trip) → Task 1 implementation + test.
- Extracted, independently Pester-testable function matching the `Config RS to use SAN-PBI.ps1` pattern → Task 1.
- Updated final summary (remove manual-edit instructions, keep restart/health-check, reprint ApiKey) → Task 2, Step 5.
- Testing via Pester fixture covering all four keys, comment/key preservation, and backslash round-trip → Task 1, Step 1.
- Out-of-scope items (MECM reachability validation, ApiKey encryption at rest, LogStoragePath changes) → untouched by this plan; no task implements them.

**Placeholder scan:** No TBD/TODO markers; every step has literal code or exact instructions.

**Type consistency:** `Set-OsdAppSetting -Path -Key -Value` signature is identical everywhere it's declared (Task 1) and called (Task 2, Step 2).
