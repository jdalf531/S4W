# Resumable, Non-Blocking File Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `TransferDriveTool-V3.ps1` from freezing during a Run, and make large network-share copies resumable across network drops and app restarts.

**Architecture:** Move the file-copy loop off the WPF UI thread into a background PowerShell runspace. The runspace reports progress by calling the UI thread's `Dispatcher.Invoke(...)` directly (verified pattern, see Global Constraints). File copying goes through a new `Copy-FileResumable` function that writes to a `.partial` file in 4&nbsp;MB chunks, hashes the source incrementally as it reads, and only renames `.partial` onto the real destination once a post-copy hash check passes — this both removes the UI freeze and makes large copies resumable.

**Tech Stack:** Windows PowerShell 5.1, WPF (PresentationFramework/PresentationCore/WindowsBase), no external modules.

**Spec:** `docs/superpowers/specs/2026-07-02-resumable-async-transfer-design.md`

## Global Constraints

- Single-file script (`TransferDriveTool/TransferDriveTool-V3.ps1`) — this plan does **not** split it into multiple files. The tool is deployed by copying that one file to removable/read-only drives; don't introduce a second file it depends on.
- Chunk size for `Copy-FileResumable`: `4MB` (PowerShell numeric literal, = 4,194,304 bytes).
- Retry policy for `Copy-FileResumable`: delays `@(2,5,15,30,60)` seconds (last value repeats), capped at `15` total attempts.
- Progress callbacks inside `Copy-FileResumable` are throttled to at most one every 250ms.
- **Verified mechanics this plan depends on** (confirmed empirically before writing this plan, see the design spec's background — these are not assumptions):
  - A scriptblock created *inside* a background runspace's own script, referencing only that runspace's own session variables, correctly executes via `$Dispatcher.Invoke([action]{...}, "Normal")` even though `Invoke` runs it on the separate UI thread.
  - User-defined functions can be injected into a background runspace via `[System.Management.Automation.Runspaces.InitialSessionState]` + `SessionStateFunctionEntry`, built from that function's own `(Get-Item Function:\Name).ScriptBlock.ToString()` — so the runspace always uses the exact same function body as the main script (no duplicated/drifting copies).
  - **Any scriptblock passed to a .NET event (`Add_Tick`, `Add_Click`, etc.) that reads a variable local to the enclosing PowerShell *function* (not top-level script scope) MUST be built with `.GetNewClosure()`, or those variables resolve empty/null when the event later fires.** `GetNewClosure()` captures live *references* correctly (so `$asyncResult.IsCompleted`, a property on a captured object, reflects real-time state), but does **not** persist mutations of value-type locals (e.g. a hand-rolled counter) across separate firings of the same event — never rely on that.
  - Only the object/dispatcher references needed are injected into the background runspace (`$Dispatcher` = `$Window.Dispatcher`, not the whole `$Window`) — this also makes the new logic testable without ever loading the real XAML window.

---

## File Structure

All changes are in `TransferDriveTool/TransferDriveTool-V3.ps1`:

- **XAML block** (near line 385-404): add a second `ProgressBar` (`pbCurrentFile`) + `TextBlock` (`lblCurrentFileProgress`) for current-file byte progress.
- **UI control bindings** (near line 643-645): bind the two new controls.
- **New function `Copy-FileResumable`**: added where `Get-FileHashSHA256` currently lives (~line 868) — replaces it entirely.
- **Deleted**: `Get-FileHashSHA256`, `Update-ProgressUI`, `Set-CurrentFileLabel`, `Copy-WithRetry`, and the `$script:TotalFiles`/`$script:FilesCopied`/`$script:FilesSkipped`/`$script:StartTime` variables — all superseded by the rewritten `Copy-Files`.
- **Rewritten `Copy-Files`** (~line 964 currently): keeps the existing synchronous validation/file-scan prologue, then snapshots UI state, builds a background runspace, and starts it. A new local completion-timer re-enables buttons and disposes the runspace when done.

No new files. No changes to `Add-CsvLogEntry` (already pure file I/O, safe to inject into the runspace as-is), the archive sweeps, domain detection, or console-hiding logic from earlier work.

---

### Task 1: Add current-file progress UI elements

**Files:**
- Modify: `TransferDriveTool/TransferDriveTool-V3.ps1` (XAML block, ~line 385-404; control bindings, ~line 643-645)
- Test: ad hoc PowerShell in the scratchpad (no permanent test file — XAML/control existence is exercised for real by Task 3's test)

**Interfaces:**
- Produces: WPF controls named `pbCurrentFile` (ProgressBar, 0-100) and `lblCurrentFileProgress` (TextBlock), and PowerShell variables `$pbCurrentFile` / `$lblCurrentFileProgress` bound via `$Window.FindName(...)`, for Task 3 to use.

- [ ] **Step 1: Add the new XAML controls**

In `TransferDriveTool/TransferDriveTool-V3.ps1`, find this block (~line 394-404):

```xml
                    <!-- Progress Summary -->
                    <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                        <TextBlock x:Name="lblProgressSummary"
                                   Text="Files: 0 / 0 | Copied: 0 | Skipped: 0"
                                   Foreground="#E0E0E0"
                                   Margin="0,0,20,0"/>

                        <TextBlock x:Name="lblCurrentFile"
                                   Text="Current: (none)"
                                   Foreground="#E0E0E0"/>
                    </StackPanel>
                </StackPanel>
```

Replace it with (adds a second progress bar + label directly below the summary row):

```xml
                    <!-- Progress Summary -->
                    <StackPanel Orientation="Horizontal" Margin="0,5,0,0">
                        <TextBlock x:Name="lblProgressSummary"
                                   Text="Files: 0 / 0 | Copied: 0 | Skipped: 0"
                                   Foreground="#E0E0E0"
                                   Margin="0,0,20,0"/>

                        <TextBlock x:Name="lblCurrentFile"
                                   Text="Current: (none)"
                                   Foreground="#E0E0E0"/>
                    </StackPanel>

                    <!-- Current File Byte Progress -->
                    <ProgressBar x:Name="pbCurrentFile"
                                 Height="14"
                                 Minimum="0"
                                 Maximum="100"
                                 Value="0"
                                 Margin="0,5,0,0"
                                 Background="#2D2D30"
                                 Foreground="#3FA9F5"/>

                    <TextBlock x:Name="lblCurrentFileProgress"
                               Text=""
                               Foreground="#E0E0E0"
                               Margin="0,3,0,0"/>
                </StackPanel>
```

- [ ] **Step 2: Bind the new controls**

Find this block (~line 643-645):

```powershell
$pbProgress         = $Window.FindName("pbProgress")
$lblProgressSummary = $Window.FindName("lblProgressSummary")
$lblCurrentFile     = $Window.FindName("lblCurrentFile")
```

Replace it with:

```powershell
$pbProgress             = $Window.FindName("pbProgress")
$lblProgressSummary     = $Window.FindName("lblProgressSummary")
$lblCurrentFile         = $Window.FindName("lblCurrentFile")
$pbCurrentFile          = $Window.FindName("pbCurrentFile")
$lblCurrentFileProgress = $Window.FindName("lblCurrentFileProgress")
```

- [ ] **Step 3: Verify the XAML still parses and the new names resolve**

Run (adjust the script path if your checkout differs):

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

foreach ($name in "pbCurrentFile","lblCurrentFileProgress") {
    $ctrl = $testWindow.FindName($name)
    if (-not $ctrl) { throw "FindName('$name') returned null" }
}
"OK: both controls resolve"
```

Expected: `OK: both controls resolve`, no errors.

- [ ] **Step 4: Full-script parse check**

Run: `powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('TransferDriveTool/TransferDriveTool-V3.ps1', [ref]$null, [ref]$e); if ($e.Count -eq 0) {'OK'} else {$e}"`

Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool/TransferDriveTool-V3.ps1
git commit -m "feat: add current-file byte progress bar to transfer UI"
```

---

### Task 2: Implement `Copy-FileResumable`

**Files:**
- Modify: `TransferDriveTool/TransferDriveTool-V3.ps1` — replace the `Get-FileHashSHA256` function (~line 868-871) with the new `Copy-FileResumable` function.
- Test: ad hoc PowerShell in the scratchpad, using the AST-extraction harness below (no permanent test file — this codebase has no test framework).

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `Copy-FileResumable -Source <string> -Destination <string> [-ChunkSizeBytes <int> = 4MB] [-ProgressCallback <scriptblock> = $null] [-RetryDelaySeconds <int[]> = @(2,5,15,30,60)] [-MaxAttempts <int> = 15]`, returning `[PSCustomObject]@{ Success = [bool]; SourceHash = [string or $null]; DestHash = [string or $null]; Error = [string or $null] }`. `ProgressCallback`, if provided, is invoked as `& $ProgressCallback $bytesDone $bytesTotal` (both `[long]`). Task 3 depends on this exact signature and return shape.

- [ ] **Step 1: Replace `Get-FileHashSHA256` with `Copy-FileResumable`**

In `TransferDriveTool/TransferDriveTool-V3.ps1`, find:

```powershell
# ============================
# HASHING
# ============================
function Get-FileHashSHA256 {
    param([string]$filePath)
    (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
}
```

Replace it with:

```powershell
# ============================
# RESUMABLE COPY ENGINE
# ============================
# Copies Source -> Destination in chunks via a "<Destination>.partial" file,
# hashing the source incrementally as it reads (no separate full hash pass on
# the happy path). Only renames .partial onto Destination once a post-copy
# hash check passes, so Destination is never touched mid-copy. A sidecar
# "<Destination>.partial.meta" records the source's Length/LastWriteTimeUtc
# so an interrupted copy can resume later -- even after a full app restart --
# as long as the source hasn't changed; otherwise it restarts from byte 0.
function Copy-FileResumable {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [int]$ChunkSizeBytes = 4MB,
        [scriptblock]$ProgressCallback = $null,
        [int[]]$RetryDelaySeconds = @(2,5,15,30,60),
        [int]$MaxAttempts = 15
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return [PSCustomObject]@{ Success = $false; SourceHash = $null; DestHash = $null; Error = "Source file not found: $Source" }
    }

    $sourceInfo = Get-Item -LiteralPath $Source
    $sourceLength = $sourceInfo.Length
    $sourceWriteTicks = $sourceInfo.LastWriteTimeUtc.Ticks

    $partialPath = "$Destination.partial"
    $metaPath = "$Destination.partial.meta"

    function Get-ResumeOffset {
        if (-not (Test-Path -LiteralPath $partialPath)) { return 0L }
        if (-not (Test-Path -LiteralPath $metaPath)) {
            Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
            return 0L
        }
        $metaLines = @(Get-Content -LiteralPath $metaPath -ErrorAction SilentlyContinue)
        if ($metaLines.Count -lt 2 -or $metaLines[0] -ne "$sourceLength" -or $metaLines[1] -ne "$sourceWriteTicks") {
            Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
            return 0L
        }
        return (Get-Item -LiteralPath $partialPath).Length
    }

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $resumeOffset = Get-ResumeOffset

        if ($resumeOffset -eq 0L -and -not (Test-Path -LiteralPath $metaPath)) {
            Set-Content -LiteralPath $metaPath -Value @("$sourceLength", "$sourceWriteTicks")
        }

        $sourceStream = $null
        $partialStream = $null
        $hasher = [System.Security.Cryptography.SHA256]::Create()

        try {
            $sourceStream = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $partialStream = [System.IO.File]::Open($partialPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

            $buffer = New-Object byte[] $ChunkSizeBytes

            # Resuming: re-hash the already-copied prefix by re-reading it from
            # the source (ground truth), so the final hash is still correct
            # for the whole file even though we didn't keep hash state across
            # attempts/restarts.
            $hashed = 0L
            while ($hashed -lt $resumeOffset) {
                $toRead = [Math]::Min($ChunkSizeBytes, $resumeOffset - $hashed)
                $read = $sourceStream.Read($buffer, 0, $toRead)
                if ($read -le 0) { break }
                $hasher.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
                $hashed += $read
            }

            $partialStream.Seek($resumeOffset, [System.IO.SeekOrigin]::Begin) | Out-Null
            $partialStream.SetLength($resumeOffset)

            $bytesDone = $resumeOffset
            $lastReport = Get-Date

            while ($true) {
                $read = $sourceStream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }

                $hasher.TransformBlock($buffer, 0, $read, $buffer, 0) | Out-Null
                $partialStream.Write($buffer, 0, $read)
                $bytesDone += $read

                if ($ProgressCallback -and ((Get-Date) - $lastReport).TotalMilliseconds -ge 250) {
                    & $ProgressCallback $bytesDone $sourceLength
                    $lastReport = Get-Date
                }
            }

            $hasher.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
            $sourceHash = ([BitConverter]::ToString($hasher.Hash) -replace '-', '')

            if ($ProgressCallback) { & $ProgressCallback $bytesDone $sourceLength }

            $partialStream.Close(); $partialStream = $null
            $sourceStream.Close(); $sourceStream = $null

            $destHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash

            if ($sourceHash -ne $destHash) {
                Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
                $lastError = "Hash mismatch after copy (source $sourceHash, dest $destHash)"
            }
            else {
                Move-Item -LiteralPath $partialPath -Destination $Destination -Force
                Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
                return [PSCustomObject]@{ Success = $true; SourceHash = $sourceHash; DestHash = $destHash; Error = $null }
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }
        finally {
            if ($partialStream) { $partialStream.Dispose() }
            if ($sourceStream) { $sourceStream.Dispose() }
            $hasher.Dispose()
        }

        if ($attempt -lt $MaxAttempts) {
            $delayIndex = [Math]::Min($attempt - 1, $RetryDelaySeconds.Count - 1)
            Start-Sleep -Seconds $RetryDelaySeconds[$delayIndex]
        }
    }

    return [PSCustomObject]@{ Success = $false; SourceHash = $null; DestHash = $null; Error = $lastError }
}
```

- [ ] **Step 2: Write the test harness helper**

Create a scratch test script at `$env:TEMP\Test-CopyFileResumable.ps1` (this is a throwaway test script, not committed to the repo — the codebase has no test framework, so verification lives here and is run manually):

```powershell
param([string]$ScriptPath = "TransferDriveTool/TransferDriveTool-V3.ps1")

function Import-SingleFunction {
    param([string]$Path, [string]$FunctionName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $funcAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $FunctionName }, $true) | Select-Object -First 1
    if (-not $funcAst) { throw "Function '$FunctionName' not found in $Path" }
    . ([scriptblock]::Create($funcAst.Extent.Text))
}

Import-SingleFunction -Path $ScriptPath -FunctionName "Copy-FileResumable"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Output "PASS: $Message"
}

