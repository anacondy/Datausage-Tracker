# Testing Across Environments & Failure Mode Analysis

Date: 2026-08-22 (revised 2026-08-29 after independent audit)  
Branch: arena/01a04ccb-datausage-tracker  
PR: https://github.com/anacondy/Datausage-Tracker/pull/1

> **v1.0.1 corrections (per AUDIT_REPORT.md):** the Arch/KDE row below no longer
> claims `Nice=-5` (impossible for unprivileged user services) and desktop
> notifications are now actually implemented, not merely checked. The
> "`/proc/net/dev` and psutil fallback" wording has been corrected: on Linux the
> tracker reads `/proc/net/dev` directly (it always exists on Linux); `psutil`
> is only consulted on the unusual no-/proc case and on non-Linux platforms.

---

## Environments Tested (or Designed For)

| Environment | Method | Status | Notes |
|---|---|---|---|
| Linux Sandbox (this workspace) | Python `test_cross_platform.py` passed | VERIFIED | File integrity, syntax, security patterns, cross-platform readiness |
| Arch Linux + KDE Plasma | `systemd` user service (`datausage-tracker.service`) with `Nice=10`, `MemoryMax=64M`, `IOSchedulingClass=idle`, `CPUSchedulingPolicy=idle`, `CPUQuota=10%` | READY | Real `notify-send` desktop notifications (threshold-based); requires `libnotify`. v1.0.0 claimed `Nice=-5`, which is impossible for unprivileged user services — corrected. |
| Linux (non-systemd) | Manual execution: `python3 python/data_tracker_cross_platform.py` | READY | Falls back gracefully; writes CSV to `~/DataUsageLogs/` |
| Windows 11 | `.ps1` scripts + `.bat` launchers + `TaskScheduler` | READY | `DataUsageTracker` registered; runs every 30 min |
| macOS | `launchd` agent (`com.datausage.tracker`) + `python3` scripts | READY | `StartInterval=1800`; `Nice=10` in plist terms |
| Any browser (UI) | `ui/index.html` (zero dependencies) | READY | Upload `.csv` and view formatted results |

---

## Failure Modes Tested / Documented

### 1. Linux — `systemd` User Daemon Not Running
- **Cause**: User logs out, or `systemctl --user` unavailable.
- **Behavior**: Service stops; no crash.
- **Recovery**: `python3 data_tracker.py` runs manually; timer resumes at next login.
- **Mitigation in install script**: `systemctl --user daemon-reload` with `2>/dev/null`; manual run message shown.

### 2. Linux — `/proc/net/dev` Unreadable
- **Cause**: Restricted container or custom kernel without `/proc` access.
- **Behavior**: `read_adapters_linux()` returns empty dict.
- **Recovery**: v1.0.1 tracker detects the missing/unreadable `/proc/net/dev`
  and falls back to `psutil` if installed (`pip install psutil`); otherwise it
  prints "No adapter statistics available." and exits cleanly.
- **Note (audit correction)**: on any normal Linux box `/proc/net/dev` is
  ALWAYS present, so `/proc/net/dev` is the primary path and `psutil` is only a
  fallback for the unusual no-/proc case. The earlier wording overstated this.

### 3. Linux — `psutil` Not Installed
- **Cause**: Minimal container or fresh install without `pip`.
- **Behavior**: Adapter tracking works via `/proc/net/dev` (no psutil needed);
  `chrome_probe_cross_platform.py` prints warning and returns limited results.
- **Recovery**: `pip install psutil` (documented in script output and `RELEASE_NOTES.md`).

### 4. Windows — `WinRT` API Unavailable
- **Cause**: Minimal Windows installation or very old Windows version.
- **Behavior**: `DataUsageTracker.ps1` falls back gracefully (`Initialize-WinRT` returns `false`); adapter stats (`Get-NetAdapterStatistics`) still work; per-app data unavailable.
- **Mitigation**: Script writes warnings silently (`Write-Warning`); `-Quiet` suppresses them.

### 5. Windows — Adapter Counter Reset (Reboot)
- **Cause**: PC reboot resets adapter byte counters.
- **Behavior**: `current < previous` detected; delta = full current value (no double counting); lifetime totals survive via `baseline.json`.
- **Mitigation**: Built into `Save-LogPoint()` logic (`if ($a.Received -ge $prevRec) ... else { $a.Received }`).

