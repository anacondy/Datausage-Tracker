#!/usr/bin/env python3
"""
Cross-Platform ChromeDataProbe — Linux / macOS / Windows (Python 3)
Inspects browser processes (Chrome/Edge/Firefox) and lists active connections.
Requires psutil for best results.
"""

import os, sys, re
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False


def get_browser_processes():
    procs = []
    if not HAS_PSUTIL:
        print("WARNING: psutil not installed. Limited process inspection available.")
        print("Run: pip install psutil")
        return procs
    for p in psutil.process_iter(attrs=["pid", "name", "cmdline", "memory_info"]):
        try:
            name = p.info.get("name", "") or ""
            cmdline = p.info.get("cmdline") or []
            cmd_str = " ".join(str(c) for c in cmdline).lower()
            if any(x in name.lower() for x in ["chrome", "chromium", "msedge", "brave", "opera", "vivaldi", "firefox"]):
                procs.append({
                    "pid": p.info.get("pid"),
                    "name": p.info.get("name"),
                    "cmdline": cmd_str,
                    "memory_mb": round(p.info.get("memory_info").rss / (1024 * 1024), 1) if p.info.get("memory_info") else 0,
                })
        except (psutil.NoSuchProcess, psutil.AccessDenied, Exception):
            continue
    return procs


def get_connections_for_pids(pids):
    connections = []
    if not HAS_PSUTIL:
        return connections
    for p in psutil.process_iter(attrs=["pid", "connections"]):
        try:
            if p.info.get("pid") in pids:
                for conn in p.info.get("connections", []):
                    if conn.status == psutil.CONN_ESTABLISHED and conn.raddr:
                        connections.append({
                            "pid": p.info.get("pid"),
                            "remote": f"{conn.raddr.ip}:{conn.raddr.port}" if conn.raddr else "unknown",
                        })
        except (psutil.NoSuchProcess, psutil.AccessDenied, Exception):
            continue
    return connections


def main():
    print("Cross-Platform ChromeDataProbe — Linux / macOS / Windows")
    print(f"psutil: {'available' if HAS_PSUTIL else 'NOT INSTALLED'}")
    print()

    procs = get_browser_processes()
    if not procs:
        print("No Chrome / Edge / Brave / Opera / Firefox processes found.")
        print("If a browser is running, ensure psutil can see it (may need admin rights).")
        return

    print(f"Browser processes found: {len(procs)}")
    print(f"{'PID':<8} {'Name':<15} {'Memory (MB)':<15} {'Notes'}")
    print("-" * 60)
    for proc in procs:
        note = ""
        if "chrome" in proc["name"].lower() and "renderer" not in proc["cmdline"]:
            note = "main process"
        elif "chrome" in proc["cmdline"] and ("gpu" in proc["cmdline"] or "type=gpu" in proc["cmdline"]):
            note = "GPU process"
        print(f"{proc['pid']:<8} {proc['name']:<15} {proc['memory_mb']:<15.1f} {note}")

    print()

    pids = {p["pid"] for p in procs}
    conns = get_connections_for_pids(pids)
    print(f"Active established connections: {len(conns)}")
    if conns:
        for c in conns[:20]:
            print(f"  PID {c['pid']} -> {c['remote']}")
    else:
        print("  (No established connections visible — may need admin rights / psutil permissions)")

    print()
    print("Reminder: The best per-tab network data lives inside Chrome itself:")
    print("  Press Shift+Esc while Chrome is open to see Chrome's own Task Manager.")


if __name__ == "__main__":
    main()
