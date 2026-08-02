# Green VPN store distribution

This directory contains store-only metadata and assets. It does not publish or
replace the direct-download Android build.

## Release contract

- Package: `pro.greenvpn.app`
- Store build flag: `GREENVPN_STORE_DISTRIBUTION_BUILD=true`
- Android build environment: `GREENVPN_ANDROID_STORE_DISTRIBUTION=true`
- No advertising SDK, advertising identifier, in-app payment, account gate, or
  self-installing updater is included in the store build.
- Store updates are delivered only by the selected store.
- The existing direct-download release keeps its own updater permission and is
  not changed by a store build.

The exact RuStore candidate and physical smoke evidence are recorded in
`rustore/ru-RU/release-0.3.20.json`.

## Current channels

- RuStore: an unpublished Green VPN draft exists and accepts the current
  individual developer account. Submission remains a deliberate final action.
- Google Play: blocked until an organization developer account with a D-U-N-S
  number is available. Google Play requires organization accounts for apps
  using `VpnService`; do not create a personal account for this package.

Official policy references:

- https://www.rustore.ru/help/developers/publishing-and-verifying-apps/app-publication
- https://support.google.com/googleplay/android-developer/answer/10788890
- https://support.google.com/googleplay/android-developer/answer/13634885
