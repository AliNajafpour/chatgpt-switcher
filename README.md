# Codex account switcher for Windows

English, isolated-account edition, version 1.3.0. Fork maintained at [AliNajafpour/chatgpt-switcher](https://github.com/AliNajafpour/chatgpt-switcher). Filenames retain the original project name. This is an unofficial local launcher.

Double-click `ChatGPT-Switcher.cmd`. Choose **Add account**, enter Work or Personal, then launch the profile and sign in. Repeat for each account. Each profile has separate sign-in data, settings and local projects/chats. Profiles can run together, subject to compatibility with the installed desktop app.

Your existing installation is **Main (existing login)**. Shared-auth code and the online installer have been removed. Old shared entries cannot launch; add a new isolated profile and sign in there. Existing data is not migrated or deleted automatically.

The switcher makes no network requests. The official desktop app still needs internet access to sign in and work.

## Usage

Requires Windows 10/11, Windows PowerShell 5.1 or newer, and the official desktop app. App discovery supports the OpenAI.Codex Store package and the standalone locations recognized by the original script.

```text
ChatGPT-Switcher.cmd                  Open picker
ChatGPT-Switcher.cmd -Add Work        Add isolated account and shortcut
ChatGPT-Switcher.cmd -Launch Work     Launch account
ChatGPT-Switcher.cmd -List            List accounts
ChatGPT-Switcher.cmd -Remove Work     DELETE this profile's local data
ChatGPT-Switcher.cmd -Setup           Create Desktop / Start menu shortcuts
ChatGPT-Switcher.cmd -Tray            Run tray mode
ChatGPT-Switcher.cmd -AutoStartTray   Start tray mode at Windows login
ChatGPT-Switcher.cmd -Diagnose        Show diagnostics
ChatGPT-Switcher.cmd -Version         Show version
```

Right-click a profile to rename it, create a shortcut, or delete it. Deletion includes local projects/chats and sign-in data for that profile. The online account is not deleted. Back up important local data first.

Data is stored under `%USERPROFILE%\ChatGPT-Accounts`. Config updates are atomic and keep the previous version as `accounts.json.bak`. Sign-in data relies on Windows file permissions and the desktop app's storage; the switcher adds no encryption.

Profile changes use an exclusive local file lock. If another switcher is adding, renaming or removing a profile, wait for it to finish and retry. Main always uses the default desktop profile, even when this launcher inherits profile environment variables from a Codex terminal.

Shortcuts use the stable profile ID so similar display names do not overwrite one another. Renaming a profile does not rename its data folder. Old shortcuts whose filenames were based on display names may remain; recreate the shortcut from the profile menu and remove the obsolete shortcut manually.

Startup is optional. To disable it, remove `ChatGPT Switcher (tray).lnk` from the Windows Startup folder. To uninstall, remove the program folder and its shortcuts. Delete the profile data folder only if you intend to erase those local profiles.

## Checks

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\self-check.ps1`. This uses synthetic data and substitutes process launching and shortcut creation. Junction testing is skipped if Windows denies junction creation.

See [SECURITY-REVIEW.md](SECURITY-REVIEW.md) for security findings and limits and [REVIEW.md](REVIEW.md) for remaining issues and prioritized improvements. MIT license, see LICENSE.
