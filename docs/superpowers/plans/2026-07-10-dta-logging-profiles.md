# DTA Logging Info Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded, single-organization defaults in the "DTA Logging Info" fields with named, saveable/loadable profiles, so the tool can be handed to other groups without editing the script.

**Architecture:** A profile is a named set of the 7 DTA Logging Info field values, stored as JSON next to the script (`$PSScriptRoot\Profiles.json`) so it travels with the tool when copied onto a transfer drive. An editable ComboBox plus Save/Delete buttons sit next to the "DTA Logging Info" header; selecting a name loads its values into the 7 fields, Save writes the current field values under whatever name is in the box (new name = new profile, existing name = overwrite), Delete removes the named profile after confirmation.

**Tech Stack:** Windows PowerShell 5.1, WPF (already loaded in the script), no external modules. `ConvertTo-Json`/`ConvertFrom-Json` for the profile file.

**Spec:** `docs/superpowers/specs/2026-07-10-dta-logging-profiles-design.md`

## Global Constraints

- Single-file script (`TransferDriveTool/TransferDriveTool-V3.ps1`) — no new files added to the repo. `Profiles.json` is a runtime data file (created next to the script when a profile is first saved), not something committed to the repo.
- Profiles are stored at `$PSScriptRoot\Profiles.json` — not `C:\VIPER\DTA` or any other fixed machine path — specifically so they travel with the script when copied onto a transfer drive between the writable commercial side and the read-only classified/MPN side.
- Save/Delete are always enabled (no preemptive read-only detection). A write failure is caught at the point of the actual file write and reported via `Write-Status`; it must never crash the app or leave the in-memory profile list in a state that doesn't match what's actually on disk (a failed save must not appear to have succeeded, e.g. in the dropdown).
- A missing or corrupt `Profiles.json` at launch is not an error — start with an empty profile list.
- No test framework exists for this script — verification is ad hoc PowerShell run manually, matching the pattern already used throughout this codebase (AST-extracting individual functions from the real script file rather than duplicating their text in test files).

---

## File Structure

All changes are in `TransferDriveTool/TransferDriveTool-V3.ps1`:

- **XAML block**: the "DTA Logging Info" header (~line 438) gains an editable `ComboBox` (`cbProfile`) and two `Button`s (`btnSaveProfile`, `btnDeleteProfile`) alongside it. The 7 existing `TextBox` controls in that section lose their hardcoded `Text="..."` defaults.
- **UI control bindings** (~line 638, alongside the existing "Global metadata" bindings): 3 new `$Window.FindName(...)` lines.
- **New functions `Get-DtaProfiles` / `Save-DtaProfiles`**: added right after `Write-Status`'s definition (~line 721), since `Get-DtaProfiles` needs `Write-Status` to report a corrupt file.
- **New wiring**: populates `$cbProfile.ItemsSource` at launch and registers the three event handlers (`cbProfile.SelectionChanged`, `btnSaveProfile.Click`, `btnDeleteProfile.Click`), added in the same new section right after the two functions.

No other existing code changes. Nothing about the preset user list, Source/Destination paths, or domain detection is touched — that's explicitly out of scope per the spec.

---

### Task 1: Add profile controls to the UI

**Files:**
- Modify: `TransferDriveTool/TransferDriveTool-V3.ps1` (XAML block, "DTA Logging Info" header ~line 438 and the 7 TextBoxes immediately below it ~line 460-493; UI control bindings ~line 638-645)
- Test: ad hoc PowerShell in the scratchpad (headless XAML load + `FindName`, matching the pattern used for prior UI-only tasks in this codebase)

**Interfaces:**
- Produces: WPF controls named `cbProfile` (editable `ComboBox`), `btnSaveProfile` (`Button`), `btnDeleteProfile` (`Button`), and PowerShell variables `$cbProfile` / `$btnSaveProfile` / `$btnDeleteProfile` bound via `$Window.FindName(...)`, for Task 2 to wire up. The 7 existing `$txtManager` / `$txtSourceSystem` / `$txtDestSystem` / `$txtClassification` / `$txtMediaUsed` / `$txtJustification` / `$txtScanVerify` variables are unchanged in name/type — only their XAML-declared default `Text` is removed.

- [ ] **Step 1: Add the profile controls next to the "DTA Logging Info" header, and remove the hardcoded field defaults**

In `TransferDriveTool/TransferDriveTool-V3.ps1`, find this block:

