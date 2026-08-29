#!/usr/bin/env bash
# One-line install for Linux (Arch / KDE Plasma optimized)
# Usage: curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a029b8-datausage-tracker/deploy/linux/install.sh | bash
# Or: bash <(curl -fsSL .../install.sh)

set -euo pipefail

REPO_URL="https://github.com/anacondy/Datausage-Tracker"
BRANCH="arena/01a029b8-datausage-tracker"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/datausage-tracker}"
SERVICE_DIR="$HOME/.config/systemd/user"

mkdir -p "$INSTALL_DIR"
mkdir -p "$SERVICE_DIR"

echo "[DataUsageTracker Linux Install] Installing to $INSTALL_DIR ..."

# Download Python cross-platform tracker and scanner
curl -fsSL "$REPO_URL/raw/$BRANCH/python/data_tracker_cross_platform.py" -o "$INSTALL_DIR/data_tracker.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/python/find_data_hog_cross_platform.py" -o "$INSTALL_DIR/find_data_hog.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/python/chrome_probe_cross_platform.py" -o "$INSTALL_DIR/chrome_probe.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/ui/index.html" -o "$INSTALL_DIR/dashboard.html"
curl -fsSL "$REPO_URL/raw/$BRANCH/docs/METHODOLOGY_TEST_REPORT.md" -o "$INSTALL_DIR/METHOD.md"

chmod +x "$INSTALL_DIR"/*.py

# Create systemd user service optimized for KDE Plasma / Arch Linux
cat > "$SERVICE_DIR/datausage-tracker.service" << 'SERVICE_EOF'
[Unit]
Description=DataUsage Tracker (low-power adapter monitoring)
Documentation=https://github.com/anacondy/Datausage-Tracker
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.local/share/datausage-tracker/data_tracker.py
Restart=on-failure
RestartSec=30
Environment=PYTHONUNBUFFERED=1

# Optimized for Arch Linux / KDE Plasma
# Uses minimal CPU; reads /proc/net/dev only
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=7
CPUSchedulingPolicy=idle
MemoryMax=64M

[Install]
WantedBy=default.target
SERVICE_EOF

# Create systemd timer (every 30 minutes, matching Windows schedule)
cat > "$SERVICE_DIR/datausage-tracker.timer" << 'TIMER_EOF'
[Unit]
Description=Run DataUsage Tracker every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Unit=datausage-tracker.service

[Install]
WantedBy=timers.target
TIMER_EOF

# KDE Plasma notification support (optional — requires libnotify or notify-send)
echo "[DataUsageTracker] Checking KDE Plasma / Arch environment ..."
if command -v notify-send &>/dev/null; then
    echo "notify-send available — desktop notifications enabled."
else
    echo "notify-send not found — install libnotify for KDE desktop notifications (optional)."
fi

# Enable and start
systemctl --user daemon-reload 2>/dev/null || echo "Note: systemd user daemon not available. You can run manually."
systemctl --user enable --now datausage-tracker.timer 2>/dev/null || echo "Timer not started (may need login session). Run manually: python3 $INSTALL_DIR/data_tracker.py"

echo ""
echo "=== INSTALL COMPLETE ==="
echo "Install dir: $INSTALL_DIR"
echo "Service: $SERVICE_DIR/datausage-tracker.service"
echo "Timer:    $SERVICE_DIR/datausage-tracker.timer"
echo "Dashboard: $INSTALL_DIR/dashboard.html (open in browser)"
echo ""
echo "To view logs: journalctl --user -u datausage-tracker --follow"
echo "To run manually: python3 $INSTALL_DIR/data_tracker.py"
echo "To uninstall: rm -rf $INSTALL_DIR $SERVICE_DIR/datausage-tracker.*"
