$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $repository 'windows.cmd')).Replace("`r`n", "`n")
$marker = "`n# NVTH_POWERSHELL_PAYLOAD`n"
$offset = $source.IndexOf($marker)
if ($offset -lt 0) { throw 'Payload marker missing.' }
$header = $source.Substring(0, $offset + $marker.Length)
$payload = $source.Substring($offset + $marker.Length)
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$admin = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-Admin' }, $false)
$start = $payload.IndexOf('# Installation workflow: all installation steps are contained in this file.')
$end = $payload.LastIndexOf('} catch {')
if ($start -lt 0 -or $end -le $start) { throw 'Workflow boundaries missing.' }
$prefix = $payload.Substring(0, $start)
$suffix = $payload.Substring($end)
$runs = Join-Path $PSScriptRoot ('.runs\click-' + [guid]::NewGuid().ToString('N'))

$directoryWorkflow = $payload.Substring($start, $payload.IndexOf('# Check burpsuite_pro.jar', $start) - $start)
$cases = @(
    @{ Name = "success & space ' quote %PATH% ! unicode-$([char]0x1EC7)"; Admin = $false; Body = 'Write-Host "FIXTURE_STARTED"; exit 0'; Code = 0; Match = 'FIXTURE_STARTED' },
    @{ Name = 'runtime-error'; Admin = $false; Body = 'throw "Fixture failure"'; Code = 1; Match = '[ERROR] [Fixture] Fixture failure' },
    @{ Name = 'native-error'; Admin = $false; Body = 'exit 23'; Code = 23; Match = 'Installation log saved to:' },
    @{ Name = 'access-denied'; Admin = $false; Body = 'throw (New-Object UnauthorizedAccessException("Fixture denied"))'; Code = 5; Match = 'Run as administrator' },
    @{ Name = 'admin-still-denied'; Admin = $true; Body = 'throw (New-Object UnauthorizedAccessException("Fixture denied"))'; Code = 5; Match = 'Access is still denied with Administrator privileges.' },
    @{ Name = 'normal-user-directories'; Admin = $false; Body = $directoryWorkflow + '
Write-Host "DIRECTORIES_READY"; exit 0'; Code = 0; Match = 'DIRECTORIES_READY'; Directories = $true }
)

foreach ($case in $cases) {
    $directory = Join-Path $runs $case.Name
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $predicate = if ($case.Admin) { 'function Test-Admin { return $true }' } else { 'function Test-Admin { return $false }' }
    $mocks = $predicate + @'

function Read-Host {
    param($Prompt)
    if ($Prompt -like 'Enter install directory*') { return (Join-Path (Split-Path $env:NVTH_INSTALLER_PATH) 'installed') }
    Write-Host 'PAUSE_REACHED'
    return ''
}
function Start-Process { throw 'Unexpected process launch or elevation in fixture.' }
$LogPath = Join-Path (Split-Path $env:NVTH_INSTALLER_PATH) 'fixture.log'
'@
    $fixture = $prefix.Replace($admin.Extent.Text, $mocks) + '$installStep = ''Fixture''; ' + $case.Body + "`n" + $suffix
    [IO.File]::WriteAllText((Join-Path $directory 'windows.cmd'), ($header + $fixture).Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /c windows.cmd'
    $info.WorkingDirectory = $directory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(20000)) {
        $process.Kill()
        throw "Fixture timed out: $($case.Name)"
    }
    $output = $stdout.Result + $stderr.Result
    [IO.File]::WriteAllText((Join-Path $directory 'output.txt'), $output)
    if ($process.ExitCode -ne $case.Code -or -not $output.Contains($case.Match)) {
        throw "Failed $($case.Name): expected $($case.Code), got $($process.ExitCode).`n$output"
    }
    if (-not $output.Contains('PAUSE_REACHED')) { throw 'Installer did not pause before closing.' }
    if (Test-Path -LiteralPath (Join-Path $directory 'install-all.ps1')) { throw 'Fixture unexpectedly has a companion PS1.' }
    if ($case.Directories) {
        if (-not (Test-Path -LiteralPath (Join-Path $directory 'installed\\bin')) -or
            -not (Test-Path -LiteralPath (Join-Path $directory 'installed\\data'))) {
            throw 'Normal-user installation directories were not created.'
        }
        if (Get-ChildItem -LiteralPath (Join-Path $directory 'installed') -Recurse -Force -Filter '.write-check-*') {
            throw 'Write probes were not cleaned up.'
        }
    }
    if ($case.Name -eq 'runtime-error' -and $output.Contains('Run as administrator')) {
        throw 'A non-permission error incorrectly requests Administrator privileges.'
    }
    $process.Dispose()
    Write-Host "PASS: $($case.Name)"
}
Write-Host 'All double-click bootstrap tests passed; no installation or UAC elevation was performed.'
