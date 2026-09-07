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

Implementation completed; build and publication pending. Reserved candidates:
Android 0.4.15+2026090703, Windows 0.4.12+4645. Backend stays
0.9.166-product-hardening.1. Existing ownership fixtures and package contract
markers were aligned with the new invariant, but were NOT RUN. No runtime test,
analyzer, physical installation or native network transition was performed.

Stable publisher rollback is restricted to the affected platform's stable
app_releases rows. It no longer restores the whole database over payments or
subscriptions created since the publication backup. This rollback change is
source-reviewed only; no forced production failure or rollback test was run.
