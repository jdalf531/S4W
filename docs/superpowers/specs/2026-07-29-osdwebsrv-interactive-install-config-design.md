# Interactive environment configuration for OSDWebSRV-MPN install

## Problem

`appsettings.json` ships with hardcoded placeholder values (`MECM-SERVER-FQDN`,
`PS1`, `REPLACE-WITH-A-STRONG-RANDOM-KEY`) that today require a manual JSON
edit on the IIS server after `Install-OsdWebService.ps1` finishes. This is
easy to forget and doesn't fit a project meant to be tuned per-environment
without hand-editing checked-in config.

## Goal

`Install-OsdWebService.ps1` collects the environment-specific values
(MECM site server, MECM site code, API key) and writes them into the
published `appsettings.json` itself, so there is no manual config-editing
step left after the script completes.

## New/changed parameters

- `-MecmSiteServer` (optional string) — MECM site server FQDN/hostname.
- `-MecmSiteCode` (optional string) — three-character MECM site code.
- `-ApiKey` (optional string) — if omitted, auto-generated.
- `-LogStoragePath` — unchanged. It already has a parameter + sensible
  default (`C:\OSDLogs`), so it already satisfies "not hardcoded."

## Flow

### 1. Validate + collect, before any system changes

Moved earlier than today (currently this check happens in the IIS-website
step): validate `-PublishPath` exists and contains an `appsettings.json`
file. Abort with a clear error otherwise — fail fast before installing IIS
features or touching the app pool.

Then, for each of `-MecmSiteServer` / `-MecmSiteCode` left blank, prompt:

- `Read-Host "Enter your MECM site server (hostname or FQDN)"` — re-prompt
  on empty input.
- `Read-Host "Enter your MECM site code (3 characters)"` — validate against
  `^[A-Za-z0-9]{3}$`, re-prompt on mismatch.

If `-ApiKey` is blank, auto-generate one:
`[System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))`
(the same method already documented in the README). Print it once with a
"record this now — it will not be shown again" warning, since it's needed
to configure `Submit-OSDLogs.ps1` / `Get-DriverPackages.ps1` on WinPE clients.

### 2. Write the values into appsettings.json

Read `appsettings.json` from `$PublishPath` as text and replace just the
four value lines (`ApiKey`, `LogStorage.BasePath`, `Mecm.SiteServer`,
`Mecm.SiteCode`) via targeted regex substitution, then write the file back.

This is deliberately *not* a full `ConvertFrom-Json` / `ConvertTo-Json`
round-trip: the file's inline `//` comments documenting each setting would
be stripped by a full parse/re-serialize. Regex substitution on known,
unique key names preserves the rest of the file untouched.

Extract this into a standalone function, e.g. `Set-OsdAppSetting -Path
-Key -Value`, so it can be unit tested with Pester independent of the rest
of the (IIS-dependent) install script — matching the Pester pattern already
used for `Config RS to use SAN-PBI.ps1` in this repo.

Values are JSON-escaped before substitution (backslash and double-quote)
so a Windows path like `C:\OSDLogs` round-trips correctly.

### 3. Updated final summary

Remove the "Edit appsettings.json in ... and set: ApiKey / LogStorage /
Mecm..." instructions from the closing banner — that step no longer
exists. Keep the restart-app-pool and health-check instructions, and add
a line re-printing the ApiKey (auto-generated or supplied) so it's visible
one more time before the console output scrolls away.

## Testing

No IIS server is available for an end-to-end run, so the safety net is
Pester coverage of `Set-OsdAppSetting` (the extracted regex-substitution
function): given a sample `appsettings.json` fixture, verify each of the
four keys is replaced correctly, comments and untouched keys survive, and
special characters (backslashes in paths) round-trip correctly.

## Out of scope

- Changing `LogStoragePath` handling — already parameter-driven.
- Validating that the supplied MECM site server is actually reachable, or
  that the site code matches a real MECM site — this script has no network
  dependency on MECM today and this change doesn't introduce one.
- Encrypting or otherwise protecting the ApiKey at rest in appsettings.json
  beyond what already exists (plaintext config file, same as before).
