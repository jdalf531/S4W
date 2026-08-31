# Archived source media

Original, unmodified Microsoft Windows 11 "Languages and Optional Features"
ISOs — the Features on Demand source content for the RSAT admin-tools
package. Kept as the historical / source record.

| File | Build | Release |
|------|-------|---------|
| `22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 22621 | Windows 11 22H2 |
| `26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 26100 | Windows 11 24H2 |
| `mul_languages_and_optional_features_for_windows_11_version_26h1_x64_dvd_8fb5e729.iso` | 28000 | Windows 11 (next branch; disc labelled "26H1") |

`Build-RsatPackage.ps1` (in the parent folder) reads every `*.iso` here by
default, mounts each read-only, verifies the 9 cabs listed in
`RsatCapabilities.psd1` are present, and reads each ISO's build number from
the cab package manifests (`10.0.<build>.<rev>`) — **the ISO filename does
not need to contain the build number**. The ISOs are git-ignored (`*.iso`)
due to size (~6–7 GB each).
