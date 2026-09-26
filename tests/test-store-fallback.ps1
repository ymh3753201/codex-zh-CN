#Requires -Version 5.1
# 商店版查找兜底、启动标识降级和磁盘空间预检。只替换系统边界，不调用真实 Appx/Robocopy。
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-store-' + [guid]::NewGuid().ToString('N'))
$oldDesktop = $env:CODEX_DESKTOP_PATH
$oldChinese = $env:CODEX_ZH_CN_PATH
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $store = Join-Path $root 'WindowsApps\OpenAI.Codex_26.917.9434.0_x64__2p2nqsd0c76g0'
    $app = Join-Path $store 'app'
    [void][IO.Directory]::CreateDirectory((Join-Path $app 'resources'))
    [IO.File]::WriteAllText((Join-Path $app 'resources\app.asar'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $app 'ChatGPT.exe'), 'fixture')
    $env:CODEX_DESKTOP_PATH = ''; $env:CODEX_ZH_CN_PATH = ''
    . (Join-Path $PSScriptRoot '..\scripts\install_windows.ps1') -CodexHome (Join-Path $root 'data') -NoRestart

    # 1. Appx 模块加载失败（精简版 Windows 10 / 策略限制）时改读注册表。
    function Get-AppxPackage { throw 'The Appx module could not be loaded.' }
    function Get-ChildItem([string]$LiteralPath) {
        @([pscustomobject]@{ PSChildName = 'OpenAI.Codex_26.917.9434.0_x64__2p2nqsd0c76g0'; PSPath = 'fixture' })
    }
    function Get-ItemProperty { [pscustomobject]@{ PackageRootFolder = $store } }
    function Get-CimInstance { @() }
    $found = Get-CodexInfo
    Assert ($found.Found -and $found.AppDirectory -eq $app) 'Registry fallback must locate the Store app folder'
    Assert ($found.InstallType -eq 'Microsoft Store' -and $found.Version -eq '26.917.9434.0') 'Registry fallback must keep Store version'
    Assert ($found.AppUserModelId -eq 'OpenAI.Codex_2p2nqsd0c76g0!App') 'Registry fallback must build the launch identity'
    Remove-Item Function:\Get-ChildItem

    # 2. 读取清单失败不能阻止安装：兼容副本本来就不通过商店标识启动。
    function Get-AppxPackageManifest { throw 'manifest unavailable' }
    $aumid = Get-PackageAppUserModelId ([pscustomobject]@{ PackageFamilyName = 'OpenAI.Codex_2p2nqsd0c76g0' })
    Assert ($aumid -eq 'OpenAI.Codex_2p2nqsd0c76g0!App') 'Manifest failure must degrade to the audited Application Id'

    # 3. 磁盘不足必须在复制前明确失败。
    $copies = Join-Path $root 'data\zh-cn-tool\copies'
    [void][IO.Directory]::CreateDirectory($copies)
    function Get-DirectorySize { return 1PB }
    $message = ''
    try { Assert-CopySpace $app $copies } catch { $message = $_.Exception.Message }
    Assert ($message -like '*磁盘空间不足*') 'Insufficient disk space must be reported before copying'
    function Get-DirectorySize { return 1KB }
    Assert-CopySpace $app $copies
    Write-Host '[PASS] Store registry fallback, launch identity fallback, disk-space precheck'
} finally {
    $env:CODEX_DESKTOP_PATH = $oldDesktop; $env:CODEX_ZH_CN_PATH = $oldChinese
    $resolved = [IO.Path]::GetFullPath($root)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-store-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
