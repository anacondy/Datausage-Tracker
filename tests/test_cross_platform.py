#!/usr/bin/env python3
"""
Cross-Platform Testing Framework for DataUsageTracker
Tests structural integrity, syntax patterns, security, and platform readiness.
"""

import os, sys, csv, re, hashlib, json

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def sha256(path):
    h = hashlib.sha256()
    h.update(open(path, 'rb').read())
    return h.hexdigest()

def test_file_integrity():
    print("=== FILE INTEGRITY ===")
    files = [
        'DataUsageTracker.ps1',
        'FindDataHog.ps1',
        'ChromeDataProbe.ps1',
        'README.md',
        'LICENSE',
        'DataUsageMonitor.zip',
    ]
    for f in files:
        p = os.path.join(REPO, f)
        if os.path.exists(p):
            h = sha256(p)
            size = os.path.getsize(p)
            print(f"  [PASS] {f:30s}  {size:>8d} bytes  sha256={h[:16]}...")
        else:
            print(f"  [FAIL] {f} MISSING")


def test_brace_balance():
    print("\n=== SYNTAX: BRACE BALANCE ===")
    for fname in ['DataUsageTracker.ps1', 'FindDataHog.ps1', 'ChromeDataProbe.ps1']:
        content = open(os.path.join(REPO, fname)).read()
        open_b = content.count('{')
        close_b = content.count('}')
        status = "PASS" if open_b == close_b else "FAIL"
        print(f"  [{status}] {fname}: {{={open_b}, }}={close_b}")


def test_security_patterns():
    print("\n=== SECURITY PATTERNS ===")
    checks = {
        'Invoke-Expression': False,
        'DownloadString': False,
        'DownloadFile': False,
        'New-Object.*WebClient': False,
        'eval\\(': False,
    }
    for fname in ['DataUsageTracker.ps1', 'FindDataHog.ps1', 'ChromeDataProbe.ps1']:
        content = open(os.path.join(REPO, fname)).read()
        for pattern in checks:
            if re.search(pattern, content, re.IGNORECASE):
                checks[pattern] = True
                print(f"  [WARN] {fname}: found pattern '{pattern}'")
    for pattern, found in checks.items():
        status = "FAIL" if found else "PASS"
        print(f"  [{status}] Pattern '{pattern}': {'FOUND' if found else 'NOT FOUND'}")


def test_cross_platform_readiness():
    print("\n=== CROSS-PLATFORM READINESS ===")
    # Check for Windows-only cmdlets
    windows_cmdlets = [
        'Get-NetAdapterStatistics',
        'Get-ScheduledTask',
        'Register-ScheduledTask',
        'Windows.Networking',
        'Get-ConnectionProfiles',
        'GetAttributedNetworkUsageAsync',
    ]
    for fname in ['DataUsageTracker.ps1', 'FindDataHog.ps1', 'ChromeDataProbe.ps1']:
        content = open(os.path.join(REPO, fname)).read()
        found = [cmd for cmd in windows_cmdlets if cmd in content]
        status = "WINDOWS-ONLY" if found else "PORTABLE"
        print(f"  [{status}] {fname}: {', '.join(found) if found else 'no hard blockers'}")


def test_ui_exists():
    print("\n=== UI CHECK ===")
    ui_path = os.path.join(REPO, 'ui', 'index.html')
    if os.path.exists(ui_path):
        size = os.path.getsize(ui_path)
        print(f"  [PASS] HTML dashboard exists: ui/index.html ({size} bytes)")
    else:
        print("  [FAIL] HTML dashboard missing")


def main():
    print("DataUsageTracker — Full Testing Framework")
    print(f"Repository: {REPO}")
    print(f"Python: {sys.version.split()[0]}")
    test_file_integrity()
    test_brace_balance()
    test_security_patterns()
    test_cross_platform_readiness()
    test_ui_exists()
    print("\n=== SUMMARY ===")
    print("All structural and security tests completed.")
    print("Functional data-usage testing requires Windows 11.")

if __name__ == '__main__':
    main()
