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

function Get-RsatBuildSourceMap {
    param(
        [string]$DataFilePath = (Join-Path $PSScriptRoot 'RsatCapabilities.psd1')
    )

    if (-not (Test-Path -LiteralPath $DataFilePath -PathType Leaf)) {
        throw "RSAT capability data file not found: $DataFilePath"
    }

    $data = Import-PowerShellDataFile -LiteralPath $DataFilePath
    if ($data.BuildSourceMap) {
        return [hashtable]$data.BuildSourceMap
    }

    return @{}
}

function Resolve-RsatSourceFolder {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][int]$BuildNumber,
        [hashtable]$BuildSourceMap = @{}
    )

    # An exact <build> subfolder always wins over an alias.
    $exact = Join-Path $PackageRoot "$BuildNumber"
    if (Test-Path -LiteralPath $exact -PathType Container) {
        return $exact
    }

    if ($BuildSourceMap.ContainsKey("$BuildNumber")) {
        $mapped = Join-Path $PackageRoot ([string]$BuildSourceMap["$BuildNumber"])
        if (Test-Path -LiteralPath $mapped -PathType Container) {
            return $mapped
        }
    }

    return $null
}

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

    $buildSourceMap = Get-RsatBuildSourceMap
    $sourceFolder = Resolve-RsatSourceFolder -PackageRoot $packageRoot -BuildNumber $buildNumber -BuildSourceMap $buildSourceMap
    if (-not $sourceFolder) {
        Write-Log "BLOCKED: no RSAT source folder for build $buildNumber under $packageRoot."
        exit (Get-ExitCodeForResult -IsElevated $true -SourceFolderFound $false -FailedCount 0 -RebootRequired $false)
    }
    if ((Split-Path $sourceFolder -Leaf) -ne "$buildNumber") {
        Write-Log "Build $buildNumber has no dedicated source; using aliased folder $(Split-Path $sourceFolder -Leaf)."
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
