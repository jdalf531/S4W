# RSAT Admin-Tools Install Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small folder (`RSAT-Install/`) that MECM can use as package source to install a fixed set of 9 admin capabilities (8 RSAT tools + OpenSSH client) on Windows 11, in both an OSD task-sequence step (WinPE / offline image) and a direct collection deployment (full online OS).

**Architecture:** Two independent Windows PowerShell 5.1 scripts in `Projects/RSAT/` plus a shared `RsatCapabilities.psd1` data file. `Build-RsatPackage.ps1` (run manually by an admin) mounts each archived source ISO read-only, verifies all 9 required cabs are present, copies them per OS build into `RSAT-Install/LanguagesAndOptionalFeatures/<build>/`, and drops in `Install-RSAT.ps1` + `RsatCapabilities.psd1` + `manifest.json`. `Install-RSAT.ps1` (ships inside `RSAT-Install/`) detects WinPE-vs-online, resolves the target build, and installs the 9 capabilities from the matching build subfolder. Pure decision/parsing logic is factored into small named functions tested with Pester; real DISM / ISO-mount / offline-hive interaction lives in each script's `Invoke-Main` and is verified manually.

**Tech Stack:** Windows PowerShell 5.1, Pester v5 (5.7.1 installed), DISM PowerShell module (`Get-WindowsCapability` / `Add-WindowsCapability`), `Mount-DiskImage` / `Dismount-DiskImage`, `Import-PowerShellDataFile`.

**Spec:** `docs/superpowers/specs/2026-08-18-rsat-install-package-design.md`

> **Post-implementation amendment (2026-08-31):** added a `BuildSourceMap`
> alias table in `RsatCapabilities.psd1` (`22631` → `22621`, `26200` →
> `26100`) — Microsoft ships one LOF ISO per release pair (22H2+23H2,
> 24H2+25H2). Added `Get-RsatBuildSourceMap` to `Install-RSAT.ps1`, a third
> parameter (`-BuildSourceMap`) on `Resolve-RsatSourceFolder` (exact
> `<build>` folder still wins over an alias), and covering tests.
>
> **Post-implementation amendment 2 (2026-08-31):** a third LOF ISO
> (`mul_..._version_26h1_..._dvd_....iso`, Windows 11 26H1, build **28000**,
> a new servicing branch, filename carries no build number) was added to
> `media-archive/`.
> Task 8's `Get-IsoBuildNumber` (filename parser) is **replaced** by
> `Get-BuildFromPackageManifest` (pure: reads `10.0.<build>.<rev>` from a
> manifest string) + `Get-CabPackageBuild` (expands `update.mum` from a cab
> and calls the former). `Build-RsatPackage.ps1`'s `Invoke-Main` now reads
> the build from `$cabPaths[0]` *after* mounting and verifying the cabs,
> instead of from the ISO filename before mounting. Build 28000 gets its own
> `28000\` source folder — no alias. Wherever the tasks below say
> "Get-IsoBuildNumber" or "build number from the ISO filename", read
> "Get-CabPackageBuild / build from the cab package manifest".
>
> **Post-implementation amendment 3 (2026-09-01):** first real MECM
> deployment (25H2 / build 26200) failed every capability with DISM
> `0x800f081f`. **Root cause was a builder bug, not the alias** — the
> builder copied only the `~amd64~~` FeaturePackage cab per capability and
> **omitted the `LanguagesAndOptionalFeatures\metadata\` folder entirely**
> (the FoD Component Database DISM uses to resolve a capability name → its
> packages), and the CompDB shows 7 of the 9 capabilities also need a
> `~wow64~~` SatellitePackage cab. Fix in `Build-RsatPackage.ps1`:
> `Get-RsatCabFileName` gains an `-Architecture` param; `Find-MissingCabFileName`
> → `Find-MissingFeatureCab` (checks only the required `~amd64~~` cab);
> `Get-RsatCabToCopy` now returns `~amd64~~` + `~wow64~~`-where-present with
> ISO casing preserved; `Invoke-Main` copies the `metadata\` folder into
> each `<build>\` and hard-fails if the ISO lacks it. The `<build>\` folder
> now mirrors the ISO's LOF layout (~16 cabs + `metadata\`, ~36 MB). The
> amendment-1 `BuildSourceMap` aliases stand (Microsoft-documented; the
> CompDB has no version lock). Wherever tasks below say "copy the 9 cabs" or
> "all 9 cabs present", read the above.

## Global Constraints

- **Target capabilities — exactly these 9, both builds, language-neutral cabs only** (capability name ↔ cab stem):
  - `Rsat.ServerManager.Tools` ↔ `Microsoft-Windows-ServerManager-Tools-FoD-Package`
  - `Rsat.FileServices.Tools` ↔ `Microsoft-Windows-FileServices-Tools-FoD-Package`
  - `Rsat.ActiveDirectory.DS-LDS.Tools` ↔ `Microsoft-Windows-ActiveDirectory-DS-LDS-Tools-FoD-Package`
  - `Rsat.GroupPolicy.Management.Tools` ↔ `Microsoft-Windows-GroupPolicy-Management-Tools-FoD-Package`
  - `Rsat.Dns.Tools` ↔ `Microsoft-Windows-DNS-Tools-FoD-Package`
  - `Rsat.DHCP.Tools` ↔ `Microsoft-Windows-DHCP-Tools-FoD-Package`
  - `Rsat.FailoverCluster.Management.Tools` ↔ `Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package` (note: uppercase `FOD`)
  - `Rsat.BitLocker.Recovery.Tools` ↔ `Microsoft-Windows-BitLocker-Recovery-Tools-FoD-Package`
  - `OpenSSH.Client` ↔ `OpenSSH-Client-Package`
- **Language-neutral cab filename pattern:** `<CabStem>~31bf3856ad364e35~amd64~~.cab`. Cab-name matching is **case-insensitive** (`FoD` vs `FOD`).
- **Supported OS builds:** one `<build>\` folder per LOF ISO in `media-archive\`. Currently `22621` (Win11 22H2), `26100` (Win11 24H2), `28000` (Win11 26H1) from real ISOs; `BuildSourceMap` aliases `22631` (23H2) → `22621` and `26200` (25H2) → `26100` because Microsoft ships one LOF ISO per release pair. An exact `<build>\` folder wins over an alias; a build with neither fails fast (installer exit `2`) with a log line naming the LOF ISO to obtain. Each `<build>\` folder holds ~16 cabs (`~amd64~~` + `~wow64~~`) plus the ISO's `metadata\` folder — see amendment 3.
- **Install order:** `Rsat.ServerManager.Tools`, then `Rsat.FileServices.Tools`, then `Rsat.ActiveDirectory.DS-LDS.Tools`, then the remaining 6 in any order — so cross-capability dependencies (`BitLocker→AD`, `AD→ServerManager`, `FileServices→ServerManager`, `FailoverCluster→FileServices`) resolve even if DISM's own resolution misbehaves against a source folder.
- **`OpenSSH.Client` is pre-installed on build 26100** — the installer treats `State = Installed` as success, never re-installs.
- **`Install-RSAT.ps1` exit codes:** `0` all installed/already present; `3010` installed + reboot required; `1` one or more failures (a capability the target OS does not offer counts as a failure); `2` no matching `<build>` source subfolder; `3` not elevated. Precedence when computing the code: not-elevated → `3`; else no-source-folder → `2`; else failures → `1`; else reboot → `3010`; else `0`.
- **Script conventions** (match `Projects/MISC-SCRIPTS/Config RS to use SAN-PBI.ps1`): top-level `<# .SYNOPSIS … .NOTES Modified: … #>` comment, `[CmdletBinding()]` + `param()`, approved PowerShell verbs, pure logic in named functions, an `if ($MyInvocation.InvocationName -ne '.') { Invoke-Main … }` guard at the bottom so dot-sourcing in tests never runs the body, Pester v5 `Describe`/`It` tests that dot-source the script under test in `BeforeAll`.
- **Neither `.Tests.ps1` file** mounts a real ISO, loads a real registry hive, or calls a real DISM cmdlet (`Get-WindowsCapability` / `Add-WindowsCapability` / `Mount-DiskImage`). Those paths are verified manually (Task 11 + the post-plan manual gate).
- **No task runs `Add-WindowsCapability` for real automatically.** The only real DISM call in this plan is a `-WhatIf` dry run (Task 11, Step 4), which installs nothing.
- **Run all Pester from the `S4W` repo root** with: `Invoke-Pester -Path "Projects\RSAT\<file>.Tests.ps1" -Output Detailed`.

