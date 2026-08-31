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

function Invoke-Main {
    [CmdletBinding()]
    param(
        [string[]]$IsoPath,
        [string]$OutputPath = (Join-Path $PSScriptRoot 'RSAT-Install')
    )

    $capabilities = Get-RsatCapabilityTable
    $cabStems = @($capabilities | ForEach-Object { $_.CabStem })

    if (-not $IsoPath -or $IsoPath.Count -eq 0) {
        $archiveDir = Join-Path $PSScriptRoot 'media-archive'
        $IsoPath = @(Get-ChildItem -LiteralPath $archiveDir -Filter '*.iso' -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
    }
    if (-not $IsoPath -or $IsoPath.Count -eq 0) {
        throw "No ISO files found under .\media-archive\ and none supplied via -IsoPath."
    }

    $featuresRoot = Join-Path $OutputPath 'LanguagesAndOptionalFeatures'
    New-Item -ItemType Directory -Path $featuresRoot -Force | Out-Null

    $manifestBuilds = @()

    foreach ($iso in $IsoPath) {
        if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) {
            throw "ISO not found: $iso"
        }

        $buildNumber = Get-IsoBuildNumber -IsoFileName $iso
        Write-Host "Processing $(Split-Path $iso -Leaf) (build $buildNumber)..."

        $mount = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop
        try {
            $driveLetter = ($mount | Get-Volume).DriveLetter
            $lofSource = "${driveLetter}:\LanguagesAndOptionalFeatures"
            if (-not (Test-Path -LiteralPath $lofSource -PathType Container)) {
                throw "ISO '$iso' has no LanguagesAndOptionalFeatures folder."
            }

            $cabPaths = Get-RsatCabToCopy -SourceFolder $lofSource -CabStem $cabStems

            $destFolder = Join-Path $featuresRoot $buildNumber
            if (Test-Path -LiteralPath $destFolder) {
                Remove-Item -LiteralPath $destFolder -Recurse -Force
            }
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null

            $copiedNames = foreach ($cabPath in $cabPaths) {
                Copy-Item -LiteralPath $cabPath -Destination $destFolder -Force
                Split-Path -Path $cabPath -Leaf
            }

            Write-Host "  Copied $(@($copiedNames).Count) cabs to $destFolder"

            $manifestBuilds += [PSCustomObject]@{
                Build     = $buildNumber
                SourceIso = (Split-Path -Path $iso -Leaf)
                Cabs      = @($copiedNames)
            }
        }
        finally {
            Dismount-DiskImage -ImagePath $iso | Out-Null
        }
    }

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install-RSAT.ps1')      -Destination $OutputPath -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RsatCapabilities.psd1') -Destination $OutputPath -Force

    $manifest = [PSCustomObject]@{
        GeneratedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Builds       = @($manifestBuilds)
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputPath 'manifest.json') -Encoding UTF8

    Write-Host "Build complete. Output: $OutputPath"
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -IsoPath $IsoPath -OutputPath $OutputPath
}
