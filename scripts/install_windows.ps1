#Requires -Version 5.1
<#
.SYNOPSIS
  Codex Desktop 简体中文一键启用器（Windows）。

.DESCRIPTION
  新版 Codex 已内置简体中文资源。本脚本只启用内置中文，并补充本地插件名称翻译；
  不修改 WindowsApps，不下载文件，也不要求安装 Node.js。
#>
[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall', 'status', 'repair-launcher')]
    [string]$Action = 'install',
    [string]$CodexPath = '',
    [string]$CodexHome = '',
    [ValidateSet('auto', 'builtin', 'compat')]
    [string]$Mode = 'auto',
    [switch]$NoRestart,
    [switch]$SkipPlugins,
    [switch]$Json,
    [string]$ReportPath = '',
    [switch]$AutoClose,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
# A caller running PowerShell 7 can pass its incompatible module directories to
# Windows PowerShell 5.1 through Python/CMD. Prefer this host's built-in modules.
if ($PSVersionTable.PSVersion.Major -eq 5) {
    $env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
}
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$scriptDir = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDir
$translationPath = Join-Path $projectRoot 'resources\bundled-plugins-zh-CN.json'
$releasePath = Join-Path $projectRoot 'resources\release.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $scriptDir 'locale-compat.ps1')
. (Join-Path $scriptDir 'console-mode.ps1')
$toolVersion = '开发版'
if (Test-Path -LiteralPath $releasePath) {
    try { $toolVersion = (Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json).release } catch {}
}

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
}
$CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$toolStateRoot = Join-Path $CodexHome 'zh-cn-tool'
$pluginBackupRoot = Join-Path $toolStateRoot 'backups\plugins'

function Write-Title {
    Write-Host ''
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host "  Codex Desktop 简体中文一键启用器 v$toolVersion" -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan
}

function Write-Ok([string]$Message) { Write-Host "  [成功] $Message" -ForegroundColor Green }
function Write-InfoLine([string]$Message) { Write-Host "  [信息] $Message" -ForegroundColor Gray }
function Write-WarnLine([string]$Message) { Write-Host "  [注意] $Message" -ForegroundColor Yellow }