## File Structure

- `Projects/RSAT/.gitignore` (new) — `*.iso` (6–7 GB each) and the generated `RSAT-Install/` output.
- `Projects/RSAT/media-archive/` (new) — the two original ISOs move here; read-only source for the builder. Git-ignored except `README.md`.
- `Projects/RSAT/media-archive/README.md` (new) — what the ISOs are, their build numbers.
- `Projects/RSAT/RsatCapabilities.psd1` (new) — the 9-row capability table (`@{ Capabilities = @( @{ CapabilityName=…; CabStem=… } … ) }`). Single source of truth; shipped inside `RSAT-Install/` too.
- `Projects/RSAT/RsatCapabilities.Tests.ps1` (new) — structural validation of the `.psd1`.
- `Projects/RSAT/Install-RSAT.ps1` (new) — the deployed installer. Ships inside `RSAT-Install/`.
- `Projects/RSAT/Install-RSAT.Tests.ps1` (new) — Pester tests for the installer's pure logic.
- `Projects/RSAT/Build-RsatPackage.ps1` (new) — run manually by an admin; assembles `RSAT-Install/`.
- `Projects/RSAT/Build-RsatPackage.Tests.ps1` (new) — Pester tests for the builder's pure logic.
- `Projects/RSAT/RSAT-Install/` (generated by the builder, git-ignored) — not created by any task directly.

---

### Task 1: Scaffolding — .gitignore, archive the ISOs, capability data file

**Files:**
- Create: `Projects/RSAT/.gitignore`
- Create: `Projects/RSAT/media-archive/README.md`
- Move: `Projects/RSAT/*.iso` → `Projects/RSAT/media-archive/`
- Create: `Projects/RSAT/RsatCapabilities.psd1`
- Create: `Projects/RSAT/RsatCapabilities.Tests.ps1`

**Interfaces:**
- Produces: `RsatCapabilities.psd1` loadable via `Import-PowerShellDataFile`, exposing `.Capabilities` — an array of 9 hashtables each with string keys `CapabilityName` and `CabStem`, authored in install-priority order (ServerManager, FileServices, ActiveDirectory, then the rest).

- [ ] **Step 1: Create the .gitignore**

Save as `Projects/RSAT/.gitignore`:

```
*.iso
RSAT-Install/
```

