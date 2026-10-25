"""How the fast suite treats the client and Ghidra: which tests skip, and when.

The rule fixed here: a test that opens WildStar64.exe skips only when
GENESIS_NO_CLIENT=1 (which only CI sets), through the one decorator
check_support.needs_client, and on any other machine a missing
client fails it; a test that needs a Ghidra install, a JDK or a seeded
project is an integration test, gated by check_support.integration_only like
test_query_process.py's. The decorator is run in a subprocess on a planted
test class with a client path that points nowhere; the other tests read this
directory's own test files. Run: python3 -I test_check_support.py
"""

import ast
import os
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_support as cs  # noqa: E402

THIS_FILE = Path(__file__).name
NOWHERE = "/nowhere/WildStar64.exe"

# What opens the client's file, by name.
CLIENT_NAMES = {"client_exe", "client_pe", "raw_pe", "ClientPE", "RawPE", "planted_client_exe"}
# What needs Ghidra, a JDK, PyGhidra or a seeded project, by name.
GHIDRA_NAMES = {"planted_ghidra_dir", "seeded_project", "fresh_unseeded_project", "QueryProcess"}
GHIDRA_VARIABLES = {"GENESIS_GHIDRA_DIR", "GENESIS_GHIDRA_PROJECT_DIR", "GENESIS_PYGHIDRA_PYTHON", "JAVA_HOME"}

PLANTED_PROGRAM = """
import os
import sys
import unittest

sys.path.insert(0, {scripts!r})
import check_support as cs

{planted}

suite = unittest.defaultTestLoader.loadTestsFromTestCase(Planted)
result = unittest.TextTestRunner(stream=open(os.devnull, "w")).run(suite)
print(len(result.skipped), len(result.errors) + len(result.failures))
"""

PLANTED_CLASS = """
@cs.needs_client
class Planted(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blob = cs.client_exe().read_bytes()

    def test_opens_the_client(self):
        self.assertTrue(self.blob)
"""

PLANTED_METHOD = """
class Planted(unittest.TestCase):
    @cs.needs_client
    def test_opens_the_client(self):
        self.assertTrue(cs.client_exe().read_bytes())
"""


def run_planted(planted: str, flag: str | None) -> tuple[int, int]:
    """(skipped, failed) of the planted tests run in a fresh interpreter whose client path points nowhere."""
    env = {k: v for k, v in os.environ.items() if k not in ("GENESIS_NO_CLIENT", "WILDSTAR_CLIENT_EXE")}
    env["WILDSTAR_CLIENT_EXE"] = NOWHERE
    if flag is not None:
        env["GENESIS_NO_CLIENT"] = flag
    program = PLANTED_PROGRAM.format(scripts=str(cs.SCRIPTS), planted=planted)
    done = subprocess.run([sys.executable, "-I", "-c", program], env=env, capture_output=True, text=True)
    assert done.returncode == 0, done.stderr
    skipped, failed = done.stdout.split()
    return int(skipped), int(failed)


class NeedsClientTest(unittest.TestCase):
    def test_a_class_that_opens_the_client_is_skipped_when_the_flag_is_1_and_it_never_starts(self):
        # the planted class's setUpClass would fail on the missing client; a skip stops it first
        self.assertEqual(run_planted(PLANTED_CLASS, "1"), (1, 0))

    def test_a_method_that_opens_the_client_is_skipped_when_the_flag_is_1(self):
        self.assertEqual(run_planted(PLANTED_METHOD, "1"), (1, 0))

    def test_a_missing_client_fails_the_class_when_the_flag_is_not_set(self):
        self.assertEqual(run_planted(PLANTED_CLASS, None), (0, 1))

    def test_a_missing_client_fails_the_method_when_the_flag_is_not_set(self):
        self.assertEqual(run_planted(PLANTED_METHOD, None), (0, 1))

    def test_a_flag_that_is_not_exactly_1_does_not_skip(self):
        # "only when GENESIS_NO_CLIENT=1": each of these must still fail on the missing client
        for value in ("0", "", "true", "yes"):
            with self.subTest(flag=value):
                self.assertEqual(run_planted(PLANTED_CLASS, value), (0, 1))


