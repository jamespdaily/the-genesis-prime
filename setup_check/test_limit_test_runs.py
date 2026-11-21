"""dev/hooks/limit_test_runs.py: refuses a command that starts a test run while as many already run
as the machine has test slots (dev/hooks/machine_slots.py), and a `gleam test` command that writes a
unitest option as `--flag=value`.

The hook's `refusal(command, rows)` takes the command and the rows of `ps -axo pid=,ppid=,command=`
split into pid, parent pid and command, so no real process is read. Evidence for the equals sign:
unitest's options match the exact word (`--test`) and take the next word; clip's `arg` skips an
unknown word that starts with `-` (build/packages/clip/src/clip/arg.gleam), so `--test=x` runs the
whole suite, and test/genesis_prime_test.gleam `runs_chosen_tests` (`starts_with "--test"`) then
reads it as a chosen run.

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_limit_test_runs.py'
"""

import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "dev" / "hooks"))

import limit_test_runs  # noqa: E402
import machine_slots  # noqa: E402

GLEAM_TEST = "gleam test -- test/a_test.gleam"
TWO_RUNS = [["101", "1", "gleam test -- test/b_test.gleam"], ["102", "1", "./check fast"]]


class LimitTestRunsTest(unittest.TestCase):
    def test_a_third_test_run_is_refused_and_a_second_is_not(self):
        self.assertIsNone(limit_test_runs.refusal(GLEAM_TEST, TWO_RUNS[:1]))
        refused = limit_test_runs.refusal(GLEAM_TEST, TWO_RUNS)
        self.assertIsNotNone(refused)
        self.assertIn("pid 101", refused)
        self.assertIn("pid 102", refused)
        started_by_a_run = TWO_RUNS[:1] + [["103", "101", "gleam test -- test/c_test.gleam"]]
        self.assertIsNone(limit_test_runs.refusal(GLEAM_TEST, started_by_a_run), "a run started by a run is not counted")
        self.assertIsNone(limit_test_runs.refusal("git status", TWO_RUNS), "a command that starts no run passes")
        self.assertIsNotNone(limit_test_runs.refusal("SALT=x gleam test -- --seed 7", TWO_RUNS), "a variable prefix starts a run")

    def test_a_gleam_test_option_written_with_an_equals_sign_is_refused_naming_the_form(self):
        for command in (
            "gleam test -- --test=a_test.x_test",
            "gleam test -- --tag=serial",
            "gleam test -- --seed=7",
            "gleam test -- test/a_test.gleam --module=a_test",
            "cd x && gleam test -- --workers=1",
            "gleam test -- --reporter=table",
            "gleam test -- --sort=name",
        ):
            with self.subTest(command=command):
                refused = limit_test_runs.refusal(command, [])
                self.assertIsNotNone(refused)
                self.assertIn("--test module.fn", refused)
                self.assertIn("with a space", refused)

    def test_the_spaced_form_and_an_equals_sign_inside_a_value_pass(self):
        for command in (
            "gleam test -- --test a_test.x_test",
            "GENESIS_TEST_SEED_SALT=x gleam test -- test/a_test.gleam --seed 7",
            "gleam test -- --test a_test.x_test && git commit -m 'use --seed=7'",
            "echo --test=x",
        ):
            with self.subTest(command=command):
                self.assertIsNone(limit_test_runs.refusal(command, []))

    def test_the_limit_is_the_number_of_test_slots(self):
        with mock.patch.object(machine_slots, "TEST_SLOTS", 3):
            self.assertIsNone(limit_test_runs.refusal(GLEAM_TEST, TWO_RUNS))
            three = TWO_RUNS + [["103", "1", "gleam test"]]
            refused = limit_test_runs.refusal(GLEAM_TEST, three)
        self.assertIsNotNone(refused)
        self.assertIn("3 test slots", refused)


if __name__ == "__main__":
    unittest.main()
