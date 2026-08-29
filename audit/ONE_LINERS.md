# One-Liners — install / activate / terminate / delete / clear-data

Branch: `arena/01a04ccb-datausage-tracker` (v1.0.1, post-audit fixes applied)
Companion to `AUDIT_REPORT.md`. Every command is copy-pasteable.

---

## Linux — Arch / KDE Plasma (recommended build, v1.0.1)

```bash
# INSTALL (downloads tracker + dashboard, creates corrected systemd user units,
# enables the 30-min timer — no root needed)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/linux/install.sh | bash

# STATUS (timer state, next run, log location)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/linux/install.sh | bash -s -- --status
systemctl --user list-timers datausage-tracker.timer     # quick alternative

# ACTIVATE / RUN NOW (one extra data point immediately)
python3 ~/.local/share/datausage-tracker/data_tracker.py

# TERMINATE (stop + disable the timer; keeps files and logs)
systemctl --user disable --now datausage-tracker.timer

# RE-ACTIVATE
systemctl --user enable --now datausage-tracker.timer

# UNINSTALL (removes timer, service and program files; KEEPS your logs)
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/linux/install.sh | bash -s -- --uninstall

# CLEAR ALL DATA (after uninstall, or anytime)
rm -rf ~/DataUsageLogs

# OPTIONAL: keep tracking while logged out (needs root once, e.g. for headless/lid-closed)
sudo loginctl enable-linger "$USER"

# OPTIONAL: KDE Plasma notifications need libnotify on Arch
sudo pacman -S libnotify
```

Notification thresholds (edit `~/.config/systemd/user/datausage-tracker.service`):
`DATAUSAGE_NOTIFY=1`, `DATAUSAGE_NOTIFY_INTERVAL_MB=512`, `DATAUSAGE_NOTIFY_DAILY_MB=2048`,
then `systemctl --user daemon-reload`.

---

## Windows (unchanged — the audited-good side)

```powershell
# INSTALL (one-line)
iwr -useb https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/windows/install.ps1 | iex

# ACTIVATE (if ever disabled)
.\DataUsageTracker.ps1 -Schedule

# RUN NOW
.\DataUsageTracker.ps1 -Log

# TERMINATE (remove scheduled task; keeps logs)
.\DataUsageTracker.ps1 -Unschedule

# CLEAR ALL DATA
Remove-Item -Recurse -Force "$env:USERPROFILE\DataUsageLogs"
```

---

## macOS

```bash
# INSTALL
curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/macos/install.sh | bash

# TERMINATE
launchctl unload -w ~/Library/LaunchAgents/com.datausage.tracker.plist

# UNINSTALL
launchctl unload -w ~/Library/LaunchAgents/com.datausage.tracker.plist 2>/dev/null; rm -rf ~/.local/share/datausage-tracker ~/Library/LaunchAgents/com.datausage.tracker.plist

# CLEAR ALL DATA
rm -rf ~/DataUsageLogs
```

---

## Viewing results (any platform)

Open `ui/index.html` (or `~/.local/share/datausage-tracker/dashboard.html` on
Linux) in any browser and drop in `~/DataUsageLogs/DataUsage_Log.csv`.
Windows and Linux write identical columns, so one dashboard serves both.
