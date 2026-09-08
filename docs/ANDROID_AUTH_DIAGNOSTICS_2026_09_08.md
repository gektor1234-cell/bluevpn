# Android session recovery and bounded support diagnostics

## Scope and evidence

The owner authorized fixing Android's expired-session handling, expanded low-cost
diagnostics and mandatory Android publication on primary/fallback. No host VPN,
route, adapter, physical installer or phone action is authorized by this work.
No new automation. Windows, backend access policy, billing and paid-beta stay
unchanged. Existing 90-day session expiry remains enforced; no token resurrection.

Read-only investigation on both nodes established that the account in the owner-
provided report has no age-valid session. Its sessions were created in May.
Primary support POSTs returned 401 at 15:35:04/09 UTC on September 8, matching
the report timestamp. No device route events or stored support reports existed.
Account/device identifiers and tokens are deliberately not recorded here.

## Implementation contract

- Native config HTTP 401 terminates candidate selection immediately and does not
  poison per-route cooldowns. Session/device-missing is also authentication-required.
- Runtime clears retry/resume intent and enters authentication_required. It does
  not stop an already running VPN just because authentication expired.
- Android UI marks the session as requiring login, offers the existing email-code
  dialog through public login endpoints, and stops new VPN attempts until login.
  The email is fixed to the current account during reauthentication. No automatic
  code submission, bypass of email verification or renewal of expired tokens.
- Acknowledging a newly persisted session clears only the terminal auth marker;
  it does not connect, disconnect, restore another VPN or change the selected mode.
- Support submission refreshes native status first, records snapshot time, includes
  runtime operation/reason/error/network state and bounded journal pages. Failures
  always release the send lock and retain an available fallback report code.
- An unauthorized report asks for reauthentication on the next send; it does not
  silently upload under a guest/different account.

## Journal cost and privacy

App-private no-backup storage, two rotating 96-KiB files; at most 64 pending
records and 400 exported events in 100-entry pages. Records older than 24 hours
are excluded; stale files are removed on the next write. There is no extra
heartbeat timer, wake lock, socket probe or periodic upload. Actual changes have
wall-clock and monotonic timestamps and elapsed durations, rather than fabricated
unchanged observations every second. Collection occurs only in Diagnostics.

Recorded: activity lifecycle, native operation/state transitions, permission and
network flags, route/cascade failures, API status and request duration, recovery
counters, battery optimization flags, Android SDK/model and app memory figures.
Only an explicit field allowlist is accepted. Credentials, full configuration,
URLs, IP addresses, email values and long opaque strings are not journaled.
No browsing history, packets, screenshots, contacts or other applications' logs.
No historical data can be reconstructed for old versions before this journal.

## Release state

Android 0.4.16+2026090801 is published as mandatory stable on fallback and primary,
with minimum Android 0.4.16. Windows remains 0.4.12+4645. Flutter analyze: no issues. Seven focused
Dart/widget checks and five Kotlin JUnit checks passed in the existing WSL guest,
with host executable paths excluded. Android debug/unit-test Kotlin compiled.
Evidence: C:\BlueVPN_Builds\android_auth_diagnostics_20260908_v1\guest-checks.log.
No physical acceptance, battery benchmark or live email login has been run.

Source: cb4ce4fa2242e16c6313a6938b2ea800ed33adcf (app and publisher, clean build).
APK: clients\GreenVPN_Android_0.4.16_2026090801.apk under the evidence root above.
Size: 56467221 bytes. SHA-256:
D5A171C39E674A2FF94B8C8C631362B777187C8376B097577056E445CB5965A5.
Package pro.greenvpn.app, versionName 0.4.16, versionCode 2026090801;
min SDK 26, target SDK 36, arm64-v8a/x86_64. APK v2 signature verified with
certificate SHA-256 1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC.
ZIP and all 23 native libraries pass 16-KiB compatibility checks.

Fallback dry-run/apply completed before primary dry-run/apply. Both public
stable/public-product manifests match the exact version, SHA, size and minimum.
All 16 HTTPS API checks passed: Android 0.4.15 catalog requests receive 426,
0.4.16 receives 200, and both versions can retrieve update manifests (200).
Both HTTPS download bodies match the APK hash and size, not merely HEAD metadata.
Before/after receipts verify unchanged Windows bytes/manifests, paid-beta
manifests/environment hashes and backend source hashes. All four databases pass
quick_check; production/nginx and sync/expiry timers are active.
Latest stable/paid-beta sync service results are success/0 on both nodes.
Post-publication free disk: fallback 905322496 bytes, primary 16987406336 bytes.
Evidence files: build.log, primary/fallback-before.json, primary/fallback-after.json,
primary/fallback-dry-run.log, primary/fallback-apply.log, public-verification.json.
The original candidate manifest retains productionPublished=false as a build-time
statement; the subsequent publication receipts establish the deployed state.
The uniquely named /dev/shm staging directory was removed on both nodes only
after successful receipts and HTTPS verification were saved locally. Rollback
backups remain in place. See primary/fallback-cleanup.log and sync.log evidence.

Rollback backups retained on their respective nodes:
- Fallback: /root/greenvpn-android-stable-release-backups/20260908T162254Z-ruvds-0.4.16-2026090801.
- Primary: /root/greenvpn-android-stable-release-backups/20260908T162522Z-timeweb-0.4.16-2026090801.
Use the publisher's release-row-only rollback, never restore the entire database
over payments or account changes made after publication. Do not reuse staging as
a physical runner, touch the excluded node or run host VPN acceptance.
