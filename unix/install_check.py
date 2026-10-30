"""Offline installer checks; all destinations are disposable fixtures."""
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import install


class Installer(unittest.TestCase):
    def setUp(self):
        work = Path(__file__).resolve().parent.parent / "work"
        work.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=work)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "download" / "Switcher"
        self.source.mkdir(parents=True)
        (self.source / install.MARKER).write_text(install.IDENTITY)
        (self.source / "codex-account-switcher").write_text("version one")
        self.destination = self.root / "User programs" / "Switcher"

    def tearDown(self):
        self.temp.cleanup()

    def test_install_upgrade_and_repair(self):
        desktop = self.root / "Menu entries" / "codex-account-switcher.desktop"
        install.install_bundle(self.source, self.destination, desktop)
        self.assertEqual((self.destination / "codex-account-switcher").read_text(), "version one")
        self.assertIn("Name=Codex Account Switcher", desktop.read_text())
        self.assertIn("Exec=", desktop.read_text())
        data = self.root / "profiles" / "keep.txt"
        data.parent.mkdir()
        data.write_text("keep")
        (self.source / "codex-account-switcher").write_text("version two")
        install.install_bundle(self.source, self.destination, desktop)
        self.assertEqual((self.destination / "codex-account-switcher").read_text(), "version two")
        install.install_bundle(self.destination, self.destination, desktop)
        self.assertEqual(data.read_text(), "keep")

    def test_mac_marker_stays_inside_resources(self):
        bundle = self.root / "download" / "Switcher.app"
        resources = bundle / "Contents" / "Resources"
        resources.mkdir(parents=True)
        (resources / install.MARKER).write_text(install.IDENTITY)
        destination = self.root / "Applications" / "Switcher.app"
        install.install_bundle(bundle, destination)
        self.assertEqual((destination / "Contents" / "Resources" / install.MARKER).read_text(), install.IDENTITY)
        self.assertFalse((destination / install.MARKER).exists())

    def test_unrelated_and_nested_destinations_refused(self):
        self.destination.mkdir(parents=True)
        sentinel = self.destination / "my-file"
        sentinel.write_text("keep")
        with self.assertRaises(ValueError):
            install.install_bundle(self.source, self.destination)
        self.assertEqual(sentinel.read_text(), "keep")
        for destination in (self.source / "nested", self.source.parent):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                install.install_bundle(self.source, destination)

    def test_copy_failure_keeps_previous_version(self):
        install.install_bundle(self.source, self.destination)
        with patch("install.shutil.copytree", side_effect=OSError("simulated disk full")), self.assertRaises(OSError):
            install.install_bundle(self.source, self.destination)
        self.assertEqual((self.destination / "codex-account-switcher").read_text(), "version one")

    def test_swap_failure_restores_previous_version(self):
        install.install_bundle(self.source, self.destination)
        real_replace = os.replace

        def fail_swap(source, destination):
            if Path(source).name == "incoming":
                raise OSError("simulated rename failure")
            return real_replace(source, destination)

        with patch("install.os.replace", side_effect=fail_swap), self.assertRaises(OSError):
            install.install_bundle(self.source, self.destination)
        self.assertEqual((self.destination / "codex-account-switcher").read_text(), "version one")

    def test_menu_failure_keeps_program_installed(self):
        with patch("install.atomic_write", side_effect=OSError("simulated shortcut failure")), self.assertRaises(OSError):
            install.install_bundle(self.source, self.destination, self.root / "menu.desktop")
        self.assertEqual((self.destination / "codex-account-switcher").read_text(), "version one")

    def test_desktop_exec_escaping(self):
        path = PurePosixPath('/home/a "quote"/$name`/100%/codex-account-switcher')
        text = install.desktop_entry(path)
        self.assertIn(r'\\"quote\\"', text)
        self.assertIn('\\$', text)
        self.assertIn('\\`', text)
        self.assertIn('100%%', text)
        self.assertNotIn("sh -c", text)
        with self.assertRaises(ValueError):
            install.desktop_entry(Path("/bad\npath/program"))

    @unittest.skipUnless(sys.platform.startswith("linux") and shutil.which("gio"), "Needs Linux desktop entry launcher")
    def test_real_desktop_entry_launch_with_special_characters(self):
        folder = self.root / 'spaces "quote" $cash` 100%'
        folder.mkdir()
        program = folder / "codex-account-switcher"
        output = self.root / "menu-launched"
        program.write_text('#!/bin/sh\nprintf "launched" > "$SWITCHER_MENU_CAPTURE"\n')
        program.chmod(0o755)
        desktop = self.root / "test.desktop"
        desktop.write_text(install.desktop_entry(program))
        subprocess.run(["desktop-file-validate", str(desktop)], check=True)
        env = os.environ.copy()
        env["SWITCHER_MENU_CAPTURE"] = str(output)
        subprocess.run(["gio", "launch", str(desktop)], env=env, check=True, timeout=10)
        for _ in range(100):
            if output.exists():
                break
            time.sleep(0.05)
        self.assertEqual(output.read_text(), "launched")

    @unittest.skipIf(os.name == "nt", "Unix links tested on native CI")
    def test_symlink_destinations_refused_and_bundle_links_preserved(self):
        outside = self.root / "outside"
        outside.mkdir()
        self.destination.parent.mkdir()
        self.destination.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            install.install_bundle(self.source, self.destination)
        self.destination.unlink()
        (self.source / "internal-link").symlink_to("codex-account-switcher")
        install.install_bundle(self.source, self.destination)
        self.assertTrue((self.destination / "internal-link").is_symlink())
        (self.source / "external-link").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            install.install_bundle(self.source, self.destination)


if __name__ == "__main__":
    unittest.main(verbosity=2)
