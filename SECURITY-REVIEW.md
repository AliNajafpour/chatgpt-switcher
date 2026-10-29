# Security review, 2026-10-29

Scope: the AliNajafpour/chatgpt-switcher fork, based on upstream commit 497bc55, and the earlier English baseline. Assumed use: one Windows user managing local desktop profiles from the picker, tray and CLI. Static review plus synthetic regression checks.

No explicit credential-exfiltration endpoint, telemetry sender, remote shell or obfuscated payload was found in the reviewed scripts. This is not a malware-free certification or an audit of the desktop executable.

## Findings addressed

- Account IDs were used directly in paths for recursive deletion. The common path function now rejects traversal, unsafe characters, reserved Windows names and direct reparse points. Deletion also rejects nested reparse points. Generated IDs are checked before saving.
- Shared mode copied credentials into shared-auth.json and replaced the real .codex/auth.json. Its process check was incomplete and failed open. Shared functions and CLI options were removed, and existing shared entries fail before launch. No real user authentication or backup files were read, migrated or deleted during this work.
- The installer downloaded mutable GitHub scripts and executed them without a pinned version, digest or signature. It was removed. No replacement download/update mechanism was added.
- Isolated launches left environment variables modified. Original values are now restored after successful and failed launches.
- Corrupt config was silently treated as an empty account list. Invalid JSON/schema now fails closed. Config writes use atomic replacement with a previous-version backup.
- Process-query failures were silently treated as no running accounts. They now stop the operation, preventing deletion based on a failed query.
- Runtime UI, help, diagnostics and shortcut names are English, using Segoe UI.
- Control-file names such as accounts.json and accounts.lock are forbidden as profile IDs. Existing profile paths must be ordinary directories.
- Creating a profile skips existing unregistered directories rather than reusing their sign-in state.
- Adding, renaming and removing profiles hold an exclusive accounts.lock handle throughout their read-modify-write operation. A competing operation fails rather than overwriting another change. Read-only operations rely on atomic config replacement.
- Main clears inherited profile variables for launch and restores the parent environment afterward.
- Shortcuts use stable profile IDs, preventing sanitized display-name collisions.
- App detection supports app/Codex.exe, standalone fallback and rediscovery after cached executables disappear.
- When both executables exist, app detection prefers ChatGPT.exe, the actual Electron executable, over the Store Codex.exe wrapper. A real disposable-profile comparison on Store version 26.1023.6621.0 reproduced the wrapper dropping profile arguments; direct Electron launch created an independent profile process and data directory. An existing isolated profile was also observed with its own user-data-dir argument. No authentication content was inspected.
- Unreadable process command lines block profile management, just like failed process queries.
- Rename rejects duplicate display names. Config loading rejects missing/empty display names and invalid color values before the picker tries to draw them.

## Original publishing scripts

The original publish.ps1 and publish.cmd staged the entire directory and created a public GitHub repository by default. They also changed global git identity if absent and deleted some underscore-prefixed files. These unused utilities have been removed from this fork. They were never executed during review.

## Verification and limits

Windows PowerShell 5.1 and PowerShell 7 checks cover parsing, unsafe/reserved IDs, isolated account creation/rename/removal, config backups, orphan directory avoidance, exclusive mutation locking, corrupt config, shared-account rejection before launch, isolated and Main launch environments, restoration after success/failure, missing cached executables, synthetic Store/standalone detection, process-query failure/unreadable command lines, English runtime strings and absent installer.

Windows denied test-junction creation here, so that test reports SKIP. Link prevention was reviewed statically. A malicious process running as the same Windows user can still race file operations; this launcher is not a security boundary against that user.

An unauthenticated real-app isolation smoke check passed on the Store build noted above; the disposable test process tree was then stopped. Actual sign-in identity, account persistence, shortcut installation, tray autostart and end-to-end GUI interaction were not verified. The automated discovery tests still use synthetic package metadata. No dependency audit of the official desktop app was performed. Remaining defects and product improvements are listed in REVIEW.md.

Profile files and authentication backups created by older versions remain sensitive. Protect them with Windows permissions; do not upload them. No extra encryption was added. Removing an account intentionally deletes that profile's local data.
