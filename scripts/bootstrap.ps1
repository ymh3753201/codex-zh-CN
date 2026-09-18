#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('install', 'status', 'uninstall', 'repair-launcher')]
    [string]$Action = 'install',
    [string]$CodexPath = '',
    [switch]$AutoClose,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch {}
$root = Split-Path -Parent $PSScriptRoot
$exitCode = 1
$transcribing = $false
$log = ''
try {
    foreach ($folder in @((Join-Path $root 'diagnostics'), (Join-Path ([IO.Path]::GetTempPath()) 'codex-zh-diagnostics'))) {
        try {
            [void][IO.Directory]::CreateDirectory($folder)
            $log = Join-Path $folder ('startup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
            Start-Transcript -LiteralPath $log -ErrorAction Stop | Out-Null
            $transcribing = $true
            break
        } catch { $log = '' }
    }
    Write-Host 'Codex Chinese installer - starting...'
    if ($log) { Write-Host "Startup log: $log" }
    foreach ($relative in @('scripts\install_windows.ps1', 'scripts\locale-compat.ps1', 'scripts\console-mode.ps1', 'scripts\start-zh.ps1', 'resources\release.json', 'resources\bundled-plugins-zh-CN.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) {
            throw "Missing package file: $relative. Extract the complete ZIP into a new folder and try again."
        }
    }
    $hostPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'install_windows.ps1'), '-Action', $Action, '-NoPause')
    if ($CodexPath) { $arguments += @('-CodexPath', $CodexPath) }
    # A separate process also captures parser/bootstrap errors and exit statements.
    $ErrorActionPreference = 'Continue'
    & $hostPath @arguments 2>&1 | ForEach-Object { Write-Host "$_" }
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($exitCode -ne 0) { throw "Installer failed (exit code $exitCode). See the error above and the startup log." }
    if ($AutoClose -and -not $NoPause -and $Action -in @('install', 'repair-launcher')) { Start-Sleep -Seconds 8 }
} catch {
    $exitCode = 1
    Write-Host "[FAILED] $($_.Exception.Message)" -ForegroundColor Red
    if ($log) { Write-Host "Startup log: $log" }
    else { Write-Host 'Unable to save a log. Please keep a screenshot of this window.' }
} finally {
    if ($transcribing) { try { Stop-Transcript | Out-Null } catch {} }
}
exit $exitCode
