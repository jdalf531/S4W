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
    # Microsoft ships ONE "Languages and Optional Features" ISO per pair of
    # releases: the 22621 ISO covers 22H2 (22621) AND 23H2 (22631); the 26100
    # ISO covers 24H2 (26100) AND 25H2 (26200). The FoD CompDB confirms this -
    # the RSAT Features carry <parent buildCompare="GE" version="0.0.0.0">,
    # i.e. no version lock. So enablement-package builds are aliased to their
    # base build's folder.
    # (See MS Learn "Install language packs on Windows 11 Enterprise VMs in
    # Azure Virtual Desktop".)
    BuildSourceMap = @{
        '22631' = '22621'   # Win11 23H2 -> 22H2 LOF ISO
        '26200' = '26100'   # Win11 25H2 -> 24H2 LOF ISO
    }
}