def test_files() -> list[Path]:
    return sorted(p for p in Path(__file__).resolve().parent.glob("test_*.py") if p.name != THIS_FILE)


def decorator_names(node: ast.AST) -> set[str]:
    names = set()
    for decorator in getattr(node, "decorator_list", []):
        names.add(decorator.attr if isinstance(decorator, ast.Attribute) else getattr(decorator, "id", ""))
    return names


def names_used(node: ast.AST) -> set[str]:
    """Bare names and check_support's attributes (cs.x); another object's attribute of the
    same name, such as a settings record's client_exe field, is not a use."""
    found = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Name):
            found.add(child.id)
        elif isinstance(child, ast.Attribute) and isinstance(child.value, ast.Name) and child.value.id == "cs":
            found.add(child.attr)
    return found


def ghidra_variables_required(node: ast.AST) -> set[str]:
    """The environment variables a node demands through require_env("...")."""
    found = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Call) and names_used(child.func) & {"require_env"} and child.args:
            argument = child.args[0]
            if isinstance(argument, ast.Constant) and argument.value in GHIDRA_VARIABLES:
                found.add(argument.value)
    return found


def uncovered(needed: set[str], used_by, decorator: str) -> list[str]:
    """Each test class (as file::Class) that uses a name in `needed` with neither the class nor
    every one of its test methods that use it carrying `decorator`, and that is not exempt."""
    problems = []
    for path in test_files():
        for cls in [n for n in ast.parse(path.read_text()).body if isinstance(n, ast.ClassDef)]:
            if decorator in decorator_names(cls) or "integration_only" in decorator_names(cls):
                continue
            for method in [n for n in cls.body if isinstance(n, ast.FunctionDef)]:
                if used_by(method) & needed and decorator not in decorator_names(method):
                    problems.append(f"{path.name}::{cls.name}.{method.name}")
    return problems


class EveryTestThatNeedsTheClientIsMarkedTest(unittest.TestCase):
    def test_every_test_class_that_opens_the_client_carries_needs_client(self):
        problems = uncovered(CLIENT_NAMES, names_used, "needs_client")
        self.assertEqual(problems, [], "these tests open the client and are not marked @cs.needs_client")

    def test_only_check_support_names_the_flag(self):
        # one decorator, one place: no test file reads GENESIS_NO_CLIENT itself
        naming = [p.name for p in test_files() if "GENESIS_NO_CLIENT" in p.read_text()]
        self.assertEqual(naming, [])


class EveryTestThatNeedsGhidraIsAnIntegrationTest(unittest.TestCase):
    def test_every_test_that_needs_ghidra_is_gated_by_integration_only(self):
        def needs(node: ast.AST) -> set[str]:
            return (names_used(node) & GHIDRA_NAMES) | ghidra_variables_required(node)

        problems = uncovered(GHIDRA_NAMES | GHIDRA_VARIABLES, needs, "integration_only")
        self.assertEqual(problems, [], "these tests need Ghidra and run in the fast suite")

    def test_the_three_ghidra_reading_tests_are_integration_tests(self):
        # the 3 tests of test_ghidra_env.py that read GENESIS_GHIDRA_DIR
        tree = ast.parse((Path(__file__).resolve().parent / "test_ghidra_env.py").read_text())
        gated = {
            f"{cls.name}.{m.name}"
            for cls in tree.body
            if isinstance(cls, ast.ClassDef) and "integration_only" in decorator_names(cls)
            for m in cls.body
            if isinstance(m, ast.FunctionDef) and m.name.startswith("test_")
        }
        self.assertEqual(
            gated,
            {
                "RealInstallTest.test_ghidra_version_reads_application_properties",
                "PlantedInstallTest.test_ghidra_version_reads_the_planted_version",
                "PlantedInstallTest.test_check_parts_refuses_another_ghidra_version_and_names_it",
            },
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
