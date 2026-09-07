# Update download and VPN ownership

## Owner scope

Implement Android/Windows update preparation and remove external VPN restoration
from every packaged Windows runtime path. No tests requested for this change.
Never execute the new endpoints, VPN tasks, installers or physical smoke on the
owner's host. Its VPN, routes, adapters and other projects must remain untouched.
No new automation. Publication remains stable-only on primary/fallback; no
backend, payment, paid-beta publication or excluded-node changes.

## Behavior

- Both the update prompt and Settings use the same preparation callback, before
  opening the artifact HTTP request or launching a previously cached installer.
- Cancel own pause/resume, pending connection intent and runtime failover;
  stop own native connection and require a confirmed stopped state.
- Windows uses a local-token-protected POST /update/prepare, serializes mutations
  and cancels standby probes. It stops the supported WireGuard/AmneziaWG/WARP
  services; enumeration failure or remaining detected VPN blocks the download.
- Android checks system VPN transports after managed disconnect. It cannot
  silently stop another application's VPN or override Android Always-on/lockdown.
  It reports that blocker instead of claiming a direct download. Reference:
  https://developer.android.com/develop/connectivity/vpn
- Do not disable arbitrary adapters, kill unrelated processes, alter third-party
  service start types or repeatedly fight another VPN's own watchdog.
- Remove external restore functions and journals, including failed initial
  takeover rollback. Historical journals are discarded, never replayed.
- No automatic VPN resume after download, cancellation, failure or installation.
  The app UI cannot start another connection while its update operation owns
  the preparation lock. An already running connection transition must finish
  before update preparation; do not race it with a second mutation.
- Recheck VPN state before the HTTP request and installation. This is not a
  claim of continuous enforcement over arbitrary external VPN applications.

The updater already installed on a user's device cannot be changed retroactively:
downloading this release from the previous version still uses the old updater.
The new behavior applies after installing this release and to subsequent updates.
Installer/network recovery harnesses are not production VPN restoration features;
their safety recovery remains available only for separately authorized test hosts.

## Status

Published on 2026-09-07 at 11:28 UTC: Android 0.4.15+2026090703 and Windows
0.4.12+4645, mandatory stable/public-product on fallback then primary. Backend
stays 0.9.166-product-hardening.1. Existing ownership fixtures and package
contract markers were aligned with the new invariant, but were NOT RUN.
No app test, analyzer, physical installation or host network transition was
performed. Compilation and packaging completed with -SkipChecks; build success
and publication receipts do not establish runtime acceptance.

Stable publisher rollback is restricted to the affected platform's stable
app_releases rows. It no longer restores the whole database over payments or
subscriptions created since the publication backup. This rollback change is
source-reviewed only; no forced production failure or rollback test was run.

## Exact release

- App source: `90753ea746e18fe357c6add9e64bbc6b1a6b2521`.
- Publisher safety source: `647cac6cc8d28530f781a9e4566d50d244820c20`.
- Evidence root: `C:\BlueVPN_Builds\update_vpn_off_20260907_v1`.
- Android: `clients\GreenVPN_Android_0.4.15_2026090703.apk`, 56446133 bytes,
  signed with the existing release certificate, SHA-256
  `F9193290AC4EAE62F94886AC176D74CD0D5B98DFC7643E13B97509D81C43BE44`.
- Windows: `clients\GreenVPN_Setup_0.4.12.exe`, 54075904 bytes, NotSigned,
  SHA-256 `0C0C2789B39745233B50118F8D21E2211CAD6136290690F572C5CFD1AFAFA8EB`.
- The 66-entry Windows payload contains PrepareUpdate and no external restore
  function. The installed host app was neither run nor replaced.
- `clients\public-product-artifacts.json` is the immutable build-time receipt:
  its productionPublished=false is historical, not current publication status.

Both nodes' public stable/public-product manifests report the exact versions,
hashes and sizes, required=true and matching minimum supported versions.
The public download files on each server have those exact hashes/sizes.
No full client download, payment, email, VPN transition or update UI test was run.
No new backend enforcement test suite was run for this change.
The existing main/fallback download aliases were updated; no site HTML change
was needed. Backend source hash, paid-beta environment and paid-beta manifest
identities stayed unchanged on each node. Both databases returned quick_check=ok
and the expected backend/nginx/sync/expiry units were active in the receipts.

Evidence: `build.log`, `windows-payload.json`, `before-{fallback,primary}.json`,
`dry-run-{fallback,primary}.log`, `apply-{fallback,primary}.log`,
`after-{fallback,primary}.json`, `cleanup-{fallback,primary}.log`.
Temporary staging was removed from both nodes; rollback backups were retained.
Fallback free disk after publication was 848023552 bytes (about 809 MiB), before
temporary staging removal; monitor capacity before the next release.

## Rollback references

Use the stable publisher's scoped rollback behavior and preserve concurrent
user transactions. These are retained server-local backup directories, not
instructions to restore an entire production database:

- Fallback Android:
  `/root/greenvpn-android-stable-release-backups/20260907T112755Z-ruvds-0.4.15-2026090703`.
- Fallback Windows:
  `/root/greenvpn-windows-stable-release-backups/20260907T112804Z-ruvds-0.4.12-4645`.
- Primary Android:
  `/root/greenvpn-android-stable-release-backups/20260907T112849Z-timeweb-0.4.15-2026090703`.
- Primary Windows:
  `/root/greenvpn-windows-stable-release-backups/20260907T112851Z-timeweb-0.4.12-4645`.
