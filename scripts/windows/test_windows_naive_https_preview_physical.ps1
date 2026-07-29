param(
    [string]$SourceConfig = 'C:\Users\gekto\GreenVPN_Checkpoints\transport_canary_naive_20260712\nl2-naive-https.client.json',
    [string]$ExpectedCanaryEgress = '5.129.216.42',
    [string]$CompetingServiceName = 'AmneziaWGTunnel$device20_full',
    [string]$ReportPath = 'C:\Users\gekto\GreenVPN_Checkpoints\windows_naive_https_preview_physical_20260729.json'
)

$script = Join-Path $PSScriptRoot 'test_windows_socks_tun_preview_physical.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script `
    -Protocol naive_https `
    -SourceConfig $SourceConfig `
    -ExpectedCanaryEgress $ExpectedCanaryEgress `
    -CompetingServiceName $CompetingServiceName `
    -ReportPath $ReportPath
exit $LASTEXITCODE
