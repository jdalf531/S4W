namespace OsdWebService.Models;

public sealed class DriverPackage
{
    public string PackageId { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string Version { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
    public string Manufacturer { get; init; } = string.Empty;
    /// <summary>Source size in KB as reported by MECM.</summary>
    public long SourceSizeKb { get; init; }
}
