"""What the client does with a function or a message, in one call.

    python3.13 -I client_trace.py <address | name | opcode> [--depth N] [--max-chars N] [--dispatcher <address | name>]...

Run with ~/.genesis-prime/env.sh read (WILDSTAR_CLIENT_EXE, and llvm-objdump as client_refs.py finds it) and
the saved C current (decompiled.py check). It reads only: the saved C (decompiled.py), the reference index
(client_refs.py, built per run in a few seconds) and the fact file; it never starts Ghidra.

The input is an address (0x hex from 0x140000000 up, a function start or a called leaf), a function name as the
saved C carries it, or an opcode (0x hex up to 0xFFFF, or decimal). --depth is 1 to 4, default 1: how many
levels of callers and callees are listed, and, from 2, whether the bodies of the first six callees (by call
site) are included. --max-chars is the size bound, default 24000: everything the report prints fits in it.

A function prints, in this order:
    facts       the fact file's record keyed to it (statement, grade, gap), the records keyed to the callers and
                callees listed, and the other records (an opcode, a table column, a Lua function) that cite it
    called by   its direct callers with each call site, and every reference that is not a call (a pointer in a
                table, a `lea`, a call from code outside .pdata), then callers' callers to --depth
    calls       its direct callees (a call or a tail jmp) with each call site, the imports, and the sites that
                go through a pointer in memory; then their callees to --depth
    strings     the string literals of its saved C
    globals     each global data address its C names that some other function also refers to (a flag or a
                setting it shares), fewest users first, with those functions; the index finds them, so no
                search of the saved C is needed
    body        its saved C, cut to what is left of the bound, with the number of lines cut
Not listed, because the index does not hold them: a call through a register or a virtual call
(`(**(code **)(*p + 0x28))(...)`): they are in the body. The client's C names no table columns; a column read
is known only through a fact-file record keyed Table.column that cites the function.

An opcode prints, before the functions below:
    registered  each saved-C registration line (id, record size, sizer, writer, reader): a writer means the
                client sends the message, a reader that it receives it. The registration names no handler.
    dispatched  for each named dispatcher (a saved name of the form Handle...Message(s), and each --dispatcher)
                whose jump table holds the opcode: the case block's address and the functions it calls.
                A dispatcher that compares ids one by one instead of by table is not found: its record in the
                fact file is the lead.
    used by     each saved-C line that passes the opcode as a call argument: a Send...( call is a sender; any
                other use may be another number that is equal (a table id).
    then the trace of the reader, the writer, each function the case block calls and each sender, with the
    bound shared between their bodies.

The saved C's file layout, its hash and its freshness are decompiled.py's contract; the walks of call_paths.py
(a chain from one function to named targets) are its own question and are not repeated here.
Exit 0 when something is printed; 1 when the input is refused or names nothing.
"""

import argparse
import difflib
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import call_paths  # noqa: E402
import check_facts  # noqa: E402
import check_support  # noqa: E402
import decompiled  # noqa: E402
import jump_tables  # noqa: E402
from client_refs import RefIndex  # noqa: E402

DEFAULT_MAX_CHARS = 24000
MAX_DEPTH = 4
MIN_BODY_CHARS = 600
IMAGE_BASE = 0x140000000
OPCODE_LIMIT = 0xFFFF
CASE_BLOCK_INSTRUCTIONS = 80
MAX_CALLERS = 20
MAX_CALLEES = 40
MAX_TREE_LINES = 40
MAX_STRINGS = 30
MAX_FACTS = 12
MAX_CASE_CALLEES = 4
MAX_SENDERS = 4
MAX_CALLEE_BODIES = 6
MAX_OTHER_USES = 6
MAX_DATA_REFERENCES = 8
MAX_GLOBALS = 12
MAX_GLOBAL_USERS = 6
FIRST_RECORD_CHARS = 1500
OTHER_RECORD_CHARS = 240
COMPACT_CALLERS = 6
COMPACT_CALLEES = 12
COMPACT_FACTS = 4
SHARED_GLOBAL_LIMIT = 40

