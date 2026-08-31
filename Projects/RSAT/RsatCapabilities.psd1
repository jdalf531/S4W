@{
    # The complete, fixed set of capabilities the RSAT admin-tools package
    # installs. Authored in install-priority order: ServerManager, then
    # FileServices, then ActiveDirectory-DS-LDS (dependency roots), then the
    # rest. Single source of truth — Build-RsatPackage.ps1 uses CabStem,
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
}
