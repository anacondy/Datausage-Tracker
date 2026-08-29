# One-Line Command Sheet — DataUsageTracker

Every lifecycle action as a copy-pasteable one-liner, for all three platforms.
All Linux/macOS commands run as your **normal user — no sudo** (the only
optional sudo anywhere is `loginctl enable-linger` and, on Arch, installing
`libnotify`).

**Two URL flavors:**

| Flavor | Base URL | When to use |
|---|---|---|
| **Stable** | `https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2` | Survives branch deletion; the right one for public docs. Live once the 8 release assets are published on the v1.0.2 release page. |
| **Dev** | `https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker` | Always tracks the current branch (what CI/PR reviewers run). |

Verify anything you download first (recommended habit for any `curl|bash`):
```bash
curl -fsSLO <stable>/SHA256SUMS.txt && curl -fsSLO <stable>/install-linux.sh && sha256sum -c SHA256SUMS.txt
```

---

## Linux — Arch / KDE Plasma (systemd **user** daemon)

```bash
# 1) DOWNLOAD + INSTALL (stable)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-linux.sh | bash
#    (dev flavor: .../raw/arena/01a04ccb-datausage-tracker/datausage-v1.0.2/release-assets/install-linux.sh)

# 2) ACTIVATE / CHECK IT'S RUNNING
bash install-linux.sh status                 # or, after download: any of —
systemctl --user status datausage-tracker.timer
systemctl --user list-timers datausage-tracker.timer
journalctl --user -u datausage-tracker -f    # live log
python3 ~/.local/share/datausage-tracker/data_tracker.py     # run one point NOW

# 3) TERMINATE (stop scheduling; keeps program + data)
bash install-linux.sh stop                   # or: systemctl --user disable --now datausage-tracker.timer

# 4) DELETE THE PROGRAM (files + units; KEEPS your logs)
bash install-linux.sh uninstall

# 5) CLEAR ITS DATA
bash install-linux.sh purge-data             # or: rm -rf ~/DataUsageLogs
#    delete everything in one line:
bash install-linux.sh uninstall && bash install-linux.sh purge-data
```

Manual equivalents (no script):
```bash
systemctl --user disable --now datausage-tracker.timer      # terminate
rm -rf ~/.local/share/datausage-tracker ~/.config/systemd/user/datausage-tracker.{service,timer}; systemctl --user daemon-reload   # delete program
rm -rf ~/DataUsageLogs                                      # clear data
```

KDE Plasma / Arch notes:
- Notifications render natively in Plasma via `notify-send`; on Arch: `sudo pacman -S libnotify`.
- Track before login / after logout too (optional, needs root once): `sudo loginctl enable-linger $USER`.
- Non-systemd distro? The installer prints a ready-made `cron` line instead.
- Cost: ≈ **2.4 s CPU/day** (48 runs × ~50 ms), ~13 MB peak RSS for half a second per run, **zero resident memory** between runs.
- The tracker reads only `/proc/net/dev` and writes only to `~/DataUsageLogs/`. No ports, no telemetry, no uploads.

---

## Windows (PowerShell / CMD)

```powershell
# 1) INSTALL (stable)
iwr -useb https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-windows.ps1 | iex
#    (dev flavor: .../raw/arena/01a04ccb-datausage-tracker/deploy/windows/install.ps1)

# 2) STATUS / run now
<install>\install-windows.ps1 -Status        # or: .\DataUsageTracker.ps1 -Log

# 3) TERMINATE + 4) DELETE (task + files; keeps logs)
<install>\install-windows.ps1 -Uninstall
#    manual: Unregister-ScheduledTask -TaskName DataUsageTracker -Confirm:$false

# 5) CLEAR DATA
Remove-Item -Recurse -Force "$env:USERPROFILE\DataUsageLogs"
```

## macOS

```bash
# 1) INSTALL (stable)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-macos.sh | bash
#    (dev flavor: .../raw/arena/01a04ccb-datausage-tracker/deploy/macos/install.sh)

# 2) STATUS / run now
bash install-macos.sh status                 # python3 .../data_tracker.py
# 3) TERMINATE + 4) DELETE
launchctl unload -w ~/Library/LaunchAgents/com.datausage.tracker.plist
bash install-macos.sh uninstall
# 5) CLEAR DATA
rm -rf ~/DataUsageLogs
```

---

## Viewing results (any platform)

Open `dashboard.html` (installed) or `ui/index.html` (repo) in any browser and
drop in `~/DataUsageLogs/DataUsage_Log.csv` (or `%USERPROFILE%\DataUsageLogs\`
on Windows — identical columns, one dashboard serves both).
