#Requires -Version 5.1
param([string]$PackageRoot = '', [switch]$SkipDelayTests)
$ErrorActionPreference = 'Stop'
if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $PSScriptRoot }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-unattended-' + [guid]::NewGuid().ToString('N'))
$process = $null
try {
    [void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'scripts'))
    # Exercise the actual BAT with stdin left open, but never send a key.
    # Substitute only the expensive installer to isolate launcher input waits.
    $fixture = @'
param([string]$Action, [switch]$AutoClose, [switch]$NoPause)
if ($Action -notin @('install', 'repair-launcher')) { exit 8 }
Write-Output 'INSTALLER_RETURNED'
exit 0
'@
    [IO.File]::WriteAllText((Join-Path $testRoot 'scripts\install_windows.ps1'), $fixture)
    foreach ($relative in @('scripts\bootstrap.ps1','scripts\run-installer.bat','scripts\locale-compat.ps1','scripts\console-mode.ps1','scripts\start-zh.ps1','resources\release.json','resources\bundled-plugins-zh-CN.json')) {
        $target = Join-Path $testRoot $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath (Join-Path $PackageRoot $relative) -Destination $target -Force
    }
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'install-windows.bat') -Destination $testRoot
    foreach ($name in @('install-windows.bat', '一键汉化.bat', '一键安装.bat', '修复启动.bat')) {
        $source = Join-Path $PackageRoot $name
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing unattended entry: $name" }
        if ($name -ne 'install-windows.bat') { Copy-Item -LiteralPath $source -Destination $testRoot }
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $env:ComSpec
        $start.Arguments = '/d /c ""' + (Join-Path $testRoot $name) + '""'
        $start.WorkingDirectory = $testRoot
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($start)
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(25000)) {
            $process.Kill(); $process.WaitForExit()
            throw "Entry still waits for a key after installer returned: $name"
        }
        if ($process.ExitCode -ne 0 -or -not $output.Result.Contains('INSTALLER_RETURNED')) {
            throw "Entry failed: $name : $($errors.Result)"
        }
        $process.Dispose(); $process = $null
    }
    Write-Host '[PASS] all install BAT entries exit without any keyboard input'
    if (-not $SkipDelayTests) {
        foreach ($name in @('locale-compat.ps1', 'console-mode.ps1')) {
            Copy-Item -LiteralPath (Join-Path $PackageRoot ('scripts\' + $name)) -Destination (Join-Path $testRoot 'scripts')
        }
        $installerFile = Join-Path $PackageRoot 'scripts\install_windows.ps1'
        $sourceText = [IO.File]::ReadAllText($installerFile)
        $ast = [Management.Automation.Language.Parser]::ParseFile($installerFile, [ref]$null, [ref]$null)
        $installFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Install' }, $false)
        foreach ($fail in @($false, $true)) {
            # Keep the actual CLI bootstrap, catch/finally, timer and exit code.
            # Replace only the workflow; full workflow has separate isolation tests.
            $replacement = if ($fail) { "function Invoke-Install { throw 'EXPECTED_FAILURE' }" } else { "function Invoke-Install { Write-Output 'WORKFLOW_DONE' }" }
            $text = $sourceText.Substring(0, $installFunction.Extent.StartOffset) + $replacement + $sourceText.Substring($installFunction.Extent.EndOffset)
            [IO.File]::WriteAllText((Join-Path $testRoot 'scripts\install_windows.ps1'), $text, (New-Object Text.UTF8Encoding($true)))
            $start = New-Object Diagnostics.ProcessStartInfo
            $start.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $testRoot 'scripts\install_windows.ps1') + '" -Action install -AutoClose -CodexHome "' + (Join-Path $testRoot 'data') + '"'
            $start.UseShellExecute = $false; $start.CreateNoWindow = $true
            $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $process = [Diagnostics.Process]::Start($start)
            $output = $process.StandardOutput.ReadToEndAsync()
            $errors = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(45000)) { $process.Kill(); $process.WaitForExit(); throw 'Actual CLI waits indefinitely for input' }
            $expectedCode = if ($fail) { 1 } else { 0 }
            $minSeconds = if ($fail) { 30 } else { 8 }
            if ($process.ExitCode -ne $expectedCode -or $watch.Elapsed.TotalSeconds -lt $minSeconds) {
                throw "CLI delay/exit code failed: exit=$($process.ExitCode), elapsed=$($watch.Elapsed.TotalSeconds), $($errors.Result)"
            }
            $marker = if ($fail) { 'EXPECTED_FAILURE' } else { 'WORKFLOW_DONE' }
            if (-not $output.Result.Contains($marker)) { throw 'CLI omitted the result before closing' }
            $process.Dispose(); $process = $null
        }
        Write-Host '[PASS] real CLI success/failure auto-close timers, result text, exit codes; no keys sent'
    }
} finally {
    if ($process) { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }; $process.Dispose() }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $allowed = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved) -match '^codex-zh-unattended-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
