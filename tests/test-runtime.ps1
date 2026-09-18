#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-runtime-' + [guid]::NewGuid().ToString('N'))
$appDirectory = ''
try {
    . (Join-Path $PSScriptRoot '..\scripts\install_windows.ps1') -CodexHome $root -NoRestart
    $source = Get-CodexInfo
    $copy = New-CompatibilityCopy $source
    $appDirectory = $copy.AppDirectory
    Set-DesktopLocale 'zh-CN'
    function Get-ShortcutFolders { @((Join-Path $root 'desktop'), (Join-Path $root 'programs')) }
    Publish-CompatibilityLauncher $copy
    $launcher = Join-Path $toolStateRoot 'launcher\start-zh.ps1'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $launcher -NoPopup
    if ($LASTEXITCODE -ne 0) { throw 'Persistent launcher failed with official Codex running' }
    Start-Sleep -Seconds 10
    $running = @(Get-CodexProcesses $copy.AppDirectory | Where-Object { $_.CommandLine -notmatch '--type=' })
    if ($running.Count -eq 0) { throw '隔离兼容副本未持续运行' }
    if (-not (Test-Path -LiteralPath $copy.UserDataPath)) { throw '测试应用未使用隔离的 Electron 数据目录' }
    if ((Get-DesktopLocale) -ne 'zh-CN') { throw '启动后语言配置被覆盖' }
    $first = Get-Content -LiteralPath (Join-Path $toolStateRoot 'last-launch.json') -Raw | ConvertFrom-Json
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $launcher -NoPopup
    if ($LASTEXITCODE -ne 0) { throw 'Repeated launcher failed' }
    $second = Get-Content -LiteralPath (Join-Path $toolStateRoot 'last-launch.json') -Raw | ConvertFrom-Json
    if ($second.result -ne 'reused-current' -or $first.processId -ne $second.processId) { throw 'Repeated launcher must reuse the original main process' }
    Write-Host '[PASS] real persistent launcher starts alongside official app, repeated open reuses main process, isolated data and locale persist'
} finally {
    if ($appDirectory) { Stop-Codex $appDirectory }
    $resolved = [IO.Path]::GetFullPath($root)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-runtime-[0-9a-f]{32}$') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
