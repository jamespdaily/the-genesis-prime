"""The gate of CI's pull request run: the job `check`, which branch protection requires.

    NEEDS=<toJSON(needs)> python3 -I dev/ci_gate.py TREE

NEEDS is the `needs` context of the gate job (`{"job": {"result": "success", ...}}`) and TREE
the git tree the run tested. Every needed job but `tested` must have ended `success`: a
failed, cancelled or skipped job fails the gate, and so does a list with no job in it, so a
matrix that lost every leg cannot pass. `tested` is the push job that decides whether main's
commit was already tested; it is skipped on a pull request, and when it runs it only tells
the part jobs whether to run, so its own result is not read.

A light change (the files `./check scope` names) still ends every leg `success`: a leg that
has nothing to run ends its steps as skipped inside the job, so a skipped job is never an
accepted outcome here.

On success the gate prints the notice dev/play_service/tested_tree.sh reads, `tested tree
TREE`, so a push to main of the same tree skips a second run. Exit status: 0 passed, 1 not
passed (the lines on stdout name each job that did not succeed), 2 NEEDS is not the JSON of
an object or TREE is missing.
"""

import json
import os
import sys

IGNORED = "tested"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: NEEDS=JSON python3 -I dev/ci_gate.py TREE", file=sys.stderr)
        return 2
    try:
        needs = json.loads(os.environ.get("NEEDS", ""))
    except json.JSONDecodeError as error:
        print(f"ci_gate: NEEDS is not JSON ({error})", file=sys.stderr)
        return 2
    if not isinstance(needs, dict):
        print("ci_gate: NEEDS is not a JSON object", file=sys.stderr)
        return 2
    results = {name: job.get("result") if isinstance(job, dict) else None for name, job in needs.items() if name != IGNORED}
    if not results:
        print("ci_gate: no job to wait for besides `tested`, so no part ran")
        return 1
    failed = [f"{name}: {result}" for name, result in results.items() if result != "success"]
    if failed:
        for line in failed:
            print(f"ci_gate: {line}")
        return 1
    print(f"::notice title=tested tree::tested tree {sys.argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
