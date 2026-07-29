using System.Security.Cryptography;
using System.Text;

namespace OsdWebService.Middleware;

/// <summary>
/// Validates the X-API-Key header on every request except the /health endpoint.
/// Uses a constant-time comparison to prevent timing-based enumeration.
/// </summary>
public sealed class ApiKeyMiddleware
{
    private const string ApiKeyHeader = "X-API-Key";

    private readonly RequestDelegate _next;

    public ApiKeyMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context, IConfiguration configuration)
    {
        // Allow the health-check endpoint through without an API key so that
        // monitoring systems can probe liveness without credentials.
        if (context.Request.Path.StartsWithSegments("/health", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        if (!context.Request.Headers.TryGetValue(ApiKeyHeader, out var providedKey)
            || string.IsNullOrWhiteSpace(providedKey))
        {
            context.Response.StatusCode  = StatusCodes.Status401Unauthorized;
            context.Response.ContentType = "text/plain";
            await context.Response.WriteAsync("Missing API key.");
            return;
        }

        var expectedKey = configuration["ApiKey"];
        if (string.IsNullOrWhiteSpace(expectedKey))
        {
            // Misconfiguration — refuse all traffic.
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            await context.Response.WriteAsync("Service not configured.");
            return;
        }

        // Constant-time comparison prevents timing attacks.
        var expectedBytes = Encoding.UTF8.GetBytes(expectedKey);
        var providedBytes = Encoding.UTF8.GetBytes(providedKey.ToString());

        if (!CryptographicOperations.FixedTimeEquals(expectedBytes, providedBytes))
        {
            context.Response.StatusCode  = StatusCodes.Status401Unauthorized;
            context.Response.ContentType = "text/plain";
            await context.Response.WriteAsync("Invalid API key.");
            return;
        }

        await _next(context);
    }
}