_ADDRESS = re.compile(r"0x14[0-9a-f]{7}(?![0-9a-f])")
_GLOBAL = re.compile(r"\b(?:PTR_)?DAT_(14[0-9a-f]{7})\b")
_STRING = re.compile(r'L?"(?:[^"\\\n]|\\.)*"')
_REGISTRATION = re.compile(
    r"\(\*\*\(code \*\*\)\*\w+\)\(\w+,(0x[0-9a-f]+|\d+),(0x[0-9a-f]+|\d+),(\w+),(\w+),(\w+),\w+\);"
)
_DISPATCHER_NAME = re.compile(r"Handle\w*Messages?\w*")
_ONE_MESSAGE_HANDLER = re.compile(r"HandleMessage[0-9A-F]{4}\w*")
_SENDER_LINE = re.compile(r"\bSend\w*\(")
_TABLE_COLUMN_KEY = re.compile(r"[A-Z][A-Za-z0-9]*\.\w+")


class Refused(Exception):
    """A request the script will not carry out; the message says why."""


@dataclass(frozen=True)
class Subject:
    kind: str  # "address", "opcode" or "name"
    value: int | str


def parse_subject(text: str) -> Subject:
    """An address (0x hex of 0x140000000 or more), an opcode (0x hex of at most 0xFFFF, or decimal) or a
    function name; anything else is refused with the forms accepted."""
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", text):
        value = int(text, 16)
        if value >= IMAGE_BASE:
            return Subject("address", value)
        if value <= OPCODE_LIMIT:
            return Subject("opcode", value)
        raise Refused("%s is neither an opcode (at most 0x%X) nor a client address (0x%X up)" % (text, OPCODE_LIMIT, IMAGE_BASE))
    if re.fullmatch(r"[0-9]+", text):
        value = int(text)
        if value > OPCODE_LIMIT:
            raise Refused("%s is not an opcode: at most %d (0x%X)" % (text, OPCODE_LIMIT, OPCODE_LIMIT))
        return Subject("opcode", value)
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", text):
        return Subject("name", text)
    raise Refused("%r is not an address (0x14...), an opcode (0x4DB or 1243) or a function name" % text)


# ---------------------------------------------------------------- the size bound

def trim_to(text: str, limit: int) -> str:
    """text cut at a line boundary to at most limit characters, ending with a line that says how many lines
    were cut; text that fits is returned as it is."""
    if len(text) <= limit:
        return text
    lines = text.split("\n")
    kept, size = [], 0
    for line in lines:
        if size + len(line) + 1 > limit:
            break
        kept.append(line)
        size += len(line) + 1
    while True:
        note = "[%d of %d lines cut: raise --max-chars]" % (len(lines) - len(kept), len(lines))
        if not kept or size + len(note) <= limit:
            return "\n".join(kept + [note])
        size -= len(kept.pop()) + 1


@dataclass(frozen=True)
class Part:
    text: str
    shrinkable: bool = False  # a body: cut to a share of what the other parts leave


def fit(parts: list[Part], limit: int) -> str:
    """The parts in order, joined, within limit characters. The parts that are not shrinkable come first
    in priority; the shrinkable ones share what is left equally, each cut by trim_to, and are left out with
    a note when their share is under MIN_BODY_CHARS. When the others alone exceed the limit, they are cut."""
    fixed = sum(len(p.text) + 1 for p in parts if not p.shrinkable)
    bodies = [p for p in parts if p.shrinkable]
    if fixed >= limit:
        joined = "\n".join(p.text for p in parts if not p.shrinkable)
        omitted = "\n[%d bodies left out: the lists fill the bound; raise --max-chars]" % len(bodies) if bodies else ""
        return trim_to(joined + omitted, limit)
    share = (limit - fixed) // len(bodies) if bodies else 0
    out = []
    left_out = 0
    for part in parts:
        if not part.shrinkable:
            out.append(part.text)
        elif share >= MIN_BODY_CHARS:
            out.append(trim_to(part.text, share - 1))
        else:
            left_out += 1
    if left_out:
        out.append("[%d bodies left out: %d characters left for them; raise --max-chars]" % (left_out, limit - fixed))
    return "\n".join(out)


# ---------------------------------------------------------------- the message registration lines

@dataclass(frozen=True)
class Registration:
    opcode: int
    size: int
    sizer: str | None
    writer: str | None
    reader: str | None
    registered_in: int  # the function whose saved C holds the line
    line: int


