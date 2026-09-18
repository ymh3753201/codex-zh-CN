#Requires -Version 5.1
param([string]$InstallerPath = '')
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    Join-Path $projectRoot 'scripts\install_windows.ps1'
} else {
    [System.IO.Path]::GetFullPath($InstallerPath)
}
$package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop |
    Sort-Object { [version]$_.Version } -Descending |
    Select-Object -First 1
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-zh-cn-test-' + [guid]::NewGuid().ToString('N'))
$pluginDir = Join-Path $testRoot 'plugins\cache\openai-bundled\browser\test\.codex-plugin'
$configPath = Join-Path $testRoot 'config.toml'
$pluginPath = Join-Path $pluginDir 'plugin.json'
$installerRoot = Split-Path -Parent (Split-Path -Parent $installer)
$translations = Get-Content -LiteralPath (Join-Path $installerRoot 'resources\bundled-plugins-zh-CN.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "断言失败：$Message" }
}

try {
    New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $configPath,
        "[general]`r`nvalue = 1`r`n`r`n[desktop]`r`nappearanceTheme = `"dark`"`r`n`r`n[after]`r`nvalue = 2`r`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
    $fixture = [pscustomobject]@{ name = 'browser'; interface = $translations.browser.source }
    [System.IO.File]::WriteAllText($pluginPath, ($fixture | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action install -CodexPath $package.InstallLocation -CodexHome $testRoot -NoRestart -Mode builtin
    Assert-True ($LASTEXITCODE -eq 0) '安装命令应成功'

    $config = [System.IO.File]::ReadAllText($configPath)
    Assert-True ($config -match '(?m)^localeOverride = "zh-CN"\r?$') '应写入中文语言'
    Assert-True ($config -match '(?m)^\[after\]\r?$') '不应破坏后续 TOML 配置段'
    $plugin = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($plugin.interface.displayName -eq '浏览器') '应汉化插件名称'
    Assert-True ($plugin.interface.longDescription -eq $translations.browser.translation.longDescription) '应完整汉化插件说明'

    $statusRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action status -CodexPath $package.InstallLocation -CodexHome $testRoot -Json
    Assert-True ($LASTEXITCODE -eq 0) '状态命令应成功'
    $status = $statusRaw | ConvertFrom-Json
    Assert-True ($status.localeZhCn -eq $true) '状态应识别中文'
    Assert-True ($status.officialZhResources -eq $true) '应识别官方中文资源'
    Assert-True ($status.pluginsLocalized -eq 1) '状态应识别插件翻译'
    Assert-True ($status.pluginsTotal -eq 1) '隔离目录中只应识别一个受支持插件文件'
    Assert-True ($status.pluginsChangedByCodex -eq 0) '匹配版本不应误报插件变化'

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action install -CodexPath $package.InstallLocation -CodexHome $testRoot -NoRestart -Mode builtin
    Assert-True ($LASTEXITCODE -eq 0) '重复安装应成功且不破坏文件'

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action uninstall -CodexPath $package.InstallLocation -CodexHome $testRoot -NoRestart -Mode builtin
    Assert-True ($LASTEXITCODE -eq 0) '恢复英文命令应成功'

    $config = [System.IO.File]::ReadAllText($configPath)
    Assert-True ($config -match '(?m)^localeOverride = "en-US"\r?$') '应恢复英文语言'
    $plugin = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($plugin.interface.displayName -eq 'Browser') '应恢复插件原文'

    $plugin.interface.shortDescription = 'Official text changed after an update'
    [System.IO.File]::WriteAllText($pluginPath, ($plugin | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action install -CodexPath $package.InstallLocation -CodexHome $testRoot -NoRestart -Mode builtin
    Assert-True ($LASTEXITCODE -eq 0) '遇到新版插件说明时应安全跳过而不是失败'
    $plugin = Get-Content -LiteralPath $pluginPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($plugin.interface.displayName -eq 'Browser') '官方说明变化后不应套用旧翻译'
    $statusRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action status -CodexPath $package.InstallLocation -CodexHome $testRoot -Json
    $status = $statusRaw | ConvertFrom-Json
    Assert-True ($status.pluginsChangedByCodex -eq 1) '状态应提示官方插件说明已变化'

    $badApp = Join-Path $testRoot 'unsupported-app'
    $badHome = Join-Path $testRoot 'unsupported-home'
    New-Item -ItemType Directory -Path (Join-Path $badApp 'resources') -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $badApp 'ChatGPT.exe'), [byte[]](0))
    [System.IO.File]::WriteAllBytes((Join-Path $badApp 'resources\app.asar'), [byte[]](1, 2, 3, 4))
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Action install -CodexPath $badApp -CodexHome $badHome -NoRestart -Mode builtin -SkipPlugins
    Assert-True ($LASTEXITCODE -eq 1) '缺少官方中文资源时应拒绝安装'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $badHome 'config.toml'))) '拒绝安装时不应写入配置'

    Write-Host '[PASS] installer compatibility, safety, status and rollback isolation tests'
} finally {
    $tempRoot = [System.IO.Path]::GetFullPath($testRoot)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($tempRoot.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $tempRoot) -like 'codex-zh-cn-test-*' -and
        (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
