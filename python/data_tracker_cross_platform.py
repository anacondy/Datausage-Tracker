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
    """Send a freedesktop notification (KDE Plasma renders these natively)."""
    for cmd in (
        ["notify-send", "--app-name=DataUsage Tracker", "-u", urgency,
         "-i", "network-transmit", summary, body],
        ["kdialog", "--title", "DataUsage Tracker", "--passivepopup",
         f"{summary}\n{body}", "10"],  # KDE-native fallback
    ):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, check=False, timeout=5,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
