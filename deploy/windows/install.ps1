# One-line install for Windows (PowerShell / CMD)
# Usage (PowerShell): iwr -useb https://github.com/anacondy/Datausage-Tracker/raw/arena/01a04ccb-datausage-tracker/deploy/windows/install.ps1 | iex
# Usage (CMD): powershell -Command "Invoke-Expression (Invoke-WebRequest -Uri 'https://...' -UseBasicParsing).Content"

[CmdletBinding()]
param(
    [string]$InstallDir = "$env:USERPROFILE\DataUsageTracker",
    [switch]$Quiet
)

$RepoUrl = "https://github.com/anacondy/Datausage-Tracker"
$Branch = "arena/01a04ccb-datausage-tracker"

Write-Host "[DataUsageTracker Windows Install] Installing to $InstallDir ..." -ForegroundColor Cyan

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Download core scripts from the PR branch
$files = @(
    "DataUsageTracker.ps1",
    "FindDataHog.ps1",
    "ChromeDataProbe.ps1",
    "README.md",
    "LICENSE"
)

foreach ($f in $files) {
    $uri = "$RepoUrl/raw/$Branch/$f"
    $out = Join-Path $InstallDir $f
    if (-not $Quiet) { Write-Host "  Downloading $f ..." }
    Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $out -ErrorAction SilentlyContinue
}

# Download docs, tests, dashboard
New-Item -ItemType Directory -Path (Join-Path $InstallDir "docs") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallDir "tests") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallDir "ui") -Force | Out-Null

Invoke-WebRequest -Uri "$RepoUrl/raw/$Branch/docs/SECURITY_AUDIT.md" -UseBasicParsing -OutFile (Join-Path $InstallDir "docs\SECURITY_AUDIT.md") -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri "$RepoUrl/raw/$Branch/docs/METHODOLOGY_TEST_REPORT.md" -UseBasicParsing -OutFile (Join-Path $InstallDir "docs\METHODOLOGY_TEST_REPORT.md") -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri "$RepoUrl/raw/$Branch/ui/index.html" -UseBasicParsing -OutFile (Join-Path $InstallDir "ui\index.html") -ErrorAction SilentlyContinue

# Register scheduled task (low-power tracker running every 30 min) — the daemon
$TaskName = "DataUsageTracker"
$ScriptPath = Join-Path $InstallDir "DataUsageTracker.ps1"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Log -Quiet"
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn
$TriggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    if (-not $Quiet) { Write-Host "  Scheduled task '$TaskName' already exists — updating." -ForegroundColor Yellow }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Description "Low-power Windows data usage tracker (daemon) — logs every 30 min in IST." -Action $Action -Trigger @($TriggerLogon, $TriggerRepeat) -Settings $Settings -Force -User $env:USERNAME | Out-Null

if (-not $Quiet) {
    Write-Host "  Scheduled daemon registered (every 30 min + at logon)." -ForegroundColor Green
}

# Create .bat launcher for convenience
$batContent = '@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DataUsageTracker.ps1" -Snapshot
pause'
Set-Content -Path (Join-Path $InstallDir "Run-Tracker.bat") -Value $batContent

if (-not $Quiet) {
    Write-Host ""
    Write-Host "=== INSTALL COMPLETE ===" -ForegroundColor Green
    Write-Host "Install dir: $InstallDir"
    Write-Host "Scheduled daemon: $TaskName"
    Write-Host "Dashboard: open $InstallDir\ui\index.html in any browser"
    Write-Host "Uninstall: Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false; Remove-Item -Recurse -Force $InstallDir"
}
