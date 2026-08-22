#!/usr/bin/env python3
"""
Cross-Platform Data Usage Tracker — Linux / macOS Alternative
Uses standard library + optional psutil for adapter monitoring.
Not a full replacement for Windows WinRT per-app tracking,
but provides adapter-level usage tracking and CSV logging.
"""

import os, sys, csv, json, time, glob
from datetime import datetime, timezone

# Optional: psutil provides nicer cross-platform adapter stats
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False


def get_ist_now():
    """Return current time formatted for Indian Standard Time (approx UTC+5:30)."""
    now = datetime.now(timezone.utc)
    # Rough IST conversion without zoneinfo database dependency
    ist_offset = 5.5  # hours
    ist_hour = (now.hour + int(ist_offset)) % 24
    ist_day = now.day + (1 if (now.hour + int(ist_offset) + (now.minute / 60.0)) >= 24 else 0)
    # Simplified representation
    return now.strftime(f"%Y-%m-%d %H:%M:%S IST (approx)")


def read_adapter_stats_linux():
    """Read /proc/net/dev for adapter byte counters (Linux)."""
    adapters = {}
    try:
        with open("/proc/net/dev", "r") as f:
            lines = f.readlines()[2:]  # skip headers
            for line in lines:
                parts = line.split(":")
                if len(parts) < 2:
                    continue
                iface = parts[0].strip()
                stats = parts[1].strip().split()
                if iface in ("lo",):  # skip loopback for this use case, or include optionally
                    pass
                # stats: bytes packets errs drop fifo frame compressed multicast
                # index mapping varies by kernel version; attempt best-effort
                try:
                    received_bytes = int(stats[0])
                    sent_bytes = int(stats[8]) if len(stats) > 8 else 0
                    adapters[iface] = {
                        "Adapter": iface,
                        "Received": received_bytes,
                        "Sent": sent_bytes,
                        "Total": received_bytes + sent_bytes,
                        "Status": "Up",
                    }
                except (IndexError, ValueError):
                    continue
    except FileNotFoundError:
        pass
    return adapters


def read_adapter_stats_macos():
    """Placeholder for macOS adapter stats (would use netstat -ib or psutil)."""
    adapters = {}
    if HAS_PSUTIL:
        try:
            counters = psutil.net_io_counters(pernic=True)
            for iface, stats in counters.items():
                adapters[iface] = {
                    "Adapter": iface,
                    "Received": stats.bytes_recv,
                    "Sent": stats.bytes_sent,
                    "Total": stats.bytes_recv + stats.bytes_sent,
                    "Status": "Up",
                }
        except Exception:
            pass
    return adapters


def get_adapter_totals():
    if sys.platform == "linux":
        return list(read_adapter_stats_linux().values())
    elif sys.platform == "darwin":
        return list(read_adapter_stats_macos().values())
    else:
        # Fallback: try psutil on any platform
        adapters = {}
        if HAS_PSUTIL:
            try:
                counters = psutil.net_io_counters(pernic=True)
                for iface, stats in counters.items():
                    adapters[iface] = {
                        "Adapter": iface,
                        "Received": stats.bytes_recv,
                        "Sent": stats.bytes_sent,
                        "Total": stats.bytes_recv + stats.bytes_sent,
                        "Status": "Up",
                    }
            except Exception:
                pass
        return list(adapters.values())


def format_bytes(num_bytes):
    if num_bytes < 0:
        num_bytes = 0
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:.2f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.2f} PB"


def main():
    print("Cross-Platform Data Usage Tracker — Linux/macOS Alternative")
    print(f"Platform: {sys.platform}")
    print(f"psutil available: {HAS_PSUTIL}")
    print(f"Time: {get_ist_now()}")
    print()

    adapters = get_adapter_totals()
    if not adapters:
        print("No adapter statistics available.")
        print("On Linux, ensure you have read access to /proc/net/dev.")
        print("On macOS, install psutil for better results: pip install psutil")
        return

    print("Adapter Statistics (current):")
    print(f"{'Adapter':<20} {'Status':<8} {'Received':<15} {'Sent':<15} {'Total':<15}")
    print("-" * 75)
    for a in adapters:
        print(
            f"{a['Adapter']:<20} {a['Status']:<8} "
            f"{format_bytes(a['Received']):<15} {format_bytes(a['Sent']):<15} {format_bytes(a['Total']):<15}"
        )

    # Write CSV for dashboard compatibility
    log_dir = os.path.expanduser("~/DataUsageLogs")
    os.makedirs(log_dir, exist_ok=True)
    csv_path = os.path.join(log_dir, "CrossPlatform_Adapter.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["TimestampIST", "Adapter", "Status", "Received", "Sent", "Total"])
        for a in adapters:
            writer.writerow([
                datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                a["Adapter"],
                a["Status"],
                a["Received"],
                a["Sent"],
                a["Total"],
            ])
    print()
    print(f"CSV written to: {csv_path}")
    print("Note: Per-app usage (WinRT SRUM) is Windows-only. This script provides adapter-level tracking only.")


if __name__ == "__main__":
    main()
