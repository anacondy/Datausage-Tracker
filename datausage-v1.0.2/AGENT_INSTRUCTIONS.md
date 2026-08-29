# AGENT INSTRUCTIONS — ship v1.0.2 on anacondy/Datausage-Tracker

You are receiving this package to finish the release. Work on branch
**`arena/01a04ccb-datausage-tracker`** (tip `9b4c521`, "Apply audit fixes v1.0.1").
Do NOT touch `main` directly; a PR from this branch to main is the goal.

Everything here was already built and verified (28/28 functional tests, live
kernel-calibration of the tracker, `systemd-analyze verify`, full installer
lifecycle, checksummed payloads). Your job: apply, re-verify, push, publish.

---

## Step 1 — Get the branch locally

```bash
git clone https://github.com/anacondy/Datausage-Tracker.git
cd Datausage-Tracker
git checkout arena/01a04ccb-datausage-tracker
```

## Step 2 — Apply v1.0.2 (choose ONE)

**Option A (preferred):**
```bash
git apply --3way /path/to/v1.0.2-residual-fixes.patch
```

**Option B:** copy the contents of `repo-overwrite/` over the repo root
(paths match the repo layout exactly).

Files that change: `python/data_tracker_cross_platform.py`,
`deploy/linux/install.sh`, `deploy/windows/install.ps1`, `deploy/README.md`,
`README.md`, `tests/test_delta_methodology.py`,
`docs/TESTING_FAILURE_MODES.md`, `docs/linux_scheduling.md`,
`releases/RELEASE_NOTES.md`, `FIXES_APPLIED.md`, and the three
`releases/<os>/DataUsageTracker-v1.0.2-*` archives (new; the v1.0.1 archives
may be removed as superseded, or kept — your call, v1.0.1 wasn't broken).

## Step 3 — Re-verify (must all pass before committing)

```bash
python3 -m py_compile python/*.py tests/*.py
python3 tests/test_delta_methodology.py        # 28 passed, 0 failed
bash -n deploy/linux/install.sh
node --check <(sed -n '/<script>/,/<\/script>/p' ui/index.html | sed '1d;$d')
cd releases/*/ 2>/dev/null; sha256sum -c /path/to/release-assets/SHA256SUMS.txt
```

Live Linux sanity (if on a Linux box):
```bash
DATAUSAGE_LOG_DIR=/tmp/dut-test python3 python/data_tracker_cross_platform.py
cat /tmp/dut-test/DataUsage_Log.csv            # one header + rows, deltas present
```

## Step 4 — Commit & push

```bash
git add -A
git commit -m "v1.0.2: notification exit-code honesty + fallback chain, Persistent no-op removed (docs+timer), Windows installer fail-fast, import-environment, tests 26->28, rebuilt archives"
git push origin arena/01a04ccb-datausage-tracker
```

## Step 5 — Publish the GitHub Release v1.0.2

If `gh` is authenticated:
```bash
gh release create v1.0.2 --repo anacondy/Datausage-Tracker \
  --target arena/01a04ccb-datausage-tracker \
  --title "DataUsageTracker v1.0.2 — release-ready (Linux/Windows/macOS)" \
  --notes-file release-assets/RELEASE_NOTES_v1.0.2.md

gh release upload v1.0.2 --repo anacondy/Datausage-Tracker \
  release-assets/install-linux.sh release-assets/install-macos.sh \
  release-assets/install-windows.ps1 \
  release-assets/DataUsageTracker-v1.0.2-linux.tar.gz \
  release-assets/DataUsageTracker-v1.0.2-macos.tar.gz \
  release-assets/DataUsageTracker-v1.0.2-windows.zip \
  release-assets/SHA256SUMS.txt
```

If `gh` is NOT available: tell the user to do it in the browser —
**Releases → Draft a new release → tag `v1.0.2` (target: the branch) → paste
`RELEASE_NOTES_v1.0.2.md` → upload the 7 files in `release-assets/` → Publish.**

The user's one-liners go LIVE at this moment:
```bash
curl -fsSL https://github.com/anacondy/Datausage-Tracker/releases/download/v1.0.2/install-linux.sh | bash
```

## Step 6 — PR & wrap-up

- Open PR: `arena/01a04ccb-datausage-tracker` → `main`, title
  "v1.0.2 — release-ready build (audit fixes + hardened installers)".
- Post-publish smoke test (any machine):
  `curl -fsSL <release-asset-url>/install-linux.sh | bash` then
  `bash install-linux.sh status` (downloaded copy) and confirm
  `~/DataUsageLogs/DataUsage_Log.csv` gets a row from
  `systemctl --user start datausage-tracker.service`.
- Report back: commit SHA, release URL, test output summary.

## Known-good facts (verified, do not re-litigate)

- Windows/macOS sides can't be executed in a Linux sandbox — they are code-reviewed
  and their payloads are byte-verified; flag anything odd on the first real run.
- The Linux installer degrades gracefully without a systemd user manager (prints
  a cron fallback) — that's expected in containers.
- `Nice=10` + idle scheduling is intentional (unprivileged services cannot set
  negative nice — v1.0.0's `Nice=-5` was a no-op; see FIXES_APPLIED.md #4).
- Inherent limits stay documented: per-app tracking is Windows-only (SRUM),
  VPN traffic double-counts across adapters, SRUM keeps ~30 days of per-app data.