$scratch = Join-Path $env:TEMP ("cfr_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

try {
    # ---- Test A: normal copy, no prior partial ----
    $srcA = Join-Path $scratch "A_source.bin"
    $dstA = Join-Path $scratch "A_dest.bin"
    $bytesA = New-Object byte[] (3MB + 12345)
    (New-Object Random).NextBytes($bytesA)
    [System.IO.File]::WriteAllBytes($srcA, $bytesA)

    $resultA = Copy-FileResumable -Source $srcA -Destination $dstA -ChunkSizeBytes 512KB
    Assert-True $resultA.Success "Test A: copy succeeds"
    Assert-True ((Get-FileHash -LiteralPath $srcA -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $dstA -Algorithm SHA256).Hash) "Test A: dest byte-identical to source"
    Assert-True (-not (Test-Path "$dstA.partial")) "Test A: no leftover .partial"
    Assert-True (-not (Test-Path "$dstA.partial.meta")) "Test A: no leftover .meta"

    # ---- Test B: resume from a pre-seeded, correctly-matching partial ----
    $srcB = Join-Path $scratch "B_source.bin"
    $dstB = Join-Path $scratch "B_dest.bin"
    $bytesB = New-Object byte[] (2MB)
    (New-Object Random).NextBytes($bytesB)
    [System.IO.File]::WriteAllBytes($srcB, $bytesB)

    $prefixLength = 1.2MB
    [System.IO.File]::WriteAllBytes("$dstB.partial", $bytesB[0..($prefixLength - 1)])
    $srcInfoB = Get-Item $srcB
    Set-Content -Path "$dstB.partial.meta" -Value @("$($srcInfoB.Length)", "$($srcInfoB.LastWriteTimeUtc.Ticks)")

    $script:firstReportedBytesDone = $null
    $cbB = { param($done, $total) if ($null -eq $script:firstReportedBytesDone) { $script:firstReportedBytesDone = $done } }

    $resultB = Copy-FileResumable -Source $srcB -Destination $dstB -ChunkSizeBytes 256KB -ProgressCallback $cbB
    Assert-True $resultB.Success "Test B: resumed copy succeeds"
    Assert-True ($script:firstReportedBytesDone -ge $prefixLength) "Test B: first progress report already includes the pre-seeded prefix (proves it resumed, not restarted) - was $script:firstReportedBytesDone"
    Assert-True ((Get-FileHash -LiteralPath $srcB -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $dstB -Algorithm SHA256).Hash) "Test B: dest byte-identical to source after resume"

    # ---- Test C: stale/mismatched partial+meta triggers a clean restart ----
    $srcC = Join-Path $scratch "C_source.bin"
    $dstC = Join-Path $scratch "C_dest.bin"
    $bytesC = New-Object byte[] (1MB)
    (New-Object Random).NextBytes($bytesC)
    [System.IO.File]::WriteAllBytes($srcC, $bytesC)

    [System.IO.File]::WriteAllBytes("$dstC.partial", [byte[]](1..500))  # garbage, unrelated to source
    Set-Content -Path "$dstC.partial.meta" -Value @("999999999", "12345")  # deliberately wrong length/ticks

    $resultC = Copy-FileResumable -Source $srcC -Destination $dstC -ChunkSizeBytes 256KB
    Assert-True $resultC.Success "Test C: copy succeeds despite stale partial"
    Assert-True ((Get-FileHash -LiteralPath $srcC -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $dstC -Algorithm SHA256).Hash) "Test C: dest byte-identical to source (stale partial was discarded, not appended to)"

    # ---- Test D: retry loop respects MaxAttempts and fails gracefully ----
    $srcD = Join-Path $scratch "D_source.bin"
    [System.IO.File]::WriteAllBytes($srcD, (New-Object byte[] 1024))
    $dstD = "Z:\this_drive_does_not_exist\D_dest.bin"  # guaranteed-invalid destination

    $swD = [System.Diagnostics.Stopwatch]::StartNew()
    $resultD = Copy-FileResumable -Source $srcD -Destination $dstD -RetryDelaySeconds @(0,0) -MaxAttempts 3
    $swD.Stop()
    Assert-True (-not $resultD.Success) "Test D: copy to an invalid destination fails (not throws)"
    Assert-True (-not [string]::IsNullOrEmpty($resultD.Error)) "Test D: failure includes an Error message"
    Assert-True ($swD.Elapsed.TotalSeconds -lt 10) "Test D: fails within a few seconds using tiny retry delays (was $($swD.Elapsed.TotalSeconds)s)"

    Write-Output "ALL TESTS PASSED"
}
finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 3: Run the test harness and verify it fails meaningfully if the function is missing**

Run: `powershell -NoProfile -File "$env:TEMP\Test-CopyFileResumable.ps1" -ScriptPath "path/to/TransferDriveTool-V3.ps1/before/Step1"`

(i.e. run this against a copy of the file from *before* Step 1's edit, or temporarily rename the function, to confirm the harness actually exercises real behavior)

Expected: throws `Function 'Copy-FileResumable' not found in ...` — confirms the harness isn't vacuously passing.

- [ ] **Step 4: Run the test harness against the real (updated) script**

Run: `powershell -NoProfile -File "$env:TEMP\Test-CopyFileResumable.ps1" -ScriptPath "TransferDriveTool/TransferDriveTool-V3.ps1"`

Expected: four `PASS:` lines (one has an inline sub-assertion count, so you'll see all `Assert-True` messages print PASS) ending in `ALL TESTS PASSED`, no `ASSERTION FAILED` or unhandled exceptions.

- [ ] **Step 5: Full-script parse check**

Run: `powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('TransferDriveTool/TransferDriveTool-V3.ps1', [ref]$null, [ref]$e); if ($e.Count -eq 0) {'OK'} else {$e}"`

Expected: `OK`

- [ ] **Step 6: Commit**

```bash
git add TransferDriveTool/TransferDriveTool-V3.ps1
git commit -m "feat: add Copy-FileResumable chunked, resumable copy engine

Replaces Get-FileHashSHA256. Writes to a .partial file with a sidecar
.meta recording source length/LastWriteTimeUtc, so an interrupted copy
resumes on retry -- even across a full app restart -- instead of
restarting from byte zero. Hashes the source incrementally while
copying instead of in a separate pass."
```

---

### Task 3: Move `Copy-Files` onto a background runspace

**Files:**
- Modify: `TransferDriveTool/TransferDriveTool-V3.ps1` — delete `Update-ProgressUI`, `Set-CurrentFileLabel`, the `$script:TotalFiles`/`$script:FilesCopied`/`$script:FilesSkipped`/`$script:StartTime` block, and `Copy-WithRetry` (currently ~line 873-960); replace the body of `Copy-Files` (~line 964-1145).
- Test: scratchpad PowerShell script using real (unshown) WPF controls + a real pumped `Dispatcher`, following the same pattern already verified for this plan.

**Interfaces:**
- Consumes: `Copy-FileResumable` from Task 2 (exact signature above), `Add-CsvLogEntry` (existing, unchanged — `-DTAName -Manager -SourceSystem -DestSystem -FileName -Classification -FileSize -Checksum -MediaUsed -Justification -ScanVerify`, all `[string]`), `$pbCurrentFile`/`$lblCurrentFileProgress` from Task 1.
- Produces: `Copy-Files` (no params, reads UI controls, unchanged call site: `$btnRun.Add_Click({ Write-Status "Starting transfer..."; Copy-Files })`).

- [ ] **Step 1: Delete the now-superseded functions and state**

Find and delete this whole block (~line 873-903, immediately after the function this task's Task 2 replaced):

```powershell
# ============================
# TRANSFER STATE / PROGRESS
# ============================
$script:TotalFiles   = 0
$script:FilesCopied  = 0
$script:FilesSkipped = 0
$script:StartTime    = $null

function Update-ProgressUI {
    if ($script:TotalFiles -gt 0) {
        $percent = [math]::Round(
            ($script:FilesCopied + $script:FilesSkipped) / $script:TotalFiles * 100, 0
        )
    } else {
        $percent = 0
    }

    $pbProgress.Value = $percent

    $lblProgressSummary.Text =
        "Files: $($script:FilesCopied + $script:FilesSkipped) / $($script:TotalFiles) | Copied: $($script:FilesCopied) | Skipped: $($script:FilesSkipped)"
}

function Set-CurrentFileLabel {
    param([string]$relativePath)
    if ([string]::IsNullOrWhiteSpace($relativePath)) {
        $lblCurrentFile.Text = "Current: (none)"
    } else {
        $lblCurrentFile.Text = "Current: $relativePath"
    }
}
```

And delete this whole block immediately after it (the old `Copy-WithRetry`, ~line 905-960):

```powershell
# ============================
# RETRY LOGIC FOR COPY
# ============================
function Copy-WithRetry {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$MaxRetries = 3
    )

    # Verify source exists before attempting copy
    if (-not (Test-Path $Source)) {
        Write-Status "✗ Source file not found: $Source"
        return $false
    }

    # Backup destination if it exists
    $destExists = Test-Path $Destination
    $backupPath = $null
    if ($destExists) {
        $backupPath = "$Destination.backup"
        if (Test-Path $backupPath) {
            Remove-Item $backupPath -Force | Out-Null
        }
        Copy-Item -Path $Destination -Destination $backupPath -Force | Out-Null
    }

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            Copy-Item -Path $Source -Destination $Destination -Force
            
            # Clean up backup if copy succeeded
            if ($backupPath -and (Test-Path $backupPath)) {
                Remove-Item $backupPath -Force | Out-Null
            }
            
            return $true
        }
        catch {
            $attempt++
            Write-Status "Error copying '$Source' (attempt $attempt of $MaxRetries): $($_.Exception.Message)"
            
            # Restore backup on final failure
            if ($attempt -eq $MaxRetries -and $backupPath -and (Test-Path $backupPath)) {
                Copy-Item -Path $backupPath -Destination $Destination -Force | Out-Null
                Write-Status "Restored backup for: $Destination"
                Remove-Item $backupPath -Force | Out-Null
            }
            
            Start-Sleep -Seconds 1
        }
    }

    return $false
}
```

- [ ] **Step 2: Replace `Copy-Files`**

Find the `Copy-Files` function (starts `# ============================\n# INCREMENTAL COPY ENGINE (UPGRADED)\n# ============================\nfunction Copy-Files {` and ends at the closing `}` right before `# ============================\n# BUTTON HANDLERS`). Replace the entire function with:

```powershell
# ============================
# INCREMENTAL COPY ENGINE (ASYNC)
# ============================
function Copy-Files {

    $activeTab = $tabMain.SelectedIndex

    if ($activeTab -eq 0) {
        $CsvLogPath = "E:\DTA\Logging\DataTransferLog.csv"
    }
    else {
        $CsvLogPath = "C:\VIPER\DTA\DataTransferLog.csv"
    }

    if (-not (Test-Path $CsvLogPath)) {
        $headers = "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"
        Set-Content -Path $CsvLogPath -Value $headers
    }

    if ($activeTab -eq 0) {
        $src = $txtSource_Commercial.Text.Trim()
        $dstRoot = $txtDest_Commercial.Text.Trim()
        $user = $cbUser_Commercial.SelectedItem
    }
    elseif ($activeTab -eq 1) {
        $src = $txtSource_MPN.Text.Trim()
        $dstRoot = $txtDest_MPN.Text.Trim()
        $user = $cbUser_MPN.SelectedItem
    }
    else {
        Write-Status "Unknown tab selected."
        return
    }

    if (-not $user) {
        Write-Status "No user selected."
        return
    }

    if (-not (Test-Path $src)) {
        Write-Status "Source path does not exist: $src"
        return
    }

    if ([string]::IsNullOrWhiteSpace($dstRoot)) {
        Write-Status "Destination path is empty."
        return
    }

    $dateFolder = (Get-Date -Format "yyyyMMdd")
    $dst = Join-Path $dstRoot $dateFolder

    if (-not (Test-Path $dst)) {
        Write-Status "Creating destination folder: $dst"
        try {
            New-Item -ItemType Directory -Path $dst -Force | Out-Null
        }
        catch {
            Write-Status "Failed to create destination: $($_.Exception.Message)"
            return
        }
    }

    Write-Status "Scanning source files for changes..."

    $archivePrefix = (Join-Path $src "Archive") + [System.IO.Path]::DirectorySeparatorChar
    $files = Get-ChildItem -Path $src -Recurse -File |
        Where-Object { -not $_.FullName.StartsWith($archivePrefix, [System.StringComparison]::OrdinalIgnoreCase) }

    if ($files.Count -eq 0) {
        Write-Status "No files found to transfer."
        return
    }

    # Snapshot everything the background runspace needs from UI controls now --
    # it's not safe to read WPF control properties from another thread.
    $snapshot = [PSCustomObject]@{
        DtaName        = $user
        Manager        = $txtManager.Text
        SourceSystem   = $txtSourceSystem.Text
        DestSystem     = $txtDestSystem.Text
        Classification = $txtClassification.Text
        MediaUsed      = $txtMediaUsed.Text
        Justification  = $txtJustification.Text
        ScanVerify     = $txtScanVerify.Text
    }

    $pbProgress.Value = 0
    $pbCurrentFile.Value = 0
    $lblProgressSummary.Text = "Files: 0 / $($files.Count) | Copied: 0 | Skipped: 0"
    $lblCurrentFile.Text = "Current: (none)"
    $lblCurrentFileProgress.Text = ""
    $btnRun.IsEnabled = $false
    $btnClose.IsEnabled = $false

    $copyFileResumableBody = (Get-Item Function:\Copy-FileResumable).ScriptBlock.ToString()
    $addCsvLogEntryBody    = (Get-Item Function:\Add-CsvLogEntry).ScriptBlock.ToString()

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Copy-FileResumable", $copyFileResumableBody)))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Add-CsvLogEntry", $addCsvLogEntryBody)))

    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    $runspace.Open()

    $runspace.SessionStateProxy.SetVariable("Dispatcher", $Window.Dispatcher)
    $runspace.SessionStateProxy.SetVariable("pbProgress", $pbProgress)
    $runspace.SessionStateProxy.SetVariable("lblProgressSummary", $lblProgressSummary)
    $runspace.SessionStateProxy.SetVariable("lblCurrentFile", $lblCurrentFile)
    $runspace.SessionStateProxy.SetVariable("pbCurrentFile", $pbCurrentFile)
    $runspace.SessionStateProxy.SetVariable("lblCurrentFileProgress", $lblCurrentFileProgress)
    $runspace.SessionStateProxy.SetVariable("txtStatus", $txtStatus)
    $runspace.SessionStateProxy.SetVariable("LogFile", $LogFile)
    $runspace.SessionStateProxy.SetVariable("CsvLogPath", $CsvLogPath)
    $runspace.SessionStateProxy.SetVariable("Files", $files)
    $runspace.SessionStateProxy.SetVariable("SrcRoot", $src)
    $runspace.SessionStateProxy.SetVariable("DstRoot", $dst)
    $runspace.SessionStateProxy.SetVariable("Snapshot", $snapshot)

    $batchScript = {
        $totalFiles   = $Files.Count
        $filesCopied  = 0
        $filesSkipped = 0
        $startTime    = Get-Date

        function Write-BackgroundStatus {
            param([string]$msg)
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $line = "[$timestamp] $msg"
            Add-Content -Path $LogFile -Value $line
            $Dispatcher.Invoke([action]{
                $txtStatus.AppendText("$line`r`n")
                $txtStatus.ScrollToEnd()
            }, "Normal")
        }

        function Update-BackgroundProgress {
            $percent = [math]::Round((($filesCopied + $filesSkipped) / $totalFiles) * 100, 0)
            $Dispatcher.Invoke([action]{
                $pbProgress.Value = $percent
                $lblProgressSummary.Text = "Files: $($filesCopied + $filesSkipped) / $totalFiles | Copied: $filesCopied | Skipped: $filesSkipped"
            }, "Normal")
        }

        foreach ($file in $Files) {
            $relativePath = $file.FullName.Substring($SrcRoot.Length).TrimStart("\", "/")

            $Dispatcher.Invoke([action]{
                $lblCurrentFile.Text = "Current: $relativePath"
                $pbCurrentFile.Value = 0
                $lblCurrentFileProgress.Text = ""
            }, "Normal")

            $destFile = Join-Path $DstRoot $relativePath
            $destDir = Split-Path $destFile -Parent

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            if (Test-Path $destFile) {
                $destInfo = Get-Item $destFile
                if ($destInfo.LastWriteTimeUtc -ge $file.LastWriteTimeUtc) {
                    Write-BackgroundStatus "(skip) File exists (destination newer/same): $relativePath"
                    $filesSkipped++
                    Update-BackgroundProgress
                    continue
                }
                Write-BackgroundStatus "(overwrite) File exists, source is newer: $relativePath"
            }

            $progressCallback = {
                param($bytesDone, $bytesTotal)
                $percent = if ($bytesTotal -gt 0) { [math]::Round(($bytesDone / $bytesTotal) * 100, 0) } else { 0 }
                $doneMb = [math]::Round($bytesDone / 1MB, 1)
                $totalMb = [math]::Round($bytesTotal / 1MB, 1)
                $Dispatcher.Invoke([action]{
                    $pbCurrentFile.Value = $percent
                    $lblCurrentFileProgress.Text = "$doneMb MB / $totalMb MB"
                }, "Normal")
            }.GetNewClosure()

            $result = Copy-FileResumable -Source $file.FullName -Destination $destFile -ProgressCallback $progressCallback

            if (-not $result.Success) {
                Write-BackgroundStatus "Failed to copy $relativePath after retries: $($result.Error)"
                $filesSkipped++
                Update-BackgroundProgress
                continue
            }

            Write-BackgroundStatus "Copied and hash-verified: $relativePath"

            try {
                $size = "{0:N0} KB" -f ($file.Length / 1KB)
                Add-CsvLogEntry `
                    -DTAName        $Snapshot.DtaName `
                    -Manager        $Snapshot.Manager `
                    -SourceSystem   $Snapshot.SourceSystem `
                    -DestSystem     $Snapshot.DestSystem `
                    -FileName       $relativePath `
                    -Classification $Snapshot.Classification `
                    -FileSize       $size `
                    -Checksum       $result.DestHash `
                    -MediaUsed      $Snapshot.MediaUsed `
                    -Justification  $Snapshot.Justification `
                    -ScanVerify     $Snapshot.ScanVerify

                Write-BackgroundStatus "Logged: $relativePath"
                $filesCopied++
            }
            catch {
                Write-BackgroundStatus "Failed to write CSV log for $relativePath : $($_.Exception.Message)"
                $filesSkipped++
            }

            Update-BackgroundProgress
        }

        $elapsed = (Get-Date) - $startTime
        Write-BackgroundStatus "Transfer complete."
        Write-BackgroundStatus "Summary: Total=$totalFiles, Copied=$filesCopied, Skipped=$filesSkipped, Elapsed=$($elapsed.ToString())"

        $Dispatcher.Invoke([action]{
            $lblCurrentFile.Text = "Current: (none)"
            $pbCurrentFile.Value = 0
            $lblCurrentFileProgress.Text = ""
        }, "Normal")
    }

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $powershell.AddScript($batchScript) | Out-Null
    $asyncResult = $powershell.BeginInvoke()

    $completionTimer = New-Object System.Windows.Threading.DispatcherTimer
    $completionTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $completionTimer.Add_Tick({
        if (-not $asyncResult.IsCompleted) { return }

        $completionTimer.Stop()

        try {
            $powershell.EndInvoke($asyncResult) | Out-Null
        }
        catch {
            Write-Status "Transfer runspace error: $($_.Exception.Message)"
        }

        foreach ($errorRecord in $powershell.Streams.Error) {
            Write-Status "Transfer error: $errorRecord"
        }

        $powershell.Dispose()
        $runspace.Close()
        $runspace.Dispose()

        $btnRun.IsEnabled = $true
        $btnClose.IsEnabled = $true
    }.GetNewClosure())
    $completionTimer.Start()
}
```

- [ ] **Step 3: Write an integration test that exercises the real runspace/progress mechanism without the real XAML window**

Create `$env:TEMP\Test-CopyFilesAsync.ps1`:

```powershell
param([string]$ScriptPath = "TransferDriveTool/TransferDriveTool-V3.ps1")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

