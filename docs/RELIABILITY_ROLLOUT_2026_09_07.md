# Green VPN reliability mandatory rollout - 2026-09-07

## Authorization and outcome

The owner explicitly requested publication to primary and fallback, delegated
real-world device testing to themselves, and separately confirmed mandatory
updates. Both exact v3 artifacts are published. Physical acceptance remains
NOT RUN; publication does not prove that every network scenario works.

App source: `3da704da3d5d8ecd59af2bb1305c8910cbdb46dd`.
Publisher source: `e07369dccac9cd1b823eafb80840985ead7f866c`.
Both were pushed before deployment. No new client build was made in this turn.

| Platform | Version | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Android | 0.4.13+2026090701 | 56407381 | A70DA5C0F2D86627BAABFB44B366A1E96361DADDE20EA20B90DCD636AE38147A |
| Windows | 0.4.9+4642 | 52843520 | 0BDD42D9159B8985079D0593BFEDE339AF7D5D3934E79C68F4C81BE74F747D04 |

Android uses the existing release signer. Windows remains NotSigned and may
display a Windows security warning. No signing claim or workaround was added.

## Deployment

Used existing stable-only publishers: dry-run on both nodes, apply on fallback
`176.113.81.35`, then primary `72.56.32.197`. Required=1, rollout=100%, minimum
Android=0.4.13, Windows=0.4.9. Backend environment/release rows and stable aliases
changed; backend source, paid-beta, billing and charge settings did not.
No owner-computer VPN transition or automation. Friendly Linnet was not accessed.

Root-only temporary staging used `/dev/shm` because fallback disk was limited;
all uploaded staging files were removed after success. Persistent rollback:

- fallback Android: `/root/greenvpn-android-stable-release-backups/20260907T040514Z-ruvds-0.4.13-2026090701`
- fallback Windows: `/root/greenvpn-windows-stable-release-backups/20260907T040550Z-ruvds-0.4.9-4642`
- primary Android: `/root/greenvpn-android-stable-release-backups/20260907T040637Z-timeweb-0.4.13-2026090701`
- primary Windows: `/root/greenvpn-windows-stable-release-backups/20260907T040642Z-timeweb-0.4.9-4642`

Each publisher saved the prior platform file, environment and consistent SQLite
backup and included error rollback. No rollback was needed. Local health requests
briefly refused connections during bounded backend restart waits; all publishers
subsequently passed readiness and exited successfully.

## Verification

- Before/after public checks: 12/12 each, including full-body SHA/size checks
  for stable and paid-beta files through both public sites.
- Stable/public-product manifests: exact version/build/SHA/size, required=true,
  rollout=100%, minimum equal to new version, fileReady=true.
- Explicit enforcement: 24/24 across both API roots and stable/public-product
  channels. Old Android 0.4.12 and Windows 0.4.8 receive 426; new versions receive
  200; old-client update manifests remain reachable with 200.
- Four landing-page download links verified. Primary uses `/downloads/...`;
  fallback `/download/android` and `/download/windows` redirect to its correct
  new stable aliases. Both pages return 200.
- Paid-beta APK/installer and backend versions match the prior snapshot. Stable
  backend remains 0.9.165-subscription-lifecycle.2; paid-beta backend remains
  0.9.154-fusion-actions.1. Primary-only paid-sales policy is unchanged.
- All four production/paid-beta DB quick_checks are ok. Explicit production sync
  ran primary then fallback, both success/0. Post-sync manifests correct, required
  units/timers active, no failed units, nginx configuration valid.
- Publication contract, pubspec, VERSION, helper defaults and handoff now match
  published versions. Final local gate result is in the rollout evidence.

## Evidence and limitations

Build root: `C:\BlueVPN_Builds\reliability_audit_20260907_v0413_v049_b4642_v3`.
Rollout root: `C:\BlueVPN_Builds\reliability_rollout_20260907_v0413_v049_b4642_v1`.
Records: `public-before.json`, `public-after.json`, `mandatory-enforcement.json`,
`site-links.json`, `node-*-post-sync.json`, `apply-*.log`, `rollout-summary.json`.
Legacy verifier fields `stableWindowsUnchanged`/`stableAndroidUnchanged` mean
equality to supplied expectations, not the old versions. Before/after records
show the upgrade. The initial final gate found six stale helper-default identity
values, corrected without rebuilding clients or weakening checks; retain both
the initial failure log and final pass log.

Actual upgrade and unstable-network/competing-VPN testing is delegated to owner.
No live email, banking, purchase or physical network test occurred here. Existing
active sessions are not forcibly terminated; clients encounter mandatory updates
when checking updates or using version-gated APIs.

Residual operations risk: fallback free disk approximately 182 MiB after new
rollback copies. Deployment and DB sync passed, but storage needs attention
before another release. Installed retention does not cover stable-only backup
directories. No historical backups were deleted or hosting purchases made.
