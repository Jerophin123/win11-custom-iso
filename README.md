# Windows 11 Custom ISO Builder

Builds a debloated, privacy-focused, fully unattended Windows 11 Pro ISO from an official Windows 11 ISO. It has its own wallpapers and a complete custom sound set.

## Features

- **Unattended install:** no EULA, edition, region, keyboard, network, Microsoft-account or privacy pages.
  - A **local** admin account is created automatically.
  - The only screen left is "Where do you want to install Windows?", unless you pass `-AutoWipeDisk0`.
- **Single edition:** only the edition you choose is kept, which makes the image smaller and removes the edition picker.
- **Debloated:** removes Copilot, Xbox, Bing apps, Teams, Outlook, Clipchamp, Widgets, Phone Link, Recall, OneDrive auto-install and legacy optional features.
- **Privacy:** turns off:
  - telemetry and diagnostics;
  - location;
  - advertising ID and activity history;
  - Start and lock-screen ads and suggestions;
  - web search in Start;
  - error reporting and inking/typing collection;
  - Delivery Optimization P2P;
  - Edge telemetry;
  - BitLocker auto-encryption.
- **Lighter and faster:**
  - disables SysMain, the Search indexer, diagnostics and other idle services;
  - stops Store apps running in the background;
  - turns off animations and transparency;
  - removes the startup delay;
  - shrinks the hibernation file while keeping Fast Startup;
  - shrinks WinSxS with `/ResetBase`.
- **Wallpapers:** removes all stock wallpapers and themes. Installs:
  - a light theme;
  - a dark theme, also used for the lock screen;
  - one extra theme for each other image in `wallpapers/`.
- **Sounds:** replaces every Windows sound with the generated set in `sounds/set`:
  - event `.wav` files, including the dark-mode copies;
  - navigation `.raw` sounds;
  - alarms and ringtones.
  - The startup sound is replaced inside Windows itself (WAVE 5080 in `SystemResources\imageres.dll.mun`), so it plays at the normal moment, with Fast Startup still on.
- Windows Update, Defender and SmartScreen are **kept** for security.

## Requirements

- Windows 10 or 11 host and an **elevated** PowerShell.
- [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install), **Deployment Tools** feature, for `oscdimg.exe`. Alternatively, put `oscdimg.exe` next to the script.
- An official Windows 11 ISO.
- About 3× the ISO size of free disk space.
- Optional: Python 3 with `numpy` and `Pillow`, to regenerate the sounds or wallpapers.

## Build the ISO

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd <path-to-this-repo>
.\Build-CustomISO.ps1
```

The script asks for:

1. **The source ISO path.** You can drag the file into the window.
2. **Where to save the custom ISO.** This can be a file path or a folder.
3. **The edition**, e.g. Windows 11 Pro.
4. **The local account's user name and password.** The password can be blank.

Press Enter at any prompt to accept the default shown. You can also pass everything as parameters:

```powershell
.\Build-CustomISO.ps1 -SourceIso 'E:\Win11.iso' -OutputIso 'F:\ISOs\Custom.iso' -Edition 'Windows 11 Pro'
```

| Parameter | Description |
|---|---|
| `-SourceIso` / `-OutputIso` | Input and output ISO |
| `-WorkDir` | Scratch folder, default `.\work`. Must not contain spaces |
| `-Wallpaper` / `-WallpaperDark` / `-LockScreen` | Override the images in `wallpapers/` |
| `-Edition` | Edition name; empty means choose from a list |
| `-UserName` / `-Password` | Local account; empty means prompt |
| `-ComputerName` | `*` gives a random name |
| `-TimeZone`, `-UserLocale`, `-SystemLocale`, `-InputLocale` | Default to this PC's settings |
| `-AutoWipeDisk0` | ⚠️ Erases disk 0 without asking |
| `-UnattendOnly` | Only writes `autounattend.xml`, for testing |

## Sounds on the current PC

| Script | Purpose |
|---|---|
| `Apply-Sounds.ps1` | Applies the custom sound set to this PC. Backs up the originals to `backup/` first |
| `Restore-Sounds.ps1` | Restores the original sounds, settings and permissions from that backup |
| `Check-StartupSound.ps1` | Run in an installed system. Reports whether the startup sound is custom or stock, then plays it |
| `Sound-Permissions.ps1` | Helper that restores TrustedInstaller ownership of `C:\Windows\Media` |

Restart after applying or restoring the sounds, because running apps keep the previous sounds in memory.

## Regenerating assets

```powershell
python -I tools\recreate_sounds.py C:\Windows\Media <startup.wav> sounds\set   # sound set
python -I tools\wallgen.py wallpapers 3840 2160                                 # wallpapers
```

## Repository layout

```
Build-CustomISO.ps1      main build script
Apply-Sounds.ps1         apply sounds to this PC
Restore-Sounds.ps1       restore original sounds
Check-StartupSound.ps1   verify the startup sound inside an install
Sound-Permissions.ps1    permission helper
sounds/set/              generated sound set (.wav + .raw)
wallpapers/              light, dark and extra wallpapers
tools/                   Python generators for sounds and wallpapers
```

ISO files, the `work/` build folder and the `backup/` folder are git-ignored.

## Disclaimer

Windows is a trademark of Microsoft. This project ships no Microsoft files: you supply your own ISO. Some sounds are inspired by Windows sounds and are intended for personal use. Use at your own risk, and test in a virtual machine first.
