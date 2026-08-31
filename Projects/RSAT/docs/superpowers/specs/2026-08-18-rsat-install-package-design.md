# RSAT Admin-Tools Install Package — Design

Date: 2026-08-18 (revised 2026-08-31)
Status: Approved for implementation

> **Revision note (2026-08-31):** the deliverable is unchanged — a small,
> self-contained folder used as MECM package source — but the tool set is now a
> fixed, explicit list of 9 capabilities (was "every `Rsat.*` the OS offers"),
> the builder copies cabs by exact name and hard-fails on any missing cab, and
> the original ISOs are retained as archived historical media. An ISO-based
> deliverable was considered and rejected (extra mount/dismount steps in both
> deployment contexts for no benefit).
>
> **Amendment (2026-08-31, later same day):** added a `BuildSourceMap` alias
> table in `RsatCapabilities.psd1`. Windows 11 25H2 (build 26200) is an
> enablement package on 24H2's (26100) servicing branch and the FoD cab
> manifests declare `buildCompare="GE"` against the 26100 EditionPack, so the
> 26100 cabs install on 26200. The installer now resolves 26200 to the 26100
> source folder. Unmapped unknown builds still fail fast (exit 2) — the alias
> table is explicit, not a "use whatever is newest" fallback.

## Purpose

Helpdesk and admin-workstation builds need a specific set of Remote Server
Administration Tools plus the BitLocker Drive Encryption Administration
Utilities and the OpenSSH client installed on Windows 11 machines, deployed
two ways:

- As a step in an MECM OSD Task Sequence, applied to the offline OS image
  while still running in WinPE.
- As a script/package pushed directly to existing machines via an MECM
  collection deployment (Run Script or Package/Program), running in the
  full OS.

The environment has no reliable path to Microsoft Update for Features on
Demand (FOD), so the source content has to come from local media: two
`..._CLIENT_LOF_PACKAGES_OEM.iso` files (Windows 11 22H2 build 22621, and
24H2 build 26100). Each ISO is ~6–7 GB and contains FOD cabs for far more
than what is needed (Notepad, Paint, printing, WSUS tools, 30+ per-language
variants of everything, etc.), so it is not practical to hand the ISO
itself to MECM.

This project produces a small folder (~62 MB) that drops straight into an
MECM package: just the cabs for the 9 required capabilities, both OS
builds, plus one install script that adapts to whichever of the two
contexts above it is running in.

## Scope

**In scope:**
- A builder script that extracts the 9 required language-neutral cabs from
  both ISOs into a deployable output folder.
- An install script, shipped inside that output folder, that installs those
  9 capabilities whether it is running in WinPE against an offline image or
  in a full online OS.
- Pester tests for the logic that does not require mounting an ISO, loading
  an offline hive, or calling DISM.
- Relocating the two original ISOs into an archive subfolder so they are
  retained as historical media.

**Out of scope:**
- Creating the actual MECM Package/Application/TS step objects in the
  ConfigMgr console — the output of this project is the package *source*
  folder; wiring it into MECM is a separate manual step.
- Any capability not in the fixed list below.
- Non-neutral (per-language) FOD resources.
- Hyper-V management tooling. Hyper-V management on Windows client is an
  in-box *optional feature* (`Microsoft-Hyper-V-Management-PowerShell` /
  `Microsoft-Hyper-V-Management-Clients`), not a capability, and no
  corresponding cab exists on these LOF ISOs. It is handled separately, if
  at all.
- Producing an ISO deliverable.

## Target capabilities

Exactly these 9, on both builds. Language-neutral cabs only. The
capability-name ↔ cab-name pairing is a static data table defined once and
shared by both scripts (the builder consumes the cab names, the installer
consumes the capability names).

