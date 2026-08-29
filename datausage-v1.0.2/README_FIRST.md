# README FIRST — DataUsageTracker v1.0.2 package

This zip contains everything needed to get **v1.0.2 (release-ready)** onto the
`arena/01a04ccb-datausage-tracker` branch and published. Hand it to your coding
agent in VS Code — `AGENT_INSTRUCTIONS.md` tells it exactly what to do.

## What's inside

```
datausage-v1.0.2/
├── README_FIRST.md              ← you are here
├── AGENT_INSTRUCTIONS.md        ← exact steps for the agent (apply → verify → push → release)
├── v1.0.2-residual-fixes.patch  ← Option A: apply with one git command (preferred)
├── repo-overwrite/              ← Option B: copy these files over the repo root (same layout)
│   ├── FIXES_APPLIED.md                     (updated with the v1.0.2 addendum)
│   ├── README.md                            (Persistent wording fixed)
│   ├── python/data_tracker_cross_platform.py  (notification exit-code honesty + makedirs guard)
│   ├── deploy/linux/install.sh               (Persistent no-op removed, import-environment, header fix)
│   ├── deploy/windows/install.ps1            (fail-fast downloads + pre-registration guard)
│   ├── deploy/README.md                      (Persistent wording fixed)
│   ├── tests/test_delta_methodology.py       (now 28 checks — 2 new notification tests)
│   ├── docs/TESTING_FAILURE_MODES.md         (accurate timer description)
│   ├── docs/linux_scheduling.md              (accurate timer example)
│   ├── releases/RELEASE_NOTES.md             (v1.0.2 section added)
│   └── releases/{linux,macos,windows}/DataUsageTracker-v1.0.2-*  (rebuilt archives)
└── release-assets/              ← upload these to the GitHub Release v1.0.2
    ├── install-linux.sh         (self-contained one-line installer)
    ├── install-macos.sh         (self-contained one-line installer)
    ├── install-windows.ps1      (self-contained one-line installer)
    ├── DataUsageTracker-v1.0.2-{linux,macos,windows}.*  (source archives)
    ├── RELEASE_NOTES_v1.0.2.md  (paste as the release description)
    └── SHA256SUMS.txt           (integrity file for the release page)
```

## What v1.0.2 changes vs the branch (v1.0.1)

1. **Notification delivery verified by exit code** (a failing `notify-send` used to
   be recorded as delivered, silently swallowing the alert) + fallback chain
   `notify-send --app-name` → `notify-send` → `kdialog` + 2 new tests (26 → 28).
2. **`Persistent=true` removed everywhere** — it only affects `OnCalendar=` timers,
   so it was a no-op on this monotonic timer (docs now explain the real behavior).
3. **Windows installer fails loudly** on a failed download and verifies the script
   exists *before* registering the scheduled task.
4. Notifications environment import for X11 sessions (`systemctl --user import-environment`).
5. Docs made accurate; archives rebuilt; SHA256SUMS regenerated.

Everything else (the v1.0.1 core: delta methodology, rejoin fix, dashboard, units,
installer lifecycle) is untouched — it was audit-verified sound.

## Quick verification (already done before zipping, re-runnable anywhere)

```bash
python3 -m py_compile python/*.py tests/*.py
bash -n deploy/linux/install.sh
python3 tests/test_delta_methodology.py          # expect: 28 passed, 0 failed
node --check <(sed -n '/<script>/,/<\/script>/p' ui/index.html | sed '1d;$d')
cd release-assets && sha256sum -c SHA256SUMS.txt
```
