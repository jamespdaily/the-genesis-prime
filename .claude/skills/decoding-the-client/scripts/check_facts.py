"""Check the client fact file, and that code citing the client has a record for each citation.

The fact file holds one TOML table per fact, keyed by a client code address
(`0x1403ec6a0`) or a Lua function (`MailSystemLib.AtMailbox`), with the fields
`statement`, `proof` and `grade` (`sure`, `fairly sure` or `guess`), and an
optional `name` on an address key. This refuses a parse error, a missing,
empty or unknown field, an unknown grade, an address key not written in
lowercase, two keys equal when lowercased, a name that is not an UpperCamelCase
word, a name on a Lua key, two records with one name, and any text that names
another project or a work record, comments included.

With `--cover`, it walks each path given and refuses each client address that
appears nowhere in the fact file's keys or values, and each Lua function that is
not a key. It skips build and tool folders and files that are not UTF-8 text.

Usage: python3 -I check_facts.py <facts.toml> [--cover <path>...]
It prints one line per finding and exits 1, or prints `ok: <n> records` and exits 0.
"""
import argparse
import os
import re
import sys
import tomllib

FIELDS = {"name", "statement", "proof", "grade"}
REQUIRED = ("statement", "proof", "grade")
GRADES = {"sure", "fairly sure", "guess"}
ADDRESS_KEY = re.compile(r"0x14[0-9a-fA-F]{7}")
ADDRESS = re.compile(r"0x14[0-9a-fA-F]{7}\b")
LUA_FUNCTION = re.compile(r"\b[A-Z][A-Za-z]*Lib\.[A-Za-z]+")
NAME = re.compile(r"[A-Z][A-Za-z0-9]*")
# The game has a chat channel called Nexus, so the word alone is allowed.
FORBIDDEN = re.compile(
    r"nexus ?forever|eldan|bezgelor|thistle|reference server|decision record|#[0-9]+",
    re.IGNORECASE,
)
SKIPPED_FOLDERS = {"build", "target", "tmp", "vendor", "worktrees", "__pycache__", ".git"}


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def forbidden_findings(facts_path, text):
    return [
        f"{facts_path}:{line_of(text, match.start())}: forbidden text {match.group()!r}"
        for match in FORBIDDEN.finditer(text)
    ]


def record_findings(facts_path, facts):
    findings = []
    lowercased = {}
    names = {}
    for key, record in facts.items():
        where = f"{facts_path}: [{key!r}]"
        if ADDRESS_KEY.fullmatch(key) and key != key.lower():
            findings.append(f"{where}: an address key must be lowercase, as {key.lower()!r}")
        if key.lower() in lowercased:
            findings.append(f"{where}: equals [{lowercased[key.lower()]!r}] when lowercased")
        else:
            lowercased[key.lower()] = key
        if not isinstance(record, dict):
            findings.append(f"{where}: must be a table")
            continue
        for field in sorted(set(record) - FIELDS):
            findings.append(f"{where}: unknown field {field!r}")
        for field in REQUIRED:
            value = record.get(field)
            if value is None:
                findings.append(f"{where}: missing {field!r}")
            elif not isinstance(value, str) or not value.strip():
                findings.append(f"{where}: {field!r} must be a non-empty string")
        grade = record.get("grade")
        if isinstance(grade, str) and grade.strip() and grade not in GRADES:
            findings.append(f"{where}: grade {grade!r} is not one of {sorted(GRADES)}")
        if "name" in record:
            name = record["name"]
            if not isinstance(name, str) or not NAME.fullmatch(name):
                findings.append(f"{where}: name {name!r} must match {NAME.pattern}")
            if not ADDRESS_KEY.fullmatch(key):
                findings.append(f"{where}: a name sits only on an address key")
            if isinstance(name, str):
                if name in names:
                    findings.append(f"{where}: name {name!r} is also on [{names[name]!r}]")
                else:
                    names[name] = key
    return findings


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield key
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def cover_files(path):
    if os.path.isfile(path):
        yield path
        return
    for folder, subfolders, files in os.walk(path):
        subfolders[:] = sorted(name for name in subfolders if name not in SKIPPED_FOLDERS)
        for name in sorted(files):
            yield os.path.join(folder, name)


def read_text(path):
    try:
        with open(path, "rb") as file:
            data = file.read()
        if b"\0" in data:
            return None
        return data.decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def cover_findings(facts_path, facts, cover_paths):
    mentioned = {
        address.lower()
        for text in strings_in(facts)
        for address in ADDRESS.findall(text)
    }
    findings = []
    facts_file = os.path.realpath(facts_path)
    for cover_path in cover_paths:
        for path in cover_files(cover_path):
            if os.path.realpath(path) == facts_file:
                continue
            text = read_text(path)
            if text is None:
                continue
            for number, line in enumerate(text.splitlines(), start=1):
                for address in ADDRESS.findall(line):
                    if address.lower() not in mentioned:
                        findings.append(f"{path}:{number}: address {address} has no mention in {facts_path}")
                for function in LUA_FUNCTION.findall(line):
                    if function not in facts:
                        findings.append(f"{path}:{number}: Lua function {function} is not a key in {facts_path}")
    return findings


def load(facts_path):
    """Return the file's text, its tables or None, and the findings from reading it."""
    try:
        with open(facts_path, "rb") as file:
            text = file.read().decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        return "", None, [f"{facts_path}: cannot read: {error}"]
    try:
        return text, tomllib.loads(text), []
    except tomllib.TOMLDecodeError as error:
        return text, None, [f"{facts_path}: parse error: {error}"]


def check(facts_path, cover_paths):
    """Return every finding for the fact file and the paths it must cover.

    A file that does not parse gets only its parse error and its forbidden
    text, since its keys are unknown.
    """
    text, facts, findings = load(facts_path)
    findings += forbidden_findings(facts_path, text)
    if facts is None:
        return findings
    findings += record_findings(facts_path, facts)
    findings += cover_findings(facts_path, facts, cover_paths)
    return findings


def record_count(facts_path):
    _, facts, _ = load(facts_path)
    return len(facts or {})


def main():
    parser = argparse.ArgumentParser(description="Check the client fact file.")
    parser.add_argument("facts")
    parser.add_argument("--cover", nargs="*", action="extend", default=[], metavar="path")
    arguments = parser.parse_args()
    findings = check(arguments.facts, arguments.cover)
    for finding in findings:
        print(finding)
    if findings:
        sys.exit(1)
    print(f"ok: {record_count(arguments.facts)} records")


if __name__ == "__main__":
    main()
