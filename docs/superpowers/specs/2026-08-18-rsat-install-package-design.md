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
> **Amendment (2026-08-31 #2):** added a `BuildSourceMap` alias table in
> `RsatCapabilities.psd1`. Microsoft ships one "Languages and Optional
> Features" ISO per release pair — the 22621 ISO covers 22H2 **and** 23H2,
> the 26100 ISO covers 24H2 **and** 25H2 (MS Learn, *Install language packs
> on Windows 11 Enterprise VMs in Azure Virtual Desktop*). So `22631 → 22621`
> and `26200 → 26100`. The installer prefers an exact `<build>\` folder and
> only consults the map as a fallback.
>
> **Amendment (2026-08-31 #3):** the builder no longer parses the OS build
> from the ISO filename — a third LOF ISO
> (`mul_..._version_26h1_..._dvd_....iso`, Windows 11 26H1, build 28000)
> carries no build number in its name. The builder reads the build from a
> cab's own package manifest (`update.mum` — the `10.0.<build>.<revision>`
> version), which is authoritative and filename-independent. Build 28000
> gets its own `28000\` folder.
>
> **Amendment (2026-09-01):** the "language-neutral cabs only" design was
> wrong and is dropped. First real MECM deployment (25H2 / build 26200)
> failed. Diagnosed against DISM/CBS logs on a real machine, in order:
> 1. `0x800f081f` — the ISO's `LanguagesAndOptionalFeatures\metadata\`
>    folder (the FoD Component Database DISM uses to resolve a capability
>    name to its packages) was not copied. Builder now copies it verbatim
>    into every `<build>\`.
> 2. `0x800f0955` (`CBS_E_INVALID_PACKAGE_REQUEST_ON_MULTILINGUAL_FOD`) — the
>    RSAT FoD packages are **multilingual**; installing a capability
>    (`-LimitAccess`, patched OS) needs the cab matching the target's
>    display language present, not just the neutral cab. Builder now copies
>    **every cab for each of the 9 stems — all architectures (amd64, wow64)
>    and all languages** (~286 MB/build, ~860 MB for 3 builds). Verified: a
>    single capability installs cleanly on real 25H2 from a folder holding
>    just its stem's full cab set + `metadata\`; the same folder minus the
>    language cabs fails `0x800f0955`.
>
> A benign side effect: on a machine patched past the ISO's RTM build,
> `-LimitAccess` blocks the LCU-level FoD top-up (`0x800f0912` in CBS.log),
> so RSAT installs at RTM binary level and self-flags for "reservicing" at
> the next cumulative update. Functionally fine for admin tools.
>
> The 2026-08-31 #2 `BuildSourceMap` aliases stand — Microsoft documents the
> 26100 ISO as covering 24H2 **and** 25H2 (and 22621 as covering 22H2 and
> 23H2), and a full-ISO `Add-WindowsCapability` confirmed it works on 25H2.

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
Demand (FOD), so the source content has to come from local media: the
Windows 11 "Languages and Optional Features" ISOs kept in `media-archive\`
(currently 22H2 / build 22621, 24H2 / build 26100, and 26H1 / build 28000).
Each ISO is ~6–7 GB and contains FOD cabs for far more than what is needed —
~4000 cabs covering Notepad, Paint, printing, WSUS tools, every OS feature,
in ~40 languages — so it is not practical to hand the ISO itself to MECM.

This project produces a folder (~286 MB per build, ~860 MB for the three)
that drops straight into an MECM package: every cab for the 9 required
capability stems (all architectures and languages) plus the FoD metadata,
one `<build>` folder per ISO, plus one install script that adapts to
whichever of the two contexts above it is running in.

## Scope

**In scope:**
- A builder script that extracts, from each ISO in `media-archive\`, every
  cab for the 9 required capability stems (all architectures and languages)
  plus the FoD `metadata\` folder, into a deployable output folder.
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
- Any capability not in the fixed list below (but for those 9, *all* their
  cabs — every architecture and language — are in scope; the RSAT FoD is
  multilingual and a neutral-only subset does not install).
- Trimming the shipped languages to a subset (e.g. just the fleet's display
  languages). Possible, but ~286 MB/build is acceptable and shipping them
  all keeps the package locale-agnostic.
- Hyper-V management tooling. Hyper-V management on Windows client is an
  in-box *optional feature* (`Microsoft-Hyper-V-Management-PowerShell` /
  `Microsoft-Hyper-V-Management-Clients`), not a capability, and no
  corresponding cab exists on these LOF ISOs. It is handled separately, if
  at all.
- Producing an ISO deliverable.

## Target capabilities

Exactly these 9. For each, the builder ships **every** cab whose name starts
`<CabStem>~31bf3856ad364e35~` — all architectures (amd64, wow64) and all
languages (neutral + per-locale), ~660 cabs total. The capability-name ↔
cab-stem pairing is a static data table shared by both scripts (the builder
matches cab names by stem prefix, the installer uses the capability names).

| Capability name (DISM)                  | Cab stem (ship every `<stem>~31bf3856ad364e35~*.cab`) |
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

Notes established by ISO inspection and by real `Add-WindowsCapability`
runs on a 25H2 machine:

- The neutral `~amd64~~` cab is the FeaturePackage; `~wow64~~` is a 32-bit
  SatellitePackage (7 of the 9 have one); `~amd64~<lang>~` / `~wow64~<lang>~`
  are the per-language satellites. **All are needed** — the RSAT FoD is a
  multilingual package and DISM rejects a neutral-only source with
  `0x800f0955`.
- The `metadata\` folder (the FoD Component Database) must be shipped too or
  DISM can't resolve the capability name (`0x800f081f`).
- All cross-capability dependencies are satisfied within this 9-item set,
  so nothing pulls in a 10th capability:
  - `Rsat.BitLocker.Recovery.Tools` → `Rsat.ActiveDirectory.DS-LDS.Tools`
  - `Rsat.ActiveDirectory.DS-LDS.Tools` → `Rsat.ServerManager.Tools`
  - `Rsat.FileServices.Tools` → `Rsat.ServerManager.Tools`
  - `Rsat.FailoverCluster.Management.Tools` → `Rsat.FileServices.Tools`
  - the rest declare no cross-capability dependency.
- The cabs' `<parent>` reference is
  `Microsoft-Windows-EditionPack-Professional-Package` with
  `buildCompare="GE" version="0.0.0.0"` — i.e. "requires Windows Pro or
  higher, any build". No version lock; the 26100 cabs are applicable to
  25H2 (confirmed by a real full-ISO install on build 26200).
- The `FailoverCluster-Management-Tools` cab uses an uppercase `FOD` token
  in its filename where the others use `FoD`; cab matching is
  case-insensitive.
- `OpenSSH.Client` ships pre-installed on Windows 11 24H2+, so the installer
  treats "already installed" as success, not re-install.

## Background: how the ISOs are structured

Each ISO has a `LanguagesAndOptionalFeatures\` folder containing ~4000 FOD
cabs named `<Feature>~31bf3856ad364e35~<arch>~<lang>~.cab` — per feature:
a language-neutral `~~.cab`, ~40 per-language `~<lang>~.cab`, and for many
features the same again in a `wow64` (32-bit) architecture flavour. Plus a
`metadata\` subfolder of Component Database `.xml.cab` files. The 9 RSAT
stems account for ~660 of those cabs.

`Add-WindowsCapability -Name <FoD> -Source <folder> -LimitAccess` resolves
the capability name via the CompDB in `<folder>\metadata\`, then installs
the FeaturePackage, the wow64 satellite, and the language satellite matching
the OS display language. Every one of those must be present in `<folder>`
or the install fails (`0x800f081f` with no metadata, `0x800f0955` with a
neutral-only / language-incomplete set).

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
  `CabStem`. The builder matches cab filenames by `<CabStem>~…~` prefix; the
  installer uses the `CapabilityName` values.
- `BuildSourceMap` — a hashtable of `<OS build>` → `<source-folder build>`
  aliases. Microsoft ships one LOF ISO per release pair (the 22621 ISO
  covers 22H2 and 23H2; the 26100 ISO covers 24H2 and 25H2), so
  `22631 → 22621` and `26200 → 26100`. Only the installer reads it; an exact
  `<build>\` folder always wins over an alias.

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
  1. Mount it (`Mount-DiskImage`).
  2. Require `LanguagesAndOptionalFeatures\metadata\` and the neutral
     `~amd64~~` FeaturePackage cab for all 9 capabilities to be present;
     hard stop naming any missing FeaturePackage cab — no partial output.
  3. Read the OS build number from the neutral ServerManager cab's package
     manifest — expand `update.mum` and take the `10.0.<build>.<revision>`
     version
     (the value DISM matches a capability against). This is authoritative
     and independent of the ISO's filename, which need not carry a build
     number at all. No `10.0.*` version in the manifest is a hard stop.
  4. Into `<OutputPath>\LanguagesAndOptionalFeatures\<build>\`, preserving
     the ISO's filename casing: (a) every cab whose name starts
     `<CabStem>~31bf3856ad364e35~` for each of the 9 stems (all
     architectures, all languages — ~660 cabs), and (b) the entire
     `metadata\` folder verbatim. A stem with zero matching cabs is a hard
     stop.
  5. Dismount the ISO in a `finally` block.
- **Idempotent:** re-running for a given build wipes and rebuilds only that
  build's subfolder; other builds in `OutputPath` are untouched.
- After all ISOs: copies `Install-RSAT.ps1` and `RsatCapabilities.psd1`
  (both checked into this repo, not generated) into `<OutputPath>\`, and
  writes `<OutputPath>\manifest.json` recording, per build, the source ISO
  filename, `CabCount`, `ApproxSizeMB`, `MetadataIncluded`, and a UTC
  timestamp.
- **Result:** `RSAT-Install\` = `Install-RSAT.ps1`, `RsatCapabilities.psd1`,
  `manifest.json`, and `LanguagesAndOptionalFeatures\<build>\` per ISO (each
  ~660 cabs + a `metadata\` folder, ~286 MB). This whole folder is the MECM
  package source.

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

All source ISOs live in `Projects/RSAT/media-archive/`, git-ignored
(~6–7 GB each). A short `media-archive/README.md` records what they are and
their build numbers, and that `Build-RsatPackage.ps1` reads every `*.iso`
in this folder by default. The originals are never modified — the builder
mounts them read-only. Adding a new Windows branch is just dropping its LOF
ISO here and re-running the builder; the ISO filename need not follow any
particular format (the build is read from the cab manifests, not the name).

## Testing

Following the repo convention (see
`Projects\MISC-SCRIPTS\Config RS to use SAN-PBI.Tests.ps1`), logic is
factored into named functions each script exposes for dot-sourcing, with a
`if ($MyInvocation.InvocationName -ne '.') { Invoke-Main ... }` guard so
tests never execute the script body.

- `RsatCapabilities.psd1`: a test asserts it loads via
  `Import-PowerShellDataFile`, has exactly 9 entries with non-empty
  `CapabilityName` / `CabStem`, and maps `22631 → 22621` and `26200 → 26100`.
- `Build-RsatPackage.ps1`: build-number-from-package-manifest parsing
  (28000 / 22621 / 26100 style version strings, non-`10.0` versions ignored,
  no version → throw); neutral-FeaturePackage-present check (complete / one
  missing / language+wow64 present but neutral absent still flagged /
  case-variant `FOD`); cab selection returns *every* cab for each stem (all
  arches and languages), casing preserved, unrelated cabs excluded, throws
  when a stem has no cabs.
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

- **Builder:** missing/unreadable ISO, mount failure, a missing
  `LanguagesAndOptionalFeatures\metadata\` folder, any capability's
  `~amd64~~` FeaturePackage cab missing, a cab whose manifest carries no
  `10.0.*` build version, and an unwritable output path are all hard stops
  with a clear message — no partial or silent output.
- **Installer:** every failure mode has a defined exit code and a log entry
  describing what was attempted and why it failed, since a helpdesk tech —
  not the author — will be reading a failure.

## Open questions

None blocking. The 9-capability table lives in one file,
`RsatCapabilities.psd1`; adding/renaming a capability is a deliberate
one-file edit. If a future Windows build ships a cab under a renamed stem,
the builder's FeaturePackage-present check fails loudly rather than
producing a short package.

**Per new Windows release:** obtain its "Languages and Optional Features"
ISO (Microsoft ships one per release pair — check the AVD language-packs doc
for which ISO covers which versions), drop it in `media-archive\`, re-run
the builder, and add a `BuildSourceMap` entry if the release shares an ISO
with another (e.g. a 26H2 build would alias to `28000`). The build-vs-source
match is not just a version check — DISM validates the FoD Component
Database in `metadata\` and the full package set, so **each `<build>\`
folder must be verified with a real `Add-WindowsCapability` on a machine of
that build** before helpdesk handoff.
