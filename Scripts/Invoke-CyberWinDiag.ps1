#Requires -Version 5.1
<#
.SYNOPSIS
    CyberWinDiagnostics - portable Windows 10 diagnostic collector.

.DESCRIPTION
    Collects a read-only evidence bundle covering system config, performance,
    storage health, power, drivers, event logs, network, the print subsystem and
    antivirus state. Writes everything to a timestamped folder and zips it.

    Read-only by default. The only switch that modifies the system is
    -RunIntegrityScans (SFC / DISM RestoreHealth).

.PARAMETER OutputRoot
    Where to write the report folder. Defaults to the Reports directory at the
    root of the USB toolkit.

.PARAMETER IncludePerfmonReport
    Also run 'perfmon /report' (60s System Diagnostics Report, HTML). ~2 min.

.PARAMETER IncludePowerReports
    Also run powercfg /energy, /batteryreport and /sleepstudy. ~1 min.

.PARAMETER RunIntegrityScans
    Also run DISM /ScanHealth, DISM /RestoreHealth and sfc /scannow.
    WRITES TO THE SYSTEM. Adds 10-30 minutes. Opt-in only.

.PARAMETER SkipZip
    Leave the report folder uncompressed.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Invoke-CyberWinDiag.ps1

.EXAMPLE
    .\Invoke-CyberWinDiag.ps1 -IncludePowerReports -IncludePerfmonReport -OutputRoot C:\Temp
#>

[CmdletBinding()]
param(
    [string] $OutputRoot,
    [switch] $IncludePerfmonReport,
    [switch] $IncludePowerReports,
    [switch] $RunIntegrityScans,
    [switch] $SkipZip
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning 'Not running elevated. Many collectors will return partial or empty results.'
    Write-Warning 'Re-launch from an Administrator PowerShell, or use CyberWinDiag.cmd.'
    $answer = Read-Host 'Continue anyway? (y/N)'
    if ($answer -notmatch '^[Yy]') { return }
}

if (-not $OutputRoot) {
    $OutputRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Reports'
    # If that resolves somewhere unwritable (read-only stick, odd layout), fall back.
    if (-not (Test-Path (Split-Path -Parent $OutputRoot))) {
        $OutputRoot = Join-Path $env:TEMP 'CyberWinDiagReports'
    }
}

$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$caseName  = '{0}-{1}' -f $env:COMPUTERNAME, $stamp
$reportDir = Join-Path $OutputRoot $caseName

try {
    New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
} catch {
    Write-Warning "Cannot write to $reportDir. Falling back to `$env:TEMP."
    $OutputRoot = Join-Path $env:TEMP 'CyberWinDiagReports'
    $reportDir  = Join-Path $OutputRoot $caseName
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$transcript = Join-Path $reportDir '_transcript.log'
try { Start-Transcript -Path $transcript -Force | Out-Null } catch { }

$script:Findings = New-Object System.Collections.Generic.List[string]
$script:StepNo   = 0

function Write-Banner {
    $b = @'
  ____ _   _ ____  _____ ____  __        _____ _   _
 / ___| | | | __ )| ____|  _ \ \ \      / /_ _| \ | |
| |   | |_| |  _ \|  _| | |_) | \ \ /\ / / | ||  \| |
| |___|  _  | |_) | |___|  _ <   \ V  V /  | || |\  |
 \____|_| |_|____/|_____|_| \_\   \_/\_/  |___|_| \_|
            D I A G N O S T I C S
'@
    Write-Host $b -ForegroundColor Cyan
    Write-Host ("  Host      : {0}" -f $env:COMPUTERNAME)
    Write-Host ("  User      : {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
    Write-Host ("  Elevated  : {0}" -f $isAdmin)
    Write-Host ("  Started   : {0}" -f (Get-Date))
    Write-Host ("  Report    : {0}" -f $reportDir)
    Write-Host ''
}

function Out-Report {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][scriptblock] $Action,
        [string] $Label
    )
    $script:StepNo++
    if (-not $Label) { $Label = $Name }
    $target = Join-Path $reportDir $Name
    Write-Host ('[{0,3}] {1}' -f $script:StepNo, $Label) -ForegroundColor DarkCyan
    try {
        $out = & $Action 2>&1
        if ($null -ne $out) {
            $out | Out-String -Width 400 | Out-File -FilePath $target -Encoding utf8
        } else {
            '(no data returned)' | Out-File -FilePath $target -Encoding utf8
        }
    } catch {
        "COLLECTOR FAILED: $($_.Exception.Message)" | Out-File -FilePath $target -Encoding utf8
        Write-Host ("      ! {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

function Add-Finding {
    param([string] $Severity, [string] $Text)
    $script:Findings.Add(('[{0,-6}] {1}' -f $Severity, $Text))
}

Write-Banner

# ---------------------------------------------------------------------------
# 1. System inventory
# ---------------------------------------------------------------------------

Out-Report 'systeminfo.txt' { systeminfo } 'System summary (systeminfo)'

Out-Report 'computerinfo.txt' {
    Get-ComputerInfo | Format-List *
} 'Consolidated computer info'

Out-Report 'os-build.txt' {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $cv | Select-Object ProductName, DisplayVersion, ReleaseId, CurrentBuild,
                        UBR, EditionID, InstallationType, BuildLabEx | Format-List
} 'OS build and edition'

Out-Report 'hotfixes.csv' {
    Get-HotFix | Sort-Object InstalledOn -Descending |
        Select-Object HotFixID, Description, InstalledOn, InstalledBy |
        ConvertTo-Csv -NoTypeInformation
} 'Installed updates'

Out-Report 'installed-software.csv' {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object DisplayName |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation |
        Sort-Object DisplayName | ConvertTo-Csv -NoTypeInformation
} 'Installed software'

Write-Host '[   ] Generating msinfo32 report (this can take a few minutes)...' -ForegroundColor DarkCyan
try {
    Start-Process -FilePath 'msinfo32.exe' `
        -ArgumentList ('/nfo "{0}"' -f (Join-Path $reportDir 'msinfo32.nfo')) `
        -Wait -WindowStyle Hidden -ErrorAction Stop
} catch { Write-Host '      ! msinfo32 failed' -ForegroundColor DarkYellow }

try {
    Start-Process -FilePath 'dxdiag.exe' `
        -ArgumentList ('/whql:off /t "{0}"' -f (Join-Path $reportDir 'dxdiag.txt')) `
        -Wait -WindowStyle Hidden -ErrorAction Stop
} catch { Write-Host '      ! dxdiag failed' -ForegroundColor DarkYellow }

# ---------------------------------------------------------------------------
# 2. Performance snapshot
# ---------------------------------------------------------------------------

Out-Report 'memory.txt' {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        TotalPhysicalGB = [math]::Round($os.TotalVisibleMemorySize/1MB, 2)
        FreePhysicalGB  = [math]::Round($os.FreePhysicalMemory/1MB, 2)
        CommitUsedGB    = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)/1MB, 2)
        CommitLimitGB   = [math]::Round($os.TotalVirtualMemorySize/1MB, 2)
        LastBootUpTime  = $os.LastBootUpTime
        UptimeDays      = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2)
    } | Format-List
    "`n--- Physical memory modules ---`n"
    Get-CimInstance Win32_PhysicalMemory |
        Select-Object BankLabel, DeviceLocator, Manufacturer, PartNumber,
            @{n='CapacityGB';e={[math]::Round($_.Capacity/1GB,0)}},
            Speed, ConfiguredClockSpeed | Format-Table -AutoSize
    "`n--- Page file ---`n"
    Get-CimInstance Win32_PageFileUsage |
        Select-Object Name, AllocatedBaseSize, CurrentUsage, PeakUsage | Format-List
} 'Memory and page file'

