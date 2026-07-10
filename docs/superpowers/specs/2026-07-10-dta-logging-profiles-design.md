# DTA Logging Info profiles

## Problem

The "DTA Logging Info" panel in `TransferDriveTool-V3.ps1` (Authorizing
Manager, Source System, Destination System, File Classification, Media
Used, Justification, Scan/Review Verification) hardcodes one organization's
default values directly in the XAML (`"Kevin Rockel"`, `"Aegis Fortress L3 -
121400002465"`, etc.). Every launch, regardless of who's running the tool
or which group they belong to, pre-populates these fields with the same
person's/group's defaults. This blocks the tool from being handed to other
teams or used more generally — each group would need to hand-edit the
script to change its own defaults, and switching between groups on the same
install means manually retyping all seven fields every time.

## Goal

Let users save named sets of these seven field values ("profiles",
representing different user groups) and switch between them via a dropdown,
without touching the script. Out of scope (per explicit descope decision):
the hardcoded preset user list and its Source/Destination path table — this
change touches only the DTA Logging Info fields.

## Storage

Profiles are stored in `$PSScriptRoot\Profiles.json` — next to the script
file itself, not in a fixed machine-local path like `C:\VIPER\DTA`. This
tool is copied as a single file onto a physical transfer drive and run from
both a writable commercial-side machine and a read-only classified/MPN-side
machine; storing profiles beside the script means they travel with that
drive between both, rather than being tied to whichever machine happens to
run the tool at a given moment.

This has a direct consequence: on the classified/MPN side, where the drive
is mounted read-only, saving or deleting a profile will fail (the file
can't be written), while loading/reading a profile for auto-fill works
fine (that's just a file read). See "Read-only handling" below.

Format: a flat JSON object, profile name as key, its seven field values as
a nested object:

```json
{
  "Group A": {
    "Manager": "Jane Doe",
    "SourceSystem": "Commercial",
    "DestSystem": "MPN DTA Station",
    "Classification": "Unclassified",
    "MediaUsed": "USB Drive",
    "Justification": "NA",
    "ScanVerify": "Jane Doe"
  }
}
```

## UI Changes

- Remove the hardcoded `Text="..."` defaults from all seven TextBoxes
  (`txtManager`, `txtSourceSystem`, `txtDestSystem`, `txtClassification`,
  `txtMediaUsed`, `txtJustification`, `txtScanVerify`) in the XAML — they
  start blank until a profile is loaded or the user types values manually
  (manual typing without ever touching a profile continues to work exactly
  as it does today; profiles are a convenience layer, not a gate).
- Add three new controls to the right of the existing "DTA Logging Info"
  header: an editable `ComboBox` (`cbProfile`, blank by default,
  `IsEditable="True"`), and two buttons (`btnSaveProfile`,
  `btnDeleteProfile`).
- At launch, `cbProfile.ItemsSource` is populated from the keys of
  `Profiles.json` if it exists and parses; if the file is missing or fails
  to parse, start with an empty list (not an error) — this is the expected
  state on a fresh install/new drive.

## Behavior

- **Load**: selecting an existing name from `cbProfile`'s dropdown list
  fills all seven TextBoxes from that profile's stored values immediately.
- **Save**: clicking `btnSaveProfile` takes whatever name is currently in
  `cbProfile` (typed or selected) and the seven TextBoxes' current values,
  and writes/overwrites that profile in `Profiles.json`. A new (not
  previously existing) name creates a new profile; an existing name
  overwrites it. A blank/whitespace-only name is rejected with a status
  message and nothing is written. After a successful save, `cbProfile`'s
  item list is refreshed to include the (possibly new) name.
- **Delete**: clicking `btnDeleteProfile` removes whichever name is
  currently in `cbProfile` from `Profiles.json`, after a confirmation
  prompt (`System.Windows.MessageBox`, Yes/No). On confirmation, the
  profile is removed, the item list refreshes, and `cbProfile` plus the
  seven TextBoxes are cleared. Deleting a name that isn't an existing
  profile (e.g. leftover typed text) is a no-op with a status message.
- **Read-only handling**: Save and Delete are always enabled — no
  preemptive read-only detection. If the actual file write fails (e.g. the
  script is running from a read-only-mounted drive), the failure is caught
  and reported via the existing `Write-Status` mechanism (e.g. "Cannot save
  profile: this location appears to be read-only"), and the rest of the
  app continues working normally. This matches how the tool already
  handles other failure conditions (retries, CSV logging errors) rather
  than introducing a new disabled-state concept.

## Functions

- `Get-DtaProfiles` — reads `$PSScriptRoot\Profiles.json`, returns an
  ordered hashtable of profile name → field-value hashtable. Returns an
  empty hashtable (not an error) if the file doesn't exist or fails to
  parse as JSON (a corrupt file is logged via `Write-Status`, not fatal).
- `Save-DtaProfiles` — takes the in-memory profile hashtable, serializes it
  to JSON, and writes it to `$PSScriptRoot\Profiles.json`. Throws on
  failure (caught by the Save/Delete click handlers, per "Read-only
  handling" above) rather than swallowing the error itself, so both call
  sites can report it distinctly ("Cannot save profile" vs "Cannot delete
  profile").

## Error handling

- Corrupt/unparseable `Profiles.json` at launch: treated as empty, logged
  once via `Write-Status`, tool continues normally (does not block
  startup).
- Save with a blank name: rejected before attempting any write, status
  message shown.
- Save/Delete write failure (read-only media, permissions, etc.): caught
  at the point of the actual file write, status message shown, no crash.
- Delete of a non-existent name: no-op, status message shown, no
  confirmation prompt needed since there's nothing to confirm deleting.

## Testing

No test framework exists for this script; verification follows the same
pattern used throughout this codebase: a throwaway scratch script that
imports `Get-DtaProfiles`/`Save-DtaProfiles` via AST extraction (not the
whole GUI) and exercises:

1. Loading when `Profiles.json` doesn't exist → empty result, no error.
2. Loading a valid `Profiles.json` → correct profile names and field
   values.
3. Loading a corrupt/malformed `Profiles.json` → empty result, no crash.
4. Save creates a new profile file when none existed.
5. Save adds a new profile alongside existing ones without disturbing them.
6. Save overwrites an existing profile's values.
7. Save with a blank name is rejected (no file write attempted).
8. Delete removes only the named profile, leaving others intact.
9. Delete of a non-existent name is a safe no-op.
10. Simulated write failure (e.g. a read-only file or directory) is caught
    and does not throw out of the click handler.

A full UI click-through (does the ComboBox actually populate the
TextBoxes, does Save actually appear in the dropdown afterward) needs a
real run by the user, the same way async-transfer verification did earlier
in this project — it can't be fully driven from this environment.

## Out of scope

- The hardcoded preset user list and Source/Destination path table (a
  separate, larger effort per an explicit scope decision during
  brainstorming).
- Warning the user about unsaved edits when switching profiles.
- Importing/exporting profiles between different drives/installs beyond
  what copying `Profiles.json` alongside the script already provides for
  free.
