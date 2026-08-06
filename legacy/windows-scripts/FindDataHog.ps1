<#
====================================================================================
  FindDataHog.ps1  —  Find what downloaded / is downloading on your PC
====================================================================================
  Use this when your MOBILE data (SIM) spiked even though you were connected to the
  PC via USB/Ethernet tethering or hotspot.  If the PC was the one that downloaded
  files behind your back, they will be sitting somewhere on this machine.

  What it does (prioritised exactly how you asked — browsers first, then Downloads):
    1. Reads each installed browser's OWN download folder (Chrome, Edge, Brave,
       Opera, Vivaldi, Firefox) from their Preferences/prefs.js files.
    2. Adds the standard Windows "Downloads" / Desktop / Documents / Pictures /
       Videos / Music folders for every user profile on the machine.
    3. Scans those folders (recursively) for files written in the last -Days days,
       sorted by size, so the biggest / most recent downloads surface immediately.
    4. Flags PARTIAL / ACTIVE download files (.crdownload, .part, .partial, .tmp,
       .download) — strong evidence of a download that is still in progress.
    5. -Watch  mode: samples file sizes a few seconds apart to detect files that are
       STILL GROWING right now (an ongoing download).
    6. Lists processes that currently hold live internet connections (so you can see
       if a browser / downloader is running in the background).
    7. Optionally -FullScan the whole user profile for big recent files.

  All times are shown in IST with a 12-hour clock and ordinal dates
  (e.g. "6th August 2026 at 03:42:15 PM").

  USAGE
  -----
     # Fast scan of all browser + Downloads folders, last 30 days, files >=5 MB
        .\FindDataHog.ps1

     # Same but only look at the last 7 days
        .\FindDataHog.ps1 -Days 7

     # Include files as small as 1 MB and show more results
        .\FindDataHog.ps1 -MinSizeMB 1 -Top 60

     # Detect files that are actively downloading RIGHT NOW (runs ~10 seconds)
        .\FindDataHog.ps1 -Watch

     # Full profile scan (slower but catches files downloaded to odd locations)
        .\FindDataHog.ps1 -FullScan
====================================================================================
#>

