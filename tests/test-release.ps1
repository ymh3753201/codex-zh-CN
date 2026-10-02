#Requires -Version 5.1
param([switch]$HeadlessRunner, [switch]$SkipInstalledAppTests)
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'resources\release.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json).release
$zipPath = Join-Path $projectRoot "dist\codex-zh-CN-v$version.zip"
$testDir = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-zh-cn-release-test-' + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $testDir -Force
    $installer = Join-Path $testDir 'scripts\install_windows.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-launcher.ps1') -LauncherPath (Join-Path $testDir 'scripts\start-zh.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Packaged launcher tests failed' }
    # Verify the actual archive against its source, including documents and entry points.
    foreach ($file in @(Get-ChildItem -LiteralPath $testDir -Recurse -File)) {
        $relative = $file.FullName.Substring($testDir.Length).TrimStart('\')
        $source = Join-Path $projectRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
            (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $source).Hash) {
            throw "发布包文件与源码不一致：$relative"
        }
    }
    foreach ($name in @('install_windows.ps1','locale-compat.ps1','start-zh.ps1','console-mode.ps1','bootstrap.ps1')) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $testDir ('scripts\' + $name)))
        if (($bytes[0..2] -join ',') -ne '239,187,191') { throw "Windows PowerShell 中文编码缺失：$name" }
    }
    foreach ($name in @('install-fallback.vbs', 'scripts\bootstrap.ps1', 'scripts\run-installer.bat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $testDir $name) -PathType Leaf)) { throw "发布包缺少启动文件：$name" }
    }
    $bootstrapArguments = @('-PackageRoot', $testDir)
    if ($HeadlessRunner) { $bootstrapArguments += '-HeadlessRunner' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-bootstrap.ps1') @bootstrapArguments
    if ($LASTEXITCODE -ne 0) { throw 'Packaged bootstrap failure tests failed' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-unattended.ps1') -PackageRoot $testDir -SkipDelayTests
    if ($LASTEXITCODE -ne 0) { throw '发布包无人值守入口测试失败' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-workflow.ps1') -InstallerPath $installer
    if ($LASTEXITCODE -ne 0) { throw '发布包默认兼容模式测试失败' }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-workflow.ps1') -InstallerPath $installer -LegacyLongPaths
    if ($LASTEXITCODE -ne 0) { throw 'Packaged legacy long-path workflow failed' }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-copy-failures.ps1') -InstallerPath $installer
    if ($LASTEXITCODE -ne 0) { throw 'Packaged copy failure tests failed' }
    if ($SkipInstalledAppTests) {
        Write-Host '[SKIP] real installed Codex isolation test; this runner has no audited Codex installation'
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-installer.ps1') `
            -InstallerPath $installer
        if ($LASTEXITCODE -ne 0) { throw "发布包隔离测试失败，退出码：$LASTEXITCODE" }
    }
    Write-Host '[PASS] packaged release isolation test'
} finally {
    $resolved = [System.IO.Path]::GetFullPath($testDir)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved) -like 'codex-zh-cn-release-test-*' -and
        (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
