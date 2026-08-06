using DataUsageTracker.App.Models;

namespace DataUsageTracker.App.Providers;

public interface IDataUsageProvider
{
    string Platform { get; }

    Task<ProviderResult> GetTotalsAsync(CancellationToken cancellationToken);
}
