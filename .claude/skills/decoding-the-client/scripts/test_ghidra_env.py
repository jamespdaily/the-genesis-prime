"""ghidra_env: the pinned parts and where they live.

Expected values: ghidra_version of the real install is 12.2 (the installed
release's Ghidra/application.properties, `application.version=12.2`; issue 24
decision 1). The wrong-version cases are planted: a copy of the install's
layout whose application.properties says 12.1.4, the version issue 16
measured. Run: python3 -I test_ghidra_env.py
"""

import hashlib
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402
import ghidra_env  # noqa: E402

VARIABLES = ("GENESIS_GHIDRA_DIR", "GENESIS_GHIDRA_PROJECT_DIR", "WILDSTAR_CLIENT_EXE", "JAVA_HOME")


class PinnedValuesTest(unittest.TestCase):
    def test_the_pins_are_the_ones_the_issue_decided(self):
        # issue 24: Ghidra 12.2, JDK 25, Python 3.13, PyGhidra 3.2.0
        self.assertEqual(ghidra_env.GHIDRA_VERSION, "12.2")
        self.assertEqual(ghidra_env.JDK_MAJOR, 25)
        self.assertEqual(ghidra_env.PYTHON_MINOR, (3, 13))
        self.assertEqual(ghidra_env.PYGHIDRA_VERSION, "3.2.0")

    def test_the_pinned_client_hash_is_the_clients_hash(self):
        # issue 16 trial
        self.assertEqual(
            ghidra_env.CLIENT_SHA256, "565c2fa1a1cf4b08cf5a93e0bff90bf09bde5772d03615402132d72db5fe0b10"
        )
        self.assertEqual(hashlib.sha256(cs.client_exe().read_bytes()).hexdigest(), ghidra_env.CLIENT_SHA256)


class SettingsTest(unittest.TestCase):
    ENV = {
        "GENESIS_GHIDRA_DIR": "/a/ghidra",
        "GENESIS_GHIDRA_PROJECT_DIR": "/a/project",
        "WILDSTAR_CLIENT_EXE": "/a/WildStar64.exe",
        "JAVA_HOME": "/a/jdk",
    }

    def test_settings_come_from_the_four_variables(self):
        s = ghidra_env.settings_from_env(self.ENV)
        self.assertEqual(
            (s.ghidra_dir, s.project_dir, s.client_exe, s.java_home),
            (Path("/a/ghidra"), Path("/a/project"), Path("/a/WildStar64.exe"), Path("/a/jdk")),
        )

    def test_a_missing_variable_is_refused_and_named(self):
        # planted: each variable removed in turn
        for name in VARIABLES:
            with self.subTest(missing=name):
                env = {k: v for k, v in self.ENV.items() if k != name}
                with self.assertRaises(ghidra_env.WrongVersion) as raised:
                    ghidra_env.settings_from_env(env)
                self.assertIn(name, str(raised.exception))


class RealInstallTest(unittest.TestCase):
    def test_ghidra_version_reads_application_properties(self):
        self.assertEqual(ghidra_env.ghidra_version(Path(cs.require_env("GENESIS_GHIDRA_DIR"))), "12.2")


class PlantedInstallTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        self.planted = cs.planted_ghidra_dir(Path(self._dir.name), "12.1.4")

    def test_ghidra_version_reads_the_planted_version(self):
        self.assertEqual(ghidra_env.ghidra_version(self.planted), "12.1.4")

    def test_check_parts_refuses_another_ghidra_version_and_names_it(self):
        settings = ghidra_env.Settings(
            ghidra_dir=self.planted,
            project_dir=Path(self._dir.name) / "project",
            client_exe=cs.client_exe(),
            java_home=Path(cs.require_env("JAVA_HOME")),
        )
        with self.assertRaises(ghidra_env.WrongVersion) as raised:
            ghidra_env.check_parts(settings)
        self.assertIn("12.1.4", str(raised.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)
