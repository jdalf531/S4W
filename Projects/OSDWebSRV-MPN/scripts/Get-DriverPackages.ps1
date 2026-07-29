<#
.SYNOPSIS
    Retrieves the list of MECM driver packages from the OSD Web Service.

.DESCRIPTION
    Designed to run from WinPE (PowerShell 5.1) during an OSD task sequence.
    Returns an array of driver package objects that can be used in later TS steps
    to select the correct driver package for the detected hardware model.

.PARAMETER ServiceBaseUrl
    Base URL of the OSD Web Service, e.g. https://mecm-iis.corp.contoso.com/osd

.PARAMETER ApiKey
    API key that matches the value configured in the web service.

.PARAMETER FilterByManufacturer
    Optional wildcard filter on the Manufacturer field (e.g. "Dell", "HP", "Lenovo").

.PARAMETER FilterByName
    Optional wildcard filter on the Name field.

.PARAMETER SkipCertificateValidation
    Disables TLS certificate verification.  Use ONLY in labs with self-signed certs.

.OUTPUTS
    PSCustomObject[]  - one object per driver package with the properties:
      packageId, name, version, description, manufacturer, sourceSizeKb

.EXAMPLE
    # Find all HP driver packages and pick the first match for this model.
    $packages = Get-DriverPackages.ps1 `
                    -ServiceBaseUrl "https://mecm-iis.corp.contoso.com/osd" `
                    -ApiKey         "your-secret-key-here" `
                    -FilterByManufacturer "HP"

    $model   = (Get-WmiObject -Class Win32_ComputerSystem).Model
    $package = $packages | Where-Object { $_.name -like "*$model*" } | Select-Object -First 1

    if ($package) {
        $tsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
        $tsEnv.Value('OSDDriverPackageID') = $package.packageId
        Write-Host "Selected driver package: $($package.name) ($($package.packageId))"
    }
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string] $ServiceBaseUrl,

    [Parameter(Mandatory)]
    [string] $ApiKey,

    [string] $FilterByManufacturer = '',
    [string] $FilterByName         = '',

    [switch] $SkipCertificateValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Build HttpClient (PS 5.1 compatible - no Invoke-RestMethod -SkipCertificateCheck)
# ---------------------------------------------------------------------------
Add-Type -AssemblyName 'System.Net.Http'

$handler = New-Object System.Net.Http.HttpClientHandler
if ($SkipCertificateValidation) {
    Write-Warning "Certificate validation is DISABLED. Do not use this in production."
    $handler.ServerCertificateCustomValidationCallback =
        [System.Net.Http.HttpClientHandler]::DangerousAcceptAnyServerCertificateValidator
}

$client = New-Object System.Net.Http.HttpClient($handler)
$client.DefaultRequestHeaders.Add('X-API-Key', $ApiKey)
$client.Timeout = [TimeSpan]::FromSeconds(60)

# ---------------------------------------------------------------------------
# GET /api/driverpackages
# ---------------------------------------------------------------------------
$uri = "$($ServiceBaseUrl.TrimEnd('/'))/api/driverpackages"
Write-Host "Querying driver packages: $uri"

$response = $client.GetAsync($uri).GetAwaiter().GetResult()
$body     = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

if (-not $response.IsSuccessStatusCode) {
    throw "Failed to retrieve driver packages: HTTP $([int]$response.StatusCode) - $body"
}

# Parse JSON (ConvertFrom-Json is available in PS 5.1).
$packages = $body | ConvertFrom-Json

Write-Host "Total packages returned: $($packages.Count)"

# ---------------------------------------------------------------------------
# Optional client-side filtering
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($FilterByManufacturer)) {
    $packages = $packages | Where-Object { $_.manufacturer -like "*$FilterByManufacturer*" }
    Write-Host "After manufacturer filter '$FilterByManufacturer': $($packages.Count)"
}

if (-not [string]::IsNullOrWhiteSpace($FilterByName)) {
    $packages = $packages | Where-Object { $_.name -like "*$FilterByName*" }
    Write-Host "After name filter '$FilterByName': $($packages.Count)"
}

if ($packages.Count -eq 0) {
    Write-Warning "No driver packages matched the specified filters."
}
else {
    $packages | Format-Table -AutoSize -Property packageId, name, version, manufacturer
}

# Return the array for use in the calling script.
return $packages
