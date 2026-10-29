# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.4.0] - 2026-10-29

### Added
- Refresh button and F5 shortcut for the picker, with visible feedback when process status is unavailable.
- Scrollable account list and a resizable picker with keyboard-accessible controls.
- Single tray instance per Windows sign-in session, scoped to the user.
- `-NoAutoStartTray` and a checked startup setting; enabling/disabling migrates the legacy startup shortcut.
- `-Remove NAME -KeepData` and a confirmed keep-data action in the profile menu.
- Windows CI for core, CLI and UI checks under Windows PowerShell 5.1 and PowerShell 7.
- Expanded English README covering download, setup, usage, upgrades and troubleshooting.

### Fixed
- CLI commands now preserve output, error output and exit codes; only the picker and a lone `-Tray` launch in the background.
- Reject unknown parameters, conflicting operations and invalid modifiers before any profile mutation. Invalid tray combinations report console errors instead of opening modal dialogs.
- Dispose replaced rows, avatar images, drawing helpers, menus, fonts, icons and tray resources.
- Keep the picker usable when running status cannot be inspected, while deletion still uses strict safety checks.

### Changed
- Consistent Codex Account Switcher labels and Start-root shortcuts. Existing script filenames and profile locations remain compatible.
- The GitHub repository is now standalone; upstream MIT attribution and commit history are retained.

### Validation
- Core, real CMD forwarding/exit-code checks and synthetic 30-profile UI checks pass in both PowerShell engines.
- Junction checks report SKIP when creation is denied. Real sign-in identities and restart persistence remain unverified.
- README documents the PowerShell-to-CMD metacharacter limitation and direct `.ps1` invocation for arbitrary names.

## [1.3.0] - 2026-10-29

### Changed
- English UI, CLI help, diagnostics and shortcut labels; Segoe UI font.
- Isolated profiles only. Legacy shared entries fail before launch and remain available for deliberate removal.
- Profile shortcuts use stable IDs rather than sanitized display names.

### Fixed
- Validate profile paths, reserved control-file names and ordinary directories before writes or recursive deletion.
- Reject linked profile paths and nested links during removal.
- New profiles skip existing unregistered data folders instead of reusing their login.
- Serialize profile changes with an exclusive per-data-folder file lock.
- Write config atomically with a previous-version backup; reject corrupt config rather than silently resetting it.
- Restore launcher environment after profile launches. Clear inherited profile variables for Main.
- Block profile management when desktop process inspection fails or command lines cannot be read.
- Detect app/Codex.exe, fall back to a standalone installation when the Store executable is unavailable, and refresh missing cached executables.
- Reject duplicate names on rename and invalid display/color fields in config.
- Prefer the real ChatGPT.exe Electron executable over the Store Codex.exe wrapper. On the tested Store build the wrapper drops profile arguments and activates the existing main window instead.

### Removed
- Shared-auth switching and its CLI flags.
- Network installer and obsolete repository-publishing utilities.
- Outdated Japanese README that described removed functionality.

### Validation
- Added dependency-free self-check.ps1 for Windows PowerShell 5.1 and PowerShell 7.
- Real multi-account login and GUI integration remain unverified. Junction checks skip if Windows denies junction creation.

## [1.2.0] - 2026-09-17

### Added
- **Full-share mode (removed in 1.3.0)**: an account could share the real `~/.codex` (projects, chats, config) with every other shared account. Only `auth.json` was swapped. This historical mode required one shared account at a time.
  - `auth.json` is backed up to `~/.codex/auth.json.switcher-bak` on every switch; a failed swap is recoverable by re-login (projects/chats are never touched).
  - First run required saving the current login with `-SaveAuth <id>`.
- Picker showed a shared badge; diagnostics reported each account's mode and the active shared account.
- Isolated mode (the original) is unchanged and remains the default: full isolation, simultaneous windows.

## [1.1.0] - 2026-09-17

### Added
- **Jump list**: pin the switcher to the taskbar, then right-click it to launch any account directly. Built with a private AppUserModelID and the managed `System.Windows.Shell.JumpList`; the switcher's taskbar button groups under that pinned icon.
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
