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
