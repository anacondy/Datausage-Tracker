<#
====================================================================================
  DataUsageTracker.ps1  —  Windows Data Usage Tracker  (low-power)
====================================================================================
  Detects your OVERALL internet data usage across every network adapter that you
  use (mobile hotspot via Wi-Fi, USB tethering / Ethernet, cable Ethernet, etc.)
  and, crucially, WHICH APPLICATION used the data and WHEN.

  Everything is reported in:
      • Indian Standard Time (IST / UTC+5:30)
      • 12-hour time, e.g.  "03:42:15 PM"
      • Long ordinal date,  e.g. "4th August 2026"

  WHY IT IS LOW-POWER
  -------------------
  It does NOT poll your network constantly.  Windows 11 already keeps a tiny,
  continuous per-app counter in the background (the SRUM database, the exact same
  numbers shown in  Settings → Network & internet → Advanced network settings →
  Data usage → View usage per app).  This script simply READS that data on demand
  using Windows' own WinRT API, plus the adapter byte counters.  Reading takes a
  fraction of a second and uses almost no CPU.  For long-term tracking you run it
  every 30–60 minutes via a Task Scheduler entry (see -Schedule), and Windows does
  all the heavy counting for you between runs.

  USAGE
  -----
  # 1) Show a one-off snapshot report (per-app + per-adapter + per-day, last 30 days)
        .\DataUsageTracker.ps1 -Snapshot

  # 2) Detailed report for a custom date range
        .\DataUsageTracker.ps1 -Report -From "1 July 2026" -To "6 August 2026"

  # 3) Register a background, low-power tracker (logs every 30 min + at logon)
        .\DataUsageTracker.ps1 -Schedule

  # 4) Remove the background tracker
        .\DataUsageTracker.ps1 -Unschedule

  # 5) Append one data point to the CSV log right now (used by the scheduled task)
        .\DataUsageTracker.ps1 -Log

  # 6) Show a short LIVE throughput meter (not for long-term logging)
        .\DataUsageTracker.ps1 -Live -Seconds 10

  OUTPUT FILES (written to  %USERPROFILE%\DataUsageLogs\ )
        DataUsage_Log.csv           per-run adapter totals + per-app deltas
        DataUsage_Report.csv        full per-app / per-day report
        baseline.json               internal state used to compute deltas
====================================================================================
#>

[CmdletBinding()]
param(
    [switch]$Snapshot,
    [switch]$Report,
    [switch]$Log,
    [switch]$Schedule,
    [switch]$Unschedule,
    [switch]$Live,
    [datetime]$From,
    [datetime]$To,
    [int]$Days = 30,
    [int]$Seconds = 10,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# --------------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------------
$LogDir = Join-Path $env:USERPROFILE 'DataUsageLogs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$TaskName  = 'DataUsageTracker'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptAbs = $MyInvocation.MyCommand.Path
$BaselineFile = Join-Path $LogDir 'baseline.json'

# --------------------------------------------------------------------------------
# Time helpers  (always IST, 12-hour time, ordinal date)
# --------------------------------------------------------------------------------
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

function Format-ISTTime12([datetime]$utc) {
    $ist = Get-IST $utc
    return $ist.ToString('hh:mm:ss tt')
}

function Format-Bytes([int64]$bytes) {
    if ($bytes -lt 0) { $bytes = 0 }
    $units = @('B','KB','MB','GB','TB')
    $u = 0
    $v = [double]$bytes
    while ($v -ge 1024 -and $u -lt ($units.Count - 1)) { $v /= 1024; $u++ }
    return ('{0:N2} {1}' -f $v, $units[$u])
}

function Format-NowIST {
    $now = [datetime]::UtcNow
    return ("{0} at {1} IST" -f (Format-OrdinalDate (Get-IST $now)), (Format-ISTTime12 $now))
}

# --------------------------------------------------------------------------------
# Windows Runtime per-app usage (exactly the Settings "View usage per app" numbers)
# --------------------------------------------------------------------------------
$script:asTaskGeneric = $null

function Initialize-WinRT {
    if ($script:asTaskGeneric) { return $true }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
        $null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
        $script:asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
            Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                           $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        return ($null -ne $script:asTaskGeneric)
    } catch {
        return $false
    }
}

