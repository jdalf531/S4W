# MPN DTA Tool - Secure File Transfer Utility

> **"Don't Copy That Floppy"** - A PowerShell-based GUI application for secure, compliant file transfers between drives with comprehensive logging, hash verification, and audit trails.

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
- [API Reference](#api-reference)
- [Compliance & Auditing](#compliance--auditing)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

The **MPN DTA Tool** is a production-grade file transfer application designed for enterprises requiring secure, auditable file transfers with compliance tracking. Built in PowerShell with a modern WPF interface, it provides:

- ✅ Real-time transfer progress monitoring
- ✅ SHA-256 cryptographic verification
- ✅ Comprehensive CSV audit trails
- ✅ Designated Transfer Agent (DTA) tracking
- ✅ Timestamp-based deduplication
- ✅ Classification and justification logging
- ✅ Automatic retry logic with failure recovery

**Current Version**: V3 (January 2026)

## ✨ Features

### Core Transfer Capabilities
- **Multi-file transfers** with intelligent filtering
- **Retry logic** (up to 3 automatic attempts)
- **Timestamp comparison** to prevent overwriting newer files
- **Recursive directory creation** for complex directory structures
- **Real-time progress tracking** with percentage and file counters

### Security & Verification
- **SHA-256 hash verification** for data integrity
- **Source-to-destination validation** with mismatch detection
- **Read-only source verification** option
- **Classification level tracking** for data sensitivity

### Compliance & Auditing
- **CSV audit logs** with complete transfer metadata
- **DTA identification** - tracks who performed the transfer
- **Manager attribution** - records supervising manager
- **Justification tracking** - documents business reasons
- **Scan/verify status** - records additional verification steps
- **Timestamped entries** - precise operation records
- **System identification** - source and destination tracking

### User Interface
- **Dark theme** professional design (#1E1E1E with blue accents)
- **Tab-based workflow** for different transfer scenarios
- **Live status log** with color-coded messages
- **Progress bar** with detailed statistics
- **Dropdown selectors** for preconfigured users and options
- **Window size**: 900x1050 (resizable)

## 🔧 System Requirements

| Requirement | Specification |
|---|---|
| **OS** | Windows 7+ (Windows 10/11 recommended) |
| **PowerShell** | 5.1 or later |
| **.NET Framework** | 3.5+ (for WPF) |
| **RAM** | 512 MB minimum, 2 GB recommended |
| **Disk Space** | Variable (based on files being transferred) |
| **Permissions** | Read access to source, Write access to destination |

## 📦 Installation

### Method 1: Direct Execution
```powershell
# Clone the repository
git clone https://github.com/jdalf531/S4W.git
cd S4W

# Run with bypass if execution policy is restricted
powershell -ExecutionPolicy Bypass -File .\TransferDriveTool-V3.ps1
```

### Method 2: Scheduled Task (Windows)
Create a scheduled task to run the tool at specific times:
```powershell
# PowerShell (as Administrator)
$scriptPath = "C:\Path\To\TransferDriveTool-V3.ps1"
$taskName = "MPN DTA Tool"

# Create task
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At 02:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -RunLevel Highest
```

### Method 3: Desktop Shortcut
Create a Windows shortcut with:
```
Target: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\TransferDriveTool-V3.ps1"
Start in: C:\Path\To\
```

## 🚀 Quick Start

1. **Launch the application**:
   ```powershell
   .\TransferDriveTool-V3.ps1
   ```

2. **Fill in transfer details**:
   - Select a DTA user from the dropdown
   - Specify source path (e.g., `C:\SourceFiles`)
   - Specify destination path (e.g., `D:\BackupDrive`)
   - Enter manager name
   - Set classification level
   - Choose media type
   - Add justification for the transfer

3. **Execute transfer**:
   - Click "Run" button
   - Monitor progress in real-time
   - Review status log for details

4. **Review audit log**:
   - Check the CSV audit trail for compliance verification
   - Default location: same directory as script

## 📖 Usage

### Basic File Transfer

```powershell
# The UI guides you through this, but the workflow is:
1. Source Path: "C:\Documents\ToTransfer"
2. Destination Path: "E:\BackupDrive"
3. DTA User: [Select from dropdown]
4. Manager: "John Smith"
5. Classification: "Confidential"
6. Justification: "Monthly data backup - Business continuity"
7. Click "Run"
```

### Understanding the Status Log

The status log displays:
- `✓ Prepared dated destination folder: E:\BackupDrive\20250106`
- `✓ Found 156 files to process`
- `⊙ Processing: document.docx (2.3 MB)`
- `✓ Copied and verified: document.docx`
- `⊘ Skipped (destination newer): old_file.txt`
- `✗ Error: permission_denied.pdf - Access denied`
- `Summary: 150 copied, 5 skipped, 1 error in 2m 45s`

### CSV Audit Trail Format

The audit log contains these columns:
```
DTAName, Manager, SourceSystem, DestSystem, FileName, Classification, FileSize, 
Checksum, MediaUsed, Justification, ScanVerify, Timestamp
```

Example entry:
```
jdalf531, John Smith, C:\Documents, E:\BackupDrive, report.xlsx, Confidential, 
2457600, a3f9e8c2d1b5..., USB_DRIVE, "Monthly financial backup", Yes, 2025-01-06 14:32:45
```

## 🏗️ Architecture

### Project Structure
```
S4W/
├── TransferDriveTool-V3.ps1      # Main application (single-file monolithic)
├── ONBOARDING.md                 # Development onboarding guide
├── README.md                      # This file
└── .git/                          # Git repository metadata
```

### Core Components

#### 1. **XAML UI Definition** (Lines 1-300+)
Defines the WPF interface with:
- Main window and grid layout
- Tab control for different workflows
- TextBox and ComboBox controls
- Progress bar and status log
- Control buttons (Run, Close)
- Dark theme styling

#### 2. **Configuration Module**
```powershell
Get-CommonConfig
  ├─ Returns: User list, default paths
  └─ Called: On startup
```

#### 3. **Transfer Engine**
```powershell
Copy-Files (Main orchestrator)
  ├─ Copy-WithRetry (3 attempts)
  ├─ Get-FileHashSHA256 (Verification)
  ├─ Add-CsvLogEntry (Audit logging)
  └─ Update-ProgressUI (Status updates)
```

#### 4. **Logging System**
```powershell
Initialize-LogFile
Add-CsvLogEntry
  └─ Output: CSV audit trail
```

### Data Flow

```
User Input
    ↓
Validation
    ↓
Preparation (Create dated folder, scan source)
    ↓
File Loop:
  ├─ Check timestamps (skip if destination newer)
  ├─ Create destination directories
  ├─ Copy with retry (up to 3 attempts)
  ├─ Verify SHA-256 hash
  ├─ Log to CSV
  └─ Update progress UI
    ↓
Summary Report
    ↓
CSV Audit Trail
```

## 🔌 API Reference

### Core Functions

#### `Copy-Files`
Main transfer orchestrator function.

**Parameters**:
- `$sourceFolder` - Source directory path
- `$destinationFolder` - Destination directory path
- `$dtaName` - Designated Transfer Agent identifier
- `$manager` - Supervising manager name
- `$sourceSystem` - Source system identifier
- `$destSystem` - Destination system identifier
- `$classification` - Data classification level
- `$mediaType` - Transfer media type
- `$justification` - Business justification
- `$scanVerify` - Scan/verify status

**Returns**: `[bool]` - Success/failure status

#### `Copy-WithRetry`
Handles single file copy with automatic retry logic.

**Parameters**:
- `$sourcePath` - File source path
- `$destPath` - File destination path
- `$maxRetries` - Maximum retry attempts (default: 3)

**Returns**: `[bool]` - Copy success status

#### `Get-FileHashSHA256`
Computes SHA-256 hash for a file.

**Parameters**:
- `$filePath` - Path to file

**Returns**: `[string]` - Hexadecimal hash value

#### `Initialize-LogFile`
Creates and initializes the CSV audit log.

**Parameters**:
- `$logPath` - Output log file path

**Returns**: `[string]` - Full path to created log

#### `Add-CsvLogEntry`
Appends a single transfer record to the audit log.

**Parameters**:
- `$logPath` - Log file path
- `$dtaName`, `$manager`, `$classification`, ... - Metadata fields

**Returns**: None

#### `Update-ProgressUI`
Refreshes the progress bar and statistics display.

**Parameters**:
- `$current` - Current file count
- `$total` - Total files
- `$copied` - Files successfully copied
- `$skipped` - Files skipped

**Returns**: None

### Configuration Functions

#### `Get-CommonConfig`
Retrieves application configuration.

**Returns**: `[hashtable]` with keys:
```powershell
@{
    UserList = @("User1", "User2", "User3")
    DefaultPath = "C:\Transfers"
}
```

## 📋 Compliance & Auditing

### DTA (Designated Transfer Agent) Tracking
Every transfer is attributed to a specific user (DTA) from the preconfigured user list. This enables accountability and traceability.

### Manager Attribution
Transfers are attributed to a supervising manager, establishing an audit chain of responsibility.

### Data Classification
Supports multiple classification levels:
- **Public** - Unrestricted data
- **Internal** - Company-internal use only
- **Confidential** - Restricted to authorized personnel
- **Restricted** - Highest sensitivity level

### Timestamp-Based Deduplication
Files are automatically skipped if the destination already has an equal or newer version. This prevents:
- Unnecessary duplication
- Overwriting newer data
- Bandwidth waste

### Hash Verification
Every file receives SHA-256 verification:
- Computed immediately after copy
- Compared against source
- Logged for audit trail
- Mismatches generate warnings (non-blocking)

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
# Check current policy
Get-ExecutionPolicy

# For current process only (temporary)
powershell -ExecutionPolicy Bypass -File .\TransferDriveTool-V3.ps1

# To set permanently (requires admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: WPF Window Won't Display

**Cause**: Missing .NET Framework or WPF components

**Solution**:
```powershell
# Check .NET installation
Get-NetFrameworkVersion  # Requires .NET 3.5+

# On Windows 10/11, enable via:
# Settings > Apps > Apps and Features > Optional features
# Search for ".NET Framework 3.5" and install
```

### Issue: Hash Mismatch Warnings

**Cause**: File modified during transfer or network corruption

**Solution**:
- Review the CSV log for affected files
- Retry the transfer
- If persistent, verify source file integrity
- Check destination disk for errors

### Issue: Slow Transfer Speed

**Cause**: 
- Network/disk I/O bottleneck
- Antivirus scanning
- System resource contention

**Solution**:
- Temporarily exclude folder from antivirus scan
- Run during off-peak hours
- Check disk health: `chkdsk E: /F` (with /F requires reboot)
- Monitor Task Manager for resource usage

## 🤝 Contributing

This is a proprietary tool. For bug reports or enhancement requests, contact the development team.

### Development Setup

See [ONBOARDING.md](ONBOARDING.md) for detailed development documentation including:
- Code structure
- Function references
- Customization points
- Enhancement guidelines

## 📄 License

This software is proprietary and confidential. Unauthorized copying, modification, or distribution is prohibited.

---

## 📞 Support & Contact

For issues, questions, or feature requests, please contact the development team.

**Project**: MPN DTA Tool (Don't Copy That Floppy)  
**Repository**: https://github.com/jdalf531/S4W  
**Last Updated**: January 2026  
**Maintainer**: Justin Dobson