function Import-SingleFunction {
    param([string]$Path, [string]$FunctionName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $funcAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $FunctionName }, $true) | Select-Object -First 1
    if (-not $funcAst) { throw "Function '$FunctionName' not found in $Path" }
    . ([scriptblock]::Create($funcAst.Extent.Text))
}

Import-SingleFunction -Path $ScriptPath -FunctionName "Copy-FileResumable"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    Write-Output "PASS: $Message"
}

# Real (unshown) WPF controls -- exercises the exact same object types and
# property/method calls (.Value, .Text, .AppendText, .ScrollToEnd,
# .IsEnabled) that the real XAML-bound controls have, without loading a
# Window or the rest of the script (which would pop the GUI).
$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$pbProgress = New-Object System.Windows.Controls.ProgressBar
$lblProgressSummary = New-Object System.Windows.Controls.TextBlock
$lblCurrentFile = New-Object System.Windows.Controls.TextBlock
$pbCurrentFile = New-Object System.Windows.Controls.ProgressBar
$lblCurrentFileProgress = New-Object System.Windows.Controls.TextBlock
$txtStatus = New-Object System.Windows.Controls.TextBox
$btnRun = New-Object System.Windows.Controls.Button
$btnClose = New-Object System.Windows.Controls.Button
$btnRun.IsEnabled = $false
$btnClose.IsEnabled = $false

