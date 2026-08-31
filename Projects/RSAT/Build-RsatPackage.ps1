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

function Get-RsatCabFileName {
    param(
        [Parameter(Mandatory)][string]$CabStem
    )

    return "$CabStem~31bf3856ad364e35~amd64~~.cab"
}

function Find-MissingCabFileName {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AvailableFileName,
        [Parameter(Mandatory)][string[]]$CabStem
    )

    $availableLower = @($AvailableFileName | ForEach-Object { $_.ToLowerInvariant() })

    $missing = foreach ($stem in $CabStem) {
        $expected = Get-RsatCabFileName -CabStem $stem
        if ($availableLower -notcontains $expected.ToLowerInvariant()) {
            $expected
        }
    }

    return @($missing)
}

function Get-RsatCabToCopy {
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string[]]$CabStem
    )

    $available = @(Get-ChildItem -LiteralPath $SourceFolder -Filter '*.cab' -File | ForEach-Object Name)

    $missing = Find-MissingCabFileName -AvailableFileName $available -CabStem $CabStem
    if ($missing.Count -gt 0) {
        throw "Source folder '$SourceFolder' is missing $($missing.Count) required cab(s): $($missing -join ', ')"
    }

    return @($CabStem | ForEach-Object { Join-Path $SourceFolder (Get-RsatCabFileName -CabStem $_) })
}
