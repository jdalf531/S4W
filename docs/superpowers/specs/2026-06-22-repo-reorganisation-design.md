---
title: Repository Reorganisation — Two-Folder Split
date: 2026-06-22
status: approved
---

## Goal

Separate two co-located PowerShell apps into their own subfolders so each app is self-contained and the repo is easy to navigate on both the local machine and GitHub.

## Current State

All files live flat at the repository root:

```
S4W/
├── DailyAppUpdatev2.ps1
├── Evergreenscript.txt
├── README_DailyAppUpdate.md
├── TransferDriveTool-V3.ps1
├── ONBOARDING.md
└── README.md
```

## Target Structure

```
S4W/
├── DailyAppUpdate/
│   ├── DailyAppUpdatev2.ps1
│   ├── Evergreenscript.txt
│   └── README.md                  ← renamed from README_DailyAppUpdate.md
├── TransferDriveTool/
│   ├── TransferDriveTool-V3.ps1
│   ├── ONBOARDING.md
│   └── README.md                  ← existing README.md
└── README.md                      ← new root README linking to both apps
```

## File Mapping

| Current path | New path |
|---|---|
| `DailyAppUpdatev2.ps1` | `DailyAppUpdate/DailyAppUpdatev2.ps1` |
| `Evergreenscript.txt` | `DailyAppUpdate/Evergreenscript.txt` |
| `README_DailyAppUpdate.md` | `DailyAppUpdate/README.md` |
| `TransferDriveTool-V3.ps1` | `TransferDriveTool/TransferDriveTool-V3.ps1` |
| `ONBOARDING.md` | `TransferDriveTool/ONBOARDING.md` |
| `README.md` | `TransferDriveTool/README.md` |
| *(new)* | `README.md` |

## Root README Content

A brief landing page that names the repo, lists both apps with one-line descriptions, and links to each app's subfolder README.

## Constraints

- Use `git mv` for all moves so Git preserves file history.
- Commit as a single atomic commit with a clear message.
- No code changes — files are moved as-is.
