# Release Notes — DataUsageTracker

## v1.0.2 — release-ready hardening (final sweep)

Three residual issues found in an independent re-sweep of v1.0.1, all fixed:

1. **Notification delivery was trusted, not verified** — `_notify_send` returned
   `True` after the first *existing* binary ran, even if it exited non-zero
   (e.g. `--app-name` on libnotify < 0.8). A silently-failed toast also recorded
   its rate-limit state, swallowing the alert. Now: notify-send with app-name →
   notify-send plain → kdialog, and only an exit-0 counts as delivered
   (+ 2 new tests: 28 total).
2. **`Persistent=true` removed from the timer** — systemd only honors it on
   `OnCalendar=` timers; it was a no-op here. Post-boot coverage comes from
   `OnBootSec=2min`, and the reboot-safe delta logic counts the whole gap at
   the first run after boot anyway.
3. **Windows installer fails loudly now** — a failed download used to be
   swallowed (`-ErrorAction SilentlyContinue`) and could register a scheduled
   task pointing at a missing script. It now throws before task registration.
   Also added `systemctl --user import-environment` for notifications on X11
   sessions.
4. **Privacy scrub (public-release requirement)** — personal machine details
   (hostname, hotspot name, per-app figures, process names from a private
   machine) removed from `README.md` and `ChromeDataProbe.ps1`; replaced with
   generic guidance. Source archives rebuilt from scrubbed sources (identical
   manifests) and `SHA256SUMS.txt` regenerated. All tracking is local-only:
   nothing is ever uploaded or published.

**Self-contained installers** (this release): `install-linux.sh`,
`install-windows.ps1`, `install-macos.sh` embed the full code — download once,
install anywhere, no further network access needed.

Archives: `releases/{linux,macos,windows}/DataUsageTracker-v1.0.2-*` (v1.0.1
kept for reference, superseded).

---

Branch: `arena/01a04ccb-datausage-tracker`  
PR: https://github.com/anacondy/Datausage-Tracker/pull/1

---

## v1.0.1 — current (post-audit fixes, 29 August 2026)

Built after the independent audit (`AUDIT_REPORT.md`). See `FIXES_APPLIED.md`
for the finding-by-finding mapping. Highlights:

- **Linux/macOS tracker rewritten** as a faithful port of the Windows delta
  methodology: CSV **append** (v1.0.0 overwrote its log every run, so nothing
  ever accumulated), `baseline.json` + lifetime totals, reboot-safe deltas,
  15-second dedup guard, loopback excluded, atomic state writes.
- **Dashboard fixed** — v1.0.0 shipped a literal `\n` token that caused a JS
  SyntaxError and killed the upload button. Now parses (`node --check`) and
  HTML-escapes all rendered values.
- **Arch/KDE units corrected** — v1.0.0's `Nice=-5` was impossible for an
  unprivileged user service. v1.0.1 uses `Nice=10` + idle CPU/IO scheduling +
  `CPUQuota=10%`, plus `Persistent=true` and wakeup coalescing on the timer,
  and cheap hardening. Verified with `systemd-analyze verify`.
- **Real KDE Plasma notifications** — threshold-based (512 MB/interval,
  2 GB/day defaults) via `notify-send` (`kdialog` fallback), not just a
  "notify-send found" message.
- **Windows hardening** — baseline/last-run state written atomically (tmp +
  rename); absent-adapter baselines preserved so rejoins don't over-report.
- **New functional test suite** — `tests/test_delta_methodology.py` (26 checks)
  executes the counting logic instead of only counting braces.

### Windows (`releases/windows/DataUsageTracker-v1.0.1-windows.zip`)
**Status: STABLE — full functionality**

PowerShell scripts (WinRT per-app + adapter tracking, atomic state writes),
`.bat` launchers, docs, structural + functional tests, fixed HTML dashboard.
Requirements: Windows 11 (PowerShell 5.1+ or 7+).

### Linux (`releases/linux/DataUsageTracker-v1.0.1-linux.tar.gz`)
**Status: STABLE — adapter-level tracking with full delta methodology**

