"""The fact file's checker: every record well formed, every cited client address recorded.

A record is one TOML table in references/client-facts.toml, keyed by a client
address (lower-case, 0x-prefixed), an opcode, a table column, an enum or a Lua
function. Its fields:

  statement  what the client does, in the game's or the message's terms
  proof      how it was read: the instructions, the table rows, the test that checks it
  grade      "sure", "fairly sure" or "guess"
  gap        what is not yet read, and what would settle it; for "fairly sure" and "guess" only
  name       the function's name, when the key is a function's entry

An address a test plants on purpose is assigned to a name starting with
PLANTED_, as seed.PLANTED_UNMAPPED is, and is not a fact.

Usage: python3 -I check_facts.py  (exits non-zero and prints each problem)
"""

import os
import re
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
FACT_FILE = SCRIPTS.parent / "references" / "client-facts.toml"
REPOSITORY = SCRIPTS.parents[3]
GRADES = ("sure", "fairly sure", "guess")
FIELDS = ("statement", "proof", "grade", "gap", "name")

_ADDRESS = r"0x14[0-9a-fA-F]{7}(?![0-9a-fA-F])"
_ADDRESS_RE = re.compile(_ADDRESS)
_HEADER_RE = re.compile(r"^\s*\[(?!\[).*\]\s*(#.*)?$")
_PLANTED_RE = re.compile(r"^\s*PLANTED_\w*\s*(?::[^=]+)?=")
_INSTRUCTION_RE = re.compile(_ADDRESS + r"\s+[a-z][a-z0-9]*")
_TEST_FILE_RE = re.compile(r"\btest_\w+\.py\b")

_REGISTERS = (
    "rax rbx rcx rdx rsi rdi rbp rsp eax ebx ecx edx esi edi ebp esp ax bx cx dx si di bp sp "
    "al bl cl dl ah bh ch dh sil dil bpl spl rip"
).split()
_REGISTERS += ["r%d%s" % (n, w) for n in range(8, 16) for w in ("", "d", "w", "b")]
_REGISTERS += ["xmm%d" % n for n in range(16)]
# What a statement may not hold: the client's machine, not the game's terms.
_STATEMENT_RULES = (
    ("a register name", re.compile(r"\b(?:%s)\b" % "|".join(_REGISTERS))),
    ("a struct offset", re.compile(r"\+0x")),
    ("the word vtable", re.compile(r"vtable", re.I)),
)
# What no field may hold: another server, or a pointer into the project's tracker.
# `dll!#115` is an import by ordinal, not an issue.
_EVERY_FIELD_RULES = (
    ("another server's name", re.compile(r"nexus\s?forever", re.I)),
    ("an issue or pull request number", re.compile(r"(?<!!)#\d+|\bissue \d+|\bpull request \d+|\bPR \d+", re.I)),
    ("the words decision record", re.compile(r"decision record", re.I)),
)


@dataclass(frozen=True)
class Record:
    key: str
    statement: str
    proof: str
    grade: str
    gap: str | None
    name: str | None


@dataclass(frozen=True)
class Problem:
    where: str  # a record's key, or a file and line that cites an address
    what: str


def load(path: Path) -> dict[str, Record]:
    """Reads the fact file; a duplicate key or a malformed table raises ValueError naming it."""
    text = Path(path).read_text()
    seen = set()
    for line in text.splitlines():
        if _HEADER_RE.match(line):
            try:
                (key,) = tomllib.loads(line)
            except (tomllib.TOMLDecodeError, ValueError):
                continue  # tomllib below names the malformed header
            if key in seen:
                raise ValueError("%s: this key is in the fact file twice" % key)
            seen.add(key)
    try:
        tables = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise ValueError("%s: %s" % (path, error)) from error
    records = {}
    for key, table in tables.items():
        if not isinstance(table, dict):
            raise ValueError("%s: a record is a table, not a value" % key)
        for field in table:
            if field not in FIELDS:
                raise ValueError("%s: %s is not a field of a record" % (key, field))
        for field in FIELDS:
            if field in table and not isinstance(table[field], str):
                raise ValueError("%s: %s must be a string" % (key, field))
        for field in ("statement", "proof", "grade"):
            if field not in table:
                raise ValueError("%s: %s is missing" % (key, field))
        records[key] = Record(
            key, table["statement"], table["proof"], table["grade"], table.get("gap"), table.get("name")
        )
    return records


