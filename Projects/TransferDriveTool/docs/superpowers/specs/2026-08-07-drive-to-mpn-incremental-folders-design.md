# Drive → MPN: incremental dated folders (design)

## Problem

On the Drive → MPN tab (Tab 2), `TransferDriveTool-V3.ps1`'s copy engine always writes
to `<MPN dest>\<today's date>` and always recursively scans the *entire* drive source
folder (`E:\DTA\<user>`). But that source folder isn't flat — it already contains one
dated subfolder per day, written by the Commercial → Drive tab (Tab 1). Because the
per-file dedup logic is keyed on a path shape that assumes a flat source, it never
matches, so every historical dated subfolder on the drive gets fully re-copied and
nested inside *today's* destination folder on every run — compounding data with every
use.

Separately, when the same day's drive folder is pushed to MPN more than once in a day
(because more files landed on the drive between runs), the tool needs to add the new
files without disturbing what's already been delivered.

This only affects Tab 2. Tab 1's source (`C:\Viper\DTA\<user>`) is genuinely flat, so
its existing per-file skip/overwrite logic is unaffected and unchanged by this design.

## Goals

- Mirror the drive's dated-folder structure onto the MPN destination, one destination
  folder per source dated folder — never collapse everything into "today."
- Never modify or delete a destination folder that already exists — existing delivered
  content is immutable once written.
- When a same-day re-run finds new or changed files for a date that's already been
  (partially) delivered, land only the new/changed files in a fresh incrementally
  numbered sibling folder (`<date>-1`, `<date>-2`, …), rather than touching the
  existing folder.
- Keep the UI responsive during the (potentially slow, network-hashing) work of
  figuring out what's new.

## Algorithm (per dated source folder on the drive)

For each top-level subfolder of `E:\DTA\<user>` whose name matches `^\d{8}$` (i.e. each
dated folder; `Archive` and anything else is skipped since discovery is non-recursive
at this level):

1. **Build the "already delivered" set.** List every existing destination folder for
   that date: `<dest>\<date>`, `<dest>\<date>-1`, `<date>-2`, … (however many exist).
   For every *complete* file in each of those (i.e. not a `.partial` or
   `.partial.meta` — those represent an abandoned prior attempt and are ignored, not
   treated as delivered), record its relative path and SHA256 hash.
2. **Compute the delta.** A file currently in the drive's dated folder counts as "new"
   if either: no file exists at that relative path in any existing destination folder
   for that date, or one does exist but its hash differs from the source file's hash
   (same filename, different content — the multiple-copies-same-day case).
3. **Empty delta → skip.** Nothing changed since the last delivery for that date; log
   "already fully delivered" and move on to the next date. Not an error.
4. **Non-empty delta → allocate a target folder.** Starting from `<date>` and
   incrementing (`<date>-1`, `<date>-2`, …, capped at 50 to guard against an infinite
   loop if folder creation is somehow never succeeding), find the first suffix that
   does not yet exist, create it, and copy *only the delta files* into it, preserving
   their relative paths from within the drive's dated folder.

Existing folders are read-only inputs to this process (for hashing) — never written to
or deleted.

**Accepted trade-off:** if the tool crashes or is stopped mid-copy while writing a
delta into a freshly allocated suffix folder, a later re-run will not resume into that
same partially-written folder. It recomputes the delta (now smaller, since whatever
finished copying already counts as "delivered" per step 1) and allocates a new suffix
folder for the remainder. No data loss or duplication results — just potentially more
suffix folders than a single successful run would have produced. Confirmed acceptable.

## Implementation shape

**Two-phase background runspace, Tab 2 only.** Today, `Copy-Files` scans the whole
source tree on the UI thread before handing a flat file list to the background
runspace (see `TransferDriveTool-V3.ps1` around line 1093 and the `$batchScript` at
line 1153). For Tab 2, resolving what's new requires hashing existing destination
files over the network, which can be slow — so this moves into the background
runspace rather than blocking the UI thread:

- **Phase 1 (resolution).** For each dated source folder, run the algorithm above:
  enumerate existing `<date>[-N]` destination folders, hash their complete files,
  diff against the drive's current dated folder. Emit one status-log line per date:
  either "already fully delivered, nothing to copy" or "N new file(s) found, will
  copy to `<resolved target folder>`". This phase entirely replaces the existing
  cross-day `completedElsewhere` / orphaned-`.partial` lookback logic (lines
  ~1178–1272) for this tab — that logic assumed a flat source and no longer applies.
  Tab 1 keeps that logic unchanged.
- **Phase 2 (copy).** Once every date's delta and target folder is resolved, flatten
  them into a single job list (`{SourceFile, RelativePath, TargetDst}`) and copy using
  the existing per-file pipeline unchanged: `Copy-FileResumable`, the byte-level
  progress callback, retry/backoff, and `Add-CsvLogEntry`. The progress bar's "Files: X
  / Y" total becomes known once Phase 1 completes across all dates, same as today's
  behavior where the total is known before the bar starts moving.

**Folder discovery.** Only top-level subfolders of the drive's `E:\DTA\<user>`
matching `^\d{8}$` are treated as dated folders. Loose files sitting directly at the
drive root (outside any dated folder) are logged as a warning and left alone.

**Matching mechanics.** Relative path is checked first (cheap); SHA256 is only
computed for a source/destination pair when a same-named file already exists at that
relative path in some existing destination folder for the date — so hashing work
scales with name collisions, not with total delivered file count.

**CSV compliance log.** The `FileName` field logs the *resolved* destination folder
plus relative path (e.g. `20260807-1\subdir\report.txt`) instead of just the relative
path, so the log stays traceable to a specific physical folder even when a day's
delivery spans multiple suffixed folders.

## Error handling

- **Phase 1 failure for one date** (network hiccup, permissions while listing/hashing
  an existing destination folder): logged and that date is skipped; other dates still
  get processed. Does not abort the whole run.
- **Phase 2 failure:** unchanged from today — `Copy-FileResumable`'s existing
  15-attempt backoff retry handles transient per-file copy failures.
- **Suffix allocation cap:** stops at `-50` and logs an error rather than looping
  forever, in case folder creation is failing for every candidate (e.g. a permissions
  problem) so no candidate ever ends up usable.
- **All dates already fully delivered:** not an error; status log reports "Nothing new
  to transfer" and the run completes normally (same tone as today's "No files found to
  transfer" case).

## Out of scope

- Tab 1 (Commercial → Drive) — unchanged.
- The drive-side archive sweep (`Invoke-DriveArchiveSweep`) and its "only runs in
  Commercial mode" behavior — unchanged; out of scope for this fix.
- Cleaning up abandoned `.partial`/`.partial.meta` files left behind in a folder after
  a crash — they're ignored by the delivered-set calculation but not deleted.