| Capability name (DISM)                  | Language-neutral cab (stem, `~31bf3856ad364e35~amd64~~.cab`) |
| --------------------------------------- | ----------------------------------------------------------- |
| `Rsat.ServerManager.Tools`              | `Microsoft-Windows-ServerManager-Tools-FoD-Package`         |
| `Rsat.ActiveDirectory.DS-LDS.Tools`     | `Microsoft-Windows-ActiveDirectory-DS-LDS-Tools-FoD-Package`|
| `Rsat.GroupPolicy.Management.Tools`     | `Microsoft-Windows-GroupPolicy-Management-Tools-FoD-Package` |
| `Rsat.Dns.Tools`                        | `Microsoft-Windows-DNS-Tools-FoD-Package`                   |
| `Rsat.DHCP.Tools`                       | `Microsoft-Windows-DHCP-Tools-FoD-Package`                  |
| `Rsat.FileServices.Tools`               | `Microsoft-Windows-FileServices-Tools-FoD-Package`          |
| `Rsat.FailoverCluster.Management.Tools` | `Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package` |
| `Rsat.BitLocker.Recovery.Tools`         | `Microsoft-Windows-BitLocker-Recovery-Tools-FoD-Package`    |
| `OpenSSH.Client`                        | `OpenSSH-Client-Package`                                    |

Notes established by direct inspection of both ISOs during design:

- Each FOD cab is fully self-contained — it bundles its own internal
  sub-packages (e.g. `ServerManager-Tools` carries 7 internal packages).
  One cab per capability is all that is needed.
- All cross-capability dependencies are satisfied within this 9-item set,
  so nothing pulls in a 10th cab:
  - `Rsat.BitLocker.Recovery.Tools` → `Rsat.ActiveDirectory.DS-LDS.Tools`
  - `Rsat.ActiveDirectory.DS-LDS.Tools` → `Rsat.ServerManager.Tools`
  - `Rsat.FileServices.Tools` → `Rsat.ServerManager.Tools`
  - `Rsat.FailoverCluster.Management.Tools` → `Rsat.FileServices.Tools`
  - the rest declare no cross-capability dependency.
- The cabs' only external reference is `<parent>` on
  `Microsoft-Windows-EditionPack-Professional-Package` — i.e. "requires
  Windows Pro or higher", already present on any RSAT-capable machine.
- Language satellite cabs are marked optional
  (`require type="language" value="*"`), so a neutral-only install succeeds
  and tool UI follows the OS display language.
- The `FailoverCluster-Management-Tools` cab uses an uppercase `FOD` token
  in its filename where the others use `FoD`; filename matching must be
  case-insensitive.
- `OpenSSH.Client` ships pre-installed on Windows 11 24H2 (build 26100),
  so the installer must treat "already installed" as success, not re-install.

## Background: how the ISOs are structured

