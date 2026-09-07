# Windows installer auto-close rollout - 2026-09-07

## Scope and outcome

Owner explicitly authorized publishing this fix on Windows only. The prior
mandatory-update instruction remains in effect. Windows `0.4.10+4643` is now
published on fallback and primary. Android remains `0.4.13+2026090701` with
identical bytes and release metadata. No Android build/publisher, backend source
deployment, payment-policy change, host VPN transition or automation occurred.
Friendly Linnet was not accessed. Physical installation remains NOT RUN here;
the owner is testing upgrades personally.

Successful Windows installation now closes its window without requiring Done.
Installation/startup errors remain visible with details and a Close button.
An unfinished installation does not auto-close. Explicit diagnostic override
`GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS=0` retains the success window; unset and 1
auto-close. This does not change a browser's download UI or save-folder setting.

## Exact artifact

- Build and publisher source: `ccb25375fdb61cc320bae1ff06d0f1c4d3057f2b`, pushed.
- Installer completion implementation: `c4be7e7`, included in that source.
- Artifact: `GreenVPN_Setup_0.4.10.exe`, `52841984` bytes, NotSigned.
- SHA-256: `457630468B25767E96FB203D548AB4BE37008F188FEE1BC8D51CB5F509332EF1`.
- Packaged app PE product/file version: `0.4.10+4643`.
- Extracted installer UI SHA-256:
  `E5CB3343D117B78D52F645E05ED482D74EBB1515A885A48D5BA4F9EABF2B52F6`.
- Windows build was fresh. `-SkipChecks` avoided rerunning the entire unchanged
  Flutter/Android suite, not compilation or packaging. Focused tests, package
  checks and release gates were run separately. No Authenticode claim is made.

## Publication and verification

Both dry-runs passed. Stable-only Windows publisher applied on `176.113.81.35`
first, `72.56.32.197` second, with atomic file replacement and rollback backups.
Required=true, rollout=100%, minimum Windows=0.4.10 on stable/public-product.
Existing sessions were not forcibly disconnected. The mandatory requirement
is enforced during version-gated API requests and update checks.

- UI handler tests: 12 mocked cases passed, no windows or installation opened.
- IExpress extract-only verification: actual embedded UI matches tested source.
- Package audit: five outer files, 66 payload entries, zero errors.
- Initial package audit found a stale test requiring background competitor
  takeover. Updated the audit to match the already-shipped ownership policy:
  require yielding/explicit-connect/rollback markers and reject guard takeover.
  Both the original failure and corrected passing report are retained. No app
  runtime code was changed to accommodate the test.
- Before/after public verification: 12/12 each, eight full downloaded artifact
  bodies and four backend checks. New Windows hashes/sizes match both sites.
- Explicit before/after comparison: stable Android and both paid-beta clients
  have unchanged versions, bytes, hashes, required flags and URLs on both nodes.
- Enforcement: 12/12 across two APIs and stable/public-product channels.
  Windows 0.4.9 catalog requests return 426; 0.4.10 returns 200; old-client
  update manifests remain accessible with 200.
- Both landing pages return 200. Primary Windows link uses `/downloads/`;
  fallback `/download/windows` redirects to its correct 52841984-byte alias.
- Production sync ran primary then fallback, both success/0. Post-sync both
  production and paid-beta databases pass quick_check; required services/timers
  active, last sync/expiry jobs successful, zero failed units, nginx valid.
- Stable backend stays `0.9.165-subscription-lifecycle.2`; paid-beta backend
  stays `0.9.154-fusion-actions.1`. Primary-only sales policy is unchanged.

## Rollback and storage

New root-only rollback directories retain prior Windows 0.4.9 installer,
environment and consistent SQLite backup:

- Fallback: `/root/greenvpn-windows-stable-release-backups/20260907T044216Z-ruvds-0.4.10-4643`
- Primary: `/root/greenvpn-windows-stable-release-backups/20260907T044242Z-timeweb-0.4.10-4643`

No rollback was needed. Brief loopback connection refusals during bounded
backend restart waits were followed by successful readiness and publisher exit 0.
Temporary staging `/dev/shm/greenvpn-installer-autoclose-20260907-b4643` was
removed on both nodes, after validating exact paths and excluding symlinks.

Fallback initially had about 182 MiB free. Existing verified retention helper
was run once on Windows stable backups only, retaining four newest backups and
removing five obsolete July directories. Plan and exact deletion evidence are
retained. Android backups and live databases were untouched. The new release
adds a fifth retained rollback. Final free space is about 607 MiB on fallback
and 15 GiB on primary. Fallback storage remains limited for future releases;
the scheduled retention roots were not expanded and no new monitor was created.

## Evidence

Build root:
`C:\BlueVPN_Builds\windows_installer_autoclose_20260907_v0410_b4643_v1`.
Rollout root:
`C:\BlueVPN_Builds\windows_installer_autoclose_rollout_20260907_v0410_b4643_v1`.

Build records: `build.log`, `public-product-artifacts.json`, `package-audit.json`
(initial stale assertion), `package-audit-ownership-aligned.json`,
`packaged-ui-comparison.json`, `exact-packaged-ui.json`.
The build manifest preserves its pre-publication state; `rollout-summary.json`
is the publication record rather than rewriting immutable build provenance.

Rollout records: `public-before.json`, `public-after.json`,
`scope-and-enforcement.json`, `site-links.json`, `node-*-post-sync.json`,
`dry-run-*.log`, `apply-*.log`, `sync-*.log`, `cleanup-*.log`,
`windows-backup-retention-*.json`, `installer-completion-tests.log`,
`release-gate-before.log`, `release-gate-final.log`, `rollout-summary.json`.
Verifier fields named `stableWindowsUnchanged` compare against supplied
expectations; the explicit before/after comparison is the scope proof.

The real in-app upgrade, actual success-window auto-close and network matrix
remain owner acceptance, not claims inferred from a build or public API checks.
