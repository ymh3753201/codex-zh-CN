#Requires -Version 5.1
# -HeadlessRunner：无控制台的运行器（例如 GitHub Actions 托管运行器）上 cmd 的 pause 会立即返回，
# 交互等待本身只能在本机带控制台的 Windows 上验证。
param([string]$PackageRoot = '', [switch]$HeadlessRunner)
$ErrorActionPreference = 'Stop'
if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $PSScriptRoot }
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-bootstrap-' + [guid]::NewGuid().ToString('N'))
$process = $null
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    $package = Join-Path $root 'package space [01] & %PATH% !test!'
    [void][IO.Directory]::CreateDirectory((Join-Path $package 'scripts'))
    foreach ($relative in @('install-windows.bat', 'scripts\bootstrap.ps1','scripts\run-installer.bat','scripts\locale-compat.ps1','scripts\console-mode.ps1','scripts\start-zh.ps1','resources\release.json','resources\bundled-plugins-zh-CN.json')) {
        $target = Join-Path $package $relative
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
        Copy-Item -LiteralPath (Join-Path $PackageRoot $relative) -Destination $target
    }
    $installer = Join-Path $package 'scripts\install_windows.ps1'
    foreach ($scenario in @('missing', 'parser-error', 'runtime-error', 'success')) {
        if ($scenario -eq 'parser-error') { [IO.File]::WriteAllText($installer, 'param( BROKEN') }
        if ($scenario -eq 'runtime-error') { [IO.File]::WriteAllText($installer, "throw 'EXPECTED_BOOTSTRAP_FAILURE'") }
        if ($scenario -eq 'success') { [IO.File]::WriteAllText($installer, 'param($Action,[switch]$NoPause); Write-Output "BOOTSTRAP_SUCCESS"; exit 0') }
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $package 'scripts\bootstrap.ps1') + '" -NoPause'
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($info)
        $output = $process.StandardOutput.ReadToEndAsync(); $errorOutput = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { throw "Bootstrap timed out: $scenario" }
        Assert (($process.ExitCode -eq 0) -eq ($scenario -eq 'success')) "Incorrect exit code: $scenario"
        $logs = @(Get-ChildItem -LiteralPath (Join-Path $package 'diagnostics') -Filter 'startup-*.log')
        $log = [IO.File]::ReadAllText(($logs | Sort-Object LastWriteTime | Select-Object -Last 1).FullName)
        $marker = if ($scenario -eq 'success') { 'BOOTSTRAP_SUCCESS' } else { '[FAILED]' }
        Assert ($output.Result.Contains($marker) -and $log.Contains($marker)) "Missing visible/persistent result: $scenario"
        $process.Dispose(); $process = $null
        Write-Host "[PASS] bootstrap $scenario; special-character path; persistent log"
    }
    # Real BAT must wait on failure, with stdin open and no keys sent.
    [IO.File]::WriteAllText($installer, "throw 'EXPECTED_BOOTSTRAP_FAILURE'")
    $info.FileName = $env:ComSpec
    # Expand the launcher path once, as Explorer does; embedding a literal
    # %PATH% in /c command text would expand it before the BAT can even run.
    $info.EnvironmentVariables['CODEX_TEST_ENTRY'] = Join-Path $package 'install-windows.bat'
    $info.Arguments = '/d /c ""%CODEX_TEST_ENTRY%""'
    $info.RedirectStandardInput = $true
    $process = [Diagnostics.Process]::Start($info)
    $output = $process.StandardOutput.ReadToEndAsync(); $errorOutput = $process.StandardError.ReadToEndAsync()
    $exitedEarly = $process.WaitForExit(8000)
    if ($HeadlessRunner) {
        Assert ($output.Result.Contains('Installation did not complete')) 'Failed BAT must reach the failure notice printed just before the pause prompt'
        try { $process.StandardInput.WriteLine(' ') } catch {}
        try { $process.StandardInput.Close() } catch {}
        if (-not $process.WaitForExit(10000)) { throw 'Failed BAT did not exit after acknowledgment' }
        Assert ($process.ExitCode -ne 0 -and $output.Result.Contains('[FAILED]')) 'BAT must preserve failure'
        Write-Host "[PASS] failed BAT preserves the failure notice and error exit code (interactive key wait is only checked on a console, exitEarly=$exitedEarly)"
    } else {
        if ($exitedEarly) {
            $earlyOut = $output.Result
            $earlyErr = $errorOutput.Result
            throw ("Failed BAT must not silently close (exit=$($process.ExitCode), entry=$($info.EnvironmentVariables['CODEX_TEST_ENTRY'])); " +
                "stdout=<<$earlyOut>>; stderr=<<$earlyErr>>")
        }
        $process.StandardInput.WriteLine(' ')
        $process.StandardInput.Close()
        Assert ($process.WaitForExit(10000)) 'Failed BAT did not exit after acknowledgment'
        Assert ($process.ExitCode -ne 0 -and $output.Result.Contains('[FAILED]')) 'BAT must preserve failure'
        Write-Host '[PASS] failed BAT keeps error window until acknowledgment'
    }
} finally {
    if ($process) { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }; $process.Dispose() }
    $resolved = [IO.Path]::GetFullPath($root)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-bootstrap-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
