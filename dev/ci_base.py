"""The commit a CI run compares its code with, as the workflow's repeat job needs it.

    python3.13 -I dev/ci_base.py

Reads GITHUB_EVENT_NAME and the event's payload from GITHUB_EVENT_PATH and prints one line:

  pull_request  origin/<the base branch>          (`pull_request.base.ref`)
  merge_group   the merge group's base sha        (`merge_group.base_sha`, "the SHA of the
                                                   merge group's parent commit")

`github.base_ref` is empty on a merge group ("only available when the event that triggers a
workflow run is either pull_request or pull_request_target"), so a workflow step reads the base
from here. Any other event has no base: the script says so and exits 2, as it does for a
payload without the field. A push is skipped by its commit's own tested tree, not by a base
(dev/play_service/tested_tree.sh).
"""

import json
import os
import sys


def base_of(event_name: str, payload: dict) -> str:
    """The base for an event's payload; KeyError when the payload lacks the field."""
    if event_name == "pull_request":
        return "origin/" + payload["pull_request"]["base"]["ref"]
    if event_name == "merge_group":
        return payload["merge_group"]["base_sha"]
    raise ValueError(f"a {event_name} event has no base to compare with")


def main() -> int:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    path = os.environ.get("GITHUB_EVENT_PATH", "")
    try:
        with open(path) as payload:
            print(base_of(event_name, json.load(payload)))
    except (OSError, json.JSONDecodeError, KeyError, ValueError) as problem:
        print(f"ci_base: {event_name or 'no event'}: {type(problem).__name__}: {problem}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
