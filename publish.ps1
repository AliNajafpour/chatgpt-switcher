<#
  Publish ChatGPT Switcher to GitHub as a public repo, using YOUR gh login.
  This never exposes credentials to anyone else - it uses the GitHub CLI (gh)
  that is signed in on this machine.

  Usage:
    .\publish.ps1                       # public repo named 'chatgpt-switcher'
    .\publish.ps1 -RepoName my-name     # custom repo name
    .\publish.ps1 -Private              # private instead of public
#>
param(
  [string]$RepoName = 'chatgpt-switcher',
  [switch]$Private,
  [string]$Description = 'Switch between multiple ChatGPT desktop app accounts on Windows - a Google-style account switcher. Dependency-free PowerShell.'
)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
Set-Location -LiteralPath $PSScriptRoot
$log = Join-Path $PSScriptRoot '_publish_log.txt'
function Log($m) { Write-Host $m; Add-Content -LiteralPath $log -Value $m -Encoding UTF8 }
Set-Content -LiteralPath $log -Value ("publish started {0}" -f (Get-Date)) -Encoding UTF8

# --- prerequisites ---
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { Log 'ERROR: git not found. Install: winget install --id Git.Git'; Log 'RESULT: FAILED'; return }
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) { Log 'ERROR: GitHub CLI (gh) not found. Install: winget install --id GitHub.cli  then run: gh auth login'; Log 'RESULT: NEED_GH'; return }

# --- auth ---
& gh auth status 2>&1 | ForEach-Object { Log $_ }
if ($LASTEXITCODE -ne 0) {
  Log 'ERROR: gh is not logged in. Run once:  gh auth login   (choose GitHub.com / HTTPS / login with a web browser), then re-run this script.'
  Log 'RESULT: NEED_AUTH'
  return
}
$owner = (& gh api user -q '.login').Trim()
if (-not $owner) { Log 'ERROR: could not read your GitHub login.'; Log 'RESULT: FAILED'; return }
Log ("GitHub user: {0}" -f $owner)

# --- git identity (only set if missing) ---
if (-not (git config --global user.name))  { git config --global user.name  $owner }
if (-not (git config --global user.email)) { git config --global user.email ("{0}@users.noreply.github.com" -f $owner) }

# --- local repo ---
if (-not (Test-Path (Join-Path $PSScriptRoot '.git'))) { git init -b main | Out-Null }
# tidy any local test artifacts before committing
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '_*' -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne '_publish_log.txt' } | Remove-Item -Force -ErrorAction SilentlyContinue

git add -A
git commit -m ("ChatGPT Switcher v" + ((Select-String -Path 'ChatGPT-Switcher.ps1' -Pattern "Version\s*=\s*'([^']+)'").Matches[0].Groups[1].Value)) 2>&1 | ForEach-Object { Log $_ }

# --- create + push ---
$vis = if ($Private) { '--private' } else { '--public' }
Log ("Creating {0} repo: {1}/{2}" -f ($vis.TrimStart('-')), $owner, $RepoName)
& gh repo create $RepoName $vis --source . --remote origin --push --description $Description 2>&1 | ForEach-Object { Log $_ }
if ($LASTEXITCODE -ne 0) { Log 'ERROR: gh repo create failed (name may already exist). Try -RepoName <other>.'; Log 'RESULT: FAILED'; return }

# --- fill repo URLs in docs, then push again ---
foreach ($f in @('README.md','README.ja.md','install.ps1')) {
  if (Test-Path $f) {
    (Get-Content -LiteralPath $f -Raw) -replace '__OWNER__', $owner -replace '__REPO__', $RepoName |
      Set-Content -LiteralPath $f -Encoding UTF8
  }
}
git commit -am 'docs: fill repository URLs' 2>&1 | ForEach-Object { Log $_ }
git push 2>&1 | ForEach-Object { Log $_ }

$url = "https://github.com/$owner/$RepoName"
Log ("URL: {0}" -f $url)
Log 'RESULT: SUCCESS'
