# Archived source media

Original, unmodified Microsoft "Client LOF Packages OEM" ISOs — the Features
on Demand source content for the RSAT admin-tools package. Kept as the
historical / source record.

| File | Windows build | Release |
|------|---------------|---------|
| `22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 22621 | Windows 11 22H2 |
| `26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 26100 | Windows 11 24H2 |

`Build-RsatPackage.ps1` (in the parent folder) reads every `*.iso` here by
default, mounts each read-only, and extracts only the 9 cabs listed in
`RsatCapabilities.psd1`. The ISOs are git-ignored (`*.iso`) due to size
(~6–7 GB each).
