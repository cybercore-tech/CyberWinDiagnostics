# Tool downloads and licensing

The collector and runbook work without third-party applications. The portable
Notepad++, 7-Zip Extra, and CrystalDiskInfo packages are bundled with their
open-source licenses. A local Sysinternals Suite copy is on the personal USB only; it is
excluded from the shareable ZIP because Microsoft's terms do not permit
redistribution. See `Tools/Bundle-INFO.md` for versions and hashes.

| Tool | Official source | Notes |
| --- | --- | --- |
| Sysinternals Suite | <https://learn.microsoft.com/sysinternals/downloads/sysinternals-suite> | The USB's copy is for your personal use on devices you own or support. Microsoft does not grant redistribution rights; do not pass the binaries to others or include them in a shared archive. |
| CrystalDiskInfo | <https://crystalmark.info/en/download/> | MIT-licensed project; the USB contains the official portable ZIP release and license materials. |
| NirSoft utilities | <https://www.nirsoft.net/> | Per-tool terms apply; many require the complete original package if redistributed. Review each utility's license page. |
| Microsoft Safety Scanner | <https://learn.microsoft.com/microsoft-365/security/intelligence/safety-scanner-download> | `Scripts/Refresh-and-Run-MSERT.cmd` downloads the current 64-bit binary and verifies its Authenticode signature. Internet is required; the scanner expires 10 days after download. |
| 7-Zip | <https://www.7-zip.org/download.html> | Official Windows download; use its portable/extra package if needed. Preserve license notices. |
| Notepad++ | <https://github.com/notepad-plus-plus/notepad-plus-plus/releases> | Official project release page; portable ZIP/7z builds are available. Verify the published checksum. |
| smartmontools | <https://www.smartmontools.org/wiki/Download> | GPL project; use the official Windows build and retain its license materials. |

No third-party binaries are embedded in the distributable ZIP. The personal
USB has the local Sysinternals copy described above. Before sharing the USB or
archive, remove any binaries whose terms do not allow redistribution. The USB
is exFAT and supports cross-platform file exchange; the PowerShell collector
and Windows executables run only on Windows.

## Runtime and validation

`CyberWinDiag.cmd` launches Windows PowerShell (`powershell.exe`) and elevates
through UAC. Windows 10/11 normally includes Windows PowerShell 5.1; this is not
a Linux PowerShell bundle. Windows CIM, Event Log, printer, DISM, SFC and other
Windows-specific checks must be smoke-tested on a Windows machine. On Linux,
PowerShell's parser can check script syntax, but cannot verify those collectors.
The included scripts were parsed successfully with PowerShell 7.6.6 on Linux;
the collector and Microsoft signature-checking updater still need a Windows
smoke test.

The main collector is read-only unless `-RunIntegrityScans` is explicitly
provided. The separate `Fix-PrintSpooler.ps1` is a remediation script and can
modify printer configuration; inspect its help and use `-WhatIf` where
supported before applying changes.