Each ISO has a `LanguagesAndOptionalFeatures\` folder containing FOD cabs
named `<Feature>~31bf3856ad364e35~<arch>~<lang>~.cab`, one language-neutral
cab per feature (`~~.cab`, no language token) plus ~35 per-language cabs.
The 9 cabs above sit in this folder alongside hundreds of unrelated
features. Windows resolves a capability name (e.g. `Rsat.Dns.Tools~~~~0.0.1.0`)
to the right cab when `Add-WindowsCapability -Source` points at a folder
containing the cab — DISM does the matching, and it resolves declared
dependencies as long as the dependency's cab is present in the same source
folder.

## Architecture

Two independent PowerShell scripts in `Projects/RSAT/`, a shared
`RsatCapabilities.psd1` data file, and an archive folder for the source
ISOs. Pure decision/parsing logic is factored into
small named functions so Pester can exercise it without real hardware; real
system interaction (ISO mounting, DISM, offline registry hives) lives in
each script's `Invoke-Main` and is verified manually.

### Shared capability table

Both scripts need the 9-row table above, so it lives once in a data file,
`RsatCapabilities.psd1`, next to the scripts in the repo. It is a plain
PowerShell data file with two keys:

- `Capabilities` — an array of hashtables, each with `CapabilityName` and
  `CabStem`. The builder uses the `CabStem` values; the installer uses the
  `CapabilityName` values.
- `BuildSourceMap` — a hashtable of `<OS build>` → `<source-folder build>`
  aliases, for OS builds that have no ISO of their own but whose FoD cabs
  are satisfied by another build's folder (currently `26200` → `26100`, for
  Windows 11 25H2 on the 24H2 servicing branch). Only the installer reads
  it.

Both scripts load it with `Import-PowerShellDataFile` from their own
`$PSScriptRoot`. The builder copies this file into `<OutputPath>\`
alongside `Install-RSAT.ps1` so the deployed package is self-contained.
Tests load the `.psd1` directly. A missing or malformed `.psd1` is a hard
stop in either script; a `.psd1` with no `BuildSourceMap` is treated as an
empty map (alias resolution simply never fires).

### 1. `Build-RsatPackage.ps1`

Run manually, on an admin workstation, whenever an ISO is added or updated.
Not part of the deployed package.

- **Parameters:**
  - `-IsoPath` (string[], optional) — one or more ISO paths. Defaults to
    every `*.iso` found under `.\media-archive\`.
  - `-OutputPath` (string, optional) — defaults to `.\RSAT-Install` next to
    the script.
- **Per ISO:**
  1. Read the OS build number from the ISO's filename — the leading numeric
     segment (e.g. `22621` from `22621.1.220506-1250.ni_release_...iso`).
     A filename that does not parse as `<digits>.*` is a hard stop.
  2. Mount it (`Mount-DiskImage`).
  3. Verify **all 9** expected language-neutral cabs are present under
     `LanguagesAndOptionalFeatures\`. If any is missing, hard stop naming
     the missing cab(s) — no partial output.
  4. Copy the 9 cabs into
     `<OutputPath>\LanguagesAndOptionalFeatures\<build>\`, preserving
     filenames as-is.
  5. Dismount the ISO in a `finally` block.
- **Idempotent:** re-running for a given build wipes and rebuilds only that
  build's subfolder; other builds in `OutputPath` are untouched.
- After all ISOs: copies `Install-RSAT.ps1` and `RsatCapabilities.psd1`
  (both checked into this repo, not generated) into `<OutputPath>\`, and
  writes `<OutputPath>\manifest.json` recording, per build, the source ISO
  filename, the 9 cab filenames, and a UTC timestamp.
- **Result:** `RSAT-Install\` containing `Install-RSAT.ps1`,
  `RsatCapabilities.psd1`, `manifest.json`,
  `LanguagesAndOptionalFeatures\22621\` (9 cabs) and
  `LanguagesAndOptionalFeatures\26100\` (9 cabs) — nothing else. This whole
  folder is the MECM package source.

### 2. `Install-RSAT.ps1`

Ships inside `RSAT-Install\`. Runs on target machines in both deployment
contexts.

- **OS build match:** reads `CurrentBuildNumber` from
  `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` (online) or from the
  offline hive (WinPE case), then resolves a source folder: an exact
  `LanguagesAndOptionalFeatures\<build>\` subfolder next to the script wins;
  failing that, if `BuildSourceMap` aliases this build to another and that
  folder exists, it is used (and the aliasing is logged); otherwise exit
  `2`, nothing attempted.
- **WinPE vs full OS:** detected via presence of
  `HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT`.
  - **WinPE (OSD TS):** target is the offline image. Resolves the offline OS
    drive from `%OSDTargetSystemDrive%` (via `Microsoft.SMS.TSEnvironment`
    COM object — its presence also confirms the script is inside a task
    sequence). Reads the offline `CurrentBuildNumber` from
    `<OSDTargetSystemDrive>\Windows\System32\config\SOFTWARE`, loaded
    temporarily with `reg load`. Installs via
    `Get-WindowsCapability -Path <drive>\` / `Add-WindowsCapability -Path <drive>\`.
  - **Full OS:** `Get-WindowsCapability -Online` / `Add-WindowsCapability -Online`.
- **Capability selection:** the fixed 9 from the shared table — *not*
  discovery. For each, find the matching entry in `Get-WindowsCapability`
  output by case-insensitive name match:
  - `State = Installed` → count as already-present, skip.
  - otherwise → `Add-WindowsCapability … -Name <name> -Source <build subfolder> -LimitAccess`.
  - capability not offered by the target OS at all → count as failed, log
    which one (should not happen for these builds, but must not be silent).
- **Install order:** `Rsat.ServerManager.Tools`, then
  `Rsat.FileServices.Tools`, then `Rsat.ActiveDirectory.DS-LDS.Tools`,
  then the remaining 6 in any order — so dependencies are satisfied even if
  DISM's own dependency resolution misbehaves against a source folder.
- **Run-context-aware output:**
  - TS environment object present, or not an interactive console (SYSTEM via
    MECM Run Script) → quiet: meaningful output to the log only.
  - Interactive console → per-capability progress and a final summary
    (installed / already-present / failed counts), in addition to logging.
  - Always writes a log:
    `C:\Windows\Temp\RSAT-Install\Install-RSAT_<yyyyMMdd-HHmmss>.log`.
- **Elevation check:** verifies Administrator/SYSTEM up front; if not, exit
  `3` with a clear message rather than a cryptic DISM access-denied error.
- **Exit codes:**
  - `0` — all 9 installed or already present.
  - `3010` — installed, but DISM reported a reboot is needed.
  - `1` — one or more capabilities failed; log has details.
  - `2` — no source folder for this OS build (no exact `<build>` subfolder
    and no usable `BuildSourceMap` alias); nothing attempted.
  - `3` — not elevated.

## Archived source media

The two original ISOs move from `Projects/RSAT/` into
`Projects/RSAT/media-archive/`. They stay git-ignored (6–7 GB each). A short
`media-archive/README.md` records what they are, their build numbers, and
that `Build-RsatPackage.ps1` reads from this folder by default. The
originals are never modified — the builder mounts them read-only.

## Testing

Following the repo convention (see
`Projects\MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`), logic is
factored into named functions each script exposes for dot-sourcing, with a
`if ($MyInvocation.InvocationName -ne '.') { Invoke-Main ... }` guard so
tests never execute the script body.

- `RsatCapabilities.psd1`: a test asserts it loads via
  `Import-PowerShellDataFile`, has exactly 9 entries with non-empty
  `CapabilityName` / `CabStem`, maps `26200` → `26100`, and only aliases to
  a build that a real ISO produces.
- `Build-RsatPackage.ps1`: build-number-from-filename parsing (valid /
  unparseable); "all 9 cabs present" verification given a fake file listing
  (complete / one missing / case-variant `FOD` token); cab selection
  produces exactly the 9 expected paths.
- `Install-RSAT.ps1`: source-folder resolution (exact match / no match /
  alias followed / exact preferred over alias / alias target missing);
  `BuildSourceMap` loading (present / absent → empty map);
  capability filtering given fake `Get-WindowsCapability` output
  (not-present → install, already-installed → skip, offered-but-in-target
  vs not-offered); install ordering (ServerManager / FileServices /
  ActiveDirectory precede the rest); exit-code selection for every
  documented code; WinPE detection (mocking the registry probe);
  run-context/quiet-mode selection.

Neither `.Tests.ps1` mounts an ISO, loads a real hive, or calls a real
DISM cmdlet. Real end-to-end validation — `Add-WindowsCapability` for real,
online and against a real offline TS image — is a manual, user-run step
before handoff to helpdesk, explicitly called out in the implementation
plan and never run automatically by any task.

## Error handling

- **Builder:** missing/unreadable ISO, unparseable filename, mount failure,
  any of the 9 expected cabs missing from a build, and an unwritable output
  path are all hard stops with a clear message — no partial or silent
  output.
- **Installer:** every failure mode has a defined exit code and a log entry
  describing what was attempted and why it failed, since a helpdesk tech —
  not the author — will be reading a failure.

## Open questions

None blocking. The 9-capability table and the `BuildSourceMap` both live in
one file, `RsatCapabilities.psd1`; adding/renaming a capability or aliasing
a new OS build to an existing folder is a deliberate one-file edit. If a
future Windows build ships a cab under a renamed stem, the builder's "all 9
cabs present" check fails loudly rather than producing a short package. If
a future 23H2-style enablement build (e.g. 22631 on the 22H2 branch) needs
covering, add it to `BuildSourceMap` — it is not there yet because only
25H2 was confirmed compatible.
