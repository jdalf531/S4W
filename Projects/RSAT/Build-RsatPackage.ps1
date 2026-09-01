<#
.SYNOPSIS
    Extracts the fixed set of RSAT, BitLocker admin, and OpenSSH-client
    Features-on-Demand cabs from the archived Windows 11 client LOF OEM ISOs
    into a self-contained folder for MECM deployment.
.DESCRIPTION
    Mounts each ISO under .\media-archive\ read-only, then for each of the 9
    capabilities in RsatCapabilities.psd1 copies its language-neutral cabs -
    the required ~amd64~~ FeaturePackage cab AND, where the ISO carries one,
    the ~wow64~~ SatellitePackage cab (7 of the 9 have one; DISM needs both
    or the install fails 0x800f081f). It also copies the ISO's
    LanguagesAndOptionalFeatures\metadata\ folder verbatim - the Component
    Database DISM uses to resolve a capability name to its packages. The OS
    build is read from a cab's own package manifest (the 10.0.<build>.<rev>
    version), so the ISO filename format does not matter. Output goes to
    <OutputPath>\LanguagesAndOptionalFeatures\<build>\ (mirroring the ISO
    layout); Install-RSAT.ps1 and RsatCapabilities.psd1 are copied into
    <OutputPath>\ and a manifest.json is written. Run manually on an admin
    workstation whenever an ISO is added or refreshed; not part of the
    deployed package.
.NOTES
    Modified: 2026-09-01
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

function Get-BuildFromPackageManifest {
    param(
        [Parameter(Mandatory)][string]$ManifestXml
    )

    $match = [regex]::Match($ManifestXml, 'version="10\.0\.(?<build>\d+)\.\d+"')
    if ($match.Success) {
        return [int]$match.Groups['build'].Value
    }

    throw "Could not find a 10.0.<build>.<revision> version in the package manifest."
}

function Get-CabPackageBuild {
    param(
        [Parameter(Mandatory)][string]$CabPath
    )

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("rsatbuild_" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        & expand.exe $CabPath -F:update.mum $tempDir | Out-Null
        $mumPath = Join-Path $tempDir 'update.mum'
        if (-not (Test-Path -LiteralPath $mumPath)) {
            throw "Cab '$CabPath' does not contain an update.mum to read the OS build from."
        }
        return Get-BuildFromPackageManifest -ManifestXml (Get-Content -LiteralPath $mumPath -Raw)
    }
    finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-RsatCabFileName {
    param(
        [Parameter(Mandatory)][string]$CabStem,
        [ValidateSet('amd64', 'wow64')][string]$Architecture = 'amd64'
    )

    return "$CabStem~31bf3856ad364e35~$Architecture~~.cab"
}

function Find-MissingFeatureCab {
    # The ~amd64~~ FeaturePackage cab is required for every capability. The
    # ~wow64~~ SatellitePackage cab is optional - only 7 of the 9 have one -
    # so it is not checked here.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AvailableFileName,
        [Parameter(Mandatory)][string[]]$CabStem
    )

    $availableLower = @($AvailableFileName | ForEach-Object { $_.ToLowerInvariant() })

    $missing = foreach ($stem in $CabStem) {
        $expected = Get-RsatCabFileName -CabStem $stem -Architecture 'amd64'
        if ($availableLower -notcontains $expected.ToLowerInvariant()) {
            $expected
        }
    }

    return @($missing)
}

function Get-RsatCabToCopy {
    # Per capability: the required ~amd64~~ FeaturePackage cab, plus the
    # ~wow64~~ SatellitePackage cab when the ISO carries one. Returns full
    # source paths, preserving the ISO's actual filename casing (the
    # FailoverCluster cab uses "FOD" where the others use "FoD").
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string[]]$CabStem
    )

    $byLowerName = @{}
    foreach ($item in Get-ChildItem -LiteralPath $SourceFolder -Filter '*.cab' -File) {
        $byLowerName[$item.Name.ToLowerInvariant()] = $item.Name
    }

    $missing = Find-MissingFeatureCab -AvailableFileName @($byLowerName.Values) -CabStem $CabStem
    if ($missing.Count -gt 0) {
        throw "Source folder '$SourceFolder' is missing $($missing.Count) required FeaturePackage cab(s): $($missing -join ', ')"
    }

    $result = foreach ($stem in $CabStem) {
        foreach ($arch in 'amd64', 'wow64') {
            $wantLower = (Get-RsatCabFileName -CabStem $stem -Architecture $arch).ToLowerInvariant()
            if ($byLowerName.ContainsKey($wantLower)) {
                Join-Path $SourceFolder $byLowerName[$wantLower]
            }
        }
    }

    return @($result)
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

        Write-Host "Processing $(Split-Path $iso -Leaf)..."

        $mount = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop
        try {
            $driveLetter = ($mount | Get-Volume).DriveLetter
            $lofSource = "${driveLetter}:\LanguagesAndOptionalFeatures"
            if (-not (Test-Path -LiteralPath $lofSource -PathType Container)) {
                throw "ISO '$iso' has no LanguagesAndOptionalFeatures folder."
            }

            $metadataSource = Join-Path $lofSource 'metadata'
            if (-not (Test-Path -LiteralPath $metadataSource -PathType Container)) {
                throw "ISO '$iso' has no LanguagesAndOptionalFeatures\metadata folder - DISM needs its Component Database to resolve capability names."
            }

            $cabPaths = Get-RsatCabToCopy -SourceFolder $lofSource -CabStem $cabStems
            $buildNumber = Get-CabPackageBuild -CabPath $cabPaths[0]
            Write-Host "  Detected OS build $buildNumber"

            $destFolder = Join-Path $featuresRoot $buildNumber
            if (Test-Path -LiteralPath $destFolder) {
                Remove-Item -LiteralPath $destFolder -Recurse -Force
            }
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null

            $copiedNames = foreach ($cabPath in $cabPaths) {
                Copy-Item -LiteralPath $cabPath -Destination $destFolder -Force
                Split-Path -Path $cabPath -Leaf
            }

            Copy-Item -LiteralPath $metadataSource -Destination $destFolder -Recurse -Force

            Write-Host "  Copied $(@($copiedNames).Count) cabs + metadata\ to $destFolder"

            $manifestBuilds += [PSCustomObject]@{
                Build            = $buildNumber
                SourceIso        = (Split-Path -Path $iso -Leaf)
                Cabs             = @($copiedNames)
                MetadataIncluded = $true
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