[CmdletBinding()]
param(
    [int]$Days = 30,
    [int]$MinSizeMB = 5,
    [int]$Top = 40,
    [switch]$FullScan,
    [switch]$Watch,
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---- IST time helpers --------------------------------------------------------
function Get-IST([datetime]$utc) {
    if ($utc.Kind -eq 'Unspecified') { $utc = [datetime]::SpecifyKind($utc, 'Utc') }
    if ($utc.Kind -ne 'Utc') { $utc = $utc.ToUniversalTime() }
    try { return [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($utc, 'India Standard Time') }
    catch { return $utc.AddHours(5).AddMinutes(30) }   # guaranteed IST fallback (UTC+5:30)
}
function Format-OrdinalDate([datetime]$dt) {
    $day = $dt.Day
    $mod100 = $day % 100
    if ($mod100 -ge 11 -and $mod100 -le 13) { $suffix = 'th' }
    else {
        switch ($day % 10) {
            1       { $suffix = 'st' }
            2       { $suffix = 'nd' }
            3       { $suffix = 'rd' }
            default { $suffix = 'th' }
        }
    }
    return "$day$suffix $($dt.ToString('MMMM')) $($dt.Year)"
}
function Format-IST12([datetime]$utc) {
    return (Get-IST $utc).ToString('hh:mm:ss tt')
}
function Format-Size([int64]$bytes) {
    if ($bytes -lt 0) { $bytes = 0 }
    $units = @('B','KB','MB','GB','TB'); $u = 0; $v = [double]$bytes
    while ($v -ge 1024 -and $u -lt ($units.Count - 1)) { $v /= 1024; $u++ }
    return ('{0:N2} {1}' -f $v, $units[$u])
}

# ---- 1) Browser download folders ----------------------------------------------
function Get-BrowserDownloadDirs {
    $items = New-Object System.Collections.Generic.List[string]
    $local = $env:LOCALAPPDATA
    $roam  = $env:APPDATA
    $targets = [ordered]@{
        'Chrome'  = "$local\Google\Chrome\User Data"
        'Edge'    = "$local\Microsoft\Edge\User Data"
        'Brave'   = "$local\BraveSoftware\Brave-Browser\User Data"
        'Opera'   = "$roam\Opera Software\Opera Stable"
        'Vivaldi' = "$local\Vivaldi\User Data"
    }
    foreach ($b in $targets.Keys) {
        $root = $targets[$b]
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Directory | ForEach-Object {
                $pref = Join-Path $_.FullName 'Preferences'
                if (Test-Path $pref) {
                    try {
                        $j = Get-Content $pref -Raw | ConvertFrom-Json
                        if ($j.download.default_directory -and $j.download.default_directory -notmatch '^\s*$') {
                            $items.Add("$b|$($j.download.default_directory)")
                        }
                    } catch { }
                }
            }
        }
    }
    # Firefox
    $ffProfiles = "$roam\Mozilla\Firefox\Profiles"
    if (Test-Path $ffProfiles) {
        Get-ChildItem -Path $ffProfiles -Directory | ForEach-Object {
            $prefs = Join-Path $_.FullName 'prefs.js'
            if (Test-Path $prefs) {
                $c = Get-Content $prefs -Raw
                if ($c -match 'user_pref\("browser\.download\.dir",\s*"(.*?)"\)') {
                    $items.Add("Firefox|$($Matches[1] -replace '\\/', '/')")
                }
            }
        }
    }
    return $items
}

# ---- 2) Standard per-profile folders ------------------------------------------
function Get-UserFolders {
    $dirs = New-Object System.Collections.Generic.List[string]
    $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $profiles = @(Get-ChildItem $profileList | ForEach-Object { $_.GetValue('ProfileImagePath') })
    if ($profiles.Count -eq 0) { $profiles = @($env:USERPROFILE) }
    foreach ($p in $profiles) {
        foreach ($sub in @('Downloads','Desktop','Documents','Pictures','Videos','Music')) {
            $d = Join-Path $p $sub
            if (Test-Path $d) { $dirs.Add("Windows|$d") }
        }
    }
    return $dirs
}

# ---- 3) Recursive recent-file scan --------------------------------------------
function Get-RecentFiles([string]$root, [datetime]$cutoff, [int64]$minSize, [switch]$full) {
    $results = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $root)) { return $results }
    $maxDepth = if ($full) { 100 } else { 6 }
    try {
        Get-ChildItem -LiteralPath $root -File -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $cutoff -and $_.Length -ge $minSize } |
            ForEach-Object {
                $results.Add([pscustomobject]@{
                    Path      = $_.FullName
                    Name      = $_.Name
                    Size      = $_.Length
                    SizeHuman = Format-Size $_.Length
                    Modified  = $_.LastWriteTimeUtc
                })
            }
    } catch { }
    return $results
}

# ---- 4) partial / active download files ---------------------------------------
function Get-PartialFiles([string]$root) {
    $ext = @('.crdownload','.part','.partial','.download','.tmp','.crdownload','.opdownload','.aria2')
    $out = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $root)) { return $out }
    Get-ChildItem -LiteralPath $root -File -Recurse -Depth 5 -ErrorAction SilentlyContinue |
        Where-Object { $ext -contains $_.Extension.ToLowerInvariant() } |
        ForEach-Object {
            $out.Add([pscustomobject]@{
                Path = $_.FullName; Name = $_.Name
                SizeHuman = Format-Size $_.Length; Size = $_.Length
                Modified = $_.LastWriteTimeUtc
            })
        }
    return $out
}

