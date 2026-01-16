# Daily App Update Script (DailyAppUpdatev2.ps1)

## Overview

The **DailyAppUpdatev2.ps1** script is an automated PowerShell application designed to download and manage the latest versions of enterprise software using the Evergreen module. It intelligently fetches stable, offline-capable installers while maintaining version control and a clean file system.

## Features

### Core Functionality
- **Automated Downloads**: Pulls the latest stable versions of 17 popular enterprise applications
- **Version Awareness**: Skips downloads if the latest version is already present
- **File Verification**: Ensures actual files exist before skipping (re-downloads if folder is cleaned)
- **Stub Installer Detection**: Automatically filters out web/stub installers under 1 MB
- **Archive Management**: Maintains up to 2 historical versions of each application
- **Uniform Naming**: Standardized file naming convention for easy identification and sorting

### Installer Preferences
The script prioritizes installers in this order:
1. **MSI x64** (preferred for enterprise deployment)
2. **MSI x86** (fallback)
3. **EXE x64** (if MSI unavailable)
4. **EXE x86** (last resort)

### Release Filtering
Automatically excludes beta, preview, EA (Early Access), nightly, and development releases, ensuring only stable versions are downloaded.

## Prerequisites

### System Requirements
- Windows PowerShell 5.1 or later
- Administrator privileges (for module installation and network access)
- Network connectivity

### Required Modules
- **Evergreen** - PowerShell module for retrieving application versions
  
  Install with:
  ```powershell
  Install-Module -Name Evergreen -Force
  ```

## Installation & Setup

### 1. Create Folder Structure
The script will automatically create these directories if they don't exist:
```
C:\Viper\DTA\Daily\
├── (Downloaded installers)
├── Archive\            (Historical versions)
└── Metadata\           (Version tracking JSON files)
```

To customize paths, edit these lines in the script:
```powershell
$DownloadPath  = "C:\Viper\DTA\Daily"
$ArchivePath   = "C:\Viper\DTA\Daily\Archive"
$MetadataPath  = "C:\Viper\DTA\Daily\Metadata"
$LogFile       = "C:\Viper\DTA\Daily\UpdateLog.txt"
```

### 2. Configure Applications
Edit the `$AppMap` and `$ManualAppMap` hashtables to customize which applications are downloaded:

#### Evergreen Applications (Auto-detected versions)
```powershell
$AppMap = @{
    "7zip"                      = "7zip"
    "AdobeAcrobatReaderDC"      = "AcrobatReader"
    "GoogleChrome"              = "Chrome"
    "MicrosoftEdge"             = "Edge"
    "MicrosoftPowerToys"        = "MPT"
    "MozillaFirefox"            = "Firefox"
    "NotepadPlusPlus"           = "NotepadPP"
    "VideoLanVlcPlayer"         = "VLC"
    "Npcap"                     = "Npcap"
    "OracleJava8"               = "Java8"
    "GitForWindows"             = "Git"
    "MicrosoftPowerShell"       = "PowerShell"
    "MicrosoftVisualStudioCode" = "VSCode"
    "PSAppDeployToolkit"        = "PSADT"
    "Python"                    = "Python"
    "PuTTy"                     = "PuTTy"
    "Wireshark"                 = "Wireshark"
    "YubicoAuthenticator"       = "YubiKey"
}
```

#### Manual Applications (Manual URLs)
```powershell
$ManualAppMap = @{
    "ElasticAgent" = "https://www.elastic.co/downloads/elastic-agent"
    "KeePass"      = "https://keepass.info/download.html"
}
```

### 3. Schedule Execution
#### Option A: Windows Task Scheduler
1. Open Task Scheduler
2. Create Basic Task
3. Set trigger (Daily at desired time, e.g., 2:00 AM)
4. Set action: `powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\DailyAppUpdatev2.ps1"`
5. Set to run with highest privileges

#### Option B: PowerShell Scheduled Job
```powershell
$trigger = New-JobTrigger -Daily -At 2:00am
Register-ScheduledJob -Name "DailyAppUpdate" -ScriptBlock {
    & "C:\Path\To\DailyAppUpdatev2.ps1"
} -Trigger $trigger
```

## Usage

### Manual Execution
```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Path\To\DailyAppUpdatev2.ps1"
```

### With Logging
Logs are automatically written to the configured `$LogFile`. Monitor progress with:
```powershell
Get-Content "C:\Viper\DTA\Daily\UpdateLog.txt" -Tail 20
```

## File Naming Convention

Downloaded files follow a standardized naming pattern for consistency and sorting:

```
<AppName>-<Version>-<Architecture>.<Extension>
```

### Examples
- `Chrome-132.0.0.0-x64.exe`
- `NotepadPP-8.6.2-x64.msi`
- `Firefox-133.0-x64.msi`
- `VSCode-1.95.3-x64.exe`

**Benefits:**
- Alphabetical sorting groups applications
- Version is immediately visible
- Architecture (x86/x64) is explicit
- Easy to identify duplicates

## Folder Structure

```
C:\Viper\DTA\Daily\
│
├── DailyAppUpdatev2.ps1           (This script)
│
├── Chrome-132.0.0.0-x64.exe       (Downloaded installers)
├── Firefox-133.0-x64.msi
├── NotepadPP-8.6.2-x64.msi
├── ...
│
├── Archive/
│   ├── Chrome-131.0.0.0-x64.exe_20260115_140530    (Previous version)
│   ├── Chrome-130.0.0.0-x64.exe_20260108_143022    (Older version)
│   └── ...
│
├── Metadata/
│   ├── Chrome.json                (Version tracking)
│   ├── NotepadPP.json
│   └── ...
│
└── UpdateLog.txt                  (Execution log)
```

