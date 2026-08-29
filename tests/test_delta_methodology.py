#!/usr/bin/env python3
"""
Functional tests for the v1.0.1 Linux/macOS tracker and dashboard.

Unlike tests/test_cross_platform.py (structural checks), this suite EXECUTES
the counting logic against synthetic /proc/net/dev data and reproduces the
adversarial scenarios from AUDIT_REPORT.md §4:

  • steady accumulation          → exact deltas
  • reboot (counter reset)       → counts only since-boot bytes
  • adapter disappears / rejoins → baseline preserved, delta exact
  • 15 s dedup guard             → no duplicate row
  • loopback excluded
  • CSV appends, never overwrites; columns identical to the Windows log
  • baseline.json valid JSON, atomic write leaves no .tmp behind
  • dashboard JS parses (node --check) and escapes HTML

Run:  python3 tests/test_delta_methodology.py
Exits non-zero on any failure.
"""

import os
import re
import sys
import json
import shutil
import subprocess
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "python"))

import data_tracker_cross_platform as dt  # noqa: E402

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name}  {detail}")


def make_proc(path, ifaces):
    """Write a synthetic /proc/net/dev. ifaces: {name: (rx_bytes, tx_bytes)}."""
    lines = [
        "Inter-|   Receive                                                |  Transmit",
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
    ]
    for name, (rx, tx) in ifaces.items():
        lines.append(
            f"{name}: {rx}    100    0    0    0     0          0         0"
            f"   {tx}    100    0    0    0    0       0          0"
        )
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def read_csv(path):
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    header = lines[0].split(",")
    rows = [dict(zip(header, l.split(","))) for l in lines[1:]]
    return header, rows


