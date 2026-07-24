<#
.SYNOPSIS
    Configures Power BI Report Server (PBIRS) to use a Subject Alternative Name (SAN),
    replacing any previously-configured SAN.
.DESCRIPTION
    Implements https://learn.microsoft.com/en-us/sql/reporting-services/report-server-sharepoint/configure-reporting-services-to-use-a-subject-alternative-name
    for Power BI Report Server specifically. Prompts for the SAN URL, validates
    prerequisites (admin rights, service/config present, TLS port + certificate valid
    for the hostname, no urlacl conflicts), then updates rsreportserver.config and the
    netsh http urlacl reservations, and restarts the service.
.NOTES
    Modified: 2026-07-23
#>

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$script:LogFile           = Join-Path $PSScriptRoot 'SAN-Config-Log.txt'
$script:PbirsServiceName  = 'PowerBIReportServer'
$script:PbirsConfigPath   = 'C:\Program Files\Microsoft Power BI Report Server\PBIRS\ReportServer\rsreportserver.config'
$script:PbirsAccountName  = 'NT SERVICE\PowerBIReportServer'
$script:PbirsAccountSid   = 'S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663'
$script:PbirsUrlAclPaths  = @('ReportServer', 'Reports', 'PowerBI', 'wopi')

# ==============================
# Logging
# ==============================
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$LogFile = $script:LogFile
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line
}

# ==============================
# Blocker checks
# ==============================
function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PbirsServiceInfo {
    $service = Get-Service -Name $script:PbirsServiceName -ErrorAction SilentlyContinue
    $configExists = Test-Path -LiteralPath $script:PbirsConfigPath

    return [PSCustomObject]@{
        ServiceFound = [bool]$service
        Service      = $service
        ConfigPath   = $script:PbirsConfigPath
        ConfigExists = $configExists
        IsReady      = ([bool]$service -and $configExists)
    }
}

function Get-TlsPortFromConfig {
    param([Parameter(Mandatory)][xml]$ConfigXml)

    $wildcardUrl = $ConfigXml.SelectSingleNode("//UrlReservations[Application='ReportServerWebService']/URLs/URL[starts-with(UrlString, 'https://+:')]")

    if (-not $wildcardUrl) {
        return $null
    }

    if ($wildcardUrl.UrlString -match ':(?<port>\d+)$') {
        return [int]$Matches['port']
    }

    return $null
}

function Get-ReservedUrlsFromNetshOutput {
    # Note: NetshOutput is intentionally not marked [Parameter(Mandatory)] here.
    # PowerShell's Mandatory validation rejects string[] arguments containing any
    # empty-string element, but real `netsh http show urlacl` output always
    # includes blank lines.
    param([string[]]$NetshOutput)

    $reserved = foreach ($line in $NetshOutput) {
        if ($line -match '^\s*Reserved URL\s*:\s*(?<url>\S+)') {
            $Matches['url'].TrimEnd('/')
        }
    }
    return $reserved
}

function Test-UrlAclConflict {
    # Note: NetshOutput is intentionally not marked [Parameter(Mandatory)] here.
    # PowerShell's Mandatory validation rejects string[] arguments containing any
    # empty-string element, but real `netsh http show urlacl` output always
    # includes blank lines.
    param(
        [string[]]$NetshOutput,
        [Parameter(Mandatory)][string]$Url
    )

    $reserved = Get-ReservedUrlsFromNetshOutput -NetshOutput $NetshOutput
    return ($reserved | Where-Object { $_ -ieq $Url.TrimEnd('/') }).Count -gt 0
}

function New-UrlAclCommandArgs {
    param(
        [Parameter(Mandatory)][ValidateSet('add', 'delete')][string]$Action,
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][int]$Port
    )

    return $script:PbirsUrlAclPaths | ForEach-Object {
        $url = "https://$($Hostname):$($Port)/$_"
        if ($Action -eq 'add') {
            [PSCustomObject]@{
                Path = $_
                Url  = $url
                Args = @(
                    'http', 'add', 'urlacl',
                    "url=$url",
                    "user=$script:PbirsAccountName",
                    "sddl=D:(A;;GX;;;$script:PbirsAccountSid)"
                )
            }
        }
        else {
            [PSCustomObject]@{
                Path = $_
                Url  = $url
                Args = @('http', 'delete', 'urlacl', "url=$url")
            }
        }
    }
}
