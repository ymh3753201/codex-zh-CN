#Requires -Version 5.1
param(
    [string]$InstallerPath = '',
    [switch]$LegacyLongPaths,
    [ValidateSet('Modern','Legacy','ModernBlocked','LegacyUnblocked')]
    [string]$PathHandling = 'Legacy',
    [string]$DataFolder = '中文 数据[测试]',
    [switch]$CompareOldTraversal,
    [string]$ResultPath = ''
)
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-workflow-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$pathSwitches = @()
$caseResult = [ordered]@{ passed=$false; profile=$DataFolder; pathHandling=$PathHandling; oldTraversalPassed=$null; oldTraversalError=''; dependencyPathLength=0 }
if ($LegacyLongPaths) {
    # Test-process-only emulation of older .NET path handling; no registry changes.
    $switchType = [IO.Path].Assembly.GetType('System.AppContextSwitches')
    foreach ($name in @('_useLegacyPathHandling', '_blockLongPaths')) {
        $field = $switchType.GetField($name, [Reflection.BindingFlags]'Static,NonPublic')
        if (-not $field) { throw 'Run legacy path tests with Windows PowerShell 5.1' }
        $enabled = if ($name -eq '_useLegacyPathHandling') { $PathHandling -in @('Legacy','LegacyUnblocked') } else { $PathHandling -in @('Legacy','ModernBlocked') }
        $pathSwitches += @{ Field=$field; Original=$field.GetValue($null); Configured=$(if ($enabled) { 1 } else { -1 }) }
    }
}
function Set-TestLegacyPaths([bool]$Enabled) {
    foreach ($entry in $pathSwitches) { $entry.Field.SetValue($null, $(if ($Enabled) { $entry.Configured } else { $entry.Original })) }
}
try {
    $app = Join-Path $root '中文 程序[测试]'
    $data = Join-Path $root $DataFolder
    [void][IO.Directory]::CreateDirectory((Join-Path $app 'resources'))
    if (-not $InstallerPath) { $InstallerPath = Join-Path $PSScriptRoot '..\scripts\install_windows.ps1' }
    . $InstallerPath -CodexPath $app -CodexHome $data -NoRestart -SkipPlugins
    function Get-ShortcutFolders { return @((Join-Path $root 'desktop'), (Join-Path $root 'programs')) }
    $files = [ordered]@{
        'package.json' = '{"version":"fixture"}'
        '.vite/build/main-test.js' = 'const localeOverride="zh-CN",nativeIntl=true;'
        'native-menu-locales/zh-CN.json' = '{"title":"中文"}'
        'webview/assets/zh-CN-test.js' = 'export default {title:"中文"};'
        'webview/assets/app-initial-test.js' = 'const localeOverride="zh-CN",layer="72216192",enabled=x?.get(`enable_i18n`,!1);'
        'webview/assets/general-settings-test.js' = 'const localeOverride="zh-CN",layer="72216192",enabled=x?.get(`enable_i18n`,!0);'
    }
    $tree = @{ files = @{} }
    $payload = New-Object IO.MemoryStream
    foreach ($file in $files.GetEnumerator()) {
        $parts = $file.Key.Split('/')
        $node = $tree
        for ($i=0; $i -lt $parts.Length-1; $i++) {
            if (-not $node.files.ContainsKey($parts[$i])) { $node.files[$parts[$i]] = @{ files = @{} } }
            $node = $node.files[$parts[$i]]
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($file.Value)
        $hash = Get-Sha256Bytes $bytes
        $node.files[$parts[-1]] = @{ size=$bytes.Length; offset=[string]$payload.Position; integrity=@{ algorithm='SHA256'; hash=$hash; blockSize=4194304; blocks=@($hash) } }
        $payload.Write($bytes,0,$bytes.Length)
    }
    $fixtureJson = [Text.Encoding]::UTF8.GetBytes(($tree | ConvertTo-Json -Depth 30 -Compress))
    $headerSize = 8 + $fixtureJson.Length + ((4 - ($fixtureJson.Length % 4)) % 4)
    $asar = Join-Path $app 'resources\app.asar'
    $writer = New-Object IO.BinaryWriter([IO.File]::Create($asar))
    $writer.Write([uint32]4); $writer.Write([uint32]$headerSize); $writer.Write([uint32]($headerSize-4)); $writer.Write([uint32]$fixtureJson.Length)
    $writer.Write($fixtureJson); $writer.Write((New-Object byte[] ($headerSize-8-$fixtureJson.Length))); $writer.Write($payload.ToArray()); $writer.Dispose(); $payload.Dispose()
    [IO.File]::WriteAllText((Join-Path $app 'ChatGPT.exe'), 'fixture executable: never launched')
    if ($LegacyLongPaths) {
        $deepRelative = 'resources\cua_node\bin\node_modules\@oai\sky\dist\js-dependency-cache\shared-v1\applied-bk-agent-openai-js\pnpm-store\v11\links\rollup\plugin-typescript\12.1.2\' + ('abcdef0123456789' * 5)
        $deepSource = '\\?\' + (Join-Path $app $deepRelative)
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $deepSource))
        [IO.File]::WriteAllText($deepSource, 'long dependency fixture')
        [IO.File]::SetAttributes($deepSource, [IO.FileAttributes]::ReadOnly)
        [IO.File]::SetAttributes($asar, [IO.FileAttributes]::ReadOnly)
        [IO.File]::SetAttributes((Join-Path $app 'ChatGPT.exe'), [IO.FileAttributes]::ReadOnly)
        Set-TestLegacyPaths $true
    }
    $originalHash = (Get-FileHash -LiteralPath $asar).Hash
    Invoke-Install
    $active = Get-ActiveCompatibilityCopy
    Assert ($null -ne $active) 'Default install must publish a compatibility copy'
    Assert ((Get-DesktopLocale) -eq 'zh-CN') 'Default workflow must persist locale'
    $status = Get-StatusReport
    Assert ($status.localizationReady -and $status.compatibleCopyCurrent -and $status.compatibleCopyPatched) 'Status must verify current patched copy'
    $originalSource = [IO.File]::ReadAllBytes($asar)
    try {
        # Same installation path, new contents: path-only checks used to miss this.
        [IO.File]::SetAttributes($asar, [IO.FileAttributes]::Normal)
        $stream = [IO.File]::Open($asar, [IO.FileMode]::Append)
        try { $stream.WriteByte(0) } finally { $stream.Dispose() }
        $status = Get-StatusReport
        Assert ($status.compatibleCopySourceChanged -and -not $status.localizationReady) 'Status must detect in-place app update'
    } finally { [IO.File]::WriteAllBytes($asar, $originalSource); if ($LegacyLongPaths) { [IO.File]::SetAttributes($asar, [IO.FileAttributes]::ReadOnly) } }
    Assert ((Get-FileHash -LiteralPath $asar).Hash -eq $originalHash) 'Source must remain unchanged'
    Assert (-not (Get-LocaleCompatibility $active.AppDirectory).Gated) 'Copy must bypass the translation gate'
    if ($LegacyLongPaths) {
        Set-TestLegacyPaths $false
        try {
            $deepCopy = '\\?\' + (Join-Path $active.AppDirectory $deepRelative)
            $caseResult.dependencyPathLength = $deepCopy.Length - 4
            Assert ($deepCopy.Length -gt 300) 'Fixture must exceed the legacy 260-character limit'
            Assert ([IO.File]::ReadAllText($deepCopy) -eq 'long dependency fixture') 'Deep dependency contents must survive copying'
            Assert (([IO.File]::GetAttributes($deepCopy) -band [IO.FileAttributes]::ReadOnly) -eq 0) 'Copied long-path file must be writable'
            Assert (([IO.File]::GetAttributes($deepSource) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'Original dependency attributes must remain unchanged'
            Assert (([IO.File]::GetAttributes($asar) -band [IO.FileAttributes]::ReadOnly) -ne 0) 'Original ASAR attributes must remain unchanged'
        } finally { Set-TestLegacyPaths $true }
        if ($CompareOldTraversal) {
            # Replay the exact v0.3.2 post-copy operation on the same real copy.
            # Do not change the system or substitute a simulated file error.
            try {
                Get-ChildItem -LiteralPath $active.AppDirectory -File -Recurse | ForEach-Object { $_.IsReadOnly = $false }
                $caseResult.oldTraversalPassed = $true
            } catch {
                $caseResult.oldTraversalPassed = $false
                $caseResult.oldTraversalError = $_.Exception.Message
            }
        }
    }
    $firstPath = $active.AppDirectory
    $shortcutPath = Join-Path $root 'desktop\Codex 中文版.lnk'
    Assert (Test-Path -LiteralPath $shortcutPath) 'Desktop shortcut must be created'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    Assert ($shortcut.Arguments.Contains((Join-Path $toolStateRoot 'launcher\start-zh.ps1'))) 'Shortcut must target persistent launcher'
    Invoke-Install
    Assert ((Get-ActiveCompatibilityCopy).AppDirectory -eq $firstPath) 'Repeated installation must reuse a verified copy'
    $persistentLauncher = Join-Path $toolStateRoot 'launcher\start-zh.ps1'
    [IO.File]::WriteAllText($persistentLauncher, '# old launcher')
    $beforeRepairHash = (Get-FileHash -LiteralPath (Join-Path $active.AppDirectory 'resources\app.asar')).Hash
    function Stop-Codex { throw 'Repair must not stop an application' }
    function Start-Codex { throw 'Repair must not restart an application' }
    Invoke-RepairLauncher
    Assert ((Get-FileHash -LiteralPath $persistentLauncher).Hash -eq (Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $InstallerPath) 'start-zh.ps1')).Hash) 'Repair must replace the installed launcher'
    Assert ((Get-ActiveCompatibilityCopy).AppDirectory -eq $firstPath) 'Repair must keep the installed copy'
    Assert ((Get-FileHash -LiteralPath (Join-Path $active.AppDirectory 'resources\app.asar')).Hash -eq $beforeRepairHash) 'Repair must not rewrite app resources'
    # Exercise the normal automatic branch with only OS process actions stubbed.
    # The separate runtime smoke test runs the real Start-Codex implementation.
    function Read-Host { throw 'Unexpected interactive input' }
    function Stop-Codex([string]$AppDirectory) {}
    function Start-Codex($CodexInfo) { $script:launchedExe = $CodexInfo.Executable }
    $NoRestart = $false
    $completed = Invoke-Install 6>&1 | Out-String
    Assert ($script:launchedExe -eq (Get-ActiveCompatibilityCopy).Executable) 'Automatic branch must launch the compatible copy'
    Assert ($completed.Contains('汉化完成，已启动 Codex 中文版')) 'Only successful startup should report completion'
    function Start-Codex($CodexInfo) { throw 'EXPECTED_START_FAILURE' }
    $failed = $false
    try { Invoke-Install 6>&1 | Out-Null } catch { $failed = $_.Exception.Message -eq 'EXPECTED_START_FAILURE' }
    Assert $failed 'Automatic workflow must propagate startup failure'
    $NoRestart = $true
    Invoke-Uninstall
    Assert ((Get-DesktopLocale) -eq 'en-US') 'Restore must set English'
    Assert (-not (Test-Path -LiteralPath $shortcutPath)) 'Restore must remove owned shortcut'
    Assert ($null -eq (Get-ActiveCompatibilityCopy)) 'Restore must deactivate the copy'
    if ($LegacyLongPaths) {
        # A patch failure with a deep partial copy used to be replaced by the
        # cleanup exception. Preserve the real reason and leave it unpublished.
        function Set-LocaleCompatibility { throw 'EXPECTED_ORIGINAL_PATCH_FAILURE' }
        $failure = $null
        try { New-CompatibilityCopy (Get-CodexInfo) | Out-Null } catch { $failure = $_ }
        Assert ($failure.Exception.Message -eq 'EXPECTED_ORIGINAL_PATCH_FAILURE') 'Cleanup must not replace the original installation error'
        Assert ($failure.Exception.Data['copyStage'] -eq 'patch-locale') 'Failure stage must identify the actual operation'
        if ($PathHandling -eq 'Legacy') {
            Assert (-not [string]::IsNullOrWhiteSpace($failure.Exception.Data['cleanupError'])) 'Legacy cleanup failure must be recorded separately'
        }
        Assert (Test-Path -LiteralPath $failure.Exception.Data['copyLog']) 'Copy log must survive failure'
        Assert ($null -eq (Get-ActiveCompatibilityCopy)) 'Failed copy must never become active'
        Write-Host '[PASS] legacy long paths: real copying, read-only attributes, unchanged source, original error preserved despite cleanup failure'
    }
    Write-Host '[PASS] default install, copy patch, persistent shortcuts, reuse, restore; Chinese and bracketed paths'
    $caseResult.passed = $true
} finally {
    Set-TestLegacyPaths $false
    if ($ResultPath) { [IO.File]::WriteAllText($ResultPath, ($caseResult | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    $resolved = [IO.Path]::GetFullPath($root)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-workflow-[0-9a-f]{32}$') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
