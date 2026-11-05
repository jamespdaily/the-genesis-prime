"""Tests of report.sh's argument checks, which run before the script reads env.sh or reaches the PC.

Each case runs report.sh with GENESIS_HOME set to an empty folder and no GENESIS_PLAY_PC, so a call
whose arguments pass goes on to pc.sh and stops there on the missing GENESIS_PLAY_PC: that message
proves the arguments were accepted, and its absence that they were refused before the PC was
reached. A usage refusal exits 2.
"""

import os
import subprocess
import tempfile
import unittest

REPORT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "report.sh")
NEEDS_PC = "set GENESIS_PLAY_PC"


class ReportArgumentsTest(unittest.TestCase):
    def run_report(self, *args):
        with tempfile.TemporaryDirectory() as home:
            env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "GENESIS_HOME": home}
            done = subprocess.run(["bash", REPORT, *args], env=env, capture_output=True, text=True, timeout=30)
        return done.returncode, done.stderr

    def assert_usage(self, *args):
        status, stderr = self.run_report(*args)
        self.assertEqual(status, 2, f"{args}: {stderr}")
        self.assertNotIn(NEEDS_PC, stderr)
        self.assertIn("report.sh collect", stderr)

    def assert_accepted(self, *args):
        status, stderr = self.run_report(*args)
        self.assertEqual(status, 1, f"{args}: {stderr}")
        self.assertIn(NEEDS_PC, stderr)

    def test_collect_by_hand_with_no_folder_is_refused_and_does_not_take_the_flag_as_the_folder(self):
        self.assert_usage("collect", "--by-hand")

    def test_a_folder_that_looks_like_a_flag_is_refused(self):
        for args in (("collect", "--by-hand", "--by-hand"), ("collect", "--folder"), ("collect", "--by-hand", "--x")):
            with self.subTest(args=args):
                self.assert_usage(*args)

    def test_collect_with_a_folder_reaches_the_pc(self):
        for args in (("collect", "folder"), ("collect", "--by-hand", "folder"), ("collect", "./a/b")):
            with self.subTest(args=args):
                self.assert_accepted(*args)

    def test_collect_with_no_arguments_or_too_many_is_refused(self):
        for args in (("collect",), ("collect", "a", "b"), ("collect", "folder", "--by-hand"),
                     ("collect", "--by-hand", "a", "b")):
            with self.subTest(args=args):
                self.assert_usage(*args)

    def test_a_timeline_of_1_to_600_minutes_reaches_the_pc(self):
        for args in (("install", "--timeline"), ("install", "--timeline", "1"), ("install", "--timeline", "600"),
                     ("install", "--with-broken", "--timeline", "20")):
            with self.subTest(args=args):
                self.assert_accepted(*args)

    def test_a_timeline_outside_1_to_600_minutes_is_refused(self):
        for minutes in ("0", "601", "05", "-3", "1.5", "20m"):
            with self.subTest(minutes=minutes):
                self.assert_usage("install", "--timeline", minutes)

    def test_an_unknown_command_or_flag_is_refused(self):
        for args in ((), ("frobnicate",), ("install", "--nope"), ("remove", "now")):
            with self.subTest(args=args):
                self.assert_usage(*args)


if __name__ == "__main__":
    unittest.main()