Out-Report 'cpu.txt' {
    Get-CimInstance Win32_Processor |
        Select-Object Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors,
            MaxClockSpeed, CurrentClockSpeed, LoadPercentage, L2CacheSize,
            L3CacheSize, VirtualizationFirmwareEnabled | Format-List
} 'CPU'

Out-Report 'top-processes.txt' {
    "--- By CPU time ---`n"
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 25 `
        Name, Id, CPU, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
        @{n='PM_MB';e={[math]::Round($_.PrivateMemorySize64/1MB,1)}},
        Handles, Description, Path | Format-Table -AutoSize
    "`n--- By working set ---`n"
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25 `
        Name, Id, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}}, Description |
        Format-Table -AutoSize
    "`n--- svchost service mapping ---`n"
    tasklist /svc /fi "imagename eq svchost.exe"
} 'Top processes'

Out-Report 'perf-counters.txt' {
    "20-second sample of disk, CPU, memory pressure`n"
    Get-Counter -Counter `
        '\Processor(_Total)\% Processor Time',
        '\System\Processor Queue Length',
        '\PhysicalDisk(_Total)\% Idle Time',
        '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Transfer',
        '\Memory\Available MBytes',
        '\Memory\Pages/sec',
        '\Paging File(_Total)\% Usage' `
        -SampleInterval 2 -MaxSamples 10 -ErrorAction Stop |
        Select-Object -ExpandProperty CounterSamples |
        Select-Object Timestamp, Path, CookedValue | Format-Table -AutoSize
} 'Live performance counters (20s)'

Out-Report 'services.csv' {
    Get-Service | Select-Object Name, DisplayName, Status, StartType |
        Sort-Object Status, Name | ConvertTo-Csv -NoTypeInformation
} 'Services'

Out-Report 'services-of-interest.txt' {
    $names = 'Spooler','WSearch','SysMain','wuauserv','BITS','DiagTrack',
             'WinDefend','SecurityHealthService','wscsvc','MpsSvc','Dnscache',
             'LanmanWorkstation','Themes','AudioSrv'
    Get-Service -Name $names -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
} 'Key service states'

Out-Report 'startup-registry.csv' {
    Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location, User | ConvertTo-Csv -NoTypeInformation
} 'Startup items'

Out-Report 'startup-folders.txt' {
    foreach ($p in @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
        "--- $p ---"
        Get-ChildItem $p -ErrorAction SilentlyContinue |
            Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
        ''
    }
} 'Startup folders'

Out-Report 'scheduled-tasks.csv' {
    Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } |
        Select-Object TaskPath, TaskName, State, Author,
            @{n='Triggers';e={ ($_.Triggers.CimClass.CimClassName) -join ';' }} |
        Sort-Object TaskPath, TaskName | ConvertTo-Csv -NoTypeInformation
} 'Enabled scheduled tasks'

if ($IncludePerfmonReport) {
    Write-Host '[   ] Running perfmon System Diagnostics report (~2 minutes)...' -ForegroundColor DarkCyan
    try {
        $perfHtml = Join-Path $reportDir 'perfmon-system-diagnostics.html'
        Start-Process -FilePath 'perfmon.exe' -ArgumentList '/report' -ErrorAction Stop
        Write-Host '      perfmon opened in a window; save the HTML manually to:' -ForegroundColor DarkYellow
        Write-Host ('      {0}' -f $perfHtml) -ForegroundColor DarkYellow
    } catch { Write-Host '      ! perfmon failed' -ForegroundColor DarkYellow }
}

# ---------------------------------------------------------------------------
# 3. Storage
# ---------------------------------------------------------------------------

Out-Report 'disks.txt' {
    "--- Physical disks ---`n"
    Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, SerialNumber,
        MediaType, BusType, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
        HealthStatus, OperationalStatus, SpindleSpeed | Format-Table -AutoSize
    "`n--- Win32_DiskDrive ---`n"
    Get-CimInstance Win32_DiskDrive |
        Select-Object Index, Model, InterfaceType, MediaType, Status, FirmwareRevision,
            @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, Partitions | Format-Table -AutoSize
} 'Physical disks'

Out-Report 'volumes.txt' {
    Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType,
        @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
        @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}},
        @{n='PctFree';e={ if ($_.Size) { [math]::Round(100*$_.SizeRemaining/$_.Size,1) } }},
        HealthStatus, AllocationUnitSize | Format-Table -AutoSize
} 'Volumes and free space'

