# App reliability audit - 2026-09-07

Publication addendum: the subsequent owner instruction explicitly authorized
mandatory publication without physical acceptance. Both exact v3 artifacts are
now published; see `RELIABILITY_ROLLOUT_2026_09_07.md`. The original audit below
records the prepublication scope and does not claim physical testing passed.

## Scope and release boundary

Owner request: audit application lifecycle, recovery, behavior and security;
fix confirmed defects and prepare unpublished release candidates. No deployment.
This turn also avoids installing/switching the host VPN that carries the Codex
connection, and does not create recurring automation.
Starting source: 5eb02739b84641d4ce4eb8d202b2720e798b3600 (clean).
Existing public Android/Windows releases and both production nodes stay unchanged.

## Checklist

- [x] Read current handoff, repository state and relevant local runtime evidence.
- [x] Fix Windows competing-VPN ownership and rollback lifetime.
- [x] Fix Windows recovery preconditions and transient-offline behavior.
- [x] Audit Android revoke, offline, background and reconnect lifecycle.
- [x] Audit app status/UI, local privileged boundaries, diagnostic privacy,
      account/subscription/update contracts. Fix evidenced issues in scope.
- [x] Add behavioral regressions and run affected checks plus broader suites.
- [x] Build exact unpublished artifacts and prepare guarded release instructions.
- [x] Record findings, limitations and required physical acceptance separately.

## Verification results

- Flutter analyze: no issues. Full suite: 155 passed, 15 skipped by test conditions.
- Public-product/Fusion UI suite: 14 passed, 4 skipped by test conditions.
- Native Android release unit suite: 30 passed. Release lint: 0 errors, 47 warnings.
  Warning groups: UseKtx (27), ObsoleteSdkInt (8), ApplySharedPref (7), dependency
  version suggestions (3), InlinedApi (1), StaticFieldLeak (1). The static backend
  is constructed with applicationContext, not Activity. The API warning concerns
  the existing ServiceCompat foreground-service path. Warnings are not suppressed.
- Backend isolated full suite: 235 passed (temporary DBs/provider mocks).
- Both Windows task variants pass behavioral ownership/rollback tests, including
  an external VPN appearing before privileged Reconnect, failed cleanup and
  process-router failure. Selective routing and standby cleanup contracts pass.
- Release gate: 0 warnings, 0 errors. Windows and Android release builds succeed.
- Windows ZIP: 66 payload entries; packaged privileged recovery gate present.
- Android APK: existing signer and 16 KB native page compatibility verified.
- No live email, payment, installed-client upgrade or network-transition smoke
  was performed for these candidates. No new automations or goals were created.

## Final artifacts

Root: `C:\BlueVPN_Builds\reliability_audit_20260907_v0413_v049_b4642_v3`.
Earlier v1/v2 local builds are marked superseded and must not be published.

| Artifact | Version | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Android APK | 0.4.13+2026090701 | 56407381 | A70DA5C0F2D86627BAABFB44B366A1E96361DADDE20EA20B90DCD636AE38147A |
| Windows installer | 0.4.9+4642 | 52843520 | 0BDD42D9159B8985079D0593BFEDE339AF7D5D3934E79C68F4C81BE74F747D04 |

The final runtime component inventory is recorded alongside the artifacts in
`verification.json`. Never reuse installer or component hashes from v1/v2.

## Confirmed findings and changes

1. Both Windows task variants persist stopped competing services after takeover.
   Every Disconnect, including internal recovery and mode switching, can restart
   those services. Local logs show restore during switch cleanup and runtime
   failover. Rollback is now pending only inside the initial failed Connect;
   successful takeover commits it. Disconnect and Guard never restore it.
   Failed cleanup does not permit restoration over an unconfirmed Green tunnel.
2. Runtime route monitoring tears down before verifying an eligible standby route.
   No standby proof can leave Green disconnected after transient probe failures.
   The new path requires known ownership/status, a proven alternative and a
   30-second unhealthy interval before teardown. Otherwise it retains the tunnel
   and monitoring. This is not a promise of connectivity during an outage.
3. Unexpected-disconnect recovery omits external-VPN ownership state. Windows
   Guard also stops new competing VPNs without a fresh user connect command.
   Guard now yields. Automatic recovery uses authenticated POST /reconnect and
   the Reconnect task, which cannot stop competitors under the mutation lock.
   There is no fallback to /connect if an older controller lacks that endpoint.
4. The Windows probe lock covered only HTTP work, not the subsequent asynchronous
   recovery decision. It now covers the full operation. Restoring a monitor also
   checks the captured epoch so a late result cannot undo a newer user action.
5. Android persisted operation IDs but did not use them to reject late probe,
   connect or disconnect results. Completion and queued disconnect now check the
   ID, and stale service intents cannot change the new service restart policy.
   Network callbacks are coalesced to avoid an unbounded queue during flapping.
6. Android's coordinator accepted an initial-takeover flag but ignored it inside
   the first candidate loop. The explicit allowance now survives config fetching
   and is consumed at the first actual connection attempt; later retries yield.
7. Diagnostic redaction missed quoted JSON keys, compound token/secret keys and
   URL userinfo. Added redaction and regressions, retaining operational counters.
8. Cleanup telemetry generated unsupported stage names. The client now sends the
   supported disconnect stage and preserves the reason in details. Backend
   validation is unchanged. This restores evidence that was previously rejected.
9. The release gate required the old background takeover, and stable publishers
   contained stale change descriptions. Updated the contract checks and release
   text without running the publishers or changing deployed metadata.

## Local incident correlation

`C:\ProgramData\BlueVPN\auth.log` on 2026-09-03:

- 10:31:20 and 10:31:30: data-plane probe timeout, backend connected=true.
- 10:31:30: failure threshold triggers clean-down and ordered reconnect.
- 10:31:34: backend.log records restoration of the competing service.
- 10:31:43: backend rejects the generated runtime_probe_failed_disconnect stage.

This confirms the reported failure mechanism on this computer. It does not prove
that every event on the friend's computer has the same cause. A third-party
VPN's own auto-connect settings can also start that VPN; these are not modified.

## Audit coverage and limits

Reviewed Windows task/service entry points, controller authentication and status,
runtime/standby selection, UI state, Android operation service/coordinator and
underlying-network logic, diagnostic serialization, update enforcement and
subscription/email/payment routing contracts. Existing loopback/token protection,
protected configuration ACL/reparse checks and selected-app fail-closed routing
remain in place. No remote attribution fallback or security bypass was added.

Automated coverage includes UI/status, application discovery, configuration ACLs,
token redaction, updates, account recovery, billing/renewal/expiry and admin
subscription behavior. Backend tests use temporary databases and provider mocks;
they are not a fresh live payment or email-delivery acceptance test.

This is a targeted cross-component reliability/security audit, not a claim that
every source line or every third-party binary has been independently audited.
Physical network-loss, roaming and competing-VPN acceptance of the new artifacts
is NOT RUN. The build is not yet declared production-verified. See
`RELIABILITY_RELEASE_2026_09_07.md` for exact remaining acceptance and publication.

## Safety and evidence

No raw keys, tokens, user configurations or payment/identity data in this file.
Mocked tests must not execute live service/route operations. Build success and
unit tests are not physical network acceptance or proof of production readiness.
Primary 72.56.32.197 and fallback 176.113.81.35 are publish targets only after a
new owner instruction. Friendly Linnet 5.129.237.163 is out of scope.
