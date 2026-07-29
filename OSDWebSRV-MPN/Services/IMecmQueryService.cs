using OsdWebService.Models;

namespace OsdWebService.Services;

public interface IMecmQueryService
{
    /// <summary>Returns all driver packages from the MECM SMS Provider (cached).</summary>
    IReadOnlyList<DriverPackage> GetDriverPackages();

    /// <summary>Clears the cached driver package list so the next call re-queries MECM.</summary>
    void InvalidateCache();
}
