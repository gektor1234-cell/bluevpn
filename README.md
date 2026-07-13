# Green VPN

Green VPN is a Flutter client, FastAPI control plane, VPN-node automation and
operator console for Android and Windows.

## Start here

1. `docs/README.md` - documentation index and source-of-truth order.
2. `docs/CURRENT_HANDOFF.md` - current live state and hard safety rules.
3. `docs/PROJECT_MAP_RU.md` - component and directory map.
4. `docs/PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md` - deploy, rollback and recovery.
5. `docs/SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md` - isolated transport rollout.

## Main components

- `lib/` - Flutter application and client-side transport selection.
- `android/` - Android VPN service and isolated transport-preview engines.
- `windows/` - Windows runner; service and installer automation live in `scripts/windows/`.
- `backend_live/` - FastAPI control plane, billing, catalog, support and monitoring API.
- `admin_support_app/` - operator-only support and readiness console.
- `scripts/` - repeatable build, deploy, monitoring, provider and recovery operations.
- `paid_beta_site/`, `public_demo_site/` - isolated commercial-site sources.

Production credentials, private keys, payment secrets and provider tokens are
never stored in this repository. They belong in the protected local secret
store or root-only server environment files.

## Verification

```powershell
python -m unittest discover -s backend_live/tests -p "test_*.py"
python scripts/security/scan_tracked_secrets.py --include-untracked --history
flutter analyze --no-pub
flutter test --no-pub
powershell -ExecutionPolicy Bypass -File scripts/windows/bluevpn_release_gate.ps1
```

Do not deploy production or change a public update manifest without first
creating and verifying a full restore checkpoint.
