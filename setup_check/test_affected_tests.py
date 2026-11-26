"""dev/affected_tests.py: which test files it lists for a diff and how --run reports them, tested on a
planted repository of small Gleam-like files (no Gleam build).

Each test copies the script into a temporary git repository (a branch `feature` of `main`) and runs
that copy; `--run` runs it with a PATH whose `gleam` is a stub that prints a pass line for a file whose
text holds "PLANT_PASS" and a failure line and exit status 1 for any other.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_affected_tests.py'
"""

import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "dev" / "affected_tests.py"

RUNNABLE = shutil.which("git") is not None and shutil.which("sh") is not None

GLEAM_STUB = """#!/bin/sh
# gleam test -- FILE
file=$3
echo "compiling noise"
if grep -q PLANT_PASS "$file"; then
  echo "3 passed, no failures"
  exit 0
fi
echo "1) planted_test.the_planted_rule_test (1ms)"
echo "2 passed, 1 failures"
exit 1
"""


@unittest.skipUnless(RUNNABLE, "the affected-tests script's tests need git and sh here")
class AffectedTestsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="genesis-affected-tests-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.repository = self.root / "repository"
        (self.repository / "dev").mkdir(parents=True)
        shutil.copyfile(SCRIPT, self.repository / "dev" / "affected_tests.py")
        self.write("src/genesis_prime/m.gleam", "pub fn m() { 1 }\n")
        self.write("src/genesis_prime/n.gleam", "import genesis_prime/m\n")
        self.write("src/genesis_prime/x.gleam", "import genesis_prime/m.{m}\n")
        self.write("src/genesis_prime/other.gleam", "pub fn other() { 1 }\n")
        self.write("test/a_test.gleam", "import genesis_prime/m\n")
        self.write("test/b_test.gleam", "import genesis_prime/x as ex\nimport support\n")
        self.write("test/support.gleam", "import genesis_prime/other\n")
        self.write("test/c_test.gleam", 'const path = "genesis_prime/m.gleam"\nimport genesis_prime/other\n')
        self.write("test/d_test.gleam", "import support\nimport genesis_prime/other\n")
        self.write("test/e_test.gleam", "import genesis_prime/other\n")
        self.git("init", "-q", "-b", "main")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "planted repository")
        self.git("checkout", "-q", "-b", "feature")

    def write(self, path: str, text: str) -> None:
        (self.repository / path).parent.mkdir(parents=True, exist_ok=True)
        (self.repository / path).write_text(text)

    def git(self, *arguments: str) -> str:
        done = subprocess.run(
            ["git", "-c", "user.name=Planted", "-c", "user.email=planted@example.invalid", *arguments],
            cwd=self.repository, capture_output=True, text=True, check=True,
        )
        return done.stdout.strip()

    def change(self, *paths: str) -> None:
        for path in paths:
            with open(self.repository / path, "a") as changed:
                changed.write("// changed on the branch\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "change")

    def listed(self) -> list[str]:
        done = subprocess.run(
            [sys.executable, "-I", "dev/affected_tests.py", "main", "HEAD"],
            cwd=self.repository, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        return done.stdout.splitlines()

    def test_a_test_that_imports_a_changed_module_is_listed(self):
        self.change("src/genesis_prime/m.gleam")
        self.assertIn("test/a_test.gleam", self.listed())

    def test_a_test_that_reaches_a_changed_module_through_other_imports_is_listed(self):
        self.change("src/genesis_prime/m.gleam")
        self.assertIn("test/b_test.gleam", self.listed())

    def test_a_test_that_names_a_changed_modules_path_in_its_text_is_listed(self):
        self.change("src/genesis_prime/m.gleam")
        self.assertIn("test/c_test.gleam", self.listed())

    def test_a_test_that_reaches_no_changed_module_is_not_listed(self):
        self.change("src/genesis_prime/m.gleam")
        listed = self.listed()
        self.assertIn("test/a_test.gleam", listed, "the list is not empty")
        self.assertNotIn("test/d_test.gleam", listed)
        self.assertNotIn("test/e_test.gleam", listed)

    def test_a_changed_test_file_is_listed(self):
        self.change("test/e_test.gleam")
        self.assertEqual(self.listed(), ["test/e_test.gleam"])

    def test_a_cycle_in_the_import_graph_ends(self):
        self.write("src/genesis_prime/p.gleam", "import genesis_prime/q\n")
        self.write("src/genesis_prime/q.gleam", "import genesis_prime/p\n")
        self.write("test/f_test.gleam", "import genesis_prime/q\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "a malformed cycle")
        self.git("branch", "-f", "main")
        self.change("src/genesis_prime/p.gleam")
        self.assertEqual(self.listed(), ["test/f_test.gleam"])

    def test_run_reports_each_files_last_line_and_fails_when_one_fails(self):
        self.write("test/a_test.gleam", "import genesis_prime/m\n// PLANT_PASS\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "a passing test")
        self.git("branch", "-f", "main")
        self.change("src/genesis_prime/m.gleam")
        executable = self.root / "tools" / "gleam"
        executable.parent.mkdir()
        executable.write_text(GLEAM_STUB)
        executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
        done = subprocess.run(
            [sys.executable, "-I", "dev/affected_tests.py", "main", "HEAD", "--run"],
            cwd=self.repository, capture_output=True, text=True, timeout=60,
            env={"PATH": "%s:/usr/bin:/bin" % executable.parent, "HOME": str(self.root)},
        )
        self.assertIn("test/a_test.gleam: 3 passed, no failures", done.stdout)
        self.assertIn("test/c_test.gleam: 2 passed, 1 failures", done.stdout)
        self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)


if __name__ == "__main__":
    unittest.main()
