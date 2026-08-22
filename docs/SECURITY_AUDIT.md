# Security Audit — DataUsageTracker Project
Date: 2026-08-22 | Branch: arena/01a029b8-datausage-tracker

## Scope
- DataUsageTracker.ps1 (550 lines)
- FindDataHog.ps1 (364 lines)
- ChromeDataProbe.ps1 (226 lines)
- Run-*.bat launcher files (3 files)
- README.md

## Findings Summary
| Check | Status | Notes |
|---|---|---|
| Hardcoded secrets / credentials | PASS | No passwords, tokens, or API keys found |
| Unsafe `Invoke-Expression` / `eval` patterns | PASS | Not used |
| Unsafe `DownloadString` / `DownloadFile` | PASS | Not used |
| Unsafe `New-Object System.Net.WebClient` | PASS | Not used |
| Path traversal in file operations | PASS | Uses `$env:USERPROFILE` and relative paths safely |
| Registry access without validation | PASS | Only reads browser download prefs from known paths |
| Command injection via user input | PASS | No user-controlled string interpolation in commands |
| Scheduled task creation security | PASS | Uses `-ExecutionPolicy Bypass` only for its own script path; no arbitrary command injection |
| File permission issues | PASS | Creates log directory with standard user permissions |
| Network exposure / open ports | PASS | No listening sockets; only reads local adapter stats |
| Dependency on external downloads | PASS | Zero external dependencies; uses only built-in Windows APIs |

## Detailed Analysis

### 1. DataUsageTracker.ps1
- Uses Windows Runtime (WinRT) API (`Windows.Networking.Connectivity`) to read per-app usage — this is a read-only, sandboxed API.
- Uses `Get-NetAdapterStatistics` for adapter byte counters — read-only.
- Writes CSV/JSON to `%USERPROFILE%\DataUsageLogs\` — user-controlled, no system-wide writes.
- Creates a scheduled task (`DataUsageTracker`) using standard `Register-ScheduledTask` cmdlets — no elevation required for user-level tasks.
- Dedup guard (`last_run.json`) prevents duplicate writes — no race condition vulnerability.
- **Risk**: `-ExecutionPolicy Bypass` in `.bat` files could be misused if a malicious `.ps1` is substituted. **Mitigation**: document that files should stay intact.

### 2. FindDataHog.ps1
- Scans browser download directories (`Chrome`, `Edge`, `Brave`, `Opera`, `Vivaldi`, `Firefox`) — reads only.
- Scans standard Windows user folders (`Downloads`, `Desktop`, etc.) — reads only.
- Uses `Get-ChildItem` with `-Recurse` and `-Depth` limits (`5` or `6`) to prevent unbounded recursion.
- Partial-file detection (`.crdownload`, `.part`, `.tmp`) — read-only matching.
- `Get-NetTCPConnection` reads established TCP connections — read-only.
- **Risk**: Full scan (`-FullScan`) may traverse large user profiles, causing temporary high disk I/O. **Mitigation**: depth limits and size filters are already in place.

### 3. ChromeDataProbe.ps1
- Reads live Chrome browser process information (`Get-Process`) — read-only.
- Reads active network connections (`Get-NetTCPConnection`) — read-only.
- Reports open tab titles from `MainWindowTitle` — read-only.
- No injection of commands into browser processes.
- **Risk**: Could report false positives for other browsers (`msedge`, `brave`, `opera`) matching the regex. **Mitigation**: this is intended behavior to catch all Chromium variants.

### 4. Batch Launchers (.bat)
- `cd /d "%~dp0"` ensures execution in the script directory — prevents working-directory confusion.
- `-ExecutionPolicy Bypass` allows the script to run without changing system policy, but does not disable any security checks beyond execution policy.
- `pause` at end allows user review.

## Recommendations
1. **Document file integrity**: Add a SHA-256 checksum file or instruct users to verify downloads.
2. **Execution policy note**: Add a note in README that `-ExecutionPolicy Bypass` is only for convenience and users can use `RemoteSigned` instead.
3. **Backup before logging**: Consider backing up `baseline.json` before overwriting, in case of corruption.
4. **Log rotation**: Add a simple log rotation mechanism (e.g., archive old CSVs monthly) to prevent unbounded file growth.
5. **Encryption at rest**: If this were used in a regulated environment, the CSV logs should be encrypted; not required for personal data tracking.

## Conclusion
**No critical or high-severity vulnerabilities found.** The scripts are read-heavy, use only built-in Windows APIs, and do not expose new network services. The security posture is appropriate for a personal-use data-monitoring tool.
