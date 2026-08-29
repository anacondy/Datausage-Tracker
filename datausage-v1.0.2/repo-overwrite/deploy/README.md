# Deploy — One-Line Downloads & Daemon Setup

This directory provides deployable install scripts for Linux, Windows, and macOS.
No manual file copying needed — one command per OS.

> **v1.0.1 revision (post-audit):** the Linux units were corrected — the v1.0.0
> `Nice=-5` was impossible for unprivileged `systemd --user` services (EPERM,
> silently clamped to 0 — see `AUDIT_REPORT.md` §5). The units now use flags a
> user service is actually allowed to set, and desktop notifications are now
> genuinely implemented instead of merely detected.

---

## Linux (Arch / KDE Plasma / any systemd distro)

```bash
# One-line download + install (bash)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/linux/install.sh | bash

# Status / uninstall
bash install.sh --status
bash install.sh --uninstall        # keeps your logs; purge with rm -rf ~/DataUsageLogs

# Or with install path override
INSTALL_DIR="$HOME/.local/share/datausage-tracker-custom" curl -fsSL ... | bash
```

What it does:
- Downloads the Python tracker (v1.0.1 — real delta/append methodology,
  reboot-safe, loopback excluded) + scanner + probe scripts
- Installs `systemd` **user** service + timer (every 30 min)
- Genuinely low-power for Arch / KDE Plasma, using only flags a user service
  may set: `Nice=10`, `CPUSchedulingPolicy=idle`, `IOSchedulingClass=idle`,
  `CPUQuota=10%`, `MemoryMax=64M`
- Timer is battery-friendly: `OnBootSec=2min` guarantees the post-boot data
  point (reboot-safe deltas count any gap in one go), and `AccuracySec=1min` +
  `RandomizedDelaySec=90` coalesce wakeups
- Real KDE Plasma **desktop notifications** via `notify-send` (threshold-based:
  512 MB per interval / 2 GB per day by default; Plasma renders them natively).
  Requires `libnotify` (`sudo pacman -S libnotify` on Arch); tracking works
  without it
- Cheap hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=full`,
  `RestrictSUIDSGID`, `LockPersonality`, `RestrictRealtime`
- Creates `dashboard.html` locally for browser viewing
- Note: on non-systemd distros (e.g. Artix) the installer prints a cron line
  instead — user units are a systemd feature, nothing here pretends otherwise

Uninstall: `bash install.sh --uninstall` (or delete `$INSTALL_DIR` and
`~/.config/systemd/user/datausage-tracker.*`), then optionally `rm -rf ~/DataUsageLogs`.

---

## Windows (PowerShell / CMD)

```powershell
# One-line PowerShell install
iwr -useb https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/windows/install.ps1 | iex
```

What it does:
- Downloads `.ps1` scripts + docs + dashboard
- Registers a Windows TaskScheduler daemon (`DataUsageTracker`) that runs every 30 minutes
- Creates `.bat` launcher for convenience
- Low CPU / battery-safe task settings (`StartWhenAvailable`,
  `ExecutionTimeLimit=3min`, `AllowStartIfOnBatteries`, `DontStopIfGoingOnBatteries`)

Uninstall: `Unregister-ScheduledTask -TaskName DataUsageTracker -Confirm:$false`; delete install folder.

---

## macOS

```bash
# One-line bash install
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/macos/install.sh | bash
```

What it does:
- Downloads Python scripts + dashboard
- Creates `launchd` agent (`com.datausage.tracker`) running every 30 minutes (`StartInterval=1800`)
- Sets low priority (`Nice=10` in plist terms — efficient background operation)

Uninstall: `launchctl unload -w ~/Library/LaunchAgents/com.datausage.tracker.plist`; delete install folder.

---

## Daemon / Offline Service Design

All three platforms run a background service/daemon:

| Platform | Daemon Type | Schedule | Resource Limit | Optimized For |
|---|---|---|---|---|
| Linux / Arch | `systemd` user service + timer | Every 30 min + 2 min after boot | `MemoryMax=64M`, `CPUQuota=10%`, `Nice=10` + idle CPU/IO scheduling | KDE Plasma / Arch (yield-to-desktop, wakeup coalescing) |
| Windows | `TaskScheduler` (user-level) | Every 30 min + logon | `ExecutionTimeLimit=3min` | Low battery / low CPU |
| macOS | `launchd` agent | Every 30 min (StartInterval=1800) | Nice=10 | Background efficiency |

The daemon only reads adapter counters (read-only OS APIs) — it never writes to
protected directories, never opens network ports, and never requires admin
rights for installation (Linux user-level systemd, macOS user `launchd`, Windows
user-level TaskScheduler). On Linux, optional `loginctl enable-linger` (needs
root once) keeps the timer running while logged out.

---

## Release Download Links (Direct)

These are the packaged releases (not the deploy scripts above):

- **Windows**: `releases/windows/DataUsageTracker-v1.0.2-windows.zip`
- **Linux**: `releases/linux/DataUsageTracker-v1.0.2-linux.tar.gz`
- **macOS**: `releases/macos/DataUsageTracker-v1.0.2-macos.tar.gz`

(v1.0.1 archives remain for reference but are superseded; v1.0.0 was removed
after the independent audit found it shipped a broken dashboard and a
non-accumulating Linux tracker — see `releases/RELEASE_NOTES.md`.)

For GitHub Releases, use the self-contained one-line installers in
`datausage-v1.0.2/release-assets/` (verified by `SHA256SUMS.txt`).

But for deployable installation (recommended), use the one-line commands above.
