# Green VPN Android 0.4.9: explicit auto-renew consent and stable rollout

Date: 2026-08-28 MSK.

## Result

Android `0.4.9+2026082803` and backend
`0.9.164-autorenew-checkout.1` are published to stable production. The Android
update is mandatory with `minSupportedVersion=0.4.9` on primary and fallback.
Stable Windows and both paid-beta clients were not changed.

The released checkout contract is explicit and fail-closed:

- no auto-renew choice is hidden on the tariff page;
- a future auto-renew checkout starts with consent unchecked and states the
  charge amount, frequency and cancellation path;
- Settings contains the auto-renew control;
- the current YooKassa manual NPD contour returns `autoRenew=false`;
- automatic charges remain disabled on both production nodes.

## Exact artifacts

Source commit:
`0fdc4811b9d6bf7ef821be3c452b6894b235002f`.

Signed Android APK:

- version/build: `0.4.9+2026082803`;
- size: `56364901` bytes;
- SHA-256:
  `B2E4D29F227853828F5942422C391F1A5B4A22F625B7B5EC5B036E1C94E857E8`;
- signer certificate SHA-256:
  `1EA2C985890E9010AA3B76AEE676624EC45398FD86A5E40DD95C76CDFC6A0FBC`;
- APK Signature Scheme v2: verified;
- 16 KB page compatibility: verified for all `23` native libraries.

Two independent release builds produced identical bytes:

- `C:\BlueVPN_Builds\android_autorenew_checkout_release_20260828_b2026082803_v1\GreenVPN_Android_0.4.9_2026082803.apk`;
- `C:\BlueVPN_Builds\android_autorenew_checkout_release_20260828_b2026082803_v2\GreenVPN_Android_0.4.9_2026082803.apk`.

Backend bundle:

- path:
  `C:\BlueVPN_Builds\autorenew_checkout_backend_20260828_r1\public-product-backend-autorenew-checkout-20260828-r1.tar.gz`;
- size: `305051` bytes;
- SHA-256:
  `F7A0EDEBA5C27445EA1D4E62D39B6DE5CAA7D55E1F654EE67E148D3AA0DD4F44`.

## Physical Android acceptance

The exact APK was installed in place on physical device `R9WT10CDC2J` and read
back byte-for-byte. The UI showed the main, tariff, settings and auto-renew
states correctly. The payment button stayed available, but it was not clicked;
no payment order was created.

The existing external WireGuard package remained the Android VPN owner before,
during and after acceptance. Green VPN performed no VPN transition. The app was
force-stopped after the check and the user's foreground app was restored.

Evidence root:
`C:\BlueVPN_Builds\android_autorenew_checkout_release_20260828_b2026082803_v1\physical-final`.
Acceptance report: `1341` bytes, SHA-256
`EB563931713782984765F4FD3958074B9307D5C436045782C951B2E3C9B89C38`.

## Production deployment

Backend deployment used dry-run then apply, fallback first and primary second.
Rollback backups:

- fallback:
  `/root/greenvpn-public-product-backups/20260828T163756Z-ruvds-0.9.164-autorenew-checkout.1`;
- primary:
  `/root/greenvpn-public-product-backups/20260828T163914Z-timeweb-0.9.164-autorenew-checkout.1`.

Android stable-only publication also used dry-run then apply, fallback first and
primary second. Rollback backups:

- fallback:
  `/root/greenvpn-android-stable-release-backups/20260828T164124Z-ruvds-0.4.9-2026082803`;
- primary:
  `/root/greenvpn-android-stable-release-backups/20260828T164343Z-timeweb-0.4.9-2026082803`.

Primary remains the only billing writer with manual sales and refunds enabled.
Fallback remains read-only. Both nodes use YooKassa with
`yookassa_npd_manual`; automatic renewal charges are disabled everywhere.

## Final verification

- primary and fallback stable/public-product manifests report exact Android
  `0.4.9+2026082803`, `required=true`, minimum `0.4.9` and the exact SHA/size;
- Android `0.4.8` receives HTTP `426`; Android `0.4.9` receives HTTP `200`;
- both public APK downloads match the candidate byte-for-byte;
- stable Windows remains `0.4.6+4636`, SHA-256
  `EAD00F9094D1749C9FB9ECFC5ADC7322E015552F66A40BDDFBD19D3DA15111DB`;
- paid-beta Android, Windows and backend remain unchanged;
- both production databases return `PRAGMA quick_check=ok` with synchronized
  counts; production, paid-beta, sync and retention systemd units are active;
- public catalogs expose three plans and `autoRenew=false`;
- strict public verifier passed `12/12` (`8` artifact bodies and `4` backend
  checks);
- Flutter release-profile suite passed `146` tests with `7` intentional
  platform skips; backend suite passed `220/220`;
- `flutter analyze` found no issues, secret scan passed and the release gate
  completed with warnings/errors `0/0`.

Strict report:
`C:\BlueVPN_Builds\android_autorenew_checkout_release_20260828_b2026082803_v1\production-verification\fusion-public-invariants-final.json`,
`5030` bytes, SHA-256
`CD546BC9F4BBE1D41BAC649893A007FCADBBBAFD3666BF2B0F90B086E412FBE6`.

Secret-safe database, billing-role and systemd runtime report:
`C:\BlueVPN_Builds\android_autorenew_checkout_release_20260828_b2026082803_v1\production-verification\production-runtime-final.json`,
`4889` bytes, SHA-256
`9127470DEC96F3EB18A30EA093A2D770EA869E3E90A61DB5F7E2796F38EF3783`.

Windows VPN/routes/services and Friendly Linnet `5.129.237.163` were not
touched. Windows installer signing status remains `NotSigned`.
