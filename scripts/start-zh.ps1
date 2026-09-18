#Requires -Version 5.1
param([string]$StateRoot = '', [switch]$NoPopup)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -eq 5) {
    $env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
}

function Get-LauncherProcesses { @(Get-CimInstance Win32_Process) }

function Get-LauncherProfile([string]$CommandLine) {
    $match = [regex]::Match($CommandLine, '(?:^|\s)(?:"--user-data-dir=([^"]+)"|--user-data-dir(?:=|\s+)(?:"([^"]+)"|(\S+)))')
    if (-not $match.Success) { return '' }
    foreach ($group in $match.Groups | Select-Object -Skip 1) {
        if ($group.Success) {
            try { return [IO.Path]::GetFullPath($group.Value).TrimEnd('\') } catch { return '' }
        }
    }
}

function Find-LauncherInstance($Processes, [string]$Executable, [string]$CopiesRoot, [string]$UserData, [int]$SessionId) {
    $candidates = @($Processes | Where-Object {
        $_.SessionId -eq $SessionId -and $_.ExecutablePath -and
        $_.CommandLine -notmatch '(?:^|\s)--type(?:=|\s)' -and
        (Get-LauncherProfile $_.CommandLine) -eq $UserData
    })
    $current = @($candidates | Where-Object { $_.ExecutablePath -eq $Executable })
    if ($current.Count -gt 0) { return $current[0] }
    # Only GUI entries directly inside owned copies can share this UI profile.
    foreach ($process in $candidates) {
        $path = [IO.Path]::GetFullPath($process.ExecutablePath)
        $app = Split-Path -Parent $path
        if ((Split-Path -Parent $app) -eq $CopiesRoot -and
            (Split-Path -Leaf $path) -eq (Split-Path -Leaf $Executable) -and
            (Test-Path -LiteralPath (Join-Path $app 'resources\app.asar'))) {
            return $process
        }
    }
    return $null
}

function Show-LauncherWindow($Instance) {
    try {
        $process = Get-Process -Id $Instance.ProcessId -ErrorAction Stop
        if ($process.Path -ne $Instance.ExecutablePath -or $process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
        if (-not ('CodexZhWindow' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CodexZhWindow {
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
        }
        $handle = $process.MainWindowHandle
        if ([CodexZhWindow]::IsIconic($handle)) { [void][CodexZhWindow]::ShowWindowAsync($handle, 9) }
        return [CodexZhWindow]::SetForegroundWindow($handle)
    } catch { return $false }
}

function Send-LauncherStart([string]$Executable, [string]$UserData, [string]$CodexHome) {
    $previousHome = $env:CODEX_HOME
    $previousData = $env:CODEX_ELECTRON_USER_DATA_PATH
    try {
        $env:CODEX_HOME = $CodexHome
        $env:CODEX_ELECTRON_USER_DATA_PATH = $UserData
        Start-Process -FilePath $Executable -WorkingDirectory (Split-Path -Parent $Executable) -WindowStyle Hidden -ArgumentList ('--user-data-dir="' + $UserData + '"') | Out-Null
    } finally {
        $env:CODEX_HOME = $previousHome
        $env:CODEX_ELECTRON_USER_DATA_PATH = $previousData
    }
}

function Wait-LauncherInstance([string]$Executable, [string]$CopiesRoot, [string]$UserData, [int]$SessionId) {
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        $instance = Find-LauncherInstance (Get-LauncherProcesses) $Executable $CopiesRoot $UserData $SessionId
        if ($instance) {
            Start-Sleep -Seconds 2
            $stable = Find-LauncherInstance (Get-LauncherProcesses) $Executable $CopiesRoot $UserData $SessionId
            if ($stable -and $stable.ProcessId -eq $instance.ProcessId) { return $stable }
        }
    }
    throw '没有确认中文兼容版正常启动，请运行检查状态并保留诊断报告。'
}

function Save-LauncherResult([string]$Root, $Result) {
    try {
        $Result | Add-Member -NotePropertyName time -NotePropertyValue (Get-Date).ToString('o') -Force
        [IO.File]::WriteAllText((Join-Path $Root 'last-launch.json'), ($Result | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    } catch { } # Diagnostic failures must not block startup.
}

function Invoke-ChineseLauncher([string]$Root) {
    $Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $record = Get-Content -LiteralPath (Join-Path $Root 'active-copy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $copies = Join-Path $Root 'copies'
    $exe = [IO.Path]::GetFullPath($record.Executable)
    $app = [IO.Path]::GetFullPath($record.AppDirectory).TrimEnd('\')
    if ((Split-Path -Parent $exe) -ne $app -or (Split-Path -Parent $app) -ne $copies -or
        (Split-Path -Leaf $exe) -notmatch '^(ChatGPT|Codex)\.exe$' -or
        -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw '中文兼容副本丢失或路径异常，请重新运行一键汉化。'
    }
    $userData = Join-Path $Root 'user-data'
    $sessionId = (Get-Process -Id $PID).SessionId
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($userData.ToLowerInvariant()))).Replace('-', '') }
    finally { $sha.Dispose() }
    $mutex = [Threading.Mutex]::new($false, ('Local\CodexZhLauncher_' + $key))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { return [pscustomobject]@{ result = 'launch-in-progress' } }
        $instance = Find-LauncherInstance (Get-LauncherProcesses) $exe $copies $userData $sessionId
        $action = 'started-current'
        if ($instance) {
            $action = if ($instance.ExecutablePath -eq $exe) { 'reused-current' } else { 'reused-running-copy' }
            if (-not (Show-LauncherWindow $instance)) {
                # Ask the existing app to reopen its tray window using its single-instance handler.
                Send-LauncherStart $instance.ExecutablePath $userData $record.CodexHome
                $instance = Wait-LauncherInstance $instance.ExecutablePath $copies $userData $sessionId
                [void](Show-LauncherWindow $instance)
            }
        } else {
            Send-LauncherStart $exe $userData $record.CodexHome
            $instance = Wait-LauncherInstance $exe $copies $userData $sessionId
            [void](Show-LauncherWindow $instance)
        }
        $result = [pscustomobject]@{ result = $action; selectedExecutable = $exe; runningExecutable = $instance.ExecutablePath; processId = $instance.ProcessId }
        Save-LauncherResult $Root $result
        return $result
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $StateRoot) { $StateRoot = Split-Path -Parent $PSScriptRoot }
try {
    Invoke-ChineseLauncher $StateRoot | Out-Null
    exit 0
} catch {
    Save-LauncherResult $StateRoot ([pscustomobject]@{ result = 'failed'; error = $_.Exception.Message })
    if ($NoPopup) { [Console]::Error.WriteLine($_.Exception.Message) }
    else {
        $shell = New-Object -ComObject WScript.Shell
        [void]$shell.Popup($_.Exception.Message, 0, 'Codex 中文版', 16)
    }
    exit 1
}
