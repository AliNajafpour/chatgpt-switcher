# Repository review and improvement priorities

What this repo does: it launches the installed desktop app with separate Electron data and CODEX_HOME folders for each local profile. It manages profile names, shortcuts and a tray menu. Expected load is one Windows user with a handful of profiles and occasional simultaneous picker, tray and command-line operations.

Reviewed against upstream commit `497bc55` on 2026-10-29. This review covers every supplied script and launcher, configuration flow, profile creation/rename/deletion, launch environment, app discovery, shortcut generation, tray/picker events and documentation. An independent read-only reviewer checked the security fixes.

## Problems fixed in this update

| Trigger | Original result | Change |
| --- | --- | --- |
| Profile ID is `..` or an outside path | Could target unintended local data | Validate every profile path centrally |
| Profile ID is `accounts.json` or another control filename | Could collide with or delete program configuration | Reserve control filenames and require ordinary directories |
| Existing profile path is linked | Recursive deletion could affect unintended data | Reject direct links and nested links during deletion |
| A new profile name matches an unregistered data folder | Could reuse an old login | Select a fresh ID without touching the existing folder |
| Tray and picker modify profiles together | Last writer could erase another registration | Hold an exclusive file handle across each full mutation |
| Config write is interrupted or JSON is corrupt | Could lose registrations or silently reset the list | Atomic replacement, previous-version backup and explicit errors |
| Main is launched from a profile's Codex terminal | Could inherit that profile's directories | Clear profile variables for Main and restore the parent environment |
| Another profile is launched from the same tray | Environment values could carry into later launches | Restore them on success and failure |
| Process query fails or command lines are unreadable | Could treat an active profile as closed | Stop profile management safely |
| Displays `A:B` and `A?B` | Both could use the same shortcut filename | Base shortcuts on unique stable profile IDs |
| Rename Work to an existing Personal label | Two indistinguishable account names | Reject duplicate names when renaming |
| Empty display or invalid color in config | Picker/tray could crash while drawing | Validate UI-critical fields during config loading |
| Store app uses `app/Codex.exe` | App could be missed | Check both Codex and legacy executable names |
| Both ChatGPT.exe and the Store Codex.exe wrapper exist | Wrapper can activate Main and drop profile arguments | Prefer the actual ChatGPT.exe Electron executable; confirmed with a disposable real-app launch |
| Store registration has no accessible executable | Valid standalone install could be ignored | Try standalone discovery before retaining the Store activation fallback |
| Desktop update removes a cached executable | Tray keeps using an obsolete path | Rediscover missing cached executables |
| Shared mode changes the main auth file | Main login was overwritten and copied into extra files | Remove shared-auth code and reject legacy shared launches |
| Online installer or publishing utilities are run | Remote code execution without pinning, or accidental broad publication/deletion | Remove these unused utilities |

The runtime interface, help, errors, diagnostics and new shortcut labels are English. No runtime dependency was added. Existing profile IDs/data locations and the main authentication file are preserved.

## Must fix before calling a release verified

1. **Run a real desktop compatibility check** (`Start-Account`, `Get-ChatGptApp`).
   - What this is: the essential promise is two independent desktop sign-ins running together.
   - Problem: automated checks substitute process launching and package metadata. A real disposable-profile test confirmed separate process/data-directory creation on Store build 26.1023.6621.0, but sign-in identities and persistence still need verification.
   - Fix: test two disposable accounts plus Main on a real installed app, from both a normal terminal and a Codex terminal. Check distinct sign-ins after restart, data separation, an app update, and launch failure. Record Windows, PowerShell and app versions. Never collect real authentication files in test artifacts.
   - If skipped: source-level checks can pass while the installed app still opens the wrong window or profile.

## Should fix next

2. **Command-line operations hide their result** (`ChatGPT-Switcher.cmd`).
   - What this is: only List and Diagnose run in a visible console; other flags use an asynchronous hidden process.
   - Problem: `-Add`, `-Remove` or `-Version` can finish or fail with output the calling terminal cannot see, and their exit status is not returned to that caller.
   - Fix: keep hidden launch for the picker/tray, and execute command-line operations synchronously with visible output and their exit code.
   - If skipped: a script or user can believe an operation succeeded when it failed.