Out-Report 'smart-failure-predict.txt' {
    Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop |
        Select-Object InstanceName, PredictFailure, Reason | Format-List
} 'SMART failure prediction'

Out-Report 'smart-reliability.txt' {
    Get-PhysicalDisk | ForEach-Object {
        $disk = $_
        $rc = $disk | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Disk                   = $disk.FriendlyName
            MediaType              = $disk.MediaType
            Health                 = $disk.HealthStatus
            Wear                   = $rc.Wear
            PowerOnHours           = $rc.PowerOnHours
            StartStopCycles        = $rc.StartStopCycleCount
            TemperatureC           = $rc.Temperature
            TemperatureMaxC        = $rc.TemperatureMax
            ReadErrorsTotal        = $rc.ReadErrorsTotal
            ReadErrorsUncorrected  = $rc.ReadErrorsUncorrected
            WriteErrorsTotal       = $rc.WriteErrorsTotal
            WriteErrorsUncorrected = $rc.WriteErrorsUncorrected
        }
    } | Format-List
} 'Storage reliability counters'

Out-Report 'trim-and-defrag.txt' {
    '--- TRIM (DisableDeleteNotify: 0 = TRIM enabled) ---'
    fsutil behavior query DisableDeleteNotify
    "`n--- Fragmentation analysis (C:) ---"
    defrag C: /A /V
} 'TRIM state and fragmentation'

Out-Report 'volume-scan.txt' {
    'Online read-only volume scan of C: (no reboot, no changes):'
    Repair-Volume -DriveLetter C -Scan -ErrorAction Stop
} 'Online volume scan'

Out-Report 'shadow-storage.txt' {
    vssadmin list shadowstorage
    ''
    vssadmin list shadows
} 'Shadow copy storage'

Out-Report 'component-store.txt' {
    Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore
} 'WinSxS component store analysis'

Out-Report 'large-dirs.txt' {
    $targets = @(
        "$env:SystemRoot\Temp",
        "$env:LOCALAPPDATA\Temp",
        "$env:SystemRoot\SoftwareDistribution\Download",
        "$env:SystemRoot\Logs\CBS",
        "$env:SystemRoot\Minidump",
        'C:\Windows.old',
        "$env:SystemRoot\System32\spool\PRINTERS"
    )
    $targetSizes = foreach ($t in $targets) {
        if (Test-Path $t) {
            $m = Get-ChildItem $t -Recurse -Force -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum
            [pscustomobject]@{
                Path   = $t
                Files  = $m.Count
                SizeMB = [math]::Round(($m.Sum / 1MB), 1)
            }
        } else {
            [pscustomobject]@{ Path = $t; Files = 'n/a'; SizeMB = 'not present' }
        }
    }
    $targetSizes | Format-Table -AutoSize
} 'Known space consumers'

# ---------------------------------------------------------------------------
# 4. Power and thermals
# ---------------------------------------------------------------------------

Out-Report 'power-plan.txt' {
    '--- Available schemes ---'
    powercfg /list
    "`n--- Active scheme ---"
    powercfg /getactivescheme
    "`n--- Available sleep states ---"
    powercfg /a
    "`n--- Processor power settings (active scheme) ---"
    powercfg /query SCHEME_CURRENT SUB_PROCESSOR
} 'Power configuration'

Out-Report 'battery.txt' {
    Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue |
        Select-Object Name, DeviceID, EstimatedChargeRemaining, BatteryStatus,
                      DesignVoltage, Chemistry | Format-List
    Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue |
        Select-Object DeviceName, ManufactureName, DesignedCapacity | Format-List
} 'Battery'

if ($IncludePowerReports) {
    Write-Host '[   ] Running powercfg reports (~1-2 minutes)...' -ForegroundColor DarkCyan
    $null = & powercfg /energy /output (Join-Path $reportDir 'energy.html') /duration 60 2>&1
    $null = & powercfg /batteryreport /output (Join-Path $reportDir 'battery.html') 2>&1
    $null = & powercfg /sleepstudy /output (Join-Path $reportDir 'sleepstudy.html') 2>&1
}

# ---------------------------------------------------------------------------
# 5. Drivers and devices
# ---------------------------------------------------------------------------

Out-Report 'problem-devices.txt' {
    $bad = Get-PnpDevice | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }
    if ($bad) {
        $bad | Select-Object Status, Class, FriendlyName, Problem, InstanceId |
            Format-Table -AutoSize -Wrap
    } else { 'No devices in a problem state.' }
} 'Problem devices'

Out-Report 'drivers.csv' {
    driverquery /v /fo csv
} 'Driver inventory'

Out-Report 'driver-store.txt' {
    pnputil /enum-drivers
} 'Third-party driver store'

Out-Report 'filter-drivers.txt' {
    '--- Loaded minifilters (AV, backup, encryption stack) ---'
    fltmc filters
    "`n--- Instances on C: ---"
    fltmc instances -v C:
} 'Filesystem filter drivers'

Out-Report 'crash-config-and-dumps.txt' {
    '--- CrashControl ---'
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue |
        Select-Object CrashDumpEnabled, DumpFile, MinidumpDir, AutoReboot, Overwrite |
        Format-List
    "`n--- Minidumps ---"
    Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object Name, @{n='SizeKB';e={[math]::Round($_.Length/1KB,0)}}, LastWriteTime |
        Format-Table -AutoSize
    "`n--- MEMORY.DMP ---"
    Get-ChildItem "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue |
        Select-Object Name, @{n='SizeMB';e={[math]::Round($_.Length/1MB,0)}}, LastWriteTime |
        Format-Table -AutoSize
} 'Crash dump config and dumps'

# ---------------------------------------------------------------------------
# 6. Event logs
# ---------------------------------------------------------------------------

$since = (Get-Date).AddDays(-14)

Out-Report 'events-summary.txt' {
    'Critical + Error events from System and Application, last 14 days,'
    'grouped by source and ID, most frequent first.'
    ''
    Get-WinEvent -FilterHashtable @{
        LogName='System','Application'; Level=1,2; StartTime=$since
    } -ErrorAction SilentlyContinue |
        Group-Object ProviderName, Id |
        Sort-Object Count -Descending |
        Select-Object Count, Name -First 40 |
        Format-Table -AutoSize
} 'Event log summary (grouped)'

