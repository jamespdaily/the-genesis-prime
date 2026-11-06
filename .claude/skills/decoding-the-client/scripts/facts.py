"""Looks up records in the fact file (references/client-facts.toml), printing only
what is asked so a lookup pulls in no neighbouring records. The fact checker's
own loader (check_facts.load) reads the file.

Usage:
  python3.13 -I facts.py get <key>...          print each record whole: its key, then
                                               statement, proof, grade, gap, name (only the
                                               fields present), a blank line between records;
                                               an unknown key prints 'no record <key>' to
                                               stderr and the exit code is 1
  python3.13 -I facts.py get --cites <key>...  also print every record whose key an asked
                                               record's statement or gap names (one level,
                                               no repeats)
  python3.13 -I facts.py find <word>...        list each key whose key or statement holds
                                               every word (case-insensitive), one per line
                                               with the statement's first 100 characters
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_facts  # noqa: E402

FACT_FILE = check_facts.FACT_FILE

USAGE = "usage: facts.py get [--cites] <key>...\n       facts.py find <word>..."

_CITED_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.]*[A-Za-z0-9_]")


def render(record: check_facts.Record) -> str:
    """The record whole: its key, then each field it holds, one line per field."""
    lines = [record.key]
    for field in check_facts.FIELDS:
        value = getattr(record, field)
        if value is not None:
            lines.append("%s: %s" % (field, value))
    return "\n".join(lines)


def cited(records: dict[str, check_facts.Record], record: check_facts.Record) -> list[str]:
    """Every record key the record names in its statement or gap, as a word or in
    backticks, in order, no repeats: records cite keys as plain words."""
    keys = []
    for text in (record.statement, record.gap or ""):
        for span in _CITED_RE.findall(text):
            if span in records and span not in keys:
                keys.append(span)
    return keys


def get(records: dict[str, check_facts.Record], keys: list[str], cites: bool) -> int:
    """Prints each found record, then the cited ones when cites is set. Returns 1 when
    any asked key is unknown, after a 'no record <key>' per unknown key on stderr."""
    blocks = []
    printed = set()
    asked = []
    for key in keys:
        record = records.get(key)
        if record is not None and key not in printed:
            asked.append(record)
            blocks.append(render(record))
            printed.add(key)
    if cites:
        for record in asked:
            for key in cited(records, record):
                if key not in printed:
                    blocks.append(render(records[key]))
                    printed.add(key)
    if blocks:
        print("\n\n".join(blocks))
    unknown = [key for key in keys if key not in records]
    for key in unknown:
        print("no record %s" % key, file=sys.stderr)
    return 1 if unknown else 0


def find(records: dict[str, check_facts.Record], words: list[str]) -> int:
    """Prints each key whose key or statement holds every word, case-insensitively,
    one per line with the statement's first 100 characters."""
    lowered = [word.lower() for word in words]
    for key, record in records.items():
        low_key = key.lower()
        low_statement = record.statement.lower()
        if all(word in low_key or word in low_statement for word in lowered):
            print("%s: %.100s" % (key, record.statement))
    return 0


def load() -> dict[str, check_facts.Record] | None:
    """The fact checker's loader on FACT_FILE; a malformed file is named on stderr, not raised."""
    try:
        return check_facts.load(FACT_FILE)
    except ValueError as error:
        print("%s" % error, file=sys.stderr)
        return None


def main(argv: list[str]) -> int:
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    command, args = argv[0], argv[1:]
    if command == "get":
        keys = [a for a in args if a != "--cites"]
        if not keys:
            print(USAGE, file=sys.stderr)
            return 2
        records = load()
        return 1 if records is None else get(records, keys, cites="--cites" in args)
    if command == "find":
        if not args:
            print(USAGE, file=sys.stderr)
            return 2
        records = load()
        return 1 if records is None else find(records, args)
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
