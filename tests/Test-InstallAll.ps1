$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repository 'tools\windows.ps1'
$source = [IO.File]::ReadAllText($scriptPath)
$shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runs = Join-Path $PSScriptRoot ('.runs\standalone-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runs -Force | Out-Null

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'The standalone installer must parse in Windows PowerShell 5.1.'
Assert-True ($source -notmatch '(?<!un)install\.(cmd|ps1)') 'The standalone installer references an old installer file.'
Assert-True ($source -notmatch 'Set-ExecutionPolicy.*-Scope (LocalMachine|CurrentUser)') 'The standalone installer must not change persistent execution policy.'

# Keep real preflight/error handling; stub only privileges and installation work in isolated copies.
$workflowMarker = '# Installation workflow: all installation steps are contained in this file.'
$start = $source.IndexOf($workflowMarker)
$end = $source.LastIndexOf('} catch {')
Assert-True ($start -gt 0 -and $end -gt $start) 'Installer error-handling boundaries were not found.'
$prefix = $source.Substring(0, $start)
$suffix = $source.Substring($end)
$admin = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-Admin' }, $false)

$cases = @(
    @{ Name = 'success & space'; Admin = $true; Body = 'Write-Host "Fixture installation completed"; exit 0'; Expected = 0; Started = $true },
    @{ Name = 'runtime-error'; Admin = $true; Body = 'throw "Fixture extraction failed"'; Expected = 1; Started = $true },
    @{ Name = 'native-exit-code'; Admin = $true; Body = 'Write-Host "Fixture download failed"; exit 23'; Expected = 23; Started = $true },
    @{ Name = 'cancel'; Admin = $true; Body = 'Write-Host "Installation canceled by user."; exit 1'; Expected = 1; Started = $true },
    @{ Name = 'no-admin'; Admin = $false; Body = 'Write-Host "Normal user installation completed"; exit 0'; Expected = 0; Started = $true },
    @{ Name = 'access-denied'; Admin = $false; Body = 'throw (New-Object UnauthorizedAccessException("Fixture denied"))'; Expected = 5; Started = $true },
    @{ Name = 'invalid-log'; Admin = $true; Body = 'throw "This body must not run"'; Expected = 1; Started = $false; BadLog = $true }
)

foreach ($case in $cases) {
    $directory = Join-Path $runs $case.Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $predicate = if ($case.Admin) { 'function Test-Admin { return $true }' } else { 'function Test-Admin { return $false }' }
    $fixturePrefix = $prefix.Replace($admin.Extent.Text, $predicate)
    $fixtureBody = '$installStep = ''Fixture install''; Add-Content -LiteralPath (Join-Path $PSScriptRoot ''started.txt'') -Value ''started''; ' + $case.Body + "`r`n"
    $fixturePath = Join-Path $directory 'install-all.ps1'
    [IO.File]::WriteAllText($fixturePath, $fixturePrefix + $fixtureBody + $suffix, [Text.Encoding]::UTF8)
    $stdout = Join-Path $directory 'stdout.txt'
    $stderr = Join-Path $directory 'stderr.txt'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $fixturePath
    if ($case.BadLog) { $arguments += ' -LogPath .' } else { $arguments += ' -LogPath logs\fixture.log' }
    $process = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $actualExit = $process.ExitCode
    $process.Dispose()
    Assert-True ($actualExit -eq $case.Expected) "$($case.Name): expected exit $($case.Expected), got $actualExit. See $directory"
    Assert-True ((Test-Path -LiteralPath (Join-Path $directory 'started.txt')) -eq $case.Started) "$($case.Name): wrong preflight/installation order"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $directory 'install.cmd'))) 'Fixture unexpectedly needs install.cmd'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $directory 'install.ps1'))) 'Fixture unexpectedly needs install.ps1'
    if (-not $case.BadLog) {
        $log = Get-ChildItem -LiteralPath (Join-Path $directory 'logs') -Filter '*.log' | Select-Object -First 1
        Assert-True ($null -ne $log) 'Automatic log was not created'
        $content = Get-Content -LiteralPath $log.FullName -Raw
        Assert-True ($content -match 'Installation log saved to:') 'Finally block did not finish the transcript'
        if ($case.Name -eq 'runtime-error') {
            Assert-True ($content -match '\[ERROR\] \[Fixture install\].*Fixture extraction failed.*line') 'Exception log lacks stage/error/line details'
        }
        if ($case.Name -eq 'access-denied') {
            Assert-True ($content -match 'Run as administrator') 'Access denial must explain how to retry with Administrator privileges.'
        }
    }
    Write-Host "PASS: $($case.Name) (exit $actualExit)"
}
Write-Host "Standalone installer checks passed. No real installation was run. Fixtures: $runs"
