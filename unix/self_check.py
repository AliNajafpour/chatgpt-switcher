"""Run with python unix/self_check.py. Uses temporary files, never real accounts."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import switcher


class Profiles(unittest.TestCase):
    def setUp(self):
        work = Path(__file__).resolve().parent.parent / "work"
        work.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=work)
        self.root = Path(self.temp.name).resolve() / "Account data with spaces"
        self.store = switcher.Store(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_add_rename_remove_preserves_data(self):
        account = self.store.add("Work & personal")
        self.assertEqual(self.store.accounts()[0]["display"], "Work & personal")
        base, electron, codex = self.store.paths(account["id"])
        self.assertTrue(electron.is_dir() and codex.is_dir())
        sentinel = codex / "keep-this.txt"
        sentinel.write_text("local project")
        self.store.rename(account["id"], "Office")
        self.assertEqual(self.store.find("Office")["id"], account["id"])
        self.store.remove(account["id"])
        self.assertEqual(self.store.accounts(), [])
        self.assertEqual(sentinel.read_text(), "local project")
        self.assertEqual(json.loads((self.root / "accounts.json.bak").read_text())["accounts"][0]["display"], "Office")

    def test_invalid_and_duplicate_names(self):
        self.store.add("Work")
        for name in ("", "  ", "work", "bad\nname", "x" * 101):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.store.add(name)
        other = self.store.add("Personal")
        with self.assertRaises(ValueError):
            self.store.rename(other["id"], "WORK")

    def test_corrupt_config_is_not_overwritten(self):
        self.root.mkdir()
        config = self.root / "accounts.json"
        for raw in ('{', '{"accounts": null}', '{"accounts":[{"id":"../outside","display":"X"}]}',
                    '{"accounts":[{"id":"safe","display":"X","mode":"shared"}]}'):
            config.write_text(raw)
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                self.store.add("New")
            self.assertEqual(config.read_text(), raw)

    def test_invalid_paths(self):
        for key in ("..", "../escape", "a/b", "a\\b", "accounts.json", "__main__", "/tmp"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.store.paths(key)

    @unittest.skipIf(os.name == "nt", "Unix permissions and symlinks tested on native CI")
    def test_links_permissions_and_concurrent_lock(self):
        account = self.store.add("Work")
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.root / "accounts.json").stat().st_mode & 0o777, 0o600)
        outside = Path(self.temp.name).resolve() / "outside"
        outside.mkdir()
        _, electron, _ = self.store.paths(account["id"])
        electron.rmdir()
        electron.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.store.paths(account["id"])
        electron.unlink()
        with self.store.lock():
            with self.assertRaises(RuntimeError):
                self.store.add("Other")
        config = self.root / "accounts.json"
        config.unlink()
        config.symlink_to(outside / "other.json")
        with self.assertRaises(ValueError):
            self.store.add("Other")
        self.assertFalse((outside / "other.json").exists())

    def test_failed_save_preserves_config(self):
        self.store.add("Work")
        before = (self.root / "accounts.json").read_bytes()
        real_replace = os.replace

        def fail_config(source, target):
            if Path(target).name == "accounts.json":
                raise OSError("simulated full disk")
            return real_replace(source, target)

        with patch("switcher.os.replace", side_effect=fail_config), self.assertRaises(OSError):
            self.store.add("Personal")
        self.assertEqual((self.root / "accounts.json").read_bytes(), before)
        self.assertEqual([a["display"] for a in self.store.accounts()], ["Work"])

    def test_launch_arguments_and_environment_are_isolated(self):
        account = self.store.add("Work & $(echo unsafe)")
        app = Path(sys.executable)
        with patch.dict(os.environ, {"CODEX_HOME": "inherited", "CODEX_ELECTRON_USER_DATA_PATH": "inherited"}), patch("switcher.subprocess.Popen") as spawn:
            switcher.launch(self.store, account["id"], app)
            args, kwargs = spawn.call_args
            _, electron, codex = self.store.paths(account["id"])
            self.assertEqual(args[0], [str(app), "--user-data-dir=" + str(electron)])
            self.assertEqual(kwargs["env"]["CODEX_HOME"], str(codex))
            self.assertEqual(kwargs["env"]["CODEX_ELECTRON_USER_DATA_PATH"], str(electron))
            self.assertFalse(kwargs.get("shell", False))
            switcher.launch(self.store, "__main__", app)
            self.assertNotIn("CODEX_HOME", spawn.call_args.kwargs["env"])
            self.assertNotIn("CODEX_ELECTRON_USER_DATA_PATH", spawn.call_args.kwargs["env"])
            self.assertEqual(os.environ["CODEX_HOME"], "inherited")
        with self.assertRaises(ValueError):
            switcher.launch(self.store, "missing", app)

    def test_real_process_receives_profile_paths(self):
        account = self.store.add("Personal")
        capture = Path(self.temp.name) / "capture.py"
        output = Path(self.temp.name) / "capture.json"
        capture.write_text("import os,sys,json; open(sys.argv[1],'w').write(json.dumps([os.environ.get('CODEX_HOME'),os.environ.get('CODEX_ELECTRON_USER_DATA_PATH'),sys.argv[2:]]))")
        real_spawn = subprocess.Popen

        def substitute(argv, **kwargs):
            return real_spawn([sys.executable, str(capture), str(output), *argv[1:]], **kwargs)

        with patch("switcher.subprocess.Popen", side_effect=substitute):
            process = switcher.launch(self.store, account["id"], Path(sys.executable))
            process.wait(timeout=10)
        _, electron, codex = self.store.paths(account["id"])
        self.assertEqual(json.loads(output.read_text()), [str(codex), str(electron), ["--user-data-dir=" + str(electron)]])

    def test_mac_bundle_and_linux_detection(self):
        bundle = Path(self.temp.name) / "Codex.app"
        binary = bundle / "Contents" / "MacOS" / "Codex"
        binary.parent.mkdir(parents=True)
        binary.write_text("fixture")
        binary.chmod(0o755)
        import plistlib
        with (bundle / "Contents" / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleExecutable": "Codex"}, stream)
        self.assertEqual(switcher.executable(bundle), binary)
        with (bundle / "Contents" / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleExecutable": "../../escape"}, stream)
        with self.assertRaises(ValueError):
            switcher.executable(bundle)
        with patch("switcher.sys.platform", "linux"), patch("switcher.shutil.which", return_value=str(sys.executable)) as which:
            self.assertEqual(switcher.detect_app(), Path(sys.executable))
            self.assertEqual(which.call_args_list[0].args, ("chatgpt",))


if __name__ == "__main__":
    unittest.main(verbosity=2)