def parse_registration(text: str, registered_in: int, line: int) -> Registration | None:
    """The registration call `(**(code **)*p)(p, id, record size, sizer, writer, reader, 0)` in one line of
    saved C; None for any other line. A 0 in the sizer, writer or reader place is None."""
    found = _REGISTRATION.search(text)
    if not found:
        return None
    opcode, size, sizer, writer, reader = found.groups()
    named = lambda word: None if word == "0" else word  # noqa: E731
    return Registration(int(opcode, 0), int(size, 0), named(sizer), named(writer), named(reader), registered_in, line)


def _grep(pattern: str, directory: Path) -> list[tuple[int, int, str]]:
    """(function address, line number, line) of every saved-C line matching the extended regex."""
    result = subprocess.run(
        ["grep", "-rEn", "--include=*.c", "--", pattern, str(directory)], capture_output=True, text=True
    )
    if result.returncode not in (0, 1):
        raise Refused("grep failed: %s" % result.stderr.strip())
    found = []
    for row in result.stdout.splitlines():
        path, number, text = row.split(":", 2)
        found.append((int(Path(path).stem, 16), int(number), text))
    return found


def read_registrations(directory: Path) -> list[Registration]:
    """Every registration line of the saved C."""
    found = (parse_registration(text, at, number) for at, number, text in _grep(_REGISTRATION.pattern, directory))
    return [r for r in found if r]


# ---------------------------------------------------------------- the dispatch tables

def first_opcode(code: list[jump_tables.Instruction], jmp_address: int) -> int | None:
    """The message id that picks the first entry of the jump table whose `jmp` is at jmp_address, read from
    the instruction that makes the table index (`lea eax, [rbx - 0x61]`, `sub eax, K`, `add eax, -K`, or a
    plain register copy, which is 0); None when that instruction is none of these. code is the dispatcher's
    listing, jump_tables.disassemble's."""
    position = next((i for i, c in enumerate(code) if c.address == jmp_address), None)
    if position is None:
        return None
    compared = None
    for i in range(position - 1, max(0, position - jump_tables.WINDOW) - 1, -1):
        c = code[i]
        if c.mnemonic == "cmp" and len(c.operands) == 2 and c.operands[0] in jump_tables.FAMILY and _immediate(c.operands[1]) is not None:
            compared = i
            break
    if compared is None:
        return None
    register = jump_tables.FAMILY[code[compared].operands[0]]
    for i in range(compared - 1, max(0, compared - jump_tables.WINDOW) - 1, -1):
        c = code[i]
        if c.mnemonic in jump_tables.NO_WRITE or not c.operands or jump_tables.FAMILY.get(c.operands[0]) != register:
            continue
        return _table_origin(c)
    return None


def _immediate(text: str) -> int | None:
    return int(text, 16) if re.fullmatch(r"-?0x[0-9a-f]+", text) else None


def _table_origin(c: jump_tables.Instruction) -> int | None:
    """The id of table entry 0 given the instruction that wrote the index; None when it is not a form read."""
    if len(c.operands) != 2:
        return None
    operand = c.operands[1]
    if c.mnemonic == "lea":
        made = re.fullmatch(r"\[\w+ ([-+]) (0x[0-9a-f]+)\]", operand)
        if made:
            return int(made.group(2), 16) * (1 if made.group(1) == "-" else -1)
        return None
    if c.mnemonic == "mov" and operand in jump_tables.FAMILY:
        return 0
    constant = _immediate(operand)
    if constant is not None and c.mnemonic == "sub":
        return constant
    if constant is not None and c.mnemonic == "add":
        return (1 << 32) - constant if constant >= 1 << 31 else -constant
    return None


@dataclass(frozen=True)
class CaseBlock:
    dispatcher: int
    jmp: int
    target: int  # the first instruction of the case
    calls: list[tuple[int, int]]  # (site, function called or tail-jumped to), in order
    ends_at: str  # why the walk stopped