class Env:
    """Isolated log dir + synthetic /proc/net/dev."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="dut_test_")
        self.log_dir = os.path.join(self.dir, "logs")
        self.proc = os.path.join(self.dir, "net_dev")
        os.environ["DATAUSAGE_LOG_DIR"] = self.log_dir
        os.environ.pop("DATAUSAGE_NOTIFY", None)  # notifications off in tests
        os.environ.pop("DATAUSAGE_INCLUDE_LOOPBACK", None)

    def run(self, ifaces, dedup=0):
        make_proc(self.proc, ifaces)
        return dt.log_point(log_dir=self.log_dir, proc_path=self.proc,
                            dedup_seconds=dedup, quiet=True, notify=False)

    def rows(self):
        return read_csv(os.path.join(self.log_dir, dt.CSV_NAME))[1]

    def cleanup(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def test_accumulation_and_deltas():
    print("=== ACCUMULATION / DELTAS ===")
    e = Env()
    try:
        check("first run writes a row (no overwrite-era emptiness)",
              e.run({"eth0": (1_000_000, 500_000)}))
        rows = e.rows()
        check("first run = since-boot values (by design)",
              len(rows) == 1 and rows[0]["Total_Delta"] == "1500000",
              str(rows))

        check("immediate second run is skipped (dedup guard)",
              e.run({"eth0": (1_000_000, 500_000)}, dedup=15) is False)
        check("dedup skip wrote no row", len(e.rows()) == 1)

        check("steady growth logged",
              e.run({"eth0": (1_200_000, 510_000)}))
        rows = e.rows()
        last = rows[-1]
        check("exact delta computed vs baseline",
              last["Received_Delta"] == "200000" and
              last["Sent_Delta"] == "10000" and
              last["Total_Delta"] == "210000", str(last))
        check("CSV appends (now 2 rows)", len(rows) == 2)
        check("lifetime = boot + delta",
              last["Lifetime_Total"] == "1710000", str(last))
    finally:
        e.cleanup()


def test_reboot_safety():
    print("=== REBOOT-SAFE DELTAS ===")
    e = Env()
    try:
        e.run({"wlan0": (2_000_000, 1_000_000)})
        # reboot: counters reset to small since-boot values
        e.run({"wlan0": (300_000, 50_000)})
        rows = e.rows()
        last = rows[-1]
        check("counter reset detected; whole current value counted once",
              last["Total_Delta"] == "350000", str(last))
        check("no negative delta, no double count of pre-reboot bytes",
              int(last["Received_Delta"]) == 300_000 and
              int(last["Sent_Delta"]) == 50_000)
        check("lifetime survives reboot (monotonic)",
              last["Lifetime_Total"] == "3350000", str(last))
    finally:
        e.cleanup()


def test_adapter_disappear_rejoin():
    print("=== ADAPTER DISAPPEAR / REJOIN (hotspot off/on) ===")
    e = Env()
    try:
        e.run({"eth0": (100_000, 10_000), "usb0": (500_000, 200_000)})
        e.run({"eth0": (150_000, 11_000)})            # usb0 gone (unplugged)
        e.run({"eth0": (160_000, 12_000),
               "usb0": (600_000, 210_000)})           # usb0 back
        rows = e.rows()
        usb_last = [r for r in rows if r["Adapter"] == "usb0"][-1]
        check("rejoined adapter resumes from stored baseline (exact delta)",
              usb_last["Total_Delta"] == "110000", str(usb_last))
        check("absent adapter wrote no row while gone",
              sum(1 for r in rows if r["Adapter"] == "usb0") == 2)
    finally:
        e.cleanup()


def test_loopback_excluded():
    print("=== LOOPBACK EXCLUDED ===")
    e = Env()
    try:
        e.run({"lo": (999_999, 999_999), "eth0": (1000, 500)})
        rows = e.rows()
        check("lo not logged by default (no double-count with local proxy)",
              all(r["Adapter"] != "lo" for r in rows), str(rows))
        os.environ["DATAUSAGE_INCLUDE_LOOPBACK"] = "1"
        e.run({"lo": (2_000_000, 2_000_000), "eth0": (1000, 500)})
        check("lo can be opted back in via env",
              any(r["Adapter"] == "lo" for r in e.rows()))
        os.environ.pop("DATAUSAGE_INCLUDE_LOOPBACK", None)
    finally:
        e.cleanup()


def test_state_files():
    print("=== STATE FILES (baseline / dedup / atomicity) ===")
    e = Env()
    try:
        e.run({"eth0": (10, 20)})
        base = os.path.join(e.log_dir, dt.BASELINE_NAME)
        data = json.load(open(base))
        check("baseline.json valid JSON with adapters+lifetime",
              "Adapters" in data and "Lifetime" in data and
              data["Adapters"]["eth0"]["Received"] == 10)
        leftovers = [f for f in os.listdir(e.log_dir) if f.endswith(".tmp")]
        check("atomic write leaves no .tmp files", not leftovers, str(leftovers))
        state = json.load(open(os.path.join(e.log_dir, dt.LAST_RUN_NAME)))
        check("dedup state (LastLogUtc) recorded", "LastLogUtc" in state)
    finally:
        e.cleanup()


def test_csv_matches_windows_columns():
    print("=== CSV COLUMNS IDENTICAL TO WINDOWS DataUsage_Log.csv ===")
    e = Env()
    try:
        e.run({"eth0": (1, 2)})
        header, rows = read_csv(os.path.join(e.log_dir, dt.CSV_NAME))
        expected = ["TimestampIST", "DateIST", "TimeIST", "Adapter",
                    "Received_Delta", "Sent_Delta", "Total_Delta",
                    "Lifetime_Received", "Lifetime_Sent", "Lifetime_Total"]
        check("header matches the Windows log (dashboard compatibility)",
              header == expected, str(header))
        check("DateIST is an ordinal date",
              re.match(r"^\d{1,2}(st|nd|rd|th) \w+ \d{4}$",
                       rows[0]["DateIST"]) is not None, rows[0]["DateIST"])
        check("TimeIST is 12-hour IST time",
              re.match(r"^\d{2}:\d{2}:\d{2} (AM|PM)$",
                       rows[0]["TimeIST"]) is not None, rows[0]["TimeIST"])
    finally:
        e.cleanup()


def test_ist_offset():
    print("=== IST TIMEZONE ===")
    from datetime import datetime, timezone
    offset = dt.ist_now().utcoffset() - datetime.now(timezone.utc).utcoffset()
    check("IST = UTC+5:30", offset.total_seconds() == 5.5 * 3600, str(offset))


def test_dashboard():
    print("=== DASHBOARD (ui/index.html) ===")
    html = open(os.path.join(REPO, "ui", "index.html")).read()
    m = re.search(r"<script>(.*)</script>", html, re.S)
    check("script block found", m is not None)
    js = m.group(1)
    # The v1.0.0 bug was a literal backslash-n token after a semicolon,
    # outside any string/regex (the legit /\r?\n/ regex has no ';' before it).
    check("no stray literal \\n token in JS (the v1.0.0 SyntaxError)",
          not re.search(r";\s*\\n", js))
    check("escapeHtml covers &, <, > and quotes",
          all(p in js for p in ["&amp;", "&lt;", "&gt;", "&quot;"]))

    node = shutil.which("node")
    if node:
        tmp = tempfile.NamedTemporaryFile("w", suffix=".js", delete=False)
        tmp.write(js)
        tmp.close()
        r = subprocess.run([node, "--check", tmp.name],
                           capture_output=True, text=True)
        check("node --check: dashboard JS parses", r.returncode == 0,
              r.stderr[:200])
        os.unlink(tmp.name)
    else:
        print("  [SKIP] node not available — JS syntax check skipped")


def main():
    print("DataUsageTracker — delta methodology functional tests")
    print(f"Python {sys.version.split()[0]}, repo {REPO}\n")
    test_accumulation_and_deltas()
    test_reboot_safety()
    test_adapter_disappear_rejoin()
    test_loopback_excluded()
    test_state_files()
    test_csv_matches_windows_columns()
    test_ist_offset()
    test_dashboard()
    print(f"\n=== SUMMARY: {PASS} passed, {FAIL} failed ===")
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