function Await($WinRtTask, [type]$ResultType) {
    $asTask = $script:asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    [void]$netTask.Wait(-1)
    return $netTask.Result
}

function New-UsageStates {
    $s = New-Object Windows.Networking.Connectivity.NetworkUsageStates
    $s.Roaming = [Windows.Networking.Connectivity.TriStates]::DoNotCare
    $s.Shared  = [Windows.Networking.Connectivity.TriStates]::DoNotCare
    return $s
}

function Get-FriendlyAppName([string]$appId) {
    if ([string]::IsNullOrWhiteSpace($appId)) { return 'Unknown' }
    # UWP/SysApp id: "Microsoft.Windows.Photos_8wekyb3d8bbwe!App"
    if ($appId -match '^([^!]+)!') {
        $name = $Matches[1]
        # Strip publisher hash tail, e.g. "Microsoft.Windows.Photos_8wekyb3d8bbwe"
        $name = $name -replace '_[0-9a-f]{32}$', ''
        return $name
    }
    # Desktop app: a path to an .exe
    if ($appId -match '([^\\/]+)\.exe\s*$') { return $Matches[1] }
    return $appId
}

# Returns per-app usage objects for the [start,end] UTC range.
function Get-PerAppUsage([datetime]$startUtc, [datetime]$endUtc) {
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Initialize-WinRT)) { return $rows }
    try {
        $states = New-UsageStates
        $profiles = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles()
        foreach ($p in $profiles) {
            try {
                $pName = $p.ProfileName
                $list = Await ($p.GetAttributedNetworkUsageAsync([datetimeoffset]$startUtc, [datetimeoffset]$endUtc, $states)) `
                        ([System.Collections.Generic.IReadOnlyList[Windows.Networking.Connectivity.AttributedNetworkUsage]])
                foreach ($u in $list) {
                    $rows.Add([pscustomobject]@{
                        Profile  = $pName
                        AppId    = $u.AppId
                        AppName  = Get-FriendlyAppName $u.AppId
                        Sent     = [uint64]$u.BytesSent
                        Received = [uint64]$u.BytesReceived
                        Total    = [uint64]($u.BytesSent + $u.BytesReceived)
                    })
                }
            } catch { if (-not $Quiet) { Write-Warning "Per-app query skipped for profile '$($p.ProfileName)': $($_.Exception.Message)" } }
        }
    } catch { if (-not $Quiet) { Write-Warning "WinRT per-app query unavailable: $($_.Exception.Message)" } }
    return $rows
}

# Returns per-day totals for the range.
function Get-PerDayUsage([datetime]$startUtc, [datetime]$endUtc) {
    $rows = New-Object System.Collections.Generic.List[object]
    if (-not (Initialize-WinRT)) { return $rows }
    try {
        $states = New-UsageStates
        $profiles = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles()
        foreach ($p in $profiles) {
            try {
                $list = Await ($p.GetNetworkUsageAsync([datetimeoffset]$startUtc, [datetimeoffset]$endUtc,
                             [Windows.Networking.Connectivity.DataUsageGranularity]::PerDay, $states)) `
                         ([System.Collections.Generic.IReadOnlyList[Windows.Networking.Connectivity.NetworkUsage]])
                foreach ($u in $list) {
                    $rows.Add([pscustomobject]@{
                        Date     = (Get-IST $u.StartTime.DateTime).Date
                        Sent     = [uint64]$u.BytesSent
                        Received = [uint64]$u.BytesReceived
                        Total    = [uint64]($u.BytesSent + $u.BytesReceived)
                    })
                }
            } catch { }
        }
    } catch { }
    # aggregate by date across all profiles
    return ($rows | Group-Object Date | ForEach-Object {
        [pscustomobject]@{
            Date     = [datetime]$_.Name
            Sent     = [uint64] (($_.Group | Measure-Object Sent -Sum).Sum)
            Received = [uint64] (($_.Group | Measure-Object Received -Sum).Sum)
            Total    = [uint64] (($_.Group | Measure-Object Total -Sum).Sum)
        }
    })
}