function Write-TextFile([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $tempPath = Join-Path $parent ('.' + (Split-Path -Leaf $Path) + '.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tempPath, $Content, $utf8NoBom)
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tempPath, $Path, $null, $true)
            } catch {
                Move-Item -LiteralPath $tempPath -Destination $Path -Force
            }
        } else {
            Move-Item -LiteralPath $tempPath -Destination $Path
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

function Resolve-CodexAppDirectory([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    $candidate = $PathValue.Trim().Trim('"')
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidate = Split-Path -Parent $candidate
    }
    foreach ($dir in @($candidate, (Join-Path $candidate 'app'))) {
        if ((Test-Path -LiteralPath (Join-Path $dir 'resources\app.asar')) -and
            ((Test-Path -LiteralPath (Join-Path $dir 'ChatGPT.exe')) -or
             (Test-Path -LiteralPath (Join-Path $dir 'Codex.exe')) -or
             (Test-Path -LiteralPath (Join-Path $dir 'codex.exe')))) {
            return [System.IO.Path]::GetFullPath($dir)
        }
    }
    return $null
}

function Find-CodexExecutable([string]$AppDirectory) {
    foreach ($name in @('ChatGPT.exe', 'Codex.exe', 'codex.exe')) {
        $candidate = Join-Path $AppDirectory $name
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Get-ExecutableVersion([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue) -or -not (Test-Path -LiteralPath $PathValue)) { return '未知' }
    try { $item = Get-Item -LiteralPath $PathValue; return "$($item.VersionInfo.ProductVersion)" } catch { return '未知' }
}

function Get-PackageAppUserModelId($Package) {
    try {
        $applicationId = $Package |
            Get-AppxPackageManifest |
            Select-Object -ExpandProperty Package |
            Select-Object -ExpandProperty Applications |
            Select-Object -ExpandProperty Application |
            Where-Object { $_.Executable -match '(?i)(ChatGPT|Codex)\.exe$' } |
            Select-Object -First 1 -ExpandProperty Id
        if ($applicationId) { return "$($Package.PackageFamilyName)!$applicationId" }
    } catch {}
    throw '无法读取应用启动标识，请先修复 Codex 安装。'
}

function Get-OfficialZhResourceStatus([string]$AppDirectory) {
    $asarPath = Join-Path $AppDirectory 'resources\app.asar'
    $result = [ordered]@{
        AsarReadable = $false
        NativeMenuZhCn = $false
        WebviewZhCn = $false
        LocaleOverrideSupported = $false
        NativeIntlSupported = $false
        Complete = $false
        Error = ''
    }
    if (-not (Test-Path -LiteralPath $asarPath -PathType Leaf)) {
        $result.Error = '缺少 resources\app.asar'
        return [pscustomobject]$result
    }

    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream(
            $asarPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        $prefix = New-Object byte[] 8
        if ($stream.Read($prefix, 0, 8) -ne 8 -or [BitConverter]::ToUInt32($prefix, 0) -ne 4) {
            throw 'app.asar 文件头格式不受支持'
        }
        $headerSize = [BitConverter]::ToUInt32($prefix, 4)
        if ($headerSize -lt 8 -or $headerSize -gt 67108864) {
            throw "app.asar 文件头大小异常：$headerSize"
        }
        $pickle = New-Object byte[] $headerSize
        $read = 0
        while ($read -lt $headerSize) {
            $count = $stream.Read($pickle, $read, $headerSize - $read)
            if ($count -le 0) { throw 'app.asar 文件头读取不完整' }
            $read += $count
        }
        $stringSize = [BitConverter]::ToInt32($pickle, 4)
        if ($stringSize -le 0 -or $stringSize -gt ($headerSize - 8)) {
            throw "app.asar JSON 文件头大小异常：$stringSize"
        }
        $headerText = [System.Text.Encoding]::UTF8.GetString($pickle, 8, $stringSize)
        $result.AsarReadable = $true
        $header = $headerText | ConvertFrom-Json
        $nativeEntry = $header.files.PSObject.Properties['native-menu-locales'].Value.files.PSObject.Properties['zh-CN.json']
        $result.NativeMenuZhCn = [bool]($nativeEntry -and $nativeEntry.Value.size -gt 0)
        $webEntries = @($header.files.webview.files.assets.files.PSObject.Properties | Where-Object { $_.Name -match '^zh-CN-[^/]+\.js$' -and $_.Value.size -gt 0 })
        $result.WebviewZhCn = $webEntries.Count -gt 0
        $vite = $header.files.PSObject.Properties['.vite'].Value
        $build = $vite.files.PSObject.Properties['build'].Value
        $mainProperty = $build.files.PSObject.Properties |
            Where-Object { $_.Name -match '^main-[^/]+\.js$' } |
            Select-Object -First 1
        if ($mainProperty) {
            $mainSize = [long]$mainProperty.Value.size
            $mainOffset = [long]$mainProperty.Value.offset
            if ($mainSize -gt 0 -and $mainSize -le 67108864) {
                [void]$stream.Seek((8L + [long]$headerSize + $mainOffset), [System.IO.SeekOrigin]::Begin)
                $mainBytes = New-Object byte[] $mainSize
                $mainRead = 0
                while ($mainRead -lt $mainSize) {
                    $count = $stream.Read($mainBytes, $mainRead, $mainSize - $mainRead)
                    if ($count -le 0) { throw 'Codex 主程序读取不完整' }
                    $mainRead += $count
                }
                $mainText = [System.Text.Encoding]::UTF8.GetString($mainBytes)
                $result.LocaleOverrideSupported = $mainText.Contains('localeOverride')
                $result.NativeIntlSupported = $mainText.Contains('nativeIntl')
            }
        }
        $result.Complete =
            $result.NativeMenuZhCn -and
            $result.WebviewZhCn -and
            $result.LocaleOverrideSupported -and
            $result.NativeIntlSupported
    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        if ($stream) { $stream.Dispose() }
    }
    return [pscustomobject]$result
}

function Get-CodexInfo {
    # An explicit path or environment override always wins over Store detection.
    if ([string]::IsNullOrWhiteSpace($CodexPath)) {
        foreach ($value in @($env:CODEX_DESKTOP_PATH, $env:CODEX_ZH_CN_PATH)) {
            if (-not [string]::IsNullOrWhiteSpace($value)) { $CodexPath = $value; break }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($CodexPath)) {
        $appDir = Resolve-CodexAppDirectory $CodexPath
        if (-not $appDir) {
            throw "指定的目录不是有效的 Codex 安装目录：$CodexPath"
        }
        $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
            Where-Object { Test-PathWithin $appDir $_.InstallLocation } |
            Select-Object -First 1
        return [pscustomobject]@{
            Found = $true
            AppDirectory = $appDir
            Executable = Find-CodexExecutable $appDir
            ExecutableVersion = Get-ExecutableVersion (Find-CodexExecutable $appDir)
            InstallType = if ($package) { 'Microsoft Store' } else { '便携版' }
            Version = if ($package) { "$($package.Version)" } else { '未知' }
            AppUserModelId = if ($package) { Get-PackageAppUserModelId $package } else { '' }
        }
    }

    $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Version } -Descending |
        Select-Object -First 1
    if ($package) {
        $appDir = Resolve-CodexAppDirectory $package.InstallLocation
        if ($appDir) {
            return [pscustomobject]@{
                Found = $true
                AppDirectory = $appDir
                Executable = Find-CodexExecutable $appDir
                ExecutableVersion = Get-ExecutableVersion (Find-CodexExecutable $appDir)
                InstallType = 'Microsoft Store'
                Version = "$($package.Version)"
                AppUserModelId = Get-PackageAppUserModelId $package
            }
        }
    }

    # Portable and custom installations may live anywhere. If one is already
    # running, its executable gives us an exact path without scanning drives.
    try {
        $sessionId = (Get-Process -Id $PID).SessionId
        $runningDirectories = @(Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.SessionId -eq $sessionId -and $_.ExecutablePath -and
                $_.Name -match '^(?i:ChatGPT|Codex)\.exe$' -and
                $_.CommandLine -notmatch '(?:^|\s)--type(?:=|\s)' -and
                -not (Test-IsLegacyCompatibilityPath $_.ExecutablePath)
            } |
            ForEach-Object { Split-Path -Parent $_.ExecutablePath } |
            Sort-Object -Unique)
        foreach ($candidate in $runningDirectories) {
            if (Test-PathWithin $candidate $toolStateRoot) { continue }
            $appDir = Resolve-CodexAppDirectory $candidate
            if ($appDir -and (Get-OfficialZhResourceStatus $appDir).Complete) {
                return [pscustomobject]@{
                    Found = $true
                    AppDirectory = $appDir
                    Executable = Find-CodexExecutable $appDir
                    ExecutableVersion = Get-ExecutableVersion (Find-CodexExecutable $appDir)
                    InstallType = '自定义安装'
                    Version = '未知'
                    AppUserModelId = ''
                }
            }
        }
    } catch {}

    $commonPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Codex'),
        (Join-Path $env:LOCALAPPDATA 'Codex'),
        (Join-Path $env:ProgramFiles 'Codex')
    )
    foreach ($candidate in $commonPaths) {
        $appDir = Resolve-CodexAppDirectory $candidate
        if ($appDir) {
            return [pscustomobject]@{
                Found = $true
                AppDirectory = $appDir
                Executable = Find-CodexExecutable $appDir
                ExecutableVersion = Get-ExecutableVersion (Find-CodexExecutable $appDir)
                InstallType = '便携版'
                Version = '未知'
                AppUserModelId = ''
            }
        }
    }

    return [pscustomobject]@{
        Found = $false
        AppDirectory = ''
        Executable = ''
        ExecutableVersion = '未知'
        InstallType = ''
        Version = ''
        AppUserModelId = ''
    }
}

