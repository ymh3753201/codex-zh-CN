#Requires -Version 5.1
param([string]$ReportPath = '')
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $project 'resources\release.json') -Raw -Encoding UTF8 | ConvertFrom-Json).release
$zip = Join-Path $project "dist\codex-zh-CN-v$version.zip"
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-zh-matrix-' + [guid]::NewGuid().ToString('N'))
$report = [ordered]@{
    startedAt=(Get-Date).ToString('o'); toolVersion=$version; archiveSha256=(Get-FileHash -LiteralPath $zip).Hash
    powershellVersion=$PSVersionTable.PSVersion.ToString(); windowsVersion=[Environment]::OSVersion.Version.ToString()
    scope='Real packaged installer and Robocopy; synthetic app resources; simulated profile directory names and process-local .NET path modes. Not separate Windows accounts or Windows 10 hardware.'
    cases=@(); passed=$false
}
if (-not $ReportPath) { $ReportPath = Join-Path $project "docs\student-matrix-v$version.json" }
try {
    [void][IO.Directory]::CreateDirectory($root)
    $package = Join-Path $root '解压后的安装包 (2)'
    Expand-Archive -LiteralPath $zip -DestinationPath $package
    $installer = Join-Path $package 'scripts\install_windows.ps1'
    $index=0
    foreach ($profile in @('asus', 'Administrator', '学生 A[01]')) {
        foreach ($mode in @('Modern', 'Legacy', 'ModernBlocked', 'LegacyUnblocked')) {
            $index++
            $resultPath = Join-Path $root "result-$index.json"
            $outputPath = Join-Path $root "output-$index.txt"
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-workflow.ps1') `
                -InstallerPath $installer -LegacyLongPaths -PathHandling $mode -DataFolder $profile -CompareOldTraversal -ResultPath $resultPath *> $outputPath
            $code=$LASTEXITCODE
            if (Test-Path -LiteralPath $resultPath) { $case = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
            else { $case=[pscustomobject]@{passed=$false;profile=$profile;pathHandling=$mode;oldTraversalPassed=$null} }
            $case | Add-Member -NotePropertyName exitCode -NotePropertyValue $code
            if ($code -ne 0 -or -not $case.passed) {
                $case | Add-Member -NotePropertyName failureOutput -NotePropertyValue (Get-Content -LiteralPath $outputPath -Raw)
                $report.cases += $case
                throw "Matrix failed: $profile / $mode. See $ReportPath"
            }
            $report.cases += $case
            Write-Host "[PASS $index/12] $profile / $mode; old traversal passed=$($case.oldTraversalPassed), new workflow passed=True"
        }
    }
    $oldFailures=@($report.cases | Where-Object { $_.oldTraversalPassed -eq $false })
    $oldSuccesses=@($report.cases | Where-Object { $_.oldTraversalPassed -eq $true })
    if ($oldFailures.Count -eq 0 -or $oldSuccesses.Count -eq 0) { throw 'Comparison must reproduce both success and failure of the old traversal' }
    $report.passed=$true
    Write-Host '[PASS] all 12 packaged workflows; old traversal succeeds or fails depending on path handling'
} finally {
    $report.finishedAt=(Get-Date).ToString('o')
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $resolved=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^codex-zh-matrix-[0-9a-f]{32}$') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
