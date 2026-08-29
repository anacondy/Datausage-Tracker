<#
====================================================================================
  ChromeDataProbe.ps1  —  Diagnose what Chrome is doing with your data
====================================================================================
  Windows' per-app usage screen often shows a big "chrome.exe" total but can't tell
  you WHICH tab / extension / background task is eating it.  This script inspects the
  live Chrome process tree on your PC to show:

    • every Chrome process, its memory, and (where possible) live network activity
    • the OPEN TAB titles (so you can see what is sitting there streaming)
    • which processes have ACTIVE internet connections right now (remote IP/host)
    • background things Chrome is known to do that silently eat data, with checks

  All times IST, 12-hour clock, ordinal dates ("6th August 2026 at 03:42:15 PM").

  IMPORTANT: the single best tool is Chrome's OWN task manager — press Shift+Esc while
  Chrome is open.  It shows REAL-TIME network bytes per tab/extension, which is exactly
  the "which tab is downloading" answer you want.  This script complements that by
  giving you the process map, tab titles and live connections from PowerShell.

  USAGE
  -----
     .\ChromeDataProbe.ps1                    # full probe (recommended)
     .\ChromeDataProbe.ps1 -Tabs              # just the open tab titles + memory
     .\ChromeDataProbe.ps1 -Connections       # just active network connections
     .\ChromeDataProbe.ps1 -RefreshSeconds 5  # live-monitor connections for a while
