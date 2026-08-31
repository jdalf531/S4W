# S4W

Scripts, tools, and small services I use for day-to-day enterprise IT work —
mostly PowerShell, plus one ASP.NET Core web API. Each project below is
self-contained with its own README.

## Projects

| Project | Description |
|---|---|
| [DailyAppUpdate](Projects/DailyAppUpdate/README.md) | Automated daily downloader for enterprise applications using Evergreen and manual URLs. MSI-first, x64-preferred, offline-capable. |
| [TransferDriveTool](Projects/TransferDriveTool/README.md) | MPN DTA Tool — a PowerShell GUI application for secure, compliant file transfers between drives with hash verification, logging, and audit trails. |
| [OSDWebSRV-MPN](Projects/OSDWebSRV-MPN/README.md) | ASP.NET Core 8 web API for MECM OSD task sequences — accepts WinPE log uploads and serves driver package lookups. Personal fork, tuned for my environment. |
| [RSAT](Projects/RSAT/README.md) | Extracts 9 admin capabilities (RSAT tools + BitLocker + OpenSSH client) from the Windows 11 LOF OEM ISOs into a small MECM package source, with a context-aware installer for OSD task sequences (WinPE/offline) and full-OS collection deployments. Covers Win11 22H2–25H2. Pester-tested. |
| [MISC-SCRIPTS](Projects/MISC-SCRIPTS) | Configures Power BI Report Server (PBIRS) to use a Subject Alternative Name (SAN) certificate, with a Pester test suite. |

## Repo layout

```
S4W/
├── Projects/   – each tool/service, self-contained with its own README
│               (RSAT keeps its own docs/ under Projects/RSAT/)
├── docs/       – design specs and implementation plans, one pair per feature
└── README.md   – this file
```