def case_block(code: list[jump_tables.Instruction], target: int, is_function) -> tuple[list[tuple[int, int]], str]:
    """The calls from target in the dispatcher's listing to the first unconditional `jmp` (a tail call counts
    as a call and ends it), `ret`, or CASE_BLOCK_INSTRUCTIONS instructions; is_function says which targets
    are functions. Conditional jumps are not followed."""
    start = next((i for i, c in enumerate(code) if c.address == target), None)
    if start is None:
        return [], "the case's first instruction is not in the listing"
    calls = []
    for c in code[start : start + CASE_BLOCK_INSTRUCTIONS]:
        destination = _immediate(c.operands[0]) if c.mnemonic in ("call", "jmp") and c.operands else None
        if destination is not None and is_function(destination):
            calls.append((c.address, destination))
        if c.mnemonic == "jmp":
            return calls, "a jmp at 0x%x" % c.address
        if c.mnemonic == "ret":
            return calls, "a ret at 0x%x" % c.address
    return calls, "%d instructions" % CASE_BLOCK_INSTRUCTIONS


def dispatch_cases(pe, dispatcher: int, opcode: int, is_function) -> list[CaseBlock]:
    """The case blocks that jump tables of the dispatcher give the opcode: for each table whose index origin
    is read and whose range holds the opcode, the table's entry for it unless it is the table's default."""
    tables = [t for t in jump_tables.read_function(pe, dispatcher) if t.found]
    if not tables:
        return []
    listings = [(low, high, jump_tables.disassemble(pe, low, high)) for low, high in jump_tables.merged_ranges(pe.root_ranges(dispatcher))]
    found = []
    for table in tables:
        own = next((code for low, high, code in listings if low <= table.jmp < high), None)
        origin = first_opcode(own, table.jmp) if own else None
        if origin is None or not 0 <= opcode - origin < len(table.targets):
            continue
        target = table.targets[opcode - origin]
        if target == table.default:
            continue
        holding = next((code for low, high, code in listings if low <= target < high), None)
        calls, ends_at = case_block(holding, target, is_function) if holding else ([], "the case is in no range of the dispatcher")
        found.append(CaseBlock(dispatcher, table.jmp, target, calls, ends_at))
    return found


# ---------------------------------------------------------------- the fact file

class Facts:
    """The fact file's records, and which records cite which client address."""

    def __init__(self, records: dict[str, check_facts.Record]):
        self.records = records
        self._citing: dict[int, list[str]] = {}
        for key, record in records.items():
            held = set()
            for text in (record.statement, record.proof, record.gap or ""):
                held.update(int(found, 16) for found in _ADDRESS.findall(text.lower()))
            for address in held:
                if key != "0x%x" % address:
                    self._citing.setdefault(address, []).append(key)

    def keyed(self, address: int) -> check_facts.Record | None:
        return self.records.get("0x%x" % address)

    def citing(self, address: int) -> list[check_facts.Record]:
        return [self.records[key] for key in self._citing.get(address, [])]

    def for_opcode(self, opcode: int) -> list[check_facts.Record]:
        base = "opcode.0x%x" % opcode
        return [r for key, r in self.records.items() if key == base or key.startswith(base + ".")]


def describe_record(record: check_facts.Record, limit: int, with_gap: bool = False) -> str:
    statement = record.statement if len(record.statement) <= limit else record.statement[:limit].rstrip() + " [...]"
    text = "%s [%s]: %s" % (record.key, record.grade, statement)
    if with_gap and record.gap:
        gap = record.gap if len(record.gap) <= 500 else record.gap[:500].rstrip() + " [...]"
        text += "\n    gap: " + gap
    return text


# ---------------------------------------------------------------- one function

