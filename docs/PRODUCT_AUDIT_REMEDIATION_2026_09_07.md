# Product audit remediation

Source audit: `FULL_PRODUCT_AUDIT_2026_09_07_RU.md`.
Baseline: `89b302e6cbc5e3f1703742194a6992a9ba335127`.

## Non-negotiable safety scope

- Never stop, replace, install, restart, disconnect or take over any host VPN.
- Never change host routes, adapters, firewall, DNS or networking services.
- No host physical smoke, recovery runner, deadman or heartbeat, even delayed.
- Network experiments only in a dedicated isolated guest; do not reuse another project's emulator.
- Local fixtures must mock VPN/process/service/installer/payment/email effects.
- No real charge, refund, tax submission or email-code delivery as a test.
- Owner authorizes primary/fallback publication on both platforms after fixes,
  retaining mandatory updates, and waives unsafe/unavailable physical checks.
- A waived check remains NOT RUN, never PASS. No claim of zero possible bugs.
- Preserve paid-beta and the excluded VPN node. Do not change host connectivity.

## Tracker

| ID | Scope | Implementation | Verification |
|---|---|---|---|
| A01 | Expiry/renewal cleanup race | IMPLEMENTED: revision fence per remote deletion | PASS: concurrent SQLite writer, renewed/revised entitlement, replica exclusion |
| A02 | Android pause preserves routing intent | IMPLEMENTED: validated mode/package intent, both IP families | PASS: JVM config parser; physical pause/resume NOT RUN |
| A03 | Windows site protection contract | MITIGATED: applications only; choose entire browser for sites | CODE + policy tests; a domain-aware engine is NOT implemented |
| A04 | Bounded, cancellable mandatory download | IMPLEMENTED | PASS: guest HTTP fixtures, truncation/oversize/cancel/header/idle/total timeout |
| A05 | Strict manifest/hash/size/version | IMPLEMENTED | PASS: incomplete metadata, untrusted URI, downgrade, modified cache, same-version build |
| A06 | Bounded support decompression | IMPLEMENTED: 512 KiB, bounded redaction, per-user throttle | PASS: expansion rejected, compatible sanitized reports |
| A07 | Stable backup retention/disk reserve | IMPLEMENTED: roots + service permissions + deploy reserve | PASS: retention fixtures; production maintenance pending |
| A08 | Email operation timeout/idempotency | IMPLEMENTED: durable bounded queue, primary-pinned polling | PASS: mocked SMTP/idempotency/restart/cooldown; live email NOT RUN |
| A09 | OTP resend/change email | IMPLEMENTED | PASS: UI resend cooldown/change-email flow |
| A10 | Authoritative auto-renew capability | IMPLEMENTED | PASS: unavailable provider cannot enable, existing agreement can cancel |
| A11 | Truthful update state | IMPLEMENTED | CODE + update policy tests |
| A12 | Session lifetime/hash/revocation | IMPLEMENTED: 90 days, digests, logout tombstones, opt-in sync format | PASS: migration, revoked raw replica, digest replay rejection, old paid-beta compatibility |
| A13 | Account logout stops own native session | IMPLEMENTED: logout, invalid session, restore, checkout promotion | CODE; physical queued/connected disconnect NOT RUN |
| A14 | Fragmented local HTTP headers | IMPLEMENTED: bounded complete header before parsing | PASS: C++ split-every-byte/oversize/NUL fixture compiled and executed in WSL |
| A15 | Redact reports before storage | IMPLEMENTED: new reports + explicit legacy migration | PASS: old/new report redaction + idempotent migration; production migration pending |
| A16 | Android unvalidated-network/ownership states | IMPLEMENTED: probe eligibility vs validation, explicit takeover epoch | PASS: native policy tests; real mobile/telephony matrix NOT RUN |
| A17 | Production test matrix/release gates | IMPLEMENTED: default + public flags, native parser CI, exact historical scanner exceptions | PASS: guest test runs and current/history secret scan; hosted CI not yet run |
| A18 | Mobile hero overlap | IMPLEMENTED: in-flow mobile layout | CODE; fresh visual browser acceptance NOT RUN |
| A19 | Download compatibility information | IMPLEMENTED: platform requirements + bounded live version fetch | CODE; live publication pending |

Publication status: NOT STARTED. Existing release files remain unchanged.

## Verification evidence

Root: `C:\BlueVPN_Builds\product_hardening_20260907_v1`.
Backend: 245 tests PASS (`backend-tests-final.log`). Android: 34 JVM tests PASS
(`android-guest-junit-pass2.log`); host only compiled test classes, guest ran them.
Final Flutter default: 167 PASS, 16 SKIP; public production: 177 PASS, 6 SKIP.
Analyzer: no issues. Fixtures include the final checkout-account-change guard.
Secret scanner passed current/untracked files and all Git history; exceptions
are exact historical fixture commit/path/line hashes, never current-tree rules.

## Release and rollback boundaries

Next candidates reserved after reading both live manifests: Android
`0.4.14+2026090702`, Windows `0.4.11+4644`, backend
`0.9.166-product-hardening.1`. They are NOT published yet.

Session storage is a one-way migration. Pause only production DB sync on both
remote control nodes until both run the new format; paid-beta retains raw-token
storage and is not upgraded. Sanitize historical report codes on both nodes
before resuming production sync. Rollback must not restore a whole DB over new
payments: rollback to old session code drops digest sessions and requires login
again, keeping production sync paused until both nodes are aligned. Financial
and subscription records remain intact. Root-only old backups follow retention;
this is not a claim that every historical backup was purged of credentials.

Physical acceptance, real email delivery, payments, mobile carrier behavior,
Windows installer execution and long-duration connection soak remain NOT RUN
under the current owner waiver. Do not equate release publication with them.
