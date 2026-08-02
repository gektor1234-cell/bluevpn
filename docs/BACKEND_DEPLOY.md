BlueVPN Backend Deploy
======================

Use this only from the development machine. It uploads `backend_live` to the dev
server, backs up the current `main.py`, installs requirements, restarts
`bluevpn-backend`, and checks `/healthz`.

Command
-------

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\deploy_backend_wsl.ps1 -ServerHost 72.56.32.197
```

Notes
-----

- The script uses WSL, SSH and SCP.
- It does not store or echo the server password.
- If there is no SSH key, SSH asks for the password interactively.
- The target service is `bluevpn-backend` on the explicitly selected control
  plane. Use `72.56.32.197` for Timeweb or `176.113.81.35` for RUVDS; VPN data
  plane hosts are rejected.