class Client:
    """What a run holds: the index, the saved C, the names and the facts."""

    def __init__(self, index: RefIndex, directory: Path, state: decompiled.State, facts: Facts):
        self.index = index
        self.directory = directory
        self.state = state
        self.facts = facts
        self.starts = set(index.pe.function_starts())
        self.by_name: dict[str, list[int]] = {}
        for address, name in state.names.items():
            self.by_name.setdefault(name, []).append(address)

    def label(self, address: int) -> str:
        name = self.state.names.get(address)
        return "0x%x %s" % (address, name) if name and not name.startswith("FUN_") else "0x%x" % address

    def is_function(self, address: int) -> bool:
        return address in self.starts or call_paths.is_leaf_address(self.index, address)

    def saved_c(self, address: int) -> str | None:
        path = self.directory / ("0x%x.c" % address)
        return path.read_text() if path.is_file() else None

    def resolve(self, subject: Subject) -> int:
        """The function start a name or an address means; Refused when it is none."""
        if subject.kind == "name":
            found = self.by_name.get(subject.value, [])
            if not found:
                close = difflib.get_close_matches(subject.value, list(self.by_name), n=5)
                raise Refused("no function is named %s in the saved C%s" % (subject.value, "; close: " + ", ".join(close) if close else ""))
            if len(found) > 1:
                raise Refused("%s names %d functions: %s" % (subject.value, len(found), ", ".join("0x%x" % a for a in sorted(found))))
            return found[0]
        try:
            call_paths.require_node(self.index, self.starts, subject.value, "function")
        except call_paths.Refused as refused:
            raise Refused(str(refused)) from refused
        return subject.value

    def global_users(self, address: int) -> list[int]:
        """The functions whose code refers to the data at address (`mov`, `lea` or compare through rip), by address."""
        users = {self.index.pe.root_of(r.source) for r in self.index.refs_to(address) if r.kind in ("rip-data", "rip-lea")}
        return sorted(u for u in users if u is not None)

    def callers(self, function: int) -> dict[int, list[int]]:
        return {caller: sites for caller, sites in self.index.callers(function).items() if caller != function}

    def callees(self, function: int) -> dict[int, list[int]]:
        """Target function -> call sites, for each `call` and tail `jmp` out of the function's .pdata ranges."""
        found: dict[int, list[int]] = {}
        for ref in self.index.sites_from(function, {"call", "jmp"}):
            if ref.target != function and self.is_function(ref.target):
                found.setdefault(ref.target, []).append(ref.source)
        return found


def _levels(neighbours, start: int, depth: int) -> list[list[tuple[int, int]]]:
    """Level n holds (function, the one it was reached from) for each function first met n steps from start."""
    seen = {start}
    levels: list[list[tuple[int, int]]] = []
    frontier = [start]
    for _ in range(depth):
        level = []
        for at in frontier:
            for other in neighbours(at):
                if other not in seen:
                    seen.add(other)
                    level.append((other, at))
        if not level:
            break
        levels.append(level)
        frontier = [member for member, _from in level]
    return levels


def _marker(client: Client, address: int) -> str:
    record = client.facts.keyed(address)
    return "  [fact: %s]" % record.grade if record else ""


def _listing(client: Client, function: int, up: bool, depth: int, limit: int) -> tuple[list[str], list[int]]:
    """The tree lines of the callers (up) or callees of a function to depth, at most limit lines at the first
    level and MAX_TREE_LINES for the rest, and the functions listed."""
    neighbours = (lambda at: sorted(client.callers(at))) if up else (lambda at: sorted(client.callees(at)))
    lines, listed = [], []
    for number, level in enumerate(_levels(neighbours, function, depth), 1):
        cap = limit if number == 1 else MAX_TREE_LINES
        for member, origin in level[:cap]:
            hop = call_paths.hop_description(client.index, member, origin) if up else call_paths.hop_description(client.index, origin, member)
            via = "" if number == 1 else "  (from %s)" % client.label(origin).split(" ", 1)[0]
            lines.append("  %s%s%s  (%s)%s" % ("  " * (number - 1), client.label(member), _marker(client, member), hop, via))
            listed.append(member)
        if len(level) > cap:
            lines.append("  %sand %d more" % ("  " * (number - 1), len(level) - cap))
    return lines, listed


def _references(client: Client, function: int) -> list[str]:
    """Every reference to the function that is not a call or tail jmp from another function."""
    phrases = []
    for ref in client.index.refs_to(function):
        root = client.index.pe.root_of(ref.source)
        if ref.kind in ("call", "jmp"):
            if root is None:
                phrases.append("%s from code outside .pdata at 0x%x" % (ref.kind, ref.source))
            continue
        where = " in " + client.label(root) if root is not None else ""
        phrases.append("%s at 0x%x%s" % (ref.kind, ref.source, where))
    return phrases


