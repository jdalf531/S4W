# Archived source media

Original, unmodified Microsoft Windows 11 "Languages and Optional Features"
ISOs — the Features on Demand source content for the RSAT admin-tools
package. Kept as the historical / source record.

| File | Build | Release |
|------|-------|---------|
| `22621.1.220506-1250.ni_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 22621 | Windows 11 22H2 |
| `26100.1.240331-1435.ge_release_amd64fre_CLIENT_LOF_PACKAGES_OEM.iso` | 26100 | Windows 11 24H2 |
| `mul_languages_and_optional_features_for_windows_11_version_26h1_x64_dvd_8fb5e729.iso` | 28000 | Windows 11 26H1 |

Microsoft ships **one LOF ISO per release pair**: the `22621` ISO covers
Windows 11 22H2 **and** 23H2; the `26100` ISO covers 24H2 **and** 25H2 (see
[MS Learn — AVD language packs](https://learn.microsoft.com/en-us/azure/virtual-desktop/windows-11-language-packs)).
Those pairings are recorded as `BuildSourceMap` aliases in
`RsatCapabilities.psd1`. A future release that starts a new pair (like 26H1
/ 28000) needs its own ISO here.

`Build-RsatPackage.ps1` (in the parent folder) reads every `*.iso` here by
default, mounts each read-only, and for each of the 9 capability stems in
`RsatCapabilities.psd1` copies **every** matching cab (all architectures and
languages, ~660 total) plus the ISO's `LanguagesAndOptionalFeatures\metadata\`
folder — ~286 MB per build. Each ISO's build number is read from the cab
package manifests (`10.0.<build>.<rev>`) — **the ISO filename does not need
to contain the build number**. The ISOs are git-ignored (`*.iso`) due to
size (~6–7 GB each).