3. **Dispose replaced controls and drawing objects** (`New-AvatarImage`, `Update-PickerRows`, `Start-Tray`).
   - What this is: avatars allocate bitmaps, brushes, fonts and formatting objects; menus and rows are rebuilt.
   - Problem: the function disposes Graphics but not the brush/font/format objects. Clearing collections does not explicitly dispose the removed controls or their custom images.
   - Fix: dispose drawing helpers after rendering and dispose old images/controls when rebuilding lists. Keep ownership clear so displayed images are not disposed early.
   - If skipped: frequent refreshes during a long tray session retain native resources unnecessarily.

4. **Prevent duplicate tray instances** (`Start-Tray`, picker Settings).
   - What this is: every Start tray action starts another PowerShell process.
   - Problem: clicking it twice creates two tray icons and two persistent processes. Config locking protects mutations but does not prevent duplicate tray windows.
   - Fix: one named mutex for tray lifetime, scoped to the Windows user. Keep ordinary profile launches and CLI operations independent.
   - If skipped: duplicate icons and inconsistent-looking tray state confuse the user.

5. **Refresh running indicators** (`Update-PickerRows`, `Show-Picker`).
   - What this is: running state is captured when rows are rebuilt.
   - Problem: closing or opening an app outside the picker leaves its badge stale until another rebuild.
   - Fix: add a Refresh action first. Add a modest timer only if manual refresh proves insufficient, with clear handling of process-query errors.
   - If skipped: a visible Running label can be wrong even though launch/delete checks use current data.

6. **Make long account lists usable** (`Show-Picker`, `Update-PickerRows`).
   - What this is: each account row is 46 pixels high and the window grows automatically.
   - Problem: 30 rows alone need 1,380 pixels before header/footer, without a capped scrolling list. Lower rows can be off-screen.
   - Fix: cap the list height and enable scrolling. Then add simple name filtering and keyboard selection if the actual account count warrants it.
   - If skipped: users with many profiles cannot comfortably reach every account.

7. **Add Windows checks to CI** (`self-check.ps1`, repository workflow).
   - What this is: regression checks currently run by hand in both PowerShell versions.
   - Problem: future changes can be pushed without running them.
   - Fix: a small Windows workflow that runs the same self-check in Windows PowerShell 5.1 and PowerShell 7. Report junction skips explicitly; do not count them as coverage.
   - If skipped: a later cleanup can reintroduce the security and isolation mistakes fixed here.

## Nice to have

8. **Give startup an off switch** (`Install-TrayAutoStart`, Settings).
   - What this is: the UI can enable startup, but disabling it requires deleting a shortcut manually.
   - Problem: users cannot undo a visible setting from the same place.
   - Fix: an Enable/Disable startup toggle reflecting the actual shortcut, and repair the target when the project folder moves.
   - If skipped: startup management remains a manual maintenance task.

9. **Offer recovery before permanent local deletion** (`Remove-Account`).
   - What this is: deletion intentionally removes the whole local profile, including local projects/chats. The confirmation now says so.
   - Problem: an accidental confirmation has no built-in undo; a config backup does not restore deleted data.
   - Fix: first offer Remove from list while keeping data. If a reversible archive is needed, use a deliberate local archive folder with clear size/retention behavior. Avoid automatically exporting login files.
   - If skipped: users remain responsible for backups before deletion.

10. **Copy diagnostics with private paths removed** (`Show-Diagnose`).
    - What this is: diagnostics print full user paths and process command lines.
    - Problem: copying that output into a public issue can disclose a Windows username or profile names.
    - Fix: a copy-safe diagnostic view that replaces personal path prefixes, with full local details available separately.
    - If skipped: users must manually redact diagnostic output before sharing it.

## Recommended order

First verify real two-account isolation, fix command-line feedback, and add Windows CI. Next improve tray lifetime, drawing cleanup and running-state refresh. Finally improve the account list, startup controls, deletion recovery and safe diagnostics.

Keep the plain PowerShell/Windows UI and reuse the installed desktop app. A web frontend, bundled browser, credential scraper or new framework would add maintenance without solving these problems. Rename branding only after deciding how existing shortcuts and startup entries should migrate.

Verdict: the original has several concrete data-loss and profile-isolation defects; those reproduced defects have been addressed in this update. Actual desktop compatibility remains unverified, and the remaining usability/reliability work is listed above.

Lean: shared-auth handling, online installer and unused publishing utilities were removed. Runtime dependencies remain zero. No rewrite is needed.

Not checked: real credentials, real logins, GUI interaction, Store activation, high-DPI/accessibility behavior, app-internal storage or dependencies. Windows denied test-junction creation locally; that case is skipped. Path checks do not defend against a hostile process running as the same Windows user racing filesystem changes.
