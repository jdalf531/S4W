<#
.SYNOPSIS
    Installs and configures the OSD Web Service on Windows Server 2022 / IIS.

.DESCRIPTION
    Run this script as a local administrator on the IIS server AFTER publishing
    the application with:
        dotnet publish -c Release -o C:\inetpub\OsdWebService

    What the script does:
      1. Verifies / installs required Windows features (IIS + URL Rewrite module).
      2. Creates the log storage folder with appropriate NTFS permissions.
      3. Creates a dedicated application pool (No Managed Code, identity = NetworkService
         or a domain service account you supply).
      4. Creates the IIS website with the specified HTTPS binding.
      5. Writes an event-log source for easy filtering in Event Viewer.

.PARAMETER PublishPath
    Folder containing the published application files.

.PARAMETER SiteName
    IIS website name.  Default: OsdWebService

.PARAMETER AppPoolName
    IIS application pool name.  Default: OsdWebService

.PARAMETER HttpsPort
    Port for the HTTPS binding.  Default: 443

.PARAMETER CertificateThumbprint
    Thumbprint of the TLS certificate already imported into the Local Machine
    certificate store (Cert:\LocalMachine\My).  Run:
        Get-ChildItem Cert:\LocalMachine\My | Format-Table Subject, Thumbprint
    to find it.

.PARAMETER LogStoragePath
    Folder where uploaded OSD log zips will be stored.  Default: C:\OSDLogs

.PARAMETER AppPoolIdentity
    Domain\User for the application pool identity.  Leave blank to use
    NetworkService (suitable when the IIS server IS the MECM site server).
    When the IIS server is separate from MECM, supply a domain account that
    is a member of the SMS Admins local security group on the site server.

.PARAMETER AppPoolPassword
    Password for AppPoolIdentity as a SecureString.  Only used when AppPoolIdentity is set.
    If omitted the script will prompt interactively.

.PARAMETER UrlRewriteMsiPath
    Path to the IIS URL Rewrite Module 2.1 (x64) MSI, used only if the module
    is not already installed on this server. Point this at a copy staged on
    an internal file share or software repository - this script never
    downloads anything from the internet. If omitted and the module is
    missing, the script warns and continues without installing it (the
    HTTP->HTTPS redirect rule in web.config will not function until the
    module is installed by some other means).

.EXAMPLE
    .\Install-OsdWebService.ps1 `
        -PublishPath           C:\inetpub\OsdWebService `
        -CertificateThumbprint 'AB12CD34...' `
        -AppPoolIdentity       'CORP\svc-osdwebservice' `
        -UrlRewriteMsiPath     '\\fileserver\software\IIS\rewrite_amd64_en-US.msi'
    # The script will prompt for the password securely.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $PublishPath,

    [string] $SiteName              = 'OsdWebService',
    [string] $AppPoolName           = 'OsdWebService',
    [int]    $HttpsPort             = 443,

    [Parameter(Mandatory)]
    [string] $CertificateThumbprint,

    [string]       $LogStoragePath     = 'C:\OSDLogs',
    [string]       $AppPoolIdentity    = '',
    [SecureString] $AppPoolPassword    = $null,
    [string]       $UrlRewriteMsiPath  = ''
)

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# Helper
# -----------------------------------------------------------------------
function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------
# 1. IIS features
# -----------------------------------------------------------------------
Write-Step "Checking IIS features"

$features = @(
    'Web-Server',
    'Web-WebServer',
    'Web-Common-Http',
    'Web-Default-Doc',
    'Web-Static-Content',
    'Web-Http-Errors',
    'Web-Security',
    'Web-Request-Monitor',
    'Web-Http-Logging',
    'Web-Mgmt-Tools',
    'Web-Mgmt-Console'
)

$missing = $features | Where-Object {
    -not (Get-WindowsFeature -Name $_).Installed
}

if ($missing) {
    Write-Host "Installing: $($missing -join ', ')"
    Install-WindowsFeature -Name $missing -IncludeManagementTools | Out-Null
}
else {
    Write-Host "All required IIS features already installed."
}

