# Android Connection Feedback and Quick Settings

Scope: Android-only mandatory 0.4.17+2026091201, published on both sites.
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

Final isolated Flutter analyze passed, 9 Dart/widget and 20 JVM tests passed.
Tests run in existing Ubuntu WSL guest without Windows executables on PATH;
host Gradle only compiles, never installs or starts a VPN.

Not physically verified: vendor Quick Settings UI, background tile interaction,
audibility/DND on an actual phone, selected-app egress, weak-network latency,
email login and battery usage. These limits are not replaced by build success.

Evidence root: C:\BlueVPN_Builds\android_connection_feedback_20260912_v1.
Publish fallback 176.113.81.35 then primary 72.56.32.197 using only the Android
stable publisher, exact hash gates, dry-run, atomic backup and protected-contour
comparison. Keep rollback files, do not restore a whole database over payments.

## Exact Release Evidence

- Source: `e8420cc25beba8e226c606251ef54d02dc900d2d`, pushed before clean-source build.
- APK: `clients/GreenVPN_Android_0.4.17_2026091201.apk` under the evidence root.
  Size `56470189`; SHA-256
  `332B29C7555A0A6421C67FFD69C6966962390DA5BB182596A69661C4A190A450`.
- Package `pro.greenvpn.app`, min SDK 26, target SDK 36, arm64-v8a/x86_64.
  APK v2 signature verified, signer SHA-256
  `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`.
  All 23 native libraries and ZIP entries meet 16-KiB alignment requirements.
  Packaged manifest includes exactly the existing QuickTileService with the
  system binding permission, QS_TILE action, toggle metadata and tile icon.
- `compile-tests.log`, `guest-checks.log`, `build.log`, `apk-manifest.txt`,
  `clients/android-16kb-compatibility.json` hold local evidence.
- Fallback dry-run/apply/after succeeded, then primary dry-run/apply/after.
  `fallback-before.json`, `fallback-after.json`, `primary-before.json`,
  `primary-after.json` prove both database quick_checks, active units, unchanged
  backend source, paid-beta environment/manifests and Windows manifests/EXE.
- `public-verification.json`: success=true; both full HTTPS downloads match
  exact SHA/size. Stable and public-product manifests require 0.4.17. All 16
  checks passed: 0.4.16 catalog=426, 0.4.17 catalog=200, manifests=200 for both.
- Primary/fallback sync and subscription-expiry service results are in the
  corresponding `*-sync.txt` files. No payment/order or user-data mutation.
- Rollback backups retained on the respective nodes:
  `/root/greenvpn-android-stable-release-backups/20260912T201021Z-ruvds-0.4.17-2026091201`
  and `/root/greenvpn-android-stable-release-backups/20260912T201138Z-timeweb-0.4.17-2026091201`.
- Build-time `public-product-artifacts.json` intentionally retains
  productionPublished=false; the after/public verification receipts prove the
  subsequent publication. Do not reinterpret the immutable build manifest.
- Both unique `/dev/shm/greenvpn-android-connection-feedback-20260912-v1` stages
  were removed after successful local receipt collection; rollback backups and
  the exact local APK remain. Release JSON and three PowerShell script parsers
  passed after the metadata-only version update.
