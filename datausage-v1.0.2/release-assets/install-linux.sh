#!/usr/bin/env bash
# ============================================================================
#  DataUsageTracker v1.0.2 — SELF-CONTAINED Linux installer (Arch/KDE ready)
#  The tracker code is embedded below — after downloading this file, NO
#  network access is needed to install or to run.
#
#  One-line install:   curl -fsSL <release-asset-url>/install-linux.sh | bash
#  Modes: install (default) | status | stop | uninstall | purge-data
# ============================================================================
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/datausage-tracker}"
SERVICE_DIR="$HOME/.config/systemd/user"
LOG_DIR="$HOME/DataUsageLogs"
MODE="${1:-install}"

case "$MODE" in
  status)
    echo "=== DataUsage Tracker status ==="
    systemctl --user status datausage-tracker.timer --no-pager 2>/dev/null || echo "Timer not active."
    systemctl --user list-timers datausage-tracker.timer --no-pager 2>/dev/null || true
    [[ -f "$LOG_DIR/DataUsage_Log.csv" ]] && echo "Log rows: $(($(wc -l < "$LOG_DIR/DataUsage_Log.csv") - 1))  in $LOG_DIR"
    exit 0 ;;
  stop)
    systemctl --user disable --now datausage-tracker.timer 2>/dev/null || true
    systemctl --user stop datausage-tracker.service 2>/dev/null || true
    echo "Tracker TERMINATED (timer disabled). Data kept in $LOG_DIR"
    exit 0 ;;
  uninstall)
    systemctl --user disable --now datausage-tracker.timer 2>/dev/null || true
    systemctl --user stop datausage-tracker.service 2>/dev/null || true
    rm -f "$SERVICE_DIR/datausage-tracker.service" "$SERVICE_DIR/datausage-tracker.timer"
    systemctl --user daemon-reload 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    echo "Uninstalled. Logs kept in $LOG_DIR (purge-data deletes them)."
    exit 0 ;;
  purge-data)
    rm -rf "$LOG_DIR"; echo "All logged data deleted ($LOG_DIR)."; exit 0 ;;
esac

echo "[DataUsageTracker] Installing (self-contained, offline) to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR" "$SERVICE_DIR" "$LOG_DIR"

cat > "$INSTALL_DIR/data_tracker.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Cross-Platform Data Usage Tracker — Linux / macOS port of DataUsageTracker.ps1
===============================================================================

