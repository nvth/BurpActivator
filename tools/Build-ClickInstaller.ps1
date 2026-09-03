$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'windows.ps1')).Replace("`r`n", "`n")

# Read the embedded payload directly, so no companion file or temporary script is needed.
$reader = '$text=[IO.File]::ReadAllText($env:NVTH_INSTALLER_PATH).Replace([string][char]13,'''');$marker=[string][char]10+''# NVTH_POWERSHELL_PAYLOAD''+[char]10;$offset=$text.IndexOf($marker);if($offset -lt 0){throw ''Embedded installer payload was not found.''};& ([scriptblock]::Create($text.Substring($offset+$marker.Length)))'
$bootstrap = 'try{' + $reader + '}catch{Write-Host (''[ERROR] [Bootstrap] ''+$_.Exception.Message);Read-Host ''Press Enter to close this window''|Out-Null;exit 1}'

$location = @'
$installerDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($env:NVTH_INSTALLER_PATH))
'@
$source = $source.Replace('$LogPath = Join-Path $PSScriptRoot $LogPath', '$LogPath = Join-Path $installerDirectory $LogPath')
$source = $source.Replace('$scriptDir = Split-Path -Parent $PSScriptRoot', '$scriptDir = $installerDirectory')
$boundary = $source.IndexOf("`ntry {")
if ($boundary -lt 0) { throw 'Installer preflight boundary was not found.' }
$source = $source.Insert($boundary + 1, $location + "`n")
$lastBrace = $source.LastIndexOf('}')
$source = $source.Insert($lastBrace, "    Read-Host 'Press Enter to close this window' | Out-Null`n")
$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }

$header = @'
@echo off
setlocal DisableDelayedExpansion
set "NVTH_INSTALLER_PATH=%~f0"
if not exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    echo [ERROR] Windows PowerShell was not found on this computer.
    pause
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "__BOOTSTRAP__"
exit /b %ERRORLEVEL%
# NVTH_POWERSHELL_PAYLOAD
'@
$output = ($header.Replace('__BOOTSTRAP__', $bootstrap) + "`n" + $source).Replace("`r`n", "`n").Replace("`n", "`r`n")
$destination = Join-Path $repository 'windows.cmd'
[IO.File]::WriteAllText($destination, $output, (New-Object Text.UTF8Encoding($false)))
Write-Host "Built standalone double-click installer: $destination"
