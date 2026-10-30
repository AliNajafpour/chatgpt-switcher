# Contributing

Keep this launcher small, readable and auditable. Windows uses PowerShell; macOS and Linux share a Python/Tk picker under `unix/`.

## Ground rules

- **No third-party runtime dependencies.** Keep Windows compatible with PowerShell 5.1. Unix source uses Python 3.12+ and standard-library Tk; release archives bundle that runtime. PyInstaller is a build dependency only.
- **Keep it readable.** Someone should be able to read the whole thing before running it.
- **Don't touch credentials or account data beyond what's needed to launch a window.** The tool only sets data-dir paths and launches the official app; it must never read, copy, or transmit `auth.json`, cookies, or tokens.

## Dev setup

There's no build step. Edit `ChatGPT-Switcher.ps1` and run it.

Run the regression check without installing anything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\self-check.ps1
pwsh.exe -NoProfile -File .\self-check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\cli-self-check.ps1
pwsh.exe -NoProfile -File .\cli-self-check.ps1
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\ui-self-check.ps1
pwsh.exe -STA -NoProfile -File .\ui-self-check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-self-check.ps1
pwsh.exe -NoProfile -File .\setup-self-check.ps1
```

The check uses synthetic data and never signs into a real account. A skipped junction check must be reported separately from passing checks. Real Store/standalone launches and GUI flows still need manual testing before a release.

GitHub Actions runs all four checks on Windows in both engines. UI checks use generated profiles, mocked account launching and temporary startup shortcuts. They do not change real account data or startup settings. Prefer invoking the PowerShell script directly for arbitrary profile names; CMD interprets metacharacters before a batch file can validate them.

The additional setup check copies only synthetic fixture files into temporary installation directories. It replaces shortcut setup and app launching with harmless stand-ins, then exercises upgrades, rollback and refusal to overwrite unrelated folders. It does not install into your actual Programs folder. Keep setup offline and preserve the explicit payload allowlist.

Syntax check without executing:

```powershell
$e=$null;$t=$null
[System.Management.Automation.Language.Parser]::ParseFile("ChatGPT-Switcher.ps1",[ref]$t,[ref]$e)
if($e){$e}else{"OK"}
```

Please test on a real ChatGPT desktop install before opening a PR, and mention:
- Windows version and PowerShell version
- ChatGPT app version (`-Diagnose` prints it)

## Reporting bugs

Open an issue with the output of `ChatGPT-Switcher.cmd -Diagnose` (redact anything you consider private). Launch failures after an app update are the most likely class of bug — the diagnostics show the detected exe path and package name.

## Scope

Good fits: reliability of app detection/launch, UX of the picker, accessibility, localization.

Out of scope: scraping the service, changing server-side accounts, and bundling the official desktop app or a browser.

## macOS and Linux

Run `python3 unix/self_check.py`, `python3 unix/install_check.py` and `python3 unix/ui_check.py` with Python 3.12+ and Tk. Linux GUI checks need a display, or `xvfb-run -a` in CI. All test profiles and installs are disposable fixtures under `work/`.

To build on the target platform, install `pyinstaller==6.22.3` and run `python3 unix/build.py`. This packages the runtime, tests the frozen app and writes an archive plus SHA-256 under `outputs/`. The four native CI jobs publish these as workflow artifacts. Linux builds use Ubuntu 24.04; macOS builds use macOS 15. Real sign-in and profile persistence remain manual release checks.

Unix source commands include `--add NAME`, `--list`, `--launch NAME_OR_ID`, `--app PATH`, `--data-dir PATH` and `--version`. `--install` is for downloaded frozen bundles. Account data lives under `~/Library/Application Support/CodexAccountSwitcher` on macOS and `$XDG_DATA_HOME/codex-account-switcher` or `~/.local/share/codex-account-switcher` on Linux. Removing a profile from the Unix picker unregisters it and keeps its files.
