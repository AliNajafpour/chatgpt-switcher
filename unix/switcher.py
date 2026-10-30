#!/usr/bin/env python3
"""Local macOS/Linux account picker. Never reads credentials or downloads code."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

VERSION = "1.6.0"
TITLE = "Codex Account Switcher"
MAIN = "__main__"
PALETTE = ("#4285F4", "#34A853", "#A142F4", "#EA4335")


def ordinary(path, directory=False):
    """Reject links, including broken links and linked ancestor directories."""
    path = Path(os.path.abspath(path))
    for parent in (path, *path.parents):
        if parent.is_symlink():
            raise ValueError(f"Linked paths are not supported: {parent}")
    if path.exists() and (path.is_dir() if directory else path.is_file()) is False:
        raise ValueError(f"Unexpected file type: {path}")
    return path


def atomic_write(path, data):
    ordinary(path)
    fd, temp = tempfile.mkstemp(prefix=".switcher-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def data_root():
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "CodexAccountSwitcher"
    base = os.environ.get("XDG_DATA_HOME", "")
    return (Path(base) if base and Path(base).is_absolute() else Path.home() / ".local" / "share") / "codex-account-switcher"


class Store:
    def __init__(self, root):
        self.root = Path(os.path.abspath(root))

    def paths(self, key):
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", key) or key == MAIN:
            raise ValueError("Invalid profile ID.")
        ordinary(self.root, directory=True)
        base = self.root / key
        return tuple(ordinary(p, directory=True) for p in (base, base / "electron", base / "codex"))

    def read(self):
        ordinary(self.root, directory=True)
        path = ordinary(self.root / "accounts.json")
        if not path.exists():
            return {"accounts": []}
        try:
            config = json.loads(path.read_text(encoding="utf-8-sig"))
            if not isinstance(config, dict) or not isinstance(config.get("accounts"), list):
                raise ValueError("Expected an accounts list.")
            names, ids = set(), set()
            for account in config["accounts"]:
                if not isinstance(account, dict):
                    raise ValueError("Invalid account record.")
                self.paths(account["id"])
                name = self.name(account["display"])
                if account.get("mode") != "isolated" or name.casefold() in names or account["id"].casefold() in ids:
                    raise ValueError("Duplicate or non-isolated profile.")
                names.add(name.casefold())
                ids.add(account["id"].casefold())
            if "app" in config and not isinstance(config["app"], str):
                raise ValueError("Invalid app path.")
            return config
        except (ValueError, KeyError, TypeError) as error:
            raise ValueError(f"Cannot read accounts.json. Restore its backup before continuing. {error}") from error

    def accounts(self):
        return self.read()["accounts"]

    @staticmethod
    def name(value):
        if not isinstance(value, str) or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("Use a name without control characters.")
        value = value.strip()
        if not value or len(value) > 100:
            raise ValueError("Use a name between 1 and 100 characters.")
        return value

    @contextmanager
    def lock(self):
        ordinary(self.root, directory=True)
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        path = ordinary(self.root / "accounts.lock")
        with path.open("a+b") as stream:
            if os.name == "nt":  # Allows the same synthetic checks on Windows.
                import msvcrt
                stream.seek(0)
                stream.write(b"0")
                stream.flush()
                stream.seek(0)
                try:
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                except OSError as error:
                    raise RuntimeError("Another picker is updating profiles. Try again.") from error
            else:
                import fcntl
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except OSError as error:
                    raise RuntimeError("Another picker is updating profiles. Try again.") from error
            try:
                yield
            finally:
                if os.name == "nt":
                    stream.seek(0)
                    msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(stream, fcntl.LOCK_UN)

    def save(self, config):
        path = ordinary(self.root / "accounts.json")
        if path.exists():
            atomic_write(self.root / "accounts.json.bak", path.read_bytes())
        atomic_write(path, (json.dumps(config, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

    def find(self, key):
        accounts = self.accounts()
        for field in ("id", "display"):
            for account in accounts:
                if account[field].casefold() == key.casefold():
                    return account
        raise ValueError(f"Profile not found: {key}")

    def add(self, name):
        name = self.name(name)
        with self.lock():
            config = self.read()
            if any(a["display"].casefold() == name.casefold() for a in config["accounts"]):
                raise ValueError("That account name already exists.")
            key = "p_" + uuid.uuid4().hex
            while (self.root / key).exists():
                key = "p_" + uuid.uuid4().hex
            base, electron, codex = self.paths(key)
            base.mkdir(mode=0o700)
            electron.mkdir(mode=0o700)
            codex.mkdir(mode=0o700)
            account = {"id": key, "display": name, "mode": "isolated", "color": PALETTE[len(config["accounts"]) % len(PALETTE)]}
            config["accounts"].append(account)
            self.save(config)
            return account

    def rename(self, key, name):
        name = self.name(name)
        with self.lock():
            account = self.find(key)
            config = self.read()
            if any(a["id"] != account["id"] and a["display"].casefold() == name.casefold() for a in config["accounts"]):
                raise ValueError("That account name already exists.")
            for row in config["accounts"]:
                if row["id"] == account["id"]:
                    row["display"] = name
            self.save(config)

    def remove(self, key):
        with self.lock():
            account = self.find(key)
            config = self.read()
            config["accounts"] = [a for a in config["accounts"] if a["id"] != account["id"]]
            self.save(config)

    def set_app(self, path):
        path = executable(path)
        with self.lock():
            config = self.read()
            config["app"] = str(path)
            self.save(config)


def executable(path):
    path = Path(path).expanduser()
    if path.suffix.lower() == ".app" and path.is_dir():
        with (path / "Contents" / "Info.plist").open("rb") as stream:
            name = plistlib.load(stream).get("CFBundleExecutable", "")
        if not isinstance(name, str) or not name or "/" in name or "\\" in name or name in (".", ".."):
            raise ValueError("The application bundle has an invalid executable name.")
        path = path / "Contents" / "MacOS" / name
    if not path.is_file():
        raise ValueError("Desktop app not found. Install the official app or choose its executable.")
    if os.name != "nt" and not os.access(path, os.X_OK):
        raise ValueError(f"The selected app is not executable: {path}")
    return path.absolute()


def detect_app():
    if sys.platform == "darwin":
        for name in ("Codex.app", "ChatGPT.app"):
            for parent in (Path("/Applications"), Path.home() / "Applications"):
                if (parent / name).is_dir():
                    return executable(parent / name)
    else:
        for name in ("chatgpt", "codex-desktop"):
            found = shutil.which(name)
            if found:
                return executable(found)
    raise ValueError("Official desktop app not found. Install it, then use Choose app if needed.")


def launch(store, key, app=None):
    config = store.read()
    app = executable(app or config["app"]) if app or config.get("app") else detect_app()
    env = os.environ.copy()
    # PyInstaller's library path belongs to the picker, not the external app.
    if getattr(sys, "frozen", False) and sys.platform.startswith("linux"):
        original = env.pop("LD_LIBRARY_PATH_ORIG", None)
        if original is None:
            env.pop("LD_LIBRARY_PATH", None)
        else:
            env["LD_LIBRARY_PATH"] = original
    args = [str(app)]
    cwd = str(Path.home())
    if key == MAIN:
        env.pop("CODEX_HOME", None)
        env.pop("CODEX_ELECTRON_USER_DATA_PATH", None)
    else:
        account = store.find(key)
        base, electron, codex = store.paths(account["id"])
        for folder in (base, electron, codex):
            folder.mkdir(mode=0o700, exist_ok=True)
        env["CODEX_HOME"] = str(codex)
        env["CODEX_ELECTRON_USER_DATA_PATH"] = str(electron)
        args.append("--user-data-dir=" + str(electron))
        cwd = str(base)
    return subprocess.Popen(args, env=env, cwd=cwd, start_new_session=True,
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def picker(store):
    import tkinter as tk
    from tkinter import filedialog, messagebox, simpledialog, ttk

    window = tk.Tk()
    window.title(TITLE)
    window.geometry("540x420")
    window.minsize(430, 340)
    window.configure(background="#f5f6f8")
    style = ttk.Style(window)
    style.configure("Treeview", rowheight=42, font=("", 12))
    style.configure("TButton", padding=(12, 8))
    outer = ttk.Frame(window, padding=20)
    outer.pack(fill="both", expand=True)
    ttk.Label(outer, text="Choose an account", font=("", 20, "bold")).pack(anchor="w")
    ttk.Label(outer, text="Separate logins. Your accounts stay on this device.").pack(anchor="w", pady=(6, 18))
    body = ttk.Frame(outer)
    body.pack(fill="both", expand=True)
    tree = ttk.Treeview(body, show="tree", selectmode="browse", height=5)
    tree.heading("#0", text="Accounts")
    tree.column("#0", minwidth=200, stretch=True)
    scroll = ttk.Scrollbar(body, orient="vertical", command=tree.yview)
    tree.configure(yscrollcommand=scroll.set)
    tree.pack(side="left", fill="both", expand=True)
    scroll.pack(side="right", fill="y")
    status = tk.StringVar(value="Select an account and choose Open.")
    ttk.Label(outer, textvariable=status, wraplength=460).pack(anchor="w", pady=(10, 8))

    def safely(action):
        try:
            action()
        except (OSError, ValueError, RuntimeError) as error:
            messagebox.showerror(TITLE, str(error), parent=window)

    def refresh(select=MAIN):
        rows = store.accounts()  # Read first: a corrupt file must not hide the current list.
        tree.delete(*tree.get_children())
        tree.insert("", "end", iid=MAIN, text="Main (existing login)")
        for account in rows:
            tree.insert("", "end", iid=account["id"], text=account["display"])
        tree.selection_set(select if tree.exists(select) else MAIN)
        tree.focus(tree.selection()[0])

    def selected():
        choice = tree.selection()
        if not choice:
            raise ValueError("Choose an account first.")
        return choice[0]

    def open_account():
        key = selected()
        process = launch(store, key)
        status.set("Starting the desktop app…")

        def check():
            if process.poll() not in (None, 0):
                messagebox.showerror(TITLE, "The desktop app exited while starting. Check the selected app and try opening it directly.", parent=window)
                status.set("Launch failed.")
            else:
                status.set("Launch request sent. Sign in inside the desktop app if needed.")
        window.after(1200, check)

    def add():
        name = simpledialog.askstring("Add account", "Account name", parent=window)
        if name is not None:
            account = store.add(name)
            refresh(account["id"])
            status.set("Account added. Choose Open, then sign in inside the desktop app.")

    def rename():
        key = selected()
        if key == MAIN:
            raise ValueError("Main is the desktop app's existing login.")
        name = simpledialog.askstring("Rename account", "Account name", initialvalue=store.find(key)["display"], parent=window)
        if name is not None:
            store.rename(key, name)
            refresh(key)

    def remove():
        key = selected()
        if key == MAIN:
            raise ValueError("Main cannot be removed.")
        if messagebox.askyesno("Remove from list", "Remove this account from the picker? Its local data will be kept.", parent=window):
            store.remove(key)
            refresh()
            status.set("Account removed from the list. Local data was kept.")

    def choose_app():
        path = filedialog.askopenfilename(title="Choose the official desktop app", parent=window)
        if path:
            store.set_app(Path(path))
            status.set("Desktop app location saved.")

    actions = ttk.Frame(outer)
    actions.pack(fill="x")
    ttk.Button(actions, text="Add account", command=lambda: safely(add)).pack(side="left")
    ttk.Button(actions, text="Open", command=lambda: safely(open_account)).pack(side="right")
    menu = tk.Menu(window, tearoff=False)
    accounts_menu = tk.Menu(menu, tearoff=False)
    for label, action in (("Add account…", add), ("Rename…", rename), ("Remove from list…", remove), ("Refresh", refresh), ("Choose app…", choose_app)):
        accounts_menu.add_command(label=label, command=lambda action=action: safely(action))
    accounts_menu.add_separator()
    accounts_menu.add_command(label="Quit", command=window.destroy)
    menu.add_cascade(label="Accounts", menu=accounts_menu)
    window.configure(menu=menu)
    tree.bind("<Double-1>", lambda event: safely(open_account))
    tree.bind("<Return>", lambda event: safely(open_account))
    window.bind("<F5>", lambda event: safely(refresh))
    window.report_callback_exception = lambda kind, value, trace: messagebox.showerror(TITLE, str(value), parent=window)
    safely(refresh)
    tree.focus_set()
    window.mainloop()


def main(argv=None):
    parser = argparse.ArgumentParser(description=TITLE + " for macOS and Linux")
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--add", metavar="NAME")
    actions.add_argument("--launch", metavar="NAME_OR_ID")
    actions.add_argument("--list", action="store_true")
    actions.add_argument("--install", action="store_true")
    actions.add_argument("--version", action="version", version=VERSION)
    parser.add_argument("--data-dir", type=Path, default=None)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args(argv)
    try:
        store = Store(args.data_dir or data_root())
        if args.install:
            from install import install_current
            install_current()
        elif args.add is not None:
            print(json.dumps(store.add(args.add), ensure_ascii=False))
        elif args.list:
            print(json.dumps(store.accounts(), ensure_ascii=False, indent=2))
        elif args.launch is not None:
            launch(store, args.launch, args.app)
        else:
            if args.app:
                store.set_app(args.app)
            picker(store)
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        if args.install or not any((args.add is not None, args.launch is not None, args.list)):
            import tkinter as tk
            from tkinter import messagebox
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror(TITLE, str(error), parent=root)
            root.destroy()
        elif sys.stderr:
            print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
