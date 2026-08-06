using DataUsageTracker.App.Models;
using DataUsageTracker.App.Services;
using System.Diagnostics;

namespace DataUsageTracker.App.Providers;

public sealed class WindowsDataUsageProvider(ILogger<WindowsDataUsageProvider> logger) : IDataUsageProvider
{
    public string Platform => "windows";

    public async Task<ProviderResult> GetTotalsAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "netstat",
                    Arguments = "-e",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            if (!process.Start())
            {
                return ProviderResult.Error("Failed to start netstat.");
            }

            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

            await process.WaitForExitAsync(cancellationToken);

            var output = await outputTask;
            var error = await errorTask;

            if (process.ExitCode != 0)
            {
                var detail = string.IsNullOrWhiteSpace(error) ? "netstat returned a non-zero exit code." : error.Trim();
                return ProviderResult.Error(detail);
            }

            if (!DataUsageParser.TryParseWindowsNetstatBytes(output, out var downloadBytes, out var uploadBytes))
            {
                return ProviderResult.Error("Unable to parse netstat output for total bytes.");
            }

            return ProviderResult.Ok(downloadBytes, uploadBytes);
        }
        catch (UnauthorizedAccessException ex)
        {
            logger.LogWarning(ex, "Permission denied while reading Windows counters");
            return ProviderResult.PermissionRequired("Permission denied while reading Windows network counters.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to read Windows network usage");
            return ProviderResult.Error($"Failed to read Windows counters: {ex.Message}");
        }
    }
}
