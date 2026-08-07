# Drive → MPN Incremental Dated Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Drive → MPN tab so it mirrors the drive's per-day dated folders onto the MPN destination (one destination folder per source date) instead of recursively re-copying every historical dated folder into a single "today" folder on every run, and so a same-day re-run with new files lands only the new/changed files in a fresh incrementally-numbered sibling folder without touching what's already been delivered.

**Architecture:** A new "Drive to MPN Sync Engine" section of six pure(ish) functions is added to `TransferDriveTool-V3.ps1`: one enumerates dated source folders, one hashes completed files in a destination folder, two resolve which destination folder (unsuffixed or `-N`) a given date should target, one computes the delta of new/changed files for a date via SHA256 comparison, one orchestrates all of these into a full copy plan, and one executes that plan's copy actions. `Copy-Files`'s Tab 2 (Drive → MPN) branch is rewired to use this engine inside the existing background runspace (two phases: resolve the plan, then execute it), replacing the old flat-recursive-scan logic that assumed a non-dated source. Tab 1 (Commercial → Drive) is untouched.

**Tech Stack:** PowerShell 5.1, WPF/XAML, Pester 5 for the new pure functions (extracted from the single-file script via AST parsing so tests never execute the file's top-level WPF/domain-detection code).

## Global Constraints

- The script must remain a single `.ps1` file with no companion files it depends on at runtime — it's copied directly onto air-gapped machines and read-only removable drives (see `README.md` "Architecture > Project Structure"). All new functions live inside `TransferDriveTool-V3.ps1` itself; the new `TransferDriveTool-V3.Tests.ps1` is a dev-only test file, never deployed.
- Existing destination folders are never modified or deleted by the new logic — only ever read from (for hashing) when computing what's new.
- SHA256 (not size/timestamp) is the match method for deciding whether a file has already been delivered, per the approved design.
- A crashed/interrupted copy into a freshly-allocated suffix folder does not resume into that same folder on retry — a new suffix folder is allocated instead. This is an accepted trade-off, not a bug.
- Tab 1 (Commercial → Drive)'s existing engine, including its cross-day orphaned-`.partial` adoption logic, is unchanged.
- Design reference: `docs/superpowers/specs/2026-08-07-drive-to-mpn-incremental-folders-design.md`.

---

## Task 1: `Get-DriveDatedFolders`

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — insert immediately after the closing `}` of `Copy-FileResumable` (end of the "RESUMABLE COPY ENGINE" section, currently just before the `# INCREMENTAL COPY ENGINE (ASYNC)` comment block).
- Create: `TransferDriveTool-V3.Tests.ps1`

**Interfaces:**
- Produces: `Get-DriveDatedFolders -DriveUserRoot <string>` → `System.IO.DirectoryInfo[]`, sorted ascending by name, containing only immediate subfolders of `-DriveUserRoot` whose name matches `^\d{8}$`. Returns `@()` if the root doesn't exist or has no matches.

- [ ] **Step 1: Create the test file with the AST-extraction test helper and the first test**

Create `TransferDriveTool-V3.Tests.ps1` in the same folder as `TransferDriveTool-V3.ps1`:

```powershell
function Import-ScriptFunctions {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string[]] $Name
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

    foreach ($functionName in $Name) {
        $functionAst = $ast.FindAll(
            { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
            $true
        ) | Select-Object -First 1

        if (-not $functionAst) {
            throw "Function '$functionName' not found in '$Path'."
        }

        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
}

$script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'

Describe 'Get-DriveDatedFolders' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DriveDatedFolders')
    }

    It 'returns dated subfolders sorted chronologically' {
        $root = Join-Path $TestDrive 'Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260805') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260806') -Force | Out-Null

        $result = Get-DriveDatedFolders -DriveUserRoot $root

        $result.Name | Should -Be @('20260805', '20260806', '20260807')
    }

    It 'excludes non-dated folders like Archive' {
        $root = Join-Path $TestDrive 'Ben'
        New-Item -ItemType Directory -Path (Join-Path $root '20260805') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'Archive') -Force | Out-Null

        $result = Get-DriveDatedFolders -DriveUserRoot $root

        $result.Name | Should -Be @('20260805')
    }

    It 'returns an empty array when the root does not exist' {
        $result = @(Get-DriveDatedFolders -DriveUserRoot (Join-Path $TestDrive 'DoesNotExist'))

        $result.Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```powershell
Import-Module Pester -RequiredVersion 5.7.1 -Force
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: FAIL — `Get-DriveDatedFolders` not found (the function doesn't exist in the script yet).

- [ ] **Step 3: Add the function to `TransferDriveTool-V3.ps1`**

Find the closing `}` of `Copy-FileResumable` (the line just before the `# ============================` / `# INCREMENTAL COPY ENGINE (ASYNC)` comment block) and insert this new section immediately after it:

```powershell

# ============================
# DRIVE TO MPN SYNC ENGINE
# ============================
# Resolves what's new on the drive's dated folders vs. what's already been
# delivered to the MPN side, and allocates an incrementally-numbered sibling
# folder (<date>-1, <date>-2, ...) for a same-day re-run's new/changed files
# instead of touching an already-delivered dated folder.
function Get-DriveDatedFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DriveUserRoot
    )

    if (-not (Test-Path -LiteralPath $DriveUserRoot)) {
        return @()
    }

    Get-ChildItem -LiteralPath $DriveUserRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}$' } |
        Sort-Object Name
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool-V3.ps1 TransferDriveTool-V3.Tests.ps1
git commit -m "Add Get-DriveDatedFolders for the Drive to MPN sync engine"
```

---

## Task 2: `Get-CompletedFileHashes`

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — append after `Get-DriveDatedFolders`.
- Modify: `TransferDriveTool-V3.Tests.ps1` — append a new `Describe` block.

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `Get-CompletedFileHashes -FolderPath <string>` → `Hashtable` mapping relative path (backslash-separated, no leading separator) to SHA256 hash string, for every file under `-FolderPath` whose name does not end in `.partial` or `.partial.meta`. Returns `@{}` if the folder doesn't exist.

- [ ] **Step 1: Add the failing test**

Append to `TransferDriveTool-V3.Tests.ps1`:

```powershell

Describe 'Get-CompletedFileHashes' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-CompletedFileHashes')
    }

    It 'returns a hash per relative path for completed files' {
        $folder = Join-Path $TestDrive 'completed'
        New-Item -ItemType Directory -Path (Join-Path $folder 'sub') -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'a.txt') -Value 'alpha' -NoNewline
        Set-Content -Path (Join-Path $folder 'sub\b.txt') -Value 'beta' -NoNewline

        $result = Get-CompletedFileHashes -FolderPath $folder

        $result.Keys | Sort-Object | Should -Be @('a.txt', 'sub\b.txt')
        $result['a.txt'] | Should -Be (Get-FileHash -LiteralPath (Join-Path $folder 'a.txt') -Algorithm SHA256).Hash
    }

    It 'excludes .partial and .partial.meta files' {
        $folder = Join-Path $TestDrive 'withpartial'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'done.txt') -Value 'finished' -NoNewline
        Set-Content -Path (Join-Path $folder 'inflight.txt.partial') -Value 'half' -NoNewline
        Set-Content -Path (Join-Path $folder 'inflight.txt.partial.meta') -Value "4`n0" -NoNewline

        $result = Get-CompletedFileHashes -FolderPath $folder

        $result.Keys | Should -Be @('done.txt')
    }

    It 'returns an empty hashtable when the folder does not exist' {
        $result = Get-CompletedFileHashes -FolderPath (Join-Path $TestDrive 'missing')

        $result.Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run:
```powershell
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: the 3 new tests FAIL — `Get-CompletedFileHashes` not found. The Task 1 tests still PASS.

- [ ] **Step 3: Add the function**

Append to the "DRIVE TO MPN SYNC ENGINE" section in `TransferDriveTool-V3.ps1`, right after `Get-DriveDatedFolders`:

```powershell

function Get-CompletedFileHashes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FolderPath
    )

    $hashes = @{}

    if (-not (Test-Path -LiteralPath $FolderPath)) {
        return $hashes
    }

    $files = Get-ChildItem -LiteralPath $FolderPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.partial' -and $_.Name -notlike '*.partial.meta' }

    $trimLength = $FolderPath.TrimEnd('\', '/').Length

    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($trimLength).TrimStart('\', '/')
        $hashes[$relativePath] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }

    $hashes
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (6 tests total).

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool-V3.ps1 TransferDriveTool-V3.Tests.ps1
git commit -m "Add Get-CompletedFileHashes for the Drive to MPN sync engine"
```

---

## Task 3: `Get-DateFolderCandidates` and `Get-NextAvailableDateSuffix`

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — append after `Get-CompletedFileHashes`.
- Modify: `TransferDriveTool-V3.Tests.ps1` — append two new `Describe` blocks.

**Interfaces:**
- Consumes: nothing from Tasks 1–2.
- Produces:
  - `Get-DateFolderCandidates -DestUserRoot <string> -Date <string yyyyMMdd>` → `System.IO.DirectoryInfo[]`, every existing folder under `-DestUserRoot` named exactly `-Date` or `-Date-N` (N = positive integer), sorted with the unsuffixed folder first then ascending by N. Returns `@()` if `-DestUserRoot` doesn't exist.
  - `Get-NextAvailableDateSuffix -DestUserRoot <string> -Date <string yyyyMMdd> [-MaxSuffix <int> = 50]` → `string`, the first unused name among `-Date`, `-Date-1`, `-Date-2`, … up to `-Date-<MaxSuffix>`. Throws if all are in use.

- [ ] **Step 1: Add the failing tests**

Append to `TransferDriveTool-V3.Tests.ps1`:

```powershell

Describe 'Get-DateFolderCandidates' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DateFolderCandidates')
    }

    It 'finds the unsuffixed and numbered folders for a date, sorted by suffix' {
        $root = Join-Path $TestDrive 'mpn\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-2') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260808') -Force | Out-Null

        $result = Get-DateFolderCandidates -DestUserRoot $root -Date '20260807'

        $result.Name | Should -Be @('20260807', '20260807-1', '20260807-2')
    }

    It 'returns an empty array when the destination root does not exist' {
        $result = @(Get-DateFolderCandidates -DestUserRoot (Join-Path $TestDrive 'nope') -Date '20260807')

        $result.Count | Should -Be 0
    }
}

