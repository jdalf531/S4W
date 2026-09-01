@{
    # The complete, fixed set of capabilities the RSAT admin-tools package
    # installs. Authored in install-priority order: ServerManager, then
    # FileServices, then ActiveDirectory-DS-LDS (dependency roots), then the
    # rest. Single source of truth - Build-RsatPackage.ps1 uses CabStem,
    # Install-RSAT.ps1 uses CapabilityName. Edit here only.
    Capabilities = @(
        @{ CapabilityName = 'Rsat.ServerManager.Tools';              CabStem = 'Microsoft-Windows-ServerManager-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.FileServices.Tools';               CabStem = 'Microsoft-Windows-FileServices-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.ActiveDirectory.DS-LDS.Tools';     CabStem = 'Microsoft-Windows-ActiveDirectory-DS-LDS-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.GroupPolicy.Management.Tools';     CabStem = 'Microsoft-Windows-GroupPolicy-Management-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.Dns.Tools';                        CabStem = 'Microsoft-Windows-DNS-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.DHCP.Tools';                       CabStem = 'Microsoft-Windows-DHCP-Tools-FoD-Package' }
        @{ CapabilityName = 'Rsat.FailoverCluster.Management.Tools'; CabStem = 'Microsoft-Windows-FailoverCluster-Management-Tools-FOD-Package' }
        @{ CapabilityName = 'Rsat.BitLocker.Recovery.Tools';         CabStem = 'Microsoft-Windows-BitLocker-Recovery-Tools-FoD-Package' }
        @{ CapabilityName = 'OpenSSH.Client';                        CabStem = 'OpenSSH-Client-Package' }
    )

    # Aliases an OS CurrentBuildNumber to a different LanguagesAndOptionalFeatures
    # <build> subfolder. Install-RSAT.ps1 prefers an exact <build> subfolder
    # when one exists and only consults this map as a fallback; a build that
    # is neither present as a subfolder nor aliased here fails fast (exit 2).
    #
    # Empty on purpose. Cross-feature-release aliasing looked safe (23H2/25H2
    # ship as enablement packages, and the cab manifests carry
    # <parent buildCompare="GE"> against the base-build EditionPack) but does
    # NOT work: DISM's Features-on-Demand applicability check is stricter than
    # that version comparison. Windows 11 25H2 (build 26200) rejects the 24H2
    # (26100) cabs with 0x800f081f, "The source files could not be found."
    # Each Windows feature release needs its own LOF ISO in media-archive\,
    # matched exactly by build. Add an entry here ONLY after confirming
    # Install-RSAT.ps1 succeeds end-to-end (real Add-WindowsCapability) on the
    # aliased build.
    BuildSourceMap = @{
    }
}
