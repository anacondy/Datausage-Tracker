using DataUsageTracker.App.Models;
using DataUsageTracker.App.Services;
using System.Globalization;

namespace DataUsageTracker.App.Providers;

public sealed class LinuxDataUsageProvider(ILogger<LinuxDataUsageProvider> logger) : IDataUsageProvider
{
    private const string ProcNetDevPath = "/proc/net/dev";

    public string Platform => "linux";

    public Task<ProviderResult> GetTotalsAsync(CancellationToken cancellationToken)
    {
        try
        {
            if (!File.Exists(ProcNetDevPath))
            {
                return Task.FromResult(ProviderResult.Unsupported("/proc/net/dev is unavailable on this Linux host."));
            }

            long totalRx = 0;
            long totalTx = 0;

            var lines = File.ReadAllLines(ProcNetDevPath);
            foreach (var line in lines.Skip(2))
            {
                if (!DataUsageParser.TryParseProcNetDevLine(line, out var iface, out var rx, out var tx))
                {
                    continue;
                }

                if (string.Equals(iface, "lo", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                totalRx += rx;
                totalTx += tx;
            }

            return Task.FromResult(ProviderResult.Ok(totalRx, totalTx));
        }
        catch (UnauthorizedAccessException ex)
        {
            logger.LogWarning(ex, "Permission denied while reading Linux counters");
            return Task.FromResult(ProviderResult.PermissionRequired("Permission denied while reading /proc/net/dev."));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to read Linux network usage");
            return Task.FromResult(ProviderResult.Error($"Failed to read Linux counters: {ex.Message}"));
        }
    }
}