### 6. Windows — Dedup Guard Triggered
- **Cause**: Manual `-Log` runs twice within 15 seconds (e.g., user clicks rapidly).
- **Behavior**: Second run outputs "Skip: a log point was just written (dedup guard)."; no duplicate CSV entry.
- **Mitigation**: `last_run.json` check before every write.

### 7. Windows — `ScheduledTask` Already Exists
- **Cause**: Re-running `-Schedule` after previous registration.
- **Behavior**: `Register-Tracker` detects existing task (`Get-ScheduledTask`); writes "already exists" message; does not create duplicate.
- **Mitigation**: `if (Get-ScheduledTask ...)` guard in script.

### 8. macOS — `launchd` Agent Not Loaded After Reboot
- **Cause**: `launchctl load -w` may not persist across certain macOS updates or user changes.
- **Behavior**: Agent stops running after reboot; no crash; adapter tracking stops until agent is reloaded.
- **Recovery**: `launchctl load -w ~/Library/LaunchAgents/com.datausage.tracker.plist` (documented in install script).
- **Mitigation**: `RunAtLoad=true` in plist; `StartInterval=1800` ensures periodic runs when loaded.

### 9. All Platforms — CSV Corruption / Manual Edit
- **Cause**: User edits `DataUsage_Log.csv` with invalid format.
- **Behavior**: Dashboard (`ui/index.html`) parses lines; malformed rows show empty values or `—`. No crash.
- **Mitigation**: HTML parser uses `String.replace(/"/g, ...)` and default values; `formatBytes` handles `parseFloat` failures (`|| 0`).

### 10. Browser UI — Large CSV Upload
- **Cause**: User uploads very large CSV (e.g., years of logs).
- **Behavior**: `parseCSV` limits display to first 40 rows; table renders quickly; no memory crash.
- **Mitigation**: `select -First 40` equivalent in HTML (`results.slice(0, 40)`).

---

## What Works the Same Everywhere

| Feature | Linux | Windows | macOS |
|---|---|---|---|
| Adapter byte tracking (read-only OS counters) | `/proc/net/dev` (psutil only if `/proc` unavailable) | `Get-NetAdapterStatistics` | `psutil` |
| Delta / append / reboot-safe methodology | Yes (v1.0.1 port of the Windows logic) | Yes (original) | Yes (v1.0.1 port) |
| CSV logging | `~/DataUsageLogs/` | `%USERPROFILE%\DataUsageLogs\` | `~/DataUsageLogs/` |
| HTML dashboard (`ui/index.html`) | Any browser | Any browser | Any browser |
| Security audit available (`docs/SECURITY_AUDIT.md`) | Readable | Readable | Readable |
| Methodology docs (`docs/METHODOLOGY_TEST_REPORT.md`) | Readable | Readable | Readable |
| Cross-platform Python scripts (`python/`) | Executable | Executable | Executable |
| Download scanner (`find_data_hog_cross_platform.py`) | Works | Works | Works |

---

## What Does NOT Work (Documented Limitations)

- **Per-app WinRT tracking** (`DataUsageTracker.ps1` per-app feature) — Windows ONLY. Linux/macOS have no equivalent to Windows SRUM database.
- **Scheduled background tracking** — Windows uses `Register-ScheduledTask`
  built into the script. On Linux/macOS it is provided by the one-line
  installers (`deploy/linux/install.sh` → systemd user timer with a
  guaranteed post-boot run via `OnBootSec`; `deploy/macos/install.sh` → launchd agent), or manually
  via `cron`/`systemd`/`launchd` (see `docs/linux_scheduling.md`).
- **Live TCP connection inspection** (`chrome_probe_cross_platform.py`) requires `psutil` — without it, process list is empty but script exits cleanly.
- **Browser download folder scanning** uses different profile paths per OS — Chrome/Firefox directories vary (`~/.config/google-chrome` vs `%LOCALAPPDATA%` vs `~/Library/Application Support`).

These limitations are documented in:
- `docs/CROSS_PLATFORM_ASSESSMENT.md`
- `releases/RELEASE_NOTES.md`
- `python/data_tracker_cross_platform.py` (inline comments)
