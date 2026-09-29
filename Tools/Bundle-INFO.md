# Bundled utility inventory

Downloaded from publisher sources on 2026-09-28. Verify hashes again after any
refresh. These utilities are optional; the diagnostic collector works without
them.

| Utility | Version | Location | Download SHA-256 | License/use |
| --- | --- | --- | --- | --- |
| Notepad++ portable x64 | 8.9.6.4 | `Misc/NotepadPlusPlus/notepad++.exe` | `7b3618195757eed0d47debc28661fe998e68d3822a06a3621ee669ee358fc952` | GPL; package includes its license. |
| 7-Zip Extra | 26.03 | `Misc/7-Zip/7za.exe` | `191894e6acb3647ffb69ce630479ff318523b2e2b9890aa7f05c1127c2e59b8f` | LGPL/BSD components; original license included. This is the portable command-line build. |
| CrystalDiskInfo Standard | 9.9.2 | `Storage/CrystalDiskInfo/DiskInfo64.exe` | `01acb3176851a85824d9589c6514e3eb9771eb7f9d5ee58ed9b4e057bd21c7df` | MIT; project license and third-party notices included. |
| Microsoft Sysinternals Suite | 2026-09 current suite | `Sysinternals/` | `e1c73a31b575c9cb216a94484a5b162bd585deb8bd1a8775c8103ced39cc67ce` | Personal local USB copy only for devices you own or support. Microsoft does not permit redistribution; it is omitted from the shareable ZIP. `Eula.txt` is included. |
| Microsoft Safety Scanner x64 | downloaded 2026-09-28 | `Scanners/MSERT.exe` | `a4990c81f937e9eecc5d3dfdb62f61a0ccaa45fb0407fee92f0e011dec377789` | Current personal USB copy; refresh through the supplied launcher before use. Expires ten days after download. |

The Notepad++ checksum matches the project's published SHA-256 for its x64
portable ZIP. The other hashes identify the exact publisher downloads used to
build this copy. `Scripts/Refresh-and-Run-MSERT.cmd` fetches and
signature-checks a fresh scanner because each download expires after ten days.
Do not copy the Sysinternals or Safety Scanner binaries into a shared archive
or hand the USB to someone else; the USB's local copies are for your own use.
