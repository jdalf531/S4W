# MPN DTA Tool - Codebase Onboarding

## Project Overview
**MPN DTA Tool** (Don't Copy That Floppy) is a PowerShell-based GUI application for securely transferring files between drives with comprehensive logging, hash verification, and compliance tracking.

## Tech Stack
- **Language**: PowerShell 5.1+
- **UI Framework**: WPF (Windows Presentation Foundation) via XAML
- **Logging**: CSV-based audit trail
- **Security**: SHA-256 hash verification

## Project Structure
```
TransferDriveTool-V3.ps1       # Single-file monolithic application
```

## Key Components

### 1. **UI Framework (XAML)**
- **Theme**: Dark theme (#1E1E1E background, #FFFFFF foreground)
- **Title**: "MPN DTA Tool"
- **Size**: 900x1050 pixels
- **Tabs**: Multiple transfer operations
- **Components**:
  - Text input fields (Source, Destination, Manager, Classification, etc.)
  - Dropdown selectors (Users, Media Type, Scan/Verify options)
  - Progress bar with real-time updates
  - Status log display
  - Control buttons (Run, Close)

### 2. **Core Functions**

#### Configuration & Initialization
- `Get-CommonConfig`: Retrieves user list and paths configuration
- `Initialize-LogFile`: Sets up CSV audit trail with headers:
  - DTAName, Manager, SourceSystem, DestSystem, FileName, Classification, FileSize, Checksum, MediaUsed, Justification, ScanVerify, Timestamp

#### File Transfer Operations
- `Copy-Files`: Main transfer orchestrator
  - Validates inputs (user selection, paths, destination)
  - Creates dated destination folder (YYYYMMDD format)
  - Scans source for files
  - Compares file timestamps (skip if destination is newer/equal)
  
- `Copy-WithRetry`: Handles file copy with retry logic
  - MaxRetries: 3 attempts
  - Resilience against transient failures

#### Verification & Logging
- `Get-FileHashSHA256`: Computes SHA-256 hash for integrity verification
- `Add-CsvLogEntry`: Logs file transfer details with:
  - DTA (Designated Transfer Agent) name
  - Source/destination systems
  - File size, checksum, media type
  - Justification and scan/verify status

#### UI Helpers
- `Update-ProgressUI`: Refreshes progress bar and statistics
- `Write-Status`: Appends messages to status log
- `Set-CurrentFileLabel`: Updates currently processing file display

### 3. **Transfer Workflow**

1. **Input Validation**:
   - User selection required
   - Source path must exist
   - Destination path must be non-empty
   
2. **Preparation**:
   - Create dated destination folder (YYYYMMDD)
   - Initialize file scanner
   - Reset progress UI

3. **File Processing** (per file):
   - Generate relative path
   - Create destination subdirectories
   - Skip logic: If destination is newer or equal timestamp
   - Copy with retry (max 3 attempts)
   - Verify hash (SHA-256 source vs destination)
   - Log entry with all metadata
   
4. **Completion**:
   - Report summary (total, copied, skipped)
   - Display elapsed time

## UI Tab Structure
- **Tab 1**: To Drive (Commercial → Drive)
  - Source path selection
  - Destination path selection
  - User/manager information
  - System classification
  - Media and justification tracking

## Data Persistence
- **Log Format**: CSV
- **Location**: Configured via `Get-CommonConfig` (default likely in script directory)
- **Audit Trail**: Complete record of all transfers for compliance

## Important Behaviors

### Timestamp-Based Skipping
Files are skipped if the destination file has the same or newer timestamp than source. This prevents unnecessary copying and data loss from overwriting newer versions.

### Hash Verification
Every copied file is verified using SHA-256. Mismatches are logged but don't block the operation—they generate a warning.

### Dated Folder Structure
Transfers are organized by date (YYYYMMDD), creating a natural daily checkpoint structure.

## Running the Application

```powershell
# Execute the script (requires PowerShell 5.1+)
.\TransferDriveTool-V3.ps1

# Or with execution policy override
powershell -ExecutionPolicy Bypass -File .\TransferDriveTool-V3.ps1
```

## Common Customization Points

1. **Branding**: Change title and colors in XAML section (lines ~1-75)
2. **Configuration**: Modify `Get-CommonConfig` to adjust default paths and users
3. **Logging**: Update `Initialize-LogFile` headers for additional metadata
4. **UI Fields**: Add new TextBox/ComboBox controls in XAML with corresponding PowerShell handlers
5. **Verification Logic**: Enhance `Copy-WithRetry` or hash verification in transfer loop

## Compliance Features

- **DTA Tracking**: Logs which designated agent performed the transfer
- **Manager Attribution**: Tracks supervising manager
- **System Documentation**: Source and destination system identification
- **Classification Levels**: Support for data classification tracking
- **Justification Logging**: Records business justification for transfers
- **Scan/Verify Status**: Documents any additional verification performed
- **Audit Trail**: Complete CSV record with timestamps

## Potential Enhancements

- [ ] Multi-file selection UI
- [ ] Transfer speed monitoring
- [ ] Retry count customization
- [ ] Email notifications on completion
- [ ] Automatic log cleanup policies
- [ ] Network share support
- [ ] Parallel multi-thread transfers

## Dependencies

- PowerShell 5.1 or later
- .NET Framework 3.5+ (for WPF)
- File system read/write permissions
- Sufficient disk space for transfers

---

**Version**: V3  
**Last Updated**: January 2026
