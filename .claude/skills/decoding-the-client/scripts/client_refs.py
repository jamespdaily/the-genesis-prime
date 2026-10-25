"""A reference index of WildStar64.exe from llvm-objdump and the relocations,
independent of Ghidra. Tests use it as the expected answer for the query
process.

Built by a linear sweep of the executable sections: data inside .text can
decode as stray instructions, so a query names the .pdata function of each site.
"""

import bisect
import os
import re
import struct
import subprocess
from array import array
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from multiprocessing import get_context
from pathlib import Path

from client_pe import ClientPE

DEFAULT_OBJDUMP = "/opt/homebrew/opt/llvm/bin/llvm-objdump"

LINE_RE = re.compile(r"^\s*([0-9a-f]{6,16}):\s+(.*)$")
COMMENT_RE = re.compile(r"#\s*0x([0-9a-f]+)")
DIRECT_RE = re.compile(r"^0x([0-9a-f]+)(?:\s|$)")
PREFIXES = {
    "rep", "repe", "repne", "repz", "repnz", "lock", "bnd", "notrack", "data16",
    "cs", "ds", "es", "fs", "gs", "ss", "xacquire", "xrelease",
}
CONDITIONAL_JUMPS = {
    "ja", "jae", "jb", "jbe", "jc", "je", "jg", "jge", "jl", "jle", "jna", "jnae", "jnb", "jnbe",
    "jnc", "jne", "jng", "jnge", "jnl", "jnle", "jno", "jnp", "jns", "jnz", "jo", "jp", "jpe",
    "jpo", "js", "jz", "jrcxz", "jecxz", "loop", "loope", "loopne",
}

KINDS = ["call", "jmp", "jcc", "rip-data", "rip-lea", "call-mem", "jmp-mem", "pointer"]
KIND_CODE = {k: i for i, k in enumerate(KINDS)}
MAGIC = b"GPREFIX1"


def objdump_path() -> Path:
    return Path(os.environ.get("GENESIS_LLVM_OBJDUMP", DEFAULT_OBJDUMP))


def parse_line(line: str) -> tuple[int, str, int] | None:
    """(address, kind, target) of a reference the instruction makes, or None."""
    m = LINE_RE.match(line)
    if not m:
        return None
    address = int(m.group(1), 16)
    rest = m.group(2)
    comment = COMMENT_RE.search(rest)
    tokens = (rest[: comment.start()] if comment else rest).split(None, 1)
    while tokens and tokens[0] in PREFIXES and len(tokens) > 1:
        tokens = tokens[1].split(None, 1)
    if not tokens:
        return None
    mnemonic = tokens[0]
    operands = tokens[1].strip() if len(tokens) > 1 else ""
    if "[rip" in operands and comment:
        target = int(comment.group(1), 16)
        if mnemonic == "lea":
            return address, "rip-lea", target
        return address, {"call": "call-mem", "jmp": "jmp-mem"}.get(mnemonic, "rip-data"), target
    if mnemonic in ("call", "jmp") or mnemonic in CONDITIONAL_JUMPS:
        direct = DIRECT_RE.match(operands)
        if direct and "[" not in operands:
            return address, mnemonic if mnemonic in ("call", "jmp") else "jcc", int(direct.group(1), 16)
    return None


def _sweep(job: tuple[str, str, int, int]) -> list[tuple[int, str, int]]:
    objdump, exe, low, high = job
    command = [
        objdump, "-d", "--no-show-raw-insn", "--x86-asm-syntax=intel",
        "--start-address=0x%x" % low, "--stop-address=0x%x" % high, exe,
    ]
    found = []
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, errors="replace") as p:
        for line in p.stdout:
            ref = parse_line(line)
            if ref:
                found.append(ref)
    return found


