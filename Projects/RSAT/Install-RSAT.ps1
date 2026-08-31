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
