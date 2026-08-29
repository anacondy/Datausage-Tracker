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
4. **Privacy scrub (public-release requirement)** — all personal machine
   details (hostnames, hotspot names, per-app figures from a private machine,
   process names) were removed from `README.md` and `ChromeDataProbe.ps1` and
   replaced with generic guidance. The source archives were rebuilt from the
   scrubbed sources (same manifests) and `SHA256SUMS.txt` regenerated — this is
   the documented reason the supplied archives were rebuilt. Everything is
   computed locally on the user's own machine; nothing is ever uploaded.

**Self-contained installers** (this release): `install-linux.sh`,
`install-windows.ps1`, `install-macos.sh` embed the full code — download once,
install anywhere, no further network access needed.

**One-line installs (stable URLs — this release):**

```bash
# Linux / Arch / KDE Plasma
curl -fsSL https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-linux.sh | bash
# macOS
curl -fsSL https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-macos.sh | bash
```
```powershell
# Windows
iwr -useb https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-windows.ps1 | iex
```

Each installer supports the full lifecycle: `status` / `stop` / `uninstall` /
`purge-data` (see `docs/ONE_LINERS.md` in the repo for manual equivalents).
Verify downloads with `SHA256SUMS.txt` included in this release.

---

# Release Notes — DataUsageTracker

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

## What's inside

| Asset | Use |
|---|---|
| `install-linux.sh` | One-line self-contained installer (Linux/Arch/KDE) |
| `install-windows.ps1` | One-line self-contained installer (Windows 10/11) |
| `install-macos.sh` | One-line self-contained installer (macOS) |
| `DataUsageTracker-v1.0.2-*.tar.gz / .zip` | Full source+docs archives per platform |
| `SHA256SUMS.txt` | Verify your download: `sha256sum -c SHA256SUMS.txt` |

## Verification performed before this release

- 28/28 functional tests (deltas, reboot reset, adapter rejoin, dedup, loopback, atomicity, dashboard JS, notification honesty)
- Live kernel-calibration: logged deltas match `/proc/net/dev` ground truth
- `systemd-analyze verify` on both user units (exit 0)
- `bash -n` / `py_compile` / `node --check` all clean
- Self-contained installers: payload decode byte-identical; full install → status → stop → uninstall → purge lifecycle executed

## Honest limits (unchanged)

- Per-app tracking (the Windows "Data usage per app" numbers) is Windows-only — OS limitation
- VPN traffic is counted on both the tunnel and physical adapter (read per-adapter rows)
- SRUM keeps Windows per-app history ~30 days
- First run logs "since boot" values by design
