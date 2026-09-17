# Contributing

Thanks for your interest! This is a small, single-file tool and the goal is to keep it that way: simple, dependency-free, and auditable.

## Ground rules

- **No new runtime dependencies.** It should stay a plain Windows PowerShell 5.1–compatible script.
- **Keep it readable.** Someone should be able to read the whole thing before running it.
- **Don't touch credentials or account data beyond what's needed to launch a window.** The tool only sets data-dir paths and launches the official app; it must never read, copy, or transmit `auth.json`, cookies, or tokens.

## Dev setup

There's no build step. Edit `ChatGPT-Switcher.ps1` and run it.

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
