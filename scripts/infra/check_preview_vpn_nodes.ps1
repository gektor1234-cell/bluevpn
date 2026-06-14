param(
    [Parameter(Mandatory = $false)]
    [string[]]$ServerId = @("tw-7879598-nl1", "ruvds-2584554-ld8"),

    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://api.greenvpn.pro",

    [Parameter(Mandatory = $false)]
    [string]$OriginHost = "37.220.85.211",

    [Parameter(Mandatory = $false)]
    [int]$SshConnectTimeoutSec = 10,

    [Parameter(Mandatory = $false)]
    [int]$HttpTimeoutSec = 60,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPeerSmoke,

    [Parameter(Mandatory = $false)]
    [switch]$SkipClientConfigSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\provider_api_common.ps1"

$SshPath = Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe"
if (-not (Test-Path -LiteralPath $SshPath -PathType Leaf)) {
    $SshPath = "ssh"
}

function Assert-GreenVpnSafeToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Value -notmatch $Pattern) {
        throw "$Name contains unsupported characters."
    }
}

foreach ($id in $ServerId) {
    Assert-GreenVpnSafeToken -Name "ServerId" -Value $id -Pattern "^[a-zA-Z0-9][a-zA-Z0-9_.-]{2,79}$"
}
Assert-GreenVpnSafeToken -Name "OriginHost" -Value $OriginHost -Pattern "^[A-Za-z0-9.-]+$"

$apiUri = [Uri]$ApiBaseUrl
if ($apiUri.Scheme -ne "https") {
    throw "ApiBaseUrl must use https."
}

$apiBaseJson = ($ApiBaseUrl.TrimEnd("/") | ConvertTo-Json -Compress)
$serverIdsJson = ConvertTo-Json -InputObject ([string[]]@($ServerId)) -Compress
$httpTimeout = [Math]::Max(5, $HttpTimeoutSec)
$skipPeerSmokePython = if ($SkipPeerSmoke) { "True" } else { "False" }
$skipClientConfigSmokePython = if ($SkipClientConfigSmoke) { "True" } else { "False" }

$remotePython = @"
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_BASE = $apiBaseJson
SERVER_IDS = $serverIdsJson
HTTP_TIMEOUT = $httpTimeout
SKIP_PEER_SMOKE = $skipPeerSmokePython
SKIP_CLIENT_CONFIG_SMOKE = $skipClientConfigSmokePython
TOKEN_PATH = Path("/opt/bluevpn/backend/data/admin_token.txt")


def short(value, limit=220):
    if value is None:
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    if len(text) > limit:
        return text[: limit - 3] + "..."
    return text


