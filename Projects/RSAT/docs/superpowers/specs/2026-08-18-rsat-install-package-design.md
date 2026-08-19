# RSAT Install Package — Design

Date: 2026-08-18
Status: Approved for implementation

## Purpose

Helpdesk needs RSAT (Remote Server Administration Tools) and the BitLocker
Drive Encryption Administration Utilities installed on Windows 11 machines,
deployed two ways:

- As a step in an MECM OSD Task Sequence, applied to the offline OS image
  while still running in WinPE.
- As a script/package pushed directly to existing machines via an MECM
  collection deployment (Run Script or Package/Program), running in the
  full OS.

The environment has no reliable path to Microsoft Update for Features on
Demand (FOD), so the source content has to come from local media: two
`..._CLIENT_LOF_PACKAGES_OEM.iso` files (Windows 11 22H2 build 22621, and
24H2 build 26100). Each ISO is ~7 GB and contains FOD cabs for far more than
RSAT (Notepad, Paint, printing, WSUS tools, 30+ per-language variants of
everything, etc.), so it isn't practical to hand the ISO itself to MECM.

This project produces a small, self-contained folder that can be dropped
straight into an MECM package: just the RSAT-relevant cabs, plus one install
script that adapts to whichever of the two contexts above it's running in.

## Scope

**In scope:**
- A builder script that extracts the RSAT + BitLocker admin cabs from both
  ISOs into a deployable output folder.
- An install script, shipped inside that output folder, that installs those
  capabilities correctly whether it's running in WinPE against an offline
  image or in a full online OS.
- Pester tests for the logic that doesn't require actually mounting an ISO
  or calling DISM.

**Out of scope:**
- Creating the actual MECM Package/Application/TS step objects in the
  ConfigMgr console — the output of this project is the package *source*
  folder; wiring it into MECM is a separate manual step.
- Non-English language resources (see Language Scope below).
- Any RSAT capability not present in the supplied OEM LOF ISOs.

## Background: how the ISOs are structured

