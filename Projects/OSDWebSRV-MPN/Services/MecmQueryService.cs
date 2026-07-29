using System.Management;
using Microsoft.Extensions.Caching.Memory;
using OsdWebService.Models;

namespace OsdWebService.Services;

public sealed class MecmQueryService : IMecmQueryService
{
    private const string CacheKey        = "mecm_driver_packages";
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(10);

    private readonly string _siteServer;
    private readonly string _siteCode;
    private readonly IMemoryCache _cache;
    private readonly ILogger<MecmQueryService> _logger;

    public MecmQueryService(
        IConfiguration configuration,
        IMemoryCache cache,
        ILogger<MecmQueryService> logger)
    {
        _siteServer = configuration["Mecm:SiteServer"]
            ?? throw new InvalidOperationException("Mecm:SiteServer must be configured in appsettings.");
        _siteCode = configuration["Mecm:SiteCode"]
            ?? throw new InvalidOperationException("Mecm:SiteCode must be configured in appsettings.");
        _cache  = cache;
        _logger = logger;
    }

    public IReadOnlyList<DriverPackage> GetDriverPackages()
    {
        if (_cache.TryGetValue(CacheKey, out IReadOnlyList<DriverPackage>? cached) && cached is not null)
            return cached;

        var packages = QueryMecm();
        _cache.Set(CacheKey, packages, CacheTtl);
        return packages;
    }

    public void InvalidateCache() => _cache.Remove(CacheKey);

    // -----------------------------------------------------------------------
    // Private
    // -----------------------------------------------------------------------

    private IReadOnlyList<DriverPackage> QueryMecm()
    {
        var result = new List<DriverPackage>();

        // Build WMI scope against the SMS Provider namespace.
        // The IIS application pool identity must be a member of the SMS Admins
        // local security group on the site server (read-only access is sufficient).
        var scopePath = $@"\\{_siteServer}\root\SMS\site_{_siteCode}";
        _logger.LogInformation("Connecting to MECM WMI scope: {Scope}", scopePath);

        var options = new ConnectionOptions
        {
            Impersonation = ImpersonationLevel.Impersonate,
            EnablePrivileges = true
        };

        var scope = new ManagementScope(scopePath, options);
        scope.Connect();

        const string wql =
            "SELECT PackageID, Name, Version, Description, Manufacturer, SourceSize " +
            "FROM SMS_DriverPackage ORDER BY Name";

        using var searcher = new ManagementObjectSearcher(scope, new ObjectQuery(wql));
        using var queryResult = searcher.Get();

        foreach (ManagementObject obj in queryResult)
        {
            result.Add(new DriverPackage
            {
                PackageId    = obj["PackageID"]?.ToString()    ?? string.Empty,
                Name         = obj["Name"]?.ToString()         ?? string.Empty,
                Version      = obj["Version"]?.ToString()      ?? string.Empty,
                Description  = obj["Description"]?.ToString()  ?? string.Empty,
                Manufacturer = obj["Manufacturer"]?.ToString() ?? string.Empty,
                SourceSizeKb = Convert.ToInt64(obj["SourceSize"] ?? 0L)
            });
        }

        _logger.LogInformation("Retrieved {Count} driver packages from MECM", result.Count);
        return result.AsReadOnly();
    }
}
