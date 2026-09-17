# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.1.0] - 2026-09-17

### Added
- **Jump list**: pin the switcher to the taskbar, then right-click it to launch any account directly (`アカウント` category). Built with a private AppUserModelID and the managed `System.Windows.Shell.JumpList`; the switcher's taskbar button now groups under that pinned icon.
- `-Setup` now stamps the shortcut's AppUserModelID and refreshes the jump list, and prints taskbar-pin instructions.

### Fixed
- **Critical**: the version constant was named `$script:Version`, which collided with the `-Version` switch parameter and made the script throw on load (so 1.0.0 failed at runtime whenever it was actually run). Renamed to `$script:AppVersion`.

## [1.0.0] - 2026-09-17

### Added
- Account picker window (Google-style) to launch any account.
- Per-account isolation via `--user-data-dir` + `CODEX_ELECTRON_USER_DATA_PATH` + `CODEX_HOME`.
- Auto-detection of the Store (`OpenAI.Codex`) and installer builds of the ChatGPT desktop app.
- Per-account desktop shortcuts; picker shortcuts for Desktop + Start Menu (`-Setup`).
- System-tray mode (`-Tray`) and auto-start at login (`-AutoStartTray`).
- Add / rename / remove accounts; "● running" indicator; bring existing window to front.
- CLI flags: `-Launch`, `-Add`, `-Remove`, `-List`, `-Setup`, `-Tray`, `-AutoStartTray`, `-Diagnose`, `-Version`.
- One-line installer (`install.ps1`).

### Fixed
- Add/rename dialogs no longer hide behind the picker window (custom owned dialogs; picker is no longer always-on-top).
