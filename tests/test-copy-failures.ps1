#Requires -Version 5.1
param([string]$InstallerPath = '')
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-copy-failures-'+[guid]::NewGuid().ToString('N'))
$lock=$null
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
try {
    if (-not $InstallerPath) { $InstallerPath=Join-Path $PSScriptRoot '..\scripts\install_windows.ps1' }
    $app=Join-Path $root 'source'
    [void][IO.Directory]::CreateDirectory((Join-Path $app 'resources'))
    . $InstallerPath -CodexHome (Join-Path $root 'home') -NoRestart -SkipPlugins
    $asar=Join-Path $app 'resources\app.asar'
    [IO.File]::WriteAllText($asar,'synthetic archive for copy boundary tests')
    [IO.File]::WriteAllText((Join-Path $app 'ChatGPT.exe'),'synthetic executable: never launched')
    $blocked=Join-Path $app 'resources\blocked.dat'
    [IO.File]::WriteAllText($blocked,'locked dependency')
    # This suite tests copying and publication boundaries only. Actual ASAR
    # patching is exercised by test-workflow and test-runtime.
    function Set-LocaleCompatibility { return 1 }
    $source=[pscustomobject]@{AppDirectory=$app;Version='fixture'}
    $original=(Get-FileHash -LiteralPath $asar).Hash
    $active=New-CompatibilityCopy $source
    $active.ToolVersion='previous-version-fixture'
    Write-TextFile (Join-Path $toolStateRoot 'active-copy.json') ($active | ConvertTo-Json)
    $previousRecord=[IO.File]::ReadAllText((Join-Path $toolStateRoot 'active-copy.json'))
    $lock=[IO.File]::Open($blocked,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $failure=$null
    try { New-CompatibilityCopy $source | Out-Null } catch { $failure=$_ }
    $lock.Dispose(); $lock=$null
    Assert ($null -ne $failure -and $failure.Exception.Data['copyStage'] -eq 'copy-files') 'Actual locked dependency must cause a copy failure'
    $copyLog=$failure.Exception.Data['copyLog']
    Assert ((Get-Content -LiteralPath $copyLog -Raw).Contains('blocked.dat')) 'Robocopy log must identify the actual unreadable file'
    Assert ([IO.File]::ReadAllText((Join-Path $toolStateRoot 'active-copy.json')) -ceq $previousRecord) 'Failed upgrade must retain existing active record'
    Assert ((Get-ActiveCompatibilityCopy).Executable -eq $active.Executable) 'Previously installed app must remain usable'
    Write-Host '[PASS] real locked-file failure: original reason and file log preserved, previous installation retained'

    $script:corruptOnce=$true
    function Get-FileHash {
        param([string]$LiteralPath,[string]$Algorithm='SHA256')
        if ($script:corruptOnce -and (Test-PathWithin $LiteralPath (Join-Path $toolStateRoot 'copies')) -and
            (Split-Path -Leaf $LiteralPath) -eq 'app.asar') {
            $script:corruptOnce=$false
            [IO.File]::AppendAllText($LiteralPath,'corruption injected at the post-copy hash boundary')
        }
        Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
    }
    $failure=$null
    try { New-CompatibilityCopy $source | Out-Null } catch { $failure=$_ }
    Assert ($null -ne $failure -and $failure.Exception.Data['copyStage'] -eq 'verify-copy') 'Corrupted copy must fail integrity verification'
    Assert ((Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $asar).Hash -eq $original) 'Source archive must remain unchanged'
    Assert ([IO.File]::ReadAllText((Join-Path $toolStateRoot 'active-copy.json')) -ceq $previousRecord) 'Corrupted copy must not replace working installation'
    Write-Host '[PASS] injected copy corruption: integrity failure, unchanged source and previous installation'
} finally {
    if ($lock) { $lock.Dispose() }
    $resolved=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-copy-failures-[0-9a-f]{32}$') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