# IMPORTANT: see docs/ for full methodology verification, security audit,
# cross-platform assessment, and UI optimization report.
# A new HTML dashboard (ui/index.html) allows viewing CSV results
# in any browser without PowerShell.
# --------------------------------------------------------------------------------
# Adapter byte counters (overall usage per adapter since last reset)
# --------------------------------------------------------------------------------
function Get-AdapterTotals {
    $rows = @()
    try {
        $rows = @(Get-NetAdapterStatistics -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Adapter   = $_.Name
                Status    = ($_.Status)
                Received  = [uint64]$_.ReceivedBytes
                Sent      = [uint64]$_.SentBytes
                Total     = [uint64]($_.ReceivedBytes + $_.SentBytes)
                Last      = (Get-IST [datetime]::UtcNow)
            }
        })
    } catch { }
    return $rows
}

# --------------------------------------------------------------------------------
# Live throughput meter (short, for debugging only)
# --------------------------------------------------------------------------------
function Show-LiveMeter([int]$secs) {
    $sample = Get-Counter "\Network Interface(*)\Bytes Total/sec" -SampleInterval 1 -MaxSamples $secs -ErrorAction SilentlyContinue
    if (-not $sample) { Write-Host 'Live meter unavailable.'; return }
    $last = @{}
    foreach ($s in $sample) {
        Write-Host ("---- {0} ----" -f (Format-ISTTime12 [datetime]::UtcNow))
        foreach ($x in $s.CounterSamples) {
            $rate = [double]$x.CookedValue
            if ($rate -gt 0) {
                Write-Host ("{0,-42} {1,10}/s" -f $x.InstanceName, (Format-Bytes $rate))
            }
        }
    }
}

