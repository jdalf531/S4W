# Configure Power BI Report Server to use a SAN

## Problem

`MISC-SCRIPTS\Config RS to use SAN-PBI.ps1` is currently an empty placeholder.
The server it targets is a Power BI Report Server (PBIRS) instance that
already has a stale Subject Alternative Name (SAN) configuration in place
(hardcoded from a previous setup). Reconfiguring a SAN by hand means editing
`rsreportserver.config` XML, running several `netsh http` urlacl commands,
and restarting the service — all error-prone to do manually, especially
when removing a previous SAN's leftover entries.

Reference: [Configure Reporting Services to use a Subject Alternative Name (SAN)](https://learn.microsoft.com/en-us/sql/reporting-services/report-server-sharepoint/configure-reporting-services-to-use-a-subject-alternative-name?view=sql-server-ver17).

## Goal

A PowerShell script that:

- Prompts for the SAN URL at runtime (no hardcoded hostname).
- Validates prerequisites ("blockers") before touching anything, and aborts
  with a clear reason if any fail.
- Replaces whatever old SAN entry is currently configured with the new one,
  in both the config file and the `netsh` urlacl reservations.
- Supports a `-WhatIf` preview mode.

Scope is Power BI Report Server specifically (per the user's environment) —
not a generic multi-product (SSRS 2016/2017/PBIRS) script. The service name,
config path, and account SID/name are fixed to PBIRS values from the MS doc.

## Fixed PBIRS values

- Service name: `PowerBIReportServer`
- Config file: `\Program Files\Microsoft Power BI Report Server\PBIRS\ReportServer\rsreportserver.config`
- Account name: `NT SERVICE\PowerBIReportServer`
- Account SID: `S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663`
- urlacl paths needed (4, per MS doc's PBIRS note): `/ReportServer`, `/Reports`, `/PowerBI`, `/wopi`

## Flow

### 1. Blocker checks (read-only, abort on first failure)

Run in this order, each printing a pass/fail line:

1. **Elevation** — script is running as Administrator. Abort otherwise
   (editing under Program Files and `netsh http` both require it).
2. **Service + config file present** — `Get-Service PowerBIReportServer`
   resolves, and the config file exists at the fixed PBIRS path. Abort
   otherwise (wrong machine / not installed).
3. **TLS port discoverable** — parse `rsreportserver.config` for the
   `https://+:<port>` wildcard `<URL>` entry inside `ReportServerWebService`.
   This is the port bound via Report Server Configuration Manager. Abort if
   no such entry exists — binding a cert to a port is a prerequisite done in
   Configuration Manager, this script does not do it.
4. **Cert covers the new hostname** — run `netsh http show sslcert
   ipport=0.0.0.0:<port>`, extract the certificate hash, load it from
   `Cert:\LocalMachine\My` by thumbprint. Abort if:
   - the cert isn't found in the store,
   - it has no private key (`HasPrivateKey -eq $false`),
   - it's self-signed (`Issuer -eq Subject`),
   - its Subject Alternative Name extension does not include the hostname
     just entered (case-insensitive match).
5. **No existing urlacl conflict** — `netsh http show urlacl` does not
   already contain a reservation for `https://<newhost>:<port>/ReportServer`
   (or the other 3 paths). Abort with a conflict message if any exist —
   this indicates the new hostname is already partially configured and
   needs manual cleanup first.

The hostname is needed for checks 4 and 5, so the URL prompt (step 2 below)
happens before those two checks, after checks 1–3.

### 2. Prompt

`Read-Host "Enter the full URL for the SAN (e.g. https://reports.contoso.com)"`.
Parse with `[Uri]` to extract the host; reject (re-prompt once, then abort)
if it doesn't parse or the scheme isn't `https`.

### 3. Identify old SAN entries

In both the `ReportServerWebService` and `ReportServerWebApp` `<Service>`
sections of the config, any `<URL>` element whose `UrlString` host portion
is not `+` is a previous SAN entry. Collect these for removal. The
`https://+:<port>` wildcard entries are never touched.

If no old SAN entries are found (first-time setup rather than "old config in
place"), that's fine — just skip removal and proceed to add the new one.

### 4. `-WhatIf` preview

If `-WhatIf` is passed, print and exit without changing anything:

- Old SAN `<URL>` entries found (or "none") and that they'd be removed.
- The new `<URL>` block that would be added, for both sections.
- The urlacl reservations that would be deleted (old hostname, if any) and
  added (new hostname) — all 4 paths.
- That the `PowerBIReportServer` service would be restarted.

### 5. Apply

1. Copy `rsreportserver.config` to
   `rsreportserver.config.bak-<yyyyMMddHHmmss>` in the same folder.
2. Load the config as XML, remove old-SAN `<URL>` nodes from both sections,
   add a new `<URL>` node to both sections — same `AccountSid`/`AccountName`
   as their sibling wildcard entry, `UrlString` = `https://<newhost>:<port>`.
   Save the file.
3. If an old SAN hostname existed, run `netsh http delete urlacl
   url=https://<oldhost>:<port>/<path>` for each of the 4 paths (ignore "not
   found" errors — the reservation may not have existed for all 4).
4. Run `netsh http add urlacl url=https://<newhost>:<port>/<path>
   user="NT SERVICE\PowerBIReportServer"
   sddl=D:(A;;GX;;;S-1-5-80-1730998386-2757299892-37364343-1607169425-3512908663)`
   for each of the 4 paths.
5. Restart the `PowerBIReportServer` service (`Restart-Service`), wait for
   `Running` status, and report success/failure.

### Logging

Console output for every check and step (pass/fail, what changed), plus a
timestamped log file written next to the script (`SAN-Config-Log.txt`),
consistent with the `Write-Log` pattern used in
`DailyAppUpdate\DailyAppUpdatev2.ps1`.

## Error handling

Any failure during the apply phase (steps 5.1–5.5) stops the script
immediately with a clear message pointing at the `.bak-` file for manual
rollback. No automatic rollback is attempted — partial `netsh` state is
easier to reason about from the log than from an automated undo.

## Out of scope

- Binding the TLS certificate to the port in the first place (Configuration
  Manager GUI step from the MS doc) — this script assumes that's already
  done, which the "old config in place" context confirms.
- Support for SSRS (non-PowerBI) report servers.
- DNS resolution checks on the hostname.