$scratch = Join-Path $env:TEMP ("cfa_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$logFile = Join-Path $scratch "log.txt"
$csvLogPath = Join-Path $scratch "audit.csv"
Set-Content -Path $csvLogPath -Value "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"

$srcRoot = Join-Path $scratch "src"
$dstRoot = Join-Path $scratch "dst"
New-Item -ItemType Directory -Path $srcRoot -Force | Out-Null
New-Item -ItemType Directory -Path $dstRoot -Force | Out-Null
1..3 | ForEach-Object {
    $bytes = New-Object byte[] (200KB)
    (New-Object Random).NextBytes($bytes)
    [System.IO.File]::WriteAllBytes((Join-Path $srcRoot "file$_.bin"), $bytes)
}
$files = Get-ChildItem -Path $srcRoot -Recurse -File

$snapshot = [PSCustomObject]@{
    DtaName = "TestUser"; Manager = "Test Manager"; SourceSystem = "SRC"; DestSystem = "DST"
    Classification = "Internal"; MediaUsed = "Test"; Justification = "Automated test"; ScanVerify = "Yes"
}

function Add-CsvLogEntry {
    param([string]$DTAName,[string]$Manager,[string]$SourceSystem,[string]$DestSystem,[string]$FileName,[string]$Classification,[string]$FileSize,[string]$Checksum,[string]$MediaUsed,[string]$Justification,[string]$ScanVerify)
    Add-Content -Path $csvLogPath -Value "`"$FileName`",`"$Checksum`""
}

$copyFileResumableBody = (Get-Item Function:\Copy-FileResumable).ScriptBlock.ToString()
$addCsvLogEntryBody = (Get-Item Function:\Add-CsvLogEntry).ScriptBlock.ToString()

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Copy-FileResumable", $copyFileResumableBody)))
$iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Add-CsvLogEntry", $addCsvLogEntryBody)))

$runspace = [runspacefactory]::CreateRunspace($iss)
$runspace.ApartmentState = "STA"
$runspace.ThreadOptions = "ReuseThread"
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("Dispatcher", $dispatcher)
$runspace.SessionStateProxy.SetVariable("pbProgress", $pbProgress)
$runspace.SessionStateProxy.SetVariable("lblProgressSummary", $lblProgressSummary)
$runspace.SessionStateProxy.SetVariable("lblCurrentFile", $lblCurrentFile)
$runspace.SessionStateProxy.SetVariable("pbCurrentFile", $pbCurrentFile)
$runspace.SessionStateProxy.SetVariable("lblCurrentFileProgress", $lblCurrentFileProgress)
$runspace.SessionStateProxy.SetVariable("txtStatus", $txtStatus)
$runspace.SessionStateProxy.SetVariable("LogFile", $logFile)
$runspace.SessionStateProxy.SetVariable("CsvLogPath", $csvLogPath)
$runspace.SessionStateProxy.SetVariable("Files", $files)
$runspace.SessionStateProxy.SetVariable("SrcRoot", $srcRoot)
$runspace.SessionStateProxy.SetVariable("DstRoot", $dstRoot)
$runspace.SessionStateProxy.SetVariable("Snapshot", $snapshot)

# This is the same $batchScript body as production Copy-Files -- extracted
# here to test it directly, matching this task's Step 2 exactly.
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $ScriptPath), [ref]$null, [ref]$null)
$copyFilesAst = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Copy-Files' }, $true) | Select-Object -First 1
$funcText = $copyFilesAst.Extent.Text
if ($funcText -notmatch '(?s)\$batchScript = \{(.*?)\n    \}\n\n    \$powershell') { throw "Could not extract batchScript body from Copy-Files -- production code structure changed" }
$batchScript = [scriptblock]::Create("{$($Matches[1])}")