# --------------------------------------------------------------------------------
# CSV logging mode  (used by the scheduled task; low power)
# --------------------------------------------------------------------------------
function Save-LogPoint {
    $nowUtc   = [datetime]::UtcNow
    $istNow   = Get-IST $nowUtc
    $dateStr  = Format-OrdinalDate $istNow
    $timeStr  = $istNow.ToString('hh:mm:ss tt')

    $adapterCsv  = Join-Path $LogDir 'DataUsage_Log.csv'
    $appCsv      = Join-Path $LogDir 'DataUsage_Apps.csv'

    # --- deduplication guard ----------------------------------------------------
    # If this script somehow runs twice within 15 seconds (e.g. a manual -Log while
    # the scheduled task also fired), skip the second write so we never double-count.
    $lastLogFile = Join-Path $LogDir 'last_run.json'
    if (Test-Path $lastLogFile) {
        try {
            $lr = Get-Content $lastLogFile -Raw | ConvertFrom-Json
            if ($lr.LastLogUtc) {
                $lastLogDt = [datetime]$lr.LastLogUtc
                if (($nowUtc - $lastLogDt).TotalSeconds -lt 15) {
                    if (-not $Quiet) { Write-Host "Skip: a log point was just written (dedup guard)." }
                    return
                }
            }
        } catch { }
    }

    # --- baseline bookkeeping ---------------------------------------------------
    $baseline = @{ LastRunUtc = $nowUtc; Adapters = @{} }
    if (Test-Path $BaselineFile) {
        try { $baseline = Get-Content $BaselineFile -Raw | ConvertFrom-Json } catch { }
    }
    $lastRunUtc = $nowUtc.AddMinutes(-30)
    if ($baseline.LastRunUtc) {
        try { $lastRunUtc = [datetime]$baseline.LastRunUtc } catch { }
    }

    $cur = @{}
    foreach ($a in Get-AdapterTotals) { $cur[$a.Adapter] = $a }

    # --- adapter deltas vs baseline --------------------------------------------
    # Robust across:
    #   • disconnecting / reconnecting (hotspot off/on, ethernet unplug): the adapter
    #     counters continue, so delta = current - previous keeps accumulating correctly.
    #   • a REBOOT (which resets the adapter counters): current < previous, so we treat
    #     the whole current value as new usage since boot (nothing is double-counted,
    #     and nothing since boot is lost).
    #   • switching networks (hotspot <-> ethernet): each adapter keeps its OWN row and
    #     baseline, so totals are never mixed or duplicated between interfaces.
    if (-not (Test-Path $adapterCsv)) {
        "TimestampIST,DateIST,TimeIST,Adapter,Received_Delta,Sent_Delta,Total_Delta,Lifetime_Received,Lifetime_Sent,Lifetime_Total" |
            Set-Content -Path $adapterCsv -Encoding UTF8
    }
    # lifetime (cumulative since we first started tracking) survives reboots:
    $lifetime = @{}
    if ($baseline.Lifetime) { $lifetime = $baseline.Lifetime }

    foreach ($a in $cur.Values) {
        $prevRec = 0; $prevSent = 0
        $prevAd = $baseline.Adapters.($a.Adapter)
        if ($prevAd) {
            $prevRec  = [uint64]$prevAd.Received
            $prevSent = [uint64]$prevAd.Sent
        }
        # delta since last run, with reboot/rollover protection:
        $recD = if ($a.Received -ge $prevRec) { $a.Received - $prevRec } else { $a.Received }
        $sntD = if ($a.Sent     -ge $prevSent){ $a.Sent     - $prevSent } else { $a.Sent }

        # cumulative lifetime totals (add the delta; monotonic, survives reboot):
        $lt = $lifetime.($a.Adapter)
        $ltRec = if ($lt) { [uint64]$lt.Received } else { 0 }
        $ltSnt = if ($lt) { [uint64]$lt.Sent } else { 0 }
        $ltRec += $recD
        $ltSnt += $sntD
        $lifetime[$a.Adapter] = [ordered]@{ Received = $ltRec; Sent = $ltSnt }

        "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $timeStr,$dateStr,(Format-ISTTime12 $nowUtc),
            $a.Adapter,$recD,$sntD,($recD+$sntD),$ltRec,$ltSnt,($ltRec+$ltSnt) |
            Add-Content -Path $adapterCsv -Encoding UTF8
    }

    # --- per-app delta for the interval since last run -------------------------
    $apps = Get-PerAppUsage $lastRunUtc $nowUtc
    if (($apps | Measure-Object).Count -gt 0) {
        if (-not (Test-Path $appCsv)) {
            "TimestampIST,DateIST,TimeIST,App,Sent_Delta,Received_Delta,Total_Delta" |
                Set-Content -Path $appCsv -Encoding UTF8
        }
        $agg = $apps | Group-Object AppName | ForEach-Object {
            [pscustomobject]@{
                AppName  = $_.Name
                Sent     = [uint64](($_.Group | Measure-Object Sent -Sum).Sum)
                Received = [uint64](($_.Group | Measure-Object Received -Sum).Sum)
                Total    = [uint64](($_.Group | Measure-Object Total -Sum).Sum)
            }
        } | Sort-Object Total -Descending
        foreach ($ap in $agg) {
            if ($ap.Total -gt 0) {
                "{0},{1},{2},{3},{4},{5},{6}" -f $timeStr,$dateStr,(Format-ISTTime12 $nowUtc),
                    $ap.AppName,$ap.Sent,$ap.Received,$ap.Total | Add-Content -Path $appCsv -Encoding UTF8
            }
        }
    }

    # --- store new baseline -----------------------------------------------------
    $newBase = [ordered]@{
        LastRunUtc = $nowUtc
        Adapters   = [ordered]@{}
        Lifetime   = $lifetime
    }
    foreach ($a in $cur.Values) {
        $newBase.Adapters[$a.Adapter] = [ordered]@{ Received = $a.Received; Sent = $a.Sent }
    }
    $newBase | ConvertTo-Json -Depth 6 | Set-Content -Path $BaselineFile -Encoding UTF8

    # remember this write time for the dedup guard:
    [ordered]@{ LastLogUtc = $nowUtc } | ConvertTo-Json | Set-Content -Path $lastLogFile -Encoding UTF8

    if (-not $Quiet) {
        Write-Host ("Log point written: {0} at {1}" -f $dateStr, $timeStr)
    }
}

