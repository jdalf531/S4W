# OSD Web Service

An ASP.NET Core 8 web API that runs on **Windows Server 2022 / IIS** and provides two functions for ConfigMgr OSD task sequences running in WinPE:

| Endpoint | Purpose |
|---|---|
| `POST /api/logs/upload` | Accept a `.zip` of OSD/SMSTS logs from a WinPE TS step |
| `GET  /api/driverpackages` | Return all MECM driver packages (queried via WMI from the SMS Provider) |

All traffic is **HTTPS-only**. Every request (except `/health`) requires the `X-API-Key` header.

---

## Repository layout

```
OSD-Webservice/
├── Controllers/
│   ├── LogsController.cs           – POST /api/logs/upload
│   └── DriverPackagesController.cs – GET  /api/driverpackages
│                                     POST /api/driverpackages/refresh
├── Middleware/
│   └── ApiKeyMiddleware.cs         – API-key gate (constant-time compare)
├── Models/
│   ├── DriverPackage.cs
│   └── UploadResult.cs
├── Services/
│   ├── LogStorageService.cs        – writes zip + metadata under BasePath
│   └── MecmQueryService.cs         – WMI query to SMS Provider, 10-min cache
├── Program.cs
├── appsettings.json                – edit before deploying
├── web.config                      – IIS hosting + request-size limits
├── nuget.config                    – restricts restore to nuget-offline-cache/ (airgap)
├── nuget-offline-cache/            – vendored NuGet packages, no internet needed to build
├── scripts/
│   ├── Submit-OSDLogs.ps1          – WinPE PS5.1 uploader
│   └── Get-DriverPackages.ps1      – WinPE PS5.1 package query
└── install/
    └── Install-OsdWebService.ps1   – IIS setup automation
```

---

## Prerequisites