Out-Report 'events-critical.csv' {
    Get-WinEvent -FilterHashtable @{
        LogName='System','Application'; Level=1,2; StartTime=$since
    } -ErrorAction SilentlyContinue -MaxEvents 1500 |
        Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName,
            @{n='Message';e={ ($_.Message -replace '\s+',' ') }} |
        ConvertTo-Csv -NoTypeInformation
} 'Critical and error events'

Out-Report 'boot-performance.txt' {
    '--- Boot durations (Event ID 100) ---'
    Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
        -MaxEvents 400 -ErrorAction SilentlyContinue |
        Where-Object Id -eq 100 |
        Select-Object -First 15 TimeCreated,
            @{n='BootMs';e={ $_.Properties[3].Value }},
            @{n='BootSec';e={ [math]::Round($_.Properties[3].Value/1000,1) }} |
        Format-Table -AutoSize
    "`n--- Boot degradation causes (101=app, 102=driver, 103=service) ---"
    Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
        -MaxEvents 600 -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -in 101,102,103,106,109,110 } |
        Select-Object -First 40 TimeCreated, Id,
            @{n='Message';e={ ($_.Message -replace '\s+',' ') }} |
        Format-List
    "`n--- Shutdown durations (Event ID 200) ---"
    Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
        -MaxEvents 400 -ErrorAction SilentlyContinue |
        Where-Object Id -eq 200 | Select-Object -First 10 TimeCreated, Id |
        Format-Table -AutoSize
} 'Boot performance events'

Out-Report 'events-hardware.txt' {
    foreach ($p in 'disk','Ntfs','WHEA-Logger','Microsoft-Windows-WHEA-Logger',
                   'Kernel-Power','Microsoft-Windows-Kernel-Power','BugCheck',
                   'Microsoft-Windows-MemoryDiagnostics-Results','volmgr','storahci') {
        $ev = Get-WinEvent -FilterHashtable @{
            LogName='System'; ProviderName=$p; StartTime=$since
        } -ErrorAction SilentlyContinue -MaxEvents 60
        if ($ev) {
            "===== $p ====="
            $ev | Select-Object TimeCreated, Id, LevelDisplayName,
                @{n='Message';e={ ($_.Message -replace '\s+',' ') }} | Format-List
            ''
        }
    }
} 'Hardware-related events'

Out-Report 'events-service-timeouts.txt' {
    Get-WinEvent -FilterHashtable @{
        LogName='System'; ProviderName='Service Control Manager'; StartTime=$since
    } -ErrorAction SilentlyContinue -MaxEvents 500 |
        Where-Object { $_.Id -in 7000,7009,7011,7022,7023,7024,7031,7034,7043 } |
        Select-Object TimeCreated, Id, @{n='Message';e={ ($_.Message -replace '\s+',' ') }} |
        Format-List
} 'Service failures and timeouts'

# ---------------------------------------------------------------------------
# 7. Network
# ---------------------------------------------------------------------------

Out-Report 'ipconfig.txt' { ipconfig /all } 'IP configuration'

Out-Report 'net-adapters.txt' {
    Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed,
        MediaType, MacAddress, DriverVersion, DriverDate | Format-List
    "`n--- Power management on adapters ---`n"
    Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue |
        Select-Object Name, WakeOnMagicPacket, DeviceSleepOnDisconnect | Format-Table -AutoSize
} 'Network adapters'

Out-Report 'dns.txt' {
    Get-DnsClientServerAddress -AddressFamily IPv4 |
        Select-Object InterfaceAlias, ServerAddresses | Format-Table -AutoSize
    "`n--- Hosts file (active entries) ---`n"
    Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction SilentlyContinue |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() }
    "`n--- WinHTTP proxy ---`n"
    netsh winhttp show proxy
    "`n--- WinINET proxy (current user) ---`n"
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue |
        Select-Object ProxyEnable, ProxyServer, AutoConfigURL | Format-List
} 'DNS, hosts file and proxy'

Out-Report 'netstat.txt' {
    Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Where-Object State -in 'Listen','Established' |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess,
            @{n='Process';e={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name }} |
        Sort-Object State, LocalPort | Format-Table -AutoSize
} 'Active connections'

Out-Report 'net-config.txt' {
    '--- TCP global parameters ---'
    netsh int tcp show global
    "`n--- Routing table ---"
    route print
    "`n--- ARP cache ---"
    arp -a
    "`n--- Firewall profiles ---"
    Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction,
        DefaultOutboundAction | Format-Table -AutoSize
} 'TCP, routing, firewall'

# ---------------------------------------------------------------------------
# 8. Printing
# ---------------------------------------------------------------------------

Out-Report 'print-spooler-service.txt' {
    Get-Service Spooler | Select-Object Name, DisplayName, Status, StartType | Format-List
    "`n--- Spool folder contents ---`n"
    $spool = "$env:SystemRoot\System32\spool\PRINTERS"
    $m = Get-ChildItem $spool -Force -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum
    [pscustomobject]@{
        Path        = $spool
        FileCount   = $m.Count
        TotalSizeMB = [math]::Round(($m.Sum/1MB),2)
    } | Format-List
    Get-ChildItem $spool -Force -ErrorAction SilentlyContinue |
        Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
} 'Print spooler service and spool folder'

Out-Report 'print-printers.txt' {
    Get-Printer -ErrorAction SilentlyContinue |
        Select-Object Name, DriverName, PortName, Shared, Published, Type,
            PrinterStatus, RenderingMode, Location, Comment | Format-List
    "`n--- Win32_Printer (offline/error state) ---`n"
    Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue |
        Select-Object Name, Default, WorkOffline, PrinterStatus, PrinterState,
            DetectedErrorState, ExtendedPrinterStatus, PrintProcessor,
            PrintJobDataType, EnableBIDI, Queued, SpoolEnabled | Format-List
} 'Printers'

