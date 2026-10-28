"""Checks what a session brought back against the character the database saved.

    python3 -I session_verdict.py <session folder>

Reads <folder>/report.json (report.sh collect, from the client's state report) and
<folder>/failures.txt (client-log.sh collect), and the saved row of the character the report names:
the play account's character whose name equals the report's strName, read by psql from the database
the PG* variables name. GENESIS_PLAY_ACCOUNT names the account.

Prints one line per check, "ok" or "FAIL" and what was compared, and exits 1 when any check fails.
A value the report leaves out fails its check; a table with no entry is empty, as report_xml.py
writes it.
"""

import json
import math
import os
import re
import subprocess
import sys

# How far the client's position may be from the saved place, in game units.
POSITION_TOLERANCE = 1.0

ROW_QUERY = """select level, path, position_x, position_y, position_z
from character join account using (account_id)
where account.login_name = :'account' and character.name = :'name';"""


def is_number(value):
    """Whether the value is a JSON number (a boolean is not)."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def read_row(account, name):
    """The saved row as (level, path, x, y, z), or the text of why there is none."""
    try:
        done = subprocess.run(
            ["psql", "-X", "-q", "-A", "-t", "-F", " ", "-v", "ON_ERROR_STOP=1",
             "-v", f"account={account}", "-v", f"name={name}", "-f", "-"],
            input=ROW_QUERY, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"psql did not run: {error}"
    if done.returncode != 0:
        return f"psql failed: {done.stderr.strip()}"
    rows = done.stdout.strip().splitlines()
    if len(rows) != 1:
        return f"{len(rows)} rows for account {account!r}, character {name!r}"
    level, path, x, y, z = rows[0].split(" ")
    return int(level), int(path), float(x), float(y), float(z)


def failure_count(folder):
    """The count on the last line of failures.txt, or the text of why there is none."""
    try:
        with open(os.path.join(folder, "failures.txt"), encoding="utf-8") as file:
            lines = file.read().strip().splitlines()
    except OSError as error:
        return f"failures.txt: {error}"
    found = re.fullmatch(r"(\d+) failure line\(s\)", lines[-1]) if lines else None
    if found is None:
        return "failures.txt does not end with a failure count"
    return int(found.group(1))


def check_report(report, row):
    """Every check of the report against the row (or the text saying why there is none)."""
    checks = []

    def add(label, ok, detail):
        checks.append((label, ok, detail))

    def expect(label, key, wanted):
        got = report.get(key)
        add(label, got is wanted, f"{key} = {got!r}")

    expect("the report is finished", "bReported", True)
    expect("the player is alive", "bDead", False)
    health = report.get("nHealth")
    add("the player has health", is_number(health) and health > 0, f"nHealth = {health!r}")
    expect("the player's unit is controlled", "bControlled", True)
    expect("the player's model is loaded", "bModelLoaded", True)

    if isinstance(row, str):
        for label in ("the level is the saved level", "the path is the saved path",
                      "the position is the saved place"):
            add(label, False, row)
    else:
        level, path, x, y, z = row
        add("the level is the saved level", report.get("nLevel") == level,
            f"nLevel = {report.get('nLevel')!r}, saved {level}")
        add("the path is the saved path", report.get("ePath") == path,
            f"ePath = {report.get('ePath')!r}, saved {path}")
        position = report.get("tPos")
        axes = [position.get(axis) for axis in ("x", "y", "z")] if isinstance(position, dict) else []
        if len(axes) == 3 and all(is_number(axis) for axis in axes):
            distance = math.dist(axes, (x, y, z))
            add("the position is the saved place", distance <= POSITION_TOLERANCE,
                f"{distance:.3f} units from the saved place (at most {POSITION_TOLERANCE})")
        else:
            add("the position is the saved place", False, f"tPos = {position!r}")

    for label, key in (("no addon raised an error", "tAddonErrors"),
                       ("no Lua error event was raised", "tLuaErrorEvents")):
        errors = report.get(key)
        if not isinstance(errors, (dict, list)):
            add(label, False, f"{key} = {errors!r}")
        elif errors:
            names = sorted(errors) if isinstance(errors, dict) else [event.get("strAddon") for event in errors]
            add(label, False, f"{key} holds {len(errors)} entries, from {names}")
        else:
            add(label, True, f"{key} is empty")
    return checks


def run(folder):
    """The checks of the session in the folder, as (label, ok, detail) lines."""
    try:
        with open(os.path.join(folder, "report.json"), encoding="utf-8") as file:
            report = json.load(file)
    except (OSError, ValueError) as error:
        return [("the report is read", False, f"report.json: {error}")]
    if not isinstance(report, dict):
        return [("the report is read", False, "report.json is not an object")]
    if not isinstance(report.get("strName"), str):
        return [("the report names a character", False, f"strName = {report.get('strName')!r}")]

    account = os.environ.get("GENESIS_PLAY_ACCOUNT")
    if not account:
        return [("the account is known", False, "GENESIS_PLAY_ACCOUNT is not set")]
    checks = [("the report names a character", True, f"strName = {report['strName']!r}")]
    checks += check_report(report, read_row(account, report["strName"]))

    failures = failure_count(folder)
    if isinstance(failures, int):
        checks.append(("the client logged no failure", failures == 0, f"{failures} failure line(s)"))
    else:
        checks.append(("the client logged no failure", False, failures))
    return checks


def main(arguments):
    if len(arguments) != 2:
        print("usage: python3 -I session_verdict.py <session folder>", file=sys.stderr)
        return 2
    checks = run(arguments[1])
    for label, ok, detail in checks:
        print(f"{'ok  ' if ok else 'FAIL'} {label}: {detail}")
    return 0 if all(ok for _, ok, _ in checks) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
