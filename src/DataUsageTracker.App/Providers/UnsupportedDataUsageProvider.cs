using DataUsageTracker.App.Models;

namespace DataUsageTracker.App.Providers;

public sealed class UnsupportedDataUsageProvider(string platform, string message) : IDataUsageProvider
{
    public string Platform { get; } = platform;

    public Task<ProviderResult> GetTotalsAsync(CancellationToken cancellationToken) =>
        Task.FromResult(ProviderResult.Unsupported(message));
}