Out-Report 'print-ports.txt' {
    Get-PrinterPort -ErrorAction SilentlyContinue |
        Select-Object Name, Description, PrinterHostAddress, PortNumber, Protocol,
            SNMPEnabled, SNMPCommunity, SNMPIndex, PortMonitor | Format-List
    "`n--- WSD ports (candidates for replacement with raw TCP/IP) ---`n"
    Get-PrinterPort -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'WSD*' -or $_.Description -like '*WSD*' } |
        Select-Object Name, Description, PrinterHostAddress | Format-Table -AutoSize
} 'Printer ports'

Out-Report 'print-drivers.txt' {
    Get-PrinterDriver -ErrorAction SilentlyContinue |
        Select-Object Name, MajorVersion, Manufacturer, PrinterEnvironment,
            DriverVersion, ConfigFile, DataFile, DriverPath, PrintProcessor |
        Format-List
} 'Printer drivers'

Out-Report 'print-jobs.txt' {
    $jobs = Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
        Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
    }
    if ($jobs) {
        $jobs | Select-Object PrinterName, Id, DocumentName, UserName, JobStatus,
            Size, TotalPages, PagesPrinted, SubmittedTime | Format-Table -AutoSize
    } else { 'No jobs currently queued.' }
} 'Queued print jobs'

Out-Report 'print-config.txt' {
    Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
        "===== $($_.Name) ====="
        Get-PrintConfiguration -PrinterName $_.Name -ErrorAction SilentlyContinue | Format-List
        ''
    }
    "`n--- Point and Print policy ---`n"
    Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' -ErrorAction SilentlyContinue | Format-List
    Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' -ErrorAction SilentlyContinue | Format-List
    "`n--- Windows-managed default printer ---`n"
    Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -ErrorAction SilentlyContinue |
        Select-Object Device, LegacyDefaultPrinterMode | Format-List
} 'Print configuration and policy'

Out-Report 'print-events.txt' {
    '--- Print log enablement state ---'
    wevtutil gl Microsoft-Windows-PrintService/Operational 2>&1 | Select-String 'enabled'
    "`n--- PrintService Operational (most recent 120) ---`n"
    Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Operational' -MaxEvents 120 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName,
            @{n='Message';e={ ($_.Message -replace '\s+',' ') }} | Format-List
    "`n--- PrintService Admin (most recent 120) ---`n"
    Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Admin' -MaxEvents 120 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName,
            @{n='Message';e={ ($_.Message -replace '\s+',' ') }} | Format-List
    "`n--- Spooler service events from System log ---`n"
    Get-WinEvent -FilterHashtable @{
        LogName='System'; ProviderName='Service Control Manager'; StartTime=$since
    } -ErrorAction SilentlyContinue -MaxEvents 400 |
        Where-Object Message -match 'Spooler|Print' |
        Select-Object TimeCreated, Id, @{n='Message';e={ ($_.Message -replace '\s+',' ') }} |
        Format-List
} 'Print service events'

# ---------------------------------------------------------------------------
# 9. Antivirus / Avast
# ---------------------------------------------------------------------------

Out-Report 'av-securitycenter.txt' {
    $products = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop
    "Registered antivirus products: $($products.Count)"
    if ($products.Count -gt 1) {
        'WARNING: more than one real-time AV product is registered. This is a'
        'common cause of severe slowness and file-access conflicts.'
    }
    ''
    $products | ForEach-Object {
        $hex = '{0:x6}' -f $_.productState
        [pscustomobject]@{
            Product         = $_.displayName
            ProductStateDec = $_.productState
            ProductStateHex = "0x$hex"
            RealTimeByte    = $hex.Substring(2,2)
            DefinitionByte  = $hex.Substring(4,2)
            RealTimeLikelyOn= ($hex.Substring(2,2) -in '10','11')
            DefsLikelyCurrent = ($hex.Substring(4,2) -eq '00')
            Reported        = $_.timestamp
            ExePath         = $_.pathToSignedProductExe
        }
    } | Format-List
    'NOTE: productState encoding is undocumented and varies by build.'
    'Confirm real-time protection and definition currency in the product UI.'
    ''
    '--- Registered antispyware products ---'
    Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiSpywareProduct -ErrorAction SilentlyContinue |
        Select-Object displayName, productState, timestamp | Format-List
    '--- Registered firewall products ---'
    Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct -ErrorAction SilentlyContinue |
        Select-Object displayName, productState, timestamp | Format-List
} 'Security Center AV registration'

