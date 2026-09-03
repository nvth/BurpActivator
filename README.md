# Burp Suite · nvth's gallery

Install Burp Suite with **Core** on Windows or Linux.

| Platform | Installer | Run |
| --- | --- | --- |
| Windows | [windows.cmd](https://github.com/nvth/burpsuite/raw/refs/heads/main/windows.cmd) | Double-click |
| Linux | [linux.sh](https://github.com/nvth/burpsuite/raw/refs/heads/main/linux.sh) | `sudo bash linux.sh` |

Download only the installer for your platform. Each script contains its own
installation code and downloads the required files.

## Windows

1. Download `windows.cmd` and double-click it.
2. Choose an installation folder, or press Enter to use
   `%LOCALAPPDATA%\nvth\burpsuite`.
3. Follow the prompts to install portable Java, Core, and Burp Suite.

Installation uses your current permissions and creates a Start Menu shortcut.
If access is denied, choose a writable folder or right-click `windows.cmd`
and select **Run as administrator**, then choose the same folder again.

Requires Windows PowerShell 5.1, `curl.exe`, and internet access for downloads.
Logs are saved in `%LOCALAPPDATA%\nvth\logs`. Close Burp to let the installer
finish; press Enter to close the installer window.

## Linux

Download `linux.sh`, open a terminal in its folder, and run:

```bash
sudo bash linux.sh
```

Follow the prompts. The script installs portable Java and creates the application
launcher. The Linux installer requires sudo for its system setup.

## Core

Both installers use
[core.jar from release v2026.3.3](https://github.com/nvth/burpsuite/releases/download/v2026.3.3/core.jar).
To supply your own copy, place `core.jar` beside the installer. It is copied
to `data/core.jar`; otherwise the installer downloads it when missing.

Existing installed JARs are retained unless a local replacement is supplied.

## Uninstall

On Windows, follow `UNINSTALL.txt` in the installation folder. Run the generated
`uninstall.ps1` normally; use Administrator privileges if the folder requires them.

## License

See [LICENSE](LICENSE).