Describe 'Get-NextAvailableDateSuffix' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DateFolderCandidates', 'Get-NextAvailableDateSuffix')
    }

    It 'returns the plain date when no folder exists yet' {
        $root = Join-Path $TestDrive 'mpn2\Kevin'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' | Should -Be '20260807'
    }

    It 'increments to the next unused suffix' {
        $root = Join-Path $TestDrive 'mpn3\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null

        Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' | Should -Be '20260807-2'
    }

    It 'throws once MaxSuffix is exhausted' {
        $root = Join-Path $TestDrive 'mpn4\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null

        { Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' -MaxSuffix 1 } | Should -Throw
    }
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run:
```powershell
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: the 5 new tests FAIL. Existing 6 tests still PASS.

- [ ] **Step 3: Add the functions**

Append to the "DRIVE TO MPN SYNC ENGINE" section, right after `Get-CompletedFileHashes`:

```powershell

function Get-DateFolderCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DestUserRoot,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{8}$')]
        [string] $Date
    )

    if (-not (Test-Path -LiteralPath $DestUserRoot)) {
        return @()
    }

    $escapedDate = [regex]::Escape($Date)
    $pattern = "^$escapedDate(-(\d+))?$"

    Get-ChildItem -LiteralPath $DestUserRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object { if ($_.Name -eq $Date) { 0 } else { [int]($_.Name.Substring($Date.Length + 1)) } }
}

function Get-NextAvailableDateSuffix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DestUserRoot,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{8}$')]
        [string] $Date,

        [int] $MaxSuffix = 50
    )

    $existingNames = @(Get-DateFolderCandidates -DestUserRoot $DestUserRoot -Date $Date | ForEach-Object { $_.Name })

    if ($existingNames -notcontains $Date) {
        return $Date
    }

    for ($n = 1; $n -le $MaxSuffix; $n++) {
        $candidate = "$Date-$n"
        if ($existingNames -notcontains $candidate) {
            return $candidate
        }
    }

    throw "Could not allocate a destination folder for date '$Date' under '$DestUserRoot' - all suffixes up to -$MaxSuffix are already in use."
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (11 tests total).

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool-V3.ps1 TransferDriveTool-V3.Tests.ps1
git commit -m "Add Get-DateFolderCandidates and Get-NextAvailableDateSuffix"
```

---

## Task 4: `Get-NewFilesForDate`

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — append after `Get-NextAvailableDateSuffix`.
- Modify: `TransferDriveTool-V3.Tests.ps1` — append a new `Describe` block.

**Interfaces:**
- Consumes: `Get-CompletedFileHashes -FolderPath <string>` (Task 2).
- Produces: `Get-NewFilesForDate -SourceDateFolder <string> -ExistingDestFolders <System.IO.DirectoryInfo[]>` → array of `[PSCustomObject]@{ FileInfo; RelativePath }` for every file recursively under `-SourceDateFolder` that either has no same-relative-path file in any of `-ExistingDestFolders`, or has one whose SHA256 differs.

- [ ] **Step 1: Add the failing tests**

Append to `TransferDriveTool-V3.Tests.ps1`:

```powershell