Out-Report 'av-defender.txt' {
    Get-MpComputerStatus -ErrorAction Stop | Select-Object `
        AMRunningMode, AMServiceEnabled, AntivirusEnabled, AntispywareEnabled,
        RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled,
        OnAccessProtectionEnabled, IsTamperProtected, AMProductVersion,
        AntivirusSignatureVersion, AntivirusSignatureLastUpdated,
        FullScanEndTime, QuickScanEndTime, ComputerState | Format-List
    "`n--- Exclusions ---`n"
    $p = Get-MpPreference -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ExcludedPaths      = ($p.ExclusionPath -join '; ')
        ExcludedExtensions = ($p.ExclusionExtension -join '; ')
        ExcludedProcesses  = ($p.ExclusionProcess -join '; ')
        DisableRealtime    = $p.DisableRealtimeMonitoring
    } | Format-List
    "`n--- Recent threat detections ---`n"
    Get-MpThreatDetection -ErrorAction SilentlyContinue |
        Select-Object -First 30 InitialDetectionTime, ThreatID, ActionSuccess,
            @{n='Resources';e={ $_.Resources -join '; ' }} | Format-List
} 'Windows Defender state'

Out-Report 'av-avast-services.txt' {
    $svc = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*avast*' -or $_.DisplayName -like '*Avast*' -or $_.Name -like 'asw*' }
    if ($svc) {
        $svc | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
    } else { 'No Avast services found.' }
    "`n--- Avast processes ---`n"
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*avast*' -or $_.Name -like 'asw*' } |
        Select-Object Name, Id, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
            StartTime, Path | Format-Table -AutoSize
} 'Avast services and processes'

Out-Report 'av-avast-drivers.txt' {
    'Expected core drivers. aswMonFlt is the File Shield minifilter - if it is'
    'absent or not Running, on-access file scanning is NOT active regardless of'
    'what the Avast UI reports.'
    ''
    'aswMonFlt','aswSP','aswSnx','aswNetSec','aswbIDSDriver','aswRdr2','aswStm',
    'aswVmm','aswKbd','aswArPot','aswElam','aswbLoga','aswbuniv' | ForEach-Object {
        $d = Get-CimInstance Win32_SystemDriver -Filter "Name='$_'" -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Driver  = $_
            Present = [bool]$d
            State   = $d.State
            Start   = $d.StartMode
            Status  = $d.Status
        }
    } | Format-Table -AutoSize
    "`n--- All asw* / avast drivers present ---`n"
    Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'asw*' -or $_.DisplayName -like '*avast*' } |
        Select-Object Name, DisplayName, State, StartMode, PathName | Format-Table -AutoSize
    "`n--- Driver files on disk ---`n"
    Get-ChildItem "$env:SystemRoot\System32\drivers\asw*" -ErrorAction SilentlyContinue |
        Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
} 'Avast kernel drivers'

Out-Report 'av-avast-version-and-defs.txt' {
    '--- Product version ---'
    foreach ($exe in @(
        'C:\Program Files\Avast Software\Avast\AvastUI.exe',
        'C:\Program Files (x86)\Avast Software\Avast\AvastUI.exe',
        'C:\Program Files\Avast Software\Avast\AvastSvc.exe')) {
        if (Test-Path $exe) {
            (Get-Item $exe).VersionInfo |
                Select-Object FileName, ProductName, ProductVersion, FileVersion | Format-List
        }
    }
    "`n--- Virus definitions (folder names are date-stamped YYMMDDNN) ---`n"
    Get-ChildItem 'C:\ProgramData\Avast Software\Avast\defs' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 8 Name, LastWriteTime |
        Format-Table -AutoSize
    "`n--- Log files (newest first) ---`n"
    Get-ChildItem 'C:\ProgramData\Avast Software\Avast\log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 20 `
        Name, @{n='SizeKB';e={[math]::Round($_.Length/1KB,1)}}, LastWriteTime |
        Format-Table -AutoSize
    "`n--- Quarantine (Virus Chest) ---`n"
    Get-ChildItem 'C:\ProgramData\Avast Software\Avast\chest' -ErrorAction SilentlyContinue |
        Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
    "`n--- Install directories present ---`n"
    'C:\Program Files\Avast Software','C:\Program Files (x86)\Avast Software',
    'C:\ProgramData\Avast Software' | ForEach-Object {
        [pscustomobject]@{ Path = $_; Exists = (Test-Path $_) }
    } | Format-Table -AutoSize
} 'Avast version, definitions and logs'

# ---------------------------------------------------------------------------
# 10. Optional integrity scans (WRITES TO THE SYSTEM)
# ---------------------------------------------------------------------------

if ($RunIntegrityScans) {
    Write-Host ''
    Write-Host '  Running integrity scans. This modifies the system and takes 10-30 minutes.' -ForegroundColor Yellow
    Write-Host ''

    Out-Report 'dism-scanhealth.txt'    { Dism.exe /Online /Cleanup-Image /ScanHealth }    'DISM ScanHealth'
    Out-Report 'dism-restorehealth.txt' { Dism.exe /Online /Cleanup-Image /RestoreHealth } 'DISM RestoreHealth'
    Out-Report 'sfc-scannow.txt'        { sfc.exe /scannow }                               'SFC scannow'

    Out-Report 'sfc-findings.txt' {
        Select-String -Path "$env:SystemRoot\Logs\CBS\CBS.log" -Pattern '\[SR\]' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Line | Select-Object -Last 400
    } 'SFC findings from CBS.log'
}

# ---------------------------------------------------------------------------
# 11. Summary / triage sheet
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Building summary...' -ForegroundColor DarkCyan

# Heuristic checks feeding _SUMMARY.txt
try {
    $sysVol = Get-Volume -DriveLetter C -ErrorAction Stop
    $pctFree = [math]::Round(100 * $sysVol.SizeRemaining / $sysVol.Size, 1)
    if     ($pctFree -lt 5)  { Add-Finding 'HIGH'   "System volume only $pctFree% free. Windows needs headroom for updates, paging and defrag." }
    elseif ($pctFree -lt 15) { Add-Finding 'MEDIUM' "System volume $pctFree% free. Aim for 20%+." }
} catch { }

try {
    $sysDisk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq (
        Get-Partition -DriveLetter C -ErrorAction SilentlyContinue).DiskNumber }
    if ($sysDisk.MediaType -eq 'HDD') {
        Add-Finding 'HIGH' "System disk is a mechanical HDD ($($sysDisk.FriendlyName)). This is the single largest cause of slowness on Windows 10. Recommend SSD."
    }
    foreach ($d in (Get-PhysicalDisk)) {
        if ($d.HealthStatus -ne 'Healthy') {
            Add-Finding 'HIGH' "Disk '$($d.FriendlyName)' reports HealthStatus=$($d.HealthStatus). Back up and replace."
        }
    }
} catch { }

try {
    $pf = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
    foreach ($p in $pf) {
        if ($p.PredictFailure) { Add-Finding 'HIGH' "SMART predicts imminent failure on $($p.InstanceName). Image the drive before doing anything else." }
    }
} catch { }

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize/1MB, 1)
    if     ($totalGB -lt 4.5) { Add-Finding 'HIGH'   "Only $totalGB GB RAM. Windows 10 with a browser and an AV suite is not usable at this level." }
    elseif ($totalGB -lt 8.5) { Add-Finding 'MEDIUM' "$totalGB GB RAM. Tight; check commit charge under normal load." }
    $uptime = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
    if ($uptime -gt 14) { Add-Finding 'LOW' "Uptime is $uptime days. Try a genuine Restart before deeper diagnosis." }
} catch { }

