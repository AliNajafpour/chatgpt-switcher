# Contributing

Thanks for your interest! This is a small, single-file tool and the goal is to keep it that way: simple, dependency-free, and auditable.

## Ground rules

- **No new runtime dependencies.** It should stay a plain Windows PowerShell 5.1–compatible script.
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

Out of scope: anything that scrapes, automates, or interacts with the ChatGPT service itself; anything that touches server-side accounts; bundling a browser or a full app runtime.
