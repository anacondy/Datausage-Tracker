# Windows Data Usage Monitor + Data Hog Finder

Three tools that show **how much data** your machine uses, **which app** used
the most, and **what** is silently downloading it. The originals are Windows
PowerShell; cross-platform (Linux / macOS) companions and background daemons
are included (see [Linux / macOS section](#linux-arch--kde-plasma-and-macos)):

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
The question every user asks: *does it break when I turn off the hotspot or
unplug ethernet?* **No.** Here's how it guarantees correctness across every
scenario:

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
(torrents, updaters, cloud sync — the classic silent data hogs).

---

## 🔍 Diagnosing silent data spikes ("2 GB gone, nothing visible downloaded")

The usual cause of a big spike with no visible download is a background tab or
browser background feature silently streaming/syncing. In order of likelihood:
1. **A tab left open playing audio/video** (YouTube, a music player, etc.) — streams
   for hours, no file download appears. **Press Shift+Esc inside Chrome** → Chrome's
   own Task Manager → sort by **Network** → the guilty tab shows huge bytes. Close it.
2. **Browser "background apps"** continue after you close the browser →
   `chrome://settings/system` → turn OFF "Continue running background apps".
3. **Extensions** doing background work → `chrome://extensions` → disable unneeded ones.
4. **Pre-fetch / preload** of pages you never opened → `chrome://settings/privacy`.
5. **Browser sync / cloud backup** pushing data in the background.
6. **A torrent client** seeding/downloading in the background — check or close it
   (a classic silent data hog; seeding counts as upload).

**Biggest single fix on mobile data:** if you use a phone hotspot, Windows treats
new networks as **unmetered** by default, so Windows Update, Store and many
background apps download freely. Set the connection to **Metered**:
`Settings → Network & internet → Wi-Fi → (your hotspot) → Metered connection → ON`.
That stops most background consumption of your SIM data.

> **Privacy by design:** this project never uploads, stores or publishes *your*
> numbers anywhere — everything is computed locally and written only to
> `%USERPROFILE%\DataUsageLogs` / `~/DataUsageLogs` on **your own machine**.
> The examples in this README are generic; nothing here comes from any user's
> real machine.

> **One caveat about SIM vs PC:** data is charged to your SIM only if the internet
> path went **through the phone** (hotspot/USB tethering). If the PC was on another
> connection instead, the spike came from the **phone itself** — check the phone's
> own mobile-data-usage screen to see which app used it.

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
