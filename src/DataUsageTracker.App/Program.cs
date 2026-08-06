using DataUsageTracker.App.Models;
using DataUsageTracker.App.Providers;
using DataUsageTracker.App.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<IDataUsageProvider>(sp => DataUsageProviderFactory.Create(sp.GetRequiredService<ILoggerFactory>()));
builder.Services.AddSingleton<RealTimeUsageSampler>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<RealTimeUsageSampler>());

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapGet("/api/usage", (RealTimeUsageSampler sampler) => Results.Ok(sampler.Current));

app.MapGet("/api/health", () => Results.Ok(new
{
    status = "ok",
    utc = DateTimeOffset.UtcNow,
    runtime = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
    os = System.Runtime.InteropServices.RuntimeInformation.OSDescription
}));

app.Run();

public partial class Program;