- [ ] **Step 2: Move the original ISOs into media-archive/**

From the `S4W` repo root:

```powershell
New-Item -ItemType Directory -Path "Projects\RSAT\media-archive" -Force
Move-Item "Projects\RSAT\*.iso" "Projects\RSAT\media-archive\"
Get-ChildItem "Projects\RSAT\media-archive"
```

Expected: both `.iso` files now listed under `media-archive\`, none left in `Projects\RSAT\`.

- [ ] **Step 3: Create media-archive/README.md**

Save as `Projects/RSAT/media-archive/README.md`:

```markdown
# Archived source media

Original, unmodified Microsoft "Client LOF Packages OEM" ISOs — the Features
on Demand source content for the RSAT admin-tools package. Kept as the
historical / source record.

| File | Windows build | Release |
|------|---------------|---------|
| `22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 22621 | Windows 11 22H2 |
| `26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 26100 | Windows 11 24H2 |

`Build-RsatPackage.ps1` (in the parent folder) reads every `*.iso` here by
default, mounts each read-only, and extracts only the 9 cabs listed in
`RsatCapabilities.psd1`. The ISOs are git-ignored (`*.iso`) due to size
(~6–7 GB each).
```

- [ ] **Step 4: Create RsatCapabilities.psd1**

Save as `Projects/RSAT/RsatCapabilities.psd1`:

```powershell
@{
    # The complete, fixed set of capabilities the RSAT admin-tools package
    # installs. Authored in install-priority order: ServerManager, then
    # FileServices, then ActiveDirectory-DS-LDS (dependency roots), then the
    # rest. Single source of truth — Build-RsatPackage.ps1 uses CabStem,
    # Install-RSAT.ps1 uses CapabilityName. Edit here only.
    Capabilities = @(
        @{ CapabilityName = 'Rsat.ServerManager.Tools';              CabStem = 'Microsoft-Windows-ServerManager-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.FileServices.Tools';               CabStem = 'Microsoft-Windows-FileServices-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.ActiveDirectory.DS-LDS.Tools';     CabStem = 'Microsoft-Windows-ActiveDirectory-DS-LDS-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.GroupPolicy.Management.Tools';     CabStem = 'Microsoft-Windows-GroupPolicy-Management-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.Dns.Tools';                        CabStem = 'Microsoft-Windows-DNS-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.DHCP.Tools';                       CabStem = 'Microsoft-Windows-DHCP-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.FailoverCluster.Management.Tools'; CabStem = 'Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package' }
        @{ CapabilityName = 'Rsat.BitLocker.Recovery.Tools';         CabStem = 'Microsoft-Windows-BitLocker-Recovery-Tools-FoD-Package' }
        @{ CapabilityName = 'OpenSSH.Client';                        CabStem = 'OpenSSH-Client-Package' }
    )
}
```

- [ ] **Step 5: Write the failing test**

Save as `Projects/RSAT/RsatCapabilities.Tests.ps1`:

```powershell
BeforeAll {
    $script:DataFilePath = "$PSScriptRoot\RsatCapabilities.psd1"
    $script:Data = Import-PowerShellDataFile -LiteralPath $script:DataFilePath
}

Describe 'RsatCapabilities.psd1' {
    It 'loads as a PowerShell data file' {
        $script:Data | Should -Not -BeNullOrEmpty
        $script:Data.Capabilities | Should -Not -BeNullOrEmpty
    }

    It 'has exactly 9 capability entries' {
        $script:Data.Capabilities.Count | Should -Be 9
    }

    It 'gives every entry a non-empty CapabilityName and CabStem' {
        foreach ($entry in $script:Data.Capabilities) {
            $entry.CapabilityName | Should -Not -BeNullOrEmpty
            $entry.CabStem        | Should -Not -BeNullOrEmpty
        }
    }

    It 'lists the three dependency-root capabilities first, in order' {
        $names = @($script:Data.Capabilities.CapabilityName)
        $names[0] | Should -Be 'Rsat.ServerManager.Tools'
        $names[1] | Should -Be 'Rsat.FileServices.Tools'
        $names[2] | Should -Be 'Rsat.ActiveDirectory.DS-LDS.Tools'
    }

    It 'includes the non-RSAT and BitLocker capabilities' {
        $names = @($script:Data.Capabilities.CapabilityName)
        $names | Should -Contain 'OpenSSH.Client'
        $names | Should -Contain 'Rsat.BitLocker.Recovery.Tools'
    }
}
```

- [ ] **Step 6: Run the test**

Run: `Invoke-Pester -Path "Projects\RSAT\RsatCapabilities.Tests.ps1" -Output Detailed`
Expected: PASS (5/5).

- [ ] **Step 7: Verify the gitignore scopes correctly**

Run: `git status --porcelain -- Projects/RSAT` (from the `S4W` repo root)
Expected: the two `.iso` files under `media-archive/` are **not** listed; `.gitignore`, `media-archive/README.md`, `RsatCapabilities.psd1`, and `RsatCapabilities.Tests.ps1` **are** listed as untracked (`??`).

- [ ] **Step 8: Commit**

```bash
git add "Projects/RSAT/.gitignore" "Projects/RSAT/media-archive/README.md" "Projects/RSAT/RsatCapabilities.psd1" "Projects/RSAT/RsatCapabilities.Tests.ps1"
git commit -m "Add RSAT package scaffolding: gitignore, media archive, capability table"
```

---

### Task 2: Install-RSAT.ps1 — skeleton, Get-RsatCapabilityTable, Resolve-RsatSourceFolder

**Files:**
- Create: `Projects/RSAT/Install-RSAT.ps1`
- Create: `Projects/RSAT/Install-RSAT.Tests.ps1`

**Interfaces:**
- Consumes: `RsatCapabilities.psd1` (Task 1).
- Produces:
  - `Get-RsatCapabilityTable [-DataFilePath <string>]` → `[object[]]` of the 9 capability hashtables from the `.psd1` next to the script. Throws if the file is missing or has no `Capabilities`.
  - `Resolve-RsatSourceFolder -PackageRoot <string> -BuildNumber <int>` → `[string]` full path to `<PackageRoot>\<BuildNumber>` if that directory exists, else `$null`.

- [ ] **Step 1: Create the Install-RSAT.ps1 skeleton**

Save as `Projects/RSAT/Install-RSAT.ps1`:

```powershell
<#
.SYNOPSIS
    Installs the fixed set of RSAT (Remote Server Administration Tools),
    BitLocker Drive Encryption Administration Utilities, and OpenSSH client
    capabilities from the LanguagesAndOptionalFeatures folder shipped
    alongside this script.
.DESCRIPTION
    Works both as an MECM OSD Task Sequence step (running in WinPE against
    the offline OS image) and as a direct MECM collection deployment
    (running in the full OS, online). Detects which context it is in and
    adapts automatically. Always logs to C:\Windows\Temp\RSAT-Install\;
    prints a readable summary only when run interactively outside a task
    sequence. The exact capability list lives in RsatCapabilities.psd1.
.NOTES
    Modified: 2026-08-31
#>

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$script:LogFile   = $null
$script:QuietMode = $false

function Get-RsatCapabilityTable {
    param(
        [string]$DataFilePath = (Join-Path $PSScriptRoot 'RsatCapabilities.psd1')
    )

    if (-not (Test-Path -LiteralPath $DataFilePath -PathType Leaf)) {
        throw "RSAT capability data file not found: $DataFilePath"
    }

    $data = Import-PowerShellDataFile -LiteralPath $DataFilePath
    if (-not $data.Capabilities -or @($data.Capabilities).Count -eq 0) {
        throw "RSAT capability data file '$DataFilePath' has no Capabilities entries."
    }

    return @($data.Capabilities)
}

function Resolve-RsatSourceFolder {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][int]$BuildNumber
    )

    $candidate = Join-Path $PackageRoot $BuildNumber
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        return $candidate
    }

    return $null
}
```

- [ ] **Step 2: Write the failing tests**

Save as `Projects/RSAT/Install-RSAT.Tests.ps1`:

```powershell
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
```

- [ ] **Step 3: Run the tests**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: PASS (5/5). (Both functions already exist in the skeleton — the point of this step is to confirm the dot-source works and the guard-free skeleton has no side effects.)

- [ ] **Step 4: Commit**

```bash
git add "Projects/RSAT/Install-RSAT.ps1" "Projects/RSAT/Install-RSAT.Tests.ps1"
git commit -m "Add Install-RSAT.ps1 skeleton with capability-table and source-folder resolution"
```

---

### Task 3: Install-RSAT.ps1 — Select-CapabilitiesToInstall and Get-CapabilityInstallOrder

**Files:**
- Modify: `Projects/RSAT/Install-RSAT.ps1`
- Modify: `Projects/RSAT/Install-RSAT.Tests.ps1`

**Interfaces:**
- Consumes: capability hashtables from `Get-RsatCapabilityTable` (each has `.CapabilityName`); `Get-WindowsCapability`-shaped objects (each has `.Name` like `Rsat.Dns.Tools~~~~0.0.1.0` and `.State`).
- Produces:
  - `Select-CapabilitiesToInstall -TargetCapability <object[]> -AvailableCapability <object[]>` → `[object[]]` of `[PSCustomObject]` with `.CapabilityName` (string, from the target), `.FullName` (string, the full versioned `.Name` of the matching available capability, or `$null`), and `.Action` (`'Install'` | `'AlreadyInstalled'` | `'NotOffered'`). One output object per target, in target order. `AvailableCapability` may be empty. Name matching is the target name vs. the available `.Name` truncated at the first `~`, case-insensitive.
  - `Get-CapabilityInstallOrder -Capability <object[]>` → `[object[]]` — the same objects, stably reordered so any whose `.CapabilityName` is `Rsat.ServerManager.Tools`, `Rsat.FileServices.Tools`, or `Rsat.ActiveDirectory.DS-LDS.Tools` come first in that order, then all others in their original relative order.

- [ ] **Step 1: Write the failing tests**

Add to `Projects/RSAT/Install-RSAT.Tests.ps1`:

```powershell
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
            # Rsat.ServerManager.Tools intentionally absent from the OS list
        )

        $result = Select-CapabilitiesToInstall -TargetCapability $script:Targets -AvailableCapability $available

        $result.Count | Should -Be 4
        ($result | Where-Object CapabilityName -eq 'Rsat.Dns.Tools').Action          | Should -Be 'Install'
        ($result | Where-Object CapabilityName -eq 'Rsat.Dns.Tools').FullName        | Should -Be 'Rsat.Dns.Tools~~~~0.0.1.0'
        ($result | Where-Object CapabilityName -eq 'Rsat.DHCP.Tools').Action         | Should -Be 'AlreadyInstalled'
        ($result | Where-Object CapabilityName -eq 'OpenSSH.Client').Action          | Should -Be 'Install'
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
        $input = @(
            [PSCustomObject]@{ CapabilityName = 'Rsat.Dns.Tools' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.ActiveDirectory.DS-LDS.Tools' }
            [PSCustomObject]@{ CapabilityName = 'OpenSSH.Client' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.ServerManager.Tools' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.FileServices.Tools' }
            [PSCustomObject]@{ CapabilityName = 'Rsat.DHCP.Tools' }
        )

        $ordered = @(Get-CapabilityInstallOrder -Capability $input | ForEach-Object CapabilityName)

        $ordered[0] | Should -Be 'Rsat.ServerManager.Tools'
        $ordered[1] | Should -Be 'Rsat.FileServices.Tools'
        $ordered[2] | Should -Be 'Rsat.ActiveDirectory.DS-LDS.Tools'
        $ordered[3] | Should -Be 'Rsat.Dns.Tools'
        $ordered[4] | Should -Be 'OpenSSH.Client'
        $ordered[5] | Should -Be 'Rsat.DHCP.Tools'
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: FAIL — `Select-CapabilitiesToInstall` and `Get-CapabilityInstallOrder` are not recognized.

- [ ] **Step 3: Implement both functions**

Add to `Projects/RSAT/Install-RSAT.ps1`, after `Resolve-RsatSourceFolder`:

```powershell
function Select-CapabilitiesToInstall {
    param(
        [Parameter(Mandatory)][object[]]$TargetCapability,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AvailableCapability
    )

    $results = foreach ($target in $TargetCapability) {
        $match = $AvailableCapability |
            Where-Object { (($_.Name -split '~', 2)[0]) -ieq $target.CapabilityName } |
            Select-Object -First 1

        if (-not $match) {
            [PSCustomObject]@{ CapabilityName = $target.CapabilityName; FullName = $null; Action = 'NotOffered' }
        }
        elseif ($match.State -eq 'Installed') {
            [PSCustomObject]@{ CapabilityName = $target.CapabilityName; FullName = $match.Name; Action = 'AlreadyInstalled' }
        }
        else {
            [PSCustomObject]@{ CapabilityName = $target.CapabilityName; FullName = $match.Name; Action = 'Install' }
        }
    }

    return @($results)
}

function Get-CapabilityInstallOrder {
    param(
        [Parameter(Mandatory)][object[]]$Capability
    )

    $priority = @(
        'Rsat.ServerManager.Tools',
        'Rsat.FileServices.Tools',
        'Rsat.ActiveDirectory.DS-LDS.Tools'
    )

    $decorated = for ($i = 0; $i -lt $Capability.Count; $i++) {
        $rank = $priority.IndexOf([string]$Capability[$i].CapabilityName)
        if ($rank -lt 0) { $rank = [int]::MaxValue }
        [PSCustomObject]@{ Item = $Capability[$i]; Rank = $rank; Original = $i }
    }

    return @($decorated | Sort-Object Rank, Original | ForEach-Object { $_.Item })
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: PASS (9/9).

- [ ] **Step 5: Commit**

```bash
git add "Projects/RSAT/Install-RSAT.ps1" "Projects/RSAT/Install-RSAT.Tests.ps1"
git commit -m "Add capability selection and install-ordering to Install-RSAT.ps1"
```

---

### Task 4: Install-RSAT.ps1 — Test-RunningInWinPE and Get-InstallRunContext

**Files:**
- Modify: `Projects/RSAT/Install-RSAT.ps1`
- Modify: `Projects/RSAT/Install-RSAT.Tests.ps1`

**Interfaces:**
- Produces:
  - `Test-RunningInWinPE` → `[bool]` — true iff `HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT` exists.
  - `Get-InstallRunContext -IsTaskSequence <bool> -IsInteractive <bool>` → `[PSCustomObject]` with `.IsTaskSequence`, `.IsInteractive`, `.Quiet` (all `[bool]`). `Quiet` is `$true` when `IsTaskSequence` is `$true` OR `IsInteractive` is `$false`; `$false` only when interactive and not in a task sequence.

- [ ] **Step 1: Write the failing tests**

Add to `Projects/RSAT/Install-RSAT.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: FAIL — `Test-RunningInWinPE` and `Get-InstallRunContext` are not recognized.

- [ ] **Step 3: Implement both functions**

Add to `Projects/RSAT/Install-RSAT.ps1`, after `Get-CapabilityInstallOrder`:

```powershell
function Test-RunningInWinPE {
    return [bool](Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')
}

function Get-InstallRunContext {
    param(
        [Parameter(Mandatory)][bool]$IsTaskSequence,
        [Parameter(Mandatory)][bool]$IsInteractive
    )

    $quiet = $IsTaskSequence -or (-not $IsInteractive)

    return [PSCustomObject]@{
        IsTaskSequence = $IsTaskSequence
        IsInteractive  = $IsInteractive
        Quiet          = $quiet
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: PASS (13/13).

- [ ] **Step 5: Commit**

```bash
git add "Projects/RSAT/Install-RSAT.ps1" "Projects/RSAT/Install-RSAT.Tests.ps1"
git commit -m "Add WinPE detection and run-context logic to Install-RSAT.ps1"
```

---

### Task 5: Install-RSAT.ps1 — Get-ExitCodeForResult

**Files:**
- Modify: `Projects/RSAT/Install-RSAT.ps1`
- Modify: `Projects/RSAT/Install-RSAT.Tests.ps1`

**Interfaces:**
- Produces: `Get-ExitCodeForResult -IsElevated <bool> -SourceFolderFound <bool> -FailedCount <int> -RebootRequired <bool>` → `[int]`. Precedence: not elevated → `3`; else no source folder → `2`; else `FailedCount > 0` → `1`; else reboot required → `3010`; else `0`.

- [ ] **Step 1: Write the failing test**

Add to `Projects/RSAT/Install-RSAT.Tests.ps1`:

```powershell
Describe 'Get-ExitCodeForResult' {
    It 'returns 3 when not elevated, regardless of other inputs' {
        Get-ExitCodeForResult -IsElevated $false -SourceFolderFound $true -FailedCount 5 -RebootRequired $true | Should -Be 3
    }

    It 'returns 2 when elevated but no matching source folder' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $false -FailedCount 0 -RebootRequired $false | Should -Be 2
    }

    It 'returns 1 when one or more capabilities failed' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount 1 -RebootRequired $false | Should -Be 1
    }

    It 'returns 3010 when everything succeeded but a reboot is needed' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount 0 -RebootRequired $true | Should -Be 3010
    }

    It 'returns 0 when everything succeeded and no reboot is needed' {
        Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount 0 -RebootRequired $false | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: FAIL — `Get-ExitCodeForResult` is not recognized.

- [ ] **Step 3: Implement Get-ExitCodeForResult**

Add to `Projects/RSAT/Install-RSAT.ps1`, after `Get-InstallRunContext`:

```powershell
function Get-ExitCodeForResult {
    param(
        [Parameter(Mandatory)][bool]$IsElevated,
        [Parameter(Mandatory)][bool]$SourceFolderFound,
        [Parameter(Mandatory)][int]$FailedCount,
        [Parameter(Mandatory)][bool]$RebootRequired
    )

    if (-not $IsElevated)        { return 3 }
    if (-not $SourceFolderFound) { return 2 }
    if ($FailedCount -gt 0)      { return 1 }
    if ($RebootRequired)         { return 3010 }
    return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: PASS (18/18).

- [ ] **Step 5: Commit**

```bash
git add "Projects/RSAT/Install-RSAT.ps1" "Projects/RSAT/Install-RSAT.Tests.ps1"
git commit -m "Add Get-ExitCodeForResult to Install-RSAT.ps1"
```

---

### Task 6: Install-RSAT.ps1 — Write-Log, Test-IsAdministrator, Get-TsEnvironmentObject, Get-OSBuildNumberOnline

**Files:**
- Modify: `Projects/RSAT/Install-RSAT.ps1`
- Modify: `Projects/RSAT/Install-RSAT.Tests.ps1`

**Interfaces:**
- Produces:
  - `Write-Log -Message <string> [-LogFile <string>]` — appends `yyyy-MM-dd HH:mm:ss - <Message>` to `$LogFile` (default `$script:LogFile`); also `Write-Host`s the line unless `$script:QuietMode` is `$true`.
  - `Test-IsAdministrator` → `[bool]` — true if the current identity is in the built-in Administrators role (SYSTEM qualifies).
  - `Get-TsEnvironmentObject` → the `Microsoft.SMS.TSEnvironment` COM object, or `$null` if it cannot be created (i.e. not in a task sequence).
  - `Get-OSBuildNumberOnline` → `[int]` — the running OS `CurrentBuildNumber` from `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`.

- [ ] **Step 1: Write the failing tests**

Add to `Projects/RSAT/Install-RSAT.Tests.ps1`:

```powershell
Describe 'Write-Log' {
    It 'appends a timestamped line to the given log file' {
        $tempLog = Join-Path $TestDrive 'test.log'
        Write-Log -Message 'hello world' -LogFile $tempLog
        Get-Content -LiteralPath $tempLog | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - hello world$'
    }

    It 'is silent on the host when QuietMode is set' {
        $tempLog = Join-Path $TestDrive 'quiet.log'
        $script:QuietMode = $true
        try {
            Write-Log -Message 'quiet line' -LogFile $tempLog 6>&1 | Should -BeNullOrEmpty
        }
        finally {
            $script:QuietMode = $false
        }
        Get-Content -LiteralPath $tempLog | Should -Match 'quiet line$'
    }
}

Describe 'Test-IsAdministrator' {
    It 'returns a boolean' {
        Test-IsAdministrator | Should -BeOfType [bool]
    }
}

Describe 'Get-TsEnvironmentObject' {
    It 'returns null outside of a task sequence' {
        Get-TsEnvironmentObject | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSBuildNumberOnline' {
    It 'returns a positive integer build number for the running OS' {
        $result = Get-OSBuildNumberOnline
        $result | Should -BeOfType [int]
        $result | Should -BeGreaterThan 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: FAIL — the four functions are not recognized.

- [ ] **Step 3: Implement the four helpers**

Add to `Projects/RSAT/Install-RSAT.ps1`, after `Get-ExitCodeForResult`:

```powershell
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogFile = $script:LogFile
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"

    if (-not $script:QuietMode) {
        Write-Host $line
    }

    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $line
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TsEnvironmentObject {
    try {
        return New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-OSBuildNumberOnline {
    return [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber')
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: PASS (23/23).

- [ ] **Step 5: Commit**

```bash
git add "Projects/RSAT/Install-RSAT.ps1" "Projects/RSAT/Install-RSAT.Tests.ps1"
git commit -m "Add logging, elevation, TS-detection, and online build-number helpers to Install-RSAT.ps1"
```

---

### Task 7: Install-RSAT.ps1 — Get-OSBuildNumberOffline, Invoke-Main, bottom guard

**Files:**
- Modify: `Projects/RSAT/Install-RSAT.ps1`

**Interfaces:**
- Consumes: every function from Tasks 2–6.
- Produces:
  - `Get-OSBuildNumberOffline -OfflineSystemDrive <string>` → `[int]` — loads `<drive>\Windows\System32\config\SOFTWARE` via `reg.exe load` under a temp key, reads `CurrentBuildNumber`, unloads (with a `[gc]::Collect()` before unload so no lingering .NET handle blocks it). Throws on `reg.exe load` failure.
  - Running the script directly (not dot-sourced) executes the full install flow and calls `exit` with one of the five documented codes.

- [ ] **Step 1: Implement Get-OSBuildNumberOffline, Invoke-Main, and the bottom guard**

Add to `Projects/RSAT/Install-RSAT.ps1`, after `Get-OSBuildNumberOnline`:

```powershell
function Get-OSBuildNumberOffline {
    param(
        [Parameter(Mandatory)][string]$OfflineSystemDrive
    )

    $hivePath = Join-Path $OfflineSystemDrive 'Windows\System32\config\SOFTWARE'
    $tempKey  = 'RSATOfflineProbe'

    & reg.exe load "HKLM\$tempKey" $hivePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to load offline SOFTWARE hive from '$hivePath' (reg.exe exit code $LASTEXITCODE)."
    }

    try {
        return [int](Get-ItemPropertyValue -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$tempKey\Microsoft\Windows NT\CurrentVersion" -Name 'CurrentBuildNumber')
    }
    finally {
        # A lingering .NET registry handle from Get-ItemPropertyValue can make
        # `reg unload` fail with access denied; forcing a GC pass first releases it.
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        & reg.exe unload "HKLM\$tempKey" | Out-Null
    }
}

function Invoke-Main {
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    $logDir = 'C:\Windows\Temp\RSAT-Install'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $script:LogFile = Join-Path $logDir "Install-RSAT_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

    $tsEnvironment  = Get-TsEnvironmentObject
    $isTaskSequence = $null -ne $tsEnvironment
    $runContext     = Get-InstallRunContext -IsTaskSequence $isTaskSequence -IsInteractive ([Environment]::UserInteractive)
    $script:QuietMode = $runContext.Quiet

    Write-Log "RSAT install starting. TaskSequence=$isTaskSequence Interactive=$($runContext.IsInteractive) Quiet=$($script:QuietMode) WhatIf=$([bool]$WhatIf)"

    if (-not (Test-IsAdministrator)) {
        Write-Log 'BLOCKED: not running elevated (Administrator or SYSTEM required).'
        exit (Get-ExitCodeForResult -IsElevated $false -SourceFolderFound $false -FailedCount 0 -RebootRequired $false)
    }

    $inWinPE     = Test-RunningInWinPE
    $packageRoot = Join-Path $PSScriptRoot 'LanguagesAndOptionalFeatures'
    $osDrive     = $null

    if ($inWinPE) {
        if (-not $isTaskSequence) {
            Write-Log 'BLOCKED: WinPE detected but no task sequence environment; cannot resolve the target OS drive.'
            exit (Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $false -FailedCount 0 -RebootRequired $false)
        }
        $osDrive = $tsEnvironment.Value('OSDTargetSystemDrive')
        if ([string]::IsNullOrWhiteSpace($osDrive)) {
            Write-Log 'BLOCKED: OSDTargetSystemDrive task sequence variable is empty.'
            exit (Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $false -FailedCount 0 -RebootRequired $false)
        }
        if ($osDrive -notmatch '\\$') { $osDrive = "$osDrive\" }
        Write-Log "WinPE / offline-image target drive: $osDrive"
        $buildNumber = Get-OSBuildNumberOffline -OfflineSystemDrive $osDrive
    }
    else {
        Write-Log 'Full-OS (online) target.'
        $buildNumber = Get-OSBuildNumberOnline
    }
    Write-Log "Target OS build: $buildNumber"

    $sourceFolder = Resolve-RsatSourceFolder -PackageRoot $packageRoot -BuildNumber $buildNumber
    if (-not $sourceFolder) {
        Write-Log "BLOCKED: no RSAT source folder for build $buildNumber under $packageRoot."
        exit (Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $false -FailedCount 0 -RebootRequired $false)
    }
    Write-Log "RSAT source folder: $sourceFolder"

    $targetTable = Get-RsatCapabilityTable
    $available   = if ($inWinPE) { Get-WindowsCapability -Path $osDrive } else { Get-WindowsCapability -Online }
    $plan        = Get-CapabilityInstallOrder -Capability (Select-CapabilitiesToInstall -TargetCapability $targetTable -AvailableCapability $available)

    $toInstall    = @($plan | Where-Object { $_.Action -eq 'Install' })
    $alreadyCount = @($plan | Where-Object { $_.Action -eq 'AlreadyInstalled' }).Count
    $notOffered   = @($plan | Where-Object { $_.Action -eq 'NotOffered' })

    foreach ($n in $notOffered) {
        Write-Log "NOT OFFERED by target OS (counts as failure): $($n.CapabilityName)"
    }
    Write-Log "Plan: install $($toInstall.Count), already present $alreadyCount, not offered $($notOffered.Count)."

    $installedCount = 0
    $failedCount    = $notOffered.Count
    $rebootRequired = $false

    foreach ($item in $toInstall) {
        if ($WhatIf) {
            Write-Log "WHATIF: would install $($item.FullName) from $sourceFolder"
            continue
        }
        try {
            $result = if ($inWinPE) {
                Add-WindowsCapability -Path $osDrive -Name $item.FullName -Source $sourceFolder -LimitAccess -ErrorAction Stop
            }
            else {
                Add-WindowsCapability -Online -Name $item.FullName -Source $sourceFolder -LimitAccess -ErrorAction Stop
            }
            $installedCount++
            if ($result.RestartNeeded) { $rebootRequired = $true }
            Write-Log "Installed $($item.CapabilityName)."
        }
        catch {
            $failedCount++
            Write-Log "FAILED $($item.CapabilityName): $($_.Exception.Message)"
        }
    }

    if ($WhatIf) {
        Write-Log "WHATIF complete. Would install $($toInstall.Count); $alreadyCount already present; $($notOffered.Count) not offered."
        exit 0
    }

    $exitCode = Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $true -FailedCount $failedCount -RebootRequired $rebootRequired
    Write-Log "Done. Installed=$installedCount AlreadyPresent=$alreadyCount Failed=$failedCount RebootRequired=$rebootRequired Exit=$exitCode"

    if (-not $script:QuietMode) {
        Write-Host ''
        Write-Host 'RSAT install summary'
        Write-Host "  Installed:       $installedCount"
        Write-Host "  Already present: $alreadyCount"
        Write-Host "  Failed:          $failedCount"
        Write-Host "  Reboot required: $rebootRequired"
        Write-Host "  Log file:        $script:LogFile"
    }

    exit $exitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -WhatIf:$WhatIf
}
```

- [ ] **Step 2: Run the full installer Pester suite to confirm nothing broke**

Run: `Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed`
Expected: PASS (23/23) — the `BeforeAll` dot-source succeeding confirms `Get-OSBuildNumberOffline` and `Invoke-Main` are syntactically valid, and the guard clause keeps `Invoke-Main` from running during dot-sourcing. Real end-to-end verification of `Invoke-Main` happens in Task 11 (the package has no `LanguagesAndOptionalFeatures\` folder next to it until the builder assembles it).

- [ ] **Step 3: Commit**

```bash
git add "Projects/RSAT/Install-RSAT.ps1"
git commit -m "Add offline build detection and Invoke-Main to Install-RSAT.ps1"
```

---

### Task 8: Build-RsatPackage.ps1 — skeleton, Get-RsatCapabilityTable, Get-IsoBuildNumber

**Files:**
- Create: `Projects/RSAT/Build-RsatPackage.ps1`
- Create: `Projects/RSAT/Build-RsatPackage.Tests.ps1`

**Interfaces:**
- Consumes: `RsatCapabilities.psd1` (Task 1).
- Produces:
  - `Get-RsatCapabilityTable [-DataFilePath <string>]` → `[object[]]` — identical contract to the Install-RSAT.ps1 copy (Task 2): the 9 capability hashtables, throws if the file is missing or empty.
  - `Get-IsoBuildNumber -IsoFileName <string>` → `[int]` — the leading numeric segment of the file's leaf name (`22621` from `22621.1.220506-1250.ni_release_...iso`). Throws if the leaf does not start with `<digits>.`.

- [ ] **Step 1: Create the Build-RsatPackage.ps1 skeleton**

Save as `Projects/RSAT/Build-RsatPackage.ps1`:

```powershell
<#
.SYNOPSIS
    Extracts the fixed set of RSAT, BitLocker admin, and OpenSSH-client
    Features-on-Demand cabs from the archived Windows 11 client LOF OEM ISOs
    into a self-contained folder for MECM deployment.
.DESCRIPTION
    Mounts each ISO under .\media-archive\ read-only, verifies all 9 cabs
    named in RsatCapabilities.psd1 are present, copies the language-neutral
    cab for each into <OutputPath>\LanguagesAndOptionalFeatures\<build>\,
    then copies Install-RSAT.ps1 and RsatCapabilities.psd1 into <OutputPath>\
    and writes manifest.json, so the whole folder can be used directly as
    MECM package source. Run manually on an admin workstation whenever an
    ISO is added or refreshed; not part of the deployed package.
.NOTES
    Modified: 2026-08-31
#>

[CmdletBinding()]
param(
    [string[]]$IsoPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'RSAT-Install')
)

function Get-RsatCapabilityTable {
    param(
        [string]$DataFilePath = (Join-Path $PSScriptRoot 'RsatCapabilities.psd1')
    )

    if (-not (Test-Path -LiteralPath $DataFilePath -PathType Leaf)) {
        throw "RSAT capability data file not found: $DataFilePath"
    }

    $data = Import-PowerShellDataFile -LiteralPath $DataFilePath
    if (-not $data.Capabilities -or @($data.Capabilities).Count -eq 0) {
        throw "RSAT capability data file '$DataFilePath' has no Capabilities entries."
    }

    return @($data.Capabilities)
}

function Get-IsoBuildNumber {
    param(
        [Parameter(Mandatory)][string]$IsoFileName
    )

    $leaf = Split-Path -Path $IsoFileName -Leaf
    if ($leaf -match '^(?<build>\d+)\.') {
        return [int]$Matches['build']
    }

    throw "Could not parse an OS build number from ISO file name '$leaf'."
}
```

- [ ] **Step 2: Write the failing tests**

Save as `Projects/RSAT/Build-RsatPackage.Tests.ps1`:

```powershell
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
```

- [ ] **Step 3: Run the tests**

Run: `Invoke-Pester -Path "Projects\RSAT\Build-RsatPackage.Tests.ps1" -Output Detailed`
Expected: PASS (5/5). Both functions exist in the skeleton; this confirms the dot-source works, the builder/installer capability tables are identical, and `Get-IsoBuildNumber` parses correctly.

- [ ] **Step 4: Commit**

```bash
git add "Projects/RSAT/Build-RsatPackage.ps1" "Projects/RSAT/Build-RsatPackage.Tests.ps1"
git commit -m "Add Build-RsatPackage.ps1 skeleton with capability table and ISO build-number parsing"
```

---

### Task 9: Build-RsatPackage.ps1 — Get-RsatCabFileName, Find-MissingCabFileName, Get-RsatCabToCopy

**Files:**
- Modify: `Projects/RSAT/Build-RsatPackage.ps1`
- Modify: `Projects/RSAT/Build-RsatPackage.Tests.ps1`

**Interfaces:**
- Produces:
  - `Get-RsatCabFileName -CabStem <string>` → `[string]` — `"<CabStem>~31bf3856ad364e35~amd64~~.cab"`.
  - `Find-MissingCabFileName -AvailableFileName <string[]> -CabStem <string[]>` → `[string[]]` — the expected cab filenames (from `Get-RsatCabFileName`) whose name is absent from `AvailableFileName`, compared case-insensitively. Empty array when all present. `AvailableFileName` may be empty.
  - `Get-RsatCabToCopy -SourceFolder <string> -CabStem <string[]>` → `[string[]]` — full paths (`<SourceFolder>\<expected filename>`) for all `CabStem`, after enumerating `*.cab` in `SourceFolder` and throwing (naming every missing cab) if any expected cab is absent.

- [ ] **Step 1: Write the failing tests**

Add to `Projects/RSAT/Build-RsatPackage.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Invoke-Pester -Path "Projects\RSAT\Build-RsatPackage.Tests.ps1" -Output Detailed`
Expected: FAIL — `Get-RsatCabFileName`, `Find-MissingCabFileName`, `Get-RsatCabToCopy` are not recognized.

- [ ] **Step 3: Implement the three functions**

Add to `Projects/RSAT/Build-RsatPackage.ps1`, after `Get-IsoBuildNumber`:

```powershell
function Get-RsatCabFileName {
    param(
        [Parameter(Mandatory)][string]$CabStem
    )

    return "$CabStem~31bf3856ad364e35~amd64~~.cab"
}

function Find-MissingCabFileName {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AvailableFileName,
        [Parameter(Mandatory)][string[]]$CabStem
    )

    $availableLower = @($AvailableFileName | ForEach-Object { $_.ToLowerInvariant() })

    $missing = foreach ($stem in $CabStem) {
        $expected = Get-RsatCabFileName -CabStem $stem
        if ($availableLower -notcontains $expected.ToLowerInvariant()) {
            $expected
        }
    }

    return @($missing)
}

function Get-RsatCabToCopy {
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string[]]$CabStem
    )

    $available = @(Get-ChildItem -LiteralPath $SourceFolder -Filter '*.cab' -File | ForEach-Object Name)

    $missing = Find-MissingCabFileName -AvailableFileName $available -CabStem $CabStem
    if ($missing.Count -gt 0) {
        throw "Source folder '$SourceFolder' is missing $($missing.Count) required cab(s): $($missing -join ', ')"
    }

    return @($CabStem | ForEach-Object { Join-Path $SourceFolder (Get-RsatCabFileName -CabStem $_) })
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester -Path "Projects\RSAT\Build-RsatPackage.Tests.ps1" -Output Detailed`
Expected: PASS (10/10).

- [ ] **Step 5: Commit**

```bash
git add "Projects/RSAT/Build-RsatPackage.ps1" "Projects/RSAT/Build-RsatPackage.Tests.ps1"
git commit -m "Add cab-name resolution and missing-cab detection to Build-RsatPackage.ps1"
```

---

### Task 10: Build-RsatPackage.ps1 — Invoke-Main, bottom guard

**Files:**
- Modify: `Projects/RSAT/Build-RsatPackage.ps1`

**Interfaces:**
- Consumes: every builder function from Tasks 8–9; `Install-RSAT.ps1` and `RsatCapabilities.psd1` as files to copy.
- Produces: running the script directly assembles the complete `<OutputPath>\` — `LanguagesAndOptionalFeatures\<build>\` (9 cabs) per ISO, `Install-RSAT.ps1`, `RsatCapabilities.psd1`, and `manifest.json`.

- [ ] **Step 1: Implement Invoke-Main and the bottom guard**

Add to `Projects/RSAT/Build-RsatPackage.ps1`, after `Get-RsatCabToCopy`:

```powershell
function Invoke-Main {
    [CmdletBinding()]
    param(
        [string[]]$IsoPath,
        [string]$OutputPath = (Join-Path $PSScriptRoot 'RSAT-Install')
    )

    $capabilities = Get-RsatCapabilityTable
    $cabStems = @($capabilities | ForEach-Object { $_.CabStem })

    if (-not $IsoPath -or $IsoPath.Count -eq 0) {
        $archiveDir = Join-Path $PSScriptRoot 'media-archive'
        $IsoPath = @(Get-ChildItem -LiteralPath $archiveDir -Filter '*.iso' -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
    }
    if (-not $IsoPath -or $IsoPath.Count -eq 0) {
        throw "No ISO files found under .\media-archive\ and none supplied via -IsoPath."
    }

    $featuresRoot = Join-Path $OutputPath 'LanguagesAndOptionalFeatures'
    New-Item -ItemType Directory -Path $featuresRoot -Force | Out-Null

    $manifestBuilds = @()

    foreach ($iso in $IsoPath) {
        if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) {
            throw "ISO not found: $iso"
        }

        $buildNumber = Get-IsoBuildNumber -IsoFileName $iso
        Write-Host "Processing $(Split-Path $iso -Leaf) (build $buildNumber)..."

        $mount = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop
        try {
            $driveLetter = ($mount | Get-Volume).DriveLetter
            $lofSource = "${driveLetter}:\LanguagesAndOptionalFeatures"
            if (-not (Test-Path -LiteralPath $lofSource -PathType Container)) {
                throw "ISO '$iso' has no LanguagesAndOptionalFeatures folder."
            }

            $cabPaths = Get-RsatCabToCopy -SourceFolder $lofSource -CabStem $cabStems

            $destFolder = Join-Path $featuresRoot $buildNumber
            if (Test-Path -LiteralPath $destFolder) {
                Remove-Item -LiteralPath $destFolder -Recurse -Force
            }
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null

            $copiedNames = foreach ($cabPath in $cabPaths) {
                Copy-Item -LiteralPath $cabPath -Destination $destFolder -Force
                Split-Path -Path $cabPath -Leaf
            }

            Write-Host "  Copied $(@($copiedNames).Count) cabs to $destFolder"

            $manifestBuilds += [PSCustomObject]@{
                Build     = $buildNumber
                SourceIso = (Split-Path -Path $iso -Leaf)
                Cabs      = @($copiedNames)
            }
        }
        finally {
            Dismount-DiskImage -ImagePath $iso | Out-Null
        }
    }

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-RSAT.ps1')      -Destination $OutputPath -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RsatCapabilities.psd1') -Destination $OutputPath -Force

    $manifest = [PSCustomObject]@{
        GeneratedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Builds       = @($manifestBuilds)
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputPath 'manifest.json') -Encoding UTF8

    Write-Host "Build complete. Output: $OutputPath"
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -IsoPath $IsoPath -OutputPath $OutputPath
}
```

- [ ] **Step 2: Run the builder Pester suite to confirm nothing broke**

Run: `Invoke-Pester -Path "Projects\RSAT\Build-RsatPackage.Tests.ps1" -Output Detailed`
Expected: PASS (10/10) — the `BeforeAll` dot-source succeeding confirms `Invoke-Main` is syntactically valid and the guard keeps it from running during dot-sourcing.

- [ ] **Step 3: Commit**

```bash
git add "Projects/RSAT/Build-RsatPackage.ps1"
git commit -m "Add Invoke-Main to Build-RsatPackage.ps1"
```

---

### Task 11: End-to-end — build the real package, dry-run the installer, flag manual validation

**Files:**
- None modified. This task runs the finished scripts against the real archived ISOs and the current machine.

**Interfaces:**
- Consumes: `Build-RsatPackage.ps1`, `Install-RSAT.ps1`, both archived ISOs.
- Produces: a fully assembled `Projects/RSAT/RSAT-Install/` (git-ignored), and confirmation that the installer's `-WhatIf` path runs clean on this machine.

- [ ] **Step 1: Run both Pester suites one more time**

Run:
```powershell
Invoke-Pester -Path "Projects\RSAT\RsatCapabilities.Tests.ps1" -Output Detailed
Invoke-Pester -Path "Projects\RSAT\Build-RsatPackage.Tests.ps1" -Output Detailed
Invoke-Pester -Path "Projects\RSAT\Install-RSAT.Tests.ps1" -Output Detailed
```
Expected: PASS 5/5, 10/10, 23/23.

- [ ] **Step 2: Build the real package**

Run from the `S4W` repo root: `& "Projects\RSAT\Build-RsatPackage.ps1"`

Expected console output: `Processing 22621.1.220506-...iso (build 22621)...` then `  Copied 9 cabs to ...\22621`, likewise for `26100`, ending `Build complete.`

- [ ] **Step 3: Verify the assembled package**

Run:
```powershell
Test-Path "Projects\RSAT\RSAT-Install\Install-RSAT.ps1"
Test-Path "Projects\RSAT\RSAT-Install\RsatCapabilities.psd1"
Test-Path "Projects\RSAT\RSAT-Install\manifest.json"
(Get-ChildItem "Projects\RSAT\RSAT-Install\LanguagesAndOptionalFeatures\22621" -Filter *.cab).Count
(Get-ChildItem "Projects\RSAT\RSAT-Install\LanguagesAndOptionalFeatures\26100" -Filter *.cab).Count
Get-Content "Projects\RSAT\RSAT-Install\manifest.json" | ConvertFrom-Json | ConvertTo-Json -Depth 5
Get-DiskImage -ImagePath (Get-ChildItem "Projects\RSAT\media-archive\*.iso" | Select-Object -First 1 -Expand FullName) | Select-Object Attached
```
Expected: first three `True`; both cab counts `9`; manifest lists both builds with 9 cabs each and their source ISO names; `Attached` is `False` (ISOs dismounted cleanly by the `finally` block).

- [ ] **Step 4: Safe `-WhatIf` dry-run of the assembled installer**

Run **from an elevated PowerShell** (the elevation check exits `3` otherwise):
`& "Projects\RSAT\RSAT-Install\Install-RSAT.ps1" -WhatIf`

Expected: console summary + a log at `C:\Windows\Temp\RSAT-Install\Install-RSAT_<timestamp>.log` showing `Full-OS (online) target`, this machine's build number, `RSAT source folder: ...\RSAT-Install\LanguagesAndOptionalFeatures\<build>`, a `Plan:` line, `WHATIF: would install ...` lines for each not-yet-present capability, and exit `0`. **No capability is actually installed.** If this machine already has some of these tools, expect them on the `already present` count instead — that is fine.

- [ ] **Step 5: Commit (only if the build script needed any fix in this task)**

If Steps 2–4 exposed a bug and you changed a script, commit the fix:
```bash
git add "Projects/RSAT"
git commit -m "Fix <specific issue> found during end-to-end package build"
```
Otherwise skip — `RSAT-Install/` is git-ignored and nothing else changed.

- [ ] **Step 6: Flag the remaining manual validation to the user**

This plan never runs `Add-WindowsCapability` for real. Before handing the package to helpdesk, the user should, on a real or disposable Windows 11 machine matching one supported build:
- Run `RSAT-Install\Install-RSAT.ps1` (no `-WhatIf`) elevated, confirm exit `0`/`3010` and that the RSAT tools + `ssh.exe` appear.
- Wire `RSAT-Install\` into an MECM Package, add it to a test OSD task sequence step **running in WinPE**, and confirm the offline path (`Get-OSBuildNumberOffline`, `Add-WindowsCapability -Path`) works end-to-end. This depends on the ConfigMgr boot image having the storage/scripting WinPE optional components (present when PowerShell support is enabled on the boot image) — verify in that test.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task(s) |
|---|---|
| 9 target capabilities, name ↔ cab table | Task 1 (`RsatCapabilities.psd1`), Global Constraints |
| Shared `.psd1` loaded by both scripts, shipped in package | Tasks 2, 8 (`Get-RsatCapabilityTable`), Task 10 (copied), Task 8 (drift-guard test) |
| `.psd1` structural test (9 entries, non-empty fields) | Task 1, Step 5 |
| Builder: build number from cab package manifest (was: ISO filename) | Task 8 (`Get-BuildFromPackageManifest` / `Get-CabPackageBuild`) — see amendment 2 |
| Builder: verify all 9 cabs present, hard-fail naming missing | Task 9 (`Find-MissingCabFileName`, `Get-RsatCabToCopy`) |
| Builder: case-insensitive `FoD`/`FOD` match | Task 9, Step 1 (test) + Step 3 |
| Builder: mount read-only, copy per build, dismount in `finally` | Task 10 (`Invoke-Main`) |
| Builder: idempotent per-build subfolder | Task 10 (`Remove-Item` then recreate `$destFolder`) |
| Builder: copy `Install-RSAT.ps1` + `.psd1`, write `manifest.json` | Task 10 |
| Builder: default `-IsoPath` = `media-archive\*.iso` | Task 10 |
| Builder: hard stops (missing ISO, unparseable name, no cabs) | Tasks 8–10 |
| Installer: WinPE vs full-OS detection (`MiniNT`) | Task 4 (`Test-RunningInWinPE`) |
| Installer: TS env object, `OSDTargetSystemDrive` | Tasks 6–7 |
| Installer: online + offline build number | Tasks 6 (`...Online`), 7 (`...Offline`) |
| Installer: build subfolder resolution, exit 2 on no match | Task 2 (`Resolve-RsatSourceFolder`), Task 7 |
| Installer: fixed-9 selection, skip Installed, NotOffered = failure | Task 3 (`Select-CapabilitiesToInstall`) |
| Installer: install order SM → FS → AD → rest | Task 3 (`Get-CapabilityInstallOrder`) |
| Installer: `-Source <build folder> -LimitAccess` | Task 7 (`Invoke-Main`) |
| Installer: run-context quiet/verbose + always-log | Tasks 4, 6, 7 |
| Installer: elevation check, exit 3 | Tasks 6 (`Test-IsAdministrator`), 7 |
| Installer: exit codes 0/3010/1/2/3 with precedence | Task 5 (`Get-ExitCodeForResult`) |
| Archived source media: move ISOs, `media-archive/README.md`, read-only | Task 1 |
| `.gitignore`: `*.iso`, `RSAT-Install/` | Task 1 |
| Testing: pure logic only, no real ISO/hive/DISM in `.Tests.ps1` | all test steps; Task 11 = manual gate |
| Repo script conventions (comment header, guard, verbs) | Tasks 2, 8 skeletons |

No gaps found.

**2. Placeholder scan:** No `TBD` / "add error handling" / "write tests for the above" / "similar to Task N". Every code step carries its full implementation.

**3. Type consistency:**
- `Get-RsatCapabilityTable` → `[object[]]` of hashtables with `.CapabilityName` / `.CabStem`: produced identically in Tasks 2 & 8, consumed in Tasks 3, 7, 10.
- `Select-CapabilitiesToInstall` output objects (`.CapabilityName`, `.FullName`, `.Action`): produced Task 3, consumed by `Get-CapabilityInstallOrder` (Task 3) and `Invoke-Main` (Task 7) — `.Action` values `'Install'`/`'AlreadyInstalled'`/`'NotOffered'` used consistently.
- `Get-CapabilityInstallOrder` takes and returns the same object type (`-Capability`), used in Task 7.
- `Get-ExitCodeForResult` params (`-IsElevated`, `-SourceFolderFound`, `-FailedCount`, `-RebootRequired`) — same names in Task 5 definition and all Task 7 call sites.
- `Get-RsatCabToCopy` / `Find-MissingCabFileName` / `Get-RsatCabFileName` param names (`-SourceFolder`, `-AvailableFileName`, `-CabStem`) consistent between Task 9 and Task 10 caller.
- `Resolve-RsatSourceFolder -PackageRoot -BuildNumber` consistent Task 2 ↔ Task 7.
- `$script:LogFile` / `$script:QuietMode` declared in the Task 2 skeleton, set in Task 7 `Invoke-Main`, read by `Write-Log` (Task 6).

No inconsistencies found.