$powershell = [powershell]::Create()
$powershell.Runspace = $runspace
$powershell.AddScript($batchScript) | Out-Null
$asyncResult = $powershell.BeginInvoke()

$frame = New-Object System.Windows.Threading.DispatcherFrame
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(50)
$timer.Add_Tick({
    if ($asyncResult.IsCompleted -or $stopwatch.Elapsed.TotalSeconds -gt 30) {
        $timer.Stop()
        $frame.Continue = $false
    }
}.GetNewClosure())
$timer.Start()
[System.Windows.Threading.Dispatcher]::PushFrame($frame)

Assert-True $asyncResult.IsCompleted "Batch completed within 30s (was $($stopwatch.Elapsed.TotalSeconds)s)"
$powershell.EndInvoke($asyncResult) | Out-Null
foreach ($e in $powershell.Streams.Error) { Write-Output "RUNSPACE ERROR: $e" }
Assert-True ($powershell.Streams.Error.Count -eq 0) "No errors in the background runspace"

Assert-True ($pbProgress.Value -eq 100) "Overall progress bar reached 100 (was $($pbProgress.Value))"
Assert-True ($txtStatus.Text -like "*Transfer complete*") "Status log contains 'Transfer complete'"
Assert-True ($txtStatus.Text -like "*Summary: Total=3, Copied=3, Skipped=0*") "Summary line reports 3 copied, 0 skipped"

