# Resumable, non-blocking file transfer for TransferDriveTool-V3

## Problem

`TransferDriveTool-V3.ps1` runs the entire transfer (`Copy-Files`, called from
`$btnRun.Add_Click`) synchronously on the WPF UI thread. WPF only repaints and
processes input when its Dispatcher is idle between queued operations; since
the click handler doesn't return control until the whole transfer finishes,
the window appears "Not Responding" for the entire duration of a run,
especially on slow network-share copies. The existing progress bar
(`$pbProgress`, updated in `Update-ProgressUI`) is invisible for the same
reason — the value is set correctly but no render pass occurs to show it.

Separately, large files copied to the MPN network share have no resume
capability: a network drop mid-copy means the retry logic in
`Copy-WithRetry` restarts the file from byte zero.

## Goals

- The UI stays responsive (repaints, accepts input) throughout a transfer.
- A large file interrupted by a network drop resumes from where it left off,
  both on automatic retry within a run and after a full app restart.
- Progress is visible: overall files-done count (existing) and current-file
  byte progress (new).
- The tool must still run when launched directly from a read-only external
  drive — nothing in this design writes next to the script file itself.

## Architecture

### Background execution

`Copy-Files` snapshots everything the transfer needs from UI controls
(selected user, `Manager`/`Classification`/`Justification`/etc. text values,
`$CsvLogPath`, the scanned file list) into plain variables *before* starting
work. It then creates a background `Runspace`, injects those snapshotted
values plus the required function definitions
(`Copy-FileResumable`, `Add-CsvLogEntry`), and invokes the transfer loop
there via `BeginInvoke()`.

The background runspace never touches WPF controls directly. Progress is
reported by calling `$Window.Dispatcher.Invoke(...)` from the background
thread, throttled to roughly every 250ms or every few MB (not per chunk), to
update:

- `$pbProgress` / `$lblProgressSummary` — existing overall files-done bar.
- A new `$pbCurrentFile` / `$lblCurrentFileProgress` — current file's byte
  progress (e.g. "Copying big_video.mp4: 340 MB / 900 MB").
- `$txtStatus` (via the existing `Write-Status`) for log lines.

`$btnRun` and `$btnClose` are disabled while a transfer is in flight and
re-enabled on completion or failure, preventing overlapping runs or closing
the window out from under an active runspace. No cancel button — out of
scope for this change.

### Resumable copy engine

`Copy-FileResumable` replaces the `Copy-Item` call inside `Copy-WithRetry`.
It is pure .NET (`FileStream`, `SHA256`) with no WPF/PowerShell-control
dependency, since it runs inside the background runspace.

- **Chunked copy**: reads/writes in 4 MB chunks. The source SHA-256 hash is
  computed incrementally as chunks are read, avoiding a separate full-file
  hash pass after copy.
- **Write-to-`.partial`, then atomic rename**: copies to
  `<destfile>.partial` in the destination folder. Only once the copy
  completes and the destination hash (read once from the finished
  `.partial`) matches the incrementally-computed source hash does it
  `Move-Item` the `.partial` onto the real destination filename. The real
  destination file is never touched mid-copy. This fully replaces the
  current backup-copy-then-restore dance in `Copy-WithRetry` — write-then-
  atomic-rename is strictly safer, since any existing destination file is
  untouched until the new copy is verified complete.
- **Sidecar metadata** (`<destfile>.partial.meta`, plain text): records the
  source file's `Length` and `LastWriteTimeUtc` alongside the partial copy.
  On (re)start — whether resuming after a dropped connection within the same
  run, or from a fresh app launch after a crash/close — if a `.partial` and
  matching `.meta` exist and the source file's length/`LastWriteTimeUtc`
  still match what's recorded, the copy seeks to the `.partial` file's
  current size and appends from there. If the source changed, or the
  `.meta` is missing/mismatched, the stale `.partial` is deleted and the
  copy restarts from byte 0.
- **Retry/backoff**: on a copy error, retry with delays of 2s, 5s, 15s, 30s,
  then every 60s, capped at 15 total attempts (~13 minutes) before marking
  that file failed and moving to the next file in the batch. Each retry
  resumes from the `.partial` file's current byte offset. This replaces the
  current fixed 3-attempt/1s-sleep loop in `Copy-WithRetry`.

This engine applies to every file, not just large ones — small files simply
complete in one or two chunks with no added overhead of consequence.

## Data flow (per file, inside the background runspace)

1. Check for an existing `<destfile>.partial` + `.partial.meta`. Validate
   against the current source file's length/`LastWriteTimeUtc`. If valid,
   resume from the recorded offset; otherwise delete and start fresh.
2. Open source and `.partial` streams, copy in 4 MB chunks, updating the
   incremental source hash and posting throttled progress via
   `Dispatcher.Invoke`.
3. On a transient I/O error: retry per the backoff schedule above, resuming
   from the `.partial` file's current size each attempt.
4. On success: hash the completed `.partial`, compare to the incremental
   source hash. Match → `Move-Item` onto the real destination filename,
   delete `.meta`, call `Add-CsvLogEntry`, increment `FilesCopied`. Mismatch
   → log a hash-mismatch error (existing behavior), leave `.partial` in
   place for investigation, increment `FilesSkipped`.
5. On exhausting all retries: log failure, leave `.partial`/`.meta` on disk
   for a future run to resume, increment `FilesSkipped`, continue to the
   next file.

## Error handling

- A single file failing all retries no longer stalls the batch — the loop
  continues to the next file.
- Hash mismatches keep today's existing behavior (logged as a mismatch,
  non-fatal, file not counted as copied).
- `.partial` and `.meta` files are never silently deleted except when
  starting a fresh copy over a stale/invalid one, or after a verified
  successful copy.

## Testing

No test framework exists for this script (single-file PowerShell/WPF app).
Verification plan:

1. Standalone scratch-directory tests of `Copy-FileResumable` (not the full
   GUI): normal copy + hash match, simulated mid-copy failure followed by
   resume producing a byte-identical file, and stale/mismatched `.meta`
   correctly triggering a restart-from-zero.
2. Full-script parse check (`Parser]::ParseFile`) after implementation.
3. Manual click-through on a real test network by the user, including
   interrupting the network mid-transfer on a large file, since that's the
   scenario this feature exists to handle — this cannot be driven from this
   environment.

## Out of scope

- Cancel button / user-initiated abort of an in-progress transfer.
- Resumable copy for the Commercial→Drive leg's underlying source read (the
  network drop scenario described is specific to the MPN network share, but
  the engine is shared by both tabs since both can write to a network-ish
  destination and the logic is identical either way).
