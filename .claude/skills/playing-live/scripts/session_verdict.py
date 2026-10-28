"""Checks what a session brought back against the character the database saved.

    python3 -I session_verdict.py <session folder>

Reads <folder>/report.json (report.sh collect, from the client's state report), <folder>/failures.txt
and <folder>/Errors (client-log.sh collect), <folder>/client-end.txt (what client.sh stop found, as
session.sh writes it), and the saved row of the character the report names: the play account's
character whose name equals the report's strName, read by psql from the database the PG* variables
name. GENESIS_PLAY_ACCOUNT names the account.

Prints one line per check, "ok" or "FAIL" and what was compared, and exits 1 when any check fails.
An input that cannot be read fails the check that needs it and no other. A value the report leaves
out fails its check; a table with no entry is empty, as report_xml.py writes it.
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


class InputError(Exception):
    """An input of the checks could not be read; the text says why."""


def is_number(value):
    """Whether the value is a JSON number (a boolean is not)."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def read_report(folder):
    """The report in report.json: an object that names its character."""
    try:
        with open(os.path.join(folder, "report.json"), encoding="utf-8") as file:
            report = json.load(file)
    except (OSError, ValueError) as error:
        raise InputError(f"report.json: {error}") from error
    if not isinstance(report, dict):
        raise InputError("report.json is not an object")
    if not isinstance(report.get("strName"), str):
        raise InputError(f"strName = {report.get('strName')!r}")
    return report


def read_row(account, name):
    """The saved row as (level, path, x, y, z)."""
    try:
        done = subprocess.run(
            ["psql", "-X", "-q", "-A", "-t", "-F", " ", "-v", "ON_ERROR_STOP=1",
             "-v", f"account={account}", "-v", f"name={name}", "-f", "-"],
            input=ROW_QUERY, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise InputError(f"psql did not run: {error}") from error
    if done.returncode != 0:
        raise InputError(f"psql failed: {done.stderr.strip()}")
    rows = done.stdout.strip().splitlines()
    if len(rows) != 1:
        raise InputError(f"{len(rows)} rows for account {account!r}, character {name!r}")
    level, path, x, y, z = rows[0].split(" ")
    return int(level), int(path), float(x), float(y), float(z)


def failure_count(folder):
    """The count on the last line of failures.txt, written as client-log.sh's failures prints it:
    "<n> failure line(s)"."""
    try:
        with open(os.path.join(folder, "failures.txt"), encoding="utf-8") as file:
            lines = file.read().strip().splitlines()
    except OSError as error:
        raise InputError(f"failures.txt: {error}") from error
    found = re.fullmatch(r"(\d+) failure line\(s\)", lines[-1]) if lines else None
    if found is None:
        raise InputError("failures.txt does not end with a failure count")
    return int(found.group(1))


def error_reports(folder):
    """The names of the client's error reports client-log.sh collect copied into the folder."""
    try:
        return sorted(os.listdir(os.path.join(folder, "Errors")))
    except FileNotFoundError:
        return []
    except OSError as error:
        raise InputError(f"Errors: {error}") from error


def client_end(folder):
    """What client.sh stop found at the end of the session: "closed" or "gone"."""
    try:
        with open(os.path.join(folder, "client-end.txt"), encoding="utf-8") as file:
            found = file.read().strip()
    except OSError as error:
        raise InputError(f"client-end.txt: {error}") from error
    if found not in ("closed", "gone"):
        raise InputError(f"client-end.txt holds {found!r}, not closed or gone")
    return found


def check_report(report, row):
    """Every check of the report against the saved row (level, path, x, y, z)."""
    checks = []

    def expect(label, key, wanted):
        got = report.get(key)
        checks.append((label, got is wanted, f"{key} = {got!r}"))

    expect("the report is finished", "bReported", True)
    expect("the player is alive", "bDead", False)
    health = report.get("nHealth")
    checks.append(("the player has health", is_number(health) and health > 0, f"nHealth = {health!r}"))
    expect("the player's unit is controlled", "bControlled", True)
    expect("the player's model is loaded", "bModelLoaded", True)

    level, path, x, y, z = row
    checks.append(("the level is the saved level", report.get("nLevel") == level,
                   f"nLevel = {report.get('nLevel')!r}, saved {level}"))
    checks.append(("the path is the saved path", report.get("ePath") == path,
                   f"ePath = {report.get('ePath')!r}, saved {path}"))
    position = report.get("tPos")
    axes = [position.get(axis) for axis in ("x", "y", "z")] if isinstance(position, dict) else []
    if len(axes) == 3 and all(is_number(axis) for axis in axes):
        distance = math.dist(axes, (x, y, z))
        checks.append(("the position is the saved place", distance <= POSITION_TOLERANCE,
                       f"{distance:.3f} units from the saved place (at most {POSITION_TOLERANCE})"))
    else:
        checks.append(("the position is the saved place", False, f"tPos = {position!r}"))

    for label, key in (("no addon raised an error", "tAddonErrors"),
                       ("no Lua error event was raised", "tLuaErrorEvents")):
        errors = report.get(key)
        if not isinstance(errors, (dict, list)):
            checks.append((label, False, f"{key} = {errors!r}"))
        elif errors:
            names = sorted(errors) if isinstance(errors, dict) else [event.get("strAddon") for event in errors]
            checks.append((label, False, f"{key} holds {len(errors)} entries, from {names}"))
        else:
            checks.append((label, True, f"{key} is empty"))
    return checks


def judged(label, read, judge):
    """The checks `judge` makes of what `read` returns; when `read` raises InputError, one failed
    check named `label` with the reason."""
    try:
        value = read()
    except InputError as error:
        return [(label, False, str(error))]
    return judge(value)


def single(label, read, judge):
    """One check named `label`: `judge` of what `read` returns gives its (ok, detail); when `read`
    raises InputError, it fails with the reason."""
    try:
        value = read()
    except InputError as error:
        return (label, False, str(error))
    ok, detail = judge(value)
    return (label, ok, detail)


def report_checks(report, account):
    """The report's own checks, and those against the saved row of the character it names."""
    named = ("the report names a character", True, f"strName = {report['strName']!r}")
    return [named] + judged("the saved character is read",
                            lambda: read_row(account, report["strName"]),
                            lambda row: check_report(report, row))


def read_account():
    """The play account's login name, from GENESIS_PLAY_ACCOUNT."""
    account = os.environ.get("GENESIS_PLAY_ACCOUNT")
    if not account:
        raise InputError("GENESIS_PLAY_ACCOUNT is not set")
    return account


def run(folder):
    """The checks of the session in the folder, as (label, ok, detail) lines."""
    checks = judged("the report is read", lambda: read_report(folder),
                    lambda report: judged("the account is known", read_account,
                                          lambda account: report_checks(report, account)))
    checks += [single("the client logged no failure", lambda: failure_count(folder),
                      lambda count: (count == 0, f"{count} failure line(s)")),
               single("the client wrote no error report", lambda: error_reports(folder),
                      lambda names: (not names, f"{len(names)} in Errors: {names}" if names
                                     else "none in Errors")),
               single("the client ran to the end of the session", lambda: client_end(folder),
                      lambda found: (found == "closed", "client.sh stop closed it" if found == "closed"
                                     else "client.sh stop found it no longer running"))]
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
