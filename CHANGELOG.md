# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