```xml
                <StackPanel>

                    <TextBlock Text="DTA Logging Info"
                               FontSize="20"
                               FontWeight="Bold"
                               Foreground="#FF3A3A"
                               Margin="0,0,0,10"/>

                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="220"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Label Grid.Row="0" Grid.Column="0" Content="Authorizing Manager:"/>
                        <TextBox x:Name="txtManager"
                                 Grid.Row="0" Grid.Column="1"
                                 Text="Kevin Rockel"/>

                        <Label Grid.Row="1" Grid.Column="0" Content="Source System:"/>
                        <TextBox x:Name="txtSourceSystem"
                                 Grid.Row="1" Grid.Column="1"
                                 Text="Commercial"/>

                        <Label Grid.Row="2" Grid.Column="0" Content="Destination System:"/>
                        <TextBox x:Name="txtDestSystem"
                                 Grid.Row="2" Grid.Column="1"
                                 Text="MPN DTA Station"/>

                        <Label Grid.Row="3" Grid.Column="0" Content="File Classification:"/>
                        <TextBox x:Name="txtClassification"
                                 Grid.Row="3" Grid.Column="1"
                                 Text="Unclassified"/>

                        <Label Grid.Row="4" Grid.Column="0" Content="Media Used:"/>
                        <TextBox x:Name="txtMediaUsed"
                                 Grid.Row="4" Grid.Column="1"
                                 Text="Aegis Fortress L3 - 121400002465"/>

                        <Label Grid.Row="5" Grid.Column="0" Content="Justification:"/>
                        <TextBox x:Name="txtJustification"
                                 Grid.Row="5" Grid.Column="1"
                                 Text="NA"/>

                        <Label Grid.Row="6" Grid.Column="0" Content="Scan/Review Verification:"/>
                        <TextBox x:Name="txtScanVerify"
                                 Grid.Row="6" Grid.Column="1"
                                 Text="Justin M Dobson"/>

                    </Grid>
                </StackPanel>
```

Replace it with:

```xml
                <StackPanel>

                    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                        <TextBlock Text="DTA Logging Info"
                                   FontSize="20"
                                   FontWeight="Bold"
                                   Foreground="#FF3A3A"
                                   VerticalAlignment="Center"
                                   Margin="0,0,15,0"/>

                        <ComboBox x:Name="cbProfile"
                                  Width="200"
                                  IsEditable="True"
                                  VerticalAlignment="Center"
                                  Margin="0,0,5,0"/>

                        <Button x:Name="btnSaveProfile"
                                Content="Save"
                                Width="70"
                                Margin="0,0,5,0"/>

                        <Button x:Name="btnDeleteProfile"
                                Content="Delete"
                                Width="70"/>
                    </StackPanel>

                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="220"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Label Grid.Row="0" Grid.Column="0" Content="Authorizing Manager:"/>
                        <TextBox x:Name="txtManager"
                                 Grid.Row="0" Grid.Column="1"/>

                        <Label Grid.Row="1" Grid.Column="0" Content="Source System:"/>
                        <TextBox x:Name="txtSourceSystem"
                                 Grid.Row="1" Grid.Column="1"/>

                        <Label Grid.Row="2" Grid.Column="0" Content="Destination System:"/>
                        <TextBox x:Name="txtDestSystem"
                                 Grid.Row="2" Grid.Column="1"/>

                        <Label Grid.Row="3" Grid.Column="0" Content="File Classification:"/>
                        <TextBox x:Name="txtClassification"
                                 Grid.Row="3" Grid.Column="1"/>

                        <Label Grid.Row="4" Grid.Column="0" Content="Media Used:"/>
                        <TextBox x:Name="txtMediaUsed"
                                 Grid.Row="4" Grid.Column="1"/>

                        <Label Grid.Row="5" Grid.Column="0" Content="Justification:"/>
                        <TextBox x:Name="txtJustification"
                                 Grid.Row="5" Grid.Column="1"/>

                        <Label Grid.Row="6" Grid.Column="0" Content="Scan/Review Verification:"/>
                        <TextBox x:Name="txtScanVerify"
                                 Grid.Row="6" Grid.Column="1"/>

                    </Grid>
                </StackPanel>
```

- [ ] **Step 2: Bind the new controls**

Find:

```powershell
# Global metadata
$txtManager        = $Window.FindName("txtManager")
$txtSourceSystem   = $Window.FindName("txtSourceSystem")
$txtDestSystem     = $Window.FindName("txtDestSystem")
$txtClassification = $Window.FindName("txtClassification")
$txtMediaUsed      = $Window.FindName("txtMediaUsed")
$txtJustification  = $Window.FindName("txtJustification")
$txtScanVerify     = $Window.FindName("txtScanVerify")
```

Replace with:

```powershell
# Global metadata
$txtManager        = $Window.FindName("txtManager")
$txtSourceSystem   = $Window.FindName("txtSourceSystem")
$txtDestSystem     = $Window.FindName("txtDestSystem")
$txtClassification = $Window.FindName("txtClassification")
$txtMediaUsed      = $Window.FindName("txtMediaUsed")
$txtJustification  = $Window.FindName("txtJustification")
$txtScanVerify     = $Window.FindName("txtScanVerify")

# DTA logging profiles
$cbProfile        = $Window.FindName("cbProfile")
$btnSaveProfile   = $Window.FindName("btnSaveProfile")
$btnDeleteProfile = $Window.FindName("btnDeleteProfile")
```

- [ ] **Step 3: Verify the XAML parses, the new controls resolve, and the 7 fields are blank by default**

Run:

```powershell
$scriptPath = "TransferDriveTool/TransferDriveTool-V3.ps1"
$content = Get-Content -Raw $scriptPath
$start = $content.IndexOf('$Xaml = @"')
$xamlStart = $content.IndexOf("`n", $start) + 1
$xamlEnd = $content.IndexOf('"@', $xamlStart)
$xamlText = $content.Substring($xamlStart, $xamlEnd - $xamlStart)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
$testWindow = [Windows.Markup.XamlReader]::Load($reader)
$testWindow.Dispatcher.Invoke([action]{}, "Render")

foreach ($name in "cbProfile","btnSaveProfile","btnDeleteProfile") {
    $ctrl = $testWindow.FindName($name)
    if (-not $ctrl) { throw "FindName('$name') returned null" }
}
"OK: profile controls resolve"

foreach ($name in "txtManager","txtSourceSystem","txtDestSystem","txtClassification","txtMediaUsed","txtJustification","txtScanVerify") {
    $ctrl = $testWindow.FindName($name)
    if (-not [string]::IsNullOrEmpty($ctrl.Text)) { throw "$name should be blank by default, was '$($ctrl.Text)'" }
}
"OK: all 7 DTA logging fields are blank by default"
```

Expected: `OK: profile controls resolve` then `OK: all 7 DTA logging fields are blank by default`, no errors.

- [ ] **Step 4: Full-script parse check**

Run: `powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('TransferDriveTool/TransferDriveTool-V3.ps1', [ref]$null, [ref]$e); if ($e.Count -eq 0) {'OK'} else {$e}"`

Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool/TransferDriveTool-V3.ps1
git commit -m "feat: add DTA logging profile controls to the UI

