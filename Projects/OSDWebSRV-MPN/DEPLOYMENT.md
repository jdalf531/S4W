# OSDWebSRV-MPN Deployment Runbook

Step-by-step deployment instructions for the admin performing the install. For full reference detail (API responses, log folder layout, troubleshooting table), see [README.md](README.md).

---

## 0. Before you start — gather these

- **Target server**: Windows Server 2022 with IIS 10 (this is the box the service runs on — can be the MECM site server itself, or a separate box).
- **TLS certificate**: already issued by your internal CA and importable into `Cert:\LocalMachine\My` on that server, bound to the server's FQDN.
- **MECM site server FQDN** and **3-character site code** (e.g. `PS1`) — whoever runs the script will be prompted for these if not supplied.
- **.NET 8 Hosting Bundle installer** — download once from a machine with internet, or get from your internal software repo.
- **IIS URL Rewrite Module 2.1 (x64) MSI** — same story, only needed if it's not already on the target server.
- Decide the **app pool identity**: `NetworkService` if the IIS server *is* the MECM site server, otherwise a domain service account that will be added to **SMS Admins** on the MECM site server.

None of this is downloaded automatically — it's an airgapped-friendly setup, so all of the above must be staged manually ahead of time.

## 1. Build the app (on a build machine with the .NET 8 SDK installed)

```powershell
cd C:\temp\OSD-Webservice        # wherever this repo is checked out
dotnet publish -c Release -o C:\inetpub\OsdWebService
```

This needs **zero network access** at build time — all NuGet packages are vendored in `nuget-offline-cache/`. Copy the resulting `C:\inetpub\OsdWebService` folder to the actual IIS target server if building elsewhere (e.g. via your normal internal file transfer process for airgapped environments).

## 2. Install the .NET 8 Hosting Bundle on the target IIS server

Run the Hosting Bundle installer staged in Step 0, on the actual IIS server. This is a manual, one-time step — no script handles it.

## 3. Import the TLS certificate on the target IIS server

Import it into `Cert:\LocalMachine\My`, then find its thumbprint:

```powershell
Get-ChildItem Cert:\LocalMachine\My | Format-Table Subject, Thumbprint
```

## 4. Run the install script — as local administrator, on the IIS server

```powershell
.\install\Install-OsdWebService.ps1 `
    -PublishPath           C:\inetpub\OsdWebService `
    -CertificateThumbprint '<thumbprint from step 3>' `
    -LogStoragePath        C:\OSDLogs `
    -AppPoolIdentity       'CORP\svc-osdweb' `
    -UrlRewriteMsiPath     '\\fileserver\software\IIS\rewrite_amd64_en-US.msi' `
    -MecmSiteServer        cm01.corp.contoso.com `
    -MecmSiteCode          PS1
```

Notes for whoever runs this:
- If `-AppPoolIdentity` is a domain account, the script prompts for its password securely (or pass `-AppPoolPassword` as a `SecureString`).
- `-MecmSiteServer` / `-MecmSiteCode` / `-ApiKey` can all be **left off** — the script prompts for the first two, and auto-generates the API key if omitted.
- **The API key is printed once, near the top of the output, and again at the very end.** Copy it immediately — it's needed in Step 6. If you lose it, re-run the script with no `-ApiKey` and it'll reuse whatever's already in `appsettings.json` rather than generating a new one (so re-running is safe, not destructive — see Step 8).
- If `-UrlRewriteMsiPath` is omitted and the module isn't already installed, the script warns and continues, but the HTTP→HTTPS redirect won't work until it's installed some other way.
- Leave `-AppPoolIdentity` off entirely to use `NetworkService` (only appropriate if this IIS server is itself the MECM site server).

## 5. Grant SMS Admins membership

Whatever identity ended up running the app pool (`NetworkService`, or the domain account from `-AppPoolIdentity`) must be added to the **SMS Admins** local security group **on the MECM site server** (not the IIS server, if they're different machines). This is required for the WMI driver-package query to work — nothing in the script does this for you.

## 6. Restart and verify

```powershell
Restart-WebAppPool -Name OsdWebService
Invoke-RestMethod https://localhost/health
```

Expect `200 Healthy`. If that fails, check `C:\inetpub\OsdWebService\logs\` for the IIS stdout log.

Then confirm the API key actually works:

```powershell
Invoke-RestMethod https://<server-fqdn>/api/driverpackages -Headers @{ 'X-API-Key' = '<the api key from step 4>' }
```

Should return a JSON array of MECM driver packages (may be empty if none are imported yet).

## 7. Wire up the WinPE task sequence

Copy `scripts/Submit-OSDLogs.ps1` and `scripts/Get-DriverPackages.ps1` into your MECM package/boot image sources. In the task sequence:

- **Log upload** — add a "Run PowerShell Script" step near the end (or in the error-handling group):
  ```powershell
  .\Submit-OSDLogs.ps1 -ServiceBaseUrl "https://<server-fqdn>" -ApiKey "<the api key>"
  ```
- **Driver package lookup** — see the `Get-DriverPackages.ps1` example in the README for the model-matching pattern that sets `OSDDriverPackageID`.

Make sure the boot image has the `WinPE-WMI` and `WinPE-PowerShell` optional components added — both scripts need them.

## 8. Things to know for later

- **Re-running the install script is safe.** It won't silently regenerate the API key on a re-run (it reuses the existing one) unless `-ApiKey` is passed explicitly — so re-running after a config tweak, or to pick up a new build, won't break already-deployed WinPE clients.
- **appsettings.json is fully managed by the script now** — there's no manual JSON edit step. Don't hand-edit it; re-run the install script with updated parameters instead.
- Rotating the API key on purpose: re-run the script with an explicit `-ApiKey <new value>`, then update it in `Submit-OSDLogs.ps1` / `Get-DriverPackages.ps1` calls in the task sequence.
