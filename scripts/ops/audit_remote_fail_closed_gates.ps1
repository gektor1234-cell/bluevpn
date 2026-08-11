[CmdletBinding()]
param(
    [string]$TimewebHost = 'root@72.56.32.197',
    [string]$RuvdsHost = 'root@176.113.81.35',
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$remoteProbe = @'
import json
import os
import re
import subprocess
import sys

service, env_path = sys.argv[1:]
service_active = subprocess.run(
    ["systemctl", "is-active", "--quiet", service],
    check=False,
).returncode == 0
environment_files = subprocess.run(
    ["systemctl", "show", service, "-p", "EnvironmentFiles", "--value"],
    check=True,
    capture_output=True,
    text=True,
).stdout
environment_file_bound = env_path in environment_files
runtime_environment_readable = os.path.isfile(env_path) and os.access(env_path, os.R_OK)
values = {}
if runtime_environment_readable:
    assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")
    with open(env_path, encoding="utf-8") as handle:
        for raw in handle:
            match = assignment.match(raw.strip())
            if not match:
                continue
            value = match.group(2).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
                value = value[1:-1]
            values[match.group(1)] = value

def explicitly_false(name):
    return name in values and values[name].strip().lower() in {
        "0", "false", "no", "off", "disabled"
    }

def effectively_false(name):
    return values.get(name, "").strip().lower() not in {
        "1", "true", "yes", "on", "enabled"
    }

result = {
    "serviceActive": service_active,
    "environmentFileBound": environment_file_bound,
    "runtimeEnvironmentReadable": runtime_environment_readable,
    "paidSalesDisabled": explicitly_false("GREENVPN_PAID_SALES_ENABLED"),
    "adsDisabled": (
        effectively_false("GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED")
        and effectively_false("GREENVPN_YANDEX_REWARDED_WEB_ENABLED")
    ),
    "forcedSessionTimerDisabled": explicitly_false("GREENVPN_FREE_AD_SESSION_TIMER_ENABLED"),
    "autoRenewChargesDisabled": explicitly_false("GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED"),
    "refundExecutionDisabled": explicitly_false("GREENVPN_REFUND_EXECUTION_ENABLED"),
    "freeQuotaDisabled": explicitly_false("GREENVPN_FREE_TIER_QUOTA_ENFORCED"),
    "freeRateLimitDisabled": explicitly_false("GREENVPN_FREE_TIER_RATE_LIMIT_ENFORCED"),
}
result["success"] = all(result.values())
print(json.dumps(result, separators=(",", ":")))
'@

function Invoke-ValueBlindProbe {
    param(
        [Parameter(Mandatory = $true)][string]$ServerHost,
        [Parameter(Mandatory = $true)][string]$Service,
        [Parameter(Mandatory = $true)][string]$EnvironmentFile
    )

    $output = $remoteProbe | & ssh -o BatchMode=yes -o ConnectTimeout=15 `
        $ServerHost python3 - $Service $EnvironmentFile
    if ($LASTEXITCODE -ne 0) {
        throw "Remote value-blind audit failed for $ServerHost/$Service."
    }
    return ($output | ConvertFrom-Json)
}

$hostDefinitions = @(
    [pscustomobject]@{ name = 'timeweb'; host = $TimewebHost },
    [pscustomobject]@{ name = 'ruvds'; host = $RuvdsHost }
)
$scopeDefinitions = @(
    [pscustomobject]@{
        name = 'production'
        service = 'bluevpn-backend.service'
        environmentFile = '/etc/bluevpn/backend.env'
    },
    [pscustomobject]@{
        name = 'paid-beta'
        service = 'greenvpn-paid-beta.service'
        environmentFile = '/etc/bluevpn/paid-beta.env'
    }
)

$hostResults = foreach ($hostDefinition in $hostDefinitions) {
    $scopeResults = foreach ($scopeDefinition in $scopeDefinitions) {
        $probe = Invoke-ValueBlindProbe `
            -ServerHost $hostDefinition.host `
            -Service $scopeDefinition.service `
            -EnvironmentFile $scopeDefinition.environmentFile
        [pscustomobject]@{
            scope = $scopeDefinition.name
            serviceActive = [bool]$probe.serviceActive
            environmentFileBound = [bool]$probe.environmentFileBound
            runtimeEnvironmentReadable = [bool]$probe.runtimeEnvironmentReadable
            paidSalesDisabled = [bool]$probe.paidSalesDisabled
            adsDisabled = [bool]$probe.adsDisabled
            forcedSessionTimerDisabled = [bool]$probe.forcedSessionTimerDisabled
            autoRenewChargesDisabled = [bool]$probe.autoRenewChargesDisabled
            refundExecutionDisabled = [bool]$probe.refundExecutionDisabled
            freeQuotaDisabled = [bool]$probe.freeQuotaDisabled
            freeRateLimitDisabled = [bool]$probe.freeRateLimitDisabled
            success = [bool]$probe.success
        }
    }
    [pscustomobject]@{
        host = $hostDefinition.name
        success = @($scopeResults | Where-Object { -not $_.success }).Count -eq 0
        results = @($scopeResults)
    }
}

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    success = @($hostResults | Where-Object { -not $_.success }).Count -eq 0
    secretValuesExposed = $false
    hosts = @($hostResults)
}
$json = $report | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $fullReportPath = [IO.Path]::GetFullPath($ReportPath)
    $reportDirectory = Split-Path -Parent $fullReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    [IO.File]::WriteAllText(
        $fullReportPath,
        $json + "`n",
        [Text.UTF8Encoding]::new($false)
    )
}
$json
if (-not $report.success) {
    throw 'One or more remote fail-closed gates are not explicitly disabled.'
}
