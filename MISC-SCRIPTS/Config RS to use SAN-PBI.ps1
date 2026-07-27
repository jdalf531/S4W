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
    # Note: NetshOutput keeps [Parameter(Mandatory)] (so a missing/null argument
    # still fails fast) but adds [AllowEmptyString()], because real
    # `netsh http show urlacl` output (and the test fixture) contains blank-line
    # array elements, which Mandatory alone rejects.
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$NetshOutput)

    $reserved = foreach ($line in $NetshOutput) {
        if ($line -match '^\s*Reserved URL\s*:\s*(?<url>\S+)') {
            $Matches['url'].TrimEnd('/')
        }
    }
    return $reserved
}

function Test-UrlAclConflict {
    # Note: NetshOutput keeps [Parameter(Mandatory)] plus [AllowEmptyString()] -
    # see Get-ReservedUrlsFromNetshOutput above for why (blank-line elements in
    # real netsh output and the test fixture).
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$NetshOutput,
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

function Get-CertHashFromSslCertOutput {
    param([Parameter(Mandatory)][string[]]$NetshOutput)

    foreach ($line in $NetshOutput) {
        if ($line -match '^\s*Certificate Hash\s*:\s*(?<hash>[0-9a-fA-F]+)') {
            return $Matches['hash']
        }
    }
    return $null
}

function Test-CertificateForSan {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][string]$Hostname
    )

    $failures = [System.Collections.Generic.List[string]]::new()

    if (-not $Certificate.HasPrivateKey) {
        $failures.Add('Certificate has no private key.')
    }

    if ($Certificate.Issuer -eq $Certificate.Subject) {
        $failures.Add('Certificate appears to be self-signed (Issuer equals Subject).')
    }

    $sanExtension = $Certificate.Extensions | Where-Object { $_.Oid.FriendlyName -eq 'Subject Alternative Name' } | Select-Object -First 1
    $sanNames = @()
    if ($sanExtension) {
        $sanText = $sanExtension.Format($true)
        $sanNames = [regex]::Matches($sanText, 'DNS Name=(?<name>\S+)') | ForEach-Object { $_.Groups['name'].Value }
    }

    if ($Hostname -notin $sanNames) {
        $failures.Add("Certificate SAN list does not include '$Hostname'. Found: $($sanNames -join ', ')")
    }

    return [PSCustomObject]@{
        IsValid  = ($failures.Count -eq 0)
        Failures = $failures
        SanNames = $sanNames
    }
}

function Get-OldSanUrlNodes {
    param(
        [Parameter(Mandatory)][xml]$ConfigXml,
        [Parameter(Mandatory)][string]$Application
    )

    $urlNodes = $ConfigXml.SelectNodes("//UrlReservations[Application='$Application']/URLs/URL")
    # Note: the unary comma is required here, not just @(). A plain `return @(...)`
    # still unwraps a single-element array back to a bare XmlElement when it crosses
    # the function's return/pipeline boundary (PowerShell only preserves array-ness
    # across pipeline output for 0 or 2+ items). XmlElement also doesn't get the
    # auto Count/ETS member that scalars normally receive, so callers doing
    # $nodes.Count would silently get $null instead of 1 for the single-match case.
    return , @($urlNodes | Where-Object { $_.UrlString -notmatch '^https?://\+:' })
}

