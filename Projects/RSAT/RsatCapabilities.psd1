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

    # Maps an OS CurrentBuildNumber to the LanguagesAndOptionalFeatures
    # <build> subfolder whose cabs satisfy it, for builds that do not ship
    # their own ISO. 25H2 (26200) is an enablement package on 24H2's (26100)
    # servicing branch and the FoD cab manifests allow build >= 26100, so
    # the 26100 cabs install cleanly on it. Install-RSAT.ps1 still prefers an
    # exact <build> subfolder when one exists; a build that is neither
    # present as a subfolder nor listed here fails fast (exit 2).
    BuildSourceMap = @{
        '26200' = '26100'
    }
}
