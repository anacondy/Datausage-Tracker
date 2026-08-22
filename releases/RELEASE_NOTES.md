# Release Notes — DataUsageTracker v1.0.0

Branch: `arena/01a029b8-datausage-tracker`  
PR: https://github.com/anacondy/Datausage-Tracker/pull/1  
Commit: `93177bd`

---

## What Was Released

### Windows (`releases/windows/DataUsageTracker-v1.0.0-windows.zip`)
**Status: STABLE — Full functionality**

Contains the original PowerShell scripts and all audit artifacts:
- `DataUsageTracker.ps1` — adapter + per-app usage tracking (WinRT)
- `FindDataHog.ps1` — download scanner
- `ChromeDataProbe.ps1` — browser process inspection
- `.bat` launchers with defensive PowerShell checks
- Full docs (`docs/`) including Security Audit, Methodology Report, Cross-Platform Assessment, UI Optimization
- `tests/test_cross_platform.py` — structural validation framework
- `ui/index.html` — browser-based CSV dashboard

**Requirements**: Windows 11 (PowerShell 5.1+ or PowerShell 7+). WinRT APIs (`Windows.Networking`) are used for per-app tracking.

---

### Linux (`releases/linux/DataUsageTracker-v1.0.0-linux.tar.gz`)
**Status: STABLE — Adapter-level tracking only (no per-app WinRT equivalent)**

Contains Python 3 alternatives using standard library (`/proc/net/dev`) and optional `psutil`:
- `python/data_tracker_cross_platform.py` — adapter byte counters, CSV logging
- `python/find_data_hog_cross_platform.py` — file scanning for recent downloads
- `docs/` — same audit reports (for reference)
- `ui/index.html` — same HTML dashboard (works with exported CSV)

**Requirements**: Python 3.7+. For full adapter statistics, install `psutil` (`pip install psutil`). Per-app usage tracking (like Windows WinRT SRUM) is **not available** on Linux — this is an OS limitation, not a script limitation.

---

### macOS (`releases/macos/DataUsageTracker-v1.0.0-macos.tar.gz`)
**Status: STABLE — Adapter-level tracking (same as Linux package)**

Same Python scripts as Linux release. Works on macOS with Python 3.7+.

**Requirements**: Python 3.7+. `psutil` recommended (`pip install psutil`) for adapter statistics. Per-app usage tracking (WinRT equivalent) is **not available** on macOS.

---

## What Works vs What Doesn't (Cross-Platform Truth)

| Feature | Windows | Linux | macOS |
|---|---|---|---|
| Adapter byte tracking (`DataUsageTracker`) | Full (WinRT + `Get-NetAdapterStatistics`) | Partial (`/proc/net/dev` or `psutil`) | Partial (`psutil` or Python standard lib) |
| Per-app usage (`DataUsageTracker`) | Full (WinRT `GetAttributedNetworkUsageAsync`) | Not possible (no SRUM equivalent) | Not possible |
| Download scanning (`FindDataHog`) | Full (browser prefs + folder scan) | Partial (`~/.config/chrome`, `~/.mozilla/firefox`) | Partial (`~/Library/Application Support/`) |
| Browser process probe (`ChromeDataProbe`) | Full (`Get-Process`, `Get-NetTCPConnection`) | Not included in Python package | Not included in Python package |
| Scheduled background tracking | Full (Windows Task Scheduler) | Not included (`cron` or `systemd` would be needed) | Not included (`launchd` would be needed) |
| HTML dashboard (`ui/index.html`) | Full | Full | Full |

---

## How to Use Each Release

### Windows
```batch
# Extract zip, then double-click:
Run-DataUsageTracker.bat
Run-FindDataHog.bat
Run-ChromeDataProbe.bat
```

### Linux / macOS
```bash
# Extract tar.gz
python3 python/data_tracker_cross_platform.py
python3 python/find_data_hog_cross_platform.py
# View results in browser:
open ui/index.html   # or xdg-open / browser of choice
```

---

## Dependencies

| Platform | Required | Optional |
|---|---|---|
| Windows | Windows 11, PowerShell | None |
| Linux | Python 3.7+ | `psutil` (`pip install psutil`) |
| macOS | Python 3.7+ | `psutil` (`pip install psutil`) |

---

## Limitations Acknowledged

1. **Per-app usage is Windows-only** — Windows maintains a System Resource Usage Monitor (SRUM) database that has no direct Linux/macOS equivalent. The Python alternatives provide adapter-level tracking only.
2. **Scheduled background tracking is Windows-only** — The `.ps1` uses `Register-ScheduledTask`. Linux/macOS users would need to set up `cron` or `systemd` timers separately.
3. **Browser download folder scanning is adapted, not identical** — The `.ps1` reads Windows `Preferences` JSON and `prefs.js`. The Python version uses standard Linux/macOS profile paths (`~/.config/google-chrome`, `~/Library/Application Support/Google/Chrome`).
4. **Live connection monitoring (`ChromeDataProbe`) is not included in Linux/macOS packages** — It relies on `Get-NetTCPConnection` (Windows-specific). A Python equivalent using `psutil.Process.connections()` could be added in future releases.

---

## Next Release Plan (Not Merged — Continuing in PR #1)

- [ ] Add Python-based live connection monitor (`python/chrome_probe_cross_platform.py`)
- [ ] Add Linux/macOS scheduled tracking instructions (`docs/linux_scheduling.md`)
- [ ] Create binary/executable releases (PyInstaller or similar) for users without Python
- [ ] Add chart visualization to `ui/index.html` using a lightweight library

---

*No forced merge. All releases packaged from the `arena/01a029b8-datausage-tracker` branch. PR remains open for continued work.*