try {
    $avs = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    if (-not $avs) {
        Add-Finding 'HIGH' 'No antivirus product registered with Windows Security Center.'
    } elseif (@($avs).Count -gt 1) {
        Add-Finding 'HIGH' ("Multiple AV products registered: {0}. Remove all but one." -f (($avs.displayName) -join ', '))
    }
    foreach ($a in $avs) {
        $hex = '{0:x6}' -f $a.productState
        if ($hex.Substring(2,2) -notin '10','11') {
            Add-Finding 'HIGH' "$($a.displayName): real-time protection appears DISABLED (state 0x$hex). Verify in the UI."
        }
        if ($hex.Substring(4,2) -ne '00') {
            Add-Finding 'MEDIUM' "$($a.displayName): definitions appear OUT OF DATE (state 0x$hex). Check the update log."
        }
    }
} catch { }

try {
    $avastSvc = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Avast*' -or $_.Name -like '*avast*' }
    if ($avastSvc) {
        foreach ($s in ($avastSvc | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' })) {
            Add-Finding 'HIGH' "Avast service '$($s.Name)' is set to Automatic but is $($s.Status)."
        }
        $monFlt = Get-CimInstance Win32_SystemDriver -Filter "Name='aswMonFlt'" -ErrorAction SilentlyContinue
        if (-not $monFlt) {
            Add-Finding 'HIGH' 'Avast is installed but the aswMonFlt File Shield minifilter is absent. On-access scanning is not active. Repair or clean-reinstall.'
        } elseif ($monFlt.State -ne 'Running') {
            Add-Finding 'HIGH' "aswMonFlt (File Shield) state is $($monFlt.State), not Running."
        }
        $defs = Get-ChildItem 'C:\ProgramData\Avast Software\Avast\defs' -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($defs -and ((Get-Date) - $defs.LastWriteTime).TotalDays -gt 7) {
            Add-Finding 'MEDIUM' ("Newest Avast definition folder is {0} days old ({1}). Updates may be failing." -f `
                [math]::Round(((Get-Date) - $defs.LastWriteTime).TotalDays,1), $defs.Name)
        }
    }
} catch { }

try {
    $md = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($md -and $md.AMRunningMode -eq 'Normal' -and (Get-Service -ErrorAction SilentlyContinue |
        Where-Object DisplayName -like '*Avast*')) {
        Add-Finding 'MEDIUM' 'Defender is in Normal (active) mode while Avast is also installed. Two active real-time engines will fight over every file access.'
    }
} catch { }

try {
    $spool = Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" -Force -ErrorAction SilentlyContinue
    if ($spool.Count -gt 10) {
        Add-Finding 'MEDIUM' "$($spool.Count) files left in the spool folder. Jobs have been failing. Stop Spooler, clear the folder, restart."
    }
    $stuck = Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
        Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
    } | Where-Object { $_.JobStatus -notmatch 'Normal|Printing|Spooling|Retained' }
    if ($stuck) { Add-Finding 'MEDIUM' "$(@($stuck).Count) print job(s) in an abnormal state. Clear the queue." }

    $wsd = Get-PrinterPort -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'WSD*' -or $_.Description -like '*WSD*' }
    if ($wsd) {
        Add-Finding 'MEDIUM' ("{0} WSD printer port(s) present: {1}. WSD re-resolves the device per job and is a leading cause of slow first-page times. Replace with a raw TCP/IP port on 9100." -f `
            @($wsd).Count, (($wsd.Name) -join ', '))
    }
    $snmp = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object SNMPEnabled -eq $true
    if ($snmp) {
        Add-Finding 'LOW' ("SNMP status polling enabled on port(s): {0}. Disable if the printer is slow to respond." -f (($snmp.Name) -join ', '))
    }
    $printers = Get-Printer -ErrorAction SilentlyContinue
    $dupes = $printers | Where-Object { $_.Name -match '\(Copy \d+\)|\(\d+\)$' }
    if ($dupes) { Add-Finding 'LOW' ("Possible ghost/duplicate printers: {0}" -f (($dupes.Name) -join ', ')) }
    if (@($printers).Count -gt 8) {
        Add-Finding 'LOW' "$(@($printers).Count) printers installed. Each one is enumerated and status-polled by apps; this slows Print dialogs."
    }
    $offline = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object WorkOffline
    if ($offline) { Add-Finding 'LOW' ("Printer(s) marked offline: {0}" -f (($offline.Name) -join ', ')) }
} catch { }

try {
    $spoolerSvc = Get-Service Spooler -ErrorAction SilentlyContinue
    if ($spoolerSvc.Status -ne 'Running') {
        Add-Finding 'HIGH' "Print Spooler service is $($spoolerSvc.Status). Nothing will print."
    }
} catch { }

try {
    $printLog = wevtutil gl Microsoft-Windows-PrintService/Operational 2>&1 | Out-String
    if ($printLog -match 'enabled:\s*false') {
        Add-Finding 'LOW' 'PrintService/Operational log is disabled. Enable it (wevtutil sl Microsoft-Windows-PrintService/Operational /e:true), reproduce the fault, then re-collect.'
    }
} catch { }

try {
    $dumps = Get-ChildItem "$env:SystemRoot\Minidump\*.dmp" -ErrorAction SilentlyContinue
    if ($dumps) {
        $recent = $dumps | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) }
        if ($recent) { Add-Finding 'HIGH' "$(@($recent).Count) crash dump(s) in the last 30 days. Open them in BlueScreenView." }
    }
    $cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction SilentlyContinue
    if ($cc.CrashDumpEnabled -eq 0) {
        Add-Finding 'LOW' 'Crash dump creation is disabled. Enable it before investigating reported crashes.'
    }
} catch { }

try {
    $boots = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
        -MaxEvents 200 -ErrorAction SilentlyContinue | Where-Object Id -eq 100
    if ($boots) {
        $avg = ($boots | Select-Object -First 5 | ForEach-Object { $_.Properties[3].Value } |
            Measure-Object -Average).Average / 1000
        $avg = [math]::Round($avg, 1)
        if     ($avg -gt 120) { Add-Finding 'HIGH'   "Average boot time over the last 5 boots: $avg s. See boot-performance.txt for the named culprits (events 101/102/103)." }
        elseif ($avg -gt 60)  { Add-Finding 'MEDIUM' "Average boot time over the last 5 boots: $avg s." }
    }
} catch { }

