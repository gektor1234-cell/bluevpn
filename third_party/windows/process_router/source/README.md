# Green VPN ProxyBridge fork

This directory contains the Windows core and CLI source used to build the
process router packaged by Green VPN.

- Upstream: https://github.com/InterceptSuite/ProxyBridge
- Upstream tag: `v4.0.0`
- Upstream commit: `22e53445e44481fad0f63c2a088aa91c0deda3af`
- License: MIT (see `..\PROXYBRIDGE_LICENSE.txt`)

Green VPN carries a narrow production hardening patch:

- capture WinDivert socket bind/connect events before the first packet, then
  retain flow events and short-lived Windows socket tables as fallbacks;
- normalize WinDivert host-order IPv4/IPv6 event addresses before matching the
  complete packet tuple, including the fourth word of IPv4-mapped event
  addresses, and keep a five-second source-port bridge for sockets whose local
  address is not assigned yet;
- cache attribution for selected and unselected processes so fail-closed mode
  does not block unrelated applications;
- fail closed when an intercepted connection cannot be attributed, its
  process path cannot be read, or its exact proxy configuration is unusable,
  after a bounded 100 ms pre-connect attribution wait;
- parse SOCKS5 responses with exact-length reads and handle every address type;
- preserve long executable paths and keep IPv4/IPv6 on one routing policy;
- make rule/proxy configuration immutable while the router is active and wait
  for worker threads during shutdown;
- build reproducibly with MSVC `/Brepro`.

Selected UDP is dropped when its SOCKS5 UDP route is unavailable, allowing
applications to fall back to TCP without leaking. Green VPN does not add a
global `svchost.exe` DNS rule, so unrelated Windows DNS traffic is untouched.

Run `build.ps1` from this directory to rebuild the two packaged binaries.
The build requires MSVC x64 tools and WinDivert 2.2.2-A.
