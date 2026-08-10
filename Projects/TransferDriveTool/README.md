# MPN DTA Tool - Secure File Transfer Utility

> A PowerShell/WPF GUI for moving files between an offline "Commercial" system, a physical transfer drive, and the MPN network, with resumable transfers, hash verification, and a full compliance audit trail.

![License](https://img.shields.io/badge/license-Proprietary-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue)
![Status](https://img.shields.io/badge/status-Production-green)

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Architecture](#architecture)
- [Function Reference](#function-reference)
- [Compliance & Auditing](#compliance--auditing)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

The **MPN DTA Tool** moves files across an air-gapped boundary in two legs:

1. **Commercial → Drive** — copies files from a local "Viper" source folder onto a physical transfer drive, organized into a dated folder per run.
2. **Drive → MPN** — copies files from that same transfer drive onto the MPN network share.

The same machine is never expected to do both: at launch, the tool detects whether it's domain-joined and only loads the relevant tab —

- **Not domain-joined** (a commercial-side box) → only the **Commercial → Drive** tab loads.
- **Domain-joined to a domain starting with `EUR`** (an MPN-side box) → only the **Drive → MPN** tab loads.
- Any other domain → the tool refuses to start and shows an error, rather than guessing.

This avoids the tool ever probing a network share it has no business reaching on a given machine.

Core guarantees:

- ✅ The UI stays responsive during a transfer — copying runs on a background thread, not the UI thread.
- ✅ Large files resume from where they left off after a network drop, an app restart, or even a crash overnight — no re-copying from byte zero.
- ✅ Every file is SHA-256 hash-verified before it's considered "copied."
- ✅ Every copy is logged to a CSV audit trail with DTA identity, classification, and justification.
- ✅ Data older than a week is automatically swept into an `Archive` subfolder so old data doesn't clutter the working folders or get re-pushed to MPN.

**Current Version**: V3

## ✨ Features

### Core Transfer Capabilities
- **Two dedicated workflows** (Commercial → Drive, Drive → MPN), auto-selected by machine domain at launch.
- **Preset users** per workflow, each with fixed Source/Destination paths, selectable from a dropdown.
- **Folder Browse buttons** on every Source/Destination field to pick a path manually.
- **Dated destination folders** (`yyyyMMdd`) — every run's output lands in its own dated folder, never mixed with a previous day's.
- **Drive → MPN mirrors the drive's own dated folders** — rather than always writing to "today," each of the drive's per-day folders is copied to a same-named folder on the MPN side. A same-day re-run that finds new or changed files for a date that's already been delivered never touches the existing folder — it lands only the new/changed files in an incrementally-numbered sibling (`<date>-1`, `<date>-2`, ...), determined by SHA256 comparison against everything already delivered for that date.
- **Timestamp comparison** — a file is skipped if the destination copy is already the same age or newer than the source.
- **Non-blocking transfers** — the copy loop runs on a background PowerShell runspace; the window stays responsive (movable, resizable, and the Close button works) throughout, even on a slow multi-gigabyte network copy.
- **Resumable, chunked copy engine** — copies in 4 MB chunks via a temporary `.partial` file; if interrupted, the *next* attempt resumes from the last completed chunk instead of restarting the whole file. Resume works:
  - across automatic retries within the same run,
  - across closing and relaunching the app,
  - across a midnight boundary (a 7-day lookback finds and adopts a `.partial` left in a previous day's dated folder).
- **Automatic retry with backoff** on a failed chunk: retries at 2s, 5s, 15s, 30s, then every 60s, up to 15 attempts, before giving up on that file and moving to the next.

### Security & Verification
- **SHA-256 hash verification**, computed incrementally while the file is copied (no separate full read-through pass), then confirmed against the written destination file.
- **Atomic, safe writes** — a file is written to `<name>.partial` and only renamed onto the real destination filename once its hash is verified; the real destination is never left in a half-written state.
- **Classification level tracking** for data sensitivity, recorded on every transfer.

### Automatic Archiving (Commercial mode only)
- **Drive-side sweep**: dated folders on the transfer drive older than 1 week are moved into an `Archive` subfolder under that user's folder.
- **Source-side sweep**: items in the local Viper source folder are archived once **both** their creation date and modified date are more than a week old — a file just copied in (which keeps its original modified date) isn't mistaken for something stale.
- **Archive folders are excluded** from every transfer scan, so archived data is never re-copied or re-pushed to MPN.
- Both sweeps run once, automatically, at launch.

### Compliance & Auditing
- **CSV audit logs** with complete transfer metadata (see [CSV Audit Trail Format](#csv-audit-trail-format)).
- **DTA identification** — tracks who performed the transfer.
- **Manager attribution** — records the supervising manager.
- **Justification tracking** — documents the business reason for the transfer.
- **Scan/verify status** — records additional verification steps.
- **Timestamped entries**, sequentially numbered per calendar year.

### User Interface
- **Dark theme** with a domain-appropriate tab shown automatically (the other tab is hidden, not just disabled).
- **Dual progress display** — an overall "files done / total" bar, plus a second bar showing the current file's byte progress (useful for a single very large file).
- **Live status log**, mirrored to a persistent log file on disk.
- **Window size**: 900×1050 (resizable), console window hidden on launch (it's a GUI tool).

## 🔧 System Requirements

| Requirement | Specification |
|---|---|
| **OS** | Windows 7+ (Windows 10/11 recommended) |
| **PowerShell** | Windows PowerShell 5.1 |
| **.NET Framework** | 3.5+ (for WPF and `System.Windows.Forms`) |
| **RAM** | 512 MB minimum, 2 GB recommended |
| **Disk Space** | Variable (based on files being transferred) |
| **Permissions** | Read access to source, write access to destination |
| **Network** | A machine running the Drive → MPN tab must be domain-joined to a domain starting with `EUR` and able to reach the MPN share |

## 📦 Installation

### Method 1: Direct Execution
```powershell
# Clone the repository
git clone https://github.com/jdalf531/S4W.git
cd S4W/TransferDriveTool

# Run with bypass if execution policy is restricted
powershell -ExecutionPolicy Bypass -File .\TransferDriveTool-V3.ps1
```

The tool can also be run directly from a read-only external/removable drive — nothing it writes depends on the location of the script itself.

### Method 2: Scheduled Task (Windows)
```powershell
# PowerShell (as Administrator)
$scriptPath = "C:\Path\To\TransferDriveTool-V3.ps1"
$taskName = "MPN DTA Tool"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 02:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -RunLevel Highest
```

### Method 3: Desktop Shortcut
```
Target: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\TransferDriveTool-V3.ps1"
Start in: C:\Path\To\
```

## 🚀 Quick Start

1. **Launch the application** — the console window hides itself automatically, and only the tab relevant to this machine (Commercial → Drive, or Drive → MPN) will be visible.

2. **Fill in transfer details**:
   - Select a DTA user from the dropdown (auto-fills Source/Destination), or use the **Browse** buttons to pick paths manually.
   - Enter manager name, classification, media used, and justification.

3. **Execute transfer**:
   - Click **Run**. Run and Close are disabled while a transfer is in progress and re-enable automatically when it finishes.
   - Watch both progress bars and the live status log.

4. **Review the audit log**:
   - Commercial → Drive tab: `E:\DTA\Logging\DataTransferLog.csv`
   - Drive → MPN tab: `C:\VIPER\DTA\DataTransferLog.csv`

## 📖 Usage

### Understanding the Status Log

A typical run looks like:
```
[2026-07-10 10:21:19] Archive sweep: scanning drive folders for dated folders older than 1 week...
[2026-07-10 10:21:19] Drive archive sweep complete. 0 folder(s) archived.
[2026-07-10 10:21:20] Loaded preset for Ben
[2026-07-10 10:21:20] Starting transfer...
[2026-07-10 10:21:20] Creating destination folder: E:\DTA\Ben\20260710
[2026-07-10 10:21:20] Scanning source files for changes...
[2026-07-10 10:21:21] (skip) File exists (destination newer/same): old_report.docx
[2026-07-10 10:21:22] Copied and hash-verified: report.xlsx
[2026-07-10 10:21:22] Logged: report.xlsx
[2026-07-10 10:21:23] Transfer complete.
[2026-07-10 10:21:23] Summary: Total=2, Copied=1, Skipped=1, Elapsed=00:00:02.97
```

If a copy is interrupted and resumed later, you'll also see:
```
[2026-07-10 10:22:05] Adopting orphaned partial copy for report.xlsx (resuming across a day boundary)
```

### CSV Audit Trail Format

The audit log header (both tabs use the same columns):
```
LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification
```

Example entries:
```
"2026-014","jdalf531","John Smith","2026-07-10 14:32Z","C:\Viper\DTA\Ben","E:\DTA\Ben","report.xlsx","Confidential","2,400 KB","A3F9E8C2D1B5...","USB_DRIVE","Monthly financial backup","Yes"
"2026-015","jdalf531","John Smith","2026-08-07 09:10Z","E:\DTA\Kevin","\\mpn-share\Kevin","20260807-1\new_file.txt","Confidential","12 KB","B7A1...","USB_DRIVE","Same-day follow-up delivery","Yes"
```

## 🏗️ Architecture

### Project Structure
```
S4W/
└── TransferDriveTool/
    ├── TransferDriveTool-V3.ps1   # Main application (single-file, monolithic by design)
    ├── ONBOARDING.md              # Development onboarding guide
    └── README.md                  # This file
```

The tool is deliberately kept as a single `.ps1` file — it's copied directly onto commercial-side and MPN-side machines, including read-only removable drives, and shouldn't depend on a second file being present alongside it.

### Data Flow

```
Launch
    ↓
Detect domain → pick ToolMode (Commercial / MPN) → hide the other tab
    ↓
[Commercial mode only] Archive sweep (drive + source, >1 week old)
    ↓
User fills in fields, clicks Run
    ↓
Validate inputs, scan source files, snapshot UI values
    ↓
Disable Run/Close, hand the file list to a background runspace
    ↓
Background runspace, per file:
  ├─ Check for an orphaned .partial from a prior day (adopt if it matches)
  ├─ Skip if destination is already newer/equal
  ├─ Copy-FileResumable (chunked, resumable, hash-verified)
  ├─ Add-CsvLogEntry
  └─ Report progress back to the UI thread
    ↓
Completion timer detects the runspace finished (or force-recovers on a stall)
    ↓
Re-enable Run/Close, show summary
```

Drive → MPN (Tab 2) resolves and executes in two phases instead of a single flat scan:

```
Background runspace:
  Phase 1 - Resolve-DriveToMpnCopyPlan, per dated folder on the drive:
    ├─ List existing <date> / <date>-1 / <date>-2 ... folders on the MPN side
    ├─ Hash their completed files (skip stray .partial / .partial.meta)
    ├─ Diff against the drive's current dated folder (SHA256 compare)
    └─ AlreadyDelivered (nothing new) | Copy (allocate next free suffix) | Error
    ↓
  Phase 2 - Invoke-DriveToMpnDeliveryPlan:
    For each Copy entry: create the target folder, copy each new file
    (Copy-FileResumable, same as Tab 1), Add-CsvLogEntry, report progress
```

## 🔌 Function Reference

#### `Copy-Files`
Main transfer orchestrator, called from the Run button. Validates inputs, scans the source folder, snapshots the UI fields needed for logging, then builds and starts a background PowerShell runspace to run the actual transfer loop, reporting progress back to the UI thread. Includes a completion timer that re-enables the UI when the background work finishes, and force-recovers it after a 10-minute stall as a safety net.

#### `Copy-FileResumable`
```powershell
Copy-FileResumable -Source <path> -Destination <path> [-ChunkSizeBytes <int> = 4MB] [-ProgressCallback <scriptblock>] [-RetryDelaySeconds <int[]> = @(2,5,15,30,60)] [-MaxAttempts <int> = 15]
```
Copies a single file in chunks via a `<Destination>.partial` file, hashing the source incrementally as it reads. Only renames `.partial` onto the real destination once the copy is complete and its hash is verified. Returns `[PSCustomObject]@{ Success; SourceHash; DestHash; Error }`. A sidecar `<Destination>.partial.meta` records the source's length and modified time so an interrupted copy can resume later, even across an app restart.

#### `Add-CsvLogEntry`
Appends one row to the CSV audit trail (path depends on the active tab — see [Quick Start](#quick-start)) with a sequential per-year log number.

#### `Invoke-DriveArchiveSweep` / `Invoke-SourceArchiveSweep`
Run once at launch in Commercial mode. Move dated drive folders and stale local source items (respectively) older than 1 week into an `Archive` subfolder, which is then excluded from all future transfer scans.

#### `Resolve-DriveToMpnCopyPlan`
```powershell
Resolve-DriveToMpnCopyPlan -DriveUserRoot <path> -DestUserRoot <path> [-MaxSuffix <int> = 50]
```
Drive → MPN only. For each dated folder on the drive, hashes every existing `<date>[-N]` folder already on the MPN side and diffs against the drive's current content to decide whether that date is already fully delivered, needs a fresh `<date>[-N]` folder for its new/changed files, or hit an error allocating one (e.g. all 50 suffixes in use). Returns one plan entry per dated folder; never modifies anything itself.

#### `Invoke-DriveToMpnDeliveryPlan`
```powershell
Invoke-DriveToMpnDeliveryPlan -Plan <object[]> -CsvLogPath <path> -LogSnapshot <object> -TotalFiles <int> [-OnStatus <scriptblock>] [-OnFileStart <scriptblock>] [-OnFileProgress <scriptblock>] [-OnFileComplete <scriptblock>]
```
Executes the `Copy` entries from a `Resolve-DriveToMpnCopyPlan` plan: creates each target folder, copies its files via `Copy-FileResumable`, and logs each success via `Add-CsvLogEntry` with the target folder name prefixed onto the logged file name (e.g. `20260807-1\report.txt`).

#### `Show-FolderBrowser`
```powershell
Show-FolderBrowser -InitialPath <string>
```
Opens a `System.Windows.Forms.FolderBrowserDialog` pre-populated with the given path if valid, and returns the chosen folder (or `$null` on Cancel). Backs all four Browse buttons.

#### `Write-Status`
Appends a timestamped line to the on-screen status log and to the persistent log file at `C:\VIPER\DTA\TransferLog_<timestamp>.txt`. Used for UI-thread messages; the background runspace uses its own `Write-BackgroundStatus`, which marshals the same append back onto the UI thread.

## 📋 Compliance & Auditing

### DTA (Designated Transfer Agent) Tracking
Every transfer is attributed to a specific user (DTA) from the preconfigured user list, enabling accountability and traceability.

### Manager Attribution
Transfers are attributed to a supervising manager, establishing an audit chain of responsibility.

### Data Classification
Classification is a free-text field entered per transfer (e.g. Public, Internal, Confidential, Restricted) and recorded in the CSV audit trail.

### Timestamp-Based Deduplication
Files are automatically skipped if the destination already has an equal or newer version, preventing unnecessary duplication, overwriting newer data, and wasted transfer time.

### Hash Verification
Every file receives SHA-256 verification, computed while copying and confirmed against the finished destination file, before it's logged as copied. A mismatch discards the attempt and retries rather than logging a bad copy.

## 🔍 Troubleshooting

### Issue: "Access Denied" Errors

**Cause**: Insufficient permissions on source or destination

**Solution**:
```powershell
# Run PowerShell as Administrator
# Verify read access to source
Get-Item -Path "C:\SourcePath" -ErrorAction Stop
# Verify write access to destination
New-Item -Path "D:\Dest" -ItemType Directory -Force
```

### Issue: Script Won't Execute

**Cause**: ExecutionPolicy is Restricted

**Solution**:
```powershell
Get-ExecutionPolicy
powershell -ExecutionPolicy Bypass -File .\TransferDriveTool-V3.ps1
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: "This machine's domain is not recognized" error on launch

**Cause**: The machine is domain-joined to a domain that doesn't start with `EUR`, and isn't a non-domain-joined commercial box either — the tool refuses to guess which workflow applies.

**Solution**: Contact IT to confirm which workflow this machine should run; the tool is only meant to run on a commercial (non-domain) box or a `EUR*`-domain box.

### Issue: A transfer seems stuck / Close doesn't respond

**Cause**: The background transfer thread hasn't signaled completion.

**Solution**: Wait — after 10 minutes with no progress, the tool automatically force-recovers the UI, attempts to stop the stalled transfer, and logs a warning. If this happens, manually verify the destination files, since the transfer's true state at that point is unknown.

### Issue: Hash Mismatch Warnings

**Cause**: File modified during transfer, or network/disk corruption.

**Solution**: The tool automatically retries on a mismatch; if it still fails after all retries, review the status log for the affected file and verify source file integrity.

### Issue: Slow Transfer Speed

**Cause**: Network/disk I/O bottleneck, antivirus scanning, or system resource contention.

**Solution**: Temporarily exclude the folder from antivirus scanning, run during off-peak hours, and check disk health.

## 🤝 Contributing

This is a proprietary tool. For bug reports or enhancement requests, contact the development team.

### Development Setup

See [ONBOARDING.md](ONBOARDING.md) for development documentation.

## 📄 License

This software is proprietary and confidential. Unauthorized copying, modification, or distribution is prohibited.

---

## 📞 Support & Contact

For issues, questions, or feature requests, please contact the development team.

**Project**: MPN DTA Tool
**Repository**: https://github.com/jdalf531/S4W
**Maintainer**: Justin Dobson
