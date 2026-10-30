"""Offline per-user installation for the frozen macOS/Linux picker."""
import os
from pathlib import Path
import shutil
import sys
import tempfile

from switcher import Store, TITLE, atomic_write, ordinary

MARKER = ".codex-switcher-install"
IDENTITY = "AliNajafpour.CodexAccountSwitcher"


def desktop_entry(program):
    text = str(program)
    if any(ord(c) < 32 or ord(c) == 127 for c in text):
        raise ValueError("Installation paths cannot contain control characters.")
    # Desktop Entry string escaping is applied before Exec argument unquoting.
    for char in ('\\', '"', '`', '$'):
        text = text.replace(char, "\\" + char)
    text = text.replace("\\", "\\\\").replace("%", "%%")
    return ("[Desktop Entry]\nType=Application\nName=" + TITLE + "\n"
            'Exec="' + text + '"\nIcon=system-users\nTerminal=false\nCategories=Utility;\n'
            "StartupNotify=false\n")


def install_bundle(source, destination, desktop=None):
    source = Path(source).absolute()
    destination = ordinary(destination, directory=True)
    marker = source / MARKER
    if not source.is_dir() or not marker.is_file() or marker.is_symlink() or marker.read_text().strip() != IDENTITY:
        raise ValueError("Incomplete setup download. Extract the entire archive first.")
    if source != destination and (source in destination.parents or destination in source.parents):
        raise ValueError("Choose an installation folder separate from the download.")
    if destination == Path(destination.anchor):
        raise ValueError("Do not install into a filesystem root.")
    # macOS bundles need internal framework links; external links are never copied.
    for path in source.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(source.resolve()):
            raise ValueError(f"The download contains a link outside the bundle: {path}")
    ordinary(destination.parent, directory=True)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with Store(destination.parent / ".codex-switcher-setup").lock():
        if destination.exists():
            owned = ordinary(destination / MARKER)
            if not owned.is_file() or owned.read_text().strip() != IDENTITY:
                raise ValueError("This folder was not installed by this setup. Its files have been left alone.")
        if source != destination:
            stage = Path(tempfile.mkdtemp(prefix=".switcher-setup-", dir=destination.parent))
            previous = stage / "previous"
            keep_backup = False
            try:
                incoming = stage / "incoming"
                shutil.copytree(source, incoming, symlinks=True)
                if destination.exists():
                    os.replace(destination, previous)
                try:
                    os.replace(incoming, destination)
                except OSError:
                    if previous.exists():
                        try:
                            os.replace(previous, destination)
                        except OSError as error:
                            keep_backup = True
                            raise OSError(f"Setup could not restore the previous app. Its backup is preserved at {previous}") from error
                    raise
            finally:
                if not keep_backup:
                    shutil.rmtree(stage)
    # A menu failure must not remove files its newly written entry points to.
    if desktop is not None:
        desktop = ordinary(desktop)
        ordinary(desktop.parent, directory=True)
        desktop.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        try:
            atomic_write(desktop, desktop_entry(destination / "codex-account-switcher").encode("utf-8"))
        except OSError as error:
            raise OSError(f"The app is installed at {destination}, but its menu entry could not be created. Run setup again to repair it.") from error
    return destination


def install_current():
    if not getattr(sys, "frozen", False):
        raise ValueError("Use the packaged installer from GitHub Releases, or run the source picker directly.")
    from tkinter import Tk, messagebox
    window = Tk()
    window.withdraw()
    try:
        binary = Path(sys.executable).absolute()
        if sys.platform == "darwin":
            source = next((p for p in binary.parents if p.suffix == ".app"), None)
            if source is None:
                raise ValueError("Run setup from the complete .app bundle.")
            destination = Path.home() / "Applications" / (TITLE + ".app")
            desktop = None
        else:
            source = binary.parent
            destination = Path.home() / ".local" / "opt" / "codex-account-switcher"
            data = os.environ.get("XDG_DATA_HOME", "")
            data = Path(data) if data and Path(data).is_absolute() else Path.home() / ".local" / "share"
            desktop = data / "applications" / "codex-account-switcher.desktop"
        if not messagebox.askokcancel("Install " + TITLE, f"Install or update for your user?\n\n{destination}\n\nClose any existing picker before upgrading. Your account data will be kept.", parent=window):
            return
        install_bundle(source, destination, desktop)
        location = "your Applications folder" if sys.platform == "darwin" else "your Applications menu"
        messagebox.showinfo(TITLE, f"Installed. Open {TITLE} from {location} now.\n\nYour account data was kept.", parent=window)
    finally:
        window.destroy()