# --------------------------------------------------------------------------------
# Report mode
# --------------------------------------------------------------------------------
function Show-Report([datetime]$fromUtc, [datetime]$toUtc) {
    $fromUtc = $fromUtc.ToUniversalTime()
    $toUtc   = $toUtc.ToUniversalTime()
    $istFrom = Format-OrdinalDate (Get-IST $fromUtc)
    $istTo   = Format-OrdinalDate (Get-IST $toUtc)

    Write-Host ""
    Write-Host "=================================================================="
    Write-Host "  DATA USAGE REPORT   (Indian Standard Time)"
    Write-Host "=================================================================="
    Write-Host ("  Machine  : {0}" -f $env:COMPUTERNAME)
    Write-Host ("  User     : {0}" -f $env:USERNAME)
    Write-Host ("  Period   : {0}  to  {1}" -f $istFrom, $istTo)
    Write-Host ("  Generated: {0}" -f (Format-NowIST))
    Write-Host ""

    # --- Per-adapter lifetime totals -------------------------------------------
    Write-Host "  [1] Overall usage per network adapter (since counters reset)"
    Write-Host "  ------------------------------------------------------------------"
    $adapters = Get-AdapterTotals
    if ($adapters.Count -eq 0) { Write-Host "      (No active adapters / module unavailable)" }
    else {
        $adapters | Sort-Object Total -Descending | ForEach-Object {
            Write-Host ("      {0,-28} {1,12}  up/down {2} / {3}" -f $_.Adapter,
                (Format-Bytes $_.Total), (Format-Bytes $_.Received), (Format-Bytes $_.Sent))
        }
    }
    Write-Host ""

    # --- Per-day totals ---------------------------------------------------------
    Write-Host "  [2] Daily usage  (per date, IST)"
    Write-Host "  ------------------------------------------------------------------"
    $daily = Get-PerDayUsage $fromUtc $toUtc
    if ($daily.Count -eq 0) { Write-Host "      (No per-day data available)" }
    else {
        $daily | Sort-Object Date | ForEach-Object {
            Write-Host ("      {0,-16} {1,12}  up {2} / down {3}" -f (Format-OrdinalDate $_.Date),
                (Format-Bytes $_.Total), (Format-Bytes $_.Received), (Format-Bytes $_.Sent))
        }
        $tot = [uint64](($daily | Measure-Object Total -Sum).Sum)
        Write-Host ("      ------------------------------------------------")
        Write-Host ("      TOTAL IN PERIOD       {0}" -f (Format-Bytes $tot))
    }
    Write-Host ""

    # --- Per-app ----------------------------------------------------------------
    Write-Host "  [3] Usage by application  (Windows 'View usage per app' data)"
    Write-Host "  ------------------------------------------------------------------"
    $apps = Get-PerAppUsage $fromUtc $toUtc
    if ($apps.Count -eq 0) {
        Write-Host "      (Per-app data unavailable for this period.)"
        Write-Host "      Tip: Windows only keeps per-app data for recent periods."
    } else {
        $agg = $apps | Group-Object AppName | ForEach-Object {
            [pscustomobject]@{
                AppName  = $_.Name
                Sent     = [uint64](($_.Group | Measure-Object Sent -Sum).Sum)
                Received = [uint64](($_.Group | Measure-Object Received -Sum).Sum)
                Total    = [uint64](($_.Group | Measure-Object Total -Sum).Sum)
            }
        } | Sort-Object Total -Descending
        $gt = [uint64](($agg | Measure-Object Total -Sum).Sum)
        foreach ($a in $agg) {
            if ($gt -gt 0) { $pct = [math]::Round(($a.Total / $gt) * 100, 1) } else { $pct = 0 }
            Write-Host ("      {0,-32} {1,12}  {2,5}%   (up {3} / down {4})" -f
                $a.AppName, (Format-Bytes $a.Total), $pct, (Format-Bytes $a.Received), (Format-Bytes $a.Sent))
        }
        Write-Host ("      ------------------------------------------------")
        Write-Host ("      TOTAL                    {0}" -f (Format-Bytes $gt))
        if ($agg.Count -gt 0) {
            Write-Host ("      MOST DATA USED BY:  {0}" -f $agg[0].AppName)
        }
    }
    Write-Host ""

    # --- export CSV -------------------------------------------------------------
    $repCsv = Join-Path $LogDir 'DataUsage_Report.csv'
    $all = @()
    if ($apps.Count -gt 0) {
        $all += $apps | Group-Object AppName | ForEach-Object {
            [pscustomobject]@{
                App      = $_.Name
                Sent     = [uint64](($_.Group | Measure-Object Sent -Sum).Sum)
                Received = [uint64](($_.Group | Measure-Object Received -Sum).Sum)
                Total    = [uint64](($_.Group | Measure-Object Total -Sum).Sum)
            }
        } | Sort-Object Total -Descending
    }
    if ($all.Count -gt 0) {
        $all | Export-Csv -Path $repCsv -NoTypeInformation -Encoding UTF8
        Write-Host ("  Report CSV saved to: {0}" -f $repCsv)
    }
}