Describe 'Get-NewFilesForDate' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-CompletedFileHashes', 'Get-NewFilesForDate')
    }

    It 'returns all source files when no destination folders exist yet' {
        $source = Join-Path $TestDrive 'src1\20260807'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.txt') -Value 'alpha' -NoNewline

        $result = @(Get-NewFilesForDate -SourceDateFolder $source -ExistingDestFolders @())

        $result.RelativePath | Should -Be @('a.txt')
    }

    It 'excludes a file whose content already matches an existing destination folder' {
        $source = Join-Path $TestDrive 'src2\20260807'
        $dest   = Join-Path $TestDrive 'dest2\20260807'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.txt') -Value 'alpha' -NoNewline
        Set-Content -Path (Join-Path $dest 'a.txt') -Value 'alpha' -NoNewline

        $result = @(Get-NewFilesForDate -SourceDateFolder $source -ExistingDestFolders @(Get-Item -LiteralPath $dest))

        $result.Count | Should -Be 0
    }

    It 'includes a file whose content differs from the same-named file at the destination' {
        $source = Join-Path $TestDrive 'src3\20260807'
        $dest   = Join-Path $TestDrive 'dest3\20260807'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Set-Content -Path (Join-Path $source 'a.txt') -Value 'alpha-v2' -NoNewline
        Set-Content -Path (Join-Path $dest 'a.txt') -Value 'alpha-v1' -NoNewline

        $result = @(Get-NewFilesForDate -SourceDateFolder $source -ExistingDestFolders @(Get-Item -LiteralPath $dest))

        $result.RelativePath | Should -Be @('a.txt')
    }
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run:
```powershell
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: the 3 new tests FAIL. Existing 11 tests still PASS.

- [ ] **Step 3: Add the function**

Append to the "DRIVE TO MPN SYNC ENGINE" section, right after `Get-NextAvailableDateSuffix`:

```powershell