foreach ($f in $files) {
    $destFile = Join-Path $dstRoot $f.Name
    Assert-True (Test-Path $destFile) "Destination file exists: $($f.Name)"
    Assert-True ((Get-FileHash -LiteralPath $f.FullName).Hash -eq (Get-FileHash -LiteralPath $destFile).Hash) "Destination byte-identical to source: $($f.Name)"
}

$csvLines = Get-Content $csvLogPath
Assert-True ($csvLines.Count -eq 4) "CSV log has header + 3 rows (had $($csvLines.Count))"

$powershell.Dispose(); $runspace.Close(); $runspace.Dispose()
Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "ALL TESTS PASSED"
```

- [ ] **Step 4: Run the integration test**

Run: `powershell -NoProfile -File "$env:TEMP\Test-CopyFilesAsync.ps1" -ScriptPath "TransferDriveTool/TransferDriveTool-V3.ps1"`

Expected: a series of `PASS:` lines ending in `ALL TESTS PASSED`. If the `$batchScript` extraction regex in Step 3 fails to match, that's a signal the production code in Step 2 was written differently than this plan specifies — re-check Step 2's exact structure (the `$batchScript = { ... }` block immediately followed by `$powershell = [powershell]::Create()`).

- [ ] **Step 5: Full-script parse check**

Run: `powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('TransferDriveTool/TransferDriveTool-V3.ps1', [ref]$null, [ref]$e); if ($e.Count -eq 0) {'OK'} else {$e}"`