Python 3 tracker (stdlib only on Linux — reads `/proc/net/dev` directly;
`psutil` used only on the unusual no-`/proc` case), download scanner, browser
probe, fixed dashboard, corrected systemd installer (`deploy/linux/install.sh`),
scheduling + failure-mode docs.
Requirements: Python 3.9+ (Arch is always fine), systemd for the timer.
Per-app (WinRT SRUM) tracking is **not available** on Linux — an OS
limitation, not a script limitation.

### macOS (`releases/macos/DataUsageTracker-v1.0.1-macos.tar.gz`)
**Status: STABLE — adapter-level tracking with full delta methodology**

Same Python payload as Linux plus the `launchd` installer
(`deploy/macos/install.sh`). Per-interface stats use `psutil`
(`pip install psutil`) since macOS has no `/proc`.

> Honesty note: the Linux and macOS payloads share the same cross-platform
> Python scripts by design. v1.0.0 shipped them byte-identical with only a
> relabel; v1.0.1 tarballs include each platform's own installer and are
> labeled accordingly.

---

## v1.0.0 — SUPERSEDED, archives removed

The v1.0.0 archives were **removed from this repository** because the audit
proved they shipped: (1) a broken HTML dashboard (JS SyntaxError — upload
button did nothing), and (2) a Linux tracker that overwrote its CSV every
run and therefore never accumulated usage. The historical record of what
v1.0.0 claimed is in the audit report; do not redistribute v1.0.0 builds.

---

## What Works vs What Doesn't (Cross-Platform Truth)

| Feature | Windows | Linux | macOS |
|---|---|---|---|
| Adapter byte tracking | Full (WinRT + `Get-NetAdapterStatistics`) | Full (`/proc/net/dev`, deltas + lifetime) | Full (`psutil`, deltas + lifetime) |
| Reboot-safe accumulation | Full | Full (v1.0.1) | Full (v1.0.1) |
| Per-app usage | Full (WinRT `GetAttributedNetworkUsageAsync`) | Not possible (no SRUM equivalent) | Not possible |
| Download scanning (`FindDataHog`) | Full | Partial (Linux profile paths) | Partial (macOS profile paths) |
| Browser process probe (`ChromeDataProbe`) | Full | Limited (needs `psutil`) | Limited (needs `psutil`) |
| Scheduled background tracking | Task Scheduler (built-in `-Schedule`) | systemd user timer (`deploy/linux/install.sh`) | launchd agent (`deploy/macos/install.sh`) |
| Desktop notifications | — | Real, threshold-based (`notify-send` / KDE Plasma) | — |
| HTML dashboard (`ui/index.html`) | Full | Full | Full |

---

## How to Use Each Release

### Windows
```batch
:: Extract zip, then double-click:
Run-DataUsageTracker.bat
Run-FindDataHog.bat
Run-ChromeDataProbe.bat
```

### Linux (Arch / KDE Plasma)
```bash
# Recommended: one-line installer (sets up the corrected timer)
bash deploy/linux/install.sh
# or manually:
python3 python/data_tracker_cross_platform.py            # log one data point
python3 python/data_tracker_cross_platform.py --snapshot # print-only
# Dashboard: open ui/index.html and drop in ~/DataUsageLogs/DataUsage_Log.csv
```

### macOS
```bash
bash deploy/macos/install.sh
python3 python/data_tracker_cross_platform.py
```

---

## Dependencies

| Platform | Required | Optional |
|---|---|---|
| Windows | Windows 11, PowerShell | None |
| Linux | Python 3.9+ | `libnotify` for KDE Plasma notifications; `psutil` only if `/proc/net/dev` is unavailable |
| macOS | Python 3.9+ | `psutil` (`pip install psutil`) for adapter statistics |

---

## Limitations Acknowledged

1. **Per-app usage is Windows-only** — Windows' SRUM database has no
   Linux/macOS equivalent; the Python ports provide adapter-level tracking.
2. **VPN double-count (all platforms)** — adapter totals sum every interface;
   with a VPN active the same payload appears on both the tunnel and the
   physical interface. Read per-adapter rows, not the sum.
3. **Windows per-app data expires after ~30 days** (SRUM retention) and some
   traffic lives in non-attributed buckets, so per-app sums may not equal
   adapter totals.
4. **First log point after a fresh install counts the whole since-boot
   counter** — by design, documented in the tracker output.

---

*No forced merge. All releases packaged from the `arena/01a04ccb-datausage-tracker` branch. PR remains open for continued work.*