def _chunks(pe: ClientPE, jobs: int) -> list[tuple[int, int]]:
    """The executable sections cut at function starts, which are instruction boundaries."""
    starts = sorted(pe.function_starts())
    out = []
    for s in pe.sections:
        if not s.executable:
            continue
        inside = starts[bisect.bisect_left(starts, s.va) : bisect.bisect_left(starts, s.end)]
        pieces = jobs * 4
        if jobs <= 1 or len(inside) < pieces * 2:
            out.append((s.va, s.end))
            continue
        cuts = sorted({s.va, s.end, *(inside[k * len(inside) // pieces] for k in range(1, pieces))})
        out += list(zip(cuts[:-1], cuts[1:]))
    return out


@dataclass(frozen=True)
class Ref:
    source: int
    target: int
    kind: str  # call, jmp, jcc, rip-data, rip-lea, call-mem, jmp-mem, pointer


class RefIndex:
    """Records sorted by source in three parallel arrays, and the same records
    ordered by target for lookups."""

    def __init__(self, exe: Path, sources: array, targets: array, kinds: bytes):
        self.pe = ClientPE(exe)
        self._sources, self._targets, self._kinds = sources, targets, kinds
        self._code_count = len(kinds) - kinds.count(KIND_CODE["pointer"])  # pointers come after the code records
        order = sorted(range(len(targets)), key=targets.__getitem__)  # stable: sources stay ascending
        self._by_target = array("I", order)
        self._sorted_targets = array("Q", (targets[i] for i in order))

    @staticmethod
    def build(pe: ClientPE, objdump: Path, jobs: int) -> "RefIndex":
        work = [(str(objdump), str(pe.path), low, high) for low, high in _chunks(pe, jobs)]
        code: list[tuple[int, str, int]] = []
        if jobs > 1:
            with ProcessPoolExecutor(jobs, mp_context=get_context("fork")) as pool:
                for found in pool.map(_sweep, work):
                    code += found
        else:
            for job in work:
                code += _sweep(job)
        code.sort(key=lambda r: r[0])
        pointers = sorted(pe.relocations())
        sources = array("Q", [r[0] for r in code] + [a for a, _v in pointers])
        targets = array("Q", [r[2] for r in code] + [v for _a, v in pointers])
        kinds = bytes([KIND_CODE[r[1]] for r in code] + [KIND_CODE["pointer"]] * len(pointers))
        return RefIndex(pe.path, sources, targets, kinds)

    @staticmethod
    def load(path: Path) -> "RefIndex":
        data = Path(path).read_bytes()
        if data[: len(MAGIC)] != MAGIC:
            raise ValueError("%s is not a reference index" % path)
        at = len(MAGIC)
        count, name_length = struct.unpack_from("<QI", data, at)
        at += 12
        exe = Path(data[at : at + name_length].decode())
        at += name_length
        sources, targets = array("Q"), array("Q")
        sources.frombytes(data[at : at + 8 * count])
        at += 8 * count
        targets.frombytes(data[at : at + 8 * count])
        at += 8 * count
        kinds = data[at : at + count]
        if len(kinds) != count or len(sources) != count or len(targets) != count:
            raise ValueError("%s is cut short" % path)
        return RefIndex(exe, sources, targets, kinds)

    def save(self, path: Path) -> None:
        name = str(self.pe.path).encode()
        with open(path, "wb") as f:
            f.write(MAGIC + struct.pack("<QI", len(self._sources), len(name)) + name)
            f.write(self._sources.tobytes() + self._targets.tobytes() + self._kinds)

    def _records_to(self, target: int) -> list[int]:
        low = bisect.bisect_left(self._sorted_targets, target)
        high = bisect.bisect_right(self._sorted_targets, target)
        return [self._by_target[i] for i in range(low, high)]

    def refs_to(self, target: int) -> list[Ref]:
        refs = [Ref(self._sources[i], target, KINDS[self._kinds[i]]) for i in self._records_to(target)]
        return sorted(refs, key=lambda r: r.source)

    def callers(self, function_start: int) -> dict[int, list[int]]:
        """Caller function start -> call sites, counting a jmp to the entry as a
        call, as Ghidra does. Sites outside every function are left out."""
        found: dict[int, list[int]] = {}
        for ref in self.refs_to(function_start):
            if ref.kind in ("call", "jmp"):
                root = self.pe.root_of(ref.source)
                if root is not None:
                    found.setdefault(root, []).append(ref.source)
        return found

    def callees(self, function_start: int) -> tuple[list[int], list[str]]:
        """(direct call targets, imports called through the IAT as 'dll!name')."""
        imports = self.pe.imports()
        internal, called = set(), set()
        for low, high in self.pe.root_ranges(function_start):
            first = bisect.bisect_left(self._sources, low, 0, self._code_count)
            for i in range(first, self._code_count):
                if self._sources[i] >= high:
                    break
                kind = self._kinds[i]
                if kind == KIND_CODE["call"]:
                    internal.add(self._targets[i])
                elif kind == KIND_CODE["call-mem"] and self._targets[i] in imports:
                    called.add(imports[self._targets[i]])
        return sorted(internal), sorted(called)

    def string_refs(self, text: str) -> dict[int, list[tuple[int, int | None]]]:
        """String address -> (site, function start) for each ASCII or UTF-16 copy of text."""
        patterns = [(text.encode("utf-16-le") + b"\0\0", 2)]
        try:
            patterns.append((text.encode("latin-1") + b"\0", 1))
        except UnicodeEncodeError:
            pass
        found: dict[int, list[tuple[int, int | None]]] = {}
        for s in self.pe.sections:
            if s.executable or s.raw_size == 0:
                continue
            blob = self.pe.data[s.raw_offset : s.raw_offset + s.raw_size]
            for pattern, alignment in patterns:
                at = blob.find(pattern)
                while at != -1:
                    if at % alignment == 0:
                        found[s.va + at] = self._sites(s.va + at)
                    at = blob.find(pattern, at + 1)
        return found

    def _sites(self, address: int) -> list[tuple[int, int | None]]:
        sites = [r.source for r in self.refs_to(address) if r.kind in ("rip-data", "rip-lea")]
        return [(site, self.pe.root_of(site)) for site in sites]
