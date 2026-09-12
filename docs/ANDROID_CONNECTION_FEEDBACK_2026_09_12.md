# Android Connection Feedback and Quick Settings

Scope: Android-only mandatory 0.4.17+2026091201 candidate. Publication pending.
Owner authorized implementation and release; never operate on host Windows VPN,
routes, services or installers. Windows 0.4.12+4645, backend, paid-beta, billing,
and the excluded 5.129.237.163 host are outside this change.

## Contract

- Reuse the declared Quick Settings service, replace its private legacy cascade
  and cached config fallback with the same native operation service as the app.
  Preserve saved location and selection; no silent conversion to full routing.
  Selected-mode native probes include the Green VPN UID in the selected tunnel.
  Server-side entitlement/config issuance remains authoritative.
- Tile presses during connect cancel that operation; presses during disconnect
  do not enqueue another operation. Unlock/permission/session requirements are
  honored. A settings action invokes the Android 13+ system add-tile prompt;
  earlier Android uses the system tile editor. Addition is never forced.
  The tile is unavailable while this process downloads an update.
- Baseline requires a VPN-bound HTTPS request with the expected response:
  gstatic 204 or Green VPN health 200, racing two bounded attempts. Proxy-backed
  transports also require their local SOCKS data path with hostname-verified TLS.
  No redirect/cached success and no direct-network fallback. Overall baseline
  deadline is 10 seconds; outstanding resources are closed on finish/cancel.
  The executor queue is bounded even when system DNS cancellation is delayed.
- YouTube is supplementary, not a connection quorum or recovery trigger. One
  best-effort native task after confirmed connect, at most once per five minutes,
  writes only a bounded journal result and cannot change route state. Existing
  baseline monitoring cadence and two-failure recovery policy remain unchanged.
- Native full-mode feedback follows verified state, explicit disconnect and
  terminal errors. Retry/network-loss/reopened-screen observations are silent.
  Legacy selected mode signals actual tunnel establishment without claiming
  independent proof for every selected application. Audio uses two 100-ms PCM
  notes, notification volume, honors silent/vibrate/DND/calls/notifications-off,
  and releases the player. One native settings toggle; no audio package, polling,
  wakelock, microphone access or external sound download.
- No other VPN is restored, no session expiry bypass, no payment changes.

## Verification

Initial isolated Flutter analyze passed, 9 Dart/widget and 20 JVM tests passed.
Final rerun and exact release/package/publication evidence will be appended.
Tests run in existing Ubuntu WSL guest without Windows executables on PATH;
host Gradle only compiles, never installs or starts a VPN.

Not physically verified: vendor Quick Settings UI, background tile interaction,
audibility/DND on an actual phone, selected-app egress, weak-network latency,
email login and battery usage. These limits are not replaced by build success.

Evidence root: C:\BlueVPN_Builds\android_connection_feedback_20260912_v1.
Publish fallback 176.113.81.35 then primary 72.56.32.197 using only the Android
stable publisher, exact hash gates, dry-run, atomic backup and protected-contour
comparison. Keep rollback files, do not restore a whole database over payments.
