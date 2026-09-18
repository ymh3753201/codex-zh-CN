#Requires -Version 5.1
# Offline, fixed-length patching. Only operate on a disposable app copy.
function Test-PathWithin([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Path)
    return $fullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-TomlStructuralLines([string[]]$Lines) {
    # Preserve line indexes while masking multiline string contents. A heading
    # inside instructions must never be mistaken for the real [desktop] table.
    $delimiter = ''
    foreach ($line in $Lines) {
        $visible = New-Object Text.StringBuilder
        $quote = ''
        for ($i = 0; $i -lt $line.Length; $i++) {
            $char = [string]$line[$i]
            if ($delimiter) {
                if ($delimiter -eq '"""' -and $char -eq '\') { $i++; continue }
                if ($i + 3 -le $line.Length -and $line.Substring($i, 3) -eq $delimiter) {
                    $closing = $delimiter.Substring(0, 1)
                    $delimiter = ''; $i += 2
                    while ($i + 1 -lt $line.Length -and [string]$line[$i + 1] -eq $closing) { $i++ }
                }
                continue
            }
            if ($quote) {
                [void]$visible.Append($char)
                if ($char -eq '\' -and $quote -eq '"') {
                    if ($i + 1 -lt $line.Length) { $i++; [void]$visible.Append($line[$i]) }
                } elseif ($char -eq $quote) { $quote = '' }
                continue
            }
            if ($char -eq '#') { break }
            if (($char -eq '"' -or $char -eq "'") -and $i + 3 -le $line.Length -and $line.Substring($i, 3) -eq ($char * 3)) {
                $delimiter = $char * 3; $i += 2; continue
            }
            if ($char -eq '"' -or $char -eq "'") { $quote = $char }
            [void]$visible.Append($char)
        }
        if ($quote) { throw '配置包含未闭合的字符串，请先修复 config.toml。' }
        $visible.ToString()
    }
    if ($delimiter) { throw '配置包含未闭合的多行字符串，请先修复 config.toml。' }
}

function Get-ActiveCompatibilityCopy {
    $recordPath = Join-Path $toolStateRoot 'active-copy.json'
    if (-not (Test-Path -LiteralPath $recordPath)) { return $null }
    $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not (Test-PathWithin $record.AppDirectory (Join-Path $toolStateRoot 'copies')) -or
        -not (Test-PathWithin $record.Executable $record.AppDirectory)) { throw '中文副本记录路径异常' }
    if (-not (Test-Path -LiteralPath $record.Executable)) { return $null }
    return $record
}

function New-CompatibilityCopy($Source) {
    $sourceAsar = Join-Path $Source.AppDirectory 'resources\app.asar'
    $sourceHash = (Get-FileHash -LiteralPath $sourceAsar -Algorithm SHA256).Hash
    $previous = Get-ActiveCompatibilityCopy
    if ($previous -and $previous.SourceHash -eq $sourceHash -and $previous.ToolVersion -eq $toolVersion -and
        $previous.SourceDirectory -eq $Source.AppDirectory) {
        if ((Get-FileHash -LiteralPath (Join-Path $previous.AppDirectory 'resources\app.asar')).Hash -eq $previous.PatchedHash -and
            (Get-FileHash -LiteralPath $previous.Executable).Hash -eq $previous.ExecutableHash) { return $previous }
    }
    $copiesRoot = Join-Path $toolStateRoot 'copies'
    if (Test-PathWithin $toolStateRoot $Source.AppDirectory) { throw '工具数据目录不能位于 Codex 程序目录中。' }
    [void][IO.Directory]::CreateDirectory($copiesRoot)
    $copyPath = Join-Path $copiesRoot ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($copyPath)
    $copyLog = Join-Path $toolStateRoot ('copy-' + (Split-Path -Leaf $copyPath) + '.log')
    $copyStage = 'copy-files'
    try {
        $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
        # Robocopy handles long dependency paths itself. Clear read-only attributes
        # during copying, without a second recursive .NET/PowerShell file walk.
        & $robocopy $Source.AppDirectory $copyPath /E /COPY:DAT /DCOPY:DAT /A-:R /R:1 /W:1 /XJ /NFL /NDL /NP "/UNILOG:$copyLog" | Out-Null
        $copyExitCode = $LASTEXITCODE
        if ($copyExitCode -ge 8) { throw "复制 Codex 失败（代码 $copyExitCode）。请检查磁盘空间和文件权限；复制日志：$copyLog" }
        $copyStage = 'verify-copy'
        $copyAsar = Join-Path $copyPath 'resources\app.asar'
        if ((Get-FileHash -LiteralPath $copyAsar).Hash -ne $sourceHash -or
            (Get-FileHash -LiteralPath $sourceAsar).Hash -ne $sourceHash) { throw '复制期间 Codex 更新了文件，请等待更新完成后重试。' }
        $copyStage = 'patch-locale'
        $changed = Set-LocaleCompatibility $copyPath
        $exe = Find-CodexExecutable $copyPath
        Write-Ok "已修复 $changed 处翻译加载开关，并更新资源完整性校验"
        return [pscustomobject]@{
            AppDirectory = $copyPath; Executable = $exe; AppUserModelId = ''
            SourceDirectory = $Source.AppDirectory; SourceHash = $sourceHash
            PatchedHash = (Get-FileHash -LiteralPath $copyAsar).Hash
            ExecutableHash = (Get-FileHash -LiteralPath $exe).Hash
            ToolVersion = $toolVersion; CodexHome = $CodexHome
            UserDataPath = Join-Path $toolStateRoot 'user-data'
        }
    } catch {
        $copyFailure = $_
        $copyFailure.Exception.Data['copyStage'] = $copyStage
        $copyFailure.Exception.Data['copyLog'] = $copyLog
        $copyFailure.Exception.Data['copyDirectory'] = $copyPath
        $copyFailure.Exception.Data['codexVersion'] = $Source.Version
        if ((Test-PathWithin $copyPath $copiesRoot) -and (Split-Path -Leaf $copyPath) -match '^[0-9a-f]{32}$') {
            try { Remove-Item -LiteralPath $copyPath -Recurse -Force -ErrorAction Stop }
            catch {
                # Cleanup may also hit legacy path limits. Preserve the first error;
                # this unpublished copy must never become the active installation.
                $copyFailure.Exception.Data['cleanupError'] = $_.Exception.Message
                Write-WarnLine "未完成的副本暂时无法清理，已保留原始错误。副本位置：$copyPath"
            }
        }
        throw $copyFailure
    }
}

function Publish-CompatibilityLauncher($Copy) {
    Write-TextFile (Join-Path $toolStateRoot 'active-copy.json') ($Copy | ConvertTo-Json)
    # Save launch support outside the downloaded ZIP so moving it cannot break shortcuts.
    $runtime = Join-Path $toolStateRoot 'launcher'
    [void][IO.Directory]::CreateDirectory($runtime)
    Copy-Item -LiteralPath (Join-Path $scriptDir 'start-zh.ps1') -Destination (Join-Path $runtime 'start-zh.ps1') -Force
    $shell = New-Object -ComObject WScript.Shell
    $shortcuts = @()
    foreach ($folder in (Get-ShortcutFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        [void][IO.Directory]::CreateDirectory($folder)
        $shortcutPath = Join-Path $folder 'Codex 中文版.lnk'
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $runtime 'start-zh.ps1') + '"'
        $shortcut.WorkingDirectory = $toolStateRoot
        $shortcut.IconLocation = $Copy.Executable + ',0'
        $shortcut.Description = 'Codex 中文兼容版；官方更新后请重新运行汉化工具'
        $shortcut.Save()
        $shortcuts += $shortcutPath
    }
    Write-TextFile (Join-Path $toolStateRoot 'shortcuts.json') (ConvertTo-Json -InputObject @($shortcuts))
}

function Get-ShortcutFolders {
    return @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
}

function Remove-CompatibilityLauncher {
    foreach ($folder in (Get-ShortcutFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        $path = Join-Path $folder 'Codex 中文版.lnk'
        if (Test-Path -LiteralPath $path) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($path)
            if ($shortcut.Arguments.Contains((Join-Path $toolStateRoot 'launcher\start-zh.ps1'))) { Remove-Item -LiteralPath $path -Force }
        }
    }
    $record = Join-Path $toolStateRoot 'active-copy.json'
    if (Test-Path -LiteralPath $record) { Remove-Item -LiteralPath $record -Force }
    # Keep backups/copies for explicit recovery; never delete user data on uninstall.
}

function Read-AsarIndex([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        if ($reader.ReadUInt32() -ne 4) { throw 'ASAR 格式不受支持' }
        $headerSize = $reader.ReadUInt32()
        [void]$reader.ReadUInt32()
        $jsonSize = $reader.ReadUInt32()
        if ($headerSize -gt 67108864 -or $jsonSize -gt ($headerSize - 8)) { throw 'ASAR 文件头异常' }
        $bytes = $reader.ReadBytes($jsonSize)
        if ($bytes.Length -ne $jsonSize) { throw 'ASAR 文件头截断' }
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        return [pscustomobject]@{ Text = $text; Tree = ($text | ConvertFrom-Json); Base = (8L + $headerSize); JsonSize = $jsonSize }
    } finally { $stream.Dispose() }
}

function Read-AsarText([string]$Path, $Index, $Entry) {
    if ($Entry.unpacked -or $null -eq $Entry.offset -or $Entry.size -gt 67108864) { throw 'ASAR 资源结构不受支持' }
    $stream = [IO.File]::OpenRead($Path)
    try {
        [void]$stream.Seek(($Index.Base + [long]$Entry.offset), [IO.SeekOrigin]::Begin)
        $reader = New-Object IO.BinaryReader($stream)
        $bytes = $reader.ReadBytes([int]$Entry.size)
        if ($bytes.Length -ne $Entry.size) { throw 'ASAR 资源截断' }
        return [Text.Encoding]::UTF8.GetString($bytes)
    } finally { $stream.Dispose() }
}

function Get-LocaleGatePattern {
    # Handles the optional layer and the direct layer call used by settings.
    return '[A-Za-z_$][\w$]*(?:\(`72216192`\))?\?\.get\(`enable_i18n`,![01]\)'
}

function Get-LocaleCompatibility([string]$AppDirectory) {
    $path = Join-Path $AppDirectory 'resources\app.asar'
    $index = Read-AsarIndex $path
    $assets = $index.Tree.files.webview.files.assets.files
    $targets = @()
    foreach ($property in $assets.PSObject.Properties) {
        if ($property.Name -notmatch '^(app-initial|index|general-settings)-.*\.js$') { continue }
        $content = Read-AsarText $path $index $property.Value
        if ($content.Contains('enable_i18n')) {
            $matches = [regex]::Matches($content, (Get-LocaleGatePattern))
            if ($matches.Count -ne 1 -or -not $content.Contains('localeOverride') -or -not $content.Contains('72216192')) {
                throw "语言加载逻辑已变化，不能安全修复：$($property.Name)"
            }
            $targets += [pscustomobject]@{ Name = $property.Name; Entry = $property.Value; Content = $content }
        }
    }
    if ($targets.Count -gt 0 -and @($targets | Where-Object { $_.Name -match '^(app-initial|index)-' }).Count -eq 0) {
        throw '仅识别到设置页开关，未识别到主界面加载逻辑；停止生成不完整补丁。'
    }
    $version = ''
    $package = $index.Tree.files.PSObject.Properties['package.json']
    if ($package) { $version = (Read-AsarText $path $index $package.Value | ConvertFrom-Json).version }
    return [pscustomobject]@{ Index = $index; Targets = $targets; Gated = ($targets.Count -gt 0); AppVersion = $version }
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Set-LocaleCompatibility([string]$AppDirectory) {
    $status = Get-LocaleCompatibility $AppDirectory
    if (-not $status.Gated) { throw '没有识别到可修复的语言开关；请使用内置语言模式或检查新版兼容性。' }
    $path = Join-Path $AppDirectory 'resources\app.asar'
    $index = $status.Index
    $oldHeaderHash = Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($index.Text))
    $header = $index.Text
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        foreach ($target in $status.Targets) {
            $content = [regex]::Replace($target.Content, (Get-LocaleGatePattern), {
                param($match)
                return 'true/*zh-cn*/'.PadRight($match.Length, ' ')
            })
            $bytes = [Text.Encoding]::UTF8.GetBytes($content)
            if ($bytes.Length -ne $target.Entry.size) { throw '补丁长度校验失败' }
            $integrity = $target.Entry.integrity
            if ($integrity.algorithm -ne 'SHA256' -or $integrity.blockSize -le 0) { throw 'ASAR 完整性算法不受支持' }
            $hash = Get-Sha256Bytes $bytes
            $blocks = @()
            for ($offset = 0; $offset -lt $bytes.Length; $offset += $integrity.blockSize) {
                $length = [Math]::Min($integrity.blockSize, $bytes.Length - $offset)
                $block = New-Object byte[] $length
                [Array]::Copy($bytes, $offset, $block, 0, $length)
                $blocks += Get-Sha256Bytes $block
            }
            if ($blocks.Count -ne $integrity.blocks.Count) { throw 'ASAR 分块数量变化' }
            # Match only this uniquely named asset, never replace hashes globally.
            $pattern = '"' + [regex]::Escape($target.Name) + '":(\{[^{}]*\{[^{}]*\}[^{}]*\})'
            $nodes = [regex]::Matches($header, $pattern)
            if ($nodes.Count -ne 1) { throw '无法唯一定位 ASAR 资源记录' }
            $node = $nodes[0].Value
            $newNode = [regex]::Replace($node, '"hash":"[0-9a-f]{64}"', ('"hash":"' + $hash + '"'))
            $newNode = [regex]::Replace($newNode, '"blocks":\[[^\]]*\]', ('"blocks":[' + (($blocks | ForEach-Object { '"' + $_ + '"' }) -join ',') + ']'))
            if ($node.Length -ne $newNode.Length -or $newNode -eq $node) { throw 'ASAR 完整性记录校验失败' }
            $header = $header.Substring(0, $nodes[0].Index) + $newNode + $header.Substring($nodes[0].Index + $node.Length)
            [void]$stream.Seek(($index.Base + [long]$target.Entry.offset), [IO.SeekOrigin]::Begin)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        $headerBytes = [Text.Encoding]::UTF8.GetBytes($header)
        if ($headerBytes.Length -ne $index.JsonSize) { throw 'ASAR 文件头长度变化' }
        [void]$stream.Seek(16, [IO.SeekOrigin]::Begin)
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    # Classic Electron embeds the header hash in the executable; OWL builds may not.
    $newHeaderHash = Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($header))
    foreach ($name in @('ChatGPT.exe', 'Codex.exe')) {
        $exe = Join-Path $AppDirectory $name
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $bytes = [IO.File]::ReadAllBytes($exe)
        $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
        $matches = [regex]::Matches($text, '"file":"resources[^"\r\n]*app\.asar","alg":"SHA256","value":"([0-9a-f]{64})"')
        foreach ($match in $matches) {
            if ($match.Groups[1].Value -ne $oldHeaderHash) { throw '程序与原 ASAR 完整性不一致，停止发布副本。' }
            $hashBytes = [Text.Encoding]::ASCII.GetBytes($newHeaderHash)
            [Array]::Copy($hashBytes, 0, $bytes, $match.Groups[1].Index, 64)
        }
        if ($matches.Count -gt 0) { [IO.File]::WriteAllBytes($exe, $bytes) }
    }
    $after = Get-LocaleCompatibility $AppDirectory
    if ($after.Gated) { throw '语言开关修复后校验失败' }
    return $status.Targets.Count
}
