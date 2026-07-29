namespace OsdWebService.Services;

public sealed class LogStorageService : ILogStorageService
{
    private readonly string _basePath;
    private readonly ILogger<LogStorageService> _logger;

    // Characters that are not allowed in file/folder names on Windows.
    private static readonly HashSet<char> _invalidChars =
        [.. Path.GetInvalidFileNameChars(), .. Path.GetInvalidPathChars()];

    public LogStorageService(IConfiguration configuration, ILogger<LogStorageService> logger)
    {
        _basePath = configuration["LogStorage:BasePath"]
            ?? throw new InvalidOperationException("LogStorage:BasePath must be configured in appsettings.");
        _logger = logger;
    }

    public async Task<string> StoreLogFileAsync(
        IFormFile file,
        string computerName,
        string? taskSequenceName,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;

        // Sanitize caller-supplied names to prevent path traversal.
        var safeComputer = SanitizeName(computerName, maxLength: 64);
        var safeFile    = SanitizeName(Path.GetFileName(file.FileName), maxLength: 128);

        var relativeFolderPath = Path.Combine(
            now.ToString("yyyy"),
            now.ToString("MM"),
            safeComputer);

        var absoluteFolderPath = Path.GetFullPath(
            Path.Combine(_basePath, relativeFolderPath));

        // Enforce that the resolved path is still under BasePath.
        if (!absoluteFolderPath.StartsWith(
                Path.GetFullPath(_basePath), StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Resolved storage path escaped the base directory.");
        }

        Directory.CreateDirectory(absoluteFolderPath);

        var timestamp     = now.ToString("yyyyMMdd_HHmmss");
        var zipFileName   = $"{timestamp}_{safeFile}";
        var metaFileName  = $"{timestamp}_metadata.txt";
        var absoluteZip   = Path.Combine(absoluteFolderPath, zipFileName);
        var absoluteMeta  = Path.Combine(absoluteFolderPath, metaFileName);

        // Write the zip file.
        await using (var fs = new FileStream(absoluteZip, FileMode.CreateNew, FileAccess.Write,
                                             FileShare.None, bufferSize: 81920, useAsync: true))
        {
            await file.CopyToAsync(fs, ct);
        }

        // Write a human-readable sidecar so admins see context without unzipping.
        var meta =
            $"Computer        : {computerName}\r\n" +
            $"Task Sequence   : {taskSequenceName ?? "(not provided)"}\r\n" +
            $"Upload Time UTC : {now:yyyy-MM-dd HH:mm:ss}\r\n" +
            $"File            : {file.FileName}\r\n" +
            $"Size (bytes)    : {file.Length:N0}\r\n";

        await File.WriteAllTextAsync(absoluteMeta, meta, ct);

        var relativePath = Path.Combine(relativeFolderPath, zipFileName);
        _logger.LogInformation(
            "Stored OSD log from {Computer} (TS: {TS}) → {Path}",
            computerName, taskSequenceName ?? "(none)", relativePath);

        return relativePath;
    }

    /// <summary>
    /// Replaces any character that is invalid in a Windows file/path name with '_',
    /// strips leading dots/spaces, and trims to a maximum length.
    /// </summary>
    private static string SanitizeName(string name, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(name))
            return "unknown";

        var safe = new string(name.Select(c => _invalidChars.Contains(c) ? '_' : c).ToArray())
                       .TrimStart('.', ' ');

        return safe.Length > maxLength ? safe[..maxLength] : safe;
    }
}
