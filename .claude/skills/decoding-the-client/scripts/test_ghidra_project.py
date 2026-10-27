"""ghidra_project.open_project: what it refuses before it starts Ghidra.

Plain tests: they never reach Ghidra, so the settings below point at paths that
do not exist, and that none is touched is part of what is checked. The open of a
real project, seeded or explicitly unseeded, is checked by test_query_process.py.
Run: python3 -I test_ghidra_project.py
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ghidra_project  # noqa: E402
from ghidra_env import Settings  # noqa: E402


class FirstOpenNeedsASeedTest(unittest.TestCase):
    def settings(self, root: Path) -> Settings:
        return Settings(
            ghidra_dir=root / "no-ghidra",
            project_dir=root / "project",
            client_exe=root / "no-client.exe",
            java_home=root / "no-java",
        )

    def test_open_project_with_no_project_and_no_seed_raises_and_the_project_folder_holds_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            settings = self.settings(root)
            settings.project_dir.mkdir()
            with self.assertRaises(ghidra_project.SeedRequired) as caught:
                ghidra_project.open_project(settings, None)
            self.assertIn(str(settings.project_dir), str(caught.exception))
            self.assertEqual(list(settings.project_dir.iterdir()), [])

    def test_open_project_with_no_project_folder_and_no_seed_raises_and_makes_no_folder(self):
        with tempfile.TemporaryDirectory() as d:
            settings = self.settings(Path(d))
            with self.assertRaises(ghidra_project.SeedRequired):
                ghidra_project.open_project(settings, None)
            self.assertFalse(settings.project_dir.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
