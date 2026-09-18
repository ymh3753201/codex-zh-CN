#Requires -Version 5.1
param([string]$LauncherPath = '')
$ErrorActionPreference = 'Stop'
if (-not $LauncherPath) { $LauncherPath = Join-Path $PSScriptRoot '..\scripts\start-zh.ps1' }
. $LauncherPath
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-launcher-' + [guid]::NewGuid().ToString('N'))
function Assert($Value, $Message) { if (-not $Value) { throw $Message } }
try {
    $state = Join-Path $root '中文 数据[测试]'
    $copies = Join-Path $state 'copies'
    $app = Join-Path $copies 'current'
    $oldApp = Join-Path $copies 'old'
    foreach ($dir in @($app, $oldApp)) {
        [void][IO.Directory]::CreateDirectory((Join-Path $dir 'resources'))
        [IO.File]::WriteAllText((Join-Path $dir 'ChatGPT.exe'), 'fixture')
        [IO.File]::WriteAllText((Join-Path $dir 'resources\app.asar'), 'fixture')
    }
    $exe = Join-Path $app 'ChatGPT.exe'
    $oldExe = Join-Path $oldApp 'ChatGPT.exe'
    $profile = Join-Path $state 'user-data'
    $sid = (Get-Process -Id $PID).SessionId
    $record = @{ Executable=$exe; AppDirectory=$app; CodexHome=$root; SourceDirectory='C:\official' }
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $state 'active-copy.json') -Encoding UTF8
    function New-Instance($Path, $Data=$profile, $Session=$sid, $Extra='') {
        [pscustomobject]@{ ExecutablePath=$Path; ProcessId=123; SessionId=$Session; CommandLine=('"' + $Path + '" --user-data-dir="' + $Data + '" ' + $Extra) }
    }
    $official = New-Instance 'C:\official\ChatGPT.exe' 'C:\official-profile'
    $current = New-Instance $exe
    $old = New-Instance $oldExe
    function Get-LauncherProcesses { $script:snapshot }
    function Show-LauncherWindow($Instance) { $script:shown=$Instance.ExecutablePath; return $script:canShow }
    function Send-LauncherStart($Executable, $UserData, $CodexHome) {
        $script:sent += $Executable
        $script:snapshot = @($script:snapshot) + @(New-Instance $Executable $UserData)
    }
    function Start-Sleep { }
    $script:canShow=$true
    $script:sent=@()
    $script:snapshot=@($official,$current)
    $result=Invoke-ChineseLauncher $state
    Assert ($result.result -eq 'reused-current' -and $script:sent.Count -eq 0 -and $script:shown -eq $exe) 'Existing Chinese window must be activated despite official background process'
    $script:snapshot=@($official)
    $result=Invoke-ChineseLauncher $state
    Assert ($result.result -eq 'started-current' -and $script:sent[-1] -eq $exe) 'Official background must not block startup'
    $script:sent=@()
    $script:snapshot=@($official,$old)
    $result=Invoke-ChineseLauncher $state
    Assert ($result.result -eq 'reused-running-copy' -and $script:sent.Count -eq 0 -and $script:shown -eq $oldExe) 'Reuse old running copy sharing the profile without terminating tasks'
    $script:canShow=$false
    $result=Invoke-ChineseLauncher $state
    Assert ($script:sent[-1] -eq $oldExe) 'Tray reopen must target running old copy, not new copy'
    $script:canShow=$true
    foreach ($ignored in @(
        (New-Instance $exe $profile ($sid+1)),
        (New-Instance $exe $profile $sid '--type=renderer'),
        (New-Instance $oldExe 'C:\different-profile'),
        (New-Instance (Join-Path $app 'Codex.exe')),
        (New-Instance (Join-Path $oldApp 'resources\codex.exe'))
    )) {
        $script:snapshot=@($official,$ignored)
        $script:sent=@()
        $result=Invoke-ChineseLauncher $state
        Assert ($result.result -eq 'started-current' -and $script:sent[-1] -eq $exe) 'Helper, CLI, different profile and other session must not intercept launch'
    }
    foreach ($arg in @('--user-data-dir="' + $profile + '"', '"--user-data-dir=' + $profile + '"', '--user-data-dir "' + $profile + '"')) {
        Assert ((Get-LauncherProfile ('app.exe ' + $arg)) -eq $profile) 'Quoted profile parsing failed'
    }
    function Send-LauncherStart { }
    $script:snapshot=@($official)
    $failed=$false
    try { Invoke-ChineseLauncher $state | Out-Null } catch { $failed=$_.Exception.Message -like '*没有确认*' }
    Assert $failed 'Failed startup must not report success'
    $record.Executable='C:\outside\ChatGPT.exe'
    $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $state 'active-copy.json') -Encoding UTF8
    $failed=$false
    try { Invoke-ChineseLauncher $state | Out-Null } catch { $failed=$_.Exception.Message -like '*路径异常*' }
    Assert $failed 'Reject paths outside owned copy'
    Write-Host '[PASS] launcher: official background, repeated open, shared-profile old copy, tray reopen, process filtering, quoted paths, failure propagation'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-launcher-[0-9a-f]{32}$') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
