#Requires -Version 5.1
# Offline, fixed-length patching. Only operate on a disposable app copy.
function Test-PathWithin([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $fullPath = [IO.Path]::GetFullPath($Path)
    return $fullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-LegacyCompatibilityRoots {
    # v0.1/v0.2 used this writable copy outside the current zh-cn-tool state
    # directory. Keep it out of discovery so a failed old install cannot be
    # selected as the source for a new installation.
    return @(
        (Join-Path $CodexHome 'zh-cn-patched'),
        (Join-Path $CodexHome 'zh-cn-patched\app')
    )
}

function Test-IsLegacyCompatibilityPath([string]$Path) {
    foreach ($root in (Get-LegacyCompatibilityRoots)) {
        if (Test-PathWithin $Path $root) { return $true }
    }
    return $false
}

function Get-AsarFileEntries($Node, [string]$Prefix = '') {
    foreach ($property in @($Node.files.PSObject.Properties)) {
        $path = if ($Prefix) { "$Prefix/$($property.Name)" } else { $property.Name }
        if ($property.Value.files) {
            Get-AsarFileEntries $property.Value $path
        } else {
            [pscustomobject]@{ Path = $path; Name = $property.Name; Entry = $property.Value }
        }
    }
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
    try {
        $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not (Test-PathWithin $record.AppDirectory (Join-Path $toolStateRoot 'copies')) -or
            -not (Test-PathWithin $record.Executable $record.AppDirectory)) { throw '路径不在受保护的副本目录中' }
    } catch {
        # Old releases could leave a truncated or incompatible record after a
        # failed copy. Ignore it for a fresh install; Publish-Compatibility-
        # Launcher will atomically replace it after the new copy is verified.
        Write-WarnLine "发现旧版或损坏的中文副本记录，安装时将重新创建：$recordPath"
        return $null
    }
    if (-not (Test-Path -LiteralPath $record.Executable)) { return $null }
    return $record
}

function Get-DirectorySize([string]$Path) {
    $total = 0L
    foreach ($file in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
        try { $total += ([IO.FileInfo]::new($file)).Length } catch {}
    }
    return $total
}

function Assert-CopySpace([string]$SourceDirectory, [string]$TargetRoot) {
    # Fail before robocopy starts, with a message ordinary users can act on.
    try {
        $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($TargetRoot)))
        $free = $drive.AvailableFreeSpace
        $needed = [long]((Get-DirectorySize $SourceDirectory) * 1.1) + 200MB
    } catch { return } # Unknown size or network drive: let robocopy report errors.
    if ($free -lt $needed) {
        throw ('磁盘空间不足：中文副本约需 {0:N1} GB，{1} 仅剩 {2:N1} GB。请清理磁盘后重试。' -f ($needed / 1GB), $drive.Name, ($free / 1GB))
    }
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
    Assert-CopySpace $Source.AppDirectory $copiesRoot
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
    $shortcuts = @()
    foreach ($folder in (Get-ShortcutFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        [void][IO.Directory]::CreateDirectory($folder)
        $shortcutPath = Join-Path $folder (Get-ShortcutName)
        Save-UnicodeShortcut $shortcutPath @{
            TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $runtime 'start-zh.ps1') + '"'
            WorkingDirectory = $toolStateRoot
            IconLocation = $Copy.Executable + ',0'
            Description = 'Codex 中文兼容版；官方更新后请重新运行汉化工具'
        }
        $shortcuts += $shortcutPath
    }
    Write-TextFile (Join-Path $toolStateRoot 'shortcuts.json') (ConvertTo-Json -InputObject @($shortcuts))
}

function Get-ShortcutName {
    # Built from code points so the name survives any console or file encoding.
    return 'Codex ' + [string][char]0x4E2D + [char]0x6587 + [char]0x7248 + '.lnk'
}