def record_problems(records: dict[str, Record], function_entries: set[str] | None) -> list[Problem]:
    """Each record's fields, grade, gap, name and wording, against the rules above.
    function_entries holds the keys known to be a function's entry; None when
    they are unknown, and then no name rule is checked."""
    problems = []
    for key, r in records.items():
        for field in ("statement", "proof"):
            if not getattr(r, field).strip():
                problems.append(Problem(key, "%s is empty" % field))
        if r.grade not in GRADES:
            problems.append(Problem(key, "grade %r is not one of %s" % (r.grade, ", ".join(GRADES))))
        elif r.grade == "sure":
            if r.gap:
                problems.append(Problem(key, "gap is for fairly sure and guess only, and this grade is sure"))
            if not (_INSTRUCTION_RE.search(r.proof) or _TEST_FILE_RE.search(r.proof)):
                problems.append(Problem(key, "proof of a sure record names no instruction (address, mnemonic) and no test file"))
        elif not r.gap:
            problems.append(Problem(key, "gap is missing, and a %s record needs one" % r.grade))
        for what, rule in _STATEMENT_RULES:
            if rule.search(r.statement):
                problems.append(Problem(key, "statement holds %s" % what))
        for field in ("statement", "proof", "gap", "name"):
            value = getattr(r, field)
            for what, rule in _EVERY_FIELD_RULES:
                if value and rule.search(value):
                    problems.append(Problem(key, "%s holds %s" % (field, what)))
        if function_entries is not None:
            if key in function_entries and not r.name:
                problems.append(Problem(key, "name is missing: the key is a function's entry"))
            elif r.name and key not in function_entries:
                problems.append(Problem(key, "name is set, and the key is not a function's entry"))
    return problems


def cited_addresses(repository: Path) -> dict[str, list[str]]:
    """Every 0x14xxxxxxx address in the repository's tracked files, outside the
    fact file and lines that assign a PLANTED_ name: address -> ["file:line", ...]."""
    try:
        skipped = FACT_FILE.relative_to(REPOSITORY).as_posix()
    except ValueError:
        skipped = None
    listed = subprocess.run(
        ["git", "ls-files", "-z"], cwd=repository, check=True, capture_output=True, text=True
    ).stdout
    cited: dict[str, list[str]] = {}
    for relative in sorted(filter(None, listed.split("\0"))):
        path = Path(repository) / relative
        if relative == skipped or not path.is_file():
            continue
        data = path.read_bytes()
        if b"\0" in data:
            continue
        for number, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
            if _PLANTED_RE.match(line):
                continue
            for found in _ADDRESS_RE.findall(line):
                sites = cited.setdefault(found.lower(), [])
                if "%s:%d" % (relative, number) not in sites:
                    sites.append("%s:%d" % (relative, number))
    return cited


def coverage_problems(records: dict[str, Record], cited: dict[str, list[str]]) -> list[Problem]:
    """One problem per cited address that no record holds as its key or in its statement or proof."""
    held = {key.lower() for key in records}
    for r in records.values():
        for text in (r.statement, r.proof):
            held.update(found.lower() for found in _ADDRESS_RE.findall(text))
    return [
        Problem(sites[0], "%s is cited in %d place(s) and no record holds it" % (address, len(sites)))
        for address, sites in sorted(cited.items())
        if address not in held
    ]


def function_entries(pe, records: dict[str, Record]) -> set[str]:
    """The keys known to be a function's entry: every .pdata start and pointer-only
    function, and every named key in a code section outside all .pdata functions.
    A leaf function has no .pdata entry, so its name is taken at its word; a name
    inside a .pdata function or outside code is still refused."""
    entries = {"0x%x" % a for a in pe.function_starts()} | {"0x%x" % a for a in pe.pointer_only_functions()}
    for key, r in records.items():
        if r.name and _ADDRESS_RE.fullmatch(key):
            address = int(key, 16)
            section = pe.section_of(address)
            if section is not None and section.executable and pe.root_of(address) is None:
                entries.add(key)
    return entries


def main(argv: list[str]) -> int:
    """Checks the fact file against the repository. The name rule needs the
    client at $WILDSTAR_CLIENT_EXE to know the function entries; without it,
    main says on stderr that the rule was not checked. Each problem goes to stdout."""
    try:
        records = load(FACT_FILE)
    except ValueError as error:
        print("%s: %s" % (FACT_FILE.name, error))
        return 1
    entries = None
    exe = os.environ.get("WILDSTAR_CLIENT_EXE")
    if exe and Path(exe).is_file():
        sys.path.insert(0, str(SCRIPTS))
        from client_pe import ClientPE

        entries = function_entries(ClientPE(Path(exe)), records)
    else:
        print("the name rule was not checked: WILDSTAR_CLIENT_EXE names no file", file=sys.stderr)
    problems = record_problems(records, entries) + coverage_problems(records, cited_addresses(REPOSITORY))
    for problem in problems:
        print("%s: %s" % (problem.where, problem.what))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
