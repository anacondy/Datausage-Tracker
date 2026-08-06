using DataUsageTracker.App.Models;
using DataUsageTracker.App.Providers;
using Microsoft.Extensions.Hosting;

namespace DataUsageTracker.App.Services;

public sealed class RealTimeUsageSampler(
    IDataUsageProvider provider,
    ILogger<RealTimeUsageSampler> logger) : BackgroundService
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1);
    private readonly Lock _lock = new();
    private UsageSnapshot _current = new(
        DateTimeOffset.UtcNow,
        0,
        0,
        0,
        0,
        "starting",
        "Collecting first sample...",
        provider.Platform,
        (int)PollInterval.TotalMilliseconds);

    private DateTimeOffset? _lastTimestamp;
    private long _lastDownload;
    private long _lastUpload;

    public UsageSnapshot Current
    {
        get
        {
            lock (_lock)
            {
                return _current;
            }
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(PollInterval);

        while (!stoppingToken.IsCancellationRequested)
        {
            await SampleAsync(stoppingToken);

            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken))
                {
                    break;
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task SampleAsync(CancellationToken cancellationToken)
    {
        var timestamp = DateTimeOffset.UtcNow;
        var result = await provider.GetTotalsAsync(cancellationToken);

        if (!result.Success)
        {
            lock (_lock)
            {
                _current = _current with
                {
                    TimestampUtc = timestamp,
                    Status = result.Status,
                    Message = result.Message,
                    Platform = provider.Platform
                };
            }

            return;
        }

        var downloadRate = 0d;
        var uploadRate = 0d;

        if (_lastTimestamp is not null)
        {
            var elapsedSeconds = (timestamp - _lastTimestamp.Value).TotalSeconds;
            if (elapsedSeconds > 0)
            {
                var downloadDelta = result.DownloadBytes >= _lastDownload ? result.DownloadBytes - _lastDownload : 0;
                var uploadDelta = result.UploadBytes >= _lastUpload ? result.UploadBytes - _lastUpload : 0;

                downloadRate = downloadDelta / elapsedSeconds;
                uploadRate = uploadDelta / elapsedSeconds;
            }
        }

        _lastTimestamp = timestamp;
        _lastDownload = result.DownloadBytes;
        _lastUpload = result.UploadBytes;

        lock (_lock)
        {
            _current = new UsageSnapshot(
                timestamp,
                result.DownloadBytes,
                result.UploadBytes,
                downloadRate,
                uploadRate,
                result.Status,
                result.Message,
                provider.Platform,
                (int)PollInterval.TotalMilliseconds);
        }
    }
}
