"""dev/migration_base.py: a pull request changes no migration its base already has.

Each test plants a git repository whose commit `base` holds two migrations, changes it
in a second commit (HEAD) and runs the script with `base` as BASE, as CI runs it with the
first parent of the merge commit. Exit status: 0 nothing of the base's migrations
changed, 1 one did (the output names the file), 2 the arguments or the commit are wrong.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_migration_base.py'
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "dev" / "migration_base.py"
RUNNABLE = shutil.which("git") is not None


@unittest.skipUnless(RUNNABLE, "the migration guard's tests need git")
class MigrationBaseTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="genesis-migration-base-")
        self.addCleanup(directory.cleanup)
        self.repository = Path(directory.name).resolve()
        (self.repository / "priv" / "migrations").mkdir(parents=True)
        (self.repository / "priv" / "migrations" / "0001_a.sql").write_text("create table a ();\n")
        (self.repository / "priv" / "migrations" / "0002_b.sql").write_text("create table b ();\n")
        (self.repository / "test").mkdir()
        (self.repository / "test" / "migration_hashes.txt").write_text("0001_a one\n0002_b two\n")
        self.git("init", "-q", "-b", "main")
        self.commit("base")
        self.git("tag", "base")

    def git(self, *arguments: str) -> None:
        subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *arguments],
            cwd=self.repository,
            check=True,
            capture_output=True,
        )

    def commit(self, message: str) -> None:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def run_script(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), *arguments],
            cwd=self.repository,
            capture_output=True,
            text=True,
        )

    def test_a_changed_migration_fails_even_when_its_row_of_the_list_is_changed_too(self):
        migrations = self.repository / "priv" / "migrations"
        (migrations / "0002_b.sql").write_text("create table b (x int);\n")
        (self.repository / "test" / "migration_hashes.txt").write_text("0001_a one\n0002_b three\n")
        self.commit("change a migration and its row")
        done = self.run_script("base")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("modified priv/migrations/0002_b.sql", done.stdout)
        self.assertNotIn("0001_a", done.stdout)

    def test_a_deleted_or_renamed_migration_fails_naming_the_file(self):
        migrations = self.repository / "priv" / "migrations"
        (migrations / "0001_a.sql").unlink()
        self.git("mv", str(migrations / "0002_b.sql"), str(migrations / "0002_c.sql"))
        self.commit("delete one, rename one")
        done = self.run_script("base")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("deleted or renamed away priv/migrations/0001_a.sql", done.stdout)
        self.assertIn("deleted or renamed away priv/migrations/0002_b.sql", done.stdout)
        self.assertNotIn("0002_c", done.stdout)

    def test_an_added_migration_and_a_change_outside_the_folder_pass(self):
        migrations = self.repository / "priv" / "migrations"
        (migrations / "0003_c.sql").write_text("create table c ();\n")
        (self.repository / "test" / "migration_hashes.txt").write_text("0001_a one\n0002_b two\n0003_c x\n")
        self.commit("add a migration")
        done = self.run_script("base")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(done.stdout, "")

    def test_a_commit_that_git_does_not_know_and_a_missing_argument_exit_2(self):
        self.assertEqual(self.run_script("no-such-commit").returncode, 2)
        self.assertEqual(self.run_script().returncode, 2)


if __name__ == "__main__":
    unittest.main()
