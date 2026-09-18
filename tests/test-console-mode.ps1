#Requires -Version 5.1
param([switch]$Child, [string]$ResultPath = '', [string]$PackageRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $PSScriptRoot }
if ($Child) {
    $guard = $null
    $original = [uint32]0
    $handleValue = [IntPtr]::Zero
    try {
        . (Join-Path $PackageRoot 'scripts\console-mode.ps1')
        $guard = Initialize-InstallerConsole
        if (-not $guard.Active) { throw "Test requires a real console, error=$($guard.ErrorCode)" }
        $handleValue = $guard.InputHandle
        $original = $guard.OriginalMode
        $guard.Dispose()
        # Enable Quick Edit like a typical Windows 10 console, then exercise
        # the real production native API calls in this isolated console.
        $before = $original -bor 0x00C0
        if (-not [CodexZh.ConsoleGuard]::SetConsoleMode($handleValue, $before)) { throw 'Cannot enable fixture Quick Edit' }
        $guard = Initialize-InstallerConsole
        $after = [uint32]0
        if (-not [CodexZh.ConsoleGuard]::GetConsoleMode($handleValue, [ref]$after)) { throw 'Cannot read console mode' }
        if (($after -band 0x40) -ne 0) { throw 'Quick Edit remains enabled' }
        if (($after -band 0x80) -eq 0) { throw 'Extended flags missing' }
        if (($after -band 0xFFFFFF3F) -ne ($before -band 0xFFFFFF3F)) { throw 'Unrelated input flags changed' }
        $guard.Dispose()
        $restored = [uint32]0
        [void][CodexZh.ConsoleGuard]::GetConsoleMode($handleValue, [ref]$restored)
        if (($restored -band 0x40) -eq 0) { throw 'Original Quick Edit not restored' }
        [IO.File]::WriteAllText($ResultPath, 'PASS')
    } catch { [IO.File]::WriteAllText($ResultPath, ('FAIL: ' + $_.Exception.Message)); exit 1 }
    finally {
        if ($guard) { $guard.Dispose() }
        if ($handleValue -ne [IntPtr]::Zero) { [void][CodexZh.ConsoleGuard]::SetConsoleMode($handleValue, ($original -bor 0x80)) }
    }
    exit 0
}
$resultFile = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-console-' + [guid]::NewGuid().ToString('N') + '.txt')
$process = $null
try {
    $argsValue = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Child -ResultPath "' + $resultFile + '" -PackageRoot "' + $PackageRoot + '"'
    $process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $argsValue -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Native console test timed out' }
    if (-not (Test-Path -LiteralPath $resultFile)) { throw 'Native console test produced no report' }
    $result = [IO.File]::ReadAllText($resultFile)
    if ($result -ne 'PASS') { throw $result }
    Write-Host '[PASS] real hidden console: disable Quick Edit, preserve other flags, restore on exit'
} finally {
    if ($process) { $process.Dispose() }
    if (Test-Path -LiteralPath $resultFile) { Remove-Item -LiteralPath $resultFile -Force }
}
