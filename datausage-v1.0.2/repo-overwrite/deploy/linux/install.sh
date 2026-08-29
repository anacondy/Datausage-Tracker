#!/usr/bin/env bash
# One-line install for Linux — optimized for Arch Linux + KDE Plasma
# Usage:
#   curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/linux/install.sh | bash
#   bash install.sh --uninstall    # remove timer+service+files (keeps your logs)
#   bash install.sh --status       # show timer state and log location
#
# What makes this actually optimized (see AUDIT_REPORT.md §5 — the v1.0.0
# units' "Nice=-5" was impossible for unprivileged user services):
#   • Nice=10 + CPUSchedulingPolicy=idle + IOSchedulingClass=idle
#     (all legal for a systemd --user service; the process yields to everything)
#   • CPUQuota=10%, MemoryMax=64M (hard caps; real peak is ~13 MB)
#   • Timer: OnBootSec=2min covers post-boot (delta logic bridges any gap),
#     AccuracySec=1min + RandomizedDelaySec=90 coalesce wakeups —
#     friendlier for laptops/battery
#   • Real KDE Plasma notifications via notify-send (threshold-based,
#     rendered natively by Plasma), not just a "notify-send found" message
#   • Cheap hardening: NoNewPrivileges, PrivateTmp, ProtectSystem=full,
#     RestrictSUIDSGID, LockPersonality, RestrictRealtime

set -euo pipefail

REPO_URL="https://github.com/anacondy/Datausage-Tracker"
BRANCH="arena/01a04ccb-datausage-tracker"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/datausage-tracker}"
SERVICE_DIR="$HOME/.config/systemd/user"
LOG_DIR="$HOME/DataUsageLogs"

# ---------------------------------------------------------------- status ----
if [[ "${1:-}" == "--status" ]]; then
    echo "=== DataUsage Tracker status ==="
    systemctl --user status datausage-tracker.timer --no-pager 2>/dev/null || echo "Timer not active."
    echo
    systemctl --user list-timers datausage-tracker.timer --no-pager 2>/dev/null || true
    echo
    echo "Install dir: $INSTALL_DIR"
    echo "Log dir:     $LOG_DIR"
    [[ -f "$LOG_DIR/DataUsage_Log.csv" ]] && echo "Log rows:    $(($(wc -l < "$LOG_DIR/DataUsage_Log.csv") - 1))"
    exit 0
fi

# ------------------------------------------------------------- uninstall ----
if [[ "${1:-}" == "--uninstall" ]]; then
    echo "[DataUsageTracker] Uninstalling ..."
    systemctl --user disable --now datausage-tracker.timer 2>/dev/null || true
    systemctl --user stop datausage-tracker.service 2>/dev/null || true
    rm -f "$SERVICE_DIR/datausage-tracker.service" "$SERVICE_DIR/datausage-tracker.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    echo "Removed service, timer and program files."
    echo "Your usage logs were KEPT in $LOG_DIR"
    echo "To delete them too:  rm -rf $LOG_DIR"
    exit 0
fi

mkdir -p "$INSTALL_DIR" "$SERVICE_DIR"

echo "[DataUsageTracker Linux Install] Installing to $INSTALL_DIR ..."

# ------------------------------------------------------------ download -----
curl -fsSL "$REPO_URL/raw/$BRANCH/python/data_tracker_cross_platform.py" -o "$INSTALL_DIR/data_tracker.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/python/find_data_hog_cross_platform.py" -o "$INSTALL_DIR/find_data_hog.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/python/chrome_probe_cross_platform.py" -o "$INSTALL_DIR/chrome_probe.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/ui/index.html" -o "$INSTALL_DIR/dashboard.html"
curl -fsSL "$REPO_URL/raw/$BRANCH/docs/METHODOLOGY_TEST_REPORT.md" -o "$INSTALL_DIR/METHOD.md"