function Get-DesktopLocale {
    $configPath = Join-Path $CodexHome 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }
    $section = ''
    foreach ($line in (Get-TomlStructuralLines ([System.IO.File]::ReadAllLines($configPath)))) {
        if ($line -match '^\s*\[\[') { $section = ''; continue }
        if ($line -match '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
            $section = $Matches[1]
            continue
        }
        if ($section -eq 'desktop' -and $line -match '^\s*localeOverride\s*=\s*["'']([^"'']+)["'']') {
            return $Matches[1]
        }
    }
    return $null
}

function Get-WindowsInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $build = 0
        [void][int]::TryParse([string]$os.BuildNumber, [ref]$build)
        return [pscustomobject]@{ Caption = "$($os.Caption)"; Version = "$($os.Version)"; Build = $build; Architecture = "$($os.OSArchitecture)"; SupportedForCodex = ($build -ge 19041) }
    } catch {
        return [pscustomobject]@{ Caption = '未知 Windows'; Version = ''; Build = 0; Architecture = ''; SupportedForCodex = $false }
    }
}

function Set-DesktopLocale([string]$Locale) {
    $configPath = Join-Path $CodexHome 'config.toml'
    if (-not (Test-Path -LiteralPath $CodexHome)) {
        New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $configPath) {
        foreach ($line in [System.IO.File]::ReadAllLines($configPath)) { [void]$lines.Add($line) }
    }

    $desktopStart = -1
    $desktopEnd = $lines.Count
    $structural = @(Get-TomlStructuralLines $lines.ToArray())
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($structural[$i] -match '^\s*\[\[' -and $desktopStart -ge 0) { $desktopEnd = $i; break }
        if ($structural[$i] -match '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
            if ($Matches[1] -eq 'desktop' -and $desktopStart -lt 0) {
                $desktopStart = $i
            } elseif ($desktopStart -ge 0) {
                $desktopEnd = $i
                break
            }
        }
    }

    $newLine = "localeOverride = `"$Locale`""
    if ($desktopStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') { [void]$lines.Add('') }
        [void]$lines.Add('[desktop]')
        [void]$lines.Add($newLine)
    } else {
        $localeIndex = -1
        for ($i = $desktopStart + 1; $i -lt $desktopEnd; $i++) {
            if ($structural[$i] -match '^\s*localeOverride\s*=') {
                $localeIndex = $i
                break
            }
        }
        if ($localeIndex -ge 0) {
            $lines[$localeIndex] = $newLine
        } else {
            $lines.Insert($desktopStart + 1, $newLine)
        }
    }

    # Reject complex TOML instead of silently inserting a second or ineffective key.
    $original = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
    $structuralText = $structural -join "`n"
    if ($structuralText -match '(?m)^\s*(?:["'']?desktop["'']?\s*[.=]|\[\s*["'']desktop["'']\s*\])') {
        throw '配置使用了内联、点分或带引号的 desktop 段。为保护配置，请先将它改为普通 [desktop] 段，或在 Codex 设置中修改语言。'
    }
    if ([regex]::Matches($structuralText, '(?m)^\s*\[desktop\]\s*$').Count -gt 1) { throw '配置存在重复的 desktop 段，请先修复配置。' }
    if ($desktopStart -ge 0) {
        $sectionLines = @($structural | Select-Object -Skip ($desktopStart + 1) -First ($desktopEnd - $desktopStart - 1)) -join "`n"
        if ([regex]::Matches($sectionLines, '(?m)^\s*localeOverride\s*=').Count -gt 1 -or
            $sectionLines -match '(?m)^\s*["'']localeOverride["'']\s*=') { throw '语言设置存在重复或带引号的键，请先在 Codex 设置中修改。' }
    }
    if (Test-Path -LiteralPath $configPath) {
        $backupDir = Join-Path $toolStateRoot 'backups\config'
        [void][IO.Directory]::CreateDirectory($backupDir)
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.toml'))
    }
    Write-TextFile $configPath (($lines -join "`r`n") + "`r`n")
    if ((Get-DesktopLocale) -ne $Locale) { throw '语言设置写入后验证失败' }
}

