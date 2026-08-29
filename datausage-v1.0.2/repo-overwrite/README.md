# Windows Data Usage Monitor + Data Hog Finder

Three PowerShell tools for your HP laptop (`onlysuccessair1`, Windows 11 Home):

1. **`DataUsageTracker.ps1`** – detects your **overall data usage** (hotspot Wi-Fi,
   USB-tethering/Ethernet, cable Ethernet — every adapter), tells you **which app**
   used the most, and logs it over time. **Low power** and **immune to network
   switches / reboots** (see below).
2. **`FindDataHog.ps1`** – hunts files that were **downloaded recently / are still
   downloading** (browsers + Downloads folder first) to explain a data spike.
3. **`ChromeDataProbe.ps1`** – finds **WHERE inside Chrome** your data went (open
   tabs, per-process memory, live connections, hidden background downloaders).

All times are **Indian Standard Time (IST)**, 12-hour clock (`03:42:15 PM`) and
**long ordinal date** (`4th August 2026`).

> These are Windows PowerShell (`.ps1`) scripts. Save the whole `DataUsageMonitor`
> folder onto your PC and run them in **PowerShell** (Start → "PowerShell").
> No installation, no internet, no admin rights needed for most features.

---

## Script 1 — `DataUsageTracker.ps1`

### Run it
```powershell
.\DataUsageTracker.ps1 -Snapshot                  # usage now / last 30 days
.\DataUsageTracker.ps1 -Report -From "1 July 2026" -To "6 August 2026"
.\DataUsageTracker.ps1 -Schedule                  # background low-power tracker
.\DataUsageTracker.ps1 -Unschedule                # remove the background tracker
.\DataUsageTracker.ps1 -Log                       # append one data point now
.\DataUsageTracker.ps1 -Live -Seconds 10          # quick live speed meter
```

### Why it's low power
It does **not** poll every second. Windows 11 already counts per-app and per-adapter
data continuously in the background with almost no overhead. This script just **reads**
those numbers on demand via Windows' own WinRT API — a fraction of a second. For
long-term tracking it runs once every 30 min via Task Scheduler.

### IMPORTANT: it never resets or double-counts
Your concern was: *does it break when I turn off the hotspot or unplug ethernet?*
**No.** Here's how it guarantees correctness across every scenario:

| Situation | What happens |
|-----------|--------------|
| **Turn hotspot off / on** (Wi-Fi drops then returns) | The adapter keeps its own counters and its own row. Delta = current − previous keeps accumulating. Nothing lost, nothing doubled. |
| **Switch between Wi-Fi hotspot and ethernet** | Each adapter gets its OWN baseline + its own row. The two are never mixed, so totals can't be duplicated across interfaces. |
| **Unplug ethernet mid-session** | Adapter disappears → its row is simply not updated that run. When it returns, it resumes from its stored baseline. |
| **PC reboot** (adapter counters reset to 0) | Detected (current < previous) and handled: the whole post-boot value is counted as new, so nothing since boot is lost AND nothing is double-counted. |
| **Scheduled run missed / PC was off** | The next run queries the full gap since the last recorded time, so the whole interval is still captured exactly once. |
| **Two runs fire at once** (manual + scheduled) | A 15-second dedup guard skips the duplicate write. |

A **lifetime cumulative total** is stored for every adapter and survives reboots — so
your all-time total never resets, unlike Windows' own counters.

### Output files (`%USERPROFILE%\DataUsageLogs\`)
| File | Contents |
|------|----------|
| `DataUsage_Log.csv`    | per-run adapter deltas + lifetime totals (IST) |
| `DataUsage_Apps.csv`   | per-app usage per interval (IST) |
| `DataUsage_Report.csv` | full per-app report |
| `baseline.json` / `last_run.json` | internal state (baselines + dedup guard) |

---

## Script 2 — `FindDataHog.ps1`  (what downloaded on your PC?)

```powershell
.\FindDataHog.ps1                 # fast scan: browsers + Downloads, last 30 days, >=5MB
.\FindDataHog.ps1 -Days 7         # last 7 days
.\FindDataHog.ps1 -MinSizeMB 1 -Top 60
.\FindDataHog.ps1 -Watch          # detect a download STILL IN PROGRESS (10s)
.\FindDataHog.ps1 -FullScan       # slower full profile scan
```
Checks: **browsers first** (Chrome/Edge/Brave/Opera/Vivaldi/Firefox download
folders), then Downloads/Desktop/Documents/etc., lists recent files by size, flags
partial/in-progress files (`.crdownload`, `.part`, `.tmp`), and lists processes with
live internet connections.

---

## Script 3 — `ChromeDataProbe.ps1`  (why did CHROME use 2 GB?)

