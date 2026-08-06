namespace DataUsageTracker.App.Models;

public sealed record ProviderResult(
    bool Success,
    long DownloadBytes,
    long UploadBytes,
    string Status,
    string Message)
{
    public static ProviderResult Ok(long downloadBytes, long uploadBytes) =>
        new(true, downloadBytes, uploadBytes, "ok", "Live data usage is updating in real time.");

    public static ProviderResult Unsupported(string message) =>
        new(false, 0, 0, "unsupported", message);

    public static ProviderResult PermissionRequired(string message) =>
        new(false, 0, 0, "permission_required", message);

    public static ProviderResult Error(string message) =>
        new(false, 0, 0, "error", message);
}