def function_parts(client: Client, function: int, depth: int, registrations: list[Registration], compact: bool = False, seen: set[str] | None = None) -> list[Part]:
    """The report on one function, as parts: its facts, callers, callees, strings and body. A record whose
    key is in seen was printed already and is left out; the keys printed are added to it."""
    seen = seen if seen is not None else set()
    parts: list[Part] = []
    text = client.saved_c(function)
    header = "== %s" % client.label(function)
    if text:
        first = text.split("\n", 1)[0]
        header += "   (saved C: %s)" % first.rsplit(" made under ", 1)[-1] if " made under " in first else ""
    parts.append(Part(header))
    name = client.state.names.get(function)
    for r in registrations:
        for role, held in (("sizer", r.sizer), ("writer", r.writer), ("reader", r.reader)):
            if held and (held == name or held == "FUN_%x" % function):
                parts.append(Part("registered as the %s of message 0x%x (record %d bytes) in %s line %d" % (role, r.opcode, r.size, client.label(r.registered_in), r.line)))

    callers_cap = COMPACT_CALLERS if compact else MAX_CALLERS
    callees_cap = COMPACT_CALLEES if compact else MAX_CALLEES
    up_lines, up_listed = _listing(client, function, True, depth, callers_cap)
    down_lines, down_listed = _listing(client, function, False, depth, callees_cap)

    def fresh(record: check_facts.Record) -> bool:
        if record.key in seen:
            return False
        seen.add(record.key)
        return True

    own = client.facts.keyed(function)
    facts = ["facts:"]
    if own and fresh(own):
        facts.append("  " + describe_record(own, FIRST_RECORD_CHARS, with_gap=True))
    elif not own and not compact:
        facts.append("  no record is keyed to this function")
    shown = [(role, m) for role, members in (("caller", up_listed), ("callee", down_listed)) for m in members if client.facts.keyed(m) and client.facts.keyed(m).key not in seen]
    for role, member in shown[:MAX_FACTS]:
        fresh(client.facts.keyed(member))
        facts.append("  (%s) %s" % (role, describe_record(client.facts.keyed(member), OTHER_RECORD_CHARS)))
    if len(shown) > MAX_FACTS:
        facts.append("  and %d more records keyed to the functions listed below" % (len(shown) - MAX_FACTS))
    citing = [r for r in client.facts.citing(function) if (not compact or not _ADDRESS.fullmatch(r.key)) and r.key not in seen]
    cap = COMPACT_FACTS if compact else MAX_FACTS
    for record in citing[:cap]:
        fresh(record)
        kind = "table column or enum" if _TABLE_COLUMN_KEY.fullmatch(record.key) else "cites it"
        facts.append("  (%s) %s" % (kind, describe_record(record, OTHER_RECORD_CHARS)))
    if len(citing) > cap:
        facts.append("  and %d more records cite it: %s" % (len(citing) - cap, ", ".join(r.key for r in citing[cap : cap + 12])))
    if len(facts) > 1:
        parts.append(Part("\n".join(facts)))

    references = _references(client, function)
    parts.append(Part("\n".join(["called by (%d functions):" % len(client.callers(function))] + (up_lines or ["  none"]))))
    if references:
        parts.append(Part("referenced otherwise: " + "; ".join(references[:MAX_DATA_REFERENCES]) + ("; and %d more" % (len(references) - MAX_DATA_REFERENCES) if len(references) > MAX_DATA_REFERENCES else "")))
    index = client.index
    imports = index.callees(function)[1]
    through = [r for r in index.sites_from(function, {"call-mem", "jmp-mem"}) if r.target not in index.pe.imports()]
    calls = ["calls (%d functions):" % len(client.callees(function))] + (down_lines or ["  none"])
    if imports:
        calls.append("  imports: " + ", ".join(imports))
    if through:
        calls.append("  %d sites call through a pointer in memory, first at 0x%x" % (len(through), through[0].source))
    parts.append(Part("\n".join(calls)))

    if text:
        strings = list(dict.fromkeys(_STRING.findall(text)))
        if strings and not compact:
            clipped = [s if len(s) <= 80 else s[:77] + '..."' for s in strings[:MAX_STRINGS]]
            parts.append(Part("strings: " + "  ".join(clipped) + ("  and %d more" % (len(strings) - MAX_STRINGS) if len(strings) > MAX_STRINGS else "")))
        shared = _shared_globals(client, function, text)
        if shared and not compact:
            parts.append(Part("\n".join(["globals the body refers to that other functions refer to too (fewest users first):"] + shared)))
        bodies = [(function, text)]
        if depth >= 2 and not compact:
            by_site = sorted(client.callees(function).items(), key=lambda item: item[1][0])
            bodies += [(callee, client.saved_c(callee)) for callee, _sites in by_site if client.saved_c(callee)][:MAX_CALLEE_BODIES]
        for owner, body in bodies:
            title = "body of %s:" % client.label(owner)
            parts.append(Part(title + "\n" + body.rstrip("\n"), shrinkable=True))
    else:
        parts.append(Part("no saved C for 0x%x (%s)" % (function, client.state.failed.get(function, "no file: a leaf function, or refresh the copy")), False))
    return parts


