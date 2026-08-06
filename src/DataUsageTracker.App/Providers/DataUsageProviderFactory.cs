namespace DataUsageTracker.App.Providers;

public static class DataUsageProviderFactory
{
    public static IDataUsageProvider Create(ILoggerFactory loggerFactory)
    {
        var logger = loggerFactory.CreateLogger("DataUsageProviderFactory");

        if (OperatingSystem.IsWindows())
        {
            logger.LogInformation("Using Windows data usage provider.");
            return new WindowsDataUsageProvider(loggerFactory.CreateLogger<WindowsDataUsageProvider>());
        }

        if (OperatingSystem.IsLinux())
        {
            logger.LogInformation("Using Linux data usage provider.");
            return new LinuxDataUsageProvider(loggerFactory.CreateLogger<LinuxDataUsageProvider>());
        }

        if (OperatingSystem.IsAndroid())
        {
            return new UnsupportedDataUsageProvider("android", "Android global network counters are unavailable in this browser-hosted runtime without a native bridge.");
        }

        if (OperatingSystem.IsIOS())
        {
            return new UnsupportedDataUsageProvider("ios", "iOS global network counters are unavailable in this browser-hosted runtime without a native bridge.");
        }

        return new UnsupportedDataUsageProvider("unsupported", "This platform is not supported for system-level usage collection.");
    }
}
