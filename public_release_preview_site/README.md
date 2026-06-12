# Green VPN Release Preview Site

This is a separate closed-preview static site for the paid/rewarded-ad launch scenario.

It intentionally does not replace or modify `public_demo_site`.

Current online path with no extra domain cost:

`https://greenvpn.pro/release-preview-20260517-private/`

Stable suggested path if/when the owner wants a prettier private URL:

`https://greenvpn.pro/release-preview/`

Deployment shape:

- copy `index.html` and `styles.css` to `/var/www/greenvpn/release-preview-20260517-private/`;
- keep icon served from the current root `/assets/`;
- use separate preview artifacts in `/downloads/`:
  - `GreenVPN_Setup_0.2.10_adgate_preview_routeprobe.exe`, SHA256 `7F6FA38059464117D60129F3353AA873AC7AB630182D15383910E3FFB034DCFA`;
  - `GreenVPN_Android_preview_latest.apk` always points to the latest closed-preview Android build;
  - current versioned Android build: `GreenVPN_Android_0.2.14_2026053106_preview.apk`, SHA256 `33CE6EDB02BB1ABA937F83057C9DBEEF9CE4BCDEA5D62D2C25BF86F8D7EA25E7`;
- keep `robots` as `noindex,nofollow`;
- optionally protect the path with Nginx basic auth before sending it outside the owner/friends group.

Android `0.2.14-adgate-preview-routeprobe-android-diagnostics` is the current rewarded-preview build. It uses the real Yandex rewarded path, includes the Green VPN Quick Settings tile, uses platform-aware in-app updates, follows the actual backend-returned VPN node after config provisioning, retries YouTube route probes, and sends Android-aware support diagnostics.

Backend server-only env has Android rewarded enabled and a Yandex rewarded ad unit value present. Do not store that value in this repo; the Android client should read it through `adGate.androidRewarded` from `/api/v1/client/bootstrap`.

Windows `0.2.10-adgate-preview-routeprobe` is the current rewarded-preview installer. Windows Developer Mode must be enabled on this PC for Flutter Windows plugin builds because they require symlink support.

Main public downloads are separate from this preview. As of 2026-05-31, main Android is `0.2.14-trial-only-routeprobe-android-diagnostics` no-ads at `/downloads/GreenVPN_Android.apk`; main Windows remains on the current no-ads installer at `/downloads/GreenVPN_Setup.exe`. The main app marker does not contain `adgate`, so backend ad-gate does not apply there.

Android preview deploy command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\deploy_android_preview_apk.ps1 -ApkPath 'C:\BlueVPN_Builds\GreenVPN_Android_0.2.14_2026053106_preview.apk'
```

Android release build + automatic preview upload:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build_android_apk.ps1 -Mode release -DeployPreview
```