def global_addresses(text: str) -> list[int]:
    """The addresses of the global data (`DAT_<address>`, `PTR_DAT_<address>`) a function's saved C names, each
    once, in order of first use."""
    return list(dict.fromkeys(int(found, 16) for found in _GLOBAL.findall(text)))


def _shared_globals(client: Client, function: int, text: str) -> list[str]:
    """One line per global data address in the C that some other function also refers to, the ones with the
    fewest other users first: those are a flag or a setting the function shares with a few others. A global
    with more than SHARED_GLOBAL_LIMIT other users is a general object and is left out."""
    found = []
    for address in global_addresses(text):
        others = [u for u in client.global_users(address) if u != function]
        if others and len(others) <= SHARED_GLOBAL_LIMIT:
            found.append((len(others), address, others))
    lines = []
    for count, address, others in sorted(found)[:MAX_GLOBALS]:
        shown = ", ".join(client.label(u) for u in others[:MAX_GLOBAL_USERS])
        lines.append("  DAT_%x: %d other function(s): %s%s" % (address, count, shown, ", and %d more" % (count - MAX_GLOBAL_USERS) if count > MAX_GLOBAL_USERS else ""))
    if len(found) > MAX_GLOBALS:
        lines.append("  and %d more globals" % (len(found) - MAX_GLOBALS))
    return lines


# ---------------------------------------------------------------- one message

def dispatcher_addresses(client: Client, extra: list[int]) -> list[int]:
    named = [a for a, n in client.state.names.items() if _DISPATCHER_NAME.fullmatch(n) and not _ONE_MESSAGE_HANDLER.fullmatch(n)]
    return sorted(set(named) | set(extra))


def opcode_parts(client: Client, opcode: int, depth: int, extra_dispatchers: list[int]) -> tuple[list[Part], bool]:
    """The report on one message: its facts, registration, dispatch cases and uses, then its functions; and
    whether the client holds anything about the message."""
    parts: list[Part] = [Part("== message 0x%X (%d)" % (opcode, opcode))]
    records = client.facts.for_opcode(opcode)
    seen = {r.key for r in records}
    if records:
        parts.append(Part("facts:\n" + "\n".join("  " + describe_record(r, FIRST_RECORD_CHARS, with_gap=True) for r in records)))
    else:
        parts.append(Part("facts: no record is keyed opcode.0x%x" % opcode))

    registrations = read_registrations(client.directory)
    mine = [r for r in registrations if r.opcode == opcode]
    subjects: list[int] = []
    if mine:
        lines = ["registered:"]
        for r in mine:
            lines.append("  in %s line %d: record %d bytes, sizer %s, writer %s, reader %s" % (client.label(r.registered_in), r.line, r.size, r.sizer or "-", r.writer or "-", r.reader or "-"))
            for held in (r.writer, r.reader):
                address = _address_of(client, held)
                if address is not None:
                    subjects.append(address)
        parts.append(Part("\n".join(lines)))
    else:
        parts.append(Part("registered: no saved-C registration line holds 0x%x" % opcode))

    blocks = []
    for dispatcher in dispatcher_addresses(client, extra_dispatchers):
        blocks += dispatch_cases(client.index.pe, dispatcher, opcode, client.is_function)
    if blocks:
        lines = ["dispatched:"]
        for block in blocks:
            lines.append("  %s case at 0x%x (table jmp 0x%x), ends at %s; calls:" % (client.label(block.dispatcher), block.target, block.jmp, block.ends_at))
            lines += ["    0x%x -> %s" % (site, client.label(callee)) for site, callee in block.calls] or ["    none"]
            subjects += [callee for _site, callee in block.calls[:MAX_CASE_CALLEES]]
        parts.append(Part("\n".join(lines)))
    else:
        parts.append(Part("dispatched: no jump table of a named dispatcher holds it (a dispatcher that compares ids one by one is not found; --dispatcher names another)"))

    literal = r"[(,]0x%x[,)]" % opcode if opcode >= 10 else r"[(,]%d[,)]" % opcode
    registering = {r.registered_in for r in registrations}
    uses = [(at, number, text) for at, number, text in _grep(literal, client.directory) if at not in registering]
    senders = [u for u in uses if _SENDER_LINE.search(u[2])]
    others = [u for u in uses if u not in senders]
    if uses:
        lines = ["used by (a Send...( call is a sender; another use may be an equal number that is not this message):"]
        for at, number, text in senders:
            lines.append("  sender %s line %d: %s" % (client.label(at), number, text.strip()))
        grouped: dict[int, list[tuple[int, str]]] = {}
        for at, number, text in others:
            grouped.setdefault(at, []).append((number, text.strip()))
        for at, rows in list(grouped.items())[:MAX_OTHER_USES]:
            lines.append("  other  %s, %d line(s), first line %d: %s" % (client.label(at), len(rows), rows[0][0], rows[0][1]))
        if len(grouped) > MAX_OTHER_USES:
            lines.append("  and %d more functions with other uses" % (len(grouped) - MAX_OTHER_USES))
        parts.append(Part("\n".join(lines)))
        subjects += list(dict.fromkeys(at for at, _n, _t in senders))[:MAX_SENDERS]
    else:
        parts.append(Part("used by: no saved-C line passes 0x%x as a call argument" % opcode))

    for function in dict.fromkeys(subjects):
        if client.saved_c(function) is not None or client.is_function(function):
            parts += function_parts(client, function, depth, registrations, compact=True, seen=seen)
    return parts, bool(records or mine or blocks or uses)