Expected: `OK`

- [ ] **Step 6: Confirm no leftover references to deleted symbols**

Run: `powershell -NoProfile -Command "Select-String -Path 'TransferDriveTool/TransferDriveTool-V3.ps1' -Pattern 'Update-ProgressUI|Set-CurrentFileLabel|Copy-WithRetry|Get-FileHashSHA256|script:TotalFiles|script:FilesCopied|script:FilesSkipped|script:StartTime'"`

Expected: no output (no matches).

- [ ] **Step 7: Commit**

```bash
git add TransferDriveTool/TransferDriveTool-V3.ps1
git commit -m "feat: run file transfers on a background runspace

Copy-Files now snapshots UI state, hands the transfer loop to a
background PowerShell runspace built from Copy-FileResumable, and
reports progress via throttled Dispatcher.Invoke calls instead of
running the whole copy synchronously on the UI thread. Run/Close are
disabled while a transfer is active and re-enabled by a completion
timer once the runspace finishes. Removes the old Copy-WithRetry
backup-copy-then-restore dance, which is superseded by
Copy-FileResumable's write-to-.partial-then-atomic-rename approach."
```

---

### Task 4: Manual verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Launch the real tool and confirm the UI stays responsive during a transfer**

Run the tool as you normally would (shortcut / `powershell -File TransferDriveTool-V3.ps1`). Start a transfer with at least one large file (several hundred MB+). While it's running: drag the window, resize it, hover over the current-file progress bar. It should repaint immediately and not show "Not Responding" at any point.

