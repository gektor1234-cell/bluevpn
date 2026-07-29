# Green VPN documentation index

Updated: 2026-07-29.

This is the only entry point for project documentation. If two documents
conflict, use the first applicable item in the precedence list below.

Current summary: production and paid-beta backend `0.9.152-release-ready.1`
are healthy on both Russian control planes. The product contract is permanent
Free with guest-first access; quota and rate enforcement, paid sales, refunds,
automatic renewals, rewarded ads and forced disconnect are fail-closed.
Android/Windows `0.3.19` exact candidates and the six-stage transport cascade
have passed physical checks, but they are not published. The remaining
external gates are Windows Authenticode, explicit production publication
approval and, only before paid sales, the owner's legal/tax/KYC decision.
Exact details are in `CURRENT_HANDOFF.md` and
`FULL_PROJECT_CLOSURE_2026_07_29_RU.md`.

## Source-of-truth order

1. `CURRENT_HANDOFF.md` - current live state, hard restrictions and blockers.
2. `RELEASE_STATE.md` - stable, candidate and rollback versions.
3. `PROJECT_MAP_RU.md` - ownership of directories, services and data.
4. `PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md` - routine deploy, backup and restore.
5. A component-specific active runbook listed below.
6. Dated evidence and audit files - proof of a past operation, not instructions
   for the current state.

Git, live configuration and a fresh readiness check take precedence over a
stale document. Never copy secrets from an old checkpoint or report.

## Start here

- `PROJECT_MAP_RU.md` - where code, sites, scripts, state and secrets belong.
- `PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md` - checkpoint, restore, deploy,
  database synchronization, Android, Windows and site procedures.
- `CURRENT_HANDOFF.md` - current branch, versions, server roles and restrictions.
- `RELEASE_STATE.md` - compact release matrix and remaining launch gates.
- `DEVELOPMENT_PROTOCOL.md` - repository workflow and verification rules.

## Active operations

- `BACKEND_DEPLOY.md` - FastAPI deploy and rollback.
- `PAYMENTS_RU.md` - YooKassa integration and payment verification.
- `SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md` - repeatable onboarding of
  a new server or transport. It does not authorize rollout by itself.
- `INFRA_PROVIDER_AUTOMATION_RU.md` - provider API operations.
- `ADMIN_SUPPORT_APP_RU.md` - support/admin application.
- `INSTALLER_TRUST_AND_AV_FALSE_POSITIVE_RU.md` - Windows signing and trust.
- `MOBILE_APP_ANDROID_MVP_RU.md` - Android build and device operations.
- `EXTERNAL_SERVICES_CHECKLIST_RU.md` - external accounts and dependencies.
- `PROJECT_EXTERNAL_SITES_RU.md` - safe inventory of every confirmed project
  website, provider panel, technical source and one-off research domain.

## Product and launch

- `GREENVPN_WORKING_MODEL_RU.md` - product behavior.
- `FULL_PROJECT_CLOSURE_2026_07_29_RU.md` - current end-to-end closure,
  evidence and owner-only gates.
- `BUSINESS_PRICING_STRATEGY_RU.md` - pricing rationale.
- `UNIT_ECONOMICS_AND_CAPACITY_RU.md` - cost and capacity model.
- `PUBLIC_PRODUCT_CANDIDATE_2026_07_11_RU.md` - public candidate evidence.
- `YOOKASSA_RECURRING_REVIEW_2026_07_11_RU.md` - recurring-payment review.

## Transport preview evidence

All transport files in this group describe the isolated NL2 preview. They are
not permission to install preview transports on any other server.

- `MULTIPROTOCOL_COMPLETION_AUDIT_2026_07_12_RU.md`
- `FIVE_STAGE_TRANSPORT_PREVIEW_2026_07_12_RU.md`
- `AMNEZIAWG2_NL2_CANARY_2026_07_11_RU.md`
- `HYSTERIA2_NL2_CANARY_2026_07_11_RU.md`
- `NAIVE_HTTPS_NL2_CANARY_2026_07_12_RU.md`
- `DNSTT_NL2_CANARY_2026_07_12_RU.md`
- `ANDROID_AWG2_PREVIEW_2026_07_11_RU.md`
- `ANDROID_HYSTERIA2_PREVIEW_2026_07_12_RU.md`
- `ANDROID_VLESS_REALITY_PREVIEW_2026_07_12_RU.md`
- `WINDOWS_AWG2_PREVIEW_2026_07_12_RU.md`
- `WINDOWS_VLESS_REALITY_PREVIEW_2026_07_12_RU.md`

## Historical evidence

Dated paid-beta, first-20, old provider-node and old handoff documents are kept
for audit and rollback evidence. They may contain superseded versions, prices,
paths and assumptions. Do not execute them without reconciling them against the
five source-of-truth documents above.

The archived configurable tariff remains intentionally preserved in
`ARCHIVED_CONFIGURABLE_TARIFF_2026_07_11_RU.md` and as an inactive method in the
client. The launch product uses fixed 30/90/180-day plans.

## Licenses

`licenses/` contains third-party license notices required by the isolated
transport preview artifacts. Do not remove a notice while its binary is shipped.
