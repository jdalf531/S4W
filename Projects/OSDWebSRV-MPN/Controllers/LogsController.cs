using Microsoft.AspNetCore.Mvc;
using OsdWebService.Models;
using OsdWebService.Services;

namespace OsdWebService.Controllers;

[ApiController]
[Route("api/logs")]
public sealed class LogsController : ControllerBase
{
    // 500 MB ceiling — adjust in appsettings / web.config if needed.
    private const long MaxFileSizeBytes = 524_288_000;

    private readonly ILogStorageService _storage;
    private readonly ILogger<LogsController> _logger;

    public LogsController(ILogStorageService storage, ILogger<LogsController> logger)
    {
        _storage = storage;
        _logger  = logger;
    }

    /// <summary>
    /// Upload a .zip file containing OSD/SMSTS logs.
    /// Consumed by Submit-OSDLogs.ps1 from the WinPE task sequence.
    /// </summary>
    /// <remarks>
    /// Form fields:
    ///   file             – the .zip attachment (required)
    ///   computerName     – name of the OSD machine (required)
    ///   taskSequenceName – friendly name of the TS (optional)
    /// </remarks>
    [HttpPost("upload")]
    [RequestSizeLimit(MaxFileSizeBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = MaxFileSizeBytes)]
    [Consumes("multipart/form-data")]
    [ProducesResponseType(typeof(UploadResult), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(UploadResult), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<UploadResult>> Upload(
        [FromForm] IFormFile file,
        [FromForm] string computerName,
        [FromForm] string? taskSequenceName,
        CancellationToken ct)
    {
        if (file is null || file.Length == 0)
            return BadRequest(Fail("No file received."));

        if (!Path.GetExtension(file.FileName).Equals(".zip", StringComparison.OrdinalIgnoreCase))
            return BadRequest(Fail("Only .zip files are accepted."));

        if (string.IsNullOrWhiteSpace(computerName))
            return BadRequest(Fail("computerName is required."));

        if (file.Length > MaxFileSizeBytes)
            return BadRequest(Fail($"File exceeds the maximum allowed size of {MaxFileSizeBytes / 1_048_576} MB."));

        try
        {
            var relativePath = await _storage.StoreLogFileAsync(file, computerName, taskSequenceName, ct);

            return Ok(new UploadResult
            {
                Success      = true,
                Message      = "Log file stored successfully.",
                RelativePath = relativePath
            });
        }
        catch (OperationCanceledException)
        {
            return StatusCode(StatusCodes.Status499ClientClosedRequest);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to store OSD log from {Computer}", computerName);
            return StatusCode(StatusCodes.Status500InternalServerError,
                Fail("An error occurred while storing the file."));
        }
    }

    private static UploadResult Fail(string message) =>
        new() { Success = false, Message = message };
}
