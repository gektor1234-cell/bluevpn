# Reliability release preparation - historical procedure

Publication completed on 2026-09-07 after a subsequent explicit owner instruction
to publish both platforms with mandatory updates and let the owner test devices.
See `RELIABILITY_ROLLOUT_2026_09_07.md` for authoritative publication evidence.
Physical acceptance was not performed and is not marked as passed. The procedure
below is the original preparation record, not an instruction to publish again.

Final artifact directory:
`C:\BlueVPN_Builds\reliability_audit_20260907_v0413_v049_b4642_v3`.
The v1/v2 builds are superseded. No build has been installed or published.

Windows: 0.4.9+4642. Android: 0.4.13+2026090701.
Authoritative artifact hashes/sizes are in `public-product-artifacts.json`.
Windows remains unsigned; Android uses the existing release signing identity.
No backend deployment or payment configuration change is required for these fixes.

## Required acceptance before publishing

Do not treat build/unit results as physical acceptance. The remaining release gate
is a controlled run of the exact candidates, including:

1. Windows: explicit takeover from an external VPN, at least 30 minutes of use,
   brief and sustained network loss, recovery with and without a proven standby,
   explicit disconnect, and external VPN activation after takeover. Verify that
   Green does not restart the previous VPN or retake it automatically.
2. Windows: full -> selected applications -> full, selected/unselected egress,
   IPv6 containment, process-router failure cleanup and truthful diagnostics.
3. Android: connect/disconnect/connect during a delayed request, minimize/restore,
   loss and return of the underlying network, external VPN takeover, and an old
   queued Disconnect arriving after a new Connect. Verify persisted intent and
   notification/status agree. No actual payments are needed for this regression.
4. Preserve exact logs, installed hashes and final network baseline. Never run
   live host VPN transitions from an active Codex response. Use the existing
   delayed detached runner with independent recovery, not recurring automation.
5. Obtain the owner's new publication instruction. No such instruction applies
   to this task: the latest request explicitly prohibits publication now.

## Publication commands after acceptance and owner approval

Use the existing stable-only publishers; do not use the public-product Android
publisher (it also touches paid-beta). Role `timeweb` below is a publisher option,
not an SSH alias. Always use the literal hosts below; never use 5.129.237.163.

The following PowerShell prepares the approved exact artifacts on both nodes and
runs the existing dry-run validation. It is documented, not executed in this task.

```powershell
$root = 'C:\BlueVPN_Builds\reliability_audit_20260907_v0413_v049_b4642_v3'
$manifest = Get-Content "$root\public-product-artifacts.json" -Raw | ConvertFrom-Json
$android = $manifest.artifacts | Where-Object platform -eq 'android'
$windows = $manifest.artifacts | Where-Object platform -eq 'windows'
$key = "$HOME\.ssh\id_ed25519"
$remote = '/root/greenvpn-reliability-20260907-b4642'
$nodes = @(@{ip='176.113.81.35';role='ruvds'}, @{ip='72.56.32.197';role='timeweb'})
foreach ($artifact in @($android, $windows)) {
    if ((Get-FileHash $artifact.path -Algorithm SHA256).Hash -ne $artifact.sha256 -or
        (Get-Item $artifact.path).Length -ne $artifact.sizeBytes) { throw 'Local artifact mismatch' }
}
foreach ($node in $nodes) {
    & ssh -o BatchMode=yes -i $key "root@$($node.ip)" "mkdir -p '$remote'"
    if ($LASTEXITCODE) { throw 'Remote directory failed' }
    & scp -o BatchMode=yes -i $key $android.path $windows.path "$root\publish-tools.tar" "root@$($node.ip):$remote/"
    if ($LASTEXITCODE) { throw 'Upload failed' }
    & ssh -o BatchMode=yes -i $key "root@$($node.ip)" "tar -xf '$remote/publish-tools.tar' -C '$remote'"
    if ($LASTEXITCODE) { throw 'Publisher extraction failed' }
    foreach ($artifact in @($android, $windows)) {
        $platform = $artifact.platform
        $file = [IO.Path]::GetFileName($artifact.path)
        $fileOption = if ($platform -eq 'android') { '--apk' } else { '--installer' }
        $command = "bash '$remote/scripts/server/install_${platform}_stable_release.sh' --role $($node.role) $fileOption '$remote/$file' --version $($artifact.version) --build-number $($artifact.buildNumber) --sha256 $($artifact.sha256) --required 1 --min-supported-version $($artifact.version)"
        & ssh -o BatchMode=yes -i $key "root@$($node.ip)" $command
        if ($LASTEXITCODE) { throw "Dry-run failed: $platform $($node.ip)" }
    }
}
```

After both dry-runs pass, repeat the inner publisher commands with `--apply`,
fallback first, primary second. Stop on any failure; each existing publisher
preserves rollback state and switches only its platform's stable artifact.

Verify both stable/public-product manifests and complete downloaded bodies against
the local hashes. Check old/current client enforcement (426/200), manifest HTTP
200, paid-beta unchanged, DB quick_check, sync, health and units. Only then update
`release_contract.json`, `VERSION.txt`, `pubspec.yaml`, build defaults and the handoff
to mark these versions as published. Keep the existing published identity until
that point. This is a release procedure, not evidence that deployment occurred.