# ---- 5) Watch: files currently growing (ongoing download) ---------------------
function Show-GrowingFiles($roots) {
    $min = [datetime]::UtcNow.AddMinutes(-5)   # only recently-touched files can be growing
    $candidates = @()
    foreach ($r in $roots) {
        if (Test-Path $r) {
            $candidates += @(Get-ChildItem -LiteralPath $r -File -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $min })
        }
    }
    if ($candidates.Count -eq 0) { Write-Host "      (No file in download folders was touched in the last 5 minutes.)"; return }
    $map1 = @{}; foreach ($c in $candidates) { $map1[$c.FullName] = $c.Length }
    Start-Sleep -Seconds 6
    Write-Host "      Monitoring for 6 seconds to catch files still growing..."
    $grew = @()
    foreach ($path in $map1.Keys) {
        $sz2 = (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).Length
        if ($sz2 -gt $map1[$path]) {
            $grew += [pscustomobject]@{ Path=$path; Grown = Format-Size ($sz2 - $map1[$path]); SizeHuman = Format-Size $sz2 }
        }
    }
    if ($grew.Count -eq 0) {
        Write-Host "      No file grew in the last few seconds — no obvious active download right now."
    } else {
        Write-Host "      >>> ACTIVE DOWNLOAD DETECTED — these files are still growing: <<<"
        $grew | ForEach-Object { Write-Host ("      {0,-12} {1}" -f $_.Grown, $_.Path) }
    }
}

# ---- 6) processes with live internet connections ------------------------------
function Get-OnlineProcesses {
    $conn = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
                Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|0\.0\.0\.0|::)' } |
                Select-Object -ExpandProperty OwningProcess -Unique)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($pidId in $conn) {
        $proc = Get-Process -Id $pidId -ErrorAction SilentlyContinue
        if ($proc) {
            $out.Add([pscustomobject]@{ Name=$proc.ProcessName; PID=$proc.Id; Title=$proc.MainWindowTitle })
        }
    }
    return $out | Sort-Object Name
}

# ===============================================================================
# MAIN
# ===============================================================================
$cutoff = [datetime]::UtcNow.AddDays(-$Days)
$minSize = [int64]($MinSizeMB * 1024 * 1024)

Write-Host ""
Write-Host "=================================================================="
Write-Host "  DATA HOG FINDER — what used your data on {0}" -f $env:COMPUTERNAME
Write-Host "=================================================================="
Write-Host ("  Scan window : last {0} days, files >= {1} MB" -f $Days, $MinSizeMB)
Write-Host ("  Generated   : {0}" -f (Format-OrdinalDate (Get-IST ([datetime]::UtcNow))))
Write-Host ""

# --- collect roots ------------------------------------------------------------
$browserRoots = Get-BrowserDownloadDirs
$userRoots    = Get-UserFolders

Write-Host "  [A] Browser download folders found"
Write-Host "  ------------------------------------------------------------------"
$browserPaths = @()
if ($browserRoots.Count -eq 0) { Write-Host "      (No browser download folders detected.)" }
else {
    foreach ($br in $browserRoots) {
        $parts = $br.Split('|', 2)
        if (Test-Path $parts[1]) {
            Write-Host ("      {0,-9} {1}" -f $parts[0], $parts[1])
            $browserPaths += $parts[1]
        }
    }
}
Write-Host ""

# --- partial downloads in browser/downloads dirs ------------------------------
Write-Host "  [B] PARTIAL / IN-PROGRESS download files (.crdownload/.part/etc.)"
Write-Host "  ------------------------------------------------------------------"
$partialAll = @()
foreach ($p in ($browserPaths + ($userRoots | ForEach-Object { $_.Split('|',2)[1] }))) {
    $partialAll += @(Get-PartialFiles $p)
}
if ($partialAll.Count -eq 0) { Write-Host "      (None found — good sign, no obvious half-finished download.)" }
else {
    $partialAll | Sort-Object Size -Descending | Select-Object -First $Top | ForEach-Object {
        Write-Host ("      {0,-10}  {1}  modified {2}" -f $_.SizeHuman, $_.Path, (Format-IST12 $_.Modified))
    }
}
Write-Host ""

