"""Smoke-test the actual frozen app with a disposable home for profile data."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

binary = Path(sys.argv[1]).resolve()
work = Path(__file__).resolve().parent.parent / "work"
with tempfile.TemporaryDirectory(dir=work) as directory:
    root = Path(directory).resolve()
    data = root / "Profile data with spaces"

    def run(*args):
        return subprocess.run([str(binary), "--data-dir", str(data), *args], capture_output=True, text=True, check=True, timeout=30).stdout

    assert "1.6.0" in run("--version")
    run("--add", "Work & personal")
    accounts = json.loads(run("--list"))
    assert accounts[0]["display"] == "Work & personal"
    capture = root / "fake desktop app"
    output = root / "received.txt"
    capture.write_text('#!/bin/sh\nprintf "%s\\n" "$CODEX_HOME" "$CODEX_ELECTRON_USER_DATA_PATH" "$1" > "$SWITCHER_CAPTURE"\n')
    capture.chmod(0o755)
    env = os.environ.copy()
    env["SWITCHER_CAPTURE"] = str(output)
    subprocess.run([str(binary), "--data-dir", str(data), "--app", str(capture), "--launch", accounts[0]["id"]], env=env, check=True, timeout=30)
    for _ in range(100):
        if output.exists():
            break
        time.sleep(0.05)
    base = data / accounts[0]["id"]
    assert output.read_text().splitlines() == [str(base / "codex"), str(base / "electron"), "--user-data-dir=" + str(base / "electron")]
    process = subprocess.Popen([str(binary), "--data-dir", str(data)])
    try:
        time.sleep(3)
        assert process.poll() is None, "Frozen GUI exited before displaying its picker"
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=10)
print("PASS: frozen version, add/list, profile launch environment and GUI startup.")
