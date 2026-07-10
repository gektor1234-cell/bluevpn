# Green VPN paid beta site

Test-only static package for the closed paid beta. It must never replace `public_demo_site` or the production `/downloads/` aliases.

Expected isolated routes:

- page: `/paid-beta/`;
- Android: `/paid-beta/downloads/GreenVPN_Android.apk`;
- Windows: `/paid-beta/downloads/GreenVPN_Setup.exe`;
- integrity manifest: `/paid-beta/downloads/manifest.json`.

Deployment requirements:

- serve `robots.txt` and the page with `X-Robots-Tag: noindex, nofollow, noarchive`;
- do not expose directory listings;
- publish only artifacts built with `GREENVPN_PAID_BETA_BUILD=true` and `/paid-beta-api` URLs;
- keep production stable downloads and update manifests unchanged;
- use the same static package on Timeweb Moscow and RUVDS Moscow;
- do not publish until the isolated backend, both downloads and real-device smoke are green.