function Get-NewFilesForDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SourceDateFolder,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.IO.DirectoryInfo[]] $ExistingDestFolders
    )

    $delivered = @{}
    foreach ($destFolder in $ExistingDestFolders) {
        $folderHashes = Get-CompletedFileHashes -FolderPath $destFolder.FullName
        foreach ($relativePath in $folderHashes.Keys) {
            if (-not $delivered.ContainsKey($relativePath)) {
                $delivered[$relativePath] = New-Object System.Collections.Generic.HashSet[string]
            }
            [void]$delivered[$relativePath].Add($folderHashes[$relativePath])
        }
    }

    $sourceFiles = Get-ChildItem -LiteralPath $SourceDateFolder -Recurse -File -ErrorAction SilentlyContinue
    $trimLength = $SourceDateFolder.TrimEnd('\', '/').Length

    $newFiles = foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($trimLength).TrimStart('\', '/')

        $isDelivered = $false
        if ($delivered.ContainsKey($relativePath)) {
            $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $isDelivered = $delivered[$relativePath].Contains($sourceHash)
        }

        if (-not $isDelivered) {
            [PSCustomObject]@{
                FileInfo     = $file
                RelativePath = $relativePath
            }
        }
    }

    @($newFiles)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (14 tests total).

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool-V3.ps1 TransferDriveTool-V3.Tests.ps1
git commit -m "Add Get-NewFilesForDate delta computation"
```

---

## Task 5: `Resolve-DriveToMpnCopyPlan`

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — append after `Get-NewFilesForDate`.
- Modify: `TransferDriveTool-V3.Tests.ps1` — append a new `Describe` block.

**Interfaces:**
- Consumes: `Get-DriveDatedFolders` (Task 1), `Get-DateFolderCandidates` and `Get-NextAvailableDateSuffix` (Task 3), `Get-NewFilesForDate` (Task 4).
- Produces: `Resolve-DriveToMpnCopyPlan -DriveUserRoot <string> -DestUserRoot <string> [-MaxSuffix <int> = 50]` → array of `[PSCustomObject]@{ Date; Action; TargetFolder; Files; Error }`, one entry per dated source folder, where `Action` is `'AlreadyDelivered'`, `'Copy'`, or `'Error'`. For `'Copy'`, `TargetFolder` is the full path to allocate/create and `Files` is the array produced by `Get-NewFilesForDate`. For `'Error'`, `Error` holds the exception message from `Get-NextAvailableDateSuffix`.

- [ ] **Step 1: Add the failing tests**

Append to `TransferDriveTool-V3.Tests.ps1`:

```powershell

Describe 'Resolve-DriveToMpnCopyPlan' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @(
            'Get-DriveDatedFolders',
            'Get-CompletedFileHashes',
            'Get-DateFolderCandidates',
            'Get-NextAvailableDateSuffix',
            'Get-NewFilesForDate',
            'Resolve-DriveToMpnCopyPlan'
        )
    }

    It 'marks a brand-new dated folder for copy when nothing exists at the destination yet' {
        $driveRoot = Join-Path $TestDrive 'drive\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $driveRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $driveRoot '20260807\report.txt') -Value 'v1' -NoNewline

        $plan = Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot

        $plan.Count | Should -Be 1
        $plan[0].Date | Should -Be '20260807'
        $plan[0].Action | Should -Be 'Copy'
        $plan[0].TargetFolder | Should -Be (Join-Path $destRoot '20260807')
        $plan[0].Files.RelativePath | Should -Be @('report.txt')
    }

    It 'reports AlreadyDelivered when the destination already has an identical file' {
        $driveRoot = Join-Path $TestDrive 'drive2\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn2\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $driveRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $driveRoot '20260807\report.txt') -Value 'v1' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $destRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $destRoot '20260807\report.txt') -Value 'v1' -NoNewline

        $plan = Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'AlreadyDelivered'
    }

    It 'allocates a -1 suffix folder for a changed file on a same-day re-run, leaving the original folder untouched' {
        $driveRoot = Join-Path $TestDrive 'drive3\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn3\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $driveRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $driveRoot '20260807\report.txt') -Value 'v1' -NoNewline
        Set-Content -Path (Join-Path $driveRoot '20260807\new_file.txt') -Value 'brand new' -NoNewline

        New-Item -ItemType Directory -Path (Join-Path $destRoot '20260807') -Force | Out-Null
        Set-Content -Path (Join-Path $destRoot '20260807\report.txt') -Value 'v1' -NoNewline

        $plan = Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot

        $plan.Count | Should -Be 1
        $plan[0].Action | Should -Be 'Copy'
        $plan[0].TargetFolder | Should -Be (Join-Path $destRoot '20260807-1')
        $plan[0].Files.RelativePath | Should -Be @('new_file.txt')

        (Get-Content -LiteralPath (Join-Path $destRoot '20260807\report.txt') -Raw) | Should -Be 'v1'
    }

    It 'returns an empty plan when there are no dated folders on the drive' {
        $driveRoot = Join-Path $TestDrive 'drive4\Kevin'
        $destRoot  = Join-Path $TestDrive 'mpn4\Kevin'
        New-Item -ItemType Directory -Path $driveRoot -Force | Out-Null

        $plan = @(Resolve-DriveToMpnCopyPlan -DriveUserRoot $driveRoot -DestUserRoot $destRoot)

        $plan.Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run:
```powershell
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: the 4 new tests FAIL. Existing 14 tests still PASS.

- [ ] **Step 3: Add the function**

Append to the "DRIVE TO MPN SYNC ENGINE" section, right after `Get-NewFilesForDate`:

```powershell

function Resolve-DriveToMpnCopyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DriveUserRoot,

        [Parameter(Mandatory)]
        [string] $DestUserRoot,

        [int] $MaxSuffix = 50
    )

    $datedFolders = Get-DriveDatedFolders -DriveUserRoot $DriveUserRoot

    $plan = foreach ($dateFolder in $datedFolders) {
        $date = $dateFolder.Name

        # The whole per-date resolution (listing/hashing existing destination
        # folders, diffing, allocating a suffix) is wrapped in one try/catch
        # so a network hiccup or permissions error on one date - anywhere in
        # that chain, not just suffix allocation - is recorded as an Error
        # entry for that date instead of aborting the rest of the plan.
        try {
            $existingCandidates = @(Get-DateFolderCandidates -DestUserRoot $DestUserRoot -Date $date)
            $newFiles = @(Get-NewFilesForDate -SourceDateFolder $dateFolder.FullName -ExistingDestFolders $existingCandidates)

            if ($newFiles.Count -eq 0) {
                [PSCustomObject]@{
                    Date         = $date
                    Action       = 'AlreadyDelivered'
                    TargetFolder = $null
                    Files        = @()
                    Error        = $null
                }
            }
            else {
                $targetName = Get-NextAvailableDateSuffix -DestUserRoot $DestUserRoot -Date $date -MaxSuffix $MaxSuffix
                [PSCustomObject]@{
                    Date         = $date
                    Action       = 'Copy'
                    TargetFolder = Join-Path $DestUserRoot $targetName
                    Files        = $newFiles
                    Error        = $null
                }
            }
        }
        catch {
            [PSCustomObject]@{
                Date         = $date
                Action       = 'Error'
                TargetFolder = $null
                Files        = @()
                Error        = $_.Exception.Message
            }
        }
    }

    @($plan)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (18 tests total).

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool-V3.ps1 TransferDriveTool-V3.Tests.ps1
git commit -m "Add Resolve-DriveToMpnCopyPlan orchestrator"
```

---

## Task 6: `Invoke-DriveToMpnDeliveryPlan`

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — append after `Resolve-DriveToMpnCopyPlan`.
- Modify: `TransferDriveTool-V3.Tests.ps1` — append a new `Describe` block.

**Interfaces:**
- Consumes: `Copy-FileResumable` (existing function, unchanged — returns `[PSCustomObject]@{ Success; SourceHash; DestHash; Error }`), `Add-CsvLogEntry` (existing function, unchanged — reads an ambient `$CsvLogPath` variable rather than taking one as a parameter; see Step 3 for why this function sets it explicitly), and the `Action`/`TargetFolder`/`Files`/`Date`/`Error` shape produced by `Resolve-DriveToMpnCopyPlan` (Task 5).
- Produces: `Invoke-DriveToMpnDeliveryPlan -Plan <object[]> -CsvLogPath <string> -LogSnapshot <PSCustomObject> -TotalFiles <int> [-OnStatus <scriptblock>] [-OnFileStart <scriptblock>] [-OnFileProgress <scriptblock>] [-OnFileComplete <scriptblock>]` → `[PSCustomObject]@{ FilesCopied; FilesSkipped }`. `-LogSnapshot` must have `DtaName, Manager, SourceSystem, DestSystem, Classification, MediaUsed, Justification, ScanVerify` properties (matches the `$snapshot` object `Copy-Files` already builds). Callbacks: `OnStatus(string)`, `OnFileStart(relativePath)`, `OnFileProgress(bytesDone, bytesTotal)`, `OnFileComplete(filesCopied, filesSkipped, totalFiles)` — all default to a no-op `{}` so they're optional in tests.

- [ ] **Step 1: Add the failing tests**

Append to `TransferDriveTool-V3.Tests.ps1`:

```powershell

