"""Build on the target OS: python unix/build.py. PyInstaller is build-only."""
import hashlib
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tarfile

from install import IDENTITY, bundle_marker

root = Path(__file__).resolve().parent.parent
dist = root / "outputs" / "unix-dist"
work = root / "work" / "pyinstaller"
dist.mkdir(parents=True, exist_ok=True)
work.mkdir(parents=True, exist_ok=True)
mac = sys.platform == "darwin"
name = "Codex Account Switcher" if mac else "codex-account-switcher"
command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir",
           "--name", name, "--distpath", str(dist), "--workpath", str(work),
           "--specpath", str(work)]
if mac:
    command += ["--windowed", "--osx-bundle-identifier", IDENTITY]
command.append(str(root / "unix" / "switcher.py"))
subprocess.run(command, check=True)
bundle = dist / (name + ".app" if mac else name)
bundle_marker(bundle).write_text(IDENTITY + "\n")
if mac:
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(bundle)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
binary = bundle / "Contents" / "MacOS" / name if mac else bundle / name
subprocess.run([sys.executable, str(root / "unix" / "package_check.py"), str(binary)], check=True)
arch = "arm64" if platform.machine().lower() in ("aarch64", "arm64") else "x64"
label = ("macOS-" if mac else "Linux-") + arch
package = root / "outputs" / ("Codex-Account-Switcher-" + label)
package.mkdir(exist_ok=True)
shutil.copytree(bundle, package / bundle.name, symlinks=True, dirs_exist_ok=True)
launcher = "Install.command" if mac else "Install.sh"
relative = f"{bundle.name}/Contents/MacOS/{name}" if mac else f"{bundle.name}/{name}"
script = package / launcher
script.write_text('#!/bin/sh\nset -eu\ncd -- "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec "./' + relative + '" --install\n')
script.chmod(0o755)
for file in ("LICENSE", "README.md"):
    shutil.copy2(root / file, package / file)
if mac:
    archive = package.with_suffix(".zip")
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(package), str(archive)], check=True)
else:
    archive = package.with_suffix(".tar.gz")
    with tarfile.open(archive, "w:gz") as stream:
        stream.add(package, arcname=package.name)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
Path(str(archive) + ".sha256").write_text(digest + "  " + archive.name + "\n", encoding="ascii")
print(f"Built and smoke-tested {archive.name}")