def _address_of(client: Client, name: str | None) -> int | None:
    """The function a registration line's name stands for: FUN_<address>, or a saved name that one function holds."""
    if not name:
        return None
    if re.fullmatch(r"FUN_[0-9a-f]+", name):
        return int(name[4:], 16)
    matches = client.by_name.get(name, [])
    return matches[0] if len(matches) == 1 else None


# ---------------------------------------------------------------- the command

def open_client(env) -> Client:
    try:
        directory = decompiled.copy_directory(env)
    except decompiled.Refused as refused:
        raise Refused(str(refused)) from refused
    state = decompiled.load_state(directory)
    if state is None:
        raise Refused("no saved C in %s: run decompiled.py refresh" % directory)
    return Client(check_support.ref_index(), directory, state, Facts(check_facts.load(check_facts.FACT_FILE)))


def run(client: Client, text: str, depth: int, max_chars: int, dispatchers: list[str], out) -> int:
    subject = parse_subject(text)
    extra = [client.resolve(parse_subject(d)) for d in dispatchers]
    found = True
    if subject.kind == "opcode":
        parts, found = opcode_parts(client, subject.value, depth, extra)
    else:
        function = client.resolve(subject)
        parts = function_parts(client, function, depth, read_registrations(client.directory))
    print(fit(parts, max_chars), file=out)
    return 0 if found else 1


def _bounded(low: int, high: int):
    def parse(word: str) -> int:
        try:
            value = int(word)
        except ValueError:
            value = low - 1
        if not low <= value <= high:
            raise argparse.ArgumentTypeError("a whole number from %d to %d" % (low, high))
        return value

    return parse


def main(argv: list[str], env=None, out=None) -> int:
    """Runs the command and returns the exit status."""
    out = out or sys.stdout
    parser = argparse.ArgumentParser(description="What the client does with a function or a message.")
    parser.add_argument("subject", help="a 0x14... address, a function name, or an opcode (0x4DB or 1243)")
    parser.add_argument("--depth", type=_bounded(1, MAX_DEPTH), default=1)
    parser.add_argument("--max-chars", type=_bounded(2000, 1_000_000), default=DEFAULT_MAX_CHARS)
    parser.add_argument("--dispatcher", action="append", default=[], metavar="address_or_name")
    arguments = parser.parse_args(argv)
    try:
        client = open_client(env if env is not None else os.environ)
        return run(client, arguments.subject, arguments.depth, arguments.max_chars, arguments.dispatcher, out)
    except Refused as refused:
        print("client_trace: refused: %s" % refused, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
