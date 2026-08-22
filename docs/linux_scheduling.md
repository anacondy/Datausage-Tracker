# Linux / macOS Scheduling Guide

The Windows `.ps1` scripts use `Register-ScheduledTask`. For Linux/macOS equivalents:

## Adapter Tracker (Python version)
Add a `cron` entry for periodic logging:

```bash
# Open crontab
crontab -e

# Log adapter stats every 30 minutes (similar to Windows TaskScheduler 30 min)
*/30 * * * * /usr/bin/python3 /path/to/python/data_tracker_cross_platform.py >> /home/$USER/data_usage_cron.log 2>&1
```

Or use `systemd` timer (Linux only):

Create `/etc/systemd/system/data-tracker.service`:
```
[Unit]
Description=Cross-Platform Data Usage Tracker

[Service]
ExecStart=/usr/bin/python3 /path/to/python/data_tracker_cross_platform.py
Type=oneshot
```

Create `/etc/systemd/system/data-tracker.timer`:
```
[Unit]
Description=Run Data Tracker every 30 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Unit=data-tracker.service

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now data-tracker.timer
```

---

## macOS `launchd`
Create `~/Library/LaunchAgents/com.datausage.tracker.plist` with a `StartInterval` of 1800 (30 minutes).