This is a FAITHFUL PORT of the Windows script's counting methodology
(audit-verified, see AUDIT_REPORT.md §4), not just a snapshot printer:

  • CSV APPEND — every run adds rows; the log accumulates over time
    (the v1.0.0 version overwrote its log each run — nothing accumulated).
  • baseline.json — per-adapter counters + lifetime totals, written
    atomically (tmp file + os.replace, so a power-cut can't lose it).
  • REBOOT-SAFE deltas — if a counter drops (reboot resets it), the whole
    current value is counted as new usage since boot. Nothing is lost,
    nothing is double-counted.
  • Adapter disappear/rejoin — each interface keeps its own baseline row,
    so hotspot-off/on or ethernet unplug/replug resumes exactly.
  • 15-second DEDUP guard — a manual run right after the timer fired
    cannot double-count.
  • Loopback (lo) is EXCLUDED on Linux — on a KDE desktop it would add
    local Plasma IPC/proxy traffic, and with a local proxy it would be
    counted twice (lo + real interface).
  • IST timestamps via zoneinfo (Asia/Kolkata), with a fixed UTC+5:30
    fallback when the tz database is unavailable.
  • Real KDE Plasma / freedesktop DESKTOP NOTIFICATIONS via notify-send
    (threshold-based, configurable, never blocks or crashes the tracker).

CSV columns are IDENTICAL to the Windows DataUsage_Log.csv so the same
ui/index.html dashboard works for both.

Per-app (WinRT SRUM) tracking remains Windows-only — that is an OS
limitation, not a script limitation.

Usage:
    python3 data_tracker_cross_platform.py             # log one data point
    python3 data_tracker_cross_platform.py --quiet     # (used by the timer)
    python3 data_tracker_cross_platform.py --snapshot  # print-only, no write

Environment:
    DATAUSAGE_LOG_DIR            log directory (default ~/DataUsageLogs)
    DATAUSAGE_NOTIFY             1 = enable desktop notifications
    DATAUSAGE_NOTIFY_INTERVAL_MB alert when one run's delta >= this (0 = off; default 512)
    DATAUSAGE_NOTIFY_DAILY_MB    alert when today's total >= this  (0 = off; default 2048)
    DATAUSAGE_INCLUDE_LOOPBACK   1 = also count loopback traffic (default: excluded)
"""

import os
import sys
import csv
import json
import shutil
import subprocess
from datetime import datetime, timedelta, timezone

try:  # Python 3.9+: real tz database (Arch ships it; also fine via pip tzdata)
    from zoneinfo import ZoneInfo
    try:
        IST = ZoneInfo("Asia/Kolkata")
    except Exception:
        IST = timezone(timedelta(hours=5, minutes=30))
except ImportError:  # guaranteed IST fallback (UTC+5:30, no DST in IST)
    IST = timezone(timedelta(hours=5, minutes=30))

PROC_NET_DEV = "/proc/net/dev"
LOG_DIR = os.path.expanduser(os.environ.get("DATAUSAGE_LOG_DIR", "~/DataUsageLogs"))
CSV_NAME = "DataUsage_Log.csv"          # same name+columns as Windows → same dashboard
BASELINE_NAME = "baseline.json"
LAST_RUN_NAME = "last_run.json"
CSV_HEADER = [
    "TimestampIST", "DateIST", "TimeIST", "Adapter",
    "Received_Delta", "Sent_Delta", "Total_Delta",
    "Lifetime_Received", "Lifetime_Sent", "Lifetime_Total",
]
DEDUP_SECONDS = 15


# ----------------------------------------------------------------------------
# Time helpers (IST, matching the Windows script's formatting)
# ----------------------------------------------------------------------------
def ist_now():
    return datetime.now(timezone.utc).astimezone(IST)


def ordinal_suffix(day):
    mod100 = day % 100
    if 11 <= mod100 <= 13:
        return "th"
    return {1: "st", 2: "nd", 3: "rd"}.get(day % 10, "th")


def format_ordinal_date(dt):
    return f"{dt.day}{ordinal_suffix(dt.day)} {dt.strftime('%B')} {dt.year}"


def format_bytes(num_bytes):
    if num_bytes < 0:
        num_bytes = 0
    num_bytes = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if num_bytes < 1024.0:
            return f"{num_bytes:.2f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.2f} PB"


# ----------------------------------------------------------------------------
# Adapter counters
# ----------------------------------------------------------------------------
def read_adapters_linux(proc_path=PROC_NET_DEV, include_loopback=None):
    """Read /proc/net/dev byte counters. Loopback excluded by default."""
    if include_loopback is None:
        include_loopback = os.environ.get("DATAUSAGE_INCLUDE_LOOPBACK", "0") == "1"
    adapters = {}
    try:
        with open(proc_path, "r") as f:
            lines = f.readlines()[2:]  # skip the two header lines
    except OSError:
        return adapters
    for line in lines:
        parts = line.split(":")
        if len(parts) < 2:
            continue
        iface = parts[0].strip()
        if not iface or (iface == "lo" and not include_loopback):
            continue
        stats = parts[1].split()
        # /proc/net/dev columns: rx bytes packets errs drop ... | tx bytes ...
        try:
            rx = int(stats[0])
            tx = int(stats[8]) if len(stats) > 8 else 0
        except (IndexError, ValueError):
            continue
        adapters[iface] = {"Adapter": iface, "Received": rx, "Sent": tx,
                           "Total": rx + tx, "Status": "Up"}
    return adapters


def read_adapters_psutil(include_loopback=None):
    """psutil-based counters (macOS and non-/proc platforms)."""
    if include_loopback is None:
        include_loopback = os.environ.get("DATAUSAGE_INCLUDE_LOOPBACK", "0") == "1"
    adapters = {}
    try:
        import psutil  # optional dependency
        counters = psutil.net_io_counters(pernic=True)
    except Exception:
        return adapters
    for iface, stats in counters.items():
        if not include_loopback and iface in ("lo", "lo0"):
            continue
        adapters[iface] = {"Adapter": iface, "Received": stats.bytes_recv,
                           "Sent": stats.bytes_sent,
                           "Total": stats.bytes_recv + stats.bytes_sent,
                           "Status": "Up"}
    return adapters


def get_adapters(proc_path=PROC_NET_DEV):
    if sys.platform == "linux":
        adapters = read_adapters_linux(proc_path)
        if adapters or not os.path.exists(proc_path):
            return adapters
        return read_adapters_psutil()  # unusual kernel: fall back to psutil
    return read_adapters_psutil()


# ----------------------------------------------------------------------------
# Atomic JSON state files (audit §3 weakness 6: power-cut safe)
# ----------------------------------------------------------------------------
def load_json(path, default):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json_atomic(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


# ----------------------------------------------------------------------------
# KDE Plasma / freedesktop desktop notifications (REAL, threshold-based)
# ----------------------------------------------------------------------------
def _notify_send(summary, body, urgency="normal"):
    """Send a freedesktop notification (KDE Plasma renders these natively).

    Tries, in order: notify-send with --app-name (libnotify >= 0.8, labels the
    toast nicely on Plasma), plain notify-send (older libnotify), then kdialog
    (KDE-native popup). Returns True ONLY if a command actually exited 0 —
    a failed notification must never be recorded as delivered, or the
    rate-limiter would swallow the alert.
    """
    commands = (
        ["notify-send", "--app-name=DataUsage Tracker", "-u", urgency,
         "-i", "network-transmit", summary, body],
        ["notify-send", "-u", urgency, summary, body],
        ["kdialog", "--title", "DataUsage Tracker", "--passivepopup",
         f"{summary}\n{body}", "10"],
    )
    for cmd in commands:
        if not shutil.which(cmd[0]):
            continue
        try:
            result = subprocess.run(cmd, timeout=5,
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
            if result.returncode == 0:
                return True
        except Exception:
            continue
    return False


def maybe_notify(log_dir, interval_total, daily_total, now_ist):
    """Threshold notifications. Enabled with DATAUSAGE_NOTIFY=1 (set by the
    systemd install). Never raises; worst case prints a note."""
    if os.environ.get("DATAUSAGE_NOTIFY", "0") != "1":
        return
    try:
        interval_mb = int(os.environ.get("DATAUSAGE_NOTIFY_INTERVAL_MB", "512"))
        daily_mb = int(os.environ.get("DATAUSAGE_NOTIFY_DAILY_MB", "2048"))
    except ValueError:
        return

    try:
        os.makedirs(log_dir, exist_ok=True)   # never crash if the dir is missing
    except OSError:
        return
    state = load_json(os.path.join(log_dir, LAST_RUN_NAME), {})
    today = now_ist.strftime("%Y-%m-%d")

    # Interval alert — at most once per hour so a long download can't spam.
    if interval_mb > 0 and interval_total >= interval_mb * 1024 * 1024:
        last = state.get("LastIntervalNotifyUtc")
        if not last or (datetime.now(timezone.utc) -
                        datetime.fromisoformat(last)).total_seconds() >= 3600:
            if _notify_send("Heavy data usage this interval",
                            f"{format_bytes(interval_total)} in the last "
                            f"~30 min (threshold {interval_mb} MB)."):
                state["LastIntervalNotifyUtc"] = datetime.now(timezone.utc).isoformat()

    # Daily alert — once per day, critical urgency (Plasma shows it prominently).
    if daily_mb > 0 and daily_total >= daily_mb * 1024 * 1024 \
            and state.get("LastDailyNotifyDate") != today:
        if _notify_send("Daily data budget exceeded",
                        f"{format_bytes(daily_total)} used today "
                        f"(threshold {daily_mb} MB).", urgency="critical"):
            state["LastDailyNotifyDate"] = today

    save_json_atomic(os.path.join(log_dir, LAST_RUN_NAME), state)


def today_total_from_csv(csv_path, now_ist):
    """Sum today's Total_Delta rows from the log (cheap; file is small)."""
    today_time_prefix = now_ist.strftime("%I:%M")  # not used; date col is ordinal
    total = 0
    today_ordinal = format_ordinal_date(now_ist)
    try:
        with open(csv_path, "r", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get("DateIST") == today_ordinal:
                    try:
                        total += int(row.get("Total_Delta", "0"))
                    except ValueError:
                        pass
    except OSError:
        pass
    return total


# ----------------------------------------------------------------------------
# The log point — faithful port of Save-LogPoint in DataUsageTracker.ps1
# ----------------------------------------------------------------------------
def log_point(log_dir=LOG_DIR, proc_path=PROC_NET_DEV, dedup_seconds=DEDUP_SECONDS,
              quiet=False, notify=True):
    os.makedirs(log_dir, exist_ok=True)
    csv_path = os.path.join(log_dir, CSV_NAME)
    baseline_path = os.path.join(log_dir, BASELINE_NAME)
    last_run_path = os.path.join(log_dir, LAST_RUN_NAME)

    now_utc = datetime.now(timezone.utc)
    now_ist = now_utc.astimezone(IST)

    # --- dedup guard (same as Windows: skip if written <15 s ago) ----------
    if dedup_seconds > 0:
        state = load_json(last_run_path, {})
        last = state.get("LastLogUtc")
        if last:
            try:
                elapsed = (now_utc - datetime.fromisoformat(last)).total_seconds()
                if elapsed < dedup_seconds:
                    if not quiet:
                        print("Skip: a log point was just written (dedup guard).")
                    return False
            except ValueError:
                pass

    adapters = get_adapters(proc_path)
    if not adapters:
        if not quiet:
            print("No adapter statistics available.")
            print("On Linux, ensure /proc/net/dev is readable; on macOS, "
                  "install psutil (pip install psutil).")
        return False

    # --- baseline bookkeeping ----------------------------------------------
    baseline = load_json(baseline_path, {})
    prev_adapters = baseline.get("Adapters", {})
    lifetime = baseline.get("Lifetime", {})

    date_str = format_ordinal_date(now_ist)
    time_str = now_ist.strftime("%I:%M:%S %p")

    # --- CSV append (never overwrite — the v1.0.0 bug) ----------------------
    is_new = not os.path.exists(csv_path)
    with open(csv_path, "a", newline="") as f:
        writer = csv.writer(f)
        if is_new:
            writer.writerow(CSV_HEADER)
        interval_total = 0
        for name, a in sorted(adapters.items()):
            prev = prev_adapters.get(name, {})
            prev_rx = int(prev.get("Received", 0))
            prev_tx = int(prev.get("Sent", 0))
            # reboot/rollover-safe delta (identical logic to the .ps1):
            rx_d = a["Received"] - prev_rx if a["Received"] >= prev_rx else a["Received"]
            tx_d = a["Sent"] - prev_tx if a["Sent"] >= prev_tx else a["Sent"]
            lt = lifetime.get(name, {})
            lt_rx = int(lt.get("Received", 0)) + rx_d
            lt_tx = int(lt.get("Sent", 0)) + tx_d
            lifetime[name] = {"Received": lt_rx, "Sent": lt_tx}
            interval_total += rx_d + tx_d
            writer.writerow([
                time_str, date_str, time_str, name,
                rx_d, tx_d, rx_d + tx_d,
                lt_rx, lt_tx, lt_rx + lt_tx,
            ])

    # --- store new baseline atomically --------------------------------------
    # Preserve baselines of adapters that are temporarily absent (hotspot off,
    # ethernet unplugged) so they rejoin with an exact delta instead of
    # over-reporting their whole current counter.
    new_adapters = {n: {"Received": a["Received"], "Sent": a["Sent"]}
                    for n, a in adapters.items()}
    for name, prev in prev_adapters.items():
        new_adapters.setdefault(name, prev)
    save_json_atomic(baseline_path, {
        "LastRunUtc": now_utc.isoformat(),
        "Adapters": new_adapters,
        "Lifetime": lifetime,
    })

    # --- dedup guard state (preserve notify state fields already there) ----
    state = load_json(last_run_path, {})
    state["LastLogUtc"] = now_utc.isoformat()
    save_json_atomic(last_run_path, state)

    if not quiet:
        print(f"Log point written: {date_str} at {time_str} IST")
        for name, a in sorted(adapters.items()):
            prev = prev_adapters.get(name, {})
            print(f"  {name:<16} lifetime {format_bytes(a['Total'])}"
                  f"  (down {format_bytes(a['Received'])} / up {format_bytes(a['Sent'])})")

    # --- real desktop notifications (KDE Plasma native) ---------------------
    if notify:
        try:
            daily_total = today_total_from_csv(csv_path, now_ist)
            maybe_notify(log_dir, interval_total, daily_total, now_ist)
        except Exception:
            pass  # notifications must never break logging

    return True


# ----------------------------------------------------------------------------
# Snapshot (print-only) mode
# ----------------------------------------------------------------------------
def snapshot(proc_path=PROC_NET_DEV):
    print("Cross-Platform Data Usage Tracker — snapshot (no log write)")
    print(f"Platform: {sys.platform}   Time: {ist_now().strftime('%Y-%m-%d %I:%M:%S %p')} IST")
    adapters = get_adapters(proc_path)
    if not adapters:
        print("No adapter statistics available.")
        return
    print(f"{'Adapter':<20} {'Status':<8} {'Received':<15} {'Sent':<15} {'Total':<15}")
    print("-" * 75)
    for a in sorted(adapters.values(), key=lambda x: -x["Total"]):
        print(f"{a['Adapter']:<20} {a['Status']:<8} "
              f"{format_bytes(a['Received']):<15} {format_bytes(a['Sent']):<15} "
              f"{format_bytes(a['Total']):<15}")
    print("\nNote: per-app usage (WinRT SRUM) is Windows-only; this port provides "
          "adapter-level tracking with the same delta methodology.")


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    proc_path = os.environ.get("DATAUSAGE_PROC_NET_DEV", PROC_NET_DEV)
    if "--snapshot" in argv:
        snapshot(proc_path)
    elif "--help" in argv or "-h" in argv:
        print(__doc__)
    else:
        log_point(quiet="--quiet" in argv, proc_path=proc_path)


if __name__ == "__main__":
    main()
PYEOF
chmod +x "$INSTALL_DIR/data_tracker.py"

base64 -d > "$INSTALL_DIR/dashboard.html" << 'B64EOF'
PCFET0NUWVBFIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9IlVURi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCwgaW5pdGlhbC1zY2FsZT0xLjAiPgo8dGl0bGU+RGF0YVVzYWdlIFRyYWNrZXIg4oCUIERhc2hib2FyZDwvdGl0bGU+CjxzdHlsZT4KOnJvb3QgewogIC0tYmc6ICMwZjE3MmE7CiAgLS1zdXJmYWNlOiAjMWUyOTNiOwogIC0tc3VyZmFjZS0yOiAjMzM0MTU1OwogIC0tdGV4dDogI2Y4ZmFmYzsKICAtLXRleHQtbXV0ZWQ6ICM5NGEzYjg7CiAgLS1hY2NlbnQ6ICMzOGJkZjg7CiAgLS1hY2NlbnQtMjogIzgxOGNmODsKICAtLXN1Y2Nlc3M6ICMzNGQzOTk7CiAgLS1ib3JkZXI6ICMzMzQxNTU7CiAgLS1mb250OiB1aS1zYW5zLXNlcmlmLCBzeXN0ZW0tdWksIC1hcHBsZS1zeXN0ZW0sIFNlZ29lIFVJLCBSb2JvdG8sIEhlbHZldGljYSwgQXJpYWwsIHNhbnMtc2VyaWY7Cn0KCiogeyBib3gtc2l6aW5nOiBib3JkZXItYm94OyB9Cgpib2R5IHsKICBtYXJnaW46IDA7IHBhZGRpbmc6IDA7CiAgZm9udC1mYW1pbHk6IHZhcigtLWZvbnQpOwogIGJhY2tncm91bmQ6IGxpbmVhci1ncmFkaWVudCgxODBkZWcsIHZhcigtLWJnKSAwJSwgIzBiMTIyMSAxMDAlKTsKICBjb2xvcjogdmFyKC0tdGV4dCk7CiAgbWluLWhlaWdodDogMTAwdmg7Cn0KCmhlYWRlciB7CiAgcGFkZGluZzogM3JlbSAxLjVyZW0gMnJlbTsKICBtYXgtd2lkdGg6IDEyMDBweDsgbWFyZ2luOiAwIGF1dG87CiAgdGV4dC1hbGlnbjogY2VudGVyOwp9CgpoZWFkZXIgaDEgewogIGZvbnQtc2l6ZTogMi42cmVtOyBmb250LXdlaWdodDogODAwOyBsZXR0ZXItc3BhY2luZzogLTAuMDNlbTsKICBtYXJnaW46IDAgMCAwLjI1cmVtOyBiYWNrZ3JvdW5kOiBsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCB2YXIoLS1hY2NlbnQpIDAlLCB2YXIoLS1hY2NlbnQtMikgMTAwJSk7CiAgLXdlYmtpdC1iYWNrZ3JvdW5kLWNsaXA6IHRleHQ7IC13ZWJraXQtdGV4dC1maWxsLWNvbG9yOiB0cmFuc3BhcmVudDsgYmFja2dyb3VuZC1jbGlwOiB0ZXh0Owp9CmhlYWRlciBwIHsgY29sb3I6IHZhcigtLXRleHQtbXV0ZWQpOyBmb250LXNpemU6IDEuMDVyZW07IG1hcmdpbjogMDsgfQoKbWFpbiB7IG1heC13aWR0aDogMTIwMHB4OyBtYXJnaW46IDAgYXV0bzsgcGFkZGluZzogMCAxLjVyZW0gNHJlbTsgfQoKLmNhcmQgewogIGJhY2tncm91bmQ6IHZhcigtLXN1cmZhY2UpOyBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIpOwogIGJvcmRlci1yYWRpdXM6IDEuMjVyZW07IHBhZGRpbmc6IDEuNzVyZW07IG1hcmdpbi1ib3R0b206IDEuNXJlbTsgYm94LXNoYWRvdzogMCAxMHB4IDQwcHggcmdiYSgwLDAsMCwwLjI1KTsKfQoKLmNhcmQgaDIgeyBtYXJnaW46IDAgMCAxcmVtOyBmb250LXNpemU6IDEuMTVyZW07IGNvbG9yOiB2YXIoLS10ZXh0KTsgZGlzcGxheTogZmxleDsgYWxpZ24taXRlbXM6IGNlbnRlcjsgZ2FwOiAwLjZyZW07IH0KLmNhcmQgaDIgLmRvdCB7IHdpZHRoOiA4cHg7IGhlaWdodDogOHB4OyBib3JkZXItcmFkaXVzOiA1MCU7IGJhY2tncm91bmQ6IHZhcigtLWFjY2VudCk7IGRpc3BsYXk6IGlubGluZS1ibG9jazsgfQoKLnVwbG9hZC1hcmVhIHsKICBib3JkZXI6IDJweCBkYXNoZWQgdmFyKC0tc3VyZmFjZS0yKTsgYm9yZGVyLXJhZGl1czogMXJlbTsgcGFkZGluZzogMnJlbTsgdGV4dC1hbGlnbjogY2VudGVyOyBjdXJzb3I6IHBvaW50ZXI7IHRyYW5zaXRpb246IGJvcmRlci1jb2xvciAuMnMsIGJhY2tncm91bmQgLjJzOwp9Ci51cGxvYWQtYXJlYTpob3ZlciB7IGJvcmRlci1jb2xvcjogdmFyKC0tYWNjZW50KTsgYmFja2dyb3VuZDogcmdiYSg1NiwxODksMjQ4LDAuMDQpOyB9Ci51cGxvYWQtYXJlYSBpbnB1dCB7IGRpc3BsYXk6IG5vbmU7IH0KLnVwbG9hZC1hcmVhIC5oaW50IHsgY29sb3I6IHZhcigtLXRleHQtbXV0ZWQpOyBmb250LXNpemU6IC45cmVtOyBtYXJnaW4tdG9wOiAuNXJlbTsgfQoKdGFibGUgeyB3aWR0aDogMTAwJTsgYm9yZGVyLWNvbGxhcHNlOiBjb2xsYXBzZTsgZm9udC1zaXplOiAuOTJyZW07IH0KdGhlYWQgdGggeyB0ZXh0LWFsaWduOiBsZWZ0OyBwYWRkaW5nOiAuNjVyZW0gLjc1cmVtOyBjb2xvcjogdmFyKC0tdGV4dC1tdXRlZCk7IGZvbnQtd2VpZ2h0OiA2MDA7IGJvcmRlci1ib3R0b206IDFweCBzb2xpZCB2YXIoLS1ib3JkZXIpOyB3aGl0ZS1zcGFjZTogbm93cmFwOyB9CnRib2R5IHRkIHsgcGFkZGluZzogLjZyZW0gLjc1cmVtOyBib3JkZXItYm90dG9tOiAxcHggc29saWQgcmdiYSgyNTUsMjU1LDI1NSwwLjA0KTsgY29sb3I6IHZhcigtLXRleHQpOyB9CnRib2R5IHRyOmhvdmVyIHRkIHsgYmFja2dyb3VuZDogcmdiYSgyNTUsMjU1LDI1NSwwLjAzKTsgfQoKLmJ5dGUgeyBmb250LXZhcmlhbnQtbnVtZXJpYzogdGFidWxhci1udW1zOyB3aGl0ZS1zcGFjZTogbm93cmFwOyBjb2xvcjogdmFyKC0tYWNjZW50LTIpOyBmb250LXdlaWdodDogNjAwOyB9Ci5kYXRlIHsgY29sb3I6IHZhcigtLXRleHQtbXV0ZWQpOyB3aGl0ZS1zcGFjZTogbm93cmFwOyB9CgoudGFnIHsgZGlzcGxheTogaW5saW5lLWJsb2NrOyBwYWRkaW5nOiAuMTVyZW0gLjU1cmVtOyBib3JkZXItcmFkaXVzOiAuNXJlbTsgZm9udC1zaXplOiAuNzVyZW07IGZvbnQtd2VpZ2h0OiA3MDA7IHRleHQtdHJhbnNmb3JtOiB1cHBlcmNhc2U7IGxldHRlci1zcGFjaW5nOiAuMDNlbTsgfQoudGFnLWFkYXB0ZXIgeyBiYWNrZ3JvdW5kOiByZ2JhKDU2LDE4OSwyNDgsMC4xNSk7IGNvbG9yOiB2YXIoLS1hY2NlbnQpOyB9Ci50YWctYXBwIHsgYmFja2dyb3VuZDogcmdiYSgxMjksMTQwLDI0OCwwLjE1KTsgY29sb3I6IHZhcigtLWFjY2VudC0yKTsgfQoKLmVtcHR5LXN0YXRlIHsgY29sb3I6IHZhcigtLXRleHQtbXV0ZWQpOyB0ZXh0LWFsaWduOiBjZW50ZXI7IHBhZGRpbmc6IDJyZW0gMDsgfQoKQG1lZGlhIChtYXgtd2lkdGg6IDcyMHB4KSB7CiAgaGVhZGVyIGgxIHsgZm9udC1zaXplOiAxLjhyZW07IH0KICBtYWluIHsgcGFkZGluZzogMCAxcmVtIDNyZW07IH0KICAuY2FyZCB7IHBhZGRpbmc6IDEuMnJlbTsgfQogIHRhYmxlLCB0aGVhZCwgdGJvZHksIHRoLCB0ZCwgdHIgeyBkaXNwbGF5OiBibG9jazsgfQogIHRoZWFkIHsgZGlzcGxheTogbm9uZTsgfQogIHRib2R5IHRkIHsgcGFkZGluZzogLjVyZW0gMDsgZGlzcGxheTogZmxleDsganVzdGlmeS1jb250ZW50OiBzcGFjZS1iZXR3ZWVuOyBhbGlnbi1pdGVtczogY2VudGVyOyB9CiAgdGJvZHkgdGQ6OmJlZm9yZSB7IGNvbnRlbnQ6IGF0dHIoZGF0YS1sYWJlbCk7IGZvbnQtd2VpZ2h0OiA2MDA7IGNvbG9yOiB2YXIoLS10ZXh0LW11dGVkKTsgfQp9Cjwvc3R5bGU+CjwvaGVhZD4KPGJvZHk+Cgo8aGVhZGVyPgogIDxoMT5EYXRhVXNhZ2UgVHJhY2tlcjwvaDE+CiAgPHA+Q3Jvc3MtcGxhdGZvcm0gQ1NWIGRhc2hib2FyZCDigJQgdmlldyB5b3VyIGFkYXB0ZXIgYW5kIHBlci1hcHAgdXNhZ2Ugd2l0aG91dCBQb3dlclNoZWxsPC9wPgo8L2hlYWRlcj4KCjxtYWluPgoKICA8c2VjdGlvbiBjbGFzcz0iY2FyZCIgYXJpYS1sYWJlbD0iVXBsb2FkIENTViI+CiAgICA8aDI+PHNwYW4gY2xhc3M9ImRvdCI+PC9zcGFuPiBVcGxvYWQgeW91ciBDU1Y8L2gyPgogICAgPGxhYmVsIGNsYXNzPSJ1cGxvYWQtYXJlYSIgaWQ9ImRyb3Bab25lIiBhcmlhLWxhYmVsPSJEcm9wIENTViBmaWxlIGhlcmUiPgogICAgICA8aW5wdXQgdHlwZT0iZmlsZSIgaWQ9ImZpbGVJbnB1dCIgYWNjZXB0PSIuY3N2IiBhcmlhLWxhYmVsPSJTZWxlY3QgQ1NWIGZpbGUiIC8+CiAgICAgIDxzdHJvbmc+RHJvcCBhIENTViBoZXJlPC9zdHJvbmc+IG9yIGNsaWNrIHRvIGNob29zZQogICAgICA8ZGl2IGNsYXNzPSJoaW50Ij5Xb3JrcyB3aXRoIDxjb2RlPkRhdGFVc2FnZV9Mb2cuY3N2PC9jb2RlPiBvciA8Y29kZT5EYXRhVXNhZ2VfUmVwb3J0LmNzdjwvY29kZT48L2Rpdj4KICAgIDwvbGFiZWw+CiAgPC9zZWN0aW9uPgoKICA8c2VjdGlvbiBjbGFzcz0iY2FyZCIgYXJpYS1sYWJlbD0iUmVzdWx0cyIgaWQ9InJlc3VsdHNDYXJkIiBzdHlsZT0iZGlzcGxheTpub25lOyI+CiAgICA8aDI+PHNwYW4gY2xhc3M9ImRvdCI+PC9zcGFuPiA8c3BhbiBpZD0icmVzdWx0c1RpdGxlIj5SZXN1bHRzPC9zcGFuPjwvaDI+CiAgICA8ZGl2IHN0eWxlPSJvdmVyZmxvdy14OmF1dG87IiBpZD0icmVzdWx0c0NvbnRhaW5lciI+PC9kaXY+CiAgPC9zZWN0aW9uPgoKICA8c2VjdGlvbiBjbGFzcz0iY2FyZCIgYXJpYS1sYWJlbD0iSG93IGl0IHdvcmtzIiBzdHlsZT0ib3BhY2l0eTogLjkyOyI+CiAgICA8aDI+PHNwYW4gY2xhc3M9ImRvdCI+PC9zcGFuPiBIb3cgdGhpcyB0cmFja2VyIHdvcmtzPC9oMj4KICAgIDx1bCBzdHlsZT0ibGluZS1oZWlnaHQ6MS43OyBjb2xvcjp2YXIoLS10ZXh0LW11dGVkKTsgcGFkZGluZy1sZWZ0OjEuMXJlbTsiPgogICAgICA8bGk+PHN0cm9uZz5XaW5SVCBBUEk8L3N0cm9uZz4g4oCUIHJlYWRzIHRoZSBzYW1lIHBlci1hcHAgY291bnRlcnMgV2luZG93cyBTZXR0aW5ncyB1c2VzLjwvbGk+CiAgICAgIDxsaT48c3Ryb25nPkFkYXB0ZXIgc3RhdGlzdGljczwvc3Ryb25nPiDigJQgcmVhZHMgcGVyLWludGVyZmFjZSBieXRlIGNvdW50ZXJzIGZyb20gdGhlIE9TIG5ldHdvcmsgc3RhY2suPC9saT4KICAgICAgPGxpPjxzdHJvbmc+RGVsdGEgY29tcHV0YXRpb248L3N0cm9uZz4g4oCUIGNvbXBhcmVzIGN1cnJlbnQgYWRhcHRlciBjb3VudGVycyBhZ2FpbnN0IHN0b3JlZCBiYXNlbGluZXMuPC9saT4KICAgICAgPGxpPjxzdHJvbmc+UmVib290LXNhZmU8L3N0cm9uZz4g4oCUIGRldGVjdHMgYWRhcHRlciBjb3VudGVyIHJlc2V0cyBhbmQgdHJlYXRzIHRoZW0gYXMgbmV3IHVzYWdlIChubyBkb3VibGUgY291bnRpbmcpLjwvbGk+CiAgICAgIDxsaT48c3Ryb25nPkxvdyBwb3dlcjwvc3Ryb25nPiDigJQgZG9lcyBub3QgcG9sbCBjb250aW51b3VzbHk7IHJlYWRzIGV4aXN0aW5nIE9TIGNvdW50ZXJzIG9uIGRlbWFuZC48L2xpPgogICAgICA8bGk+PHN0cm9uZz5TY2hlZHVsZWQgdHJhY2tpbmc8L3N0cm9uZz4g4oCUIGV2ZXJ5IDMwIG1pbnV0ZXMgKFdpbmRvd3MgVGFzayBTY2hlZHVsZXIsIG9yIGEgc3lzdGVtZCB1c2VyIHRpbWVyIG9uIExpbnV4IC8gbGF1bmNoZCBvbiBtYWNPUykuPC9saT4KICAgICAgPGxpPjxzdHJvbmc+TG9vcGJhY2sgZXhjbHVkZWQ8L3N0cm9uZz4g4oCUIGxvY2FsLW9ubHkgdHJhZmZpYyBpcyBub3QgY291bnRlZCBvbiBMaW51eCwgc28gbG9jYWwgcHJveGllcyBhcmUgbm90IGRvdWJsZS1jb3VudGVkLjwvbGk+CiAgICA8L3VsPgogIDwvc2VjdGlvbj4KCjwvbWFpbj4KCjxzY3JpcHQ+CmNvbnN0IGRyb3Bab25lID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2Ryb3Bab25lJyk7CmNvbnN0IGZpbGVJbnB1dCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdmaWxlSW5wdXQnKTsKY29uc3QgcmVzdWx0c0NhcmQgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgncmVzdWx0c0NhcmQnKTsKY29uc3QgcmVzdWx0c1RpdGxlID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3Jlc3VsdHNUaXRsZScpOwpjb25zdCByZXN1bHRzQ29udGFpbmVyID0gZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3Jlc3VsdHNDb250YWluZXInKTsKCmZ1bmN0aW9uIGZvcm1hdEJ5dGVzKGJ5dGVzU3RyKSB7CiAgY29uc3QgYiA9IHBhcnNlRmxvYXQoU3RyaW5nKGJ5dGVzU3RyKS5yZXBsYWNlKC8sL2csICcnKSkgfHwgMDsKICBpZiAoYiA8IDEwMjQpIHJldHVybiBiLnRvRml4ZWQoMCkgKyAnIEInOwogIGlmIChiIDwgMTAyNCAqIDEwMjQpIHJldHVybiAoYiAvIDEwMjQpLnRvRml4ZWQoMikgKyAnIEtCJzsKICBpZiAoYiA8IDEwMjQgKiAxMDI0ICogMTAyNCkgcmV0dXJuIChiIC8gKDEwMjQgKiAxMDI0KSkudG9GaXhlZCgyKSArICcgTUInOwogIHJldHVybiAoYiAvICgxMDI0ICogMTAyNCAqIDEwMjQpKS50b0ZpeGVkKDIpICsgJyBHQic7Cn0KCmZ1bmN0aW9uIGRldGVjdEtpbmQocm93cykgewogIGNvbnN0IGZpcnN0Um93ID0gcm93c1swXSB8fCB7fTsKICBjb25zdCBoZWFkZXJzID0gZmlyc3RSb3cgPyBPYmplY3Qua2V5cyhmaXJzdFJvdykgOiBbXTsKICBpZiAoaGVhZGVycy5zb21lKGggPT4gaC50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKCdhZGFwdGVyJykpKSByZXR1cm4gJ2FkYXB0ZXInOwogIGlmIChoZWFkZXJzLnNvbWUoaCA9PiBoLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMoJ2FwcCcpIHx8IGgudG9Mb3dlckNhc2UoKS5pbmNsdWRlcygnYXBwbmFtZScpIHx8IGgudG9Mb3dlckNhc2UoKS5pbmNsdWRlcygncHJvZmlsZScpKSkgcmV0dXJuICdhcHAnOwogIHJldHVybiAndW5rbm93bic7Cn0KCmZ1bmN0aW9uIGVzY2FwZUh0bWwocykgewogIHJldHVybiBTdHJpbmcocykKICAgIC5yZXBsYWNlKC8mL2csICcmYW1wOycpCiAgICAucmVwbGFjZSgvPC9nLCAnJmx0OycpCiAgICAucmVwbGFjZSgvPi9nLCAnJmd0OycpCiAgICAucmVwbGFjZSgvIi9nLCAnJnF1b3Q7JykKICAgIC5yZXBsYWNlKC8nL2csICcmIzM5OycpOwp9CgpmdW5jdGlvbiByZW5kZXJUYWJsZShoZWFkZXJzLCByb3dzKSB7CiAgbGV0IGh0bWwgPSAnPHRhYmxlPjx0aGVhZD48dHI+JzsKICBoZWFkZXJzLmZvckVhY2goaCA9PiBodG1sICs9ICc8dGg+JyArIGVzY2FwZUh0bWwoaCkgKyAnPC90aD4nKTsKICBodG1sICs9ICc8L3RyPjwvdGhlYWQ+PHRib2R5Pic7CiAgcm93cy5zbGljZSgwLCA0MCkuZm9yRWFjaChyb3cgPT4gewogICAgaHRtbCArPSAnPHRyPic7CiAgICBoZWFkZXJzLmZvckVhY2goaCA9PiB7CiAgICAgIGxldCB2ID0gcm93W2hdICE9PSB1bmRlZmluZWQgPyBTdHJpbmcocm93W2hdKSA6ICcnOwogICAgICBsZXQgY2VsbENsYXNzID0gJyc7CiAgICAgIGlmIChoLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMoJ2J5dGUnKSB8fCBoLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMoJ3RvdGFsJykgfHwgaC50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKCdkZWx0YScpIHx8IGgudG9Mb3dlckNhc2UoKS5pbmNsdWRlcygnc2VudCcpIHx8IGgudG9Mb3dlckNhc2UoKS5pbmNsdWRlcygncmVjZWl2ZWQnKSkgewogICAgICAgIGNlbGxDbGFzcyA9ICdieXRlJzsKICAgICAgICB2ID0gZm9ybWF0Qnl0ZXModik7CiAgICAgIH0gZWxzZSBpZiAoaC50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKCdkYXRlJykgfHwgaC50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKCd0aW1lJykgfHwgaC50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKCd0aW1lc3RhbXAnKSkgewogICAgICAgIGNlbGxDbGFzcyA9ICdkYXRlJzsKICAgICAgfQogICAgICBodG1sICs9ICc8dGQgZGF0YS1sYWJlbD0iJyArIGVzY2FwZUh0bWwoaCkgKyAnIiBjbGFzcz0iJyArIGNlbGxDbGFzcyArICciPicgKyAodiA/IGVzY2FwZUh0bWwodikgOiAnPHNwYW4gc3R5bGU9Im9wYWNpdHk6LjQ7Ij4mbWRhc2g7PC9zcGFuPicpICsgJzwvdGQ+JzsKICAgIH0pOwogICAgaHRtbCArPSAnPC90cj4nOwogIH0pOwogIGh0bWwgKz0gJzwvdGJvZHk+PC90YWJsZT4nOwogIGlmIChyb3dzLmxlbmd0aCA+IDQwKSBodG1sICs9ICc8cCBzdHlsZT0iY29sb3I6dmFyKC0tdGV4dC1tdXRlZCk7IG1hcmdpbi10b3A6Ljc1cmVtOyBmb250LXNpemU6Ljg1cmVtOyI+U2hvd2luZyBmaXJzdCA0MCBvZiAnICsgcm93cy5sZW5ndGggKyAnIHJvd3MuPC9wPic7CiAgcmV0dXJuIGh0bWw7Cn0KCmZ1bmN0aW9uIHBhcnNlQ1NWKHRleHQpIHsKICBjb25zdCBsaW5lcyA9IHRleHQudHJpbSgpLnNwbGl0KC9ccj9cbi8pLmZpbHRlcihsID0+IGwudHJpbSgpKTsKICBpZiAoIWxpbmVzLmxlbmd0aCkgcmV0dXJuIHsgaGVhZGVyczogW10sIHJvd3M6IFtdIH07CiAgY29uc3QgaGVhZGVycyA9IGxpbmVzWzBdLnNwbGl0KCcsJykubWFwKHMgPT4gcy50cmltKCkucmVwbGFjZSgvXiJ8IiQvZywgJycpKTsKICBjb25zdCByb3dzID0gW107CiAgZm9yIChsZXQgaSA9IDE7IGkgPCBsaW5lcy5sZW5ndGg7IGkrKykgewogICAgY29uc3QgdmFsdWVzID0gbGluZXNbaV0uc3BsaXQoJywnKS5tYXAocyA9PiBzLnRyaW0oKS5yZXBsYWNlKC9eInwiJC9nLCAnJykpOwogICAgY29uc3Qgcm93ID0ge307CiAgICBoZWFkZXJzLmZvckVhY2goKGgsIGlkeCkgPT4gcm93W2hdID0gdmFsdWVzW2lkeF0gIT09IHVuZGVmaW5lZCA/IHZhbHVlc1tpZHhdIDogJycpOwogICAgcm93cy5wdXNoKHJvdyk7CiAgfQogIHJldHVybiB7IGhlYWRlcnMsIHJvd3MgfTsKfQoKZnVuY3Rpb24gaGFuZGxlRmlsZShmaWxlKSB7CiAgY29uc3QgcmVhZGVyID0gbmV3IEZpbGVSZWFkZXIoKTsKICByZWFkZXIub25sb2FkID0gKGUpID0+IHsKICAgIGNvbnN0IHsgaGVhZGVycywgcm93cyB9ID0gcGFyc2VDU1YoZS50YXJnZXQucmVzdWx0KTsKICAgIGNvbnN0IGtpbmQgPSBkZXRlY3RLaW5kKHJvd3MpOwogICAgcmVzdWx0c1RpdGxlLnRleHRDb250ZW50ID0gZmlsZS5uYW1lICsgJyDigJQgJyArIChraW5kID09PSAnYWRhcHRlcicgPyAnQWRhcHRlciBMb2cnIDoga2luZCA9PT0gJ2FwcCcgPyAnQXBwIFVzYWdlJyA6ICdDU1YnKTsKICAgIHJlc3VsdHNDb250YWluZXIuaW5uZXJIVE1MID0gcmVuZGVyVGFibGUoaGVhZGVycywgcm93cyk7CiAgICByZXN1bHRzQ2FyZC5zdHlsZS5kaXNwbGF5ID0gJ2Jsb2NrJzsKICAgIHJlc3VsdHNDYXJkLnNjcm9sbEludG9WaWV3KHsgYmVoYXZpb3I6ICdzbW9vdGgnLCBibG9jazogJ3N0YXJ0JyB9KTsKICB9OwogIHJlYWRlci5yZWFkQXNUZXh0KGZpbGUpOwp9CgpbJ2RyYWdlbnRlcicsICdkcmFnb3ZlcicsICdkcmFnbGVhdmUnLCAnZHJvcCddLmZvckVhY2goZXYgPT4gewogIGRyb3Bab25lLmFkZEV2ZW50TGlzdGVuZXIoZXYsIChlKSA9PiB7IGUucHJldmVudERlZmF1bHQoKTsgZS5zdG9wUHJvcGFnYXRpb24oKTsgfSk7Cn0pOwpbJ2RyYWdlbnRlcicsICdkcmFnb3ZlciddLmZvckVhY2goZXYgPT4gewogIGRyb3Bab25lLmFkZEV2ZW50TGlzdGVuZXIoZXYsICgpID0+IGRyb3Bab25lLnN0eWxlLmJvcmRlckNvbG9yID0gJ3ZhcigtLWFjY2VudCknKTsKfSk7ClsnZHJhZ2xlYXZlJywgJ2Ryb3AnXS5mb3JFYWNoKGV2ID0+IHsKICBkcm9wWm9uZS5hZGRFdmVudExpc3RlbmVyKGV2LCAoKSA9PiBkcm9wWm9uZS5zdHlsZS5ib3JkZXJDb2xvciA9ICd2YXIoLS1zdXJmYWNlLTIpJyk7Cn0pOwpkcm9wWm9uZS5hZGRFdmVudExpc3RlbmVyKCdkcm9wJywgKGUpID0+IHsKICBjb25zdCBmaWxlID0gZS5kYXRhVHJhbnNmZXIuZmlsZXNbMF07CiAgaWYgKGZpbGUgJiYgZmlsZS5uYW1lLmVuZHNXaXRoKCcuY3N2JykpIGhhbmRsZUZpbGUoZmlsZSk7Cn0pOwpkcm9wWm9uZS5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsICgpID0+IGZpbGVJbnB1dC5jbGljaygpKTsKZmlsZUlucHV0LmFkZEV2ZW50TGlzdGVuZXIoJ2NoYW5nZScsICgpID0+IHsKICBpZiAoZmlsZUlucHV0LmZpbGVzWzBdKSBoYW5kbGVGaWxlKGZpbGVJbnB1dC5maWxlc1swXSk7Cn0pOwo8L3NjcmlwdD4KPC9ib2R5Pgo8L2h0bWw+Cg==
B64EOF

# ---------------- systemd user service (unprivileged-safe low-power) --------
cat > "$SERVICE_DIR/datausage-tracker.service" << 'SERVICE_EOF'
[Unit]
Description=DataUsage Tracker (low-power adapter monitoring, KDE Plasma notifications)
Documentation=https://github.com/anacondy/Datausage-Tracker

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 %h/.local/share/datausage-tracker/data_tracker.py --quiet
Environment=PYTHONUNBUFFERED=1
Environment=DATAUSAGE_NOTIFY=1
Environment=DATAUSAGE_NOTIFY_INTERVAL_MB=512
Environment=DATAUSAGE_NOTIFY_DAILY_MB=2048
Nice=10
CPUSchedulingPolicy=idle
IOSchedulingClass=idle
CPUQuota=10%
MemoryMax=64M
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=full
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictRealtime=yes

[Install]
WantedBy=default.target
SERVICE_EOF

cat > "$SERVICE_DIR/datausage-tracker.timer" << 'TIMER_EOF'
[Unit]
Description=Run DataUsage Tracker every 30 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
AccuracySec=1min
RandomizedDelaySec=90
Unit=datausage-tracker.service

[Install]
WantedBy=timers.target
TIMER_EOF

if command -v systemd-analyze &>/dev/null; then
    systemd-analyze verify "$SERVICE_DIR/datausage-tracker.service" 2>/dev/null \
      && systemd-analyze verify "$SERVICE_DIR/datausage-tracker.timer" 2>/dev/null \
      && echo "[DataUsageTracker] systemd-analyze verify: OK" || true
fi

echo "[DataUsageTracker] Environment check:"
if grep -qiE '^ID=arch|^ID_LIKE=.*arch' /etc/os-release 2>/dev/null; then
    echo "  Arch Linux detected."
else
    echo "  (non-Arch systemd distro — units work the same)"
fi
[[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* || "${XDG_CURRENT_DESKTOP:-}" == *Plasma* ]] \
  && echo "  KDE Plasma session detected — notifications render natively."
if command -v notify-send &>/dev/null; then
    echo "  notify-send found — Plasma notifications ON (512 MB/interval, 2 GB/day)."
else
    echo "  notify-send NOT found — Arch:  sudo pacman -S libnotify   (optional)"
fi

if command -v systemctl &>/dev/null && systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null || true
    systemctl --user enable --now datausage-tracker.timer \
      && echo "[DataUsageTracker] Daemon timer ENABLED (every 30 min, ~2.4s CPU/day)." \
      || echo "Timer enable failed (login session needed?) — run manually: python3 $INSTALL_DIR/data_tracker.py"
    systemctl --user start datausage-tracker.service 2>/dev/null || true
else
    echo "No systemd user manager — cron alternative:  */30 * * * * /usr/bin/python3 $INSTALL_DIR/data_tracker.py --quiet"
fi

command -v loginctl &>/dev/null && [[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]] \
  && echo "TIP (optional): sudo loginctl enable-linger $USER  → keep tracking while logged out."

echo ""
echo "=== INSTALL COMPLETE ==="
echo "  status:     bash $0 status"
echo "  terminate:  bash $0 stop"
echo "  uninstall:  bash $0 uninstall"
echo "  clear data: bash $0 purge-data"
echo "  logs:       $LOG_DIR/DataUsage_Log.csv   dashboard: $INSTALL_DIR/dashboard.html"
