# Patched WireGuard Android backend

Green VPN uses the official `com.wireguard.android:tunnel:1.0.20260102`
artifact. On affected Android 16 runtimes, the diagnostic native
`wgVersion()` call can abort inside Go `debug.ReadBuildInfo`. The tunnel may
already be connected when the process exits.

`GoBackend.java` is the upstream source for that release with two narrow
changes:

- `getVersion()` returns an empty diagnostic value;
- tunnel startup logs a fixed message instead of calling `wgVersion()`.

Tunnel creation, native libraries, keys, configuration, routing, and packet
handling remain upstream code. The official AAR checksum is pinned in the
build script.

Regenerate the checked-in AAR from the official Maven artifact:

```powershell
.\scripts\android\build_patched_wireguard_aar.ps1
```

Upstream source: <https://git.zx2c4.com/wireguard-android/tag/?h=1.0.20260102>

License: Apache-2.0, as declared in the upstream source.