# URL Rewrite module (needed for HTTP->HTTPS redirect in web.config).
# This script never downloads anything - supply -UrlRewriteMsiPath pointing
# at a copy of the installer staged on an internal file share or software
# repository if the module isn't already present on this server.
$rewriteReg = 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite'
if (-not (Test-Path $rewriteReg)) {
    if ($UrlRewriteMsiPath) {
        if (-not (Test-Path -LiteralPath $UrlRewriteMsiPath)) {
            throw "UrlRewriteMsiPath '$UrlRewriteMsiPath' was not found."
        }
        Write-Host "URL Rewrite module not found. Installing from $UrlRewriteMsiPath ..."
        $msiArgs = @('/i', "`"$UrlRewriteMsiPath`"", '/quiet', '/norestart')
        $proc    = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "URL Rewrite module install failed (msiexec exit code $($proc.ExitCode))."
        }
        Write-Host "URL Rewrite module installed."
    }
    else {
        Write-Warning "URL Rewrite module not found and -UrlRewriteMsiPath was not supplied."
        Write-Warning "Obtain the IIS URL Rewrite Module 2.1 (x64) installer from your internal"
        Write-Warning "software repository, then re-run with -UrlRewriteMsiPath, or install it manually."
        Write-Warning "Continuing without URL Rewrite.  HTTP redirect in web.config will not function."
    }
}

# -----------------------------------------------------------------------
# 2. Log storage folder
# -----------------------------------------------------------------------
Write-Step "Creating log storage folder: $LogStoragePath"

if (-not (Test-Path $LogStoragePath)) {
    New-Item -ItemType Directory -Path $LogStoragePath | Out-Null
}

# Grant Modify to the app pool identity
$identity = if ($AppPoolIdentity) { $AppPoolIdentity } else { 'NT AUTHORITY\NetworkService' }
$acl = Get-Acl $LogStoragePath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity,
    [System.Security.AccessControl.FileSystemRights]::Modify,
    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)
$acl.SetAccessRule($rule)
Set-Acl -Path $LogStoragePath -AclObject $acl
Write-Host "Granted Modify on $LogStoragePath to $identity"

# -----------------------------------------------------------------------
# 3. Application Pool
# -----------------------------------------------------------------------
Write-Step "Configuring application pool: $AppPoolName"

Import-Module WebAdministration -ErrorAction Stop

if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
    Write-Host "Created app pool."
}

Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ''
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name enable32BitAppOnWin64   -Value $false

if ($AppPoolIdentity) {
    # Prompt for the password interactively if it was not supplied on the command line.
    if ($null -eq $AppPoolPassword) {
        $AppPoolPassword = Read-Host -AsSecureString "Enter password for $AppPoolIdentity"
    }
    # IIS WMI requires a plain-text string; convert only at the point of use.
    $bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AppPoolPassword)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

    Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel -Value @{
        userName     = $AppPoolIdentity
        password     = $plainPass
        identityType = 3   # SpecificUser
    }
    $plainPass = $null   # Discard from memory as soon as possible
    Write-Host "App pool identity set to $AppPoolIdentity"
}
else {
    Set-ItemProperty "IIS:\AppPools\$AppPoolName" processModel.identityType -Value 2  # NetworkService
    Write-Host "App pool identity set to NetworkService"
}

# -----------------------------------------------------------------------
# 4. IIS Website
# -----------------------------------------------------------------------
Write-Step "Configuring IIS website: $SiteName"

# Validate publish path
if (-not (Test-Path $PublishPath)) {
    throw "PublishPath '$PublishPath' not found.  Run 'dotnet publish' first."
}

$cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Thumbprint -ieq $CertificateThumbprint } |
        Select-Object -First 1

if (-not $cert) {
    throw "Certificate with thumbprint '$CertificateThumbprint' not found in Cert:\LocalMachine\My"
}

if (Get-Website -Name $SiteName -ErrorAction SilentlyContinue) {
    Remove-Website -Name $SiteName
    Write-Host "Removed existing website '$SiteName'."
}

New-Website -Name $SiteName `
            -PhysicalPath $PublishPath `
            -ApplicationPool $AppPoolName `
            -Port $HttpsPort `
            -Ssl | Out-Null

# Bind the certificate to the HTTPS listener
$binding = Get-WebBinding -Name $SiteName -Protocol https
$binding.AddSslCertificate($CertificateThumbprint, 'My')

Write-Host "Website '$SiteName' bound to port $HttpsPort with certificate: $($cert.Subject)"

# -----------------------------------------------------------------------
# 5. IIS permissions on the publish folder
# -----------------------------------------------------------------------
Write-Step "Setting NTFS permissions on publish folder"

$pubAcl = Get-Acl $PublishPath
$readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity,
    [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)
$pubAcl.SetAccessRule($readRule)
Set-Acl -Path $PublishPath -AclObject $pubAcl
Write-Host "Granted ReadAndExecute on $PublishPath to $identity"

# Logs subfolder needs write access for stdout logging
$logsDir = Join-Path $PublishPath 'logs'
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
$logAcl = Get-Acl $logsDir
$logRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity,
    [System.Security.AccessControl.FileSystemRights]::Modify,
    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)
$logAcl.SetAccessRule($logRule)
Set-Acl -Path $logsDir -AclObject $logAcl

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
Write-Host "`n" -NoNewline
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Edit appsettings.json in '$PublishPath' and set:"
Write-Host "       ApiKey           - a strong random string"
Write-Host "       LogStorage:BasePath - $LogStoragePath (already created)"
Write-Host "       Mecm:SiteServer  - your MECM site server FQDN"
Write-Host "       Mecm:SiteCode    - your three-character site code"
Write-Host "  2. Restart the application pool:"
Write-Host "       Restart-WebAppPool -Name $AppPoolName"
Write-Host "  3. Test the health endpoint:"
Write-Host "       Invoke-RestMethod https://localhost:$HttpsPort/health"
Write-Host ""
Write-Host "MECM WMI access note:"
Write-Host "  The identity '$identity' must be a member of the 'SMS Admins'"
$siteServerNote = if ($Env:COMPUTERNAME -eq 'MECM-SERVER-FQDN') { 'this server' } else { 'the MECM site server' }
Write-Host "  local security group on $siteServerNote."
