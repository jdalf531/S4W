using OsdWebService.Middleware;
using OsdWebService.Services;

var builder = WebApplication.CreateBuilder(args);

// ------------------------------------------------------------------
// Services
// ------------------------------------------------------------------
builder.Services.AddControllers();
builder.Services.AddMemoryCache();
builder.Services.AddHealthChecks();

builder.Services.AddSingleton<ILogStorageService, LogStorageService>();
builder.Services.AddSingleton<IMecmQueryService, MecmQueryService>();

// Increase the default request body size limit for large zip uploads.
// This matches the ceiling enforced in the controller and in web.config.
const long maxBodyBytes = 524_288_000; // 500 MB

builder.Services.Configure<IISServerOptions>(o =>
    o.MaxRequestBodySize = maxBodyBytes);

builder.WebHost.ConfigureKestrel(o =>
    o.Limits.MaxRequestBodySize = maxBodyBytes);

// ------------------------------------------------------------------
// Middleware pipeline
// ------------------------------------------------------------------
var app = builder.Build();

// Redirect plain HTTP to HTTPS (belt-and-suspenders; IIS should handle this too).
app.UseHttpsRedirection();

// API key authentication — every request except /health must present X-API-Key.
app.UseMiddleware<ApiKeyMiddleware>();

app.MapHealthChecks("/health");
app.MapControllers();

app.Run();
