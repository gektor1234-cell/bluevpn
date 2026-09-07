# Product Hardening Rollout, 2026-09-07

## Published

Owner authorized both stable platforms, mandatory updates and publication on
primary/fallback, while prohibiting any host-PC VPN or network transition.
Publication completed fallback first, primary second. No rollback was needed.

| Component | Version | Bytes | SHA-256 |
|---|---|---:|---|
| Android APK, signed | 0.4.14+2026090702 | 56443701 | 39323FCACEEE074191E32477DFFBE407D78435A122D1D3CAF27B024D357FDE4A |
| Windows EXE, NotSigned | 0.4.11+4644 | 52853760 | 100EE4AC758D9F0095375F2726CF0086BBAC8EA1125AE1439895748D847498C1 |
| Backend bundle r2 | 0.9.166-product-hardening.1 | 322496 | 6C1ED853F3895A757AE30614B2EC05609BA38C197D77C29525DCF9781C27B1A9 |

Both platforms have required=true, rollout=100%, and minimum supported version
equal to the new platform version. Public files were fully downloaded and hashed;
this did not execute an installer or replace the running host application.

App implementation source: `d11545aaaf1f1553784643e27958c4a47d029877`.
Backend packaging source: `0b77fbcaa6ef4a28781d0c7e4e64e5cb23516d72`.
Later release-record/default-version/CSP/gate changes do not rebuild these files.
The deployed backend uses its explicit version environment override; the source
default was aligned only after publication. The generic backend publisher also
gained a disk-reserve preflight for future backend-only deployments; this rollout
already passed the stricter client+DB reserve checks before backend deployment.

## Audit Coverage

`PRODUCT_AUDIT_REMEDIATION_2026_09_07.md` tracks all A01-A19 findings separately.
Implemented changes cover subscription cleanup fencing, Android pause/network
intent, account-change cleanup, asynchronous idempotent email delivery, resend,
capability-aware renewal UI, bounded verified downloads, session digests/expiry/
revocation, bounded sanitized support storage, HTTP header fragmentation,
retention, public-test flags and site compatibility information.

Windows site-only protection is **mitigated by restricting selection to whole
applications**, not by claiming that a DNS snapshot protects every domain/CDN/IP
family. Select the entire browser for websites. Legacy site-only selections need
explicit application selection. A true domain-aware engine is not implemented.

The site retains its existing design and contains no application screenshots.
The mobile graphic is in normal flow. Version text comes from the public manifest
with a bounded request and an honest unavailable state. The main site's CSP now
allows that request specifically to `https://api.greenvpn.pro`; other restrictions
remain. The fallback's existing API-front-door behavior is preserved; its stored
site files and public download aliases are updated, not replaced with a new route.

## Verification

- WSL guest backend suite: 245 PASS, including real concurrent SQLite writers.
- WSL guest Flutter: default 167 PASS / 16 SKIP; public 177 PASS / 6 SKIP.
- Flutter analyzer: no issues.
- Android test classes compiled without executing them on Windows; guest JVM:
  34 PASS. Release signing and 16 KiB native-library checks PASS.
- C++ header parser compiled/executed in WSL: split boundaries, oversize and NUL PASS.
- Guest Linux PowerShell release gate, StaticOnly: zero errors, one explicit
  NOT RUN warning for the Windows PowerShell child-process standby fixture.
  Windows interop directories were excluded from the guest PATH.
  One redundant repeat could not start WSL due to host resource limits; its
  error is retained separately. A bounded retry with a temporary 3 GiB / two-CPU
  guest limit passed. The temporary .wslconfig was removed, restoring its prior
  absence; no other guest or host network service was stopped or reconfigured.
- Current/untracked and full-history secret scanning PASS. Historical fixture
  exceptions are exact commit/path/line hashes, not current-tree exclusions.
- Post-sync public artifact/backend checks: 12/12. Version enforcement: 24/24,
  old clients 426, current clients 200, old-client update manifests 200.
- All four paid-beta public artifacts and both paid-beta backend versions remain
  unchanged. Paid-beta environment hashes and its raw-session format unchanged.
- Both production and paid-beta DBs: quick_check=ok. Sync success/0, expected
  units/timers active, no failed units. Primary sales remain enabled; fallback
  sales remain disabled. Automatic charges remain disabled in manual NPD mode.
- Both production DBs migrated from 206 raw sessions to zero raw sessions.
  Ten old support reports per node sanitized, zero unreadable reports.
- Final free disk after scheduled retention: fallback 1157804032 bytes,
  primary 17573793792 bytes. Four latest backups are retained per allowed root.

## Waived, Not Passed

No host VPN/service/route/DNS/firewall/adapter changes, native installation,
physical full-selected-full test, real email-code delivery, real charge/refund,
phone modification, competing-VPN experiment or carrier/telephony test ran.
The Windows package input ZIP has 66 entries; the resulting SFX was not executed
even for extraction. A new desktop/mobile browser visual acceptance was not run.
These are NOT RUN under the owner's waiver, not guarantees of zero future bugs.
The earlier emergency-calls-only report is not proven to be caused by the VPN.
No Codex automation, goal, extra task or recurring assistant runner was created.
Temporary deployment staging was removed from both nodes after final verification.
Live downloads, rollback backups and databases were preserved.

## Rollback And Evidence

Backend backups:
- fallback `/root/greenvpn-public-product-backups/20260907T073405Z-ruvds-0.9.166-product-hardening.1`
- primary `/root/greenvpn-public-product-backups/20260907T073512Z-timeweb-0.9.166-product-hardening.1`

Exact Android, Windows and site rollback directories are in the corresponding
`*-apply-*.log` files below. Never restore a whole DB over newer payments. The
one-way session migration requires fresh login when rolling back to old session
code; keep production sync paused until both nodes agree on the storage format.
Historical backups remain root-only and follow retention; they are not claimed
to have been individually scrubbed of every old sensitive value.

Evidence root: `C:\BlueVPN_Builds\product_hardening_20260907_v1`.
Key records: `final-verification.json`, `public-before.json`, `public-after.json`,
`node-*-before.json`, `node-*-after.json`, all build/test/deployment logs,
`windows-payload-identity.json`, `retention-*.json`, `release-gate-guest-final.log`,
`release-gate-repeat-resource-failure.log`, `cleanup-fallback.log`,
`cleanup-primary.log`, `secret-scan-postrelease.log`.
Immutable build provenance remains `clients/public-product-artifacts.json` with
productionPublished=false at build time. This document and final verification
record subsequent publication; build provenance is not rewritten.
