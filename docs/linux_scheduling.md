# Linux / macOS Scheduling Guide

The Windows `.ps1` scripts use `Register-ScheduledTask`. For Linux/macOS
equivalents, the **recommended path is the one-line installer**
(`deploy/linux/install.sh` / `deploy/macos/install.sh`), which sets up a
corrected, low-power daemon for you. Manual setup is below.

> **Important (v1.0.1):** the v1.0.0 `systemd` unit used `Nice=-5`. An
> unprivileged `systemd --user` manager is **not allowed** to raise priority —
> `Nice=-5` is silently clamped to 0 (or fails on older systemd) and logs a
> priority error on every timer activation. Use `Nice=10` plus idle CPU/IO
> scheduling instead, which are legal and genuinely low-power. The corrected
> units are in `deploy/linux/install.sh`.

## Adapter Tracker (Python version)

The v1.0.1 `python/data_tracker_cross_platform.py` **accumulates** usage:
it appends a row per run to `~/DataUsageLogs/DataUsage_Log.csv`, keeps a
`baseline.json`, is reboot-safe, and skips loopback. It is safe to run on a
30-minute timer.

### Option A — cron
```bash
# Open crontab
crontab -e

# Log adapter stats every 30 minutes (matches Windows TaskScheduler 30 min)
*/30 * * * * /usr/bin/python3 /path/to/python/data_tracker_cross_platform.py --quiet >> /home/$USER/data_usage_cron.log 2>&1
```

### Option B — systemd user timer (recommended on Arch/KDE)
Create `~/.config/systemd/user/datausage-tracker.service`:
```
[Unit]
Description=DataUsage Tracker (low-power adapter monitoring)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/.local/share/datausage-tracker/data_tracker.py --quiet
Environment=PYTHONUNBUFFERED=1
Environment=DATAUSAGE_NOTIFY=1

# Legal, genuinely low-power tuning for a user service
Nice=10
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
CPUQuota=10%
MemoryMax=64M

# Cheap hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
RestrictSUIDSGID=yes

[Install]
WantedBy=default.target
```

Create `~/.config/systemd/user/datausage-tracker.timer`:
```
[Unit]
Description=Run DataUsage Tracker every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Persistent=true
AccuracySec=1min
RandomizedDelaySec=90
Unit=datausage-tracker.service

[Install]
WantedBy=timers.target
```

Enable (as your normal user — no root needed):
```bash
systemctl --user daemon-reload
systemctl --user enable --now datausage-tracker.timer
```

`Persistent=true` makes up for runs missed while the machine was powered off
(parity with Windows' `StartWhenAvailable`). `AccuracySec` + `RandomizedDelaySec`
let systemd coalesce wakeups, which is friendlier for laptop batteries.

---

## macOS `launchd`
Create `~/Library/LaunchAgents/com.datausage.tracker.plist` with a
`StartInterval` of 1800 (30 minutes) and `Nice=10` — see
`deploy/macos/install.sh` for the full plist.

---

## KDE Plasma notifications
The v1.0.1 tracker sends real freedesktop notifications via `notify-send`
(rendered natively by Plasma) when usage crosses a threshold. Enable with
`DATAUSAGE_NOTIFY=1` and tune:
```bash
DATAUSAGE_NOTIFY=1 \
DATAUSAGE_NOTIFY_INTERVAL_MB=512 \
DATAUSAGE_NOTIFY_DAILY_MB=2048 \
python3 data_tracker_cross_platform.py
```
On Arch, `notify-send` comes from `libnotify`: `sudo pacman -S libnotify`.
