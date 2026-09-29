# Tool downloads and licensing

The collector and runbook work without third-party applications. The personal
USB has portable Notepad++, 7-Zip Extra, and CrystalDiskInfo packages with
their license materials. These binaries are excluded from the repository and
shareable ZIP. A local Sysinternals Suite copy is also on the personal USB;
Microsoft's terms do not permit redistribution. See `Tools/Bundle-INFO.md` for
the USB inventory, versions, hashes, and use restrictions.

| Tool | Official source | Notes |
| --- | --- | --- |
| Sysinternals Suite | <https://learn.microsoft.com/sysinternals/downloads/sysinternals-suite> | The USB's copy is for your personal use on devices you own or support. Microsoft does not grant redistribution rights; do not pass the binaries to others or include them in a shared archive. |
| CrystalDiskInfo | <https://crystalmark.info/en/download/> | MIT-licensed project; the USB contains the official portable ZIP release and license materials. |
| NirSoft utilities | <https://www.nirsoft.net/> | Per-tool terms apply; many require the complete original package if redistributed. Review each utility's license page. |
| Microsoft Safety Scanner | <https://learn.microsoft.com/microsoft-365/security/intelligence/safety-scanner-download> | `Scripts/Refresh-and-Run-MSERT.cmd` downloads the current 64-bit binary and verifies its Authenticode signature. Internet is required; the scanner expires 10 days after download. |
| 7-Zip | <https://www.7-zip.org/download.html> | Official Windows download; use its portable/extra package if needed. Preserve license notices. |
| Notepad++ | <https://github.com/notepad-plus-plus/notepad-plus-plus/releases> | Official project release page; portable ZIP/7z builds are available. Verify the published checksum. |
| smartmontools | <https://www.smartmontools.org/wiki/Download> | GPL project; use the official Windows build and retain its license materials. |

No third-party binaries are embedded in the repository or distributable ZIP.
The personal USB contains local third-party binaries under their respective
terms. Do not hand this USB to another person or copy its binaries into a
shared archive; distribute links to vendor download pages instead. For a
shareable build, obtain and review the terms for every utility before adding
it. The USB is exFAT and supports cross-platform file exchange; the PowerShell
collector and Windows executables run only on Windows.

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
