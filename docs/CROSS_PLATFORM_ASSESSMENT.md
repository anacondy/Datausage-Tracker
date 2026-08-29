# Cross-Platform Assessment
Date: 2026-08-22 | Project: DataUsageTracker

## Current Platform Status
| Component | Windows 11 | Linux | macOS | Notes |
|---|---|---|---|---|
| `DataUsageTracker.ps1` (main tracker) | FULL | NONE | NONE | Requires WinRT (`Windows.Networking`), `Get-NetAdapterStatistics`, `Get-ScheduledTask`, `Register-ScheduledTask` |
| `FindDataHog.ps1` (download scanner) | FULL | PARTIAL* | PARTIAL* | Browser profile paths are Windows-specific (`$env:LOCALAPPDATA`, `HKLM` registry). File scanning logic (`Get-ChildItem`) is portable to PowerShell Core. |
| `ChromeDataProbe.ps1` (browser probe) | FULL | PARTIAL* | PARTIAL* | `Get-Process`, `Get-NetTCPConnection`, `MainWindowTitle` are available in PowerShell Core on Linux/macOS, but browser process names and paths differ. |
| `.bat` launchers | FULL | NONE | NONE | Windows batch syntax |
| `.ps1` syntax (PowerShell Core) | FULL | FULL | FULL | Scripts use standard PowerShell syntax; PowerShell 7+ (`pwsh`) supports Linux/macOS. |

\* Partial = if run with `pwsh` (PowerShell Core) and if user adapts paths/registry access.

## Why Not Fully Cross-Platform?

### Windows-Specific Dependencies (Hard Blockers)
1. **WinRT API (`Windows.Networking.Connectivity`)**
   - Used by `DataUsageTracker.ps1` to read per-app usage (`GetAttributedNetworkUsageAsync`) and per-day totals (`GetNetworkUsageAsync`).
   - No equivalent Linux/macOS API exists in PowerShell Core.
   - Linux alternative: `nethogs` (per-process network usage) + `/proc/net/dev` (adapter stats). macOS alternative: `nettop` + `netstat`.

2. **`Get-NetAdapterStatistics`**
   - Windows PowerShell cmdlet that reads adapter byte counters from WMI/network stack.
   - Linux equivalent: `cat /sys/class/net/<iface>/statistics/rx_bytes` + `/tx_bytes`.
   - macOS equivalent: `netstat -ib` or `ifconfig`.

3. **Scheduled Task (`Get-ScheduledTask`, `Register-ScheduledTask`)**
   - Windows Task Scheduler integration.
   - Linux equivalent: `cron` or `systemd` timers.
   - macOS equivalent: `launchd`.

4. **Windows Registry (`Get-ChildItem` on `HKLM:`)**
   - Used by `FindDataHog.ps1` to find user profile paths (`ProfileImagePath`).
   - Linux equivalent: `/etc/passwd` or `/home/*` scanning.
   - macOS equivalent: `/Users/*` scanning.

5. **Browser Profile Paths**
   - Hardcoded to Windows directory structures (`%LOCALAPPDATA%`, `%APPDATA%`).
   - Linux paths: `~/.config/google-chrome/`, `~/.mozilla/firefox/`.
   - macOS paths: `~/Library/Application Support/Google/Chrome/`, `~/Library/Application Support/Firefox/`.

## What Would Be Required for Cross-Platform Support

### Option A: Add Linux/macOS Adapter and Per-Process Monitoring
Create Python or `pwsh` wrappers that use native OS APIs:

```bash
# Linux adapter stats
cat /sys/class/net/wlan0/statistics/rx_bytes

# Linux per-process network usage
sudo nethogs -t

# Linux TCP connections (established)
ss -tan state established
```

### Option B: Python Wrapper / Reimplementation
A Python reimplementation (`data_usage_tracker.py`) could use:
- `psutil` for adapter statistics (`psutil.net_io_counters(pernic=True)`) — works on Windows, Linux, macOS.
- `psutil` for per-process connections (`psutil.Process.connections()`).
- `sqlite3` for browser download folder detection (read Chrome `Preferences` JSON directly — same format on all platforms).

This would make the project fully cross-platform with minimal platform-specific code.

### Option C: PowerShell Core (`pwsh`) Compatibility Layer
Modify `.ps1` files to detect OS and branch:

```powershell
if ($IsWindows) {
    # Use WinRT, TaskScheduler, HKLM
} elseif ($IsLinux) {
    # Use /proc/net/dev, /sys/class/net/*, cron
} elseif ($IsMacOS) {
    # Use netstat, System Preferences
}
```

However, `Windows.Networking.Connectivity` is unavailable outside Windows, so the per-app usage feature (`DataUsageTracker`) still requires a native replacement.

## Recommendation for This Project
Given the user's request ("make sure its cross platform"), the best practical approach is:

1. **Keep the Windows `.ps1` scripts as-is** — they work correctly on their target platform.
2. **Add a Python cross-platform companion script** (`tests/test_cross_platform.py` and optionally `python/data_tracker.py`) that replicates the adapter-monitoring and download-scanning functionality using `psutil`.
3. **Document clearly** that full per-app usage tracking (WinRT SRUM) is Windows-only, but adapter tracking and download scanning can work anywhere.

---

## Tests Performed for Cross-Platform Readiness

| Test | Result | Evidence |
|---|---|---|
| Can `.ps1` syntax run with `pwsh` on Linux? | PARTIAL | PowerShell Core (`pwsh`) is not installed in this sandbox. The syntax is standard PS 5.1; `pwsh` 7+ supports it, but Windows-specific cmdlets will fail. |
| Can `.bat` files work on Linux? | NO | Batch syntax requires `cmd.exe`. |
| Are file paths portable? | NO | Hardcoded `%LOCALAPPDATA%`, `%APPDATA%`, `HKLM:` registry paths. |
| Could a Python version work on Linux? | YES | `tests/test_cross_platform.py` demonstrates adapter stat reading via Python `subprocess` to `cat /sys/class/net/*/statistics/*`. |

---

## Conclusion
**The project is currently Windows-only.** It cannot run fully on Linux or macOS without either:
- A native OS-specific replacement module (Python/`pwsh` branch), or
- Running inside a Windows VM/container (e.g., Wine for `.ps1` — not practical for WinRT APIs).

A cross-platform Python companion (`python/` directory with `psutil`-based adapters and download scanning) has been proposed and partially demonstrated.
