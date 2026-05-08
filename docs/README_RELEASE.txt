Green VPN Release Notes
=====================

Version: 0.1.0-working-freeze
Channel: Windows MVP
Build note: 2026-05-05 admin/support readiness candidate

What is included
----------------
- greenvpn.exe
- uninstall_greenvpn.cmd
- uninstall_greenvpn.ps1
- doctor_greenvpn.ps1
- greenvpn_network_recover.ps1
- greenvpn_boot_repair.ps1
- greenvpn_vpn_task.ps1
- VERSION.txt

How to launch
-------------
1. Install WireGuard for Windows.
2. Run GreenVPN_Setup.exe and accept the Windows UAC prompt during installation.
3. Start Green VPN from the installer-created desktop or Start menu shortcut.
4. Register or sign in.
5. Use the VPN tab to connect or disconnect.
6. If something looks broken, run doctor_greenvpn.ps1 with -SaveReport.

Normal app launch should not request administrator rights. The installer creates GreenVPNConnect, GreenVPNDisconnect and GreenVPNGuard scheduled tasks for privileged VPN operations.
Internal backend/admin-support work can be newer than this visible app version. This installer keeps the normal user app clean; support, monitoring and admin tools are separate and not exposed in the user UI.

Useful paths
------------
- Installed app: %LOCALAPPDATA%\Programs\Green VPN
- Support tools: %LOCALAPPDATA%\Programs\Green VPN\tools

Doctor command
--------------
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\doctor_greenvpn.ps1 -SaveReport

Network recovery command
------------------------
Run only from PowerShell as Administrator if Windows networking is broken after switching between VPN clients:

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\greenvpn_network_recover.ps1 -RestartAdapters -ForceReboot

Boot conflict repair
--------------------
If Green VPN was tested together with Amnezia/WARP/WireGuard and networking breaks after Windows restart, run:

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\greenvpn_boot_repair.ps1 -FlushDns

Full uninstall
--------------
To remove Green VPN completely, run from the installed app folder:

uninstall_greenvpn.cmd

This removes Green VPN tasks, startup entries, shortcuts, installed files and Green VPN ProgramData state. It does not uninstall WireGuard, Amnezia, WARP or other VPN clients.

Notes
-----
This package is based on the known-good working freeze where:
- VPN connect/disconnect works
- social-only mode works
- WireGuard tunnel service is managed by Green VPN
- The Windows executable should start as a normal user app; privileged VPN control goes through installer-created SYSTEM scheduled tasks.
- The release package does not ship local WireGuard configs from ProgramData; each device should receive its own config from the backend after sign in.
- Safety build: Green VPN delegates tunnel control to WireGuard instead of manually removing routes, removing IP addresses, disabling network adapters, or force-killing the tunnel process.
- Boot-safety build: Green VPN tunnel service is converted to manual start after connect, so Windows should not auto-start BlueVPNDev1 on reboot.
- Single-active-VPN build: Green VPN refuses to connect over an already active Amnezia/WARP/WireGuard-style tunnel.
- Task-guard build: GreenVPNGuard runs every minute and disconnects only Green VPN if another VPN becomes active afterwards.
- The release gate checks that local WireGuard configs, sessions, admin tokens and device ids are not packed into the release zip.
- Current backend readiness layer includes server-side checks, admin/support incidents, monitoring targets and external-service setup checklist. Real SMTP/SMS/YooKassa/Telegram secrets must be configured only on the server, never inside this package.
