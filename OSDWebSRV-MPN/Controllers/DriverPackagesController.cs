using Microsoft.AspNetCore.Mvc;
using OsdWebService.Models;
using OsdWebService.Services;

namespace OsdWebService.Controllers;

[ApiController]
[Route("api/driverpackages")]
public sealed class DriverPackagesController : ControllerBase
{
    private readonly IMecmQueryService _mecm;
    private readonly ILogger<DriverPackagesController> _logger;

    public DriverPackagesController(IMecmQueryService mecm, ILogger<DriverPackagesController> logger)
    {
        _mecm   = mecm;
        _logger = logger;
    }

    /// <summary>
    /// Returns all MECM driver packages from the configured site server.
    /// Results are cached for 10 minutes; call /api/driverpackages/refresh to bust the cache.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<DriverPackage>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public ActionResult<IReadOnlyList<DriverPackage>> GetAll()
    {
        try
        {
            return Ok(_mecm.GetDriverPackages());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to retrieve driver packages from MECM");
            return StatusCode(StatusCodes.Status500InternalServerError,
                "Unable to retrieve driver packages. Check server logs.");
        }
    }

    /// <summary>
    /// Flushes the in-memory cache so the next GET re-queries the SMS Provider.
    /// Useful after adding new driver packages to MECM without waiting for the
    /// automatic 10-minute TTL to expire.
    /// </summary>
    [HttpPost("refresh")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public IActionResult Refresh()
    {
        _mecm.InvalidateCache();
        _logger.LogInformation("Driver package cache cleared by admin request");
        return NoContent();
    }
}
