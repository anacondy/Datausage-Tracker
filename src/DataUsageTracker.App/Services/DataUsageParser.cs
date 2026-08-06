using System.Globalization;
using System.Text.RegularExpressions;

namespace DataUsageTracker.App.Services;

public static partial class DataUsageParser
{
    [GeneratedRegex(@"^\s*Bytes\s+([0-9,]+)\s+([0-9,]+)", RegexOptions.IgnoreCase | RegexOptions.Multiline)]
    private static partial Regex WindowsBytesRegex();

    public static bool TryParseWindowsNetstatBytes(string output, out long downloadBytes, out long uploadBytes)
    {
        downloadBytes = 0;
        uploadBytes = 0;

        if (string.IsNullOrWhiteSpace(output))
        {
            return false;
        }

        var match = WindowsBytesRegex().Match(output);
        if (!match.Success)
        {
            return false;
        }

        if (!long.TryParse(match.Groups[1].Value.Replace(",", string.Empty), NumberStyles.Integer, CultureInfo.InvariantCulture, out downloadBytes))
        {
            return false;
        }

        return long.TryParse(match.Groups[2].Value.Replace(",", string.Empty), NumberStyles.Integer, CultureInfo.InvariantCulture, out uploadBytes);
    }

    public static bool TryParseProcNetDevLine(string line, out string iface, out long downloadBytes, out long uploadBytes)
    {
        iface = string.Empty;
        downloadBytes = 0;
        uploadBytes = 0;

        if (string.IsNullOrWhiteSpace(line))
        {
            return false;
        }

        var parts = line.Split(':', 2, StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            return false;
        }

        iface = parts[0].Trim();
        var metrics = parts[1].Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (metrics.Length < 9)
        {
            return false;
        }

        if (!long.TryParse(metrics[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out downloadBytes))
        {
            return false;
        }

        return long.TryParse(metrics[8], NumberStyles.Integer, CultureInfo.InvariantCulture, out uploadBytes);
    }
}