Describe 'Invoke-DriveToMpnDeliveryPlan' {
    BeforeAll {
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @(
            'Copy-FileResumable',
            'Add-CsvLogEntry',
            'Invoke-DriveToMpnDeliveryPlan'
        )
    }

    BeforeEach {
        $script:CsvLogPath = Join-Path $TestDrive "log_$([guid]::NewGuid().ToString('N')).csv"
        $headers = "LogEntryNumber,DTAName,AuthorizingManager,DateTimeUTC,SourceSystem,DestinationSystem,FileName,FileClassification,FileSize,SHA256,MediaUsed,Justification,ScanReviewVerification"
        Set-Content -Path $script:CsvLogPath -Value $headers

        $script:LogSnapshot = [PSCustomObject]@{
            DtaName = 'Kevin'; Manager = 'Jane Doe'; SourceSystem = 'E:\DTA\Kevin'
            DestSystem = '\\mpn\Kevin'; Classification = 'Confidential'
            MediaUsed = 'USB_DRIVE'; Justification = 'Test'; ScanVerify = 'Yes'
        }
    }

    It 'copies delta files into the target folder and logs a CSV row with the resolved folder name' {
        $sourceFile = Join-Path $TestDrive 'source_report.txt'
        Set-Content -Path $sourceFile -Value 'hello world' -NoNewline
        $fileInfo = Get-Item -LiteralPath $sourceFile

        $targetFolder = Join-Path $TestDrive 'dest\20260807-1'
        $plan = @(
            [PSCustomObject]@{
                Date = '20260807'
                Action = 'Copy'
                TargetFolder = $targetFolder
                Files = @([PSCustomObject]@{ FileInfo = $fileInfo; RelativePath = 'report.txt' })
                Error = $null
            }
        )

        $statusMessages = [System.Collections.Generic.List[string]]::new()

        $result = Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $script:CsvLogPath `
            -LogSnapshot $script:LogSnapshot -TotalFiles 1 `
            -OnStatus { param($msg) $statusMessages.Add($msg) }

        $result.FilesCopied | Should -Be 1
        $result.FilesSkipped | Should -Be 0
        (Get-Content -LiteralPath (Join-Path $targetFolder 'report.txt') -Raw) | Should -Be 'hello world'

        $csvRows = Import-Csv -LiteralPath $script:CsvLogPath
        $csvRows.Count | Should -Be 1
        $csvRows[0].FileName | Should -Be '20260807-1\report.txt'
    }

    It 'logs a status message and copies nothing for an AlreadyDelivered entry' {
        $plan = @(
            [PSCustomObject]@{ Date = '20260805'; Action = 'AlreadyDelivered'; TargetFolder = $null; Files = @(); Error = $null }
        )
        $statusMessages = [System.Collections.Generic.List[string]]::new()

        $result = Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $script:CsvLogPath `
            -LogSnapshot $script:LogSnapshot -TotalFiles 0 `
            -OnStatus { param($msg) $statusMessages.Add($msg) }

        $result.FilesCopied | Should -Be 0
        $statusMessages | Should -Contain 'Already fully delivered for 20260805, nothing to copy.'
    }

    It 'logs an error status for an Error entry without throwing' {
        $plan = @(
            [PSCustomObject]@{ Date = '20260806'; Action = 'Error'; TargetFolder = $null; Files = @(); Error = 'boom' }
        )
        $statusMessages = [System.Collections.Generic.List[string]]::new()

        { Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $script:CsvLogPath `
            -LogSnapshot $script:LogSnapshot -TotalFiles 0 `
            -OnStatus { param($msg) $statusMessages.Add($msg) } } | Should -Not -Throw

        ($statusMessages | Where-Object { $_ -like '*boom*' }) | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run:
```powershell
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: the 3 new tests FAIL. Existing 18 tests still PASS.

- [ ] **Step 3: Add the function**

Append to the "DRIVE TO MPN SYNC ENGINE" section, right after `Resolve-DriveToMpnCopyPlan`:

```powershell

# Add-CsvLogEntry reads $CsvLogPath as an ambient variable rather than a
# parameter (see its definition above), so it must be published to global
# scope here -- both for this function's own callers (this script's
# background runspace already sets it that way) and so this function stays
# independently callable/testable without relying on caller-side setup.
function Invoke-DriveToMpnDeliveryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Plan,

        [Parameter(Mandatory)]
        [string] $CsvLogPath,

        [Parameter(Mandatory)]
        [PSCustomObject] $LogSnapshot,

        [Parameter(Mandatory)]
        [int] $TotalFiles,

        [scriptblock] $OnStatus = {},
        [scriptblock] $OnFileStart = {},
        [scriptblock] $OnFileProgress = {},
        [scriptblock] $OnFileComplete = {}
    )

    Set-Variable -Name CsvLogPath -Value $CsvLogPath -Scope Global

    $filesCopied = 0
    $filesSkipped = 0

    foreach ($entry in $Plan) {
        switch ($entry.Action) {
            'AlreadyDelivered' {
                & $OnStatus "Already fully delivered for $($entry.Date), nothing to copy."
            }
            'Error' {
                & $OnStatus "Failed to resolve a destination folder for $($entry.Date): $($entry.Error)"
            }
            'Copy' {
                if (-not (Test-Path -LiteralPath $entry.TargetFolder)) {
                    New-Item -ItemType Directory -Path $entry.TargetFolder -Force | Out-Null
                }
                $targetName = Split-Path -Leaf $entry.TargetFolder
                & $OnStatus "$($entry.Files.Count) new file(s) found for $($entry.Date), copying to $targetName"

                foreach ($file in $entry.Files) {
                    & $OnFileStart $file.RelativePath

                    $destFile = Join-Path $entry.TargetFolder $file.RelativePath
                    $destDir  = Split-Path $destFile -Parent
                    if (-not (Test-Path -LiteralPath $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }

                    $progressCallback = {
                        param($bytesDone, $bytesTotal)
                        & $OnFileProgress $bytesDone $bytesTotal
                    }.GetNewClosure()

                    $copyResult = Copy-FileResumable -Source $file.FileInfo.FullName -Destination $destFile -ProgressCallback $progressCallback

                    if (-not $copyResult.Success) {
                        & $OnStatus "Failed to copy $($file.RelativePath) after retries: $($copyResult.Error)"
                        $filesSkipped++
                        & $OnFileComplete $filesCopied $filesSkipped $TotalFiles
                        continue
                    }

                    & $OnStatus "Copied and hash-verified: $targetName\$($file.RelativePath)"

                    try {
                        $size = "{0:N0} KB" -f ($file.FileInfo.Length / 1KB)
                        Add-CsvLogEntry `
                            -DTAName        $LogSnapshot.DtaName `
                            -Manager        $LogSnapshot.Manager `
                            -SourceSystem   $LogSnapshot.SourceSystem `
                            -DestSystem     $LogSnapshot.DestSystem `
                            -FileName       "$targetName\$($file.RelativePath)" `
                            -Classification $LogSnapshot.Classification `
                            -FileSize       $size `
                            -Checksum       $copyResult.DestHash `
                            -MediaUsed      $LogSnapshot.MediaUsed `
                            -Justification  $LogSnapshot.Justification `
                            -ScanVerify     $LogSnapshot.ScanVerify

                        $filesCopied++
                    }
                    catch {
                        & $OnStatus "Failed to write CSV log for $($file.RelativePath): $($_.Exception.Message)"
                        $filesSkipped++
                    }

                    & $OnFileComplete $filesCopied $filesSkipped $TotalFiles
                }
            }
        }
    }

    [PSCustomObject]@{ FilesCopied = $filesCopied; FilesSkipped = $filesSkipped }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the same command as Step 2.
Expected: PASS (21 tests total).

- [ ] **Step 5: Commit**

```bash
git add TransferDriveTool-V3.ps1 TransferDriveTool-V3.Tests.ps1
git commit -m "Add Invoke-DriveToMpnDeliveryPlan copy executor"
```

---

## Task 7: Wire the new engine into `Copy-Files` for the Drive → MPN tab

**Files:**
- Modify: `TransferDriveTool-V3.ps1` — replace the entire `Copy-Files` function.

**Interfaces:**
- Consumes: all six functions from Tasks 1–6 (`Get-DriveDatedFolders`, `Get-CompletedFileHashes`, `Get-DateFolderCandidates`, `Get-NextAvailableDateSuffix`, `Get-NewFilesForDate`, `Resolve-DriveToMpnCopyPlan`, `Invoke-DriveToMpnDeliveryPlan`), plus the existing `Copy-FileResumable` and `Add-CsvLogEntry`.
- Produces: no new callable interface (this is the UI/runspace wiring); manually verified per Step 3 below since it depends on WPF and a live background runspace that Pester cannot exercise.

This task has no automated test — it's the glue between the tested engine and the WPF/runspace machinery, which Pester can't drive. Verification is a scripted manual run instead.

- [ ] **Step 1: Replace `Copy-Files`**

Find the `function Copy-Files {` … matching closing `}` (immediately before the `# ============================` / `# BUTTON HANDLERS` comment block) and replace the entire function with:

```powershell
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

    if ($activeTab -eq 0) {
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
    }
    else {
        $datedSourceFolders = Get-ChildItem -Path $src -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}$' }

        if (-not $datedSourceFolders) {
            Write-Status "No dated folders found under source: $src"
            return
        }
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
    $lblProgressSummary.Text = "Files: 0 / 0 | Copied: 0 | Skipped: 0"
    $lblCurrentFile.Text = "Current: (none)"
    $lblCurrentFileProgress.Text = ""
    $btnRun.IsEnabled = $false
    $btnClose.IsEnabled = $false

    try {
    $copyFileResumableBody = (Get-Item Function:\Copy-FileResumable).ScriptBlock.ToString()
    $addCsvLogEntryBody    = (Get-Item Function:\Add-CsvLogEntry).ScriptBlock.ToString()

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Copy-FileResumable", $copyFileResumableBody)))
    $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry("Add-CsvLogEntry", $addCsvLogEntryBody)))

    if ($activeTab -eq 1) {
        foreach ($functionName in @(
            'Get-DriveDatedFolders', 'Get-CompletedFileHashes', 'Get-DateFolderCandidates',
            'Get-NextAvailableDateSuffix', 'Get-NewFilesForDate', 'Resolve-DriveToMpnCopyPlan',
            'Invoke-DriveToMpnDeliveryPlan'
        )) {
            $body = (Get-Item "Function:\$functionName").ScriptBlock.ToString()
            $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($functionName, $body)))
        }
    }

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
    $runspace.SessionStateProxy.SetVariable("SrcRoot", $src)
    $runspace.SessionStateProxy.SetVariable("DstRoot", $dstRoot)
    $runspace.SessionStateProxy.SetVariable("Snapshot", $snapshot)

    if ($activeTab -eq 0) {
        $runspace.SessionStateProxy.SetVariable("Files", $files)
        $runspace.SessionStateProxy.SetVariable("DstUserRoot", $dstRoot)

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

            $orphanedPartials = @{}
            $completedElsewhere = @{}
            for ($daysAgo = 1; $daysAgo -le 7; $daysAgo++) {
                $candidateDateFolder = Join-Path $DstUserRoot ((Get-Date).AddDays(-$daysAgo).ToString("yyyyMMdd"))
                if (-not (Test-Path $candidateDateFolder)) { continue }
                Get-ChildItem -Path $candidateDateFolder -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.Name.EndsWith(".partial")) {
                        $relPath = $_.FullName.Substring($candidateDateFolder.Length).TrimStart("\", "/") -replace '\.partial$', ''
                        if (-not $orphanedPartials.ContainsKey($relPath)) {
                            $orphanedPartials[$relPath] = $_.FullName
                        }
                    }
                    elseif (-not $_.Name.EndsWith(".partial.meta")) {
                        $relPath = $_.FullName.Substring($candidateDateFolder.Length).TrimStart("\", "/")
                        if (-not $completedElsewhere.ContainsKey($relPath)) {
                            $completedElsewhere[$relPath] = $_
                        }
                    }
                }
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
                elseif ($completedElsewhere.ContainsKey($relativePath) -and $completedElsewhere[$relativePath].LastWriteTimeUtc -ge $file.LastWriteTimeUtc) {
                    Write-BackgroundStatus "(skip) Already transferred in a previous dated folder: $relativePath"
                    $filesSkipped++
                    Update-BackgroundProgress
                    continue
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

                if (-not (Test-Path "$destFile.partial") -and $orphanedPartials.ContainsKey($relativePath)) {
                    $orphanPartial = $orphanedPartials[$relativePath]
                    $orphanMeta = "$orphanPartial.meta"
                    if (Test-Path $orphanMeta) {
                        $metaLines = @(Get-Content -LiteralPath $orphanMeta -ErrorAction SilentlyContinue)
                        $srcInfo = Get-Item -LiteralPath $file.FullName
                        if ($metaLines.Count -ge 2 -and $metaLines[0] -eq "$($srcInfo.Length)" -and $metaLines[1] -eq "$($srcInfo.LastWriteTimeUtc.Ticks)") {
                            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                            try {
                                Move-Item -LiteralPath $orphanPartial -Destination "$destFile.partial" -Force
                                Move-Item -LiteralPath $orphanMeta -Destination "$destFile.partial.meta" -Force
                                Write-BackgroundStatus "Adopting orphaned partial copy for $relativePath (resuming across a day boundary)"
                            }
                            catch {
                                Write-BackgroundStatus "Failed to adopt orphaned partial copy for $relativePath : $($_.Exception.Message)"
                                foreach ($stray in @("$destFile.partial", "$destFile.partial.meta", $orphanPartial, $orphanMeta)) {
                                    if (Test-Path -LiteralPath $stray) { Remove-Item -LiteralPath $stray -Force -ErrorAction SilentlyContinue }
                                }
                            }
                        }
                    }
                }

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
    }
    else {
        $batchScript = {
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

            $startTime = Get-Date

            Write-BackgroundStatus "Resolving what's new on the drive for each dated folder..."
            $plan = @(Resolve-DriveToMpnCopyPlan -DriveUserRoot $SrcRoot -DestUserRoot $DstRoot -MaxSuffix 50)

            foreach ($entry in $plan) {
                if ($entry.Action -eq 'AlreadyDelivered') {
                    Write-BackgroundStatus "$($entry.Date): already fully delivered, nothing to copy."
                }
                elseif ($entry.Action -eq 'Error') {
                    Write-BackgroundStatus "$($entry.Date): failed to resolve a destination folder - $($entry.Error)"
                }
            }

            $totalFiles = ($plan | Where-Object { $_.Action -eq 'Copy' } | ForEach-Object { $_.Files.Count } | Measure-Object -Sum).Sum
            if (-not $totalFiles) { $totalFiles = 0 }

            $Dispatcher.Invoke([action]{
                $lblProgressSummary.Text = "Files: 0 / $totalFiles | Copied: 0 | Skipped: 0"
            }, "Normal")

            if ($totalFiles -eq 0) {
                Write-BackgroundStatus "Nothing new to transfer."
                Write-BackgroundStatus "Transfer complete."
                $elapsed = (Get-Date) - $startTime
                Write-BackgroundStatus "Summary: Total=0, Copied=0, Skipped=0, Elapsed=$($elapsed.ToString())"
                return
            }

            $onStatus = { param($msg) Write-BackgroundStatus $msg }.GetNewClosure()

            $onFileStart = {
                param($relativePath)
                $Dispatcher.Invoke([action]{
                    $lblCurrentFile.Text = "Current: $relativePath"
                    $pbCurrentFile.Value = 0
                    $lblCurrentFileProgress.Text = ""
                }, "Normal")
            }.GetNewClosure()

            $onFileProgress = {
                param($bytesDone, $bytesTotal)
                $percent = if ($bytesTotal -gt 0) { [math]::Round(($bytesDone / $bytesTotal) * 100, 0) } else { 0 }
                $doneMb = [math]::Round($bytesDone / 1MB, 1)
                $totalMb = [math]::Round($bytesTotal / 1MB, 1)
                $Dispatcher.Invoke([action]{
                    $pbCurrentFile.Value = $percent
                    $lblCurrentFileProgress.Text = "$doneMb MB / $totalMb MB"
                }, "Normal")
            }.GetNewClosure()

            $onFileComplete = {
                param($copied, $skipped, $total)
                $percent = [math]::Round((($copied + $skipped) / $total) * 100, 0)
                $Dispatcher.Invoke([action]{
                    $pbProgress.Value = $percent
                    $lblProgressSummary.Text = "Files: $($copied + $skipped) / $total | Copied: $copied | Skipped: $skipped"
                }, "Normal")
            }.GetNewClosure()

            $result = Invoke-DriveToMpnDeliveryPlan -Plan $plan -CsvLogPath $CsvLogPath -LogSnapshot $Snapshot `
                -TotalFiles $totalFiles -OnStatus $onStatus -OnFileStart $onFileStart `
                -OnFileProgress $onFileProgress -OnFileComplete $onFileComplete

            $elapsed = (Get-Date) - $startTime
            Write-BackgroundStatus "Transfer complete."
            Write-BackgroundStatus "Summary: Total=$totalFiles, Copied=$($result.FilesCopied), Skipped=$($result.FilesSkipped), Elapsed=$($elapsed.ToString())"

            $Dispatcher.Invoke([action]{
                $lblCurrentFile.Text = "Current: (none)"
                $pbCurrentFile.Value = 0
                $lblCurrentFileProgress.Text = ""
            }, "Normal")
        }
    }

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $powershell.AddScript($batchScript) | Out-Null
    $asyncResult = $powershell.BeginInvoke()
    }
    catch {
        Write-Status "Failed to start transfer: $($_.Exception.Message)"

        if ($powershell) { $powershell.Dispose() }
        if ($runspace) { $runspace.Close(); $runspace.Dispose() }

        $btnRun.IsEnabled = $true
        $btnClose.IsEnabled = $true
        return
    }

    $transferStartTime = Get-Date
    $stallTimeout = [TimeSpan]::FromMinutes(10)

    $completionTimer = New-Object System.Windows.Threading.DispatcherTimer
    $completionTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $completionTimer.Add_Tick({
        if (-not $asyncResult.IsCompleted) {
            if (((Get-Date) - $transferStartTime) -gt $stallTimeout) {
                $completionTimer.Stop()
                Write-Status "Transfer did not finish within $([int]$stallTimeout.TotalMinutes) minutes and appears stalled. Re-enabling controls; verify the destination files manually, since the background transfer's true state is now unknown."
                try { $powershell.Stop() } catch {}
                $btnRun.IsEnabled = $true
                $btnClose.IsEnabled = $true
            }
            return
        }

        $completionTimer.Stop()

        try {
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
        }
        catch {
            Write-Status "Error cleaning up transfer runspace: $($_.Exception.Message)"
        }
        finally {
            $btnRun.IsEnabled = $true
            $btnClose.IsEnabled = $true
        }
    }.GetNewClosure())
    $completionTimer.Start()
}
```

- [ ] **Step 2: Run the full Pester suite to confirm nothing broke**

Run:
```powershell
Invoke-Pester -Path "TransferDriveTool-V3.Tests.ps1" -Output Detailed
```
Expected: all 21 tests still PASS (this task only touches `Copy-Files`, which none of them exercise directly).

- [ ] **Step 3: Manual verification on a real (or simulated EUR-domain) machine**

Since `Copy-Files` drives real WPF controls and a live background runspace, verify by hand. If this machine isn't domain-joined to `EUR*`, temporarily edit the `$ToolMode` assignment (around the `DOMAIN DETECTION` section) to force `$ToolMode = "MPN"` for this test, then revert it afterward — do not commit that change.

Set up fixtures (adjust drive letter/paths to match the machine):
```powershell
Remove-Item 'E:\DTA\Kevin' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item '\\<mpn-share>\Kevin' -Recurse -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path 'E:\DTA\Kevin\20260805' -Force | Out-Null
Set-Content 'E:\DTA\Kevin\20260805\old_report.txt' -Value 'from the 5th' -NoNewline

New-Item -ItemType Directory -Path 'E:\DTA\Kevin\20260807' -Force | Out-Null
Set-Content 'E:\DTA\Kevin\20260807\report.txt' -Value 'v1' -NoNewline
```

Run the tool, select user `Kevin` on the Drive → MPN tab, click Run. Expected in the status log:
- `20260805: ...` and `20260807: ...` each get a "N new file(s) found, copying to 20260805" / "...20260807" line (first-ever run, nothing delivered yet).
- Two `Copied and hash-verified: ...` lines.
- `\\<mpn-share>\Kevin\20260805\old_report.txt` and `\\<mpn-share>\Kevin\20260807\report.txt` both exist with correct content.

Now simulate a same-day re-run with a new file added to the existing date:
```powershell
Set-Content 'E:\DTA\Kevin\20260807\new_file.txt' -Value 'added later' -NoNewline
```
Click Run again. Expected:
- `20260805: already fully delivered, nothing to copy.`
- `20260807: 1 new file(s) found, copying to 20260807-1`
- `\\<mpn-share>\Kevin\20260807\report.txt` is untouched (still just that one file, unchanged content).
- `\\<mpn-share>\Kevin\20260807-1\new_file.txt` exists with content `added later`.

Run a third time with no drive changes. Expected: both dates report `already fully delivered, nothing to copy.` and the status log ends with `Summary: Total=0, Copied=0, Skipped=0, ...` without creating any new folder.

Check the CSV log (`C:\VIPER\DTA\DataTransferLog.csv`) has `FileName` values `20260807\report.txt`, `20260805\old_report.txt`, and `20260807-1\new_file.txt` respectively.

- [ ] **Step 4: Commit**

```bash
git add TransferDriveTool-V3.ps1
git commit -m "Wire the Drive to MPN sync engine into Copy-Files"
```

---

## Task 8: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `ONBOARDING.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update `README.md`**

In the **Features > Core Transfer Capabilities** section, replace this bullet:
```
- **Dated destination folders** (`yyyyMMdd`) — every run's output lands in its own dated folder, never mixed with a previous day's.
```
with:
```
- **Dated destination folders** (`yyyyMMdd`) — every run's output lands in its own dated folder, never mixed with a previous day's.
- **Drive → MPN mirrors the drive's own dated folders** — rather than always writing to "today," each of the drive's per-day folders is copied to a same-named folder on the MPN side. A same-day re-run that finds new or changed files for a date that's already been delivered never touches the existing folder — it lands only the new/changed files in an incrementally-numbered sibling (`<date>-1`, `<date>-2`, ...), determined by SHA256 comparison against everything already delivered for that date.
```

In the **Architecture > Data Flow** section, after the closing ` ``` ` of the existing diagram, add a second diagram:
```

Drive → MPN (Tab 2) resolves and executes in two phases instead of a single flat scan:

```
Background runspace:
  Phase 1 - Resolve-DriveToMpnCopyPlan, per dated folder on the drive:
    ├─ List existing <date> / <date>-1 / <date>-2 ... folders on the MPN side
    ├─ Hash their completed files (skip stray .partial / .partial.meta)
    ├─ Diff against the drive's current dated folder (SHA256 compare)
    └─ AlreadyDelivered (nothing new) | Copy (allocate next free suffix) | Error
    ↓
  Phase 2 - Invoke-DriveToMpnDeliveryPlan:
    For each Copy entry: create the target folder, copy each new file
    (Copy-FileResumable, same as Tab 1), Add-CsvLogEntry, report progress
```
```

In the **🔌 Function Reference** section, after the `Invoke-DriveArchiveSweep` / `Invoke-SourceArchiveSweep` entry, add:
```

#### `Resolve-DriveToMpnCopyPlan`
```powershell
Resolve-DriveToMpnCopyPlan -DriveUserRoot <path> -DestUserRoot <path> [-MaxSuffix <int> = 50]
```
Drive → MPN only. For each dated folder on the drive, hashes every existing `<date>[-N]` folder already on the MPN side and diffs against the drive's current content to decide whether that date is already fully delivered, needs a fresh `<date>[-N]` folder for its new/changed files, or hit an error allocating one (e.g. all 50 suffixes in use). Returns one plan entry per dated folder; never modifies anything itself.

#### `Invoke-DriveToMpnDeliveryPlan`
```powershell
Invoke-DriveToMpnDeliveryPlan -Plan <object[]> -CsvLogPath <path> -LogSnapshot <object> -TotalFiles <int> [-OnStatus <scriptblock>] [-OnFileStart <scriptblock>] [-OnFileProgress <scriptblock>] [-OnFileComplete <scriptblock>]
```
Executes the `Copy` entries from a `Resolve-DriveToMpnCopyPlan` plan: creates each target folder, copies its files via `Copy-FileResumable`, and logs each success via `Add-CsvLogEntry` with the target folder name prefixed onto the logged file name (e.g. `20260807-1\report.txt`).
```

Update the CSV Audit Trail Format example if desired to show a suffixed folder name in `FileName`, e.g. add a second example row:
```
"2026-015","jdalf531","John Smith","2026-08-07 09:10Z","E:\DTA\Kevin","\\mpn-share\Kevin","20260807-1\new_file.txt","Confidential","12 KB","B7A1...","USB_DRIVE","Same-day follow-up delivery","Yes"
```

- [ ] **Step 2: Update `ONBOARDING.md`**

In **Core Functions > File Transfer Operations**, after the `Copy-Files` bullet, add:
```
- `Resolve-DriveToMpnCopyPlan` / `Invoke-DriveToMpnDeliveryPlan`: Drive → MPN only. Mirrors the drive's own dated folders onto the MPN destination one-to-one; a same-day re-run with new/changed files gets an incrementally-numbered sibling folder (`<date>-1`, ...) instead of touching what's already delivered. Matching is by SHA256, not timestamp.
```

In **Important Behaviors**, add a new subsection after **Dated Folder Structure**:
```

### Drive → MPN Incremental Folders
Unlike Tab 1 (which always writes to today's dated folder), Tab 2 mirrors each of the drive's existing per-day dated folders onto the MPN destination under the same name. If a date's destination folder already exists and the drive now has new or changed files for that date, they land in a new `<date>-1` (then `-2`, etc.) sibling folder instead of modifying the existing one. See `docs/superpowers/specs/2026-08-07-drive-to-mpn-incremental-folders-design.md` for the full design.
```

- [ ] **Step 3: Commit**

```bash
git add README.md ONBOARDING.md
git commit -m "Document the Drive to MPN incremental-folder behavior"
```