====================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Tabs,
    [switch]$Connections,
    [int]$RefreshSeconds = 0
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---- IST helpers --------------------------------------------------------------
function Get-IST([datetime]$utc) {
    if ($utc.Kind -eq 'Unspecified') { $utc = [datetime]::SpecifyKind($utc, 'Utc') }
    if ($utc.Kind -ne 'Utc') { $utc = $utc.ToUniversalTime() }
    try { return [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($utc, 'India Standard Time') }
    catch { return $utc.AddHours(5).AddMinutes(30) }
}
function Format-OrdinalDate([datetime]$dt) {
    $day = $dt.Day; $m = $day % 100
    if ($m -ge 11 -and $m -le 13) { $suf = 'th' } else {
        switch ($day % 10) { 1 {$suf='st'} 2 {$suf='nd'} 3 {$suf='rd'} default {$suf='th'} }
    }
    return "$day$suf $($dt.ToString('MMMM')) $($dt.Year)"
}
function Format-Size([int64]$bytes) {
    if ($bytes -lt 0) { $bytes = 0 }
    $u=@('B','KB','MB','GB','TB'); $i=0; $v=[double]$bytes
    while ($v -ge 1024 -and $i -lt 4) { $v/=1024; $i++ }
    return ('{0:N1} {1}' -f $v, $u[$i])
}
function Get-HostName([string]$ip) {
    try {
        $h = [System.Net.Dns]::GetHostEntry($ip).HostName
        if ($h -and $h -notmatch '\.$') { return $h }
    } catch { }
    return $ip
}

# IMPORTANT: see docs/ for full audit reports. HTML dashboard: ui/index.html
# ---- gather Chrome processes --------------------------------------------------
function Get-ChromeProcesses {
    Get-Process | Where-Object {
        $_.ProcessName -match 'chrome|msedge|brave|opera|vivaldi|firefox|tor browser' -or
        $_.Path -match 'Google\\Chrome|Microsoft\\Edge|BraveSoftware|Opera|Vivaldi|Mozilla'
    }
}

Write-Host ""
Write-Host "=================================================================="
Write-Host "  CHROME / BROWSER DATA PROBE — {0}" -f $env:COMPUTERNAME
Write-Host "=================================================================="
Write-Host ("  Generated : {0} at {1} IST" -f (Format-OrdinalDate (Get-IST ([datetime]::UtcNow))), (Get-IST ([datetime]::UtcNow)).ToString('hh:mm:ss tt'))
Write-Host ""

$procs = @(Get-ChromeProcesses)

if ($procs.Count -eq 0) {
    Write-Host "  No Chrome/Edge/Brave/Opera/Firefox process is running right now."
    Write-Host "  If chrome was consuming data earlier but is closed now, then Chrome was"
    Write-Host "  running in the BACKGROUND (see the 'background apps' check below)."
} else {

    # --- Process map -----------------------------------------------------------
    Write-Host "  [1] Browser process map  (memory = private working set)"
    Write-Host "  ------------------------------------------------------------------"
    $procs | Sort-Object @{Expression={$_.WorkingSet64};Descending=$true} |
        Select-Object -First 25 | ForEach-Object {
            $t = if ($_.MainWindowTitle) { "  | tab: $($_.MainWindowTitle)" } else { '' }
            Write-Host ("  PID {0,-7} {1,-9} {2,10}  {3} {4}" -f $_.Id, $_.ProcessName,
                (Format-Size $_.WorkingSet64), $_.Responding, $t)
        }

    # --- Open tabs (window titles) ---------------------------------------------
    Write-Host ""
    Write-Host "  [2] Open browser windows / tabs  (page title = what is loaded)"
    Write-Host "  ------------------------------------------------------------------"
    $tabs = @($procs | Where-Object { $_.MainWindowTitle } |
              Select-Object -Unique ProcessName, MainWindowTitle, Id)
    if ($tabs.Count -eq 0) { Write-Host "      (No titled window found — likely minimized to tray or running headless.)" }
    else {
        $i=0
        $tabs | ForEach-Object {
            $i++
            Write-Host ("  {0,2}. {1}  [PID {2}]  {3}" -f $i, $_.ProcessName, $_.Id, $_.MainWindowTitle)
        }
        Write-Host ""
        Write-Host "      >> A video/audio site in any of these tabs can stream for HOURS even"
        Write-Host "         in the background, with NO file download visible. This is the #1"
        Write-Host "         cause of a 'chrome ate my data' mystery."
    }
}

# ---- active internet connections ----------------------------------------------
function Show-Connections {
    Write-Host ""
    Write-Host "  [3] Active internet connections from browser processes (now)"
    Write-Host "  ------------------------------------------------------------------"
    $pids = @($procs | Select-Object -ExpandProperty Id -Unique)
    $conns = @(Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Established' -and $pids -contains $_.OwningProcess })
    if ($conns.Count -eq 0) {
        Write-Host "      (No established browser connection found right now — either none, or"
        Write-Host "       needs admin rights to read other processes' connections.)"
    } else {
        $conns | Sort-Object @{Expression={$_.RemotePort};Descending=$true} |
            Select-Object -First 40 | ForEach-Object {
                $hostn = Get-HostName $_.RemoteAddress
                Write-Host ("  PID {0,-6} -> {1,-28} : {2,-6} {3}" -f $_.OwningProcess, $hostn, $_.RemotePort,
                    (($procs | Where-Object Id -eq $_.OwningProcess | Select-Object -First 1).ProcessName))
            }
    }
}

if ($Connections) { Show-Connections }

# --- live monitor --------------------------------------------------------------
if ($RefreshSeconds -gt 0) {
    Write-Host ""
    Write-Host ("  [4] Live connection monitor, refreshing every {0}s (Ctrl+C to stop)" -f $RefreshSeconds)
    Write-Host "  ------------------------------------------------------------------"
    $pids = @($procs | Select-Object -ExpandProperty Id -Unique)
    for ($n=0; $n -lt 20; $n++) {
        Write-Host ("  ---- {0} ----" -f (Get-IST ([datetime]::UtcNow)).ToString('hh:mm:ss tt'))
        Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Established' -and $pids -contains $_.OwningProcess } |
            Select-Object -Unique OwningProcess, RemoteAddress, RemotePort |
            ForEach-Object { Write-Host ("  PID {0} -> {1}:{2}" -f $_.OwningProcess,
                (Get-HostName $_.RemoteAddress), $_.RemotePort) }
        Start-Sleep -Seconds $RefreshSeconds
    }
}

# ---- silent background data eaters --------------------------------------------
Write-Host ""
Write-Host "  [5] Known silent Chrome data consumers — CHECK THESE"
Write-Host "  ------------------------------------------------------------------"
Write-Host "  A. Open tabs playing audio/video  -> press Shift+Esc in Chrome to open"
Write-Host "     Chrome's Task Manager. Look at 'Network' column, sort it. The tab with"
Write-Host "     the huge network number is your culprit. Close that tab to stop it."
Write-Host "  B. 'Continue running background apps when Google Chrome is closed':"
Write-Host "     chrome://settings/system  -> turn OFF. Background apps (Gmail, Drive,"
Write-Host "     WhatsApp Web etc.) keep using data after you close the browser."
Write-Host "  C. Extensions doing background work (ad-blocker updates, sync, cloud):"
Write-Host "     chrome://extensions  -> disable any you don't need. Extensions can call"
Write-Host "     home servers constantly."
Write-Host "  D. Chrome pre-fetch / preconnect: chrome://settings/privacy  -> 'Preload' settings"
Write-Host "     and 'Predictive' options -> set to standard/off. Chrome pre-loads pages"
Write-Host "     you haven't even opened, which downloads content you never see."
Write-Host "  E. Sync / Google backup: chrome://settings/syncSetup  -> pause or sign out"
Write-Host "     if not needed. Large sync can push GBs."
Write-Host "  F. A 'drive/cloud' web app or Google Photos in a background tab can be"
Write-Host "     uploading your photos in the background right now."
Write-Host "  G. If it's STILL using data with all tabs closed -> close Chrome fully"
Write-Host "     (check the system tray, right-click the icon, Exit), or end task in"
Write-Host "     Task Manager, then check the Data usage page again to confirm it drops."
Write-Host ""

# ---- other hidden downloaders (torrents, updaters, cloud sync) ----------------
Write-Host "  [6] Other background downloaders running right now"
Write-Host "  ------------------------------------------------------------------"
$hogNames = 'bittorrent|qbittorrent|utorrent|deluge|transmission|fdm|idm|internet download|aria2c|download|dropbox|onedrive|gdrive|backup|photos|megasync|steam|epic|battle.net|update'
$suspects = @(Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match $hogNames } |
    Select-Object -Unique ProcessName, Id, @{n='MB';e={[math]::Round($_.WorkingSet64/1MB)}})
if ($suspects.Count -eq 0) { Write-Host "      (No torrent / downloader / cloud-sync process detected.)" }
else {
    Write-Host "      >> Potential hidden data consumers detected:"
    $suspects | Select-Object -First 20 | ForEach-Object {
        Write-Host ("      {0,-24} PID {1,-7} ~{2} MB" -f $_.ProcessName, $_.Id, $_.MB)
    }
    Write-Host "      A torrent client (e.g. qBittorrent/BitTorrent) that is SEEDING or"
    Write-Host "      downloading will keep using data in the background even with no"
    Write-Host "      visible window. Check its 'transfers/peers' or close it entirely."
}
Write-Host ""

# ---- metered-connection advice ------------------------------------------------
Write-Host "  [7] Stop Windows + background downloads from using mobile data"
Write-Host "  ------------------------------------------------------------------"
Write-Host "  If you use a PHONE HOTSPOT or other metered link: by default Windows"
Write-Host "  treats it as an unmetered connection and freely downloads updates, app"
Write-Host "  refreshes and background sync. Set it to METERED to stop that:"
Write-Host "     Settings -> Network & internet -> Wi-Fi -> (your hotspot) -> "
Write-Host "     'Metered connection' -> ON"
Write-Host "  This stops Windows Update, Store auto-downloads and many background apps"
Write-Host "  from eating your SIM data."
Write-Host ""

# ---- how to find the exact numbers --------------------------------------------
Write-Host "  [8] Where the exact per-tab numbers live"
Write-Host "  ------------------------------------------------------------------"
Write-Host "  • In Chrome press  Shift+Esc  (Chrome's own Task Manager) -> sort by Network."
Write-Host "    This is the ONLY place Chrome shows per-tab/per-extension bytes."
Write-Host "  • chrome://net-export  /  chrome://net-internals#events  -> detailed logs."
Write-Host "  • Windows  Settings -> Network & internet -> Advanced -> Data usage ->"
Write-Host "    'View usage per app'  -> click chrome -> shows per-site bytes Windows"
Write-Host "    captured (may lag / undercount, that is normal)."
Write-Host ""