# --------------------------------------------------------------------------------
# Snapshot mode
# --------------------------------------------------------------------------------
function Show-Snapshot([int]$days) {
    $from = [datetime]::UtcNow.AddDays(-$days)
    $to   = [datetime]::UtcNow
    Write-Host "  Snapshot: last $days days, in IST."
    Show-Report $from $to
}

# --------------------------------------------------------------------------------
# Scheduler
# --------------------------------------------------------------------------------
function Register-Tracker {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Host "Scheduled task '$TaskName' already exists."
        return
    }
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptAbs`" -Log -Quiet"
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $triggerRepeat= New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
                   -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
                   -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Description 'Low-power Windows data usage tracker (per-app + per-adapter) in IST.' `
        -Action $action -Trigger @($triggerLogon, $triggerRepeat) -Settings $settings -Force | Out-Null
    Write-Host "Registered background tracker '$TaskName' (runs at logon and every 30 min)."
    Write-Host "Logs will be written to: $LogDir"
    Write-Host "Run  .\DataUsageTracker.ps1 -Unschedule  to remove it."
}

function Unregister-Tracker {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'."
    } else {
        Write-Host "No scheduled task '$TaskName' found."
    }
}

# --------------------------------------------------------------------------------
# Main dispatch
# --------------------------------------------------------------------------------
if ($Schedule)   { Register-Tracker;   exit 0 }
if ($Unschedule) { Unregister-Tracker; exit 0 }
if ($Log)        { Save-LogPoint;      exit 0 }
if ($Live)       { Show-LiveMeter $Seconds; exit 0 }
if ($Report) {
    if (-not $From) { $From = [datetime]::UtcNow.AddDays(-$Days) }
    if (-not $To)   { $To   = [datetime]::UtcNow }
    Show-Report $From $To
    exit 0
}
if ($Snapshot) { Show-Snapshot $Days; exit 0 }

# No switch: default to snapshot so the script is still useful if just double-clicked
Show-Snapshot $Days
