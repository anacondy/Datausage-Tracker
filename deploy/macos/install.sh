#!/usr/bin/env bash
# One-line install for macOS
# Usage: curl -fsSL https://github.com/anacondy/Datausage-Tracker/raw/arena/01a029b8-datausage-tracker/deploy/macos/install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/anacondy/Datausage-Tracker"
BRANCH="arena/01a029b8-datausage-tracker"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/datausage-tracker}"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

mkdir -p "$INSTALL_DIR"
mkdir -p "$LAUNCH_DIR"

echo "[DataUsageTracker macOS Install] Installing to $INSTALL_DIR ..."

curl -fsSL "$REPO_URL/raw/$BRANCH/python/data_tracker_cross_platform.py" -o "$INSTALL_DIR/data_tracker.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/python/find_data_hog_cross_platform.py" -o "$INSTALL_DIR/find_data_hog.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/python/chrome_probe_cross_platform.py" -o "$INSTALL_DIR/chrome_probe.py"
curl -fsSL "$REPO_URL/raw/$BRANCH/ui/index.html" -o "$INSTALL_DIR/dashboard.html"

chmod +x "$INSTALL_DIR"/*.py

# Create launchd agent (daemon running every 30 minutes — optimized for macOS)
cat > "$LAUNCH_DIR/com.datausage.tracker.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.datausage.tracker</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>INSTALL_DIR_PLACEHOLDER/data_tracker.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>Nice</key>
    <integer>10</integer>
</dict>
</plist>
PLIST_EOF

# Replace placeholder with actual path
sed -i "" "s|INSTALL_DIR_PLACEHOLDER|$INSTALL_DIR|g" "$LAUNCH_DIR/com.datausage.tracker.plist"

echo "[DataUsageTracker macOS] Checking Python 3 ..."
if command -v python3 &>/dev/null; then
    echo "python3 found: $(python3 --version)"
else
    echo "WARNING: python3 not found. Install Python 3 (brew install python3) for full functionality."
fi

# Load and start agent
launchctl unload -w "$LAUNCH_DIR/com.datausage.tracker.plist" 2>/dev/null || true
launchctl load -w "$LAUNCH_DIR/com.datausage.tracker.plist" 2>/dev/null || echo "Note: launchctl load may require a fresh login session. Agent configured."

echo ""
echo "=== INSTALL COMPLETE ==="
echo "Install dir: $INSTALL_DIR"
echo "Daemon agent: $LAUNCH_DIR/com.datausage.tracker.plist"
echo "Runs every 30 minutes (StartInterval=1800)"
echo "Dashboard: open $INSTALL_DIR/dashboard.html in any browser"
echo ""
echo "To view agent status: launchctl list | grep com.datausage.tracker"
echo "To stop: launchctl unload -w $LAUNCH_DIR/com.datausage.tracker.plist"
echo "To uninstall: rm -rf $INSTALL_DIR $LAUNCH_DIR/com.datausage.tracker.plist"
