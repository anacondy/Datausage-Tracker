# Independent Audit Report — PR #1 on `anacondy/Datausage-Tracker`

**Auditor:** independent re-verification (fresh clone, black-box + white-box testing)
**Date:** 29 August 2026 · **Audited:** branch `arena/01a029b8-datausage-tracker` (PR #1, open, unmerged) vs `main`
**Environment:** Debian 13 sandbox, systemd 257 as PID 1, Python 3.13, Node 20 — no Windows available (see "Not testable here")

---

## 1. Executive verdict

| Question you asked | Verdict |
|---|---|
| Is the PR "truth" — does it do what it claims? | **Mostly true, honestly documented — with one outright broken deliverable (the HTML dashboard) and several overstated "optimizations".** |
| Will the counting methodology work in realistic conditions? | **Windows: yes** (SRUM/WinRT = the same source Windows Settings uses; reboot-safe delta logic proven sound by simulation). **Linux port: no, as shipped** — it overwrites its log every run, so it never accumulates usage. I built and validated a corrected version. |
| How robust is the structure & code? | **Good structure, honest docs, safe code — but "tests" are shallow (brace-counting), and two doc claims are inaccurate.** |
| Properly optimized for Arch + KDE Plasma? | **Works on Arch, but the "KDE optimization" is marketing.** `Nice=-5` is impossible for an unprivileged user service (proven); nothing in the code is KDE-specific; notifications don't exist. |
| One-line install / activate / terminate / delete / clear-data? | **Provided** — for both the PR as-is and the corrected build (`audit/ONE_LINERS.md`). |
| Low power & efficient? | **Yes — genuinely negligible**: ~50 ms CPU per 30-min run ≈ 2.4 s CPU/day, ~13 MB peak RAM, zero resident processes. |

**Merge recommendation: do not merge as-is.** Merge after: (1) replacing/fixing the Linux Python tracker (delta logic), (2) fixing the dashboard's one-line JS bug, (3) removing/downgrading the false claims (`Nice=-5`, notifications, psutil fallback). Everything else is sound.

---

## 2. Claim-by-claim truth audit (the PR's own bullet points)

| # | PR claim | My verdict | Evidence |
|---|---|---|---|
| 1 | "Unzipped DataUsageMonitor.zip; verified all 7 files intact (sha256)" | ✅ **TRUE** | I unzipped independently: exactly 7 files; hashes recomputed. Committed copies differ **only** by disclosed changes (3 comment headers + a `where powershell` guard in one `.bat`) — benign and matches the commit message. |
| 2 | "Full structural/syntax testing" | ⚠️ **TRUE but shallow** | Their `tests/test_cross_platform.py` is literally brace-balance + regex greps + hash printing. I ran it: passes. It is not functional testing, and their own docs admit PowerShell couldn't be executed. |
| 3 | "Security audit: no critical/high vulnerabilities" | ✅ **TRUE (I concur)** | Independent grep + manual review: no `Invoke-Expression`, no `DownloadString`, no outbound network calls in any tracker, no listening ports, user-level scheduled tasks only, writes confined to `%USERPROFILE%\DataUsageLogs` / `~/DataUsageLogs`. The `curl \| bash` install pattern is the main (inherent) trust consideration. |
| 4 | "Methodology verified: WinRT adapter/app tracking, reboot-safe delta logic" | ✅ **TRUE (Windows side)** | The WinRT calls (`GetAttributedNetworkUsageAsync`, `GetNetworkUsageAsync`, `NetworkUsageStates`) are real documented APIs and are the same source as Settings → Data usage → per-app view (Microsoft docs; community module explicitly cross-checks against that Settings page). The reboot-safe delta algorithm: I ported it verbatim and stress-tested 6 adversarial scenarios — **5/5 pass** (see §4). PR docs also honestly flag SRUM's ~30-day retention and the baseline-loss over-report. |
| 5 | "Cross-platform assessment: Windows-only; alternatives documented" | ✅ **TRUE & honest** | Release notes state plainly: Linux/macOS = adapter-level only; per-app (SRUM) is impossible outside Windows. Correct. |
| 6 | "UI: added responsive HTML dashboard" | ❌ **BROKEN as shipped** | `ui/index.html` contains a literal `\n` token inside a JS statement → **SyntaxError kills the entire script** → the upload button renders but does nothing. Verified with `node --check`. The same broken file ships in **all three release archives**. The accompanying `ui_preview.png` is a concept mockup (fictional "Alex R." profile, Alerts/Settings nav, VPN/Bluetooth stats) implying features that don't exist in the HTML. |
| 7 | "One-line installs (systemd service+timer, Arch/KDE optimized)" | ⚠️ **WORKS, overstated** | URLs resolve (HTTP 200), `bash -n` clean, units pass `systemd-analyze verify`. But see §5: the "optimization" flags are mostly decorative, and the scheduled Linux tracker itself is the broken part (§4.2). |
| 8 | (deploy README) "Enables desktop notifications if notify-send is available" | ❌ **FALSE** | `notify-send` is only *checked and printed about*. No notification code exists anywhere in the shipped trackers. |
| 9 | (docs) "Python script tries both /proc/net/dev and psutil fallback" | ❌ **INACCURATE** | On Linux the code reads `/proc/net/dev` only; `psutil` is used solely on non-Linux paths. (Practically irrelevant — `/proc/net/dev` always exists on Linux — but the doc claim is wrong.) |
| 10 | "Committed to session branch, not forced/merged" | ✅ **TRUE** | `main` still contains only `DataUsageMonitor.zip` + `LICENSE`; PR #1 open with the 5 commits. |

---

## 3. Repository structure & code robustness

**Layout (good):** clean separation — `*.ps1` originals, `python/` ports, `deploy/` per-OS installers, `docs/` reports, `tests/`, `ui/`, `releases/`. README is clear; PROJECT_FULL.txt accurately says "Status: NOT MERGED".

**Strengths**
- Windows `.ps1` code quality is genuinely good: proper `try/catch` guards, `-ErrorAction SilentlyContinue` on non-critical cmdlets, dedup guard (15 s), atomic-enough baseline, IST formatting with a manual UTC+5:30 fallback, graceful "no WinRT" degradation.
- Security posture is clean (verified independently — see claim #3).
- Docs are unusually candid about failure modes (SRUM retention, baseline loss over-report, driver-reload edge case) — these match my own test results.

**Weaknesses found**
1. **Linux Python tracker is not a port — it's a snapshot printer** (detail in §4.2). This is the single biggest defect.
2. Dashboard JS fatal bug (one literal `\n`), shipped everywhere including releases.
3. Test suite = structural only; no parser-level PowerShell validation, no functional tests. The "TESTING: PASS" impression is stronger than reality.
4. Two inaccurate doc claims (#8, #9 above); `RELEASE_NOTES` cites commit `93177bd` though releases were added in `06faf63` (cosmetic).
5. `releases/linux` and `releases/macos` tarballs are **byte-identical** (`sha256 b9c16ad2…` both) — "macOS build" is a relabel.
6. Windows `Save-LogPoint` writes `baseline.json` non-atomically (`Set-Content`) — a power-cut mid-write loses the baseline → one-time over-report next run (safe direction; my corrected port uses tmp-file + `os.replace`).
7. CSV columns: the first column is labeled `TimestampIST` but contains time-only strings, and `DateIST`/`TimeIST` are redundant (cosmetic).

---

## 4. Does the data-counting methodology actually work in real life?

### 4.1 Windows (`DataUsageTracker.ps1`) — YES, with known limits
- **Per-app numbers:** real. `GetAttributedNetworkUsageAsync` is the documented WinRT API for per-attribution usage; the Windows Settings "Data usage per app" view is powered by the same SRUM database. The PR's `Await`/`AsTask` bridging is the canonical PowerShell pattern for WinRT async calls.
- **Delta algorithm:** ported verbatim and stress-tested (see `audit/test_delta_methodology.py`):

| Scenario | Result |
|---|---|
| A. Steady 30-min accumulation | ✅ exact deltas, lifetime exact |
| B. Reboot (counter resets to ~0) | ✅ counts only since-boot bytes — no double-count, no loss |
| C. Hotspot off → on (adapter missing for N runs) | ✅ baseline preserved, rejoin delta exact |
| D. Driver reload to non-zero counter | ⚠️ over-reports once (documented by the PR; fail-safe direction) |
| E. `baseline.json` deleted | ⚠️ over-reports once (documented) |
| F. 64-bit counter wrap | practically impossible; logic degrades safely |

- **Realistic limits you should know** (beyond what the PR documents):
  - Per-app data vanishes after ~30 days (SRUM retention) — `-Report` for older dates is empty.
  - Per-app attributed sums **won't exactly equal** adapter totals — Microsoft's docs state some traffic lives in non-attributed/system buckets. Not a bug.
  - **VPN double-count:** adapter-level lifetime totals sum *every* interface. With a VPN active (tun0 + wlan0), the same payload is counted twice (inner + encrypted outer). Affects both platforms. If you use VPN, read per-adapter rows, not the sum.
  - First log point counts the whole since-boot counter (expected; documented).

### 4.2 Linux port (`python/data_tracker_cross_platform.py`) — NO, as shipped
Proven by execution:
- `/proc/net/dev` parsing is correct (numbers matched the kernel exactly), CPU cost trivial.
- **But it `open(...,"w")`-overwrites its CSV every run.** Two consecutive runs produced identical 3-line files — nothing accumulates. A 30-min systemd timer running this produces a log that perpetually holds one since-boot snapshot. **The scheduled daemon therefore does not measure consumption over time at all.**
- It also counts `lo` (loopback) despite a skip comment — on a KDE desktop that adds Plasma/local-proxy traffic, and with a local proxy (common setup) traffic is counted twice (lo + eth0).
- It has no baseline, no deltas, no dedup, no lifetime — none of the Windows script's (good) methodology was ported.

**Fix delivered and verified:** `audit/fix/data_tracker_fixed.py` — faithful port of the Windows delta logic (append + `baseline.json`, reboot-safe, dedup guard, loopback excluded, zoneinfo IST, identical CSV columns so the dashboard works). Live test on this box:

```
RUN 1: eth0 +2.04 MB down +1.77 MB up (lifetime 3.81 MB)   ← first run = since-boot (by design)
RUN 2 (3 s later): "Skip: … (dedup guard)."                ← guard works
kernel delta over test window: rx 1,281,328 B
RUN 3 logged:                 rx 1,320,115 B               ← ≈ kernel + background chatter ✅
CSV appends row-per-run; lifetime monotonic across reboots (reboot-safe branch unit-tested)
```

### 4.3 The HTML dashboard
- Broken as shipped (§2 #6). **Fix delivered:** `audit/fix/index.html` — one-token repair; `node --check` now passes; functional tests in Node: CSV parse ✅, adapter/app type detection ✅, byte formatting ✅, `<script>` injection in CSV cells is neutralized (`<` escaped; `>`/`&` unescaped is sloppy but harmless in text nodes).

---

## 5. Arch Linux + KDE Plasma optimization audit

| Installer claim | Reality (proven) |
|---|---|
| `Nice=-5` "optimized for Arch/KDE" | ❌ An unprivileged `systemd --user` manager **cannot** raise priority: `nice -n -5 true` → `cannot set niceness: Permission denied`; Arch forums confirm for user services; systemd ≥v257 source (`setpriority_closest`) **silently clamps to 0**, older releases fail the unit outright. Every timer activation also logs a priority error. Net effect: **no-op + log spam.** (The system manager *can* set it — I proved the permission mechanics differ by testing `systemd-run --uid=user Nice=-5` successfully — but the PR installs user units.) |
| `IOSchedulingClass=best-effort` prio 7 | ✅ valid, lowest io priority — genuinely harmless/idle-ish |
| `CPUSchedulingPolicy=idle` | ✅ SCHED_IDLE is allowed unprivileged; good choice |
| `MemoryMax=64M` | ✅ fine (measured peak RSS ≈ 12.8 MB) |
| "KDE Plasma notification support" | ❌ no notification code exists; it merely checks if `notify-send` is installed |
| Timer | ⚠️ works, but no `Persistent=true` (missed runs while powered off are skipped — Windows task uses `StartWhenAvailable`, the Linux timer doesn't match), no wake-coalescing (`AccuracySec`/`RandomizedDelaySec`) for battery friendliness |
| "Arch optimized" | It's a plain systemd **user** unit — works on *any* systemd distro; nothing KDE-specific; dead on non-systemd (Artix etc.), which matters for an "Arch" claim |

**Corrected units delivered** (`audit/fix/datausage-tracker.service`/`.timer`): `Nice=10` (real, allowed), `idle` CPU/IO scheduling, `CPUQuota=10%`, `MemoryMax=64M`, `Persistent=true`, `AccuracySec=1min` + `RandomizedDelaySec=90` (fewer wakeups), plus cheap hardening (`NoNewPrivileges`, `ProtectSystem=full`, `PrivateTmp`, `RestrictSUIDSGID`). Both pass `systemd-analyze verify`.

**Low-power verdict (measured):** one run ≈ 45–50 ms CPU, ~13 MB peak RSS, zero resident memory between runs → **≈ 2.4 s CPU per day**, ~15 min CPU/year, ~28 parts-per-million average load. This is about as low-power as a tracker can be while still logging; the design (read OS counters on demand, never poll) is the right one.

---

## 6. What I executed (test log)

| Test | Result |
|---|---|
| Fresh clone; diff PR branch vs `main` (28 files) | ✅ matches PR description |
| Independent unzip + sha256 vs committed files | ✅ 7 files; only disclosed diffs |
| `python3 tests/test_cross_platform.py` (their suite) | ✅ all PASS (structural) |
| `py_compile` all Python | ✅ |
| Ran Linux tracker twice | ❌ overwrite bug proven |
| `/proc/net/dev` vs script numbers | ✅ exact match |
| Ran `find_data_hog` / `chrome_probe` ports | ✅ run cleanly, correct empty-state behavior |
| Dashboard JS via `node --check` | ❌ SyntaxError (literal `\n`); fixed version passes; functional Node tests PASS |
| Release archives extracted + diffed vs repo | ✅ consistent (linux≡macos byte-identical; all ship broken dashboard) |
| `bash -n` + executed `deploy/linux/install.sh` logic paths | ✅ syntax OK; URLs HTTP 200; `systemctl --user` guarded |
| `systemd-analyze verify` on shipped units | ✅ no static errors |
| `nice -n -5` as unprivileged user | ❌ EPERM — proves `Nice=-5` claim void |
| systemd 257 source review (`exec-invoke.c`, `process-util.c`) | clamps silently on privilege failure (older systemd: fatal 217) |
| Live `systemd-run --uid=user Nice=-5` (system manager) | applied — confirms the user-manager limitation is the issue, not nice(1) generally |
| Delta-algorithm simulation (6 scenarios) | 5/5 pass, 2 documented over-report edges |
| **Fixed** tracker live 3-run test vs kernel counters | ✅ deltas match, dedup works, CSV appends |
| **Fixed** installer all 5 modes in sandbox | ✅ exit 0 everywhere |
| **Fixed** units `systemd-analyze verify` | ✅ |

**Not testable here (stated plainly):** live Windows 11 execution of the `.ps1` (no Windows in sandbox — Windows-side verified via code review + API documentation + algorithm simulation), and real KDE Plasma GUI interaction (headless). Everything Linux-side was executed for real.

---

## 7. Bottom line

- **Truth:** the PR's audit narrative is substantially true and its self-reported caveats check out. Two of its deliverables don't work (dashboard; Linux accumulation), and three claims are overstated (`Nice=-5`, notifications, psutil fallback).
- **Methodology:** Windows = sound and realistic (same source as Settings, reboot-safe). Linux = broken as shipped, corrected version provided and validated. VPN double-count and ~30-day per-app retention are inherent limits you should remember when reading the numbers.
- **Structure:** good and honest; tests are shallow; security is clean.
- **Arch/KDE:** runs fine as a user unit, but "KDE-optimized" is marketing; use the corrected units for real (and battery-friendlier) low-power behavior.
- **Deliverables in this workspace:** `AUDIT_REPORT.md` (this file), `audit/ONE_LINERS.md` (install/activate/stop/uninstall/purge cheat sheet), `audit/test_delta_methodology.py` (re-runnable), `audit/fix/{data_tracker_fixed.py, datausage-tracker.service, datausage-tracker.timer, install-fixed.sh, index.html}`.
