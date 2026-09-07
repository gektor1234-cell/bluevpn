param([string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message actual=$Actual expected=$Expected" }
}

# Execute only extracted UI handlers against mocks, never the installer or a form.
$tokens = $null
$parseErrors = $null
$builder = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $ProjectRoot 'scripts\windows\build_installer.ps1'),
    [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$uiSource = @($builder.FindAll({
    param($node)
    $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
        $node.Value.Contains('$script:processFinished = $false') -and
        $node.Value.Contains('$timer.Add_Tick')
}, $true))
Assert-Equal $uiSource.Count 1 'Exactly one embedded installer UI'
$ui = [Management.Automation.Language.Parser]::ParseInput(
    $uiSource[0].Value, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

function Get-Handler([string]$Name) {
    $node = $ui.Find({
        param($item)
        $item -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
            $item.Member.Value -eq $Name
    }, $true)
    if ($null -eq $node) { throw "Missing handler: $Name" }
    return $node.Arguments[0].ScriptBlock
}
$tick = (Get-Handler 'Add_Tick').GetScriptBlock()
$shown = Get-Handler 'Add_Shown'
$startTry = $shown.Find({ param($node) $node -is [Management.Automation.Language.TryStatementAst] }, $true)
$startFailure = [scriptblock]::Create($startTry.CatchClauses[0].Body.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
$buttonText = $ui.Find({
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$okButton.Text'
}, $true)
if ($null -eq $buttonText) { throw 'Missing initial close button text' }
$initializeButtonText = [scriptblock]::Create($buttonText.Extent.Text)

function Set-UiText { param($Title, $Detail, $Accent) $script:lastTitle = $Title; $script:lastDetail = $Detail }
function Reset-Mocks([bool]$Started, [bool]$Exited, [int]$ExitCode) {
    $script:processStarted = $Started
    $script:processFinished = $false
    $script:exitCode = 1
    $script:installerProcess = [pscustomobject]@{ HasExited=$Exited; ExitCode=$ExitCode }
    $script:form = [pscustomobject]@{ CloseCount=0 }
    $script:form | Add-Member ScriptMethod Close { $this.CloseCount++ }
    $script:timer = [pscustomobject]@{ StopCount=0 }
    $script:timer | Add-Member ScriptMethod Stop { $this.StopCount++ }
    $script:queue = [Collections.Concurrent.ConcurrentQueue[string]]::new()
    $script:progress = [pscustomobject]@{ MarqueeAnimationSpeed=34; Style='Marquee'; Value=0 }
    $script:okButton = [pscustomobject]@{ Enabled=$false; Text='' }
    $script:stageLabel = [pscustomobject]@{ Text='' }
    $script:hintLabel = [pscustomobject]@{ Text='' }
    $script:lastTitle = ''
    $script:lastDetail = ''
    . $initializeButtonText
}
$brandGreen = 'green'
$brandDanger = 'red'
$logPath = 'mock:installation-log'
$oldAutoClose = $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS
try {
    foreach ($setting in @($null, '1', '0')) {
        $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS = $setting
        Reset-Mocks $true $true 0
        . $tick
        Assert-Equal $script:exitCode 0 'Successful exit preserved'
        Assert-Equal $script:processFinished $true 'Success is finished before closure'
        $expectedCloses = if ($setting -eq '0') { 0 } else { 1 }
        Assert-Equal $form.CloseCount $expectedCloses 'Success closes by default'
        . $tick
        Assert-Equal $form.CloseCount $expectedCloses 'Completion handled only once'

        foreach ($code in @(1, 1603)) {
            Reset-Mocks $true $true $code
            . $tick
            Assert-Equal $form.CloseCount 0 'Installation failure stays visible'
            Assert-Equal $script:exitCode $code 'Failure exit preserved'
            Assert-Equal $okButton.Enabled $true 'Failure can be dismissed'
            Assert-Equal $script:lastDetail.Contains($logPath) $true 'Failure shows log location'
        }
    }
    foreach ($started in @($false, $true)) {
        Reset-Mocks $started $false 0
        . $tick
        Assert-Equal $form.CloseCount 0 'Unfinished installation never auto-closes'
        Assert-Equal $script:processFinished $false 'Pending operation stays pending'
    }
    Reset-Mocks $false $false 0
    try { throw 'mock:cannot-start' } catch { . $startFailure }
    Assert-Equal $form.CloseCount 0 'Startup failure stays visible'
    Assert-Equal $script:exitCode 1 'Startup failure exits unsuccessfully'
    Assert-Equal $okButton.Enabled $true 'Startup failure can be dismissed'
    Assert-Equal $script:lastDetail.Contains('mock:cannot-start') $true 'Startup failure explains the cause'
} finally {
    $env:GREENVPN_INSTALLER_AUTOCLOSE_SUCCESS = $oldAutoClose
}
Write-Output 'Installer completion behavior passed: 12 cases; no installation or windows opened.'