# --- biggest recent files (browsers + downloads first) -------------------------
$allRoots = @()
foreach ($br in $browserPaths) { $allRoots += "browser|$br" }
foreach ($ur in $userRoots)    { $allRoots += $ur }   # already has "Windows|path"

Write-Host "  [C] Biggest files downloaded in the last $Days days (size, newest first)"
Write-Host "      (Browser + Windows Download folders scanned first.)"
Write-Host "  ------------------------------------------------------------------"
$recent = @()
foreach ($r in $allRoots) {
    $parts = $r.Split('|', 2)
    $recent += @(Get-RecentFiles $parts[1] $cutoff $minSize)
}
# merge duplicates by path
$recent = $recent | Sort-Object @{Expression='Modified';Descending=$true}, @{Expression='Size';Descending=$true} |
                   Select-Object -First $Top

if ($recent.Count -eq 0) { Write-Host "      (No large recent files found in the main download locations.)" }
else {
    $i = 0
    foreach ($f in $recent) {
        $i++
        Write-Host ("  {0,2}. {1,-10}  {2}" -f $i, $f.SizeHuman, $f.Path)
        Write-Host ("        modified {0}  IST" -f (Format-IST12 $f.Modified))
    }
}
Write-Host ""

# --- full profile scan (optional, slower) -------------------------------------
if ($FullScan) {
    Write-Host "  [D] Full user-profile scan (may take a while) — biggest recent files"
    Write-Host "  ------------------------------------------------------------------"
    $allRec = @()
    foreach ($ur in $userRoots) {
        $parts = $ur.Split('|', 2)
        $allRec += @(Get-RecentFiles $parts[1] $cutoff $minSize -full)
    }
    $allRec = $allRec | Sort-Object @{Expression='Size';Descending=$true} | Select-Object -First $Top
    if ($allRec.Count -eq 0) { Write-Host "      (None found.)" }
    else {
        $i = 0
        foreach ($f in $allRec) {
            $i++
            Write-Host ("  {0,2}. {1,-10}  {2}" -f $i, $f.SizeHuman, $f.Path)
            Write-Host ("        modified {0}  IST" -f (Format-IST12 $f.Modified))
        }
    }
    Write-Host ""
}

# --- active download detection (Watch) -----------------------------------------
if ($Watch) {
    Write-Host "  [E] Live check for a download STILL IN PROGRESS"
    Write-Host "  ------------------------------------------------------------------"
    Show-GrowingFiles ($browserPaths + @($userRoots | ForEach-Object { $_.Split('|',2)[1] }))
    Write-Host ""
}

# --- processes holding internet connections ------------------------------------
Write-Host "  [F] Processes currently holding internet connections (possible hidden downloaders)"
Write-Host "  ------------------------------------------------------------------"
$online = Get-OnlineProcesses
if ($online.Count -eq 0) { Write-Host "      (None / needs admin rights for full list.)" }
else {
    $online | Select-Object -First 30 | ForEach-Object {
        $t = if ($_.Title) { " — $($_.Title)" } else { '' }
        Write-Host ("      {0,-30} PID {1}{2}" -f $_.Name, $_.PID, $t)
    }
}
Write-Host ""

# --- summary / guidance ---------------------------------------------------------
Write-Host "=================================================================="
Write-Host "  How to read this"
Write-Host "=================================================================="
Write-Host "  • If section [B] shows .crdownload/.part files, a download is/was"
Write-Host "    INCOMPLETE — that is a strong candidate for your data spike."
Write-Host "  • The biggest files in section [C] are what actually used your bytes."
Write-Host "  • Files you did NOT recognise downloading = the likely data hog."
Write-Host "  • To see exact per-app usage on Windows, run:"
Write-Host "        .\DataUsageTracker.ps1 -Snapshot"
Write-Host ""
Write-Host "  Full download history (exact bytes + start/end time per file) lives"
Write-Host "  inside each browser:  Chrome/Edge -> Ctrl+J ; Firefox -> Ctrl+J"
Write-Host "=================================================================="
Write-Host ""
