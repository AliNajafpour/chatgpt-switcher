# Codex Account Switcher

A local Windows launcher for using separate accounts in the official Codex desktop app. Create a profile for Work, Personal, or another account, sign in once in each profile, and open it from the picker, a desktop shortcut, or the system tray.

Each added profile gets its own app data and `CODEX_HOME`. Your existing desktop login remains available as **Main (existing login)**. Separate profiles can run together when supported by the installed desktop app.

Version **1.4.0** · Windows · PowerShell · [راهنمای فارسی](README.fa.md)

This is an unofficial community project, unaffiliated with OpenAI. It launches your installed app; it does not install Codex, provide accounts, or change subscription limits.

## Download and install

You need Windows 10 or 11, Windows PowerShell 5.1 or newer, and the official Codex desktop app installed and working. There are no additional packages, build tools, or runtime dependencies to install.

1. [Download the source ZIP](https://github.com/AliNajafpour/chatgpt-switcher/archive/refs/heads/main.zip).
2. Extract it into a permanent folder you control, such as `Documents\Codex Account Switcher`. Do not run it inside the ZIP.
3. Keep `ChatGPT-Switcher.cmd` and `ChatGPT-Switcher.ps1` together.
4. Double-click `ChatGPT-Switcher.cmd` to open the account picker.

The `ChatGPT-Switcher` filenames are retained for compatibility. The visible app name is Codex Account Switcher. There is no `.exe` installer or online installation script.

If you use Git, clone the same source instead:

```powershell
git clone https://github.com/AliNajafpour/chatgpt-switcher.git
cd chatgpt-switcher
.\ChatGPT-Switcher.cmd
```

The ZIP tracks the current `main` branch. Check the [changelog](CHANGELOG.md) for changes and the [releases page](https://github.com/AliNajafpour/chatgpt-switcher/releases) for any published releases.

## First use

1. Choose **Add account** and enter a recognizable name, such as `Work`.
2. Open the new profile and complete sign-in inside the official app.
3. Add another profile, such as `Personal`, and sign into that account there.
4. Open either profile from the picker or its desktop shortcut whenever you need it.

Adding a profile creates local folders and a registration. It does not create an online account or sign you in automatically. Each new profile starts separately, so your Main login is not imported.

Choose **Main (existing login)** to open the app with its normal data and existing login. Main also uses the default profile when the switcher starts from a terminal inside an isolated Codex profile.

## Picker, shortcuts, and tray

Click a profile to launch it. Use **Refresh** or **F5** to update the list and running indicators after closing a window or making changes elsewhere. Long lists scroll within the window.

Right-click an added profile to rename it, create its desktop shortcut, remove it from the list while keeping its data, or permanently delete its local data. Close that profile's app windows before removing it. Permanent deletion in the UI requires confirmation.

### Add the switcher to Start

Open the picker's Settings menu and choose the shortcut creation action, or run this in PowerShell from the extracted folder:

```powershell
.\ChatGPT-Switcher.cmd -Setup
```

Setup creates these shortcuts for your Windows user:

| Location | Shortcut | Opens |
| --- | --- | --- |
| Desktop | Codex Account Switcher | Account picker |
| Start menu | Codex Account Switcher | Account picker |
| Start menu | Codex Switcher (tray) | Tray mode |

Search Start for **Codex Account Switcher** to open it. You can pin the Start shortcut to the taskbar using Windows' available pin action. The switcher also maintains account launch entries in its taskbar jump list, where supported by Windows.

Shortcuts point to the extracted script folder. If you move that folder, run `-Setup` again and recreate profile shortcuts from the picker. Profile shortcuts use stable IDs, so renaming an account does not change its data folder.

### Tray and Windows startup

```powershell
.\ChatGPT-Switcher.cmd -Tray
.\ChatGPT-Switcher.cmd -AutoStartTray
.\ChatGPT-Switcher.cmd -NoAutoStartTray
```

Tray mode keeps an icon in the Windows notification area. Left-click it to open the picker; right-click it to launch a profile, add an account, or exit tray mode. Windows may place the icon under the hidden-icons arrow. Only one tray instance runs per Windows user.

`-AutoStartTray` enables tray mode at Windows sign-in. `-NoAutoStartTray` disables it. You can also change this setting from the picker. Disabling startup does not close an already running tray instance; use **Exit tray mode** for that. Enabling or disabling startup also handles the legacy `ChatGPT Switcher (tray)` startup shortcut.

## Command line

Run these commands in PowerShell from the switcher's folder. Quote names containing spaces. Launch and removal accept the profile's display name or stable ID; `-List` shows IDs. Use one primary operation per invocation.

For names containing CMD special characters such as `&`, `|`, `<`, `>`, `^`, `%`, `!`, or parentheses, invoke the `.ps1` script directly. Quoting alone does not make those names safe through the `.cmd` launcher:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-Switcher.ps1 -Add 'Work & Personal'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-Switcher.ps1 -Launch 'Work & Personal'
```

Automation that accepts names from user input should call `.ps1` directly for both adding and launching profiles. Pass the name as a parameter, without building a command string.

| Command | Result |
| --- | --- |
| `.\ChatGPT-Switcher.cmd` | Open the picker |
| `.\ChatGPT-Switcher.cmd -Add Work` | Add an isolated profile and its desktop shortcut |
| `.\ChatGPT-Switcher.cmd -Add "Work account" -NoShortcut` | Add a profile without a desktop shortcut |
| `.\ChatGPT-Switcher.cmd -Launch Work` | Launch a registered profile |
| `.\ChatGPT-Switcher.cmd -Launch __main__` | Launch Main with its existing login |
| `.\ChatGPT-Switcher.cmd -List` | List profiles and running indicators |
| `.\ChatGPT-Switcher.cmd -Setup` | Create Desktop and Start menu picker/tray shortcuts |
| `.\ChatGPT-Switcher.cmd -Setup -NoShortcut` | Create the same shortcuts without the completion dialog |
| `.\ChatGPT-Switcher.cmd -Tray` | Start tray mode |
| `.\ChatGPT-Switcher.cmd -AutoStartTray` | Enable tray startup at Windows sign-in |
| `.\ChatGPT-Switcher.cmd -NoAutoStartTray` | Disable tray startup |
| `.\ChatGPT-Switcher.cmd -Remove Work -KeepData` | Unregister Work and remove its shortcut, keeping its local data |
| `.\ChatGPT-Switcher.cmd -Remove Work` | Permanently delete Work's local data and registration |
| `.\ChatGPT-Switcher.cmd -Diagnose` | Print app discovery, profile, and process diagnostics |
| `.\ChatGPT-Switcher.cmd -Version` | Print the switcher version |

`-NoShortcut` has a legacy naming exception. With `-Add`, it skips the profile's desktop shortcut. With `-Setup`, it suppresses the completion dialog and still creates all setup shortcuts.

Command-line operations print their result in the calling terminal and return when finished. Exit code `0` indicates success; `1` indicates an error. Picker and tray launches run separately so they do not hold the terminal open.

```powershell
.\ChatGPT-Switcher.cmd -Add Work -NoShortcut
if ($LASTEXITCODE -ne 0) { throw 'Could not add Work.' }
.\ChatGPT-Switcher.cmd -Launch Work
```

You can also invoke the script directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ChatGPT-Switcher.ps1 -List
```

The command launcher uses Windows PowerShell. The script is also checked with PowerShell 7. The launcher's execution-policy option applies to its process; it does not change your saved system policy. Organizational controls can still block execution.

## How profile isolation works

For an added profile, the switcher launches the app with a separate Electron user-data directory and sets `CODEX_ELECTRON_USER_DATA_PATH` and `CODEX_HOME` for that launch. It restores its own environment afterward. It does not read, copy, scrape, or swap `auth.json`, cookies, or tokens. Sign-in happens inside the official app.

The data directory keeps the original name for compatibility:

```text
%USERPROFILE%\ChatGPT-Accounts\
  accounts.json          Profile names, IDs, and display settings
  accounts.json.bak      Previous saved configuration, when available
  accounts.lock          File used to serialize profile changes
  switcher.log           Local launcher log
  <profile-id>\
    electron\            This profile's desktop app data
    codex\               This profile's CODEX_HOME
```

Sign-in state, settings, and app-managed local history are stored per profile. Files you deliberately open in the same project directory remain the same files. Profiles share your Windows user and filesystem permissions, so this is not a sandbox or a security boundary between untrusted accounts.

App compatibility matters. Separate real app processes and data directories were tested on Microsoft Store build **26.1023.6621.0**. Full independent sign-in identities and persistence across restarts have not yet been verified. Future desktop updates can change launch behavior; verify the displayed identity in each window before sensitive work. Discovery supports the `OpenAI.Codex` Store package and recognized standalone paths, including legacy executable names.

## Removing a profile and keeping data

**`-Remove NAME` permanently deletes that profile's local sign-in data, settings, and app-managed local projects/chats.** It does not delete the online account. The CLI performs the requested deletion without a confirmation prompt. The UI asks for confirmation. There is no built-in undo, and the configuration backup does not back up profile contents.

Use `-Remove NAME -KeepData` or the picker's keep-data action when you only want to remove an entry from the list. Keep-data removal leaves the profile folder on disk. Adding the same name later creates a fresh profile and does not reconnect the retained folder. There is no automatic restore/import command.

Main is not a switcher-managed profile and cannot be removed through these operations. Removal stops when the switcher detects the profile running or cannot inspect app processes. Permanent deletion also rejects unsafe linked paths.

## Upgrade

1. Exit tray mode and close the picker. Close profile windows if you plan to back up their data.
2. Download and extract the new source, or run `git pull` in a clean clone.
3. Replace the program files in the same permanent folder. Keep `ChatGPT-Switcher.cmd` and `.ps1` from the same version together.
4. Run `-Version`, then `-Setup` to refresh picker shortcuts. Recreate profile shortcuts as needed.
5. If tray startup was enabled, run `-AutoStartTray` again to refresh its target, then start tray mode.

Profile data lives outside the program folder under `%USERPROFILE%\ChatGPT-Accounts`. Updating program files does not migrate or erase it. If the program folder moves, recreate or manually remove old shortcuts, including pinned shortcuts and obsolete ChatGPT-branded links.

Versions before 1.3.0 supported shared-auth switching. That mode and its flags have been removed. Legacy shared entries cannot launch. Add a new isolated profile and sign in there. Old shared-auth files and backups are not read, migrated, or deleted automatically; treat them as sensitive data and decide how to retain or remove them yourself.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| Desktop app was not found | Open the official app normally first. Run `-Diagnose` to see the detected package and executable. Custom install paths may not be recognized. |
| A launch opens Main or the wrong account | Check that you selected an added isolated profile, not Main or a legacy shared entry. Close that profile and retry. Record the app version from diagnostics and verify the identity in the opened window. |
| Launch fails after an app update | Exit and restart tray mode, then run diagnostics. Discovery refreshes a cached executable if it disappeared, but desktop changes can still require a switcher fix. |
| A shortcut points to a missing file | Keep both launcher files together. Run `-Setup` from the current folder and recreate profile shortcuts. Remove obsolete or pinned links manually. |
| Running indicators are stale | Click Refresh or press F5 in the picker. Reopen the tray menu to rebuild its list. |
| A profile change reports a lock error | Wait for the other picker, tray, or CLI operation to finish and retry. The presence of `accounts.lock` alone does not mean it is locked. |
| Process inspection fails | Close the affected app processes normally and retry from the same Windows user. Unknown process state blocks management operations instead of being treated as closed. |
| `accounts.json` is corrupt | Exit the switcher. Preserve the damaged file, then restore a known-valid `accounts.json.bak` if available. It restores registrations only, not deleted data. |
| Windows blocks a downloaded script | Review the source first. If you trust this download, use Properties > Unblock where available. Managed-device policy may require your administrator. |
| No tray icon appears | Check Windows' hidden notification icons. A second tray launch exits when an instance already runs for your user. |

For a bug report, include Windows, PowerShell, and app versions, the command or UI action, the error text, and relevant diagnostics. Open an [issue](https://github.com/AliNajafpour/chatgpt-switcher/issues).

Diagnostics and `%USERPROFILE%\ChatGPT-Accounts\switcher.log` may contain your Windows username, full paths, profile labels, and process command lines. Review and redact them manually before posting. Never attach profile folders, `auth.json`, cookies, tokens, or old credential backups.

## Uninstall

1. Disable tray startup with `.\ChatGPT-Switcher.cmd -NoAutoStartTray`.
2. Exit tray mode and close the picker.
3. Delete the program folder and its Desktop, Start menu, and pinned shortcuts. Remove old ChatGPT-branded shortcuts you no longer use.
4. Keep `%USERPROFILE%\ChatGPT-Accounts` to retain profile data. Delete it only after closing all isolated app windows and deciding to permanently erase every profile stored there.

Uninstalling the switcher does not uninstall the official app or remove Main's default data. There is no uninstaller service or background updater.

## Security and privacy

- The switcher makes no network requests and has no telemetry or online updater. The official app still uses the network for sign-in and normal operation.
- Profile data relies on Windows permissions and the desktop app's storage. The switcher adds no encryption. Anyone with sufficient access to your Windows user or files may access that data.
- Configuration writes use atomic replacement and keep the previous saved version. Profile mutations hold an exclusive local file lock. These protections reduce accidental corruption; they do not replace backups.
- Profile paths are validated, and deletion rejects linked paths. A hostile process running as the same Windows user can still race filesystem operations.
- Source checks and the documented review do not certify the official desktop executable or guarantee compatibility with every version.

See [SECURITY-REVIEW.md](SECURITY-REVIEW.md) for findings and limitations, and [REVIEW.md](REVIEW.md) for review context and compatibility checks still needed.

## Development and checks

There is no build step. Run the dependency-free checks from the repository folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\self-check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\cli-self-check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\ui-self-check.ps1
```

With PowerShell 7 installed:

```powershell
pwsh.exe -NoProfile -File .\self-check.ps1
pwsh.exe -NoProfile -File .\cli-self-check.ps1
pwsh.exe -NoProfile -STA -File .\ui-self-check.ps1
```

GitHub Actions runs all three checks on Windows with Windows PowerShell 5.1 and PowerShell 7. Checks use synthetic profiles and substitutes for relevant external effects. They do not sign in to real accounts or establish end-to-end account isolation. Junction checks report a skip if Windows denies junction creation; a skip is not coverage.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before contributing. Keep changes small, keep runtime dependencies at zero, and keep authentication handling inside the official app.

## License and credits

Released under the [MIT license](LICENSE). This repository builds on the original [kociden/chatgpt-switcher](https://github.com/kociden/chatgpt-switcher) project. Its license credits **Alyawmu**, and the original copyright and license notice are retained. The PowerShell launcher, picker, profile layout, shortcuts, and tray integration originate in that work.

Changes maintained at [AliNajafpour/chatgpt-switcher](https://github.com/AliNajafpour/chatgpt-switcher) include the English interface, isolated-only account flow, security and reliability fixes, usability updates, checks, and documentation. See the [changelog](CHANGELOG.md) for project history.