Adds an editable profile-name ComboBox plus Save/Delete buttons next
to the DTA Logging Info header, and removes the hardcoded per-org
default text from the 7 logging fields (Manager, Source/Dest System,
Classification, Media Used, Justification, Scan/Verify) so they start
blank. Not wired up yet -- that's the next task."
```

---

### Task 2: Implement profile load/save/delete

**Files:**
- Modify: `TransferDriveTool/TransferDriveTool-V3.ps1` — add `Get-DtaProfiles`/`Save-DtaProfiles` and the wiring immediately after `Write-Status`'s closing brace (~line 721), before the `# AUTO-ARCHIVE OLD DATA` section.
- Test: ad hoc PowerShell in the scratchpad — isolated function tests via AST extraction (no permanent test file, matching this codebase's established pattern), plus one fuller integration test with real WPF controls.

**Interfaces:**
- Consumes: `$cbProfile`, `$btnSaveProfile`, `$btnDeleteProfile`, and the 7 `$txt*` field variables from Task 1; `Write-Status` (existing function, `Write-Status -msg <string>` — called positionally as `Write-Status "..."` elsewhere in this file).
- Produces: `Get-DtaProfiles` (no params, returns `[ordered]` dictionary of profile name → field-value dictionary, read from `$ProfilesPath`), `Save-DtaProfiles -Profiles <IDictionary>` (writes the given dictionary to `$ProfilesPath` as JSON, throws on failure — callers catch it), and the script-scope `$ProfilesPath` / `$dtaProfiles` variables. No later task depends on these, but they must exist under exactly these names since the test in this task's Step 4 refers to them.

- [ ] **Step 1: Add `Get-DtaProfiles` and `Save-DtaProfiles`**

Find:

```powershell
function Write-Status {
    param([string]$msg)

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $msg"

    $txtStatus.AppendText("$line`r`n")
    $txtStatus.ScrollToEnd()

    Add-Content -Path $LogFile -Value $line
}

# ============================
# AUTO-ARCHIVE OLD DATA (Commercial mode only)
```

Replace with:

```powershell
function Write-Status {
    param([string]$msg)

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$timestamp] $msg"

    $txtStatus.AppendText("$line`r`n")
    $txtStatus.ScrollToEnd()

    Add-Content -Path $LogFile -Value $line
}

# ============================
# DTA LOGGING PROFILES
# ============================
# Stored next to the script itself, not a fixed machine path like
# C:\VIPER\DTA -- this tool is copied as a single file onto a transfer
# drive and run from both the writable commercial side and the
# read-only classified/MPN side, so profiles need to travel with it.
$ProfilesPath = Join-Path $PSScriptRoot "Profiles.json"

function Get-DtaProfiles {
    if (-not (Test-Path -LiteralPath $ProfilesPath)) {
        return [ordered]@{}
    }

    try {
        $raw = Get-Content -LiteralPath $ProfilesPath -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

        $profiles = [ordered]@{}
        foreach ($property in $parsed.PSObject.Properties) {
            $profiles[$property.Name] = $property.Value
        }
        return $profiles
    }
    catch {
        Write-Status "Profiles.json is unreadable or corrupt, starting with an empty profile list: $($_.Exception.Message)"
        return [ordered]@{}
    }
}

function Save-DtaProfiles {
    param($Profiles)
    $json = $Profiles | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $ProfilesPath -Value $json -ErrorAction Stop
}

function Set-DtaProfileFields {
    param([string]$ProfileName)
    if (-not $dtaProfiles.Contains($ProfileName)) { return }
    $p = $dtaProfiles[$ProfileName]
    $txtManager.Text        = $p.Manager
    $txtSourceSystem.Text   = $p.SourceSystem
    $txtDestSystem.Text     = $p.DestSystem
    $txtClassification.Text = $p.Classification
    $txtMediaUsed.Text      = $p.MediaUsed
    $txtJustification.Text  = $p.Justification
    $txtScanVerify.Text     = $p.ScanVerify
}

$dtaProfiles = Get-DtaProfiles
$cbProfile.ItemsSource = @($dtaProfiles.Keys)

$cbProfile.Add_SelectionChanged({
    if ($cbProfile.SelectedItem) {
        Set-DtaProfileFields -ProfileName $cbProfile.SelectedItem
    }
})

$btnSaveProfile.Add_Click({
    $name = $cbProfile.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Status "Cannot save profile: enter a profile name first."
        return
    }

    $previous = if ($dtaProfiles.Contains($name)) { $dtaProfiles[$name] } else { $null }

    $dtaProfiles[$name] = [ordered]@{
        Manager        = $txtManager.Text
        SourceSystem   = $txtSourceSystem.Text
        DestSystem     = $txtDestSystem.Text
        Classification = $txtClassification.Text
        MediaUsed      = $txtMediaUsed.Text
        Justification  = $txtJustification.Text
        ScanVerify     = $txtScanVerify.Text
    }

    try {
        Save-DtaProfiles -Profiles $dtaProfiles
        $cbProfile.ItemsSource = @($dtaProfiles.Keys)
        $cbProfile.Text = $name
        Write-Status "Saved profile: $name"
    }
    catch {
        if ($null -ne $previous) { $dtaProfiles[$name] = $previous } else { $dtaProfiles.Remove($name) }
        Write-Status "Cannot save profile: this location appears to be read-only. ($($_.Exception.Message))"
    }
})

$btnDeleteProfile.Add_Click({
    $name = $cbProfile.Text.Trim()
    if (-not $dtaProfiles.Contains($name)) {
        Write-Status "Cannot delete profile: '$name' is not a saved profile."
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Delete profile '$name'? This cannot be undone.",
        "Delete Profile",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }

    $removed = $dtaProfiles[$name]
    $dtaProfiles.Remove($name)

    try {
        Save-DtaProfiles -Profiles $dtaProfiles
        $cbProfile.ItemsSource = @($dtaProfiles.Keys)
        $cbProfile.Text = ""
        $txtManager.Text = ""
        $txtSourceSystem.Text = ""
        $txtDestSystem.Text = ""
        $txtClassification.Text = ""
        $txtMediaUsed.Text = ""
        $txtJustification.Text = ""
        $txtScanVerify.Text = ""
        Write-Status "Deleted profile: $name"
    }
    catch {
        $dtaProfiles[$name] = $removed
        Write-Status "Cannot delete profile: this location appears to be read-only. ($($_.Exception.Message))"
    }
})

# ============================
# AUTO-ARCHIVE OLD DATA (Commercial mode only)
```

- [ ] **Step 2: Write and run the isolated function tests**

Create `$env:TEMP\Test-DtaProfiles.ps1`:

```powershell
param([string]$ScriptPath = "TransferDriveTool/TransferDriveTool-V3.ps1")

function Import-SingleFunction {
    param([string]$Path, [string]$FunctionName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $funcAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $FunctionName }, $true) | Select-Object -First 1
    if (-not $funcAst) { throw "Function '$FunctionName' not found in $Path" }
    $defText = "function global:$FunctionName $($funcAst.Body.Extent.Text)"
    . ([scriptblock]::Create($defText))
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Output "PASS: $Message"
}

$script:WriteStatusLog = New-Object System.Collections.Generic.List[string]
function Write-Status([string]$msg) { $script:WriteStatusLog.Add($msg) }

Import-SingleFunction -Path $ScriptPath -FunctionName "Get-DtaProfiles"
Import-SingleFunction -Path $ScriptPath -FunctionName "Save-DtaProfiles"

$scratch = Join-Path $env:TEMP ("dtaprofiles_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    # ---- Test A: no Profiles.json yet -> empty result, no error ----
    $ProfilesPath = Join-Path $scratch "Profiles.json"
    $resultA = Get-DtaProfiles
    Assert-True ($resultA.Count -eq 0) "Test A: missing Profiles.json returns an empty set"

    # ---- Test B: save creates the file; a fresh Get-DtaProfiles reads it back correctly ----
    $profilesB = [ordered]@{
        "Group A" = [ordered]@{ Manager="Jane Doe"; SourceSystem="Commercial"; DestSystem="MPN"; Classification="Unclassified"; MediaUsed="USB"; Justification="NA"; ScanVerify="Jane Doe" }
    }
    Save-DtaProfiles -Profiles $profilesB
    Assert-True (Test-Path $ProfilesPath) "Test B: Save-DtaProfiles created Profiles.json"

    $resultB = Get-DtaProfiles
    Assert-True ($resultB.Count -eq 1) "Test B: one profile read back"
    Assert-True ($resultB["Group A"].Manager -eq "Jane Doe") "Test B: field values round-trip correctly"

    # ---- Test C: saving a second profile preserves the first ----
    $profilesC = [ordered]@{}
    foreach ($key in $resultB.Keys) { $profilesC[$key] = $resultB[$key] }
    $profilesC["Group B"] = [ordered]@{ Manager="John Smith"; SourceSystem="Commercial"; DestSystem="MPN"; Classification="Confidential"; MediaUsed="HDD"; Justification="Backup"; ScanVerify="John Smith" }
    Save-DtaProfiles -Profiles $profilesC

    $resultC = Get-DtaProfiles
    Assert-True ($resultC.Count -eq 2) "Test C: both profiles present after adding a second"
    Assert-True ($resultC["Group A"].Manager -eq "Jane Doe") "Test C: first profile untouched by adding a second"
    Assert-True ($resultC["Group B"].Manager -eq "John Smith") "Test C: second profile saved correctly"

    # ---- Test D: overwriting an existing profile's values ----
    $profilesD = [ordered]@{}
    foreach ($key in $resultC.Keys) { $profilesD[$key] = $resultC[$key] }
    $profilesD["Group A"] = [ordered]@{ Manager="Jane D. Updated"; SourceSystem="Commercial"; DestSystem="MPN"; Classification="Unclassified"; MediaUsed="USB"; Justification="NA"; ScanVerify="Jane Doe" }
    Save-DtaProfiles -Profiles $profilesD

    $resultD = Get-DtaProfiles
    Assert-True ($resultD.Count -eq 2) "Test D: still exactly 2 profiles after overwrite (no duplicate)"
    Assert-True ($resultD["Group A"].Manager -eq "Jane D. Updated") "Test D: overwrite updated the value"

    # ---- Test E: deleting a profile removes only that one ----
    $profilesE = [ordered]@{}
    foreach ($key in $resultD.Keys) { if ($key -ne "Group B") { $profilesE[$key] = $resultD[$key] } }
    Save-DtaProfiles -Profiles $profilesE

    $resultE = Get-DtaProfiles
    Assert-True ($resultE.Count -eq 1) "Test E: one profile remains after deleting the other"
    Assert-True (-not $resultE.Contains("Group B")) "Test E: deleted profile is gone"
    Assert-True ($resultE.Contains("Group A")) "Test E: remaining profile untouched"

    # ---- Test F: corrupt Profiles.json is treated as empty, not fatal ----
    Set-Content -Path $ProfilesPath -Value "{ this is not valid json"
    $script:WriteStatusLog.Clear()
    $resultF = Get-DtaProfiles
    Assert-True ($resultF.Count -eq 0) "Test F: corrupt file returns an empty set"
    Assert-True ($script:WriteStatusLog.Count -eq 1) "Test F: corrupt file is reported via Write-Status exactly once"

    # ---- Test G: a write failure (invalid path) throws, doesn't silently succeed ----
    $ProfilesPath = "Z:\this_drive_does_not_exist\Profiles.json"
    $threw = $false
    try { Save-DtaProfiles -Profiles ([ordered]@{ "X" = [ordered]@{ Manager = "a" } }) }
    catch { $threw = $true }
    Assert-True $threw "Test G: Save-DtaProfiles throws on an unwritable path instead of failing silently"

    Write-Output "ALL TESTS PASSED"
}
finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
```

Run: `powershell -NoProfile -File "$env:TEMP\Test-DtaProfiles.ps1" -ScriptPath "TransferDriveTool/TransferDriveTool-V3.ps1"`

Expected: a series of `PASS:` lines ending in `ALL TESTS PASSED`.

- [ ] **Step 3: Write and run the UI integration test**

Create `$env:TEMP\Test-DtaProfilesUI.ps1`:

```powershell
param([string]$ScriptPath = "TransferDriveTool/TransferDriveTool-V3.ps1")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Output "PASS: $Message"
}

# Real (unshown) controls -- exercises the exact same object types the real
# XAML-bound controls have, without loading a Window or the rest of the
# script (which would pop the GUI).
$cbProfile = New-Object System.Windows.Controls.ComboBox
$cbProfile.IsEditable = $true
$btnSaveProfile = New-Object System.Windows.Controls.Button
$btnDeleteProfile = New-Object System.Windows.Controls.Button
$txtManager = New-Object System.Windows.Controls.TextBox
$txtSourceSystem = New-Object System.Windows.Controls.TextBox
$txtDestSystem = New-Object System.Windows.Controls.TextBox
$txtClassification = New-Object System.Windows.Controls.TextBox
$txtMediaUsed = New-Object System.Windows.Controls.TextBox
$txtJustification = New-Object System.Windows.Controls.TextBox
$txtScanVerify = New-Object System.Windows.Controls.TextBox

$script:WriteStatusLog = New-Object System.Collections.Generic.List[string]
function Write-Status([string]$msg) { $script:WriteStatusLog.Add($msg) }

$scratch = Join-Path $env:TEMP ("dtaprofilesui_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$ProfilesPath = Join-Path $scratch "Profiles.json"

function Import-SingleFunction {
    param([string]$Path, [string]$FunctionName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $funcAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $FunctionName }, $true) | Select-Object -First 1
    if (-not $funcAst) { throw "Function '$FunctionName' not found in $Path" }
    $defText = "function global:$FunctionName $($funcAst.Body.Extent.Text)"
    . ([scriptblock]::Create($defText))
}
Import-SingleFunction -Path $ScriptPath -FunctionName "Get-DtaProfiles"
Import-SingleFunction -Path $ScriptPath -FunctionName "Save-DtaProfiles"
Import-SingleFunction -Path $ScriptPath -FunctionName "Set-DtaProfileFields"

# Re-create the same wiring Task 2 Step 1 adds to the real script, using the
# mocked controls above -- this is the same event-handler code, just bound
# to test doubles instead of the real XAML tree.
$dtaProfiles = Get-DtaProfiles
$cbProfile.ItemsSource = @($dtaProfiles.Keys)

$cbProfile.Add_SelectionChanged({
    if ($cbProfile.SelectedItem) {
        Set-DtaProfileFields -ProfileName $cbProfile.SelectedItem
    }
}.GetNewClosure())

$btnSaveProfile.Add_Click({
    $name = $cbProfile.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Status "Cannot save profile: enter a profile name first."
        return
    }
    $previous = if ($dtaProfiles.Contains($name)) { $dtaProfiles[$name] } else { $null }
    $dtaProfiles[$name] = [ordered]@{
        Manager = $txtManager.Text; SourceSystem = $txtSourceSystem.Text; DestSystem = $txtDestSystem.Text
        Classification = $txtClassification.Text; MediaUsed = $txtMediaUsed.Text
        Justification = $txtJustification.Text; ScanVerify = $txtScanVerify.Text
    }
    try {
        Save-DtaProfiles -Profiles $dtaProfiles
        $cbProfile.ItemsSource = @($dtaProfiles.Keys)
        $cbProfile.Text = $name
        Write-Status "Saved profile: $name"
    }
    catch {
        if ($null -ne $previous) { $dtaProfiles[$name] = $previous } else { $dtaProfiles.Remove($name) }
        Write-Status "Cannot save profile: this location appears to be read-only. ($($_.Exception.Message))"
    }
}.GetNewClosure())

$btnDeleteProfile.Add_Click({
    $name = $cbProfile.Text.Trim()
    if (-not $dtaProfiles.Contains($name)) {
        Write-Status "Cannot delete profile: '$name' is not a saved profile."
        return
    }
    $removed = $dtaProfiles[$name]
    $dtaProfiles.Remove($name)
    try {
        Save-DtaProfiles -Profiles $dtaProfiles
        $cbProfile.ItemsSource = @($dtaProfiles.Keys)
        $cbProfile.Text = ""
        $txtManager.Text = ""; $txtSourceSystem.Text = ""; $txtDestSystem.Text = ""
        $txtClassification.Text = ""; $txtMediaUsed.Text = ""; $txtJustification.Text = ""; $txtScanVerify.Text = ""
        Write-Status "Deleted profile: $name"
    }
    catch {
        $dtaProfiles[$name] = $removed
        Write-Status "Cannot delete profile: this location appears to be read-only. ($($_.Exception.Message))"
    }
}.GetNewClosure())

# ---- Scenario 1: Save with a blank name is rejected ----
$cbProfile.Text = "   "
$btnSaveProfile.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert-True ($dtaProfiles.Count -eq 0) "Scenario 1: blank-name save did not create a profile"
Assert-True (-not (Test-Path $ProfilesPath)) "Scenario 1: blank-name save did not write Profiles.json"

# ---- Scenario 2: Save creates a new profile and it appears in the dropdown ----
$cbProfile.Text = "Group A"
$txtManager.Text = "Jane Doe"
$txtSourceSystem.Text = "Commercial"
$txtDestSystem.Text = "MPN"
$txtClassification.Text = "Unclassified"
$txtMediaUsed.Text = "USB"
$txtJustification.Text = "NA"
$txtScanVerify.Text = "Jane Doe"
$btnSaveProfile.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert-True ($cbProfile.ItemsSource -contains "Group A") "Scenario 2: new profile appears in the dropdown after Save"
Assert-True ((Get-Content $ProfilesPath -Raw) -like "*Jane Doe*") "Scenario 2: Profiles.json actually contains the saved value"

# ---- Scenario 3: Loading clears and re-fills all 7 fields ----
$txtManager.Text = "someone else"
$cbProfile.SelectedItem = "Group A"
Assert-True ($txtManager.Text -eq "Jane Doe") "Scenario 3: selecting a profile restores its Manager value"
Assert-True ($txtDestSystem.Text -eq "MPN") "Scenario 3: selecting a profile restores its DestSystem value"

# ---- Scenario 4: Delete removes the profile and clears the fields ----
$cbProfile.Text = "Group A"
$cbProfile.SelectedItem = $null
$btnDeleteProfile.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert-True (-not ($cbProfile.ItemsSource -contains "Group A")) "Scenario 4: deleted profile no longer in the dropdown"
Assert-True ([string]::IsNullOrEmpty($txtManager.Text)) "Scenario 4: fields cleared after delete"
Assert-True ((Get-Content $ProfilesPath -Raw) -notlike "*Jane Doe*") "Scenario 4: Profiles.json no longer contains the deleted profile's data"

# ---- Scenario 4b: deleting a name that isn't a saved profile is a safe no-op ----
# (If the early-return check were missing, this would instead reach
# MessageBox.Show and hang waiting for a real click, which would time out
# this test -- so reaching "ALL TESTS PASSED" below is itself part of the
# evidence this path never shows a confirmation dialog.)
$cbProfile.Text = "NonexistentProfile"
$script:WriteStatusLog.Clear()
$btnDeleteProfile.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert-True ($script:WriteStatusLog.Count -eq 1 -and $script:WriteStatusLog[0] -like "*not a saved profile*") "Scenario 4b: deleting a non-existent profile name logs a clear message"

# ---- Scenario 5: a write failure on Save is caught, doesn't crash, and doesn't corrupt in-memory state ----
$goodPath = $ProfilesPath
$ProfilesPath = "Z:\this_drive_does_not_exist\Profiles.json"
$cbProfile.Text = "Group C"
$txtManager.Text = "Someone"
$script:WriteStatusLog.Clear()
$btnSaveProfile.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
Assert-True (-not $dtaProfiles.Contains("Group C")) "Scenario 5: failed save does not leave a phantom profile in memory"
Assert-True ($script:WriteStatusLog.Count -eq 1 -and $script:WriteStatusLog[0] -like "*read-only*") "Scenario 5: failed save reports a clear read-only-style message"
$ProfilesPath = $goodPath

Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "ALL TESTS PASSED"
```

Run: `powershell -NoProfile -File "$env:TEMP\Test-DtaProfilesUI.ps1" -ScriptPath "TransferDriveTool/TransferDriveTool-V3.ps1"`

Expected: a series of `PASS:` lines ending in `ALL TESTS PASSED`.

- [ ] **Step 4: Full-script parse check**

Run: `powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('TransferDriveTool/TransferDriveTool-V3.ps1', [ref]$null, [ref]$e); if ($e.Count -eq 0) {'OK'} else {$e}"`

Expected: `OK`

- [ ] **Step 5: Confirm no leftover references to the old hardcoded defaults**

Run: `powershell -NoProfile -Command "Select-String -Path 'TransferDriveTool/TransferDriveTool-V3.ps1' -Pattern 'Kevin Rockel|Aegis Fortress L3'"`

Expected: no output (no matches) — confirms Task 1's removal of the hardcoded defaults wasn't reintroduced or left partially in place.

- [ ] **Step 6: Commit**

```bash
git add TransferDriveTool/TransferDriveTool-V3.ps1
git commit -m "feat: implement DTA logging profile load/save/delete

Adds Get-DtaProfiles/Save-DtaProfiles (JSON at \$PSScriptRoot\Profiles.json,
travels with the script when copied onto a transfer drive) and wires
up the profile controls added in the previous commit: selecting a
profile loads its 7 field values, Save creates or overwrites a
profile under the current name, Delete removes it after confirmation.
A failed write (e.g. read-only media) is caught and reported via
Write-Status rather than crashing or corrupting the in-memory list."
```

---

### Task 3: Manual verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Confirm the fields start blank on a fresh launch**

Launch the tool where no `Profiles.json` exists next to the script yet. Confirm all 7 DTA Logging Info fields are empty and the profile dropdown is empty, with no error shown.

- [ ] **Step 2: Save, reload, and edit a profile**

Type values into the 7 fields, type a new name into the profile box, click Save. Confirm the name appears selected in the dropdown and a `Profiles.json` file now exists next to the script. Change one field's value, click Save again (same name), and confirm it overwrote rather than duplicating (still only one entry with that name in the dropdown).

- [ ] **Step 3: Create a second profile and switch between them**

Type a different profile name, adjust the fields, Save. Switch the dropdown between both profiles and confirm the 7 fields update correctly each time.

- [ ] **Step 4: Delete a profile**

Select a profile, click Delete, confirm the Yes/No prompt, confirm it disappears from the dropdown and the fields clear, and confirm `Profiles.json` no longer contains it (the other profile should still be there).

- [ ] **Step 5: Confirm profiles travel with the script**

Copy the script (and the `Profiles.json` that now sits next to it) onto a test USB drive or a different folder, launch it from there, and confirm the same profiles show up in the dropdown — this is the core reason profiles live next to the script rather than in a fixed machine path.

- [ ] **Step 6: If you have access to a read-only-mounted drive, confirm the failure path**

Run the tool from read-only media (or mark the folder read-only locally as a stand-in), try to Save or Delete a profile, and confirm the app shows a clear "read-only" style message in the status log instead of crashing, and that loading/selecting existing profiles still works fine.

- [ ] **Step 7: Report back**

Let the person who requested this feature know the outcome of Steps 1-6 before considering this plan complete.
