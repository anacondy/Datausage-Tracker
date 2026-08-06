namespace DataUsageTracker.App.Models;

public sealed record UsageSnapshot(
    DateTimeOffset TimestampUtc,
    long TotalDownloadBytes,
    long TotalUploadBytes,
    double DownloadBytesPerSecond,
    double UploadBytesPerSecond,
    string Status,
    string Message,
    string Platform,
    int RefreshIntervalMs);
