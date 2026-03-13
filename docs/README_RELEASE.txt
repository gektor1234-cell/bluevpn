BlueVPN Release Notes
=====================

Version: 0.1.0-working-freeze
Channel: Windows MVP

What is included
----------------
- bluevpn.exe
- BlueVPN.conf.sample
- BlueVPN.base.conf.sample
- doctor_bluevpn.ps1
- VERSION.txt

How to launch
-------------
1. Install WireGuard for Windows.
2. Run bluevpn.exe as Administrator.
3. Use the VPN tab to connect or disconnect.
4. If something looks broken, run doctor_bluevpn.ps1 with -SaveReport.

Useful paths
------------
- App config: C:\ProgramData\BlueVPN
- App log: C:\ProgramData\BlueVPN\backend.log
- User prefs: %APPDATA%\BlueVPN

Doctor command
--------------
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\doctor_bluevpn.ps1 -SaveReport

Notes
-----
This package is based on the known-good working freeze where:
- VPN connect/disconnect works
- social-only mode works
- WireGuard tunnel service is managed by BlueVPN
