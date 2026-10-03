#Requires -Version 5.1
param(
    [string]$Version = '',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$releaseJson = Get-Content -LiteralPath (Join-Path $projectRoot 'resources\release.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $releaseJson.release }
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $projectRoot 'dist' }
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') { throw '版本格式不正确' }
if ($Version -ne $releaseJson.release) { throw '发布版本必须与 resources/release.json 一致' }
$folderName = "codex-zh-CN-v$Version"
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) $folderName
$zipPath = Join-Path $OutputDir "$folderName.zip"
$files = @(
    'install-windows.bat',
    'install-fallback.vbs',
    'uninstall-codex.bat',
    'check-status.bat',
    '一键汉化.bat',
    '一键安装.bat',
    '修复启动.bat',
    '恢复英文.bat',
    '检查状态.bat',
    'README.md',
    'LICENSE',
    "RELEASE_NOTES_v$Version.md",
    'RELEASE_NOTES_v0.3.1.md',
    'RELEASE_NOTES_v0.3.2.md',
    'RELEASE_NOTES_v0.3.3.md',
    'RELEASE_NOTES_v0.3.4.md',
    'resources\release.json',
    'resources\bundled-plugins-zh-CN.json',
    'scripts\install_windows.ps1',
    'scripts\bootstrap.ps1',
    'scripts\run-installer.bat',
    'scripts\locale-compat.ps1',
    'scripts\console-mode.ps1',
    'scripts\start-zh.ps1',
    'docs\diagnosis-v0.3.0.md',
    'docs\student-report-review-2026-10-03.md'
)

if (Test-Path -LiteralPath $stageRoot) {
    $resolvedStage = [System.IO.Path]::GetFullPath($stageRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $resolvedStage.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedStage) -ne $folderName) {
        throw "拒绝清理异常的临时目录：$resolvedStage"
    }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

try {
    foreach ($relative in $files) {
        $source = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "发布文件缺失：$source"
        }
        $target = Join-Path $stageRoot $relative
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $zipPath)
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}

Write-Host "[成功] 发布包：$zipPath"
Write-Host "[信息] 版本：v$Version"
