# Deploy — One-Line Downloads & Daemon Setup

This directory provides deployable install scripts for Linux, Windows, and macOS.
No manual file copying needed — one command per OS.

---

## Linux (Arch / KDE Plasma / any systemd distro)

```bash
# One-line download + install (bash)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a029b8-datausage-tracker/deploy/linux/install.sh | bash

# Or with install path override
INSTALL_DIR="$HOME/.local/share/datausage-tracker-custom" curl -fsSL ... | bash
```

What it does:
- Downloads Python adapter/download/probe scripts
- Installs `systemd` user service + timer (every 30 min)
- Optimized for Arch Linux / KDE Plasma (`Nice=-5`, `IOSchedulingClass=best-effort`, `MemoryMax=64M`)
- Enables desktop notifications if `notify-send` is available
- Creates `dashboard.html` locally for browser viewing

Uninstall: delete `$INSTALL_DIR` and `~/.config/systemd/user/datausage-tracker.*`

---

## Windows (PowerShell / CMD)

```powershell
# One-line PowerShell install
iwr -useb https://github.com/anacondy/Datausage-Tracker/raw/arena/01a029b8-datausage-tracker/deploy/windows/install.ps1 | iex
```

What it does:
- Downloads `.ps1` scripts + docs + dashboard
- Registers a Windows TaskScheduler daemon (`DataUsageTracker`) that runs every 30 minutes
- Creates `.bat` launcher for convenience
- Optimized for low CPU (`ExecutionTimeLimit=3min`, `Nice=-5` equivalent via settings)

Uninstall: `Unregister-ScheduledTask -TaskName DataUsageTracker -Confirm:$false`; delete install folder.

---

## macOS

```bash
# One-line bash install
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a029b8-datausage-tracker/deploy/macos/install.sh | bash
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
| Linux / Arch | `systemd` user service + timer | Every 30 min | MemoryMax=64M, Nice=-5 | KDE Plasma / Arch |
| Windows | `TaskScheduler` (user-level) | Every 30 min + logon | ExecutionTimeLimit=3min | Low battery / low CPU |
| macOS | `launchd` agent | Every 30 min (StartInterval=1800) | Nice=10, idle scheduling | Background efficiency |

The daemon only reads adapter counters (read-only OS APIs) — it never writes to protected directories, never opens network ports, and never requires admin rights for installation (Linux user-level systemd, macOS user `launchd`, Windows user-level TaskScheduler).

---

## Release Download Links (Direct)

These are the packaged releases (not the deploy scripts above):

- **Windows**: `releases/windows/DataUsageTracker-v1.0.0-windows.zip`
- **Linux**: `releases/linux/DataUsageTracker-v1.0.0-linux.tar.gz`
- **macOS**: `releases/macos/DataUsageTracker-v1.0.0-macos.tar.gz`

But for deployable installation (recommended), use the one-line commands above.
