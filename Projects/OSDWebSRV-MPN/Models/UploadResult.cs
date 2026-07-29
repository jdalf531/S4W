namespace OsdWebService.Models;

public sealed class UploadResult
{
    public bool Success { get; init; }
    public string Message { get; init; } = string.Empty;
    /// <summary>
    /// Relative path (year/month/computer/filename) where the file was stored.
    /// Intentionally omits the full server path to avoid information disclosure.
    /// </summary>
    public string RelativePath { get; init; } = string.Empty;
}
