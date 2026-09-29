# CYBERWINDIAGNOSTICS

> Portable Windows 10 diagnostic runbook and toolkit.
> Boot it, plug it, run it, walk away with a report.

**Project site:** [CyberWinDiagnostics for Windows](https://cybercore-tech.github.io/CyberWinDiagnostics/) · [Source repository](https://github.com/cybercore-tech/CyberWinDiagnostics)

> **Personal USB build status (2026-09-28):** the USB includes portable Notepad++,
> 7-Zip Extra, CrystalDiskInfo, and a local Sysinternals Suite copy. It also
> has a fresh Microsoft Safety Scanner with a signature-checked refresh button.
> These third-party binaries are only on the personal USB, not in the Git
> repository or shareable ZIP. Do not distribute the USB or its binaries.
> See [TOOL-SOURCES.md](TOOL-SOURCES.md) for official sources and
> [Tools/Bundle-INFO.md](Tools/Bundle-INFO.md) for exact versions, hashes, and
> use restrictions. The collector uses Windows built-ins.

A field manual for answering four questions on a machine you don't own:

1. **Why is it slow?**
2. **Why is printing slow?**
3. **Is Avast actually protecting this thing?**
4. **What else is quietly broken?**

Everything here runs from a USB stick. No installers on the client machine, no
leftovers, all output written back to the stick as a timestamped evidence
bundle.

---

## Contents

- [0. Ground rules](#0-ground-rules)
- [Install from a shell](#install-from-a-shell)
- [1. Building the stick](#1-building-the-stick)
- [2. Toolkit manifest](#2-toolkit-manifest)
- [3. Phase 0 — Intake](#3-phase-0--intake)
- [4. Phase 1 — Fast triage (10 minutes)](#4-phase-1--fast-triage-10-minutes)
- [5. Phase 2 — System inventory](#5-phase-2--system-inventory)
- [6. Phase 3 — Why is it slow](#6-phase-3--why-is-it-slow)
- [7. Phase 4 — Network](#7-phase-4--network)
- [8. Phase 5 — Printing](#8-phase-5--printing)
- [9. Phase 6 — Avast verification](#9-phase-6--avast-verification)
- [10. Phase 7 — Malware second opinion](#10-phase-7--malware-second-opinion)
- [11. Phase 8 — Automated collection](#11-phase-8--automated-collection)
- [12. Phase 9 — Remediation order of operations](#12-phase-9--remediation-order-of-operations)
- [13. Report template](#13-report-template)
- [Appendix A — Command cheat sheet](#appendix-a--command-cheat-sheet)
- [Appendix B — Event ID reference](#appendix-b--event-id-reference)
- [Appendix C — Avast services and drivers](#appendix-c--avast-services-and-drivers)
- [Appendix D — Gotchas](#appendix-d--gotchas)

---

## 0. Ground rules

| Rule | Why |
| --- | --- |
| **Measure before you touch.** | Half of "slow PC" jobs get "fixed" by three unrelated changes and nobody learns anything. Collect first. |
| **One change at a time, then retest.** | Otherwise you can't attribute the fix. |
| **Never run a full `chkdsk /r` on a disk with failing SMART.** | It can be the thing that finishes off a dying drive. Image it first. |
| **No registry cleaners, no "optimizers", no driver-updater tools.** | They are the cause on a meaningful share of these machines. |
| **Get consent before scanning or removing anything.** | Especially on a work machine. |
| **Back up before remediation, not after.** | At minimum: user profile, browser profiles, Outlook `.ost`/`.pst`, license keys. |

### Two shells, know which one you're in

Most of this runbook is PowerShell. A few things are legacy `cmd.exe` only.

```powershell
# Confirm you are elevated (must print True)
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')

# Confirm your PowerShell version (Win10 ships 5.1)
$PSVersionTable.PSVersion
```

Open an elevated PowerShell fast: `Win+X`, then `A` (Windows PowerShell (Admin)).

### Running scripts from a USB stick

Windows will block them by default. Two obstacles: execution policy, and
Mark-of-the-Web on files that came from the internet.

```powershell
# Per-process bypass — does not persist, does not need a policy change
powershell.exe -NoProfile -ExecutionPolicy Bypass -File E:\CyberWinDiagnostics\Scripts\Invoke-CyberWinDiag.ps1

# Strip Mark-of-the-Web from anything you downloaded onto the stick
Get-ChildItem E:\CyberWinDiagnostics -Recurse | Unblock-File
```

Never set `Set-ExecutionPolicy Unrestricted` machine-wide on a client box.

## Install from a shell

On Linux or macOS, run the installer from the mounted USB directory to create
`./CyberWinDiagnostics`, or pass `--dest` with the target folder. This prepares
the Windows toolkit files on the drive; the PowerShell collector itself runs
on Windows. No `sudo` is used.

```sh
curl -fsSL https://raw.githubusercontent.com/cybercore-tech/CyberWinDiagnostics/main/install.sh | sh -s --
```

Choose a destination explicitly:

```sh
curl -fsSL https://raw.githubusercontent.com/cybercore-tech/CyberWinDiagnostics/main/install.sh | sh -s -- --dest "/path/to/mounted/USB/CyberWinDiagnostics"
```

The installer needs `curl`, `unzip`, and `sha256sum` (Linux) or `shasum`
(macOS). It verifies the downloaded source ZIP against the repository's
published SHA-256 file and refuses a non-empty destination by default. For an
existing CyberWinDiagnostics folder, `--update` overlays project files while
preserving reports and unrelated files; it does not remove obsolete files.
The shareable ZIP contains no optional third-party utility binaries. Review
[`install.sh`](install.sh) before running the one-line bootstrap if you want
to inspect what the shell command executes.

---

## 1. Building the stick

### 1.1 Layout

```
E:\CyberWinDiagnostics\
├── README.md                     # this document
├── CyberWinDiag.cmd              # double-clickable launcher (elevates, runs script)
├── Scripts\
│   ├── Invoke-CyberWinDiag.ps1   # main collector
│   ├── Fix-PrintSpooler.ps1      # optional targeted remediations
│   ├── Update-MicrosoftSafetyScanner.ps1
│   └── Refresh-and-Run-MSERT.cmd # refreshes, verifies, then launches MSERT
├── Tools\
│   ├── Sysinternals\             # local USB copy; do not redistribute
│   ├── NirSoft\                  # optional; see TOOL-SOURCES.md
│   ├── Storage\                  # CrystalDiskInfo portable
│   ├── Hardware\                 # optional; see TOOL-SOURCES.md
│   ├── Scanners\                 # optional; see TOOL-SOURCES.md
│   └── Misc\                     # optional; see TOOL-SOURCES.md
├── Reports\                      # output lands here: HOSTNAME-YYYYMMDD-HHMMSS\
└── Notes\
    └── report-template.md
```

To refresh and run Microsoft's expiring second-opinion scanner, double-click
`Scripts\Refresh-and-Run-MSERT.cmd` while online. It downloads the current
64-bit copy, verifies its Microsoft signature, then launches it. Each copy
expires ten days after download; refresh before each use. Internet access is
needed for this step.

### 1.2 Filesystem choice

| FS | Use when | Notes |
| --- | --- | --- |
| **exFAT** | Default choice, and what Ventoy uses | Handles >4 GB files, mounts everywhere. No journal — always eject properly. Can't hold alternate data streams, so Mark-of-the-Web never attaches to your tools and SmartScreen won't block them. |
| **NTFS** | You want journaling | Survives a bad unplug better. `ntfs3` is in-kernel since 5.15 so Linux performance is fine. Carries `Zone.Identifier` streams, so you may need `Unblock-File` on Windows. |
| **FAT32** | Never, for the data partition | 4 GB file cap rules out a Windows install ISO (~5.5 GB) or any disk image. Windows won't even format >32 GB as FAT32. Only appropriate for a small UEFI boot partition. |

**Recommendation: let Ventoy do it.** Ventoy creates two partitions itself — a
large **exFAT** partition labeled `Ventoy` that holds both the bootable ISOs and
your `CyberWinDiagnostics\` tree, plus a ~32 MB vfat partition labeled
`VTOYEFI` for the Ventoy binaries. You don't partition anything by hand, and you
never write to `VTOYEFI`.

Only format manually (section 1.3, Options A/B) if you're skipping the bootable
side entirely.

### 1.3 Prep from Linux

```bash
# Identify the stick. Check the size twice before you nuke it.
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT

# Unmount anything auto-mounted
sudo umount /dev/sdX*   # replace sdX

# Option A: single NTFS data partition
sudo wipefs -a /dev/sdX
sudo parted -s /dev/sdX mklabel gpt
sudo parted -s /dev/sdX mkpart primary ntfs 1MiB 100%
sudo mkfs.ntfs -f -L CYBERWIN /dev/sdX1

# Option B: exFAT instead
sudo mkfs.exfat -n CYBERWIN /dev/sdX1

# Mount and lay out the tree
sudo mkdir -p /mnt/cyberwin && sudo mount /dev/sdX1 /mnt/cyberwin
mkdir -p /mnt/cyberwin/CyberWinDiagnostics/{Scripts,Tools/{Sysinternals,NirSoft,Storage,Hardware,Scanners,Misc},Reports,Notes}
```

**Option C — Ventoy** (recommended): one exFAT partition holds both the
bootable ISOs (MemTest86, a Windows 10 install ISO, a Linux rescue ISO) and the
toolkit.

On Arch, `ventoy-bin` installs to `/opt/ventoy/` and puts wrappers on your PATH.
Use the wrappers — `Ventoy2Disk.sh` uses relative paths to `./tool/` and fails
from an arbitrary cwd.

```bash
# Clear any stale partition table first. dd only zeroes the front of the disk,
# leaving the GPT backup header at the END intact — which is why partprobe then
# complains and udisks re-mounts a phantom vfat partition.
sudo wipefs -a /dev/sdX
sudo blockdev --rereadpt /dev/sdX

sudo ventoy -i /dev/sdX -g       # -i install (destructive), -g GPT
sudo ventoy -u /dev/sdX          # -u upgrades Ventoy in place, keeps your data
```

Confirm the device by **serial**, not by letter — `sdb` shifts as you swap
sticks, and `-i` is unrecoverable:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN /dev/sdX
```

Afterwards, udisks will often auto-mount the wrong partition — `VTOYEFI` instead
of `Ventoy`. Fix it and load the stick:

```bash
lsblk -o NAME,LABEL,FSTYPE,MOUNTPOINTS /dev/sdX
udisksctl unmount -b /dev/sdX2        # release VTOYEFI; never write to it
udisksctl mount   -b /dev/sdX1        # mount the Ventoy data partition

cp -r ~/Toolkits/CyberWinDiagnostics /run/media/$USER/Ventoy/
cp ~/Downloads/*.iso                 /run/media/$USER/Ventoy/
sync

udisksctl unmount  -b /dev/sdX1
udisksctl power-off -b /dev/sdX       # the "Safely Remove Hardware" equivalent
```

`power-off` matters on exFAT, which has no journal.

### 1.4 Line endings — this one bites

`.cmd` and `.bat` files **must** have CRLF line endings or `cmd.exe` will
misparse them. PowerShell `.ps1` tolerates LF, but be consistent.

```bash
sudo apt install dos2unix   # provides unix2dos
find /mnt/cyberwin/CyberWinDiagnostics -name '*.cmd' -o -name '*.bat' | xargs unix2dos
```

If you version the toolkit in git, add a `.gitattributes`:

```gitattributes
*.cmd text eol=crlf
*.bat text eol=crlf
*.ps1 text eol=crlf
*.md  text eol=lf
```

### 1.5 Finish up

```bash
sync && sudo umount /mnt/cyberwin
```

---

## 2. Toolkit manifest

The entries below are optional recommendations. Notepad++, 7-Zip Extra,
CrystalDiskInfo, Sysinternals, and a refreshable Microsoft Safety Scanner are
present on this USB; other listed tools are not included.
Their cost, availability, supported Windows versions, and license terms differ;
check current details before use. See [TOOL-SOURCES.md](TOOL-SOURCES.md).

### Suggested tools for common cases

| Tool | Vendor | What it answers |
| --- | --- | --- |
| **Autoruns** | Sysinternals | Everything that starts automatically, including the stuff Task Manager hides |
| **Process Explorer** | Sysinternals | What is actually eating CPU/RAM/handles; which service is in which `svchost` |
| **Process Monitor** | Sysinternals | File/registry/network calls in real time — the tool for "slow when I do X" |
| **CrystalDiskInfo** | Crystal Dew World | SMART health, reallocated sectors, drive hours, temperature |
| **HWiNFO64** | REALiX | Live clocks, temps, thermal-throttle flags, power limits |
| **WizTree** | Antibody Software | Reads the NTFS MFT directly — full disk space map in seconds |
| **LatencyMon** | Resplendence | DPC/ISR latency — the answer to stuttering and audio dropouts |
| **BlueScreenView** | NirSoft | Reads minidumps without WinDbg |

### Secondary

| Tool | Purpose |
| --- | --- |
| **smartmontools** (`smartctl.exe`) | Raw SMART attributes when CrystalDiskInfo's summary isn't enough |
| **TCPView** | Live socket table with process names |
| **RAMMap** | Where memory actually went (paged pool, standby, driver locked) |
| **ShellExView / ShellMenuView** | Explorer shell extensions — a top cause of slow right-click and slow file dialogs |
| **CPU-Z** | Confirm RAM is running dual-channel and at rated speed |
| **Everything** (voidtools) | Instant filename search, useful for finding stray logs and dumps |
| **7-Zip portable** | Extract everything else |
| **Notepad++ portable** | Read logs without Notepad choking on a 200 MB CBS.log |

### Second-opinion scanners

| Tool | Notes |
| --- | --- |
| **Microsoft Safety Scanner** (`MSERT.exe`) | Microsoft-signed, expires after ~10 days, re-download each trip |
| **Kaspersky Virus Removal Tool** (`KVRT.exe`) | Aggressive, good rootkit detection |
| **Malwarebytes AdwCleaner** | Best-in-class for adware, browser hijacks, PUPs |
| **Sophos Scan & Clean** | Runs alongside an installed AV without conflict |
| **ESET Online Scanner** | Needs internet, downloads engine at runtime |

> **Heads up:** Avast and Defender both flag several NirSoft and PsTools
> binaries as riskware, because they *are* dual-use. Expect the stick to get
> quarantined mid-job. Note it in the report rather than adding a blanket
> exclusion for a removable drive.

### Bootable media worth keeping on the Ventoy partition

- **MemTest86** (free edition) — the only trustworthy RAM test; run 4+ passes
- **A Windows 10 install ISO** — for `Startup Repair`, `DISM` offline servicing, and the recovery console
- **A live Linux ISO** — for `ddrescue` imaging a dying drive and pulling data off an unbootable machine

---

## 3. Phase 0 — Intake

Do this before you touch a keyboard. Write the answers down.

- [ ] What exactly is slow — boot, login, opening apps, one specific app, file browsing, printing, web?
- [ ] When did it start? What changed around then (update, new software, new printer, new AV)?
- [ ] Is it slow constantly, or in bursts? How long do the bursts last?
- [ ] Does a reboot help, and for how long?
- [ ] Is it on Wi-Fi or Ethernet? Does the printer live on USB, network, or a print server?
- [ ] Any recent BSODs, freezes, or hard power-offs?
- [ ] Is there more than one antivirus installed?
- [ ] Is the data backed up? (Assume no.)

Then, before changing anything:

```powershell
# Create a restore point you can fall back to
Enable-ComputerRestore -Drive "C:\"
Checkpoint-Computer -Description "CyberWinDiag baseline" -RestorePointType MODIFY_SETTINGS
```

> `Checkpoint-Computer` is rate-limited to one restore point per 24 hours by
> default. If it silently does nothing, that's why.

---

## 4. Phase 1 — Fast triage (10 minutes)

Five commands that identify the cause on maybe 60% of "slow PC" calls.

### 4.1 Is the disk saturated?

```powershell
# Watch % idle time and queue length for 20 seconds
Get-Counter -Counter '\PhysicalDisk(_Total)\% Idle Time',
                     '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
                     '\PhysicalDisk(_Total)\Avg. Disk sec/Transfer' `
            -SampleInterval 2 -MaxSamples 10
```

Interpretation:

| Reading | Meaning |
| --- | --- |
| `% Idle Time` near 0 for sustained periods | Disk-bound. This is the #1 cause of "slow" on machines with a spinning HDD. |
| `Avg. Disk sec/Transfer` > 0.025 (25 ms) sustained | Latency is bad. > 0.1 s means something is very wrong (dying drive, or HDD thrashing). |
| `Avg. Disk Queue Length` > 2 per spindle | Requests are backing up. |

### 4.2 Is it a mechanical drive?

```powershell
Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, Size, HealthStatus, OperationalStatus
```

If `MediaType` is `HDD` and the machine runs Windows 10 with a modern browser
and an AV suite, **the drive is the diagnosis.** An SSD upgrade fixes more of
these calls than every software tweak combined. Everything else in this document
still applies, but set expectations early.

### 4.3 Is memory exhausted?

```powershell
$os = Get-CimInstance Win32_OperatingSystem
[pscustomobject]@{
    TotalGB      = [math]::Round($os.TotalVisibleMemorySize/1MB, 2)
    FreeGB       = [math]::Round($os.FreePhysicalMemory/1MB, 2)
    CommitUsedGB = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory)/1MB, 2)
    CommitLimGB  = [math]::Round($os.TotalVirtualMemorySize/1MB, 2)
}
```

4 GB on Windows 10 is functionally broken in 2026. 8 GB is tight. If
`CommitUsedGB` is near `CommitLimGB`, the machine is paging constantly and no
amount of tuning will save it.

### 4.4 What's on top right now?

```powershell
Get-Process | Sort-Object -Property CPU -Descending |
    Select-Object -First 15 Name, Id, CPU, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}}, Description |
    Format-Table -AutoSize
```

For `svchost.exe` entries, resolve which services are inside:

```cmd
tasklist /svc /fi "imagename eq svchost.exe"
```

### 4.5 How bad was the last boot?

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 200 |
    Where-Object { $_.Id -eq 100 } |
    Select-Object -First 10 TimeCreated, @{n='BootMs';e={$_.Properties[3].Value}} |
    Format-Table -AutoSize
```

Then find *what* made it slow:

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -MaxEvents 500 |
    Where-Object { $_.Id -in 101,102,103,106,109 } |
    Select-Object TimeCreated, Id, Message |
    Format-List
```

IDs 101/102/103 name the specific application, driver, and service that
degraded boot. This is the single most under-used log in Windows.

---

## 5. Phase 2 — System inventory

Establish what you're actually working on.

```powershell
# Broad strokes
Get-ComputerInfo | Select-Object CsName, CsManufacturer, CsModel, OsName,
    OsVersion, WindowsVersion, OsBuildNumber, OsArchitecture,
    CsProcessors, CsTotalPhysicalMemory, BiosSeralNumber, BiosReleaseDate,
    OsInstallDate, OsLastBootUpTime

# Windows build and servicing state
winver                        # GUI, quickest read
[Environment]::OSVersion
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
```

> Windows 10 reached end of support in **October 2025**. Any Win10 machine you
> touch now is unpatched unless it's on an ESU program or an LTSC branch. Check
> the edition — `Get-ComputerInfo | Select OsName` — and flag it in the report.
> This matters for the security section as much as the performance one.

### Full dumps to file

```cmd
:: Text inventory
systeminfo > %USERPROFILE%\Desktop\systeminfo.txt

:: Full System Information report (NFO opens in msinfo32; TXT is greppable)
msinfo32 /nfo "%USERPROFILE%\Desktop\msinfo32.nfo"
msinfo32 /report "%USERPROFILE%\Desktop\msinfo32.txt"

:: DirectX / display / audio devices and driver dates
dxdiag /t "%USERPROFILE%\Desktop\dxdiag.txt"
```

### Installed software and updates

```powershell
# 64-bit and 32-bit uninstall keys. More reliable than Win32_Product,
# which triggers an MSI reconfiguration on every installed package.
$paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $paths |
    Where-Object DisplayName |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
    Sort-Object DisplayName

# Patch level
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 25
```

### Reliability history — the one-screen summary

```cmd
perfmon /rel
```

Reliability Monitor gives you a calendar of crashes, hangs, failed updates and
driver failures. Start here when the user's story is vague.

### Built-in system diagnostics report

```cmd
:: Collects 60 seconds of perf data and produces an HTML report with
:: findings, top processes, disk breakdown, and hardware config.
perfmon /report
```

Takes about two minutes. Genuinely good output. Save the HTML to the stick.

---

## 6. Phase 3 — Why is it slow

### 6.1 Boot and login

```powershell
# Startup items (the registry Run keys + Startup folders)
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User | Format-Table -AutoSize

# Startup folders, both user and all-users
Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"

# Scheduled tasks that fire at logon or boot
Get-ScheduledTask | Where-Object {
    $_.Triggers.CimClass.CimClassName -match 'Logon|Boot' -and $_.State -ne 'Disabled'
} | Select-Object TaskPath, TaskName, State | Format-Table -AutoSize
```

Then run **Autoruns** (`autoruns64.exe`) as admin. Configure it properly:

1. `Options` → check **Hide Microsoft entries** and **Hide Windows entries**
2. `Options` → **Scan Options** → check **Verify code signatures** and **Check VirusTotal.com**
3. Work the tabs: `Logon`, `Scheduled Tasks`, `Services`, `Drivers`, `Explorer`, `Winlogon`, `AppInit`, `Image Hijacks`, `LSA Providers`

Anything unsigned in `Drivers`, `AppInit`, `LSA Providers`, or `Image Hijacks`
gets investigated. Unsigned entries in `Logon` are usually just sloppy vendors.

**Fast Startup** is worth knowing about. It makes shutdown a hibernate, which
means "I rebooted and it's still broken" often means the machine never actually
cold-booted:

```powershell
# Check
powercfg /a
# Disable hiberfile and Fast Startup entirely (also reclaims RAM-sized disk space)
powercfg /h off
```

Use `Restart`, not `Shut down` → `Power on`, when you need a genuine kernel restart.

### 6.2 Live contention — where the time actually goes

**Process Explorer** (`procexp64.exe`), run as admin, is the correct tool:

- `View` → `System Information` for a proper CPU/memory/IO/GPU dashboard
- Set `View` → `Update Speed` → `1 second`
- Add columns: `Context Switch Delta`, `I/O Read Bytes`, `I/O Write Bytes`, `Handle Count`, `Private Bytes`
- Double-click a process → `Threads` tab → sort by CPU → `Stack` to see what a
  pegged thread is doing. For a wedged `svchost`, this names the DLL.
- Sort by `Delta Total Bytes` to find the process hammering the disk

**Resource Monitor** for a lighter-weight look:

```cmd
resmon
```

Go to the `Disk` tab, expand `Disk Activity`, sort by `Total (B/sec)`. The
`Response Time (ms)` column is the one to watch — three-digit response times
mean the storage subsystem is the bottleneck.

**Process Monitor** when the complaint is "slow when I do X":

1. Launch `procmon64.exe`, immediately `Ctrl+E` to stop capture, `Ctrl+X` to clear
2. `Filter` → add `Result` `is` `SUCCESS` `Exclude` (cuts the noise dramatically)
3. `Ctrl+E` to start, reproduce the slow action, `Ctrl+E` to stop
4. `Tools` → `File Summary` and `Tools` → `Process Activity Summary` — sort by total duration
5. Look for retry loops, `NAME NOT FOUND` storms, and network paths being polled

That workflow is how you catch things like an app hunting for a decommissioned
network share on every file-open dialog.

### 6.3 Storage health

Run **CrystalDiskInfo** first — it gives a red/yellow/blue health verdict in one
screen. Then get the raw numbers:

```powershell
# Vendor-reported failure prediction
Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus |
    Select-Object InstanceName, PredictFailure, Reason

# Wear, errors, hours, temperature (best support on NVMe)
Get-PhysicalDisk | Get-StorageReliabilityCounter |
    Select-Object DeviceId, Wear, PowerOnHours, Temperature,
                  ReadErrorsTotal, ReadErrorsUncorrected,
                  WriteErrorsTotal, WriteErrorsUncorrected
```

For real SMART attributes, `smartctl` from smartmontools:

```cmd
smartctl.exe --scan
smartctl.exe -a /dev/sda
smartctl.exe -a -d nvme /dev/nvme0
```

Attributes that mean "replace this drive now":

| Attribute | Threshold |
| --- | --- |
| `Reallocated_Sector_Ct` (05) | Any non-zero value that is *growing* |
| `Current_Pending_Sector` (C5) | Any non-zero value |
| `Offline_Uncorrectable` (C6) | Any non-zero value |
| `Reported_Uncorrect` (BB) | Any non-zero value |
| `UDMA_CRC_Error_Count` (C7) | Growing → bad SATA cable or port, not the drive |
| SSD `Percentage_Used` / `Wear_Leveling_Count` | > 90% consumed |

Filesystem and volume state:

```powershell
# Online scan, no reboot, no downtime — always safe to run
Repair-Volume -DriveLetter C -Scan
# or:
chkdsk C: /scan

# Space
Get-Volume | Select-Object DriveLetter, FileSystemLabel, FileSystem,
    @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}},
    @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}},
    @{n='PctFree';e={[math]::Round(100*$_.SizeRemaining/$_.Size,1)}},
    HealthStatus
```

Below ~10-15% free on the system volume, Windows starts to hurt: no room for
Update staging, page file growth, or defrag. Below 5% it's a primary cause.

Find the space with **WizTree** (MFT-based, seconds even on a full 2 TB drive).
Then clean:

```cmd
:: Modern cleanup UI (includes Windows Update cleanup, previous installations)
cleanmgr /d C:

:: Analyze the WinSxS component store before touching it
DISM /Online /Cleanup-Image /AnalyzeComponentStore

:: Then, if it recommends cleanup:
DISM /Online /Cleanup-Image /StartComponentCleanup
```

Usual space hogs: `C:\Windows.old` (safe to remove via `cleanmgr`),
`C:\Windows\Temp`, `%LOCALAPPDATA%\Temp`, `%LOCALAPPDATA%\Packages\...\LocalCache`,
Teams/Chrome/Edge caches, OneDrive-duplicated content, hibernation file, VSS
shadow copies (`vssadmin list shadowstorage`), and orphaned Windows Update
downloads in `C:\Windows\SoftwareDistribution\Download`.

TRIM and defrag:

```cmd
:: 0 = TRIM is enabled (correct for SSDs)
fsutil behavior query DisableDeleteNotify

:: Analyze only, no changes
defrag C: /A /V

:: Re-issue TRIM on an SSD (safe; not a defrag)
defrag C: /L

:: Actual defrag — HDDs only, never routinely on an SSD
defrag C: /O /V
```

### 6.4 Thermals, power, and throttling

A machine that scores fine in every software check but feels slow under load is
usually thermally throttled or stuck on a power-saver plan.

```powershell
# Are we running below rated clock?
Get-CimInstance Win32_Processor |
    Select-Object Name, NumberOfCores, NumberOfLogicalProcessors,
                  MaxClockSpeed, CurrentClockSpeed, LoadPercentage

# Active power plan
powercfg /list
powercfg /getactivescheme

# Dump the full active scheme to check processor min/max state
powercfg /query SCHEME_CURRENT SUB_PROCESSOR
```

A `CurrentClockSpeed` sitting far below `MaxClockSpeed` while under load means
throttling or a capped `Maximum processor state`. To set a sane plan:

```cmd
:: Balanced (safe default)
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
:: High performance
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
```

The definitive answer comes from **HWiNFO64** → `Sensors`. Watch, under load:

- Core temperatures (sustained 95-100 °C on Intel = throttling)
- `Core Thermal Throttling` / `Core Power Limit Exceeded` flags — HWiNFO shows these as Yes/No sensors
- Effective clocks vs. rated
- Battery `Wear Level` and `Charge Level` on laptops

Also run the built-in power audit:

```cmd
powercfg /energy /output "%USERPROFILE%\Desktop\energy.html" /duration 60
powercfg /batteryreport /output "%USERPROFILE%\Desktop\battery.html"
powercfg /sleepstudy /output "%USERPROFILE%\Desktop\sleepstudy.html"
```

`/energy` flags devices blocking sleep, USB suspend failures, and drivers with
excessive processor utilization. `/batteryreport` gives design capacity vs. full
charge capacity — a battery at 40% of design will cause aggressive throttling on
many OEM laptops.

Physical causes worth naming in the report: dust-blocked heatsink fins, dried
thermal paste, a failed fan, a laptop used on carpet, or a third-party charger
that isn't negotiating full power.

### 6.5 Drivers and DPC latency

```powershell
# Devices in a problem state
Get-PnpDevice | Where-Object { $_.Status -ne 'OK' } |
    Select-Object Status, Class, FriendlyName, InstanceId, Problem | Format-Table -AutoSize

# Third-party driver packages in the store — the usual suspects live here
pnputil /enum-drivers

# Old-school but fast
driverquery /v /fo csv > "%USERPROFILE%\Desktop\drivers.csv"
```

For stutter, crackling audio, or mouse lag, run **LatencyMon** for 10 minutes
under normal use. It names the offending driver. The recurring culprits:
`ndis.sys` / Wi-Fi drivers, `nvlddmkm.sys`, `storport.sys`, `ACPI.sys`,
Killer/Intel network suites, and RGB/fan-control utilities.

Driver policy for a diagnostic visit: get **chipset, storage, network, and GPU**
drivers from the OEM or chip vendor directly. Do not install a "driver updater."
Do not let Windows Update be the source for GPU drivers if the machine has a
discrete card and a working OEM package.

### 6.6 OS integrity

Order matters. Component store first, then system files.

```cmd
:: 1. Check the component store (the source SFC repairs from)
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth

:: 2. Repair it if needed (requires internet, or a mounted install ISO)
DISM /Online /Cleanup-Image /RestoreHealth

:: 2b. Offline source, if no internet or WU is broken.
::     Mount the Windows 10 ISO as drive D:, then:
DISM /Online /Cleanup-Image /RestoreHealth /Source:esd:D:\sources\install.esd:1 /LimitAccess
::     or, for a WIM-based ISO:
DISM /Online /Cleanup-Image /RestoreHealth /Source:wim:D:\sources\install.wim:1 /LimitAccess

:: 3. Now repair system files
sfc /scannow
```

Logs to read afterwards:

- `C:\Windows\Logs\CBS\CBS.log` — SFC and servicing detail
- `C:\Windows\Logs\DISM\dism.log` — DISM detail

Extract just the SFC findings from the giant CBS log:

```powershell
Select-String -Path C:\Windows\Logs\CBS\CBS.log -Pattern '\[SR\]' |
    Select-Object -ExpandProperty Line |
    Out-File "$env:USERPROFILE\Desktop\sfc-findings.txt"
```

If SFC reports unrepairable corruption after a successful `RestoreHealth`, the
next step is an in-place upgrade (repair install) from the ISO — keeps apps and
data, replaces the OS.

### 6.7 The event log sweep

```powershell
# Critical + Error across System and Application, last 14 days, grouped
$since = (Get-Date).AddDays(-14)
Get-WinEvent -FilterHashtable @{ LogName='System','Application'; Level=1,2; StartTime=$since } -ErrorAction SilentlyContinue |
    Group-Object ProviderName, Id |
    Sort-Object Count -Descending |
    Select-Object Count, Name -First 30 |
    Format-Table -AutoSize
```

Grouping first is the trick — it turns 4,000 events into a ranked list of eight
real problems. Then drill into whatever tops the list:

```powershell
Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='disk'; StartTime=$since } |
    Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List
```

Crash dumps:

```powershell
Get-ChildItem C:\Windows\Minidump\*.dmp -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 10
Get-ChildItem C:\Windows\MEMORY.DMP -ErrorAction SilentlyContinue
```

Open the minidumps in **BlueScreenView** — it gives you the bugcheck code and
the driver named in the stack without installing WinDbg. Confirm dumps are even
being written:

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' |
    Select-Object CrashDumpEnabled, DumpFile, MinidumpDir, AutoReboot
```

`CrashDumpEnabled` of `0` means no dumps are being kept, which is why "it just
restarts and there's nothing in the logs."

### 6.8 Memory test

Software checks can't rule out bad RAM. Windows' own tester:

```cmd
mdsched.exe
```

Reboots and runs. Results land in the System log:

```powershell
Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-MemoryDiagnostics-Results' } -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, Message | Format-List
```

`mdsched` is weak. If you suspect RAM, boot **MemTest86** from the Ventoy
partition and run at least four full passes. Also check RAM is running in
dual-channel at its rated speed via CPU-Z → `Memory` tab (`Channel #`, `DRAM
Frequency` — double it for the DDR rating) and `SPD` tab.

### 6.9 The usual software suspects on a slow Win10 box

| Suspect | Check | Notes |
| --- | --- | --- |
| Two antivirus products | See [Phase 6](#9-phase-6--avast-verification) | Guaranteed slowdown. Real-time engines fight over every file open. |
| Windows Search indexing | `Get-Service WSearch`; Indexing Options | Rebuild if the index is corrupt; the rebuild itself pegs the disk for hours |
| Windows Update stuck in a loop | `Get-Service wuauserv,bits`; check `SoftwareDistribution` size | A wedged update service will hammer CPU and disk indefinitely |
| SysMain / Superfetch | `Get-Service SysMain` | Helps HDDs, occasionally pathological on SSDs. Test with it stopped before disabling. |
| OneDrive / Dropbox / Google Drive resync | Process Explorer IO columns | A full resync looks exactly like malware from a performance standpoint |
| Browser extensions and open tabs | Browser task manager (`Shift+Esc` in Chrome/Edge) | 80 tabs on 8 GB of RAM is not a Windows problem |
| Explorer shell extensions | ShellExView | Slow right-click, slow save dialogs, hanging Explorer |
| Telemetry/diagnostic tracing left enabled | `Get-Service DiagTrack` | Usually minor; occasionally not |
| Vendor bloat (OEM update managers, "PC health" suites) | Autoruns | Frequent offenders. Remove, don't disable. |

Service state check:

```powershell
Get-Service WSearch, SysMain, wuauserv, BITS, DiagTrack, Spooler, WinDefend |
    Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
```

---

## 7. Phase 4 — Network

Relevant to printing, cloud sync, and "the internet is slow" reports.

```powershell
Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
Get-NetIPConfiguration -Detailed
Get-DnsClientServerAddress -AddressFamily IPv4
```

```cmd
ipconfig /all
route print
arp -a
netsh int tcp show global
netsh wlan show interfaces
netsh wlan show wlanreport
```

`netsh wlan show wlanreport` produces an HTML report at
`C:\ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html` with a
session/disconnect timeline. Very good for intermittent Wi-Fi.

Reachability and latency:

```powershell
Test-NetConnection 1.1.1.1 -InformationLevel Detailed
Test-NetConnection www.microsoft.com -Port 443
Resolve-DnsName microsoft.com
```

```cmd
pathping 1.1.1.1
```

`pathping` gives per-hop packet loss, which `tracert` doesn't.

Speed link negotiation matters: a gigabit NIC showing `LinkSpeed` of 100 Mbps
means a bad cable, a bad port, or a duplex mismatch.

Only reset the stack if you have evidence of stack corruption, and warn the user
it will drop VPN configs and static IPs:

```cmd
netsh int ip reset
netsh winsock reset
ipconfig /flushdns
:: reboot required
```

---

## 8. Phase 5 — Printing

Slow printing is almost never "the printer is slow." It's one of six things.
Work them in this order.

### 8.1 Inventory the print subsystem

```powershell
Get-Service Spooler | Select-Object Name, Status, StartType

Get-Printer | Select-Object Name, DriverName, PortName, Shared, Published,
    PrinterStatus, RenderingMode, Type | Format-Table -AutoSize

Get-PrinterPort | Select-Object Name, Description, PrinterHostAddress,
    PortNumber, SNMPEnabled, SNMPCommunity, Protocol | Format-Table -AutoSize

Get-PrinterDriver | Select-Object Name, MajorVersion, Manufacturer,
    PrinterEnvironment, ConfigFile, DataFile | Format-Table -AutoSize

Get-PrintJob -PrinterName * -ErrorAction SilentlyContinue |
    Select-Object PrinterName, Id, DocumentName, JobStatus, Size, SubmittedTime

# Offline / error state, which Get-Printer doesn't surface well
Get-CimInstance Win32_Printer |
    Select-Object Name, Default, WorkOffline, PrinterStatus, DetectedErrorState, PrintProcessor |
    Format-Table -AutoSize
```

Save this whole block — it's the single most useful artifact for a printing case.

### 8.2 Cause 1 — a jammed spool queue

A stuck job blocks everything behind it, and Windows will retry it forever.

```powershell
# Look for jobs stuck in Error / Retained / Paused state
Get-PrintJob -PrinterName * | Where-Object { $_.JobStatus -notmatch 'Normal|Printing|Spooling' }

# Nuke the queue (the classic fix)
Stop-Service -Name Spooler -Force
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
Start-Service -Name Spooler
```

Check the spool folder is where you think it is and isn't full of orphans:

```powershell
Get-ChildItem "$env:SystemRoot\System32\spool\PRINTERS" | Measure-Object -Property Length -Sum
```

Hundreds of `.SHD`/`.SPL` files means jobs have been failing silently for a long
time.

### 8.3 Cause 2 — WSD ports (the big one)

Windows loves to auto-create **WSD** (Web Services on Devices) printer ports.
They rely on multicast discovery and re-resolve the device on every job. When
the network doesn't cooperate — VLANs, Wi-Fi isolation, a changed DHCP lease —
each print job stalls for 15-60 seconds before anything comes out.

Identify them:

```powershell
Get-PrinterPort | Where-Object { $_.Name -like 'WSD*' -or $_.Description -like '*WSD*' } |
    Select-Object Name, Description, PrinterHostAddress
```

**Fix: replace with a Standard TCP/IP raw port.** Give the printer a static IP
or a DHCP reservation first.

```powershell
# 1. Confirm the printer answers on the raw print port
Test-NetConnection 192.168.1.50 -Port 9100      # RAW / JetDirect
Test-NetConnection 192.168.1.50 -Port 631       # IPP
Test-NetConnection 192.168.1.50 -Port 515       # LPR

# 2. Create a raw TCP/IP port with SNMP off
Add-PrinterPort -Name 'IP_192.168.1.50' -PrinterHostAddress '192.168.1.50' -PortNumber 9100

# 3. Point the printer at it
Set-Printer -Name 'HP LaserJet Whatever' -PortName 'IP_192.168.1.50'

# 4. Remove the old WSD port once nothing references it
Remove-PrinterPort -Name 'WSD-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

**Disable SNMP status polling** on existing standard ports if it's on. Bidi
status queries against a printer that doesn't answer promptly add a fixed delay
to every job:

```powershell
Get-PrinterPort | Where-Object SNMPEnabled -eq $true | Select-Object Name, PrinterHostAddress
Set-PrinterPort -Name 'IP_192.168.1.50' -SNMPEnabled $false
```

Also turn off **bidirectional support** in the printer's properties → `Ports`
tab if status isn't needed.

### 8.4 Cause 3 — the driver and rendering mode

```powershell
Get-PrinterDriver | Select-Object Name, MajorVersion, PrinterEnvironment
```

| `MajorVersion` | Model | Notes |
| --- | --- | --- |
| `3` | v3 driver | Runs in the spooler process, full-featured, can be unstable, vendor-specific |
| `4` | v4 driver | Sandboxed, uses a shared print class driver, generally faster and safer |

Guidance:

- Prefer the **v4 / "class driver"** or the vendor's **PCL6 / Universal Print
  Driver** over a full "feature" install with toolbars, scan suites and tray
  monitors.
- For a big-document, slow-printing complaint on a laser printer, **PCL beats
  PostScript** on rendering time in most cases.
- Avoid host-based / GDI drivers (common on cheap inkjets) — all rendering
  happens on the PC, so a slow PC means slow printing by design.

Rendering location — client-side vs. server-side — matters a lot on shared
printers:

```powershell
Get-Printer | Select-Object Name, RenderingMode

# Force server-side rendering (offloads the client, good for weak PCs)
Set-Printer -Name 'Shared Printer' -RenderingMode SSR
# Force client-side rendering (offloads a hammered print server)
Set-Printer -Name 'Shared Printer' -RenderingMode CSR
```

Spooling behavior, per printer (`Printer properties` → `Advanced`):

| Setting | Effect |
| --- | --- |
| **Spool print documents so program finishes printing faster** → *Start printing immediately* | Fastest time-to-first-page |
| → *Start printing after last page is spooled* | Slower start, but prevents mid-job stalls on slow links |
| **Print directly to the printer** | Bypasses the spooler entirely. Great diagnostic: if this is fast, the problem is the spooler/driver chain, not the printer. |
| **Enable advanced printing features** (EMF) | Turning this **off** forces the RAW datatype. Fixes a surprising number of slow/garbled print jobs. |

Command-line equivalents:

```powershell
Set-PrintConfiguration -PrinterName 'HP LaserJet Whatever' -Color $false -DuplexingMode TwoSidedLongEdge
Get-PrintConfiguration -PrinterName 'HP LaserJet Whatever' | Format-List
```

The legacy printer UI CLI is still the fastest way to do bulk work:

```cmd
:: Show all its options
rundll32 printui.dll,PrintUIEntry /?

:: Server properties dialog (drivers, ports, forms)
rundll32 printui.dll,PrintUIEntry /s /t2

:: Delete a printer
rundll32 printui.dll,PrintUIEntry /dl /n "Old Printer"

:: Add a printer with a specific driver and port
rundll32 printui.dll,PrintUIEntry /if /b "New Printer" /f "C:\drv\oemsetup.inf" /r "IP_192.168.1.50" /m "HP Universal Printing PCL 6"
```

### 8.5 Cause 4 — ghost printers and default-printer churn

```powershell
Get-Printer | Select-Object Name, PortName, DriverName | Sort-Object Name
```

Look for `Printer (Copy 1)`, `Printer (Copy 2)`, duplicates on different ports,
and printers pointing at dead ports. Each one gets enumerated and status-polled
by apps at startup, which is why an app's `File` → `Print` dialog can take 30
seconds to open.

Also disable "Let Windows manage my default printer" (Settings → Devices →
Printers & scanners), which retargets the default based on location and confuses
users into thinking printing failed.

```powershell
# Check the registry equivalent
Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name LegacyDefaultPrinterMode -ErrorAction SilentlyContinue
```

Remove stale drivers from the store after deleting printers:

```powershell
Remove-PrinterDriver -Name 'Dead Vendor Driver v3'
# Then check the driver store
pnputil /enum-drivers | Select-String -Pattern 'Printer' -Context 3,3
```

### 8.6 Cause 5 — the print event logs (turn them on)

The `Operational` log is off by default. Enable it, reproduce, read it.

```cmd
wevtutil sl Microsoft-Windows-PrintService/Operational /e:true
wevtutil sl Microsoft-Windows-PrintService/Admin /e:true
```

```powershell
# Everything the print service did, newest first
Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Operational' -MaxEvents 100 |
    Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-List

# Just completed jobs, with the time they took to render
Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Operational' -MaxEvents 500 |
    Where-Object Id -eq 307 |
    Select-Object TimeCreated, Message | Format-List

# Errors and warnings only
Get-WinEvent -FilterHashtable @{
    LogName='Microsoft-Windows-PrintService/Operational','Microsoft-Windows-PrintService/Admin'
    Level=1,2,3
} -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message | Format-List
```

Event ID **307** is "document printed" and includes the job size, page count and
the byte count actually sent. Compare its timestamp against when the user hit
print — that interval tells you whether time is being lost in the application,
the spooler, or on the wire.

Also check the spooler service isn't crashing and restarting:

```powershell
Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Service Control Manager' } -MaxEvents 200 |
    Where-Object Message -match 'Spooler' |
    Select-Object TimeCreated, Id, Message | Format-List
```

### 8.7 Cause 6 — everything else

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Long pause before the first page, then it prints fine | DNS/WSD resolution timeout, or SNMP bidi polling | `Resolve-DnsName printername`; disable SNMP; use IP not hostname |
| Slow only on Wi-Fi | Client isolation, weak signal, or power-saving on the NIC | `netsh wlan show interfaces`; disable NIC power saving in Device Manager |
| Slow only for one user | Corrupt user profile print settings, or GPO-mapped printers at logon | Test with a fresh local profile |
| Slow only from one app | App-side rendering (Adobe is notorious) | In Acrobat, `Advanced` → **Print as image**; also try a PDF print to a different app |
| Slow only for shared/print-server printers | Point-and-Print restrictions, Kerberos, or SSR/CSR mismatch | See below |
| Slow after a Windows update | Post-2021 Point-and-Print hardening | See below |
| Huge jobs, tiny documents | EMF spooling with a host-based driver | Disable advanced printing features → RAW |
| Printer prints, then hangs on the next job | Bidi/status deadlock, or a full spool folder | Clear spool folder; disable bidi |

Shared-printer specifics. Microsoft's 2021 print security hardening
(PrintNightmare response) restricted non-admin driver installation, which breaks
or slows shared-printer connections on unpatched-driver environments:

```powershell
# Point and Print restrictions
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' -ErrorAction SilentlyContinue
# Driver install restriction (1 = admins only)
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' -Name RestrictDriverInstallationToAdministrators -ErrorAction SilentlyContinue
```

The correct fix is a v4 or signed package-aware driver installed locally, not
loosening the restriction. Note it in the report and escalate to whoever owns
the print server.

Printer driver isolation, if the spooler is crashing:

```powershell
# Isolate a flaky v3 driver into its own process so it can't take the spooler down
Set-PrinterDriver -Name 'Flaky Vendor Driver' -PrinterEnvironment 'Windows x64'
# Isolation mode is set per-driver in Print Management (printmanagement.msc)
# → Drivers → right-click → Set Driver Isolation → Isolated
```

Full spooler reset, when nothing else works:

```powershell
Stop-Service Spooler -Force
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse -ErrorAction SilentlyContinue
# Remove all printers and ports, then re-add cleanly
Get-Printer | Where-Object { -not $_.Shared } | Remove-Printer
Get-PrinterPort | Where-Object { $_.Name -notmatch '^(LPT|COM|FILE|PORTPROMPT|nul|SHRFAX)' } | Remove-PrinterPort -ErrorAction SilentlyContinue
Start-Service Spooler
# Then re-add via Add-PrinterPort / Add-Printer with a chosen driver
```

Run `printmanagement.msc` for the GUI view of all of this — drivers, ports,
forms, and a filtered "all printers with jobs" view.

---

## 9. Phase 6 — Avast verification

Three separate questions: **is it registered with Windows**, **are its
components actually running**, and **does it actually block anything**. Answer
all three; a broken AV usually passes the first one.

### 9.1 Is it registered and does Windows think it's healthy?

Windows Security Center keeps a registry of AV products. This is authoritative
for "is a real-time AV present and current":

```powershell
Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct |
    Select-Object displayName, productState, timestamp, pathToSignedProductExe, pathToSignedReportingExe |
    Format-List
```

`productState` is an undocumented bitfield. Decode it like this:

```powershell
Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct | ForEach-Object {
    $hex = '{0:x6}' -f $_.productState
    [pscustomobject]@{
        Product      = $_.displayName
        StateHex     = "0x$hex"
        RealTimeByte = $hex.Substring(2,2)
        DefsByte     = $hex.Substring(4,2)
        RealTimeOn   = $hex.Substring(2,2) -in '10','11'
        DefsCurrent  = $hex.Substring(4,2) -eq '00'
        Reported     = $_.timestamp
    }
}
```

Reading it:

| Byte | Value | Meaning |
| --- | --- | --- |
| Middle byte (real-time) | `10` / `11` | Real-time protection enabled |
| Middle byte | `00` / `01` | Real-time protection **off** |
| Last byte (definitions) | `00` | Definitions up to date |
| Last byte | `10` | Definitions **outdated** |

> The encoding isn't documented by Microsoft and has varied across builds. Treat
> it as a strong signal, then confirm in the Avast UI. Don't report from this
> alone.

Multiple entries in this class means **multiple AV products installed** — flag
it immediately as a probable performance cause.

Also confirm Defender has correctly stepped aside:

```powershell
Get-MpComputerStatus | Select-Object AMRunningMode, AMServiceEnabled,
    RealTimeProtectionEnabled, AntivirusEnabled, AntispywareEnabled,
    AntivirusSignatureLastUpdated, IsTamperProtected
```

| `AMRunningMode` | Meaning |
| --- | --- |
| `Normal` | Defender is the active AV — if Avast is installed too, that's a conflict |
| `Passive` / `SxS Passive Mode` | Correct when a third-party AV is registered and working |
| `Not running` | Defender is off, Avast should be carrying the load — verify below |

### 9.2 Are Avast's components actually running?

```powershell
# Services
Get-Service | Where-Object { $_.Name -like '*avast*' -or $_.DisplayName -like '*Avast*' } |
    Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize

# Kernel-mode drivers — these are the shields. Missing/stopped drivers here
# mean the shields are not protecting anything, whatever the UI claims.
Get-CimInstance Win32_SystemDriver |
    Where-Object { $_.Name -like 'asw*' -or $_.DisplayName -like '*avast*' } |
    Select-Object Name, DisplayName, State, Status, StartMode | Format-Table -AutoSize

# Processes
Get-Process | Where-Object { $_.Name -like '*avast*' -or $_.Name -like 'asw*' } |
    Select-Object Name, Id, @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}}, Path
```

Expected: the main service running with `StartType` `Automatic`, the behavior
shield agent running, and a set of `asw*` drivers in `Running` state. See
[Appendix C](#appendix-c--avast-services-and-drivers) for the full list.

Product version and install path:

```powershell
$avastExe = 'C:\Program Files\Avast Software\Avast\AvastUI.exe'
if (Test-Path $avastExe) {
    (Get-Item $avastExe).VersionInfo | Select-Object ProductName, ProductVersion, FileVersion
}
```

### 9.3 Are the definitions current?

Avast stores virus definitions ("VPS") in dated folders:

```powershell
Get-ChildItem 'C:\ProgramData\Avast Software\Avast\defs' -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 5 Name, LastWriteTime
```

Folder names are date-stamped (`YYMMDDNN`). Anything more than a few days old
means updates are failing — check the update log:

```powershell
Get-ChildItem 'C:\ProgramData\Avast Software\Avast\log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 15 Name, Length, LastWriteTime
```

Key logs in that folder: the update log, the shield/service log, and the
self-defense log. Read them with Notepad++ from the stick.

### 9.4 Are all Core Shields on?

This part is UI-only. Open Avast → `Menu` → `Settings` → `Protection` → `Core
Shields` and confirm all four:

- [ ] **File Shield** — scans files on open/write. If this is off, the AV is decorative.
- [ ] **Web Shield** — HTTP/HTTPS inspection. Common cause of slow browsing and, occasionally, slow network printing.
- [ ] **Mail Shield** — POP3/IMAP/SMTP scanning. Common cause of slow Outlook send/receive.
- [ ] **Behavior Shield** — runtime behavior monitoring.

Then check `Menu` → `Settings` → `Troubleshooting`:

- [ ] **Passive Mode** is **off** (if it's on, Avast is not protecting anything)
- [ ] **Enable Avast Self-Defense** is **on**
- [ ] **Enable hardware-assisted virtualization** — note the setting; it conflicts with Hyper-V, WSL2, VirtualBox and Docker Desktop, and is a real cause of slowness and VM failures on dev machines

And `Menu` → `Settings` → `General` → `Update`:

- [ ] Virus definitions and application updates set to **automatic**
- [ ] Click `Check for updates` and confirm both succeed

Subscription state: an expired paid tier can leave shields disabled while the UI
still looks mostly normal. Check `Menu` → `My subscriptions`.

### 9.5 Does it actually block something?

Registration and running services don't prove detection works. Test it with
**EICAR** — a harmless, industry-standard test file that every AV is required to
detect.

Go to **eicar.org** and download the test files over HTTPS. Doing it that way
tests two things at once:

1. **Web Shield** should block the download at the browser
2. If you get the file onto disk, **File Shield** should quarantine it instantly

If neither happens, real-time protection is not functioning regardless of what
the UI says. Document the result and reinstall.

> The EICAR file is not malware — it's a defined test string that AV vendors
> detect by agreement. It cannot harm the machine. Tell the user what you're
> doing before an alarm pops up.

### 9.6 Is Avast the cause of the slowness?

Test it properly instead of guessing:

1. Right-click the Avast tray icon → `Avast shields control` → **Disable for 10 minutes**
2. Reproduce the slow operation and time it
3. Re-enable the shields (verify they came back — see 9.2)
4. Compare

If disabling shields fixes it, the fix is **targeted exclusions**, not removing
the AV. Add exclusions under `Menu` → `Settings` → `General` → `Exceptions` for:

- Build/compile output directories and package caches (`node_modules`, `target`, `.venv`, `__pycache__`)
- Database and VM disk files (`.vhdx`, `.vmdk`, `.ldf`, `.mdf`)
- Line-of-business app directories that touch thousands of small files
- Backup software staging paths

Avast components that are commonly worth turning off on a slow machine:

| Component | Why |
| --- | --- |
| **Avast Cleanup / Cleanup Premium** | Background scanning and nagging; a genuine resource cost |
| **Software Updater** (automatic mode) | Silently downloads and installs third-party updates |
| **Rescue Disk / Sandbox / SafeZone browser** | Rarely used, always resident |
| **Hardware-assisted virtualization** | Conflicts with Hyper-V/WSL2/Docker/VirtualBox |
| **"Do Not Disturb" mode** | Suppresses notifications, including real detections |

### 9.6a Cross-check: is Avast the printing problem?

Web Shield's HTTPS interception and the firewall (on paid tiers) can both
interfere with network printing.

```powershell
# Is the print traffic being blocked or filtered?
Test-NetConnection 192.168.1.50 -Port 9100
Get-NetFirewallRule -Enabled True | Where-Object DisplayName -match 'Avast|Print' |
    Select-Object DisplayName, Direction, Action, Profile
```

Test by disabling shields for 10 minutes and printing. If that fixes it, add the
printer's IP and the spooler executable as exceptions rather than leaving
shields off.

### 9.7 Repair or clean removal

If Avast is registered but non-functional (shields won't stay on, definitions
won't update, services won't start):

**Repair first** — `Settings` → `Apps` → `Avast ...` → `Modify` → **Repair**.
Reboot. Re-run section 9.2 and 9.5.

**Clean removal** if repair fails. A partial uninstall leaves `asw*` filter
drivers behind, and those *will* cause slowness and boot problems:

1. Download the **Avast Clear** utility (`avastclear.exe`) from Avast's site onto the stick
2. Boot to Safe Mode: `msconfig` → `Boot` → check `Safe boot`, reboot
3. Run `avastclear.exe`, point it at the Avast install directory, remove
4. Uncheck `Safe boot` in `msconfig`, reboot
5. Verify the drivers are gone:

```powershell
Get-CimInstance Win32_SystemDriver | Where-Object Name -like 'asw*'
Get-ChildItem 'C:\Windows\System32\drivers\asw*' -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Program Files\Avast Software','C:\ProgramData\Avast Software' -ErrorAction SilentlyContinue
```

6. Confirm Defender took over:

```powershell
Get-MpComputerStatus | Select-Object AMRunningMode, RealTimeProtectionEnabled, AntivirusSignatureLastUpdated
```

For vendor support cases, download and run the **Avast Support Tool** — it
bundles the logs Avast support will ask for.

---

## 10. Phase 7 — Malware second opinion

Never trust a single engine, especially the one that was installed while the
machine got infected.

Order of operations:

```powershell
# 1. Defender offline scan — boots into WinRE, scans before rootkits load.
#    Reboots the machine. Warn the user first.
Start-MpWDOScan
```

Then, from the stick, in this order:

1. **AdwCleaner** — `Scan`, review the results *before* cleaning (it's aggressive with browser policies), then clean. Reboot.
2. **MSERT** (`msert.exe /F:Y` for full scan) — Microsoft-signed, no conflict with installed AV.
3. **KVRT** (`KVRT.exe -adinsilent -accepteula`) — good rootkit and bootkit coverage.
4. **Sophos Scan & Clean** — designed to run alongside an installed AV.

Manual checks the scanners miss:

```powershell
# Browser hijacks: check homepage/search policies
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome' -ErrorAction SilentlyContinue
Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -ErrorAction SilentlyContinue

# Hosts file tampering
Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() }

# Proxy hijack
Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' |
    Select-Object ProxyEnable, ProxyServer, AutoConfigURL
netsh winhttp show proxy

# DNS hijack — should be the router or a known resolver, not something random
Get-DnsClientServerAddress -AddressFamily IPv4 | Select-Object InterfaceAlias, ServerAddresses

# Suspicious scheduled tasks (a favorite persistence spot)
Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
    Select-Object TaskPath, TaskName, State
Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
    ForEach-Object { $_ | Get-ScheduledTaskInfo } | Select-Object TaskName, LastRunTime, NumberOfMissedRuns

# WMI event subscription persistence
Get-CimInstance -Namespace root\subscription -ClassName __EventFilter
Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer
```

And run **Autoruns** with VirusTotal lookups enabled (section 6.1). It's still
the best single persistence-hunting tool on Windows.

---

## 11. Phase 8 — Automated collection

The manual commands above are for investigating. For the *collection* pass, run
the bundled script — it captures all of it into one timestamped folder and zips
it.

**Ships with this toolkit:** `Scripts/Invoke-CyberWinDiag.ps1`

### Usage

Easiest — double-click `CyberWinDiag.cmd` at the root of the stick. It requests
elevation and runs with the right flags.

Or drive it directly from an elevated PowerShell:

```powershell
# Standard run — read-only collection, ~3-5 minutes, no reboots, no changes
powershell -NoProfile -ExecutionPolicy Bypass -File E:\CyberWinDiagnostics\Scripts\Invoke-CyberWinDiag.ps1

# Add the 60-second perfmon System Diagnostics report (adds ~2 min)
... -IncludePerfmonReport

# Add powercfg energy/battery/sleepstudy reports (adds ~1 min)
... -IncludePowerReports

# Add SFC + DISM scans. WRITES to the system. Adds 10-30 minutes. Opt-in only.
... -RunIntegrityScans

# Write the report somewhere other than the stick (do this if the USB is slow or read-only)
... -OutputRoot C:\Temp
```

### What it collects

| Section | Files |
| --- | --- |
| System | `systeminfo.txt`, `computerinfo.txt`, `msinfo32.nfo`, `dxdiag.txt`, `hotfixes.csv` |
| Performance | `top-processes.txt`, `services.csv`, `startup-*.csv`, `scheduled-tasks.csv`, `perf-counters.txt` |
| Storage | `disks.txt`, `volumes.txt`, `smart-*.txt`, `trim.txt`, `defrag-analysis.txt` |
| Power | `power-plan.txt`, `energy.html`, `battery.html`, `sleepstudy.html` |
| Drivers | `drivers.csv`, `problem-devices.txt`, `driver-store.txt` |
| Events | `events-summary.txt`, `events-critical.csv`, `boot-performance.txt`, `minidumps.txt` |
| Network | `ipconfig.txt`, `net-adapters.txt`, `dns.txt`, `netstat.txt`, `wlan-report.html` |
| **Printing** | `print-printers.txt`, `print-ports.txt`, `print-drivers.txt`, `print-jobs.txt`, `print-spool-folder.txt`, `print-events.txt` |
| **Antivirus** | `av-securitycenter.txt`, `av-avast-services.txt`, `av-avast-drivers.txt`, `av-avast-defs.txt`, `av-defender.txt` |
| Meta | `_transcript.log`, `_SUMMARY.txt` |

Everything is wrapped in per-step error handling, so one failing collector
doesn't abort the run. `_SUMMARY.txt` is the triage sheet — read that first.

### Reading the output

```powershell
# On your own machine afterwards
Expand-Archive .\HOSTNAME-20260909-142233.zip -DestinationPath .\case-1234
Get-Content .\case-1234\_SUMMARY.txt
```

---

## 12. Phase 9 — Remediation order of operations

Cheapest and least invasive first. Retest after each step.

1. **Reboot properly.** `Restart`, not shutdown-then-power-on. Rules out accumulated state and Fast Startup weirdness.
2. **Free up disk space.** Get the system volume above 20% free. `cleanmgr`, remove `Windows.old`, component store cleanup.
3. **Remove, don't disable, junk.** Registry cleaners, "optimizers", driver updaters, toolbars, duplicate AV, OEM bloat suites.
4. **Fix startup.** Disable non-essential startup items and logon tasks via Autoruns. Re-measure boot time via Event ID 100.
5. **Resolve the AV situation.** One real-time engine, current definitions, verified with EICAR, targeted exclusions for dev/LOB paths.
6. **Clear the print stack.** Purge the spool folder, delete ghost printers and stale drivers, replace WSD ports with raw TCP/IP, disable SNMP/bidi, choose a lean driver.
7. **Update drivers selectively.** Chipset, storage, network, GPU — from the OEM or chip vendor. Nothing else.
8. **Apply pending Windows updates.** Then re-measure; updates frequently *are* the load you were measuring.
9. **Repair OS integrity.** DISM `RestoreHealth`, then `sfc /scannow`. Reboot, re-run to confirm clean.
10. **Address power and thermals.** Sane power plan, physical cleaning, repaste if warranted, replace a worn battery.
11. **Hardware.** Replace a failing disk, replace an HDD with an SSD, add RAM to reach at least 8 GB (16 preferred).
12. **Last resort:** in-place upgrade / repair install from ISO, or a clean install with a documented data migration.

**Set expectations honestly.** A 2013-era dual-core laptop with 4 GB of RAM and
a 5400 RPM drive running Windows 10 and a full AV suite is not going to feel
fast. Say so, in writing, with the numbers from your report backing it up. That
conversation goes far better than three hours of tweaking followed by "it's
still slow."

---

## 13. Report template

Keep a copy at `Notes/report-template.md` on the stick.

```markdown
# CyberWinDiagnostics Report

**Machine:** <hostname> / <make model> / <serial>
**User:** <name>
**Date:** <YYYY-MM-DD>
**Technician:** <name>
**Evidence bundle:** `<HOSTNAME>-<timestamp>.zip`

## Reported complaints
1.
2.

## Configuration
| Item | Value |
| --- | --- |
| OS / build | |
| CPU | |
| RAM | |
| System disk (model / type / SMART) | |
| Free space on C: | |
| Antivirus | |
| Printers | |

## Findings
| # | Severity | Finding | Evidence | Recommendation |
| --- | --- | --- | --- | --- |
| 1 | High | | | |
| 2 | Medium | | | |
| 3 | Low | | | |

## Actions taken
- [ ]
- [ ]

## Measurements
| Metric | Before | After |
| --- | --- | --- |
| Boot time (Event ID 100) | | |
| Free space on C: | | |
| Idle CPU % | | |
| Disk sec/transfer at idle | | |
| Time to first printed page | | |

## Outstanding / recommended
-

## Notes for next visit
-
```

---

## Appendix A — Command cheat sheet

### GUI tools worth memorizing

| Command | Tool |
| --- | --- |
| `msinfo32` | System Information |
| `perfmon /rel` | Reliability Monitor |
| `perfmon /report` | System Diagnostics Report (HTML) |
| `resmon` | Resource Monitor |
| `eventvwr.msc` | Event Viewer |
| `devmgmt.msc` | Device Manager |
| `services.msc` | Services |
| `diskmgmt.msc` | Disk Management |
| `printmanagement.msc` | Print Management |
| `taskschd.msc` | Task Scheduler |
| `msconfig` | System Configuration (boot options, Safe Mode) |
| `mdsched` | Windows Memory Diagnostic |
| `cleanmgr /d C:` | Disk Cleanup |
| `sigverif` | File Signature Verification |
| `optionalfeatures` | Windows Features |
| `wf.msc` | Windows Firewall (advanced) |
| `control /name Microsoft.Troubleshooting` | Troubleshooters |
| `sysdm.cpl` | System Properties (perf options, restore, env vars) |
| `powercfg.cpl` | Power Options |

### Command-line

| Command | Purpose |
| --- | --- |
| `systeminfo` | Full system summary |
| `winver` | Exact Windows build |
| `driverquery /v /fo csv` | All drivers |
| `pnputil /enum-drivers` | Third-party driver store |
| `sfc /scannow` | Verify/repair system files |
| `DISM /Online /Cleanup-Image /RestoreHealth` | Repair the component store |
| `chkdsk C: /scan` | Online filesystem scan |
| `defrag C: /A /V` | Analyze fragmentation |
| `defrag C: /L` | Re-TRIM an SSD |
| `fsutil behavior query DisableDeleteNotify` | Is TRIM on |
| `powercfg /energy` | Power/efficiency audit |
| `powercfg /batteryreport` | Battery health |
| `powercfg /a` | Available sleep states |
| `powercfg /h off` | Disable hibernation + Fast Startup |
| `wevtutil sl <log> /e:true` | Enable a disabled event log |
| `wevtutil epl System sys.evtx` | Export an event log |
| `tasklist /svc` | Services per process |
| `netstat -ano` | Sockets with owning PID |
| `pathping <host>` | Per-hop loss and latency |
| `netsh wlan show wlanreport` | Wi-Fi session HTML report |
| `rundll32 printui.dll,PrintUIEntry /?` | Printer management CLI |
| `bcdedit /enum` | Boot configuration |

### PowerShell one-liners

| Command | Purpose |
| --- | --- |
| `Get-ComputerInfo` | Consolidated system info |
| `Get-PhysicalDisk \| Get-StorageReliabilityCounter` | Wear, hours, errors |
| `Get-Volume` | Space and health per volume |
| `Get-PnpDevice \| ? Status -ne OK` | Problem devices |
| `Get-CimInstance Win32_StartupCommand` | Startup items |
| `Get-ScheduledTask \| ? State -ne Disabled` | Enabled tasks |
| `Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2}` | Critical/error events |
| `Get-Printer`, `Get-PrinterPort`, `Get-PrinterDriver`, `Get-PrintJob` | Print subsystem |
| `Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct` | Registered AV |
| `Get-MpComputerStatus` | Defender state and running mode |
| `Get-Counter '\PhysicalDisk(_Total)\% Idle Time'` | Live disk saturation |
| `Get-NetAdapter`, `Get-NetIPConfiguration` | Network state |
| `Repair-Volume -DriveLetter C -Scan` | Online volume scan |

> `wmic` still exists on Windows 10 but is deprecated and absent from newer
> builds. Prefer the `Get-CimInstance` equivalents so the toolkit keeps working.

---

## Appendix B — Event ID reference

Build-dependent, but these are stable and worth recognizing on sight.

### Stability and crashes

| Source | ID | Meaning |
| --- | --- | --- |
| `Kernel-Power` | 41 | System restarted without a clean shutdown — power loss, hard hang, or BSOD with no dump |
| `BugCheck` | 1001 | Bugcheck code and parameters from the last BSOD |
| `EventLog` | 6008 | Previous shutdown was unexpected |
| `Application Error` | 1000 | Application crashed — names the faulting module |
| `Application Hang` | 1002 | Application stopped responding |
| `WER` / `Windows Error Reporting` | 1001 | Crash report bucket details |

### Hardware

| Source | ID | Meaning |
| --- | --- | --- |
| `WHEA-Logger` | 17, 19 | Corrected hardware error — often PCIe or memory. Recurring = investigate. |
| `WHEA-Logger` | 18 | **Uncorrectable** hardware error. Serious. |
| `disk` | 7 | Bad block on the device |
| `disk` | 11 | Controller error — often a cable/port issue rather than the drive |
| `disk` | 51 | Error during a paging operation |
| `disk` | 153 | I/O operation was retried — precursor to failure, very common on dying drives |
| `Ntfs` | 55 | Filesystem structure corruption — run `chkdsk` |
| `Ntfs` | 98, 137 | Volume/metadata issues |
| `Microsoft-Windows-MemoryDiagnostics-Results` | 1201 | Memory diagnostic result |

### Boot and services

| Source | ID | Meaning |
| --- | --- | --- |
| `Diagnostics-Performance` | 100 | Boot duration (the headline number) |
| `Diagnostics-Performance` | 101 | An **application** caused a boot delay — names it |
| `Diagnostics-Performance` | 102 | A **driver** initialized slowly — names it |
| `Diagnostics-Performance` | 103 | A **service** started slowly — names it |
| `Diagnostics-Performance` | 200 | Shutdown duration |
| `Diagnostics-Performance` | 300s | Logon/standby/resume degradation |
| `Service Control Manager` | 7000 | Service failed to start |
| `Service Control Manager` | 7009 | Service start timed out |
| `Service Control Manager` | 7011 | Service transaction timed out (classic hang symptom) |
| `Service Control Manager` | 7031, 7034 | Service terminated unexpectedly |
| `User Profile Service` | 1511, 1515 | Logged on with a temporary profile |

### Printing

| Log | ID | Meaning |
| --- | --- | --- |
| `PrintService/Operational` | 307 | Document printed — includes size, pages, bytes sent |
| `PrintService/Operational` | 800 series | Job rendering and processing detail |
| `PrintService/Admin` | — | Driver load failures, spooler errors, port problems |
| `System` (Service Control Manager) | 7031 | Print Spooler terminated unexpectedly |

Handy filter for the whole sweep:

```powershell
$since = (Get-Date).AddDays(-14)
Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2; StartTime=$since } |
    Group-Object ProviderName, Id | Sort-Object Count -Descending | Format-Table Count, Name
```

---

## Appendix C — Avast services and drivers

Names vary by Avast version and edition. Presence and state matter more than
exact naming.

### Services (typical)

| Service | Role |
| --- | --- |
| `avast! Antivirus` / `AvastSvc` | Main service — must be `Running`, `Automatic`. If it's stopped, nothing else matters. |
| `aswbIDSAgent` | Behavior Shield / IDS agent |
| `AvastWscReporter` | Reports status to Windows Security Center |
| `AvastNM` | Network monitoring |
| `Avast Cleanup` / `AvastCleanupSvc` | Cleanup component (only on relevant tiers) |
| `AvastVBoxSVC` | Virtualization support for Sandbox / hardware-assisted virtualization |
| `avast! Firewall` | Firewall, on Premium/Ultimate tiers only |

### Kernel drivers (`asw*`)

| Driver | Role |
| --- | --- |
| `aswSP` | Self-protection |
| `aswSnx` | Virtualization / kernel core |
| `aswMonFlt` | File system minifilter — **this is the File Shield.** Not loaded = files are not being scanned. |
| `aswNetSec` | Network security / Web Shield |
| `aswbIDSDriver` | Behavior Shield driver |
| `aswRdr` / `aswRdr2` | Network redirect (traffic interception) |
| `aswStm` | Stream filter |
| `aswVmm` | Virtual machine monitor |
| `aswKbd` | Keyboard filter (anti-keylogger) |
| `aswArPot` | Ransomware / anti-rootkit protection |
| `aswElam` | Early Launch Anti-Malware driver |

Quick verification block:

```powershell
'aswMonFlt','aswSP','aswSnx','aswNetSec','aswbIDSDriver' | ForEach-Object {
    $d = Get-CimInstance Win32_SystemDriver -Filter "Name='$_'" -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Driver  = $_
        Present = [bool]$d
        State   = $d.State
        Start   = $d.StartMode
    }
} | Format-Table -AutoSize
```

`aswMonFlt` missing or stopped while the UI reports "You're protected" is the
classic broken-Avast signature. Repair or clean-reinstall.

Filter driver load order also matters — a mangled minifilter stack causes real
slowness:

```cmd
fltmc filters
fltmc instances -v C:
```

Look for orphaned filters from *previously uninstalled* AV products (`aswMonFlt`
plus a leftover McAfee/Norton/Kaspersky filter is a common and expensive
mistake).

### Log and data locations

| Path | Contents |
| --- | --- |
| `C:\ProgramData\Avast Software\Avast\log\` | Service, shield, update, self-defense logs |
| `C:\ProgramData\Avast Software\Avast\defs\` | Virus definitions, date-stamped folders |
| `C:\ProgramData\Avast Software\Avast\chest\` | Quarantine ("Virus Chest") |
| `C:\Program Files\Avast Software\Avast\` | Program files, `AvastUI.exe` |

---

## Appendix D — Gotchas

- **Your USB tools will get quarantined.** NirSoft utilities, PsExec and
  Autoruns are routinely flagged as riskware. Don't add a blanket exclusion for
  a removable drive on a client machine — note it and work around it.
- **Running from USB is slow.** ProcMon writing a backing file to a USB 2.0
  stick will itself distort your measurements. Point ProcMon's backing file at
  `C:\Temp` and copy the results off afterwards.
- **Removing the stick mid-write corrupts the report.** Use `Safely Remove
  Hardware`, especially on exFAT.
- **`msinfo32 /nfo` can take several minutes** on a machine with many devices
  and will appear hung. It isn't.
- **`sfc /scannow` needs a healthy component store first.** Running it before
  DISM `RestoreHealth` is why "SFC found corruption it couldn't fix."
- **Fast Startup means "shut down" isn't a reboot.** Always use `Restart` when
  testing.
- **Don't run `chkdsk /r` on a drive with pending or reallocated sectors.**
  Image it first with `ddrescue` from the Linux side of the stick.
- **`Checkpoint-Computer` is rate-limited** to one restore point per 24 hours by
  default, and System Protection is often disabled entirely on OEM images.
- **`Win32_Product` triggers an MSI reconfiguration** of every installed
  package. It's slow and it can break things. Use the uninstall registry keys.
- **PowerShell 5.1's default output encoding is UTF-16LE.** If you're grepping
  the reports from Linux afterwards, either use `-Encoding utf8` on every
  `Out-File` or convert with `iconv -f UTF-16LE -t UTF-8`.
- **Some of the print cmdlets need the `PrintManagement` module**, which is
  present on Win10 but absent in some stripped/LTSC images. Fall back to
  `Get-CimInstance Win32_Printer` and `printui.dll`.
- **Windows 10 is out of support.** Any security finding you write up should
  note that the platform itself no longer receives patches outside ESU.

---

## License and attribution

The CyberWinDiagnostics scripts and documentation in this repository are
licensed under the MIT License; see [LICENSE](LICENSE). That license does not
cover third-party utilities placed on a personal USB. Those remain under their
respective terms: for example, Sysinternals cannot be redistributed, and
Microsoft Safety Scanner expires ten days after download. Review
[TOOL-SOURCES.md](TOOL-SOURCES.md) before adding or sharing any vendor tools.

Nothing in this document requires you to modify a system to gather evidence.
Every command in Phases 0-8 is read-only unless explicitly flagged otherwise.
Keep it that way — the collection pass and the remediation pass should never be
the same pass.
