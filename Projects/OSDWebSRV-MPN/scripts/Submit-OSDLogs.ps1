<#
.SYNOPSIS
    Collects OSD / SMSTS logs, compresses them, and uploads to the OSD Web Service.

.DESCRIPTION
    Designed to run as a task sequence step in WinPE (PowerShell 5.1).
    Uses System.Net.Http.HttpClient for multipart/form-data upload so that
    no PowerShell 6+ features are required.

.PARAMETER ServiceBaseUrl
    Base URL of the OSD Web Service, e.g. https://mecm-iis.corp.contoso.com/osd

.PARAMETER ApiKey
    API key that matches the value configured in the web service appsettings.json.

.PARAMETER LogPaths
    One or more paths to gather logs from.  Defaults to the standard SMSTS log
    locations searched in WinPE / full OS.

.PARAMETER ComputerName
    Override the computer name written to the log record.  Defaults to the
    OSDComputerName task sequence variable, then _SMSTSMachineName, then $env:COMPUTERNAME.

.PARAMETER TaskSequenceName
    Friendly description of the task sequence, written to the metadata sidecar.

.PARAMETER SkipCertificateValidation
    Disables TLS certificate verification.  Use ONLY in labs with self-signed certs.
    Never use in production.

.EXAMPLE
    # Run from a task sequence "Run PowerShell Script" step
    Submit-OSDLogs.ps1 `
        -ServiceBaseUrl "https://mecm-iis.corp.contoso.com/osd" `
        -ApiKey         "your-secret-key-here"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string] $ServiceBaseUrl,

    [Parameter(Mandatory)]
    [string] $ApiKey,

    [string[]] $LogPaths = @(),

    [string] $ComputerName = '',

    [string] $TaskSequenceName = 'OSD',

    [switch] $SkipCertificateValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve computer name from TS environment variables when available.
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    try {
        $tsEnv = New-Object -ComObject 'Microsoft.SMS.TSEnvironment'
        $ComputerName = $tsEnv.Value('OSDComputerName')
        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            $ComputerName = $tsEnv.Value('_SMSTSMachineName')
        }
        if ([string]::IsNullOrWhiteSpace($TaskSequenceName)) {
            $TaskSequenceName = $tsEnv.Value('_SMSTSPackageName')
        }
    }
    catch {
        Write-Host "Not running inside a task sequence COM object; falling back to environment."
    }
}
if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    $ComputerName = $env:COMPUTERNAME
}
if ([string]::IsNullOrWhiteSpace($ComputerName)) {
    $ComputerName = 'UnknownComputer'
}

Write-Host "Computer name   : $ComputerName"
Write-Host "Task sequence   : $TaskSequenceName"

# ---------------------------------------------------------------------------
# Resolve log paths (searched in order; all that exist are included).
# ---------------------------------------------------------------------------
$defaultPaths = @(
    'X:\Windows\Temp\SMSTSLog',
    'C:\Windows\Temp\SMSTSLog',
    'C:\Windows\CCM\Logs',
    'C:\_SMSTaskSequence\Logs',
    'X:\_SMSTaskSequence\Logs'
)

if ($LogPaths.Count -eq 0) { $LogPaths = $defaultPaths }

$resolvedPaths = $LogPaths | Where-Object { Test-Path $_ }
if ($resolvedPaths.Count -eq 0) {
    Write-Warning "No log paths found.  Searched: $($LogPaths -join ', ')"
    Write-Warning "Attempting to continue with an empty archive."
}
Write-Host "Log paths found : $($resolvedPaths -join ', ')"

# ---------------------------------------------------------------------------
# Compress logs to a temp zip.
# ---------------------------------------------------------------------------
$tempDir = $env:TEMP
if ([string]::IsNullOrWhiteSpace($tempDir)) { $tempDir = 'C:\Windows\Temp' }

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$zipPath   = Join-Path $tempDir "OSDLogs_${ComputerName}_${timestamp}.zip"

try {
    if ($resolvedPaths.Count -gt 0) {
        Write-Host "Compressing logs -> $zipPath"
        # Compress-Archive does not exist in very early WinPE builds.
        # Fall back to System.IO.Compression if needed.
        try {
            $items = $resolvedPaths | ForEach-Object { Join-Path $_ '*' }
            Compress-Archive -Path $items -DestinationPath $zipPath -Force
        }
        catch {
            Write-Host "Compress-Archive unavailable, using System.IO.Compression..."
            Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
            $archive = [System.IO.Compression.ZipFile]::Open($zipPath,
                       [System.IO.Compression.ZipArchiveMode]::Create)
            foreach ($dir in $resolvedPaths) {
                Get-ChildItem -Path $dir -Recurse -File | ForEach-Object {
                    $entryName = $_.FullName.Substring($dir.Length).TrimStart('\','/')
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                        $archive, $_.FullName, $entryName) | Out-Null
                }
            }
            $archive.Dispose()
        }
    }
    else {
        # Create an empty zip so the upload still records the attempt.
        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        $archive = [System.IO.Compression.ZipFile]::Open($zipPath,
                   [System.IO.Compression.ZipArchiveMode]::Create)
        $archive.Dispose()
    }

    $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
    Write-Host "Archive size    : ${sizeMB} MB"

    # ---------------------------------------------------------------------------
    # Upload via System.Net.Http.HttpClient (PS 5.1 compatible).
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
    $client.Timeout = [TimeSpan]::FromMinutes(10)

    $form = New-Object System.Net.Http.MultipartFormDataContent

    # -- zip file part
    $fileStream   = [System.IO.File]::OpenRead($zipPath)
    $fileContent  = New-Object System.Net.Http.StreamContent($fileStream)
    $fileContent.Headers.ContentType =
        [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/zip')
    $form.Add($fileContent, 'file', [System.IO.Path]::GetFileName($zipPath))

    # -- text parts
    $form.Add((New-Object System.Net.Http.StringContent($ComputerName)),    'computerName')
    $form.Add((New-Object System.Net.Http.StringContent($TaskSequenceName)), 'taskSequenceName')

    $uri      = "$($ServiceBaseUrl.TrimEnd('/'))/api/logs/upload"
    Write-Host "Uploading to    : $uri"

    $response = $client.PostAsync($uri, $form).GetAwaiter().GetResult()
    $body     = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

    if ($response.IsSuccessStatusCode) {
        Write-Host "Upload succeeded (HTTP $([int]$response.StatusCode))"
        Write-Host $body
    }
    else {
        Write-Error "Upload failed: HTTP $([int]$response.StatusCode) - $body"
    }
}
finally {
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        Write-Host "Temp archive removed."
    }
}