- [ ] **Step 2: Confirm both progress bars move visibly**

During the same transfer, confirm the overall "Files: x / y" bar advances between files, and the new current-file bar/label advances smoothly within a single large file (not just jumping 0% to 100%).

- [ ] **Step 3: Test resume across a network drop (the original bug report)**

On the Drive → MPN tab, start a transfer including a multi-GB file to the MPN network share. Mid-copy, disconnect the network (or disable the network adapter) for 30-60 seconds, then reconnect. Confirm the status log shows retry attempts and the transfer eventually completes (or, if you disconnect for longer than the backoff schedule tolerates, that it fails gracefully and leaves a `.partial`/`.partial.meta` pair next to the destination file). Re-run the same transfer and confirm it resumes rather than re-copying the whole file from scratch (the status log timing for that file should be much shorter than a full copy).

- [ ] **Step 4: Test resume across an app restart**

Start a large-file transfer, close the tool entirely partway through (or kill the process), relaunch, and re-run the same transfer. Confirm it resumes from the `.partial` file rather than restarting from zero.

- [ ] **Step 5: Confirm the CSV audit log and on-disk data are still correct**

After a completed transfer, spot-check `E:\DTA\Logging\DataTransferLog.csv` (or `C:\VIPER\DTA\DataTransferLog.csv` for the MPN tab) has the expected new rows, and that a couple of transferred files hash-match their originals.

- [ ] **Step 6: Report back**

Let the person who requested this feature know the outcome of Steps 1-5 (especially Step 3, since that's the originally-reported bug) before considering this plan complete.