function Get-PluginFiles {
    $roots = @(
        (Join-Path $CodexHome 'plugins\cache\openai-bundled'),
        (Join-Path $CodexHome 'plugins\cache\openai-primary-runtime'),
        (Join-Path $CodexHome '.tmp\bundled-marketplaces\openai-bundled\plugins')
    )
    $files = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $files += Get-ChildItem -LiteralPath $root -Filter 'plugin.json' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\.codex-plugin\\plugin\.json$' }
    }
    return @($files | Sort-Object FullName -Unique)
}

function Get-Translations {
    if (-not (Test-Path -LiteralPath $translationPath)) {
        throw "缺少离线翻译文件：$translationPath"
    }
    return (Get-Content -LiteralPath $translationPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-ObjectPropertiesEqual($Actual, $Expected) {
    if ($null -eq $Actual -or $null -eq $Expected) { return $false }
    foreach ($property in $Expected.PSObject.Properties) {
        $current = $Actual.PSObject.Properties[$property.Name]
        if (-not $current) { return $false }
        $currentJson = $current.Value | ConvertTo-Json -Compress -Depth 20
        $expectedJson = $property.Value | ConvertTo-Json -Compress -Depth 20
        if ($currentJson -cne $expectedJson) { return $false }
    }
    return $true
}

function Backup-PluginFile([string]$FilePath) {
    $relative = $FilePath.Substring($CodexHome.Length).TrimStart('\')
    $backupPath = Join-Path $pluginBackupRoot $relative
    $parent = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # 调用本函数前已确认目标是当前版本官方原文，因此可刷新可能过期的旧备份。
    Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force
}

function Install-PluginTranslations {
    $translations = Get-Translations
    $changed = 0
    $supported = 0
    $stale = 0
    foreach ($file in Get-PluginFiles) {
        try {
            $plugin = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $plugin.name -or -not $plugin.interface) { continue }
            $patchProperty = $translations.PSObject.Properties["$($plugin.name)"]
            if (-not $patchProperty) { continue }
            $supported++
            $record = $patchProperty.Value
            if (-not $record.source -or -not $record.translation) { continue }
            if (Test-ObjectPropertiesEqual $plugin.interface $record.translation) {
                continue
            }
            if (-not (Test-ObjectPropertiesEqual $plugin.interface $record.source)) {
                $stale++
                continue
            }
            $patch = $record.translation
            $needsWrite = $false
            foreach ($property in $patch.PSObject.Properties) {
                $current = $plugin.interface.PSObject.Properties[$property.Name]
                $oldJson = if ($current) { $current.Value | ConvertTo-Json -Compress -Depth 20 } else { '' }
                $newJson = $property.Value | ConvertTo-Json -Compress -Depth 20
                if ($oldJson -ne $newJson) {
                    if ($current) {
                        $current.Value = $property.Value
                    } else {
                        $plugin.interface | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
                    }
                    $needsWrite = $true
                }
            }
            if ($needsWrite) {
                Backup-PluginFile $file.FullName
                Write-TextFile $file.FullName (($plugin | ConvertTo-Json -Depth 50) + "`r`n")
                $changed++
            }
        } catch {
            Write-WarnLine "跳过无法读取的插件文件：$($file.FullName)"
        }
    }
    return [pscustomobject]@{ Changed = $changed; Supported = $supported; Stale = $stale }
}

function Restore-PluginTranslations {
    if (-not (Test-Path -LiteralPath $pluginBackupRoot)) {
        return [pscustomobject]@{ Restored = 0; Skipped = 0 }
    }
    $translations = Get-Translations
    $restored = 0
    $skipped = 0
    foreach ($backup in Get-ChildItem -LiteralPath $pluginBackupRoot -Filter 'plugin.json' -File -Recurse) {
        $relative = $backup.FullName.Substring($pluginBackupRoot.Length).TrimStart('\')
        $target = Join-Path $CodexHome $relative
        if (Test-Path -LiteralPath $target) {
            try {
                $plugin = Get-Content -LiteralPath $target -Raw -Encoding UTF8 | ConvertFrom-Json
                $recordProperty = $translations.PSObject.Properties["$($plugin.name)"]
                if ($recordProperty -and
                    (Test-ObjectPropertiesEqual $plugin.interface $recordProperty.Value.translation)) {
                    Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
                    $restored++
                } else {
                    # Codex 可能已更新这个文件；不要用旧备份覆盖新版内容。
                    $skipped++
                }
            } catch {
                $skipped++
            }
        }
    }
    return [pscustomobject]@{ Restored = $restored; Skipped = $skipped }
}

function Get-PluginTranslationStatus {
    $translations = Get-Translations
    $total = 0
    $localized = 0
    $stale = 0
    foreach ($file in Get-PluginFiles) {
        try {
            $plugin = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not $plugin.name -or -not $plugin.interface) { continue }
            $patchProperty = $translations.PSObject.Properties["$($plugin.name)"]
            if (-not $patchProperty) { continue }
            $record = $patchProperty.Value
            if (-not $record.source -or -not $record.translation) { continue }
            if (Test-ObjectPropertiesEqual $plugin.interface $record.translation) {
                $total++
                $localized++
            } elseif (Test-ObjectPropertiesEqual $plugin.interface $record.source) {
                $total++
            } else {
                $stale++
            }
        } catch {}
    }
    return [pscustomobject]@{ Total = $total; Localized = $localized; Stale = $stale }
}

function Get-CodexProcesses([string]$AppDirectory) {
    $all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $sessionId = (Get-Process -Id $PID).SessionId
    return @($all | Where-Object {
        $_.SessionId -eq $sessionId -and $_.ExecutablePath -and
        (Test-PathWithin $_.ExecutablePath $AppDirectory)
    })
}

function Stop-Codex([string]$AppDirectory) {
    $processes = @(Get-CodexProcesses $AppDirectory)
    if ($processes.Count -eq 0) { return }
    Write-InfoLine '正在关闭 Codex，以便中文设置生效……'
    foreach ($process in ($processes | Sort-Object ProcessId -Descending)) {
        try { Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop }
        catch {
            if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) { throw }
        }
    }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (@(Get-CodexProcesses $AppDirectory).Count -eq 0) { return }
        Start-Sleep -Milliseconds 500
    }
    throw 'Codex 进程尚未退出；请关闭 Codex 后重新运行。配置尚未写入。'
}

