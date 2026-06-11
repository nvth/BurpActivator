# Burp Suite Windows Installer

Windows installer script for Burp Suite. It uses `install.cmd` as a bootstrapper to handle PowerShell Execution Policy, lets you choose the installation directory, and uses a dedicated portable JDK 21 for Burp only.

> Use this only with a valid Burp Suite license. This project should not be used to bypass software licensing terms or access controls.

## Main Files

- `install.cmd`: the Windows entry point. It temporarily updates PowerShell Execution Policy, runs `install.ps1`, then restores the policy to `Default`.
- `install.ps1`: the main Windows installation script.
- `install-linux.sh`: Linux installer script.
- `capsule_windows.md`: extra Windows notes and screenshots.

## Requirements

- Windows 10/11.
- Administrator privileges.
- Internet connection to download required files.
- Java 21 does not need to be installed globally. The script downloads a portable JDK 21 inside the selected install directory.

## Windows Installation

1. Clone or download this repository.

   Example:

   ```powershell
   git clone https://github.com/nvth/burpsuite.git
   ```

2. Make sure the Windows installer files are present in the repository folder:

   ```text
   install.cmd
   install.ps1
   capsule_windows.md
   ```

3. Open the repository folder, for example:

   ```text
   C:\Users\admin\Downloads\burpsuite-master
   ```

4. Right-click `install.cmd` and choose **Run as administrator**.

5. When prompted for the install directory:

   ```text
   Default install directory: C:\burpsuite_nvth
   Enter install directory, or press Enter to use default:
   ```

   You can:

   - Press Enter to use the default `C:\burpsuite_nvth`.
   - Enter an absolute path, for example `D:\Tools\BurpSuite`.
   - Enter a relative path, for example `burp_install`; the script will create it next to `install.ps1`.

6. The script downloads the required files, creates launchers, and adds a Start Menu shortcut.

## Execution Policy

Do not run this directly:

```powershell
.\install.ps1
```

If PowerShell script execution is disabled, you may see:

```text
running scripts is disabled on this system
```

Run `install.cmd` as Administrator instead. It automatically runs:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
```

After `install.ps1` finishes, `install.cmd` restores the policy:

```powershell
Set-ExecutionPolicy Default -Scope LocalMachine -Force
```

If restoring the policy fails, the manual command is printed in the console.

## Installed Layout

If you choose `<install-dir>`, the script creates:

```text
<install-dir>\
  bin\
    burp.bat
    BurpSuiteProfessional.vbs
  data\
    burpsuite_pro.jar
    loader.jar
    jdk-21.0.10_windows-x64_bin.zip
    burppro.ico
  jdk\
    bin\
      java.exe
  uninstall.ps1
  UNINSTALL.txt
```

## Portable Java

The script does not install Java globally and does not overwrite the Java version already used by your system.

JDK 21 is downloaded from:

```text
https://github.com/nvth/burpsuite/releases/download/v2024.7.4/jdk-21.0.10_windows-x64_bin.zip
```

It is extracted to:

```text
<install-dir>\jdk
```

All Burp launchers use this local Java runtime:

```text
<install-dir>\jdk\bin\java.exe
```

Your system `PATH`, Java registry entries, and other applications are not modified.

## Running Burp

After installation, start Burp using one of these options:

- Start Menu shortcut: `BurpSuiteProfessional`.
- VBS launcher:

  ```text
  <install-dir>\bin\BurpSuiteProfessional.vbs
  ```

- BAT launcher:

  ```text
  <install-dir>\bin\burp.bat
  ```

## RAM And JVM Settings

The script detects system RAM and creates a JVM memory option:

- Less than 16 GB RAM: uses `-Xmx4G`.
- 16 GB to 32 GB RAM: uses `-Xmx8G`.
- More than 32 GB RAM: leaves JVM memory at default.

If Burp is too heavy for your machine, edit:

```text
<install-dir>\bin\burp.bat
```

For example, change:

```bat
-Xmx4G
```

to:

```bat
-Xmx2G
```

or remove the `-Xmx...` option entirely.

## Uninstall

Open PowerShell as Administrator, then run:

```powershell
<install-dir>\uninstall.ps1
```

The uninstall script removes:

- Start Menu shortcut, if present.
- `bin` directory.
- `data` directory.
- `jdk` directory.
- The main install directory.

## Troubleshooting

### `running scripts is disabled on this system`

Do not run `install.ps1` directly. Run `install.cmd` with **Run as administrator**.

### `This installer must be run as Administrator`

Close the current window, right-click `install.cmd`, then choose **Run as administrator**.

### Execution Policy cannot be restored

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy Default -Scope LocalMachine -Force
```

Check the current policy list:

```powershell
Get-ExecutionPolicy -List
```

### Change the install directory

Run `install.cmd` again and enter the new directory when prompted. The script will create launchers pointing to the selected directory.

## Linux

This README focuses on the updated Windows flow. For Linux, run:

```bash
sudo bash install-linux.sh
```

## License

See `LICENSE`.