Each ISO has a `LanguagesAndOptionalFeatures\` folder containing FOD cabs
named `<Feature>-FoD-Package~31bf3856ad364e35~<arch>~<lang>~.cab`, one
language-neutral cab per feature (`~~.cab`, no language token) plus ~35
per-language cabs. RSAT capabilities live in this same folder under 17 confirmed stems (e.g.
`Microsoft-Windows-ActiveDirectory-DS-LDS-Tools-FoD-Package`,
`Microsoft-Windows-BitLocker-Recovery-Tools-FoD-Package`), alongside many
non-RSAT features (Notepad, MSPaint, printing, storage management, ...)
that get discarded. Both ISOs were inspected directly during design and
carry the identical 17-stem set:

```
Microsoft-Windows-ActiveDirectory-DS-LDS-Tools-FoD-Package
Microsoft-Windows-BitLocker-Recovery-Tools-FoD-Package
Microsoft-Windows-CertificateServices-Tools-FoD-Package
Microsoft-Windows-DHCP-Tools-FoD-Package
Microsoft-Windows-DNS-Tools-FoD-Package
Microsoft-Windows-FileServices-Tools-FoD-Package
Microsoft-Windows-GroupPolicy-Management-Tools-FoD-Package
Microsoft-Windows-IPAM-Client-FoD-Package
Microsoft-Windows-LLDP-Tools-FoD-Package
Microsoft-Windows-NetworkController-Tools-FoD-Package
Microsoft-Windows-NetworkLoadBalancing-Tools-FoD-Package
Microsoft-Windows-RemoteAccess-Management-Tools-FoD-Package
Microsoft-Windows-RemoteDesktop-Services-Tools-FoD-Package
Microsoft-Windows-ServerManager-Tools-FoD-Package
Microsoft-Windows-StorageReplica-Tools-FoD-Package
Microsoft-Windows-VolumeActivation-Tools-FoD-Package
Microsoft-Windows-WSUS-Tools-FoD-Package
```

Windows itself resolves a capability name (e.g. `Rsat.Dns.Tools~~~~0.0.1.0`)
to the right cab when you point `Add-WindowsCapability -Source` at a folder
containing them — DISM does the matching, not us. So the builder just needs
to copy the neutral cab for each stem above; it does not maintain a
capability-name-to-filename mapping.

## Architecture

Two scripts:

### 1. `Build-RsatPackage.ps1`

Run manually, on an admin workstation, whenever an ISO is added or updated.
Not part of the deployed package.

- **Parameters:**
  - `-IsoPath` (string[], optional) — one or more ISO paths. Defaults to
    every `*.iso` found next to the script.
  - `-OutputPath` (string, optional) — defaults to `.\RSAT-Install` next to
    the script.
- **Per ISO:**
  1. Mount it (`Mount-DiskImage`).
  2. Read the OS build number from the ISO's own filename — the build
     number is the leading numeric segment (e.g. `22621` from
     `22621.1.220506-1250.ni_release_...iso`). Both known ISOs follow this
     naming convention; if a filename doesn't parse as `<digits>.*`, the
     builder stops with a clear error rather than guessing.
  3. Enumerate `LanguagesAndOptionalFeatures\*.cab`, and select the
     language-neutral cabs (`~~.cab`, no language token) whose feature stem
     matches the 17-stem RSAT list above.
  4. Copy the matched cabs into
     `<OutputPath>\LanguagesAndOptionalFeatures\<build>\`, preserving
     filenames as-is (so `Add-WindowsCapability -Source` still resolves
     them normally).
  5. Dismount the ISO in a `finally` block so a failure partway through
     never leaves it mounted.
- **Idempotent:** re-running for a given build wipes and rebuilds just that
  build's subfolder; other builds already in `OutputPath` are untouched.
- After processing all ISOs, copies/writes `Install-RSAT.ps1` (script #2,
  checked into this repo, not generated text) into `<OutputPath>\`.
- Result: `RSAT-Install\` containing `Install-RSAT.ps1` and
  `LanguagesAndOptionalFeatures\22621\...`,
  `LanguagesAndOptionalFeatures\26100\...` — nothing else. This whole
  folder is what gets pointed at as MECM package source.

### 2. `Install-RSAT.ps1`

Ships inside `RSAT-Install\`. This is what actually runs on target
machines, in both deployment contexts.

- **OS build match:** reads `CurrentBuildNumber` from
  `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` (online) or from the
  offline hive (WinPE case, see below), and selects the matching
  `LanguagesAndOptionalFeatures\<build>\` subfolder next to itself. If no
  subfolder matches the running build, it fails fast with a clear log
  message rather than guessing.
- **WinPE vs full OS:** detected via presence of
  `HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT`.
  - **WinPE (OSD TS):** target is the offline image, not the boot media.
    Resolves the offline OS drive from the `%OSDTargetSystemDrive%` TS
    variable (via the `Microsoft.SMS.TSEnvironment` COM object — its
    presence is also how the script confirms it's running inside a task
    sequence at all). Reads the offline `CurrentBuildNumber` via
    `Get-ItemPropertyValue` against the offline hive path
    (`<OSDTargetSystemDrive>\Windows\System32\config\SOFTWARE`, loaded
    temporarily with `reg load`). Installs via
    `Get-WindowsCapability -Path <OSDTargetSystemDrive>\` /
    `Add-WindowsCapability -Path <OSDTargetSystemDrive>\`.
  - **Full OS (post-OS TS step, or direct MECM deployment to a
    collection):** `Get-WindowsCapability -Online` /
    `Add-WindowsCapability -Online`.
- **Capability selection:** every capability returned by
  `Get-WindowsCapability` (online or offline, as appropriate) whose `Name`
  matches `Rsat.*` and whose `State` isn't already `Installed`. Not a
  hardcoded list — it installs whatever `Rsat.*` capabilities the target OS
  offers and the matched source folder can satisfy.
- **Run-context-aware output:**
  - TS environment object present → treat as unattended: minimal console
    output, everything meaningful goes to the log file.
  - No TS object, but not an interactive console (e.g. SYSTEM via MECM Run
    Script) → same: quiet, log-file only.
  - Interactive console (a helpdesk tech double-clicked it or ran it in a
    terminal) → prints per-capability progress and a final summary
    (installed / already-present / failed counts) in addition to logging.
  - Always writes a log regardless of mode:
    `C:\Windows\Temp\RSAT-Install\Install-RSAT_<yyyyMMdd-HHmmss>.log`.
- **Elevation check:** verifies running as Administrator (or SYSTEM) up
  front; if not, fails immediately with a clear message rather than letting
  DISM produce a cryptic access-denied error. Skipped implicitly in the
  WinPE/TS case since those always run elevated.
- **Exit codes:**
  - `0` — all applicable capabilities installed (or already present).
  - `3010` — installed, but a component indicated a reboot is needed
    (uncommon for these capabilities, but honored if DISM reports it).
  - `1` — one or more capabilities failed to install; log has details.
  - `2` — no matching `<build>` source subfolder for this OS; nothing
    attempted.
  - `3` — not elevated.

## Testing

Following this repo's existing convention (see
`Projects\MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`), logic gets
factored into named functions inside each script so Pester can exercise it
without touching real hardware:

- `Build-RsatPackage.ps1`: build-number-from-filename parsing, cab
  selection/filtering logic (given a fake file listing) — mocking
  `Mount-DiskImage`/`Dismount-DiskImage` rather than using a real ISO.
- `Install-RSAT.ps1`: WinPE-vs-full-OS detection (mocking the registry
  probe), build-subfolder selection (given a fake directory listing and a
  fake build number), capability filtering (given fake
  `Get-WindowsCapability` output), and exit-code selection logic — mocking
  `Add-WindowsCapability` and the TS COM object entirely.

Neither test file mounts an ISO, calls real DISM, or installs anything —
that path is verified manually against a real machine/TS before handoff to
helpdesk.

## Error handling

- Builder: missing/unreadable ISO, mount failure, zero matching cabs found
  for a build, and output path not writable are all treated as hard stops
  with a clear message — no partial/silent output.
- Installer: every failure mode above has a defined exit code and a log
  entry explaining what was attempted and why it failed, since a helpdesk
  tech (not the author) will be the one looking at a failure.

## Open questions

None blocking. The 17-stem list is static and lives in the builder script;
if a future Windows release adds or renames an RSAT capability, the list
will need a manual update the next time an ISO is refreshed — this is an
accepted maintenance cost in exchange for not depending on the admin
workstation's own capability set at build time.
