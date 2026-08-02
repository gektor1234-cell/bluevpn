# RuStore submission checklist

## Artifact

- [x] Exact release APK is version `0.3.20` / `2026080301`.
- [x] Package is `pro.greenvpn.app`, min SDK 26, target SDK 36.
- [x] Release signer matches `android/release_signer_sha256.txt`.
- [x] APK passes Android lint, transport verification, signature verification,
  and 16 KB compatibility.
- [x] Physical install/connect/background/disconnect smoke is complete on the
  connected Samsung device.

## Store policy

- [x] `REQUEST_INSTALL_PACKAGES` and `AD_ID` are absent.
- [x] Yandex Mobile Ads and AppMetrica components are absent.
- [x] `VpnService` purpose and encrypted transport are disclosed.
- [x] Data-safety answers match `data-safety.md` and the public privacy policy.
- [x] The app is marked free and contains no paid offer or advertising claim.

## Media and listing

- [x] Opaque 512x512 PNG icon, under 3 MB.
- [x] At least three final phone screenshots, each under 3 MB and within
  RuStore dimensions.
- [x] Name, short description, detailed description, release notes, support,
  website, and privacy URL are prepared.

## Final external gate

- [ ] Upload the exact APK to the existing RuStore draft.
- [ ] Review every rendered field and permission declaration in the console.
- [ ] Confirm any new agreement and the final «Отправить на модерацию» action
  only at action time.
