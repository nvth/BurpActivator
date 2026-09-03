# Burp Suite — nvth's gallery

Windows and Linux installers using **Core** from
[release v2026.3.3](https://github.com/nvth/burpsuite/releases/tag/v2026.3.3).

## Windows

Download `windows.cmd` and double-click it. This single file contains the
installer; no companion PowerShell script is required.

- Runs with your current permissions. Default folder: `%LOCALAPPDATA%\nvth\burpsuite`.
- Creates a Start Menu shortcut for the current user.
- On access denial, choose a writable folder or use **Run as administrator**
  and select the same installation folder again.
- Logs are saved to `%LOCALAPPDATA%\nvth\logs`. The window waits for Enter
  before closing so you can read errors.
- Requires Windows PowerShell 5.1, `curl.exe`, and internet access for missing downloads.
- Execution policy is set only for the installer process. Organization policies still apply.

The installer downloads portable Java when needed, prepares the application,
and starts Core and Burp. Close Burp to let the installer finish.

## Linux

Download `linux.sh` and run:

```bash
sudo bash linux.sh
```

The Linux installer uses its existing system setup workflow and requires sudo.
It downloads portable Java and prepares the desktop launcher.

## Core

Both installers download
[core.jar](https://github.com/nvth/burpsuite/releases/download/v2026.3.3/core.jar)
when it is missing from the installation. You can also place a replacement
`core.jar` beside the installer; it is copied to `data/core.jar`.
Existing installed JARs are retained unless a local replacement is supplied.

Release binaries are kept on GitHub Releases instead of in this repository.
Ubuntu runtime operation has not been tested here.

## Errors and uninstall

Windows errors include the installation step, message, and script line.
Exit codes: `0` success, `1` general error or cancellation, `5` permission
error; native command failures retain their exit codes. Optional icon or shortcut
failures may be warnings. Partial installations are not automatically rolled back.

To uninstall on Windows, follow `UNINSTALL.txt` in the installation directory.
Run the generated `uninstall.ps1` normally; use Administrator privileges only
if the installation's permissions require them.

## Maintenance

Repository files:

- `windows.cmd`, `linux.sh`: distributable installers.
- `tools/windows.ps1`: editable Windows installer source.
- `tools/Build-ClickInstaller.ps1`: rebuilds `windows.cmd`.
- `tests/`: isolated installer checks, without downloads, real installation, or UAC.
- `LICENSE`: project license.

After editing `tools/windows.ps1`, rebuild and check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-ClickInstaller.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InstallAll.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ClickInstaller.ps1
```

Check Linux syntax with `bash -n linux.sh`.
Generated test runs, logs, and local Core binaries are ignored by Git.