function Update-ReportServerConfigXml {
    param(
        [Parameter(Mandatory)][xml]$ConfigXml,
        [Parameter(Mandatory)][string]$NewHostname,
        [Parameter(Mandatory)][int]$Port
    )

    $applications = 'ReportServerWebService', 'ReportServerWebApp'
    $removedHostnames = [System.Collections.Generic.List[string]]::new()

    foreach ($app in $applications) {
        $urlsNode = $ConfigXml.SelectSingleNode("//UrlReservations[Application='$app']/URLs")
        if (-not $urlsNode) {
            throw "Could not find URLs section for application '$app' in rsreportserver.config."
        }

        $wildcardNode = $urlsNode.URL | Where-Object { $_.UrlString -match '^https?://\+:' } | Select-Object -First 1
        if (-not $wildcardNode) {
            throw "Could not find default 'https://+:$Port' listener for application '$app'."
        }

        foreach ($oldNode in (Get-OldSanUrlNodes -ConfigXml $ConfigXml -Application $app)) {
            if ($oldNode.UrlString -match '^https?://([^:/]+):') {
                $removedHostnames.Add($Matches[1])
            }
            [void]$urlsNode.RemoveChild($oldNode)
        }

        $newNode = $ConfigXml.CreateElement('URL')

        $urlStringEl = $ConfigXml.CreateElement('UrlString')
        $urlStringEl.InnerText = "https://$($NewHostname):$($Port)"
        [void]$newNode.AppendChild($urlStringEl)

        $sidEl = $ConfigXml.CreateElement('AccountSid')
        $sidEl.InnerText = $wildcardNode.AccountSid
        [void]$newNode.AppendChild($sidEl)

        $nameEl = $ConfigXml.CreateElement('AccountName')
        $nameEl.InnerText = $wildcardNode.AccountName
        [void]$newNode.AppendChild($nameEl)

        [void]$urlsNode.AppendChild($newNode)
    }

    return ($removedHostnames | Select-Object -Unique)
}

