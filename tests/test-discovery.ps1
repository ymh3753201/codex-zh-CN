#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-discovery-' + [guid]::NewGuid().ToString('N'))
$oldDesktop = $env:CODEX_DESKTOP_PATH
$oldChinese = $env:CODEX_ZH_CN_PATH
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $app = Join-Path $root 'custom drive folder [01] & special'
    [void][IO.Directory]::CreateDirectory((Join-Path $app 'resources'))
    [IO.File]::WriteAllText((Join-Path $app 'resources\app.asar'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $app 'Codex.exe'), 'fixture')
    $env:CODEX_DESKTOP_PATH = ''; $env:CODEX_ZH_CN_PATH = ''
    . (Join-Path $PSScriptRoot '..\scripts\install_windows.ps1') -CodexHome (Join-Path $root 'data') -NoRestart
    function Get-AppxPackage { @() }
    function Get-OfficialZhResourceStatus { [pscustomobject]@{ Complete=$true } }
    $sid = (Get-Process -Id $PID).SessionId
    function Get-CimInstance { @([pscustomobject]@{ SessionId=$sid; ExecutablePath=(Join-Path $app 'Codex.exe'); Name='Codex.exe'; CommandLine='Codex.exe' }) }
    $found = Get-CodexInfo
    Assert ($found.Found -and $found.AppDirectory -eq $app) 'Discover running custom installation'
    $CodexPath = Join-Path $app 'Codex.exe'
    Assert ((Get-CodexInfo).AppDirectory -eq $app) 'Explicit executable must resolve to app folder'
    $CodexPath = $root
    $failed = $false
    try { Get-CodexInfo | Out-Null } catch { $failed = $true }
    Assert $failed 'Invalid explicit path must not silently select another app'
    Write-Host '[PASS] custom running installation, explicit executable path, invalid-path rejection'
} finally {
    $env:CODEX_DESKTOP_PATH = $oldDesktop; $env:CODEX_ZH_CN_PATH = $oldChinese
    $resolved = [IO.Path]::GetFullPath($root)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-discovery-[0-9a-f]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