function Start-Codex($CodexInfo) {
    if ($CodexInfo.AppUserModelId) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($CodexInfo.AppUserModelId)" -WindowStyle Hidden | Out-Null
    } elseif ($CodexInfo.Executable) {
        $previousHome = $env:CODEX_HOME
        $previousUserData = $env:CODEX_ELECTRON_USER_DATA_PATH
        try {
            $env:CODEX_HOME = $CodexHome
            if ($CodexInfo.UserDataPath) {
                $env:CODEX_ELECTRON_USER_DATA_PATH = $CodexInfo.UserDataPath
                Start-Process -FilePath $CodexInfo.Executable -WorkingDirectory $CodexInfo.AppDirectory -WindowStyle Hidden -ArgumentList ('--user-data-dir="' + $CodexInfo.UserDataPath + '"') | Out-Null
            } else {
                Start-Process -FilePath $CodexInfo.Executable -WorkingDirectory $CodexInfo.AppDirectory -WindowStyle Hidden | Out-Null
            }
        } finally { $env:CODEX_HOME = $previousHome; $env:CODEX_ELECTRON_USER_DATA_PATH = $previousUserData }
    } else {
        throw '没有找到可启动的 Codex 程序。'
    }
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 500
        $running = @(Get-CodexProcesses $CodexInfo.AppDirectory | Where-Object { $_.ExecutablePath -eq $CodexInfo.Executable -and $_.CommandLine -notmatch '--type=' })
        if ($running.Count -gt 0) {
            Start-Sleep -Seconds 2
            if (@(Get-CodexProcesses $CodexInfo.AppDirectory | Where-Object { $_.ProcessId -eq $running[0].ProcessId }).Count -gt 0) { return }
        }
    }
    throw '已发送启动请求，但未确认目标 Codex 持续运行。请打开“Codex 中文版”或“检查状态”，不要重复重装。'
}