# ==============================
# System integration
# ==============================
function Invoke-NetshCommand {
    param([Parameter(Mandatory)][string[]]$Args)

    $output = & netsh.exe @Args 2>&1
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Backup-ReportServerConfig {
    param([Parameter(Mandatory)][string]$ConfigPath)

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backupPath = "$ConfigPath.bak-$timestamp"
    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    return $backupPath
}

function Restart-PbirsService {
    Restart-Service -Name $script:PbirsServiceName -Force
    $service = Get-Service -Name $script:PbirsServiceName
    $service.WaitForStatus('Running', (New-TimeSpan -Seconds 60))
}

# ==============================
# Orchestration
# ==============================
function Invoke-Main {
    param([switch]$WhatIf)

    Write-Log 'Starting PBIRS SAN configuration.'

    if (-not (Test-IsAdministrator)) {
        Write-Log 'BLOCKED: This script must be run as Administrator.'
        throw 'This script must be run as Administrator.'
    }
    Write-Log 'CHECK PASSED: Running as Administrator.'

    $serviceInfo = Get-PbirsServiceInfo
    if (-not $serviceInfo.IsReady) {
        Write-Log "BLOCKED: PowerBI Report Server service or config file not found. ServiceFound=$($serviceInfo.ServiceFound) ConfigExists=$($serviceInfo.ConfigExists)"
        throw 'PowerBI Report Server is not installed on this machine (service or config file missing).'
    }
    Write-Log "CHECK PASSED: PowerBIReportServer service and config found at $($serviceInfo.ConfigPath)."

    [xml]$configXml = Get-Content -LiteralPath $serviceInfo.ConfigPath -Raw

    $port = Get-TlsPortFromConfig -ConfigXml $configXml
    if (-not $port) {
        Write-Log 'BLOCKED: No https://+:<port> wildcard listener found in rsreportserver.config. Bind a certificate to a port using Report Server Configuration Manager first.'
        throw 'No TLS port configured yet. Bind a certificate via Report Server Configuration Manager before running this script.'
    }
    Write-Log "CHECK PASSED: TLS port $port discovered from config."

    $urlInput = Read-Host 'Enter the full URL for the SAN (e.g. https://reports.contoso.com)'
    $parsedUri = $null
    if (-not [Uri]::TryCreate($urlInput, [UriKind]::Absolute, [ref]$parsedUri) -or $parsedUri.Scheme -ne 'https') {
        Write-Log "BLOCKED: '$urlInput' is not a valid https URL."
        throw "'$urlInput' is not a valid https URL."
    }
    $newHostname = $parsedUri.Host
    Write-Log "Target SAN hostname: $newHostname (port $port)."

    $sslCertOutput = (Invoke-NetshCommand -Args @('http', 'show', 'sslcert', "ipport=0.0.0.0:$port")).Output
    $certHash = Get-CertHashFromSslCertOutput -NetshOutput $sslCertOutput
    if (-not $certHash) {
        Write-Log "BLOCKED: No certificate bound to port $port (netsh http show sslcert returned nothing usable)."
        throw "No certificate is bound to port $port. Bind one via Report Server Configuration Manager first."
    }

    $certificate = Get-Item -LiteralPath "Cert:\LocalMachine\My\$certHash" -ErrorAction SilentlyContinue
    if (-not $certificate) {
        Write-Log "BLOCKED: Certificate with thumbprint $certHash not found in Cert:\LocalMachine\My."
        throw "Certificate $certHash bound to port $port was not found in the LocalMachine\My store."
    }

    $certCheck = Test-CertificateForSan -Certificate $certificate -Hostname $newHostname
    if (-not $certCheck.IsValid) {
        foreach ($failure in $certCheck.Failures) {
            Write-Log "BLOCKED: $failure"
        }
        throw "Certificate bound to port $port is not valid for SAN '$newHostname': $($certCheck.Failures -join ' ')"
    }
    Write-Log "CHECK PASSED: Certificate $certHash is signed, has a private key, and covers '$newHostname'."

    $urlAclOutput = (Invoke-NetshCommand -Args @('http', 'show', 'urlacl')).Output
    $addCommands = New-UrlAclCommandArgs -Action add -Hostname $newHostname -Port $port
    $conflicts = @($addCommands | Where-Object { Test-UrlAclConflict -NetshOutput $urlAclOutput -Url $_.Url } | ForEach-Object Url)
    if ($conflicts) {
        Write-Log "BLOCKED: urlacl reservation(s) already exist for: $($conflicts -join ', ')"
        throw "urlacl reservations already exist for: $($conflicts -join ', '). Resolve manually before re-running."
    }
    Write-Log 'CHECK PASSED: No existing urlacl conflicts for the new hostname.'

    $oldHostnames = @(
        (Get-OldSanUrlNodes -ConfigXml $configXml -Application 'ReportServerWebService') +
        (Get-OldSanUrlNodes -ConfigXml $configXml -Application 'ReportServerWebApp')
    ) | ForEach-Object {
        if ($_.UrlString -match '^https?://([^:/]+):') { $Matches[1] }
    } | Select-Object -Unique

    $deleteCommands = @()
    foreach ($oldHostname in $oldHostnames) {
        $deleteCommands += New-UrlAclCommandArgs -Action delete -Hostname $oldHostname -Port $port
    }

    if ($WhatIf) {
        Write-Log '--- WHATIF PREVIEW (no changes made) ---'
        Write-Log "Old SAN hostname(s) found: $(if ($oldHostnames) { $oldHostnames -join ', ' } else { 'none' })"
        Write-Log "New SAN URL to add: https://$($newHostname):$($port)"
        foreach ($cmd in $deleteCommands) { Write-Log "Would run: netsh $($cmd.Args -join ' ')" }
        foreach ($cmd in $addCommands) { Write-Log "Would run: netsh $($cmd.Args -join ' ')" }
        Write-Log "Would restart service: $script:PbirsServiceName"
        return
    }

    $backupPath = Backup-ReportServerConfig -ConfigPath $serviceInfo.ConfigPath
    Write-Log "Backed up config to $backupPath."

    $removedHostnames = Update-ReportServerConfigXml -ConfigXml $configXml -NewHostname $newHostname -Port $port
    $configXml.Save($serviceInfo.ConfigPath)
    Write-Log "Updated rsreportserver.config. Removed old SAN entries for: $(if ($removedHostnames) { $removedHostnames -join ', ' } else { 'none' })."

    foreach ($cmd in $deleteCommands) {
        Invoke-NetshCommand -Args $cmd.Args | Out-Null
        Write-Log "Deleted urlacl: $($cmd.Url)"
    }
    foreach ($cmd in $addCommands) {
        $result = Invoke-NetshCommand -Args $cmd.Args
        if ($result.ExitCode -ne 0) {
            Write-Log "FAILED to add urlacl $($cmd.Url): $($result.Output -join ' ')"
            throw "Failed to add urlacl $($cmd.Url). See $backupPath to restore the previous config if needed."
        }
        Write-Log "Added urlacl: $($cmd.Url)"
    }

    Restart-PbirsService
    Write-Log 'PowerBIReportServer service restarted successfully.'
    Write-Log 'SAN configuration complete.'
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main -WhatIf:$WhatIf
}