def call(method, path, token=None, body=None):
    headers = {"Accept": "application/json"}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    if token:
        headers["X-Admin-Token"] = token
    req = urllib.request.Request(
        API_BASE + path,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as response:
            raw = response.read()
            parsed = json.loads(raw.decode("utf-8") or "{}")
            return {"transportOk": True, "httpStatus": response.status, "json": parsed}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        return {
            "transportOk": False,
            "httpStatus": exc.code,
            "error": short(raw),
        }
    except Exception as exc:
        return {
            "transportOk": False,
            "httpStatus": None,
            "error": short(exc),
        }


def get_path(obj, *keys):
    current = obj
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def bool_or_none(value):
    if value is None:
        return None
    return bool(value)


def response_status(response):
    body = response.get("json") or {}
    return {
        "transportOk": bool(response.get("transportOk")),
        "httpStatus": response.get("httpStatus"),
        "ok": bool_or_none(body.get("ok")),
        "errorCode": body.get("errorCode") or body.get("code"),
        "message": short(body.get("message") or body.get("detail") or response.get("error")),
    }


def provisioning_summary(response):
    body = response.get("json") or {}
    summary = response_status(response)
    details = body.get("details") if isinstance(body.get("details"), dict) else {}
    summary.update(
        {
            "sshReachable": bool_or_none(
                body.get("sshReachable")
                if body.get("sshReachable") is not None
                else details.get("sshReachable")
            ),
            "wireGuardReady": bool_or_none(
                body.get("wireGuardReady")
                if body.get("wireGuardReady") is not None
                else details.get("wireGuardReady")
            ),
            "publicKeyMatches": bool_or_none(
                body.get("publicKeyMatches")
                if body.get("publicKeyMatches") is not None
                else details.get("publicKeyMatches")
            ),
        }
    )
    return summary


def peer_smoke_summary(response):
    body = response.get("json") or {}
    summary = response_status(response)
    summary.update(
        {
            "applied": bool_or_none(body.get("applied")),
            "existsAfterApply": bool_or_none(body.get("existsAfterApply")),
            "removed": bool_or_none(body.get("removed")),
        }
    )
    return summary


def client_smoke_summary(response):
    body = response.get("json") or {}
    summary = response_status(response)
    summary.update(
        {
            "applied": bool_or_none(body.get("applied")),
            "configShapeOk": bool_or_none(body.get("configShapeOk")),
            "removed": bool_or_none(body.get("removed")),
        }
    )
    return summary


def catalog_entry_summary(entry):
    if not isinstance(entry, dict):
        return {"found": False}
    return {
        "found": True,
        "title": entry.get("title"),
        "status": entry.get("status"),
        "host": entry.get("host"),
        "port": entry.get("port"),
        "clientConfigProfile": entry.get("clientConfigProfile"),
        "clientConfigReady": entry.get("clientConfigReady"),
        "isActive": entry.get("isActive"),
        "isPublic": entry.get("isPublic"),
    }


if not TOKEN_PATH.exists():
    print(
        json.dumps(
            {
                "ok": False,
                "error": "origin_admin_token_missing",
                "tokenPath": str(TOKEN_PATH),
            },
            ensure_ascii=False,
        )
    )
    sys.exit(2)

admin_token = TOKEN_PATH.read_text(encoding="utf-8").strip()
if not admin_token:
    print(json.dumps({"ok": False, "error": "origin_admin_token_empty"}, ensure_ascii=False))
    sys.exit(2)

admin_catalog_response = call(
    "GET",
    "/api/v1/admin/server-catalog?status=all&active=all&public=all&limit=500",
    token=admin_token,
)
managed_entries = []
if admin_catalog_response.get("transportOk"):
    managed_entries = (admin_catalog_response.get("json") or {}).get("managedEntries") or []

stable_catalog = call(
    "GET",
    "/api/v1/catalog/servers?channel=stable&appVersion=0.2.26",
)
preview_catalog = call(
    "GET",
    "/api/v1/catalog/servers?channel=preview&appVersion=0.2.26-adgate-preview",
)

stable_ids = {
    item.get("id")
    for item in get_path(stable_catalog.get("json") or {}, "catalog", "servers") or []
    if isinstance(item, dict)
}
preview_ids = {
    item.get("id")
    for item in get_path(preview_catalog.get("json") or {}, "catalog", "servers") or []
    if isinstance(item, dict)
}

results = []
for server_id in SERVER_IDS:
    entry = next(
        (
            item
            for item in managed_entries
            if isinstance(item, dict) and item.get("serverId") == server_id
        ),
        None,
    )
    provisioning = call(
        "GET",
        f"/api/v1/admin/server-catalog/{server_id}/remote-provisioning-check",
        token=admin_token,
    )
    if SKIP_PEER_SMOKE:
        peer_smoke = {"skipped": True}
    else:
        peer_smoke = peer_smoke_summary(
            call(
                "POST",
                f"/api/v1/admin/server-catalog/{server_id}/remote-peer-smoke",
                token=admin_token,
                body={},
            )
        )
    if SKIP_CLIENT_CONFIG_SMOKE:
        client_smoke = {"skipped": True}
    else:
        client_smoke = client_smoke_summary(
            call(
                "POST",
                f"/api/v1/admin/server-catalog/{server_id}/client-config-smoke",
                token=admin_token,
                body={},
            )
        )

    provisioning_clean = provisioning_summary(provisioning)
    required = [
        (catalog_entry_summary(entry).get("found") is True),
        (provisioning_clean.get("ok") is True),
    ]
    if not SKIP_PEER_SMOKE:
        required.append(peer_smoke.get("ok") is True)
    if not SKIP_CLIENT_CONFIG_SMOKE:
        required.append(client_smoke.get("ok") is True)

    results.append(
        {
            "serverId": server_id,
            "checksOk": all(required),
            "catalog": catalog_entry_summary(entry),
            "publicCatalog": {
                "inStable": server_id in stable_ids,
                "inPreview": server_id in preview_ids,
            },
            "remoteProvisioning": provisioning_clean,
            "remotePeerSmoke": peer_smoke,
            "clientConfigSmoke": client_smoke,
        }
    )

output = {
    "ok": all(item["checksOk"] for item in results),
    "apiBaseUrl": API_BASE,
    "originHost": "__ORIGIN_HOST__",
    "adminCatalogReadable": bool(admin_catalog_response.get("transportOk")),
    "stableCatalogReadable": bool(stable_catalog.get("transportOk")),
    "previewCatalogReadable": bool(preview_catalog.get("transportOk")),
    "serverCount": len(results),
    "servers": results,
}
print(json.dumps(output, ensure_ascii=False, indent=2))
"@

$remotePython = $remotePython.Replace("__ORIGIN_HOST__", $OriginHost)
$remotePayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($remotePython -replace "`r", "")))
$remoteCommand = "echo $remotePayload | base64 -d | python3 -"

$sshArgs = @(
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=$SshConnectTimeoutSec",
    "root@$OriginHost",
    $remoteCommand
)

$output = & $SshPath @sshArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    $safeOutput = Protect-GreenVpnString -Value (($output | Out-String).Trim())
    throw "SSH smoke check failed on origin $OriginHost`: $safeOutput"
}

$raw = (($output | Out-String).Trim())
try {
    $parsed = $raw | ConvertFrom-Json
    Write-GreenVpnJson -InputObject $parsed
} catch {
    $safeRaw = Protect-GreenVpnString -Value $raw
    throw "Origin smoke check returned non-JSON output: $safeRaw"
}