function Save-DiagnosticReport($Report) {
    $destination = $ReportPath
    if ([string]::IsNullOrWhiteSpace($destination)) {
        $destination = Join-Path $projectRoot ('diagnostics\codex-zh-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    }
    Write-TextFile $destination ($Report | ConvertTo-Json -Depth 10)
    Write-InfoLine "诊断报告已保存：$destination"
}

function Get-StatusReport {
    $codex = Get-CodexInfo
    $windows = Get-WindowsInfo
    $plugins = if ($SkipPlugins) {
        [pscustomobject]@{ Total = 0; Localized = 0; Stale = 0 }
    } else {
        Get-PluginTranslationStatus
    }
    $officialZh = if ($codex.Found) {
        Get-OfficialZhResourceStatus $codex.AppDirectory
    } else {
        [pscustomobject]@{
            AsarReadable = $false
            NativeMenuZhCn = $false
            WebviewZhCn = $false
            LocaleOverrideSupported = $false
            NativeIntlSupported = $false
            Complete = $false
            Error = ''
        }
    }
    $locale = Get-DesktopLocale
    $compatibility = if ($codex.Found) { Get-LocaleCompatibility $codex.AppDirectory } else { $null }
    $activeCopy = Get-ActiveCompatibilityCopy
    $copyCurrent = $false
    $copyPatched = $false
    $copyLauncherReady = $false
    $copyError = ''
    if ($activeCopy) {
        try {
            $copyCurrent = $codex.Found -and
                $activeCopy.SourceDirectory -eq $codex.AppDirectory -and
                (Get-FileHash -LiteralPath (Join-Path $codex.AppDirectory 'resources\app.asar') -Algorithm SHA256).Hash -eq $activeCopy.SourceHash
            $copyPatched = (Get-FileHash -LiteralPath (Join-Path $activeCopy.AppDirectory 'resources\app.asar') -Algorithm SHA256).Hash -eq $activeCopy.PatchedHash -and
                (Get-FileHash -LiteralPath $activeCopy.Executable -Algorithm SHA256).Hash -eq $activeCopy.ExecutableHash -and
                -not (Get-LocaleCompatibility $activeCopy.AppDirectory).Gated
            $launcherPath = Join-Path $toolStateRoot 'launcher\start-zh.ps1'
            $copyLauncherReady = (Test-Path -LiteralPath $launcherPath -PathType Leaf)
        } catch { $copyError = $_.Exception.Message }
    }
    $testedVersion = ''
    $lastLaunch = $null
    $lastLaunchPath = Join-Path $toolStateRoot 'last-launch.json'
    if (Test-Path -LiteralPath $lastLaunchPath) {
        try { $lastLaunch = Get-Content -LiteralPath $lastLaunchPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if (Test-Path -LiteralPath $releasePath) {
        try { $testedVersion = (Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json).testedCodexVersion } catch {}
    }
    return [pscustomobject]@{
        codexFound = [bool]$codex.Found
        codexVersion = $codex.Version
        executableVersion = $codex.ExecutableVersion
        appVersion = if ($compatibility) { $compatibility.AppVersion } else { '' }
        translationGatePresent = [bool]($compatibility -and $compatibility.Gated)
        compatibleCopy = if ($activeCopy) { $activeCopy.AppDirectory } else { '' }
        compatibleCopyCurrent = $copyCurrent
        compatibleCopyPatched = $copyPatched
        compatibleCopyLauncherReady = $copyLauncherReady
        compatibleCopyError = $copyError
        lastLaunch = $lastLaunch
        compatibleCopySourceChanged = [bool]($activeCopy -and -not $copyCurrent)
        runningAppPaths = @((Get-CodexProcesses $codex.AppDirectory).ExecutablePath | Sort-Object -Unique)
        runningCompatiblePaths = if ($activeCopy) { @((Get-CodexProcesses $activeCopy.AppDirectory).ExecutablePath | Sort-Object -Unique) } else { @() }
        uiLanguageVerified = $false
        testedCodexVersion = $testedVersion
        installType = $codex.InstallType
        codexPath = $codex.AppDirectory
        windowsCaption = $windows.Caption
        windowsVersion = $windows.Version
        windowsBuild = $windows.Build
        windowsArchitecture = $windows.Architecture
        windowsBuildSupported = [bool]$windows.SupportedForCodex
        configPath = (Join-Path $CodexHome 'config.toml')
        locale = $locale
        localeZhCn = ($locale -eq 'zh-CN')
        officialZhResources = [bool]$officialZh.Complete
        nativeMenuZhCn = [bool]$officialZh.NativeMenuZhCn
        webviewZhCn = [bool]$officialZh.WebviewZhCn
        localeOverrideSupported = [bool]$officialZh.LocaleOverrideSupported
        nativeIntlSupported = [bool]$officialZh.NativeIntlSupported
        resourceCheckError = $officialZh.Error
        pluginsLocalized = $plugins.Localized
        pluginsTotal = $plugins.Total
        pluginsChangedByCodex = $plugins.Stale
        localizationReady = (($locale -eq 'zh-CN') -and [bool]$codex.Found -and [bool]$officialZh.Complete -and
            (-not $compatibility.Gated -or ($copyCurrent -and $copyPatched -and $copyLauncherReady)))
        ready = ([bool]$codex.Found -and [bool]$officialZh.Complete)
    }
}

function Show-Status($Report) {
    Write-Title
    Write-InfoLine "系统：$($Report.windowsCaption)（版本 $($Report.windowsVersion)，构建 $($Report.windowsBuild)，$($Report.windowsArchitecture)）"
    if (-not $Report.windowsBuildSupported) { Write-WarnLine '本机 Codex 安装包要求 Windows 10 构建 19041 或更新版本；请核对安装包要求。' }
    if ($Report.codexFound) {
        Write-Ok "已找到 Codex $($Report.codexVersion)（$($Report.installType)）"
        Write-InfoLine "实际程序版本：$($Report.executableVersion)"
        Write-InfoLine "关于窗口版本：$($Report.appVersion)（与安装包版本采用不同编号，不代表装错版本）"
        Write-InfoLine "安装位置：$($Report.codexPath)"
    } else {
        Write-WarnLine '没有找到 Codex Desktop。请先安装 Codex，再运行本工具。'
    }
    if ($Report.localeZhCn) { Write-Ok '语言配置：简体中文（不等于已验证当前窗口）' }
    else { Write-WarnLine "界面语言尚未设为中文（当前：$($Report.locale)）" }
    Write-InfoLine "配置文件：$($Report.configPath)"
    if ($Report.translationGatePresent) { Write-WarnLine '官方主界面受翻译加载开关控制，仅写语言配置可能无效。' }
    if ($Report.compatibleCopy -and $Report.compatibleCopyCurrent -and
        $Report.compatibleCopyPatched -and $Report.compatibleCopyLauncherReady) {
        Write-Ok "中文兼容版检查通过：$($Report.compatibleCopy)"
        Write-InfoLine '请从桌面或开始菜单的“Codex 中文版”启动；官方 Codex 图标不会加载兼容补丁。'
    } elseif ($Report.compatibleCopy) {
        Write-WarnLine '现有中文兼容版已过期或不完整，请重新运行一键安装。'
        if ($Report.compatibleCopyError) { Write-WarnLine "副本检查原因：$($Report.compatibleCopyError)" }
    } elseif ($Report.translationGatePresent) {
        Write-WarnLine '尚未准备中文兼容版，请运行一键安装。'
    }
    if ($Report.compatibleCopySourceChanged) { Write-WarnLine 'Codex 已更新或安装位置已变化，请重新运行一键安装更新中文兼容版。' }
    if ($Report.runningAppPaths.Count -gt 0 -and $Report.translationGatePresent) {
        Write-WarnLine '检测到官方 Codex 仍在运行。请使用“Codex 中文版”图标，官方窗口可能仍显示英文。'
    }
    if ($Report.lastLaunch -and $Report.lastLaunch.result -eq 'failed') {
        Write-WarnLine "上次中文启动失败：$($Report.lastLaunch.error)"
    }
    if ($Report.codexFound) {
        if ($Report.officialZhResources) {
            Write-Ok '官方中文资源：主界面和原生菜单均已找到'
        } else {
            Write-WarnLine "未找到完整的官方中文资源；本工具不会强行修改程序包。$($Report.resourceCheckError)"
        }
    }
    if (-not $SkipPlugins) {
        Write-InfoLine "插件中文名称：$($Report.pluginsLocalized)/$($Report.pluginsTotal)"
        if ($Report.pluginsChangedByCodex -gt 0) {
            Write-WarnLine "有 $($Report.pluginsChangedByCodex) 个插件的官方说明已变化，为防止错译已自动跳过。"
        }
    }
    if ($Report.testedCodexVersion -and $Report.codexVersion -and
        $Report.codexVersion -ne '未知' -and $Report.codexVersion -ne $Report.testedCodexVersion) {
        Write-InfoLine "参考测试版本：Codex $($Report.testedCodexVersion)。当前版本不同不代表不兼容，以资源和副本检查结果为准；官方安装目录不会被修改。"
    }
}

function Invoke-Install {
    Write-Title
    Write-InfoLine '[1/5] 正在查找 Codex。安装会自动进行，无需按空格或回车。'
    $codex = Get-CodexInfo
    if (-not $codex.Found) { throw '没有找到 Codex Desktop。请先安装 Codex，再重新运行。' }

    Write-InfoLine '[2/5] 正在检查中文资源，请稍候……'
    $officialZh = Get-OfficialZhResourceStatus $codex.AppDirectory
    if (-not $officialZh.Complete) {
        $details = if ($officialZh.Error) { " 原因：$($officialZh.Error)" } else { '' }
        throw "当前 Codex 安装包中没有检测到完整的官方简体中文资源，本工具已安全停止。$details"
    }

    Write-InfoLine "检测到 Codex $($codex.Version)（$($codex.InstallType)）"
    $compatibility = Get-LocaleCompatibility $codex.AppDirectory
    $useCopy = $Mode -eq 'compat' -or ($Mode -eq 'auto' -and $compatibility.Gated)
    $previousCopy = Get-ActiveCompatibilityCopy
    $launchInfo = $codex
    Write-InfoLine '[3/5] 正在准备中文程序；首次复制可能需要几分钟，无需按键。'
    if ($useCopy) {
        Write-InfoLine '检测到翻译加载开关，正在准备中文兼容副本……'
        $launchInfo = New-CompatibilityCopy $codex
    } elseif ($compatibility.Gated) {
        Write-WarnLine '当前选择仅写配置模式：无法保证主界面翻译加载。建议使用默认模式。'
    }
    if (-not $NoRestart) { Stop-Codex $codex.AppDirectory }
    if ($previousCopy -and -not $NoRestart -and $previousCopy.AppDirectory -ne $launchInfo.AppDirectory) {
        Stop-Codex $previousCopy.AppDirectory
    }
    if ($useCopy -and -not $NoRestart) { Stop-Codex $launchInfo.AppDirectory }
    Write-InfoLine '[4/5] 正在保存中文设置、快捷方式和插件翻译……'
    Set-DesktopLocale 'zh-CN'
    Write-Ok '已写入并回读简体中文语言配置'
    if ($useCopy) { Publish-CompatibilityLauncher $launchInfo }

    if (-not $SkipPlugins) {
        # 只取函数的最终统计对象，避免 PowerShell 将内部命令输出混入统计结果。
        $result = @(Install-PluginTranslations)[-1]
        if ($result.Supported -eq 0) {
            Write-InfoLine '暂未发现可汉化的本地插件；启动一次 Codex 后可重新运行本工具。'
        } else {
            $pluginStatusAfterInstall = Get-PluginTranslationStatus
            Write-Ok "插件名称已处理：匹配 $($pluginStatusAfterInstall.Total) 个，本次更新 $($result.Changed) 个"
        }
        if ($result.Stale -gt 0) {
            Write-WarnLine "有 $($result.Stale) 个插件的官方说明已变化，为防止错译已自动跳过。"
        }
    }

    if (-not (Test-Path -LiteralPath $toolStateRoot)) {
        New-Item -ItemType Directory -Path $toolStateRoot -Force | Out-Null
    }
    $state = [pscustomobject]@{
        installedAt = (Get-Date).ToString('o')
        codexVersion = $codex.Version
        mode = if ($useCopy) { 'compatible-copy' } else { 'built-in-locale' }
        configPath = Join-Path $CodexHome 'config.toml'
        launchPath = $launchInfo.Executable
        uiLanguageVerified = $false
    }
    Write-TextFile (Join-Path $toolStateRoot 'state.json') (($state | ConvertTo-Json) + "`r`n")

    if (-not $NoRestart) {
        Write-InfoLine '[5/5] 正在启动 Codex 并检查目标进程……'
        Start-Sleep -Milliseconds 500
        Start-Codex $launchInfo
        Write-Ok '已确认目标 Codex 进程启动；请检查窗口是否显示中文'
    } else {
        Write-InfoLine '已跳过自动重启；下次启动 Codex 时生效。'
    }
    Write-Host ''
    if ($useCopy -and -not $NoRestart) { Write-Host '  汉化完成，已启动 Codex 中文版。以后请使用桌面或开始菜单中的“Codex 中文版”。' -ForegroundColor Green }
    elseif ($useCopy) { Write-Host '  中文兼容版已准备好。已按要求跳过启动；请使用“Codex 中文版”图标。' -ForegroundColor Green }
    else { Write-Host '  语言配置已保存。请重启后检查界面；若仍是英文，请使用默认兼容模式。' -ForegroundColor Yellow }
}

function Invoke-RepairLauncher {
    Write-Title
    $copy = Get-ActiveCompatibilityCopy
    if (-not $copy) { throw '没有找到有效的中文兼容副本，请先运行一键安装。' }
    Publish-CompatibilityLauncher $copy
    Write-Ok '启动器和中文快捷方式已修复。'
    Write-Host '  请使用桌面或开始菜单中的“Codex 中文版”打开；已打开的任务会保留。' -ForegroundColor Green
}

function Invoke-Uninstall {
    Write-Title
    $codex = Get-CodexInfo
    $activeCopy = Get-ActiveCompatibilityCopy
    if ($activeCopy -and -not $NoRestart) { Stop-Codex $activeCopy.AppDirectory }
    if ($codex.Found -and -not $NoRestart) { Stop-Codex $codex.AppDirectory }
    Set-DesktopLocale 'en-US'
    Remove-CompatibilityLauncher
    Write-Ok '界面语言已恢复为英文'
    if (-not $SkipPlugins) {
        $restoreResult = @(Restore-PluginTranslations)[-1]
        if ($restoreResult.Restored -gt 0) { Write-Ok "已恢复 $($restoreResult.Restored) 个插件文件" }
        else { Write-InfoLine '没有需要恢复的插件文件。' }
        if ($restoreResult.Skipped -gt 0) {
            Write-WarnLine "有 $($restoreResult.Skipped) 个插件已被 Codex 更新，为防止覆盖新版内容，未使用旧备份。"
        }
    }
    if ($codex.Found -and -not $NoRestart) {
        Start-Sleep -Milliseconds 500
        Start-Codex $codex
        Write-Ok 'Codex 已重新启动'
    } elseif ($NoRestart) {
        Write-InfoLine '已跳过自动重启；下次启动 Codex 时生效。'
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

$consoleGuard = $null
$installerExitCode = 1
try {
    try { $consoleGuard = Initialize-InstallerConsole }
    catch {
        if (-not $Json) { Write-WarnLine '无法关闭终端选字暂停功能；安装中请不要拖动选择文字。' }
    }
    switch ($Action) {
        'install' { Invoke-Install }
        'uninstall' { Invoke-Uninstall }
        'repair-launcher' { Invoke-RepairLauncher }
        'status' {
            $report = Get-StatusReport
            if ($Json) { $report | ConvertTo-Json -Compress }
            else { Show-Status $report; Save-DiagnosticReport $report }
            if (-not $report.ready) { $installerExitCode = 2; exit 2 }
        }
    }
    $installerExitCode = 0
    exit 0
} catch {
    $installFailure = $_
    if ($Json) {
        [pscustomobject]@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
    } else {
        Write-Host ''
        Write-Host "  [失败] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '  官方安装目录没有被修改。配置或中文副本可能已完成部分步骤，详情见诊断报告。' -ForegroundColor Yellow
        try {
            Save-DiagnosticReport ([pscustomobject]@{
                toolVersion = $toolVersion; action = $Action; error = $installFailure.Exception.Message
                errorId = $installFailure.FullyQualifiedErrorId
                errorFile = $installFailure.InvocationInfo.ScriptName
                errorLine = $installFailure.InvocationInfo.ScriptLineNumber
                powershellVersion = $PSVersionTable.PSVersion.ToString()
                windowsVersion = [Environment]::OSVersion.Version.ToString()
                copyStage = $installFailure.Exception.Data['copyStage']
                copyLog = $installFailure.Exception.Data['copyLog']
                copyDirectory = $installFailure.Exception.Data['copyDirectory']
                cleanupError = $installFailure.Exception.Data['cleanupError']
                codexVersion = $installFailure.Exception.Data['codexVersion']
                configPath = (Join-Path $CodexHome 'config.toml'); uiLanguageVerified = $false
            })
        } catch { Write-WarnLine '诊断文件无法保存，请保留当前错误提示。' }
    }
    exit 1
} finally {
    if ($AutoClose -and -not $NoPause -and -not $Json) {
        $seconds = if ($installerExitCode -eq 0) { 8 } else { 30 }
        Write-Host ''
        Write-Host "  本窗口将在 $seconds 秒后自动关闭，无需按任何键。"
        if ($installerExitCode -ne 0) { Write-Host '  未完成安装。请保留 diagnostics 文件夹中的诊断报告。' -ForegroundColor Yellow }
        Start-Sleep -Seconds $seconds
    }
    if ($consoleGuard) { $consoleGuard.Dispose() }
}
