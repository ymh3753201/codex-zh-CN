#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-regression-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    [void][IO.Directory]::CreateDirectory($root)
    $envBefore = $env:CODEX_HOME
    $env:CODEX_HOME = $root
    . (Join-Path $PSScriptRoot '..\scripts\install_windows.ps1') -NoRestart
    Assert ($CodexHome -eq $root) 'CODEX_HOME override must be respected'
    $env:CODEX_HOME = $envBefore
    $config = Join-Path $root 'config.toml'
    $cases = @(
        ('[desktop]' + "`n" + 'theme = "dark"' + "`n" + '[[agents]]' + "`n" + 'localeOverride = "en-US"'),
        ('instructions = """' + "`n" + '[desktop]' + "`n" + 'localeOverride = "keep-this-text"' + "`n" + '"""' + "`n" + '[desktop]' + "`n" + 'localeOverride = "en-US"'),
        ('[desktop] # comment' + "`n" + "localeOverride = 'en-US' # previous" + "`n" + '[other]' + "`n" + 'text = "中文"')
    )
    foreach ($case in $cases) {
        [IO.File]::WriteAllText($config, $case)
        Set-DesktopLocale 'zh-CN'
        Assert ((Get-DesktopLocale) -eq 'zh-CN') 'Effective desktop locale must be Chinese'
        $after = [IO.File]::ReadAllText($config)
        if ($case.Contains('keep-this-text')) { Assert ($after.Contains('keep-this-text')) 'Multiline instructions must remain unchanged' }
        if ($case.Contains('[[agents]]')) { Assert ($after.Contains('localeOverride = "en-US"')) 'Array-table value must remain unchanged' }
        $first = [IO.File]::ReadAllText($config)
        Set-DesktopLocale 'zh-CN'
        Assert ([IO.File]::ReadAllText($config) -ceq $first) 'Repeated writes must be idempotent'
    }
    foreach ($case in @('desktop.localeOverride = "en-US"', ('["desktop"]' + "`n" + 'localeOverride = "en-US"'), ('[desktop]' + "`n" + 'localeOverride = "en-US"' + "`n" + 'localeOverride = "fr-FR"'))) {
        [IO.File]::WriteAllText($config, $case)
        $failed = $false
        try { Set-DesktopLocale 'zh-CN' } catch { $failed = $true }
        Assert $failed 'Ambiguous TOML must be rejected'
        Assert ([IO.File]::ReadAllText($config) -ceq $case) 'Rejected config must remain unchanged'
    }
    Assert (Test-PathWithin 'C:\Codex\app.exe' 'C:\Codex') 'Child path should match'
    Assert (-not (Test-PathWithin 'C:\Codex-old\app.exe' 'C:\Codex')) 'Sibling prefix must not match'
    # Mock OS/process boundaries, not the process selection implementation.
    $session = (Get-Process -Id $PID).SessionId
    function Get-CimInstance { @(
        [pscustomobject]@{ SessionId=$session; ExecutablePath='C:\Codex\ChatGPT.exe'; ProcessId=111; Name='ChatGPT.exe' },
        [pscustomobject]@{ SessionId=$session; ExecutablePath='C:\Other\ChatGPT.exe'; ProcessId=222; Name='ChatGPT.exe' },
        [pscustomobject]@{ SessionId=$session; ExecutablePath='C:\Tools\codex.exe'; ProcessId=333; Name='codex.exe' },
        [pscustomobject]@{ SessionId=($session+1); ExecutablePath='C:\Codex\ChatGPT.exe'; ProcessId=444; Name='ChatGPT.exe' }
    ) }
    $selected = @(Get-CodexProcesses 'C:\Codex')
    Assert ($selected.Count -eq 1 -and $selected[0].ProcessId -eq 111) 'Only the selected app in this session may be stopped'
    function Start-Sleep {}
    function Stop-Process {}
    $failed = $false
    try { Stop-Codex 'C:\Codex' } catch { $failed = $true }
    Assert $failed 'Failure to stop must not be reported as success'
    function Get-CimInstance { @() }
    function Start-Process {}
    $failed = $false
    try { Start-Codex ([pscustomobject]@{ AppDirectory='C:\Codex'; Executable='C:\Codex\ChatGPT.exe'; AppUserModelId='test!App' }) } catch { $failed = $true }
    Assert $failed 'Failed activation must not be reported as a successful restart'
    Write-Host '[PASS] home, TOML preservation, backups, process isolation, stop/start failure regressions'
} finally {
    $env:CODEX_HOME = $envBefore
    $resolved = [IO.Path]::GetFullPath($root)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-regression-[0-9a-f]{32}$') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
