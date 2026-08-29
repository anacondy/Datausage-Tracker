#!/usr/bin/env python3
"""
Cross-Platform FindDataHog — Linux / macOS / Windows (Python 3)
Scans browser download folders and user directories for recent large files.
"""

import os, sys, glob, re
from datetime import datetime, timedelta


def get_user_folders():
    folders = []
    user_home = os.path.expanduser("~")
    for sub in ["Downloads", "Desktop", "Documents", "Pictures", "Videos", "Music"]:
        path = os.path.join(user_home, sub)
        if os.path.isdir(path):
            folders.append(path)
    return folders


def get_browser_dirs():
    dirs = []
    local = os.environ.get("LOCALAPPDATA", os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~")))
    # Chrome / Edge / Chromium (Linux/macOS paths)
    chrome_profile = os.path.expanduser("~/.config/google-chrome/Default")
    if os.path.isdir(chrome_profile):
        dirs.append(("Chrome", chrome_profile))
    # Firefox
    firefox_profiles = os.path.expanduser("~/.mozilla/firefox/")
    if os.path.isdir(firefox_profiles):
        # Simplified: scan profile directories
        dirs.append(("Firefox (profiles)", firefox_profiles))
    # Standard downloads
    for user_dir in get_user_folders():
        dirs.append(("Windows/User", user_dir))
    return dirs


def scan_recent_files(root_dirs, days=30, min_size_mb=5):
    min_size = min_size_mb * 1024 * 1024
    cutoff = datetime.utcnow() - timedelta(days=days)
    results = []
    for label, root in root_dirs:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            # Limit depth to avoid extremely deep scans
            if dirpath[len(root):].count(os.sep) > 6:
                dirnames[:] = []
                continue
            for fn in filenames:
                try:
                    full = os.path.join(dirpath, fn)
                    stat = os.stat(full)
                    if stat.st_mtime >= cutoff.timestamp() and stat.st_size >= min_size:
                        results.append({
                            "Path": full,
                            "Name": fn,
                            "Size": stat.st_size,
                            "SizeHuman": format_size(stat.st_size),
                            "Modified": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M"),
                        })
                except (OSError, PermissionError):
                    continue
    results.sort(key=lambda x: x["Size"], reverse=True)
    return results[:40]


def format_size(bytes_size):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(bytes_size) < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


def main():
    print("Cross-Platform FindDataHog — Linux / macOS / Windows (Python 3)")
    root_dirs = get_browser_dirs()
    if not root_dirs:
        print("No scan directories found.")
        return
    print(f"Scanning {len(root_dirs)} root directories (last 30 days, >= 5 MB)...")
    results = scan_recent_files(root_dirs, days=30, min_size_mb=5)
    if not results:
        print("No large recent files found.")
        return
    print(f"\nTop {len(results)} recent large files:")
    for i, r in enumerate(results, 1):
        print(f"  {i}. {r['SizeHuman']:>10}  {r['Path']} (modified {r['Modified']})")


if __name__ == "__main__":
    main()
