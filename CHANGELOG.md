# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.2.0] - 2026-09-17

### Added
- **Full-share mode (official-like)**: an account can share the real `~/.codex` (projects, chats, config) with every other shared account — only `auth.json` is swapped when you switch. Add with `-Add <name> -Shared`, or pick "完全共有" in the picker. Trade-off: one shared account at a time (no simultaneous run), because two processes on one `~/.codex` / `state_*.sqlite` would corrupt it, and current Codex Desktop rejects a symlinked session store.
  - `auth.json` is backed up to `~/.codex/auth.json.switcher-bak` on every switch; a failed swap is recoverable by re-login (projects/chats are never touched).
  - First run of a shared account: log in, then right-click it → "現在のログインをこのアカウントとして保存" (or `-SaveAuth <id>`).
- Picker shows a 〔共有〕 badge for shared accounts; `-Diagnose` reports each account's mode and the active shared account.
- Isolated mode (the original) is unchanged and remains the default: full isolation, simultaneous windows.

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
