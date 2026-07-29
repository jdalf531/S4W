namespace OsdWebService.Services;

public interface ILogStorageService
{
    /// <summary>
    /// Saves the uploaded zip file under the configured base path.
    /// Returns the relative path (year\month\computer\filename).
    /// </summary>
    Task<string> StoreLogFileAsync(
        IFormFile file,
        string computerName,
        string? taskSequenceName,
        CancellationToken ct = default);
}