Windows shows a big "chrome.exe" total but not *which tab*. This probe inspects the
live Chrome processes:
```powershell
.\ChromeDataProbe.ps1                       # full probe
.\ChromeDataProbe.ps1 -Tabs                 # open tab titles
.\ChromeDataProbe.ps1 -Connections          # active connections (remote hosts)
.\ChromeDataProbe.ps1 -RefreshSeconds 5     # live monitor
```
It reports: process memory map, **open tab titles**, active internet connections with
resolved hostnames, known silent data consumers, and **other hidden downloaders**
(torrents, updaters, cloud sync — it caught a `gbittorrent.exe` in your screenshots!).

---

## 🔍 Diagnosing YOUR 2 GB chrome spike (from your screenshots)

What your own screenshots showed:
- Network = **phone hotspot "realme 6i"** (2.4 GHz, 72 Mbps, Open).
- **Last 24 h on that hotspot = 2.02 GB.** Last 30 days = 3.45 GB.
- Per-app (30 days): **chrome.exe 2.07 GB**, msedge 837 MB, System/Windows Update 367 MB.
- **In the "last 24 hours" per-app list chrome is NOT shown** — that's the known
  Windows per-app **undercount/lag bug**, not proof chrome didn't use it.
- Task Manager shows **Chrome (10 processes, ~985 MB)** and **a Bittorrent client
  (`gbittorrent.exe`)** both running.

**The most likely cause of "2 GB with no visible download":** a background tab or
Chrome background feature silently streaming/syncing. In order of likelihood:
1. **A tab left open playing audio/video** (YouTube, a music player, etc.) — streams
   for hours, no file download appears. **Press Shift+Esc inside Chrome** → Chrome's
   own Task Manager → sort by **Network** → the guilty tab shows huge bytes. Close it.
2. **Chrome "background apps"** (Gmail, Drive, WhatsApp Web, etc.) continue after you
   close the browser → `chrome://settings/system` → turn OFF "Continue running
   background apps".
3. **Extensions** doing background work → `chrome://extensions` → disable unneeded.
4. **Pre-fetch / preload** of pages you never opened → `chrome://settings/privacy`.
5. **Chrome sync / backup** pushing data.
6. **The Bittorrent client** (`gbittorrent.exe`) seeding/downloading in the background
   — check/close it (it's a classic silent data hog).

**Biggest single fix for your mobile data:** your hotspot is currently treated as an
**unmetered** connection, so Windows + background apps download freely. Set the
hotspot to **Metered**:
`Settings → Network & internet → Wi-Fi → (realme 6i) → Metered connection → ON`.
That stops Windows Update, Store and many background apps from eating your SIM data.

> **One caveat about SIM vs PC:** the 2–3 GB was charged to your SIM only if the
> internet path went **through the phone** (hotspot/USB tethering). If the PC was on
> cable broadband instead, the spike came from the **phone itself** — check the
> phone's own Mobile-data-usage screen to see which app (YouTube, Photos backup,
> Play Store, Chrome) used it.

---

## Linux (Arch + KDE Plasma) and macOS

The `python/` directory contains cross-platform ports. As of **v1.0.1**
(post-audit, see `AUDIT_REPORT.md` and `FIXES_APPLIED.md`), the Linux tracker
is a faithful port of the Windows delta methodology — it **accumulates** usage
(CSV append + `baseline.json`), is reboot-safe, has the same 15-second dedup
guard, excludes loopback traffic, and writes the **same CSV columns** as
Windows, so the same `ui/index.html` dashboard works for both.

One-line install for Arch / KDE Plasma (systemd user service + timer, no root):

```bash
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/linux/install.sh | bash
```

- Runs every 30 min with genuinely low-power flags a user service may actually
  set (`Nice=10`, idle CPU/IO scheduling, `CPUQuota=10%`, `MemoryMax=64M`).
- Timer is battery-friendly (`AccuracySec=1min`, `RandomizedDelaySec=90`); a
  guaranteed post-boot run (`OnBootSec=2min`) captures everything that happened
  while powered off, via the reboot-safe delta logic.
- Real KDE Plasma **desktop notifications** via `notify-send` when usage
  crosses a threshold (512 MB/interval, 2 GB/day defaults). On Arch:
  `sudo pacman -S libnotify`.
- Status / uninstall: `bash install.sh --status` / `bash install.sh --uninstall`
  (see `audit/ONE_LINERS.md` for the full cheat sheet).

Per-app (WinRT SRUM) tracking stays Windows-only — that's an OS limitation,
documented in `docs/CROSS_PLATFORM_ASSESSMENT.md`.

---

## Verifying correctness of the tracker
Each `-Log` writes exactly one non-overlapping interval. You can cross-check totals:
- Compare `DataUsage_Log.csv` `Lifetime_Total` (never resets) with
  Windows `Settings → Network → Data usage`.
- The sum of per-app (`DataUsage_Apps.csv`) should roughly equal the adapter delta;
  minor gaps are normal because Windows' per-app counter can lag/undercount browsers.