function Initialize-ShellLinkType {
    # WScript.Shell stores shortcut strings through the ANSI code page, so Chinese
    # user names or paths turn into "?" on English Windows. IShellLinkW is Unicode.
    if ('CodexZh.ShellLink' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
namespace CodexZh {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class CShellLink {}
    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
    interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int cch, IntPtr pfd, int flags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetHotkey(out short h);
        void SetHotkey(short h);
        void GetShowCmd(out int c);
        void SetShowCmd(int c);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int cch, out int i);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, int r);
        void Resolve(IntPtr hwnd, int flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
    }
    public static class ShellLink {
        public static void Save(string path, string target, string arguments, string workingDirectory, string icon, int iconIndex, string description) {
            var link = (IShellLinkW)new CShellLink();
            try {
                link.SetPath(target);
                link.SetArguments(arguments);
                link.SetWorkingDirectory(workingDirectory);
                link.SetIconLocation(icon, iconIndex);
                link.SetDescription(description);
                ((IPersistFile)link).Save(path, true);
            } finally { Marshal.FinalReleaseComObject(link); }
        }
        public static string ReadArguments(string path) {
            var link = (IShellLinkW)new CShellLink();
            try {
                ((IPersistFile)link).Load(path, 0);
                var sb = new StringBuilder(32768);
                link.GetArguments(sb, sb.Capacity);
                return sb.ToString();
            } finally { Marshal.FinalReleaseComObject(link); }
        }
    }
}
'@
}

function Save-UnicodeShortcut([string]$Path, [hashtable]$Properties) {
    Initialize-ShellLinkType
    $icon = [string]$Properties.IconLocation
    $index = 0
    if ($icon -match '^(.*),(-?\d+)$') { $icon = $Matches[1]; $index = [int]$Matches[2] }
    [CodexZh.ShellLink]::Save($Path, $Properties.TargetPath, $Properties.Arguments,
        $Properties.WorkingDirectory, $icon, $index, $Properties.Description)
    if (-not [IO.File]::Exists($Path)) { throw "快捷方式创建失败：$Path" }
}

function Read-UnicodeShortcutArguments([string]$Path) {
    try { Initialize-ShellLinkType; return [CodexZh.ShellLink]::ReadArguments($Path) } catch { return '' }
}

function Get-ShortcutFolders {
    return @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
}

function Remove-CompatibilityLauncher {
    foreach ($folder in (Get-ShortcutFolders)) {
        if ([string]::IsNullOrWhiteSpace($folder)) { continue }
        $path = Join-Path $folder (Get-ShortcutName)
        if (Test-Path -LiteralPath $path) {
            $arguments = Read-UnicodeShortcutArguments $path
            if ($arguments -and $arguments.Contains((Join-Path $toolStateRoot 'launcher\start-zh.ps1'))) { Remove-Item -LiteralPath $path -Force }
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
    # The Statsig layer id is not part of the contract: new releases may rename it.
    return '[A-Za-z_$][\w$]*(?:\(`\d{4,}`\))?\?\.get\(`enable_i18n`,![01]\)'
}

function Get-LocaleCompatibility([string]$AppDirectory) {
    $path = Join-Path $AppDirectory 'resources\app.asar'
    $index = Read-AsarIndex $path
    $entries = @(Get-AsarFileEntries $index.Tree)
    $targets = @()
    foreach ($file in $entries) {
        if ($file.Path -notmatch '(?i)^webview/assets/(app-initial|index|general-settings)-.*\.js$') { continue }
        $content = Read-AsarText $path $index $file.Entry
        if ($content.Contains('enable_i18n')) {
            $gateMatches = [regex]::Matches($content, (Get-LocaleGatePattern))
            if ($gateMatches.Count -ne 1 -or -not $content.Contains('localeOverride') -or
                [regex]::Matches($content, 'enable_i18n').Count -ne 1) {
                throw "语言加载逻辑已变化，不能安全修复：$($file.Name)"
            }
            $targets += [pscustomobject]@{ Name = $file.Name; Entry = $file.Entry; Content = $content }
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
