"""Exercise the real Tk widgets with synthetic accounts and mocked app launches."""
from pathlib import Path
import tempfile
import tkinter as tk
from tkinter import ttk
from unittest.mock import Mock, patch

import switcher


def descendants(widget):
    for child in widget.winfo_children():
        yield child
        yield from descendants(child)


work = Path(__file__).resolve().parent.parent / "work"
work.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=work) as directory:
    store = switcher.Store(Path(directory).resolve() / "profiles")
    account = store.add("Work & Personal")
    for n in range(20):
        store.add(f"Test account {n + 1}")
    process = Mock()
    process.poll.return_value = None

    def inspect(window):
        try:
            window.update()
            widgets = list(descendants(window))
            tree = next(w for w in widgets if isinstance(w, ttk.Treeview))
            assert len(tree.get_children()) == 22, "The picker lost profiles"
            tree.selection_set(account["id"])
            window.focus_force()
            tree.focus_set()
            window.update()
            tree.event_generate("<Return>")
            window.update()
            launch.assert_called_once_with(store, account["id"])
            add = next(w for w in widgets if isinstance(w, ttk.Button) and w.cget("text") == "Add account")
            with patch("tkinter.simpledialog.askstring", return_value="New account"):
                add.invoke()
            assert len(tree.get_children()) == 23, "Add did not refresh the picker"
            assert store.find("New account")
            window.geometry("430x340")
            window.update()
            assert tree.winfo_width() <= window.winfo_width(), "Account list overflows the window"
        finally:
            window.destroy()

    with patch("switcher.launch", return_value=process) as launch, patch.object(tk.Tk, "mainloop", inspect):
        switcher.picker(store)
print("PASS: real Tk picker, keyboard launch, add, scrolling and minimum width.")