| Component | Minimum version |
|---|---|
| Windows Server | 2022 |
| IIS | 10 (included with Windows Server) |
| [.NET 8 Hosting Bundle](https://dotnet.microsoft.com/download/dotnet/8.0) | 8.0.x |
| [IIS URL Rewrite Module](https://www.iis.net/downloads/microsoft/url-rewrite) | 2.1 |
| TLS certificate | issued by your internal CA, bound to the IIS server FQDN |

**Airgapped/enterprise networks:** none of the above are downloaded automatically
by any script or build step in this repo. Obtain the .NET 8 Hosting Bundle
installer and the IIS URL Rewrite Module MSI once, on a machine with internet
access (or from your internal software repository), and stage them internally.
See "Offline build (airgapped) setup" below for the application's own build
dependencies (NuGet packages), which ARE vendored in this repo.

---

## Build & publish

At runtime, this service makes no outbound calls to the public internet —
every request it handles is either its own HTTPS API (for WinPE clients) or
an intranet WMI query to your MECM site server. The only place the public
internet is ever touched is by `dotnet` tooling while *building* the project
(NuGet package restore), and that has been made fully offline-capable — see
below.

```powershell
cd C:\temp\OSD-Webservice
dotnet publish -c Release -o C:\inetpub\OsdWebService
```

### Offline build (airgapped) setup

This repo vendors all of its NuGet dependencies under `nuget-offline-cache/`
(checked into source control) and ships a `nuget.config` that restricts
restore to *only* that local folder — `dotnet build`/`publish` never
contacts nuget.org. This has been verified end-to-end: a clean `dotnet
publish` succeeds with `nuget-offline-cache/` as the sole configured source
and nothing in the default global NuGet cache.

You still need the .NET 8 SDK installed on the build machine (a one-time,
offline-installer step — the SDK itself is not something a per-project NuGet
vendor folder can substitute for). Once the SDK is installed, `dotnet
publish` in this repo works with **zero network access**.

**To add or update a dependency** (requires a machine with internet access —
do this once, then carry the result into the airgapped environment via your
normal internal transfer process):

```powershell
cd C:\temp\OSD-Webservice
dotnet restore --source https://api.nuget.org/v3/index.json --packages ./nuget-offline-cache
```

Commit the resulting contents of `nuget-offline-cache/` along with the
`.csproj` change. Do **not** add nuget.org (or any other remote source) to
`nuget.config` permanently — only use `--source` for this one-off update
command.

---

## Configuration (`appsettings.json`)

`Install-OsdWebService.ps1` (below) writes `ApiKey`, `LogStorage:BasePath`,
`Mecm:SiteServer`, and `Mecm:SiteCode` into the published `appsettings.json`
for you — prompting for the MECM site server/site code if you don't pass
them as parameters, and auto-generating the API key if you don't supply
one. There is no manual JSON edit needed after the script completes.

If you ever need to generate an API key by hand (e.g. to rotate one later):
```powershell
[System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
```

---

## IIS installation

Run as a local administrator on the IIS server:

```powershell
.\install\Install-OsdWebService.ps1 `
    -PublishPath           C:\inetpub\OsdWebService `
    -CertificateThumbprint 'AB12CD34EF56...' `
    -LogStoragePath        C:\OSDLogs `
    -AppPoolIdentity       'CORP\svc-osdweb' `
    -UrlRewriteMsiPath     '\\fileserver\software\IIS\rewrite_amd64_en-US.msi' `
    -MecmSiteServer        cm01.corp.contoso.com `
    -MecmSiteCode          PS1
    # Script will prompt securely for the app pool password.
    # Omit -MecmSiteServer/-MecmSiteCode to be prompted for them instead.
    # Omit -ApiKey to have one generated and printed for you.
```

`-UrlRewriteMsiPath` is optional and only used if the URL Rewrite module
isn't already installed. The script never downloads it - point this at a
copy staged on an internal file share or software repository. If omitted
and the module is missing, the script warns and continues (the HTTP->HTTPS
redirect rule in `web.config` won't function until the module is installed
by some other means).

`-MecmSiteServer`, `-MecmSiteCode`, and `-ApiKey` are all optional: leave
any of them off the command line and the script will prompt for it (or, for
`-ApiKey`, generate one and print it once).

### Application pool identity requirements

The app pool identity needs:

1. **NTFS Modify** on `LogStorage:BasePath` (created by the install script).
2. **SMS Admins** local group membership on the MECM site server — required for WMI access to `ROOT\SMS\site_<code>`.

If the IIS server **is** the MECM site server you can use `NetworkService`; otherwise supply a domain service account.

---

## Stored log folder structure

```
C:\OSDLogs\
└── 2025\
    └── 07\
        └── DESKTOP-ABC123\
            ├── 20250714_103045_OSDLogs_DESKTOP-ABC123_20250714_103042.zip
            └── 20250714_103045_metadata.txt
```

The `metadata.txt` sidecar contains computer name, task sequence name, upload timestamp, and file size so MECM admins can triage without unzipping.

---

## WinPE client scripts

Both scripts require only **PowerShell 5.1** and `System.Net.Http` (present in all WinPE 10/11 images once the `WinPE-WMI` and `WinPE-PowerShell` optional components are added).

### Submit-OSDLogs.ps1 — task sequence step

Add a **Run PowerShell Script** step near the end of your TS (or in the error handler group):

```powershell
.\Submit-OSDLogs.ps1 `
    -ServiceBaseUrl "https://cm01-iis.corp.contoso.com" `
    -ApiKey         "your-api-key-here"
```

The script automatically reads `OSDComputerName` and `_SMSTSPackageName` from the TS environment.

### Get-DriverPackages.ps1 — driver selection

```powershell
# Find the right HP driver package for this model
$pkgs = .\Get-DriverPackages.ps1 `
            -ServiceBaseUrl      "https://cm01-iis.corp.contoso.com" `
            -ApiKey              "your-api-key-here" `
            -FilterByManufacturer "HP"

$model   = (Get-WmiObject Win32_ComputerSystem).Model
$match   = $pkgs | Where-Object { $_.name -like "*$model*" } | Select-Object -First 1

if ($match) {
    $tsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    $tsEnv.Value('OSDDriverPackageID') = $match.packageId
}
```

### Self-signed certificates in a lab

Add `-SkipCertificateValidation` to either script. **Never use this in production.**

---

## API reference

### `POST /api/logs/upload`

| Item | Detail |
|---|---|
| Content-Type | `multipart/form-data` |
| `file` | `.zip` attachment (required) |
| `computerName` | OSD machine name (required) |
| `taskSequenceName` | friendly TS name (optional) |
| Max body size | 500 MB |

Response (200):
```json
{ "success": true, "message": "Log file stored successfully.", "relativePath": "2025\\07\\DESKTOP-ABC123\\20250714_103045_OSDLogs.zip" }
```

### `GET /api/driverpackages`

Returns a JSON array. Results cached for 10 minutes.

```json
[
  {
    "packageId":    "PS100042",
    "name":         "HP EliteBook 840 G10 - Win11 23H2",
    "version":      "1.0",
    "description":  "",
    "manufacturer": "HP",
    "sourceSizeKb": 524288
  }
]
```

### `POST /api/driverpackages/refresh`

Clears the in-memory cache. Call this after importing new driver packages into MECM without waiting 10 minutes.

### `GET /health`

No API key required. Returns `200 Healthy` when the service is running.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| 401 Unauthorized | Verify the `X-API-Key` header value matches `ApiKey` in appsettings.json |
| 500 on `/api/driverpackages` | Check IIS stdout log in `C:\inetpub\OsdWebService\logs\`. The app pool identity may lack SMS Admins membership. |
| Upload succeeds but file not found | Check `LogStorage:BasePath` NTFS permissions for the app pool identity. |
| WinPE cannot reach HTTPS endpoint | Ensure WinPE image includes `WinPE-WMI` and `WinPE-PowerShell`. Verify TLS cert is trusted (or use `-SkipCertificateValidation` in a lab). |
| `Compress-Archive` missing in WinPE | The script falls back to `System.IO.Compression.FileSystem` automatically. |
