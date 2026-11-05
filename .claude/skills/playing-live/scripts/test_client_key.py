"""Tests of client.sh key's argument checks, which run before the script reads env.sh or reaches the PC.

Each case runs client.sh with GENESIS_HOME set to an empty folder and no GENESIS_PLAY_PC, so a call
whose arguments pass goes on to pc.sh and stops there on the missing GENESIS_PLAY_PC: that message
proves the arguments were accepted, and its absence that they were refused before the PC was
reached. A usage refusal exits 2; a takeover without --pc-free exits 1 with its own message.
"""

import os
import subprocess
import tempfile
import unittest

CLIENT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "client.sh")
NEEDS_PC = "set GENESIS_PLAY_PC"
NEEDS_PC_FREE = "it runs only with --pc-free or GENESIS_PC_FREE=1"


class ClientKeyArgumentsTest(unittest.TestCase):
    def run_client(self, *args, pc_free=None):
        with tempfile.TemporaryDirectory() as home:
            env = {
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "HOME": home,
                "GENESIS_HOME": home,
            }
            if pc_free is not None:
                env["GENESIS_PC_FREE"] = pc_free
            done = subprocess.run(
                ["bash", CLIENT, "key", *args],
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
        return done.returncode, done.stderr

    def assert_usage(self, *args):
        status, stderr = self.run_client(*args, pc_free="1")
        self.assertEqual(status, 2, f"key {args}: {stderr}")
        self.assertNotIn(NEEDS_PC, stderr)

    def assert_accepted(self, *args, pc_free=None):
        status, stderr = self.run_client(*args, pc_free=pc_free)
        self.assertEqual(status, 1, f"key {args}: {stderr}")
        self.assertIn(NEEDS_PC, stderr)

    def test_a_scan_code_key_without_pc_free_is_refused_before_the_pc(self):
        for args in (("0x0F",), ("0x0F", "200"), ("0xE04B", "50")):
            status, stderr = self.run_client(*args)
            self.assertEqual(status, 1, f"key {args}: {stderr}")
            self.assertIn(NEEDS_PC_FREE, stderr)
            self.assertNotIn(NEEDS_PC, stderr)

    def test_a_pc_free_other_than_1_does_not_free_the_pc(self):
        status, stderr = self.run_client("0x0F", pc_free="yes")
        self.assertEqual(status, 1)
        self.assertIn(NEEDS_PC_FREE, stderr)

    def test_a_scan_code_that_is_not_a_make_code_is_refused(self):
        for scan in ("0x00", "0x80", "0xFF", "0xE000", "0xE080", "0x0", "0x123", "0xE1", "0xE1F0",
                     "15", "0F", "tab0x0F", "0x0G", "escape"):
            with self.subTest(scan=scan):
                self.assert_usage(scan, "--pc-free")

    def test_a_hold_outside_1_to_10000_ms_is_refused(self):
        for hold in ("0", "10001", "99999", "-5", "05", "1.5", "50ms", "100000"):
            with self.subTest(hold=hold):
                self.assert_usage("0x02", hold, "--pc-free")

    def test_extra_or_misplaced_arguments_are_refused(self):
        for args in (("0x02", "50", "60", "--pc-free"), ("0x02", "--pc-free", "50"),
                     ("0x02", "--pc-free", "--pc-free"), ("--pc-free",), ()):
            with self.subTest(args=args):
                self.assert_usage(*args)

    def test_the_named_keys_take_no_more_arguments(self):
        for args in (("tab", "--pc-free"), ("enter", "50")):
            with self.subTest(args=args):
                self.assert_usage(*args)

    def test_a_good_scan_code_and_hold_reach_the_pc(self):
        for args in (("0x0F", "--pc-free"), ("0x02", "1", "--pc-free"), ("0x11", "10000", "--pc-free"),
                     ("0xe04b", "300", "--pc-free"), ("0X7F", "--pc-free")):
            with self.subTest(args=args):
                self.assert_accepted(*args)

    def test_genesis_pc_free_1_stands_for_the_flag(self):
        self.assert_accepted("0x1E", "400", pc_free="1")

    def test_the_named_keys_still_reach_the_pc_with_no_flag(self):
        for name in ("tab", "enter"):
            with self.subTest(name=name):
                self.assert_accepted(name)


if __name__ == "__main__":
    unittest.main()
