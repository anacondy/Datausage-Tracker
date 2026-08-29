# Fixes Applied — response to AUDIT_REPORT.md

Date: 29 August 2026 · Branch: `arena/01a04ccb-datausage-tracker`

Every blocking finding and overstated claim in the independent audit
(`AUDIT_REPORT.md`) is addressed below. All fixes are verified by the new
functional test suite `tests/test_delta_methodology.py` (26 checks, all pass)
and, where possible, executed live.

| # | Audit finding | Fix | Where |
|---|---|---|---|
| 1 | **Linux tracker was a snapshot printer** — `open(...,"w")` overwrote the CSV every run; no baseline/deltas/dedup/lifetime (§4.2) | Rewritten as a faithful port of the Windows `Save-LogPoint` methodology: CSV **append**, `baseline.json` with per-adapter counters + lifetime totals, **reboot-safe** deltas, **15 s dedup guard**, first run = since-boot by design. Verified live: run N+1 deltas match kernel counters. | `python/data_tracker_cross_platform.py` |
| 2 | **Loopback counted** despite skip comment → Plasma/local-proxy traffic double-counted (§4.2) | `lo` excluded by default (opt back in with `DATAUSAGE_INCLUDE_LOOPBACK=1`); macOS path skips `lo0`. | `python/data_tracker_cross_platform.py` |
| 3 | **Dashboard JS fatal bug** — literal `\n` token → SyntaxError killed the upload button (§2 #6) | Token removed; `node --check` passes. While there: full HTML escaping (`&`, `<`, `>`, quotes) for headers/cells/attributes, duplicated `detectKind` condition cleaned. | `ui/index.html` |
| 4 | **`Nice=-5` is impossible** for an unprivileged `systemd --user` service — silently clamped + log spam (§5) | Replaced with flags a user service **may** set: `Nice=10`, `CPUSchedulingPolicy=idle`, `IOSchedulingClass=idle`, `CPUQuota=10%`, `MemoryMax=64M`. Both units pass `systemd-analyze verify`. | `deploy/linux/install.sh`, `docs/linux_scheduling.md` |
| 5 | **Timer missed runs while powered off**; no wake-coalescing (§5) | `Persistent=true` (parity with Windows `StartWhenAvailable`) + `AccuracySec=1min` + `RandomizedDelaySec=90` (battery-friendly wakeup coalescing). | `deploy/linux/install.sh` |
| 6 | **"KDE Plasma notification support" was false** — `notify-send` was only detected, never used (§2 #8) | Real threshold-based freedesktop notifications implemented in the tracker (`notify-send`, `kdialog` fallback — both rendered natively by Plasma): ≥512 MB per interval (max 1/hour) or ≥2 GB per day (once/day, critical urgency), enabled via `DATAUSAGE_NOTIFY=1` which the service now sets. Never blocks or crashes logging. Doc claims corrected. | `python/data_tracker_cross_platform.py`, `deploy/linux/install.sh`, `deploy/README.md`, `docs/TESTING_FAILURE_MODES.md` |
| 7 | **"psutil fallback" doc claim inaccurate** (§2 #9) | Docs corrected: Linux reads `/proc/net/dev` directly (always present); psutil is consulted only in the unusual no-`/proc` case and on non-Linux platforms — which the v1.0.1 code now actually does. | `docs/TESTING_FAILURE_MODES.md`, `python/data_tracker_cross_platform.py` |
| 8 | **Non-atomic baseline writes** (Windows `Set-Content`; power-cut could lose baseline → one-time over-report) (§3 #6) | Windows: tmp file + `Move-Item` rename. Linux port: tmp file + `fsync` + `os.replace`. | `DataUsageTracker.ps1`, `python/data_tracker_cross_platform.py` |
| 9 | **NEW defect found while porting** (beyond the audit): baselines of *absent* adapters were dropped after one missed run, so a rejoining adapter over-reported its entire counter — contradicting the README's "resumes from stored baseline" promise | Baselines of absent adapters are now preserved on both platforms; covered by test `test_adapter_disappear_rejoin`. | `python/data_tracker_cross_platform.py`, `DataUsageTracker.ps1`, `tests/test_delta_methodology.py` |
| 10 | **Tests were structural only** (brace-counting) (§3 #3) | New functional suite executes the counting logic against synthetic `/proc/net/dev`: exact deltas, reboot reset, adapter disappear/rejoin, dedup guard, loopback exclusion, append behavior, atomic state files, Windows-identical CSV columns, IST offset, dashboard JS syntax + escaping. **26/26 pass.** | `tests/test_delta_methodology.py` |
| 11 | **Release archives shipped the broken dashboard & broken Linux tracker; linux ≡ macos byte-identical relabel; wrong commit cited** (§3 #4, #5) | v1.0.0 archives **removed**; v1.0.1 rebuilt from fixed sources with platform-specific payloads (linux tarball includes the fixed units/installer, macos tarball the launchd installer). Release notes rewritten and honest about what v1.0.0 got wrong. | `releases/` |
| 12 | **IST conversion in the old Python port was fake** (printed UTC labelled "IST (approx)") | Real IST via `zoneinfo` (`Asia/Kolkata`) with a guaranteed UTC+5:30 fixed-offset fallback. Timestamps match the Windows format (ordinal date + 12-hour time). | `python/data_tracker_cross_platform.py` |
| 13 | Install one-liners pointed at the pre-fix branch | All deploy scripts + docs now point at `arena/01a04ccb-datausage-tracker`; Linux installer gained `--status` / `--uninstall` modes, Arch/KDE detection, `libnotify` (`pacman`) hints, and a `loginctl enable-linger` tip. | `deploy/*` |

## Deliberately NOT changed (audit found them sound)

- Windows WinRT per-app methodology, delta algorithm core, security posture
  (no `Invoke-Expression`, no network calls, user-level only) — §2 #1–5, §3.
- CSV column layout of `DataUsage_Log.csv` (kept identical so one dashboard
  serves Windows + Linux logs) — the cosmetic `TimestampIST`/`DateIST`
  redundancy was left as-is for backwards compatibility.
- Known inherent limits are still documented, not hidden: SRUM ~30-day
  per-app retention, per-app sums ≠ adapter totals, VPN double-count,
  first run = since-boot.

## Verification summary

- `python3 -m py_compile python/*.py tests/*.py` — clean
- `python3 tests/test_delta_methodology.py` — 26/26 PASS
- `python3 tests/test_cross_platform.py` — structural PASS
- Live 3-run test vs `/proc/net/dev` — deltas match kernel, dedup guard fires
- `bash -n deploy/linux/install.sh` — clean
- `systemd-analyze verify` on both units — clean (exit 0)
- `node --check` on dashboard JS — clean