try {
    $diskEv = Get-WinEvent -FilterHashtable @{
        LogName='System'; ProviderName='disk'; StartTime=(Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue
    $bad = $diskEv | Where-Object { $_.Id -in 7,11,51,153 }
    if ($bad) {
        Add-Finding 'HIGH' "$(@($bad).Count) disk error event(s) (IDs 7/11/51/153) in the last 30 days. Strongly suggests failing storage or a bad cable."
    }
    $whea = Get-WinEvent -FilterHashtable @{
        LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue
    if ($whea) { Add-Finding 'HIGH' "$(@($whea).Count) WHEA hardware error event(s) in the last 30 days. See events-hardware.txt." }
} catch { }

try {
    $bad = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }
    if ($bad) { Add-Finding 'MEDIUM' "$(@($bad).Count) device(s) in a problem state. See problem-devices.txt." }
} catch { }

try {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($cpu.CurrentClockSpeed -and $cpu.MaxClockSpeed -and
        $cpu.CurrentClockSpeed -lt ($cpu.MaxClockSpeed * 0.5)) {
        Add-Finding 'MEDIUM' "CPU reporting $($cpu.CurrentClockSpeed) MHz against a rated $($cpu.MaxClockSpeed) MHz. Check power plan and thermals with HWiNFO64 under load."
    }
} catch { }

try {
    $hib = powercfg /a 2>&1 | Out-String
    if ($hib -match 'Hibernate') {
        Add-Finding 'LOW' 'Hibernation/Fast Startup is available. Remember that "Shut down" is not a real reboot; use Restart when testing.'
    }
} catch { }

$summary = Join-Path $reportDir '_SUMMARY.txt'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('CYBERWINDIAGNOSTICS - TRIAGE SUMMARY')
[void]$sb.AppendLine('====================================')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('Host          : {0}' -f $env:COMPUTERNAME))
[void]$sb.AppendLine(('Collected     : {0}' -f (Get-Date)))
[void]$sb.AppendLine(('Collected by  : {0}\{1}' -f $env:USERDOMAIN, $env:USERNAME))
[void]$sb.AppendLine(('Elevated      : {0}' -f $isAdmin))
try {
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    [void]$sb.AppendLine(('Model         : {0} {1}' -f $cs.Manufacturer, $cs.Model))
    [void]$sb.AppendLine(('Serial        : {0}' -f $bios.SerialNumber))
    [void]$sb.AppendLine(('BIOS          : {0} ({1})' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate))
} catch { }
try {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [void]$sb.AppendLine(('OS            : {0} {1} build {2}.{3}' -f `
        $cv.ProductName, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR))
} catch { }
[void]$sb.AppendLine(('Report folder : {0}' -f $reportDir))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('FINDINGS')
[void]$sb.AppendLine('--------')
if ($script:Findings.Count -eq 0) {
    [void]$sb.AppendLine('No automated findings tripped. That does not mean the machine is healthy -')
    [void]$sb.AppendLine('it means the heuristics in this script did not fire. Read the detail files,')
    [void]$sb.AppendLine('starting with events-summary.txt, top-processes.txt and perf-counters.txt.')
} else {
    $order = @{ 'HIGH' = 0; 'MEDIUM' = 1; 'LOW' = 2 }
    $sorted = $script:Findings | Sort-Object {
        if ($_ -match '^\[(\w+)') { $order[$Matches[1]] } else { 99 }
    }
    foreach ($f in $sorted) { [void]$sb.AppendLine($f) }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('WHERE TO LOOK NEXT')
[void]$sb.AppendLine('------------------')
[void]$sb.AppendLine('Slow generally    : perf-counters.txt, top-processes.txt, disks.txt, smart-reliability.txt')
[void]$sb.AppendLine('Slow boot         : boot-performance.txt, startup-registry.csv, scheduled-tasks.csv')
[void]$sb.AppendLine('Slow printing     : print-ports.txt, print-printers.txt, print-drivers.txt, print-events.txt')
[void]$sb.AppendLine('Antivirus state   : av-securitycenter.txt, av-avast-drivers.txt, av-defender.txt')
[void]$sb.AppendLine('Crashes / hangs   : events-hardware.txt, crash-config-and-dumps.txt, events-critical.csv')
[void]$sb.AppendLine('Network / Wi-Fi   : net-adapters.txt, dns.txt, net-config.txt')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('This collection was read-only unless -RunIntegrityScans was specified.')
$sb.ToString() | Out-File -FilePath $summary -Encoding utf8

Write-Host ''
Write-Host '=== SUMMARY ===' -ForegroundColor Cyan
Get-Content $summary | ForEach-Object {
    if     ($_ -match '^\[HIGH')   { Write-Host $_ -ForegroundColor Red }
    elseif ($_ -match '^\[MEDIUM') { Write-Host $_ -ForegroundColor Yellow }
    elseif ($_ -match '^\[LOW')    { Write-Host $_ -ForegroundColor DarkGray }
    else                           { Write-Host $_ }
}

# ---------------------------------------------------------------------------
# 12. Package
# ---------------------------------------------------------------------------

try { Stop-Transcript | Out-Null } catch { }

if (-not $SkipZip) {
    $zip = Join-Path $OutputRoot ('{0}.zip' -f $caseName)
    try {
        Compress-Archive -Path (Join-Path $reportDir '*') -DestinationPath $zip -Force -ErrorAction Stop
        Write-Host ''
        Write-Host ('Evidence bundle: {0}' -f $zip) -ForegroundColor Green
    } catch {
        Write-Warning ("Zip failed: {0}" -f $_.Exception.Message)
        Write-Host ('Report folder: {0}' -f $reportDir) -ForegroundColor Green
    }
} else {
    Write-Host ''
    Write-Host ('Report folder: {0}' -f $reportDir) -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done. Read _SUMMARY.txt first.' -ForegroundColor Cyan
Write-Host 'Safely eject the USB drive before removing it.' -ForegroundColor DarkYellow
