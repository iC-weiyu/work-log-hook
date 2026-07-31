[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pluginRoot = Split-Path -Parent $PSScriptRoot
$handlerPath = Join-Path $pluginRoot 'hooks\session_start.py'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

if (-not (Test-Path -LiteralPath $handlerPath -PathType Leaf)) {
    throw "Missing production handler: $handlerPath"
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function New-TestRepository {
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    & git -C $Root init -q
    if ($LASTEXITCODE -ne 0) {
        throw "git init failed for test repository: $Root"
    }

    $nested = Join-Path $Root 'nested\task'
    New-Item -ItemType Directory -Force -Path $nested | Out-Null
    return $nested
}

function Invoke-Hook {
    param(
        [Parameter(Mandatory)]
        [string]$InputJson
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'python'
    $startInfo.Arguments = '"' + $handlerPath + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Failed to start Python hook handler.'
    }

    $process.StandardInput.Write($InputJson)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)]
        [string]$Actual,

        [Parameter(Mandatory)]
        [string]$ExpectedSubstring,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Actual.Contains($ExpectedSubstring)) {
        throw "$Message Missing=[$ExpectedSubstring]"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)]
        [string]$Actual,

        [Parameter(Mandatory)]
        [string]$UnexpectedSubstring,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Actual.Contains($UnexpectedSubstring)) {
        throw "$Message Unexpected=[$UnexpectedSubstring]"
    }
}

function ConvertFrom-HookOutput {
    param(
        [Parameter(Mandatory)]
        [string]$Stdout
    )

    $trimmed = $Stdout.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'Expected one JSON object, but stdout was empty.'
    }

    try {
        return $trimmed | ConvertFrom-Json
    }
    catch {
        throw "Hook stdout was not one JSON object: $trimmed"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'work-log-hook-tests-' + [guid]::NewGuid().ToString('N')
)

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    $repoV2 = Join-Path $tempRoot 'v2'
    $cwdV2 = New-TestRepository -Root $repoV2
    $logV2 = Join-Path $repoV2 'log.md'
    $v2Content = "<!-- work-log:v2 -->`n# Recovery Checkpoint`ncritical-v2"
    Write-Utf8File -Path $logV2 -Content $v2Content
    $beforeHash = (Get-FileHash -LiteralPath $logV2 -Algorithm SHA256).Hash
    $eventV2 = @{
        hook_event_name = 'SessionStart'
        source = 'compact'
        cwd = $cwdV2
    } | ConvertTo-Json -Compress
    $resultV2 = Invoke-Hook -InputJson $eventV2
    Assert-Equal $resultV2.ExitCode 0 'v2 compact event must succeed.'
    Assert-Equal $resultV2.Stderr '' 'v2 compact event must not write stderr.'
    $payloadV2 = ConvertFrom-HookOutput -Stdout $resultV2.Stdout
    Assert-Equal $payloadV2.hookSpecificOutput.hookEventName 'SessionStart' 'Wrong hook event name.'
    Assert-Contains $payloadV2.hookSpecificOutput.additionalContext '<!-- work-log:v2 -->' 'v2 marker was not injected.'
    Assert-Contains $payloadV2.hookSpecificOutput.additionalContext 'critical-v2' 'v2 recovery content was not injected.'
    $afterHash = (Get-FileHash -LiteralPath $logV2 -Algorithm SHA256).Hash
    Assert-Equal $afterHash $beforeHash 'The Hook modified log.md.'
    Write-Output 'PASS: compact-v2-read-only'

    $repoV1 = Join-Path $tempRoot 'v1'
    $cwdV1 = New-TestRepository -Root $repoV1
    Write-Utf8File -Path (Join-Path $repoV1 'log.md') -Content (
        "<!-- work-log:v1 -->`n# Recovery Checkpoint`nlegacy-v1"
    )
    $eventV1 = @{
        hook_event_name = 'SessionStart'
        source = 'compact'
        cwd = $cwdV1
    } | ConvertTo-Json -Compress
    $resultV1 = Invoke-Hook -InputJson $eventV1
    Assert-Equal $resultV1.ExitCode 0 'v1 compact event must succeed.'
    $payloadV1 = ConvertFrom-HookOutput -Stdout $resultV1.Stdout
    Assert-Contains $payloadV1.hookSpecificOutput.additionalContext '<!-- work-log:v1 -->' 'v1 marker was not injected.'
    Assert-Contains $payloadV1.hookSpecificOutput.additionalContext 'legacy-v1' 'v1 recovery content was not injected.'
    Write-Output 'PASS: compact-v1-compatibility'

    $repoRootSelection = Join-Path $tempRoot 'root-selection'
    $nestedCwd = New-TestRepository -Root $repoRootSelection
    Write-Utf8File -Path (Join-Path $repoRootSelection 'log.md') -Content (
        "<!-- work-log:v2 -->`nroot-signal"
    )
    Write-Utf8File -Path (Join-Path $nestedCwd 'log.md') -Content (
        "<!-- work-log:v2 -->`nnested-decoy"
    )
    $rootEvent = @{
        hook_event_name = 'SessionStart'
        source = 'compact'
        cwd = $nestedCwd
    } | ConvertTo-Json -Compress
    $rootResult = Invoke-Hook -InputJson $rootEvent
    $rootPayload = ConvertFrom-HookOutput -Stdout $rootResult.Stdout
    Assert-Contains $rootPayload.hookSpecificOutput.additionalContext 'root-signal' 'Git-root log was not selected.'
    Assert-NotContains $rootPayload.hookSpecificOutput.additionalContext 'nested-decoy' 'Nested decoy log was selected.'
    Write-Output 'PASS: git-root-only'

    $startupEvent = @{
        hook_event_name = 'SessionStart'
        source = 'startup'
        cwd = $cwdV2
    } | ConvertTo-Json -Compress
    $startupResult = Invoke-Hook -InputJson $startupEvent
    Assert-Equal $startupResult.ExitCode 0 'startup event must exit successfully.'
    Assert-Equal $startupResult.Stdout '' 'startup event must not inject context.'
    Assert-Equal $startupResult.Stderr '' 'startup event must not write stderr.'
    Write-Output 'PASS: ignore-non-compact'

    $repoUnmarked = Join-Path $tempRoot 'unmarked'
    $cwdUnmarked = New-TestRepository -Root $repoUnmarked
    Write-Utf8File -Path (Join-Path $repoUnmarked 'log.md') -Content (
        "# Ordinary project log`nnot-managed"
    )
    $unmarkedEvent = @{
        hook_event_name = 'SessionStart'
        source = 'compact'
        cwd = $cwdUnmarked
    } | ConvertTo-Json -Compress
    $unmarkedResult = Invoke-Hook -InputJson $unmarkedEvent
    Assert-Equal $unmarkedResult.ExitCode 0 'unmarked log case must exit successfully.'
    Assert-Equal $unmarkedResult.Stdout '' 'unmarked log must not be injected.'
    Assert-Equal $unmarkedResult.Stderr '' 'unmarked log case must not write stderr.'
    Write-Output 'PASS: ignore-unmarked-log'

    $malformedResult = Invoke-Hook -InputJson '{not-json'
    Assert-Equal $malformedResult.ExitCode 0 'malformed input must exit successfully.'
    Assert-Equal $malformedResult.Stdout '' 'malformed input must not inject context.'
    Assert-Equal $malformedResult.Stderr '' 'malformed input must not write stderr.'
    Write-Output 'PASS: ignore-malformed-input'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
