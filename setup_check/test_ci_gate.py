"""dev/ci_gate.py: the job `check` of CI passes only when every part job succeeded.

The gate reads the `needs` context of its job as JSON from the variable NEEDS and the tree
the run tested as its one argument. Exit status: 0 every needed job but `tested` succeeded
(and the notice of the tree is printed), 1 one did not or there is none, 2 NEEDS is not the
JSON of an object. The tests run it as a script on hand-made JSON of GitHub's shape
(`{"job": {"result": ..., "outputs": {}}}`).

Run: python3.13 -I -m unittest discover -s setup_check -p 'test_ci_gate.py'
"""

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

GATE = Path(__file__).resolve().parent.parent / "dev" / "ci_gate.py"
TREE = "76759fc1d0b8b0c2a1e1a4d5a3d6e7f8091a2b3c"
NOTICE = "::notice title=tested tree::tested tree " + TREE


def gate(needs: object) -> subprocess.CompletedProcess:
    text = needs if isinstance(needs, str) else json.dumps(needs)
    environment = {"PATH": os.environ["PATH"], "NEEDS": text}
    return subprocess.run([sys.executable, "-I", str(GATE), TREE], capture_output=True, text=True, env=environment)


def jobs(**results: str) -> dict:
    return {name: {"result": result, "outputs": {}} for name, result in results.items()}


class CiGateTest(unittest.TestCase):
    def test_the_gate_passes_only_when_every_needed_job_succeeded(self):
        # (needs, exit status, a line the output holds, why)
        rows = [
            (jobs(part="success"), 0, "", "every job but `tested` succeeded"),
            (jobs(tested="success", part="success"), 0, "", "`tested` succeeded and is ignored"),
            (jobs(tested="skipped", part="success"), 0, "", "`tested` is skipped on a pull request and is ignored"),
            (jobs(tested="failure", part="success"), 0, "", "`tested` failing leaves the part jobs to run, so it is ignored"),
            (jobs(part="failure"), 1, "part: failure", "a failed leg ends the matrix job `part` as failure, named with its result"),
            (jobs(part="cancelled"), 1, "part: cancelled", "a cancelled job is not a pass"),
            (jobs(part="skipped"), 1, "part: skipped", "a skipped part job is a part not run, not a pass"),
            (jobs(tested="skipped", part="failure"), 1, "part: failure", "`tested` skipped does not hide a failed part"),
            (jobs(tested="success"), 1, "no job", "only `tested` present: no part job was waited for"),
            ({}, 1, "no job", "an empty list: nothing was waited for"),
            ("this is not json", 2, "not JSON", "text that is not JSON is the gate's own error"),
            ("[1, 2]", 2, "not a JSON object", "a list is not the needs context"),
        ]
        for needs, status, line, why in rows:
            with self.subTest(why):
                done = gate(needs)
                self.assertEqual(done.returncode, status, done.stdout + done.stderr)
                self.assertIn(line, done.stdout + done.stderr)

    def test_the_gate_writes_the_tested_tree_notice_only_after_every_job_succeeded(self):
        passed = gate(jobs(part="success"))
        self.assertEqual(passed.returncode, 0, passed.stderr)
        self.assertIn(NOTICE, passed.stdout.splitlines())
        for needs in (jobs(part="failure"), jobs(part="cancelled"), jobs(part="skipped"), {}, "not json"):
            with self.subTest(needs=needs):
                failed = gate(needs)
                self.assertNotIn("tested tree", failed.stdout + failed.stderr)


if __name__ == "__main__":
    unittest.main()