## Version Tracking

The script maintains metadata for each application in `Metadata\` folder:

### Example: Chrome.json
```json
{
  "Version": "132.0.0.0",
  "FileName": "Chrome-132.0.0.0-x64.exe",
  "Updated": "2026-01-16T14:05:30.1234567"
}
```

**Purpose:**
- Prevents re-downloading unchanged versions
- Enables quick version comparison
- Tracks when each application was last updated

## Log Output

The script generates detailed logs with timestamps:

```
2026-01-16 14:00:00 - ===== Viper Evergreen Update Run Started =====
2026-01-16 14:00:01 - Evergreen module imported.
2026-01-16 14:00:02 - Evergreen catalog updated.
2026-01-16 14:00:03 - Processing Evergreen app: GoogleChrome
2026-01-16 14:00:15 - Downloading Chrome from https://... (version 132.0.0.0)
2026-01-16 14:00:45 - Downloaded Chrome-132.0.0.0-x64.exe successfully
2026-01-16 14:01:00 - Updated metadata for Chrome to version 132.0.0.0
2026-01-16 14:05:30 - ===== Viper Evergreen Update Run Completed =====
```

## Behavior Details

### Download Decision Logic
```
1. Check if latest version matches stored metadata AND file exists
   ├─ YES: Skip download (already up-to-date)
   └─ NO: Continue

2. Filter for stable releases (exclude beta/preview/dev)

3. Find installer using preference order (MSI x64 → MSI x86 → EXE x64 → EXE x86)

4. Download to temporary file

5. Verify file size (must be > 1 MB)

6. Archive existing version (keep 2 historical versions)

7. Move to final location

8. Update metadata
```

### Archive Management
- When a new version is downloaded, the previous version is moved to the Archive folder
- Only the 2 most recent versions are retained per application
- Older archives are automatically deleted
- Timestamped format: `AppName-Version-Architecture.ext_YYYYMMDD_HHMMSS`

### File Replacement
If the download folder is emptied but metadata remains, the script will:
- Detect the missing file
- Re-download the application fresh
- No manual metadata cleanup required

## Troubleshooting

### Issue: "Evergreen module not found"
**Solution:**
```powershell
Install-Module -Name Evergreen -Force -Scope CurrentUser
```

### Issue: Downloads failing with network errors
**Solution:**
- Check network connectivity
- Verify firewall rules allow outbound HTTPS
- Check log file for specific URL errors
- Run script with `-Verbose` flag for detailed output

### Issue: Permission denied errors
**Solution:**
- Run PowerShell as Administrator
- Verify write permissions on `C:\Viper\DTA\` folder
- Check NTFS permissions on destination folder

### Issue: Script runs but downloads nothing
**Possible causes:**
1. All applications already at latest version
2. Network connectivity issues
3. Evergreen catalog needs update (run manually: `Update-Evergreen`)
4. Permissions issue preventing metadata write

**Debug steps:**
1. Check `UpdateLog.txt` for error messages
2. Run: `Get-EvergreenApp -Name "GoogleChrome"` to test Evergreen
3. Verify metadata folder permissions

### Issue: Slow downloads
**Optimization tips:**
- Reduce application list to essentials
- Schedule during off-hours
- Consider network bandwidth throttling requirements
- Monitor `UpdateLog.txt` for slow URL sources

## Best Practices

1. **Monitor the Log**: Regularly review `UpdateLog.txt` for errors or anomalies
   
2. **Backup Metadata**: Keep a backup of the `Metadata\` folder to preserve version history

3. **Archive Retention**: Consider increasing `Select-Object -Skip 2` limit if you need longer history

4. **Test Installers**: Periodically verify downloaded installers by running them in a test environment

5. **Network Bandwidth**: If bandwidth is limited, consider disabling less-critical applications

6. **Scheduling**: Schedule during maintenance windows to avoid impacting user productivity

## Performance Considerations

| Metric | Typical Value |
|--------|---------------|
| Time to download 18 apps | 5-15 minutes |
| Network bandwidth per run | 1-3 GB (varies by versions) |
| Disk space required | 20-50 GB (with archives) |
| Log file growth | ~5-10 KB per run |

## Support for Evergreen Applications

The script officially supports the following applications via the Evergreen module:

| Application | Short Name |
|-------------|-----------|
| 7-Zip | 7zip |
| Adobe Acrobat Reader DC | AcrobatReader |
| Google Chrome | Chrome |
| Microsoft Edge | Edge |
| Microsoft PowerToys | MPT |
| Mozilla Firefox | Firefox |
| Notepad++ | NotepadPP |
| VLC Media Player | VLC |
| Npcap | Npcap |
| Oracle Java 8 | Java8 |
| Git for Windows | Git |
| Microsoft PowerShell | PowerShell |
| Visual Studio Code | VSCode |
| PS App Deployment Toolkit | PSADT |
| Python | Python |
| PuTTY | PuTTy |
| Wireshark | Wireshark |
| Yubico Authenticator | YubiKey |

## License & Notes

- **Author**: SCCM/MECM Administrator
- **Last Modified**: 2026-01-05
- **Evergreen Module**: https://github.com/evergreen-releases/evergreen

## Changelog

### v2.0
- Implemented uniform file naming convention (AppName-Version-Architecture)
- Added file existence verification to prevent false skips on empty folders
- MSI-first preference order for enterprise deployments
- Improved archive management with timestamp tracking
- Enhanced logging with detailed version tracking

### v1.0
- Initial release with Evergreen integration
- Basic download and archival functionality

---

**Last Updated**: January 16, 2026
