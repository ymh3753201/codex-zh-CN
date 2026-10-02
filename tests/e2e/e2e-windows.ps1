#Requires -Version 5.1
<#
  真实端到端验证：安装官方 MSIX → 运行真实安装器（不打桩）→ 启动中文副本 →
  用 Chrome DevTools 协议读取窗口语言并截图 → 官方程序作英文对照 → 恢复英文。
  需要：可交互桌面会话（GitHub windows-2022 / windows-2025 托管运行器满足），Node 22+。
#>
param(
    [Parameter(Mandatory)] [string]$MsixPath,
    [string]$OutDir = (Join-Path (Get-Location) 'e2e-output'),
    [int]$ZhPort = 9333,
    [int]$OfficialPort = 9334,
    [switch]$SkipControl
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$check = Join-Path $PSScriptRoot 'cdp-check.mjs'
[void][IO.Directory]::CreateDirectory($OutDir)
$summary = [ordered]@{ os = ''; build = 0; msix = (Split-Path -Leaf $MsixPath); steps = [ordered]@{} }
function Step([string]$Name, [scriptblock]$Body) {
    Write-Host "==== $Name" -ForegroundColor Cyan
    $started = Get-Date
    try { & $Body; $summary.steps[$Name] = "pass ($([int]((Get-Date) - $started).TotalSeconds)s)" }
    catch { $summary.steps[$Name] = 'FAIL: ' + $_.Exception.Message; throw }
}
function Stop-Tree([string]$Directory) {
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($Directory, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $summary.os = $os.Caption; $summary.build = [int]$os.BuildNumber
    Write-Host "OS: $($os.Caption) $($os.Version)  PS: $($PSVersionTable.PSVersion)  ACP: $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP)"

    Step 'install-msix' {
        if (-not (Get-AppxPackage -Name 'OpenAI.Codex')) {
            # Store-signed package: trusted by default, no developer mode needed.
            Add-AppxPackage -Path $MsixPath -ForceApplicationShutdown
        }
        $pkg = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
        if (-not $pkg) { throw 'MSIX installation did not register OpenAI.Codex' }
        $summary.codexVersion = "$($pkg.Version)"
        Write-Host "Installed $($pkg.PackageFullName) at $($pkg.InstallLocation)"
    }

    Step 'status-before' {
        $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts\install_windows.ps1') -Action status -Json
        if ($LASTEXITCODE -ne 0) { throw 'Status command failed' }
        $json | Set-Content -LiteralPath (Join-Path $OutDir 'status-before.json') -Encoding UTF8
        $s = $json | ConvertFrom-Json
        if (-not $s.codexFound -or -not $s.officialZhResources) { throw "Status before install not ready: $json" }
        $summary.translationGatePresent = $s.translationGatePresent
    }

    Step 'real-install' {
        # Real entry point, real robocopy and patch; no restart so the test controls launch flags.
        & cmd.exe /c "`"$repo\install-windows.bat`"" 2>&1 | Tee-Object -FilePath (Join-Path $OutDir 'install-output.txt') | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Real BAT installer failed' }
        $state = Join-Path $env:USERPROFILE '.codex\zh-cn-tool\active-copy.json'
        if (-not (Test-Path -LiteralPath $state)) { throw 'Installer did not publish active-copy.json' }
        $script:copy = Get-Content -LiteralPath $state -Raw -Encoding UTF8 | ConvertFrom-Json
        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Codex ' + [string][char]0x4E2D + [char]0x6587 + [char]0x7248 + '.lnk')
        if (-not (Test-Path -LiteralPath $lnk)) { throw "Chinese shortcut missing: $lnk" }
    }

    Step 'status-after' {
        $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts\install_windows.ps1') -Action status -Json
        if ($LASTEXITCODE -ne 0) { throw 'Status command failed' }
        $json | Set-Content -LiteralPath (Join-Path $OutDir 'status-after.json') -Encoding UTF8
        $s = $json | ConvertFrom-Json
        if (-not $s.localizationReady) { throw "localizationReady=false after install: $json" }
    }

    Step 'zh-copy-ui' {
        Stop-Tree $copy.AppDirectory
        $env:CODEX_ELECTRON_USER_DATA_PATH = $copy.UserDataPath
        Start-Process -FilePath $copy.Executable -WorkingDirectory $copy.AppDirectory -ArgumentList @("--user-data-dir=`"$($copy.UserDataPath)`"", "--remote-debugging-port=$ZhPort")
        Remove-Item Env:\CODEX_ELECTRON_USER_DATA_PATH
        & node $check $ZhPort (Join-Path $OutDir 'zh-copy') zh
        if ($LASTEXITCODE -ne 0) { throw 'Chinese copy did not render a Chinese UI' }
        Stop-Tree $copy.AppDirectory
    }

    if (-not $SkipControl) {
        Step 'official-control-ui' {
            # Same config (localeOverride=zh-CN), official unpatched binary: shows whether the gate blocks Chinese.
            $pkg = Get-AppxPackage -Name 'OpenAI.Codex' | Select-Object -First 1
            $exe = Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'
            $data = Join-Path $env:TEMP 'codex-official-control'
            Start-Process -FilePath $exe -ArgumentList @("--user-data-dir=`"$data`"", "--remote-debugging-port=$OfficialPort")
            & node $check $OfficialPort (Join-Path $OutDir 'official') any
            if ($LASTEXITCODE -ne 0) { throw 'Official control UI check failed' }
            Stop-Tree (Join-Path $pkg.InstallLocation 'app')
        }
    }

    Step 'uninstall' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts\install_windows.ps1') -Action uninstall -NoRestart
        if ($LASTEXITCODE -ne 0) { throw 'uninstall failed' }
        $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Codex ' + [string][char]0x4E2D + [char]0x6587 + [char]0x7248 + '.lnk')
        if (Test-Path -LiteralPath $lnk) { throw 'Chinese shortcut still present after uninstall' }
        $cfg = [IO.File]::ReadAllText((Join-Path $env:USERPROFILE '.codex\config.toml'))
        if ($cfg -notmatch 'localeOverride = "en-US"') { throw 'Locale not restored to en-US' }
    }
    $summary.result = 'pass'
} catch {
    $summary.result = 'FAIL'
    $summary.error = $_.Exception.Message
    throw
} finally {
    Get-ChildItem -Path (Join-Path $repo 'diagnostics') -Filter *.json -ErrorAction SilentlyContinue | Copy-Item -Destination $OutDir -ErrorAction SilentlyContinue
    ($summary | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $OutDir 'summary.json') -Encoding UTF8
    $summary | ConvertTo-Json -Depth 5 | Out-Host
}
