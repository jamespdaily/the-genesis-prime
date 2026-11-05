"""Tests of client.sh key's argument checks, which run before the script reads env.sh or reaches the PC.

Each case runs client.sh with GENESIS_HOME set to an empty folder and no GENESIS_PLAY_PC, so a call
whose arguments pass goes on to pc.sh and stops there on the missing GENESIS_PLAY_PC: that message
proves the arguments were accepted, and its absence that they were refused before the PC was
reached. A usage refusal exits 2; a takeover without --pc-free exits 1 with its own message.
"""

import base64
import os
import re
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.join(HERE, "client.sh")
KEY_SCRIPT = os.path.join(HERE, "genesis-key.ps1")
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


# Stand-ins for ssh and scp on the PATH, so no test reaches a PC: scp succeeds, and ssh answers the
# run of the task with a finished key press and records the command it was given (the waiter it
# runs on the PC is passed encoded, which the test decodes).
STUB_SSH = """#!/bin/sh
case "$*" in
  *-EncodedCommand*) printf '%s\\n' "$*" >> "$STUB_LOG"; echo 'pressed=0xF held=1 foreground_is_client=True pid=1' ;;
esac
exit 0
"""
STUB_SCP = "#!/bin/sh\nexit 0\n"


class ClientKeyTaskLimitTest(unittest.TestCase):
    """The task's time limit holds the key's hold: run_task ends the task when the limit passes, and
    an ended task never releases the key (a PowerShell process that is stopped runs no finally)."""

    def waiter_limit_seconds(self, hold):
        with tempfile.TemporaryDirectory() as root:
            tools = os.path.join(root, "tools")
            os.mkdir(tools)
            for name, text in (("ssh", STUB_SSH), ("scp", STUB_SCP)):
                path = os.path.join(tools, name)
                with open(path, "w") as stub:
                    stub.write(text)
                os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
            home = os.path.join(root, "home")
            os.mkdir(home)
            with open(os.path.join(home, "client.pid"), "w") as state:
                state.write("123 133000000000000000\n")
            log = os.path.join(root, "ssh.log")
            env = {
                "PATH": f"{tools}:/usr/bin:/bin",
                "HOME": home,
                "GENESIS_HOME": home,
                "GENESIS_PLAY_PC": "someone@planted.invalid",
                "STUB_LOG": log,
            }
            done = subprocess.run(["bash", CLIENT, "key", "0x0F", str(hold), "--pc-free"], env=env,
                                  capture_output=True, text=True, timeout=30)
            self.assertEqual(done.returncode, 0, done.stderr)
            with open(log) as recorded:
                commands = recorded.read().splitlines()
        self.assertEqual(len(commands), 1, commands)
        encoded = re.search(r"-EncodedCommand (\S+)", commands[0]).group(1)
        waiter = base64.b64decode(encoded).decode("utf-16-le")
        return int(re.search(r"AddSeconds\((\d+)\)", waiter).group(1))

    def test_the_limit_is_30_seconds_for_the_script_plus_the_hold_rounded_up_to_whole_seconds(self):
        for hold, limit in ((50, 31), (1000, 31), (1001, 32), (10000, 40)):
            with self.subTest(hold=hold):
                self.assertEqual(self.waiter_limit_seconds(hold), limit)


def without_here_string(text):
    """The PowerShell text without its Add-Type here-string, whose C# braces are not blocks."""
    return re.sub(r'Add-Type @".*?\n"@', "", text, flags=re.DOTALL)


def enclosing_block(text, position):
    """The word before the innermost brace open at position (`try`, `finally`, `while`), or None;
    the braces of an `if (...)` are not blocks here."""
    depth = 0
    for index in range(position - 1, -1, -1):
        if text[index] == "}":
            depth += 1
        elif text[index] == "{":
            header = text[:index]
            if depth == 0 and not re.search(r"\bif\s*\([^{}]*\)\s*$", header):
                return re.search(r"(\w+)\s*(\([^{}]*\))?\s*$", header).group(1)
            if depth > 0:
                depth -= 1
    return None


class GenesisKeyReleaseTest(unittest.TestCase):
    """genesis-key.ps1 releases the key in a finally block that covers the hold, so a throw during
    the hold (or a stopped pipeline) cannot leave the key down. There is no PowerShell here, so the
    tests read the script's structure."""

    def setUp(self):
        with open(KEY_SCRIPT, encoding="utf-8") as script:
            self.text = without_here_string(script.read())

    def test_the_release_is_sent_once_and_from_a_finally_block(self):
        release = "[Key]::Send($scan, $flags -bor $releaseFlag)"
        self.assertEqual(self.text.count(release), 1)
        self.assertEqual(enclosing_block(self.text, self.text.index(release)), "finally")

    def test_the_press_and_the_whole_hold_are_in_the_try_that_the_release_finally_follows(self):
        press = self.text.index("[Key]::Send($scan, $flags)")
        hold_loop = self.text.index("while ($watch.ElapsedMilliseconds -lt $hold)")
        release = self.text.index("[Key]::Send($scan, $flags -bor $releaseFlag)")
        self.assertEqual(enclosing_block(self.text, press), "try")
        self.assertEqual(enclosing_block(self.text, hold_loop), "try")
        self.assertRegex(self.text[press:release], r"\}\s*finally\s*\{[^}]*$")

    def test_the_release_is_sent_only_when_the_press_went_through(self):
        self.assertRegex(self.text, r"\$pressed = \$true")
        self.assertRegex(self.text, r"if \(\$pressed\) \{[^}]*\$releaseFlag")


if __name__ == "__main__":
    unittest.main()