chmod +x "$INSTALL_DIR"/*.py

# ------------------------------------------- systemd user service (fixed) -
cat > "$SERVICE_DIR/datausage-tracker.service" << 'SERVICE_EOF'
[Unit]
Description=DataUsage Tracker (low-power adapter monitoring, KDE Plasma notifications)
Documentation=https://github.com/anacondy/Datausage-Tracker
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/.local/share/datausage-tracker/data_tracker.py --quiet
Environment=PYTHONUNBUFFERED=1
# Real desktop notifications (KDE Plasma renders freedesktop notifications)
Environment=DATAUSAGE_NOTIFY=1
Environment=DATAUSAGE_NOTIFY_INTERVAL_MB=512
Environment=DATAUSAGE_NOTIFY_DAILY_MB=2048

# --- Real low-power tuning (all legal for an unprivileged user service) ---
# NOTE: Nice=-5 is NOT possible for systemd --user services (EPERM, silently
# clamped). Nice=10 + idle scheduling genuinely yields to your desktop.
Nice=10
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
CPUQuota=10%
MemoryMax=64M

# --- Cheap hardening (no functional impact: writes only to ~/DataUsageLogs)
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes

[Install]
WantedBy=default.target
SERVICE_EOF

# --------------------------------------------- systemd timer (battery-safe) -
cat > "$SERVICE_DIR/datausage-tracker.timer" << 'TIMER_EOF'
[Unit]
Description=Run DataUsage Tracker every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
# Monotonic timer: always runs 2 min after boot, so a machine that was off
# never loses data — the delta logic counts the whole gap at the first run
# after boot (reboot-safe by design). Persistent=true would be a no-op here:
# systemd only honors it on OnCalendar= timers.
AccuracySec=1min
RandomizedDelaySec=90
Unit=datausage-tracker.service

[Install]
WantedBy=timers.target
TIMER_EOF

# Validate units when systemd-analyze is available
if command -v systemd-analyze &>/dev/null; then
    systemd-analyze verify --user "$SERVICE_DIR/datausage-tracker.service" 2>/dev/null \
        && systemd-analyze verify --user "$SERVICE_DIR/datausage-tracker.timer" 2>/dev/null \
        && echo "[DataUsageTracker] systemd-analyze verify: OK" || true
fi

# --------------------------------------------- Arch / KDE Plasma detection --
echo "[DataUsageTracker] Checking Arch Linux / KDE Plasma environment ..."
if grep -qiE '^ID=arch|^ID_LIKE=.*arch' /etc/os-release 2>/dev/null; then
    echo "  Arch Linux detected."
    if ! command -v notify-send &>/dev/null; then
        echo "  For KDE Plasma notifications:  sudo pacman -S libnotify"
    fi
else
    echo "  (Non-Arch distro — the user units work on any systemd distro.)"
fi
DESKTOP="${XDG_CURRENT_DESKTOP:-}"
if [[ "$DESKTOP" == *KDE* || "$DESKTOP" == *Plasma* ]]; then
    echo "  KDE Plasma session detected — notifications render natively."
fi
if command -v notify-send &>/dev/null; then
    echo "  notify-send found — desktop notifications enabled (thresholds:"
    echo "  512 MB per 30-min interval, 2048 MB per day; edit the service file to change)."
else
    echo "  notify-send not found — install libnotify for desktop notifications"
    echo "  (Arch: sudo pacman -S libnotify). Tracking works without it."
fi

# ------------------------------------------------------------ enable -------
if command -v systemctl &>/dev/null && systemctl --user daemon-reload 2>/dev/null; then
    # Make sure desktop notifications can reach the user manager's env
    # (needed on some X11/edge sessions where the user manager lacks DISPLAY).
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null || true
    systemctl --user enable --now datausage-tracker.timer \
        && echo "[DataUsageTracker] Timer enabled and started (every 30 min)." \
        || echo "Timer not started (may need a login session). Run manually: python3 $INSTALL_DIR/data_tracker.py"

    # Optional: linger keeps the timer running even when logged out.
    if command -v loginctl &>/dev/null; then
        LINGER="$(loginctl show-user "${USER:-$(whoami)}" -p Linger --value 2>/dev/null || echo unknown)"
        if [[ "$LINGER" != "yes" ]]; then
            echo ""
            echo "TIP: to keep tracking while logged out, enable linger (needs root once):"
            echo "     sudo loginctl enable-linger ${USER:-$(whoami)}"
        fi
    fi
else
    echo "Note: systemd user daemon not available (non-systemd distro?)."
    echo "Run manually or via cron:  */30 * * * * /usr/bin/python3 $INSTALL_DIR/data_tracker.py --quiet"
fi

echo ""
echo "=== INSTALL COMPLETE ==="
echo "Install dir: $INSTALL_DIR"
echo "Service:     $SERVICE_DIR/datausage-tracker.service"
echo "Timer:       $SERVICE_DIR/datausage-tracker.timer"
echo "Logs:        $LOG_DIR/DataUsage_Log.csv (same columns as the Windows log)"
echo "Dashboard:   $INSTALL_DIR/dashboard.html (open in browser)"
echo ""
echo "Status:      bash $0 --status"
echo "Run now:     python3 $INSTALL_DIR/data_tracker.py"
echo "Live log:    journalctl --user -u datausage-tracker --follow"
echo "Uninstall:   bash $0 --uninstall   (logs kept; purge: rm -rf $LOG_DIR)"
