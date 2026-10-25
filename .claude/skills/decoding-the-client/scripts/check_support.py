"""Helpers shared by the tests of the client query process; it holds no test.

- RawPE: a minimal PE parse written for the tests, the independent reading
  that client_pe.py is checked against.
- the cached PE and reference index, the ten questions of issue 16, and the
  expected answer of each from the index.
- QueryProcess: the query process started as a subprocess, JSON lines in and out.
- Watcher: the socket watcher of the issue 16 trial (netwatch.py).
- seeded_project(): one analysed project, built once per test run.

Every path but the client's comes from the environment:
WILDSTAR_CLIENT_EXE (default below), GENESIS_GHIDRA_DIR, JAVA_HOME,
GENESIS_PYGHIDRA_PYTHON, GENESIS_LLVM_OBJDUMP (default below).
"""

import atexit
import inspect
import json
import os
import queue
import random
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import types
import unittest
from dataclasses import dataclass
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

import formulas_by_hand  # noqa: E402

DEFAULT_CLIENT_EXE = "/Users/jimd/Coding/wildstar/client/WildStar/Client64/WildStar64.exe"
DEFAULT_OBJDUMP = "/opt/homebrew/opt/llvm/bin/llvm-objdump"

# Only CI sets GENESIS_NO_CLIENT=1, because it has no client; on any other machine a
# test that opens the client fails when the file is missing, so no test skips by accident.
NO_CLIENT = os.environ.get("GENESIS_NO_CLIENT") == "1"
needs_client = unittest.skipIf(NO_CLIENT, "the client is not on this machine: GENESIS_NO_CLIENT=1")

INTEGRATION = os.environ.get("GENESIS_INTEGRATION") == "1"
integration_only = unittest.skipUnless(
    INTEGRATION, "the Ghidra integration tests run only when GENESIS_INTEGRATION=1"
)


def client_exe() -> Path:
    return Path(os.environ.get("WILDSTAR_CLIENT_EXE", DEFAULT_CLIENT_EXE))


def objdump() -> Path:
    return Path(os.environ.get("GENESIS_LLVM_OBJDUMP", DEFAULT_OBJDUMP))


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise AssertionError(f"{name} must be set in the environment to run this test")
    return value


def hx(n: int) -> str:
    return "0x%x" % n


# Addresses used by more than one test. Each is measured on WildStar64.exe
# (SHA-256 565c2fa1...fe0b10) by the issue 16 trial's checkers.
FN_CONTROL_SWITCH = 0x140003FB0  # issue 16 trial: 27-case switch, jmp rdx at 0x140003fe8
JMP_CONTROL_SWITCH = 0x140003FE8
FN_BIG_SWITCH = 0x1403EC6A0  # issue 16 trial: 2,322 cases, jmp rcx at 0x1403ec719
JMP_BIG_SWITCH = 0x1403EC719
FN_NOT_A_SWITCH = 0x140001B30  # contains `jmp rax` at 0x140001b6b (llvm-objdump), no table
JMP_NOT_A_SWITCH = 0x140001B6B
POINTER_ONLY_A = 0x14077ED70  # issue 16 trial: one relocated pointer, from 0x140b6d240
POINTER_ONLY_B = 0x140001C30
IAT_SHOWCURSOR = 0x1409598F8  # issue 16 trial: user32.dll!ShowCursor
IAT_SETERRORMODE = 0x140959298  # issue 16 trial: kernel32.dll!SetErrorMode
IAT_WS2_115 = 0x140959A78  # issue 16 trial: ws2_32.dll!#115
SWITCH_JMP_DIFFERENCES = (0x1400BC619, 0x1403EC719, 0x140612B08)  # issue 16: where Ghidra and the reader differ


# ---------------------------------------------------------------- raw PE

class RawPE:
    """Sections, pdata and bytes parsed straight from the file with struct only."""

    SCN_EXECUTE = 0x20000000

    def __init__(self, path: Path):
        self.data = Path(path).read_bytes()
        d = self.data
        pe = struct.unpack_from("<I", d, 0x3C)[0]
        assert d[pe : pe + 4] == b"PE\0\0"
        count = struct.unpack_from("<H", d, pe + 6)[0]
        optional_size = struct.unpack_from("<H", d, pe + 20)[0]
        opt = pe + 24
        assert struct.unpack_from("<H", d, opt)[0] == 0x20B  # PE32+
        self.base = struct.unpack_from("<Q", d, opt + 24)[0]
        self.sections = []  # (name, rva, virtual_size, raw_offset, raw_size, characteristics)
        s = opt + optional_size
        for _ in range(count):
            name = d[s : s + 8].rstrip(b"\0").decode()
            vsize, rva, raw_size, raw_off = struct.unpack_from("<IIII", d, s + 8)
            chars = struct.unpack_from("<I", d, s + 36)[0]
            self.sections.append((name, rva, vsize, raw_off, raw_size, chars))
            s += 40

    def offset(self, va: int) -> int:
        rva = va - self.base
        for _name, srva, _vs, raw_off, raw_size, _c in self.sections:
            if srva <= rva < srva + raw_size:
                return raw_off + rva - srva
        raise ValueError(hex(va))

    def read(self, va: int, n: int) -> bytes:
        off = self.offset(va)
        return self.data[off : off + n]

    def u32(self, va: int) -> int:
        return struct.unpack("<I", self.read(va, 4))[0]

    def u64(self, va: int) -> int:
        return struct.unpack("<Q", self.read(va, 8))[0]

    def pdata(self) -> list[tuple[int, int, int | None]]:
        """(begin, end, chained parent begin or None), all virtual addresses, sorted.

        The unwind info's flags are the top 5 bits of its first byte; bit 0x4
        is UNW_FLAG_CHAININFO. A chained entry stores the parent's
        RUNTIME_FUNCTION after its unwind codes, which are padded to an even count.
        """
        name, rva, vsize, raw_off, raw_size, _c = next(s for s in self.sections if s[0] == ".pdata")
        out = []
        for i in range(vsize // 12):
            begin, end, unwind = struct.unpack_from("<III", self.data, raw_off + 12 * i)
            if begin == 0:
                continue
            uoff = self.offset(self.base + unwind)
            flags = self.data[uoff] >> 3
            parent = None
            if flags & 0x4:
                codes = self.data[uoff + 2]
                parent = self.base + struct.unpack_from("<I", self.data, uoff + 4 + 2 * ((codes + 1) & ~1))[0]
            out.append((self.base + begin, self.base + end, parent))
        out.sort()
        return out


# ---------------------------------------------------------------- cached evidence

_cache: dict = {}


def client_pe():
    if "pe" not in _cache:
        from client_pe import ClientPE

        _cache["pe"] = ClientPE(client_exe())
    return _cache["pe"]


def raw_pe() -> RawPE:
    if "raw" not in _cache:
        _cache["raw"] = RawPE(client_exe())
    return _cache["raw"]


def ref_index():
    """The full index; about 2 s with 4 jobs, built once per process."""
    if "index" not in _cache:
        from client_refs import RefIndex

        _cache["index"] = RefIndex.build(client_pe(), objdump(), 4)
    return _cache["index"]


def all_found_switches() -> list:
    """Every switch the jump-table reader finds in every .pdata function, once."""
    if "switches" not in _cache:
        from jump_tables import read_function

        pe = client_pe()
        _cache["switches"] = [
            t for start in pe.function_starts() for t in read_function(pe, start) if t.found
        ]
    return _cache["switches"]


# ---------------------------------------------------------------- the ten questions

# Issue 16's ten questions, as its questions.py drew them with random.Random(16).
QUESTIONS_16 = [
    {"id": 1, "kind": "bytes", "address": 0x1404A4E30},
    {"id": 2, "kind": "bytes", "address": 0x14063E550},
    {"id": 3, "kind": "callers", "function": 0x140663030},
    {"id": 4, "kind": "callers", "function": 0x14055A260},
    {"id": 5, "kind": "callees", "function": 0x140283670},
    {"id": 6, "kind": "callees", "function": 0x1403A81E0},
    {"id": 7, "kind": "string_refs", "text": "Lighting"},
    {"id": 8, "kind": "string_refs", "text": "DialogResponseType_ViewQuestIncomplete"},
    {"id": 9, "kind": "import", "name": "user32.dll!ShowCursor"},
    {"id": 10, "kind": "import", "name": "ws2_32.dll!#115"},
]

_MAX_TRIES = 200_000


def _draw(rng, items, ok, taken):
    for _ in range(_MAX_TRIES):
        x = rng.choice(items)
        if x in taken:
            continue
        r = ok(x)
        if r is not None:
            taken.add(x)
            return x, r
    raise AssertionError("no candidate satisfied the constraint after %d draws" % _MAX_TRIES)


def _ascii_string_at(blob: bytes, section_va: int, addr: int):
    """The whole printable NUL-delimited string that starts at addr, or None."""
    off = addr - section_va
    if off < 0 or off >= len(blob):
        return None
    if off > 0 and blob[off - 1] != 0:
        return None
    end = blob.find(b"\0", off)
    if end == -1:
        return None
    s = blob[off:end]
    if len(s) < 8 or any(c < 0x20 or c > 0x7E for c in s):
        return None
    return s.decode("ascii")


def draw_questions(pe, idx) -> list[dict]:
    """Ported from issue 16's questions.py: random.Random(16), two questions of
    each kind in the order bytes, callers, callees, string refs, imports;
    candidate lists sorted before every draw."""
    rng = random.Random(16)
    starts = sorted(pe.function_starts())
    qs = []

    taken = set()
    for _ in range(2):
        f, _r = _draw(rng, starts, lambda x: True, taken)
        qs.append({"kind": "bytes", "address": f})

    taken = set()
    for _ in range(2):  # 2..20 distinct calling functions

        def ok_callers(f):
            r = idx.callers(f)
            return r if 2 <= len(r) <= 20 else None

        f, _r = _draw(rng, starts, ok_callers, taken)
        qs.append({"kind": "callers", "function": f})

    taken = set()
    for _ in range(2):  # 2..20 distinct direct call targets

        def ok_callees(f):
            internal, imports = idx.callees(f)
            return (internal, imports) if 2 <= len(internal) <= 20 else None

        f, _r = _draw(rng, starts, ok_callees, taken)
        qs.append({"kind": "callees", "function": f})

    # whole printable ASCII strings in .rdata, length >= 8, exactly one copy in
    # the file, 1..10 referencing functions, every reference inside a function
    rdata = next(s for s in pe.sections if s.name == ".rdata")
    blob = pe.read(rdata.va, rdata.raw_size)
    cands = [
        t
        for t in range(rdata.va, rdata.va + rdata.raw_size)
        # issue 16's index filed call [rip+x] and jmp [rip+x] under rip-data; this
        # index names them call-mem and jmp-mem, so all four count to repeat its draw
        if any(r.kind in ("rip-data", "rip-lea", "call-mem", "jmp-mem") for r in idx.refs_to(t))
    ]
    taken = set()
    for _ in range(2):

        def ok_string(addr):
            text = _ascii_string_at(blob, rdata.va, addr)
            if text is None:
                return None
            copies = idx.string_refs(text)
            if len(copies) != 1 or addr not in copies:
                return None
            functions = {fn for _site, fn in copies[addr]}
            if not 1 <= len(functions) <= 10 or None in functions:
                return None
            return text

        addr, text = _draw(rng, cands, ok_string, taken)
        qs.append({"kind": "string_refs", "text": text})

    # 1..20 call sites through the import slot, all inside a function
    slot_of = {name: slot for slot, name in pe.imports().items()}
    names = sorted(slot_of)
    taken = set()
    for _ in range(2):

        def ok_import(name):
            sites = [r.source for r in idx.refs_to(slot_of[name]) if r.kind == "call-mem"]
            if 1 <= len(sites) <= 20 and all(pe.root_of(s) is not None for s in sites):
                return sites
            return None

        name, _r = _draw(rng, names, ok_import, taken)
        qs.append({"kind": "import", "name": name})

    for i, q in enumerate(qs, 1):
        q["id"] = i
    return qs


def request_for(question: dict, pe) -> tuple[str, dict]:
    """The query process request (kind, arguments) that asks a question."""
    k = question["kind"]
    if k == "bytes":
        return "bytes", {"address": hx(question["address"]), "length": 16}
    if k in ("callers", "callees"):
        return k, {"function": hx(question["function"])}
    if k == "string_refs":
        return "string_refs", {"text": question["text"]}
    slot = next(s for s, n in pe.imports().items() if n == question["name"])
    return "refs_to", {"address": hx(slot)}


def expected_value(question: dict, pe, idx):
    """The answer the index gives, in the normal form normalise_answer returns."""
    k = question["kind"]
    if k == "bytes":
        return pe.read(question["address"], 16).hex()
    if k == "callers":
        return {f: sorted(sites) for f, sites in idx.callers(question["function"]).items()}
    if k == "callees":
        internal, imports = idx.callees(question["function"])
        return {"internal": sorted(internal), "imports": sorted(imports)}
    if k == "string_refs":
        return {a: sorted(refs, key=_none_last) for a, refs in idx.string_refs(question["text"]).items()}
    slot = next(s for s, n in pe.imports().items() if n == question["name"])
    return {r.source: pe.root_of(r.source) for r in idx.refs_to(slot)}


def expected_caller_sites(question: dict, pe, idx) -> dict:
    """Call site -> its .pdata function, or None where no .pdata entry holds the
    site. A jmp to the entry counts as a call, as Ghidra counts it."""
    return {r.source: pe.root_of(r.source) for r in idx.refs_to(question["function"]) if r.kind in ("call", "jmp")}


def caller_sites(answer) -> dict:
    """The query process's callers answer as call site -> calling function."""
    return {_addr(site): _addr(e["function"]) for e in answer for site in e["sites"]}


def _none_last(pair):
    return (pair[0], -1 if pair[1] is None else pair[1])


def _addr(text):
    return None if text is None else int(text, 16)


def normalise_answer(question: dict, answer):
    k = question["kind"]
    if k == "bytes":
        return answer
    if k == "callers":
        return {_addr(e["function"]): sorted(_addr(s) for s in e["sites"]) for e in answer}
    if k == "callees":
        return {"internal": sorted(_addr(a) for a in answer["internal"]), "imports": sorted(answer["imports"])}
    if k == "string_refs":
        return {
            _addr(e["string"]): sorted(((_addr(r["from"]), _addr(r["function"])) for r in e["refs"]), key=_none_last)
            for e in answer
        }
    return {_addr(r["from"]): _addr(r["function"]) for r in answer}


# ---------------------------------------------------------------- the planted copies

def planted_client_exe(parent: Path, file_offset: int, xor: int) -> Path:
    """A copy of the client with the 4-byte little-endian value at file_offset XORed."""
    copy = Path(parent) / "WildStar64-planted.exe"
    shutil.copyfile(client_exe(), copy)
    with open(copy, "r+b") as f:
        f.seek(file_offset)
        (old,) = struct.unpack("<I", f.read(4))
        f.seek(file_offset)
        f.write(struct.pack("<I", old ^ xor))
    return copy


def planted_ghidra_dir(parent: Path, version: str = "12.1.4") -> Path:
    """A copy of the install's directory layout (everything else a symlink into
    the real one) whose Ghidra/application.properties names another version."""
    real = Path(require_env("GENESIS_GHIDRA_DIR"))
    out = Path(parent) / "ghidra_planted"
    (out / "Ghidra").mkdir(parents=True)
    for entry in real.iterdir():
        if entry.name != "Ghidra":
            (out / entry.name).symlink_to(entry)
    for entry in (real / "Ghidra").iterdir():
        if entry.name != "application.properties":
            (out / "Ghidra" / entry.name).symlink_to(entry)
    text = (real / "Ghidra" / "application.properties").read_text()
    changed, n = re.subn(r"(?m)^application\.version=.*$", f"application.version={version}", text)
    assert n == 1
    (out / "Ghidra" / "application.properties").write_text(changed)
    return out


def planted_formula_a():
    """formula_a with every 0x1F replaced by 0x1E."""
    source = inspect.getsource(formulas_by_hand.formula_a)
    assert source.count("0x1F") == 2
    namespace = {"M32": formulas_by_hand.M32, "M64": formulas_by_hand.M64}
    exec(source.replace("0x1F", "0x1E"), namespace)
    return namespace["formula_a"]


def planted_formula_b():
    """formula_b with C_PI_OVER_180 moved by one float32 ulp."""
    bits = formulas_by_hand.f32_bits(formulas_by_hand.C_PI_OVER_180) + 1
    moved = struct.unpack("<f", struct.pack("<I", bits))[0]
    assert moved != formulas_by_hand.C_PI_OVER_180
    return types.FunctionType(
        formulas_by_hand.formula_b.__code__, {**vars(formulas_by_hand), "C_PI_OVER_180": moved}
    )


# ---------------------------------------------------------------- processes

def wait_until(predicate, deadline_seconds: float, poll: float = 0.05) -> bool:
    """True as soon as predicate is, False when the deadline passes first."""
    end = time.monotonic() + deadline_seconds
    while True:
        if predicate():
            return True
        if time.monotonic() >= end:
            return False
        time.sleep(poll)


def process_table() -> list[tuple[int, int, str]]:
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,comm="], capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and parts[0].isdigit() and parts[1].isdigit():
            rows.append((int(parts[0]), int(parts[1]), parts[2]))
    return rows


def process_tree(root: int) -> list[int]:
    """root and every descendant of it now."""
    children: dict[int, list[int]] = {}
    for pid, ppid, _comm in process_table():
        children.setdefault(ppid, []).append(pid)
    found, todo = [], [root]
    while todo:
        pid = todo.pop()
        found.append(pid)
        todo.extend(children.get(pid, []))
    return found


def java_or_decompile_pids() -> set[int]:
    return {
        pid
        for pid, _ppid, comm in process_table()
        if os.path.basename(comm) == "java" or os.path.basename(comm).startswith("decompile")
    }


def pid_alive(pid: int) -> bool:
    # A finished child that is not yet reaped shows as a zombie (Z); it is not alive.
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return state != "" and not state.startswith("Z")


def query_environment(project_dir: Path, ghidra_dir: Path | None = None) -> dict:
    env = dict(os.environ)
    env["GENESIS_GHIDRA_DIR"] = str(ghidra_dir) if ghidra_dir else require_env("GENESIS_GHIDRA_DIR")
    env["GENESIS_GHIDRA_PROJECT_DIR"] = str(project_dir)
    env["WILDSTAR_CLIENT_EXE"] = str(client_exe())
    env["JAVA_HOME"] = require_env("JAVA_HOME")
    return env


def query_command(seed: Path | None = None) -> list[str]:
    # No -I: the script puts its own directory on sys.path to import its siblings.
    # `--seed PATH` is new in the interface: it is used only when the project
    # does not exist yet; main() takes it in the build step.
    cmd = [require_env("GENESIS_PYGHIDRA_PYTHON"), str(SCRIPTS / "ghidra_query.py")]
    if seed is not None:
        cmd += ["--seed", str(seed)]
    return cmd


@dataclass(frozen=True)
class Reply:
    body: dict
    ms: float  # measured by this client around the request, write to read

    @property
    def answer(self):
        assert self.body.get("ok") is True, self.body
        return self.body["answer"]


class QueryProcess:
    """The query process as a subprocess, one JSON line per request and reply."""

    def __init__(self, project_dir: Path, seed: Path | None = None, ghidra_dir: Path | None = None):
        self.stderr_file = tempfile.TemporaryFile()
        self.started = time.monotonic()
        self.proc = subprocess.Popen(
            query_command(seed),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.stderr_file,
            env=query_environment(project_dir, ghidra_dir),
            cwd=project_dir,
        )
        self.lines: queue.Queue = queue.Queue()
        self.first_reply_seconds: float | None = None
        self._next_id = 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def stderr_text(self) -> str:
        self.stderr_file.seek(0)
        return self.stderr_file.read().decode(errors="replace")

    def _reply(self, started: float, timeout: float) -> Reply:
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty:
            raise AssertionError(f"no reply within {timeout} s; stderr:\n{self.stderr_text()}")
        ms = (time.perf_counter() - started) * 1000
        if line is None:
            raise AssertionError(f"the process closed stdout; stderr:\n{self.stderr_text()}")
        if self.first_reply_seconds is None:
            self.first_reply_seconds = time.monotonic() - self.started
        return Reply(json.loads(line), ms)

    def send_line(self, raw: bytes, timeout: float = 120) -> Reply:
        """One raw line (a newline is added) and the next reply line."""
        started = time.perf_counter()
        self.proc.stdin.write(raw + b"\n")
        self.proc.stdin.flush()
        return self._reply(started, timeout)

    def ask(self, kind: str, timeout: float = 120, **arguments) -> Reply:
        self._next_id += 1
        request = {"id": self._next_id, "kind": kind, **arguments}
        reply = self.send_line(json.dumps(request).encode(), timeout)
        if reply.body.get("id") != self._next_id:
            raise AssertionError(f"reply {reply.body} is not for request {request}")
        return reply

    def close(self, timeout: float = 60) -> int:
        """Closes stdin and waits for the process to end; kills it and fails after timeout."""
        if not self.proc.stdin.closed:
            self.proc.stdin.close()
        try:
            return self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            raise AssertionError(f"the process did not stop {timeout} s after stdin closed")

    def kill(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()


# ---------------------------------------------------------------- the socket watcher

LOCAL_PEERS = ("127.", "::1", "[::1]", "localhost", "*")


def _sockets(pids) -> list[str]:
    out = subprocess.run(
        ["lsof", "-nP", "-a", "-i", "-p", ",".join(map(str, pids))], capture_output=True, text=True
    ).stdout
    return [line for line in out.splitlines()[1:] if line.strip()]


def _peer(line: str):
    parts = line.split()
    name = parts[8] if len(parts) > 8 else ""
    return name.split("->")[1] if "->" in name else None


def _outside(line: str) -> bool:
    peer = _peer(line)
    return peer is not None and not peer.startswith(LOCAL_PEERS)


class Watcher(threading.Thread):
    """Samples every socket of a process tree and flags any remote address off
    this machine (ported from the issue 16 trial's netwatch.py). It stops when
    the root exits or finish() is called, after at least one sample."""

    def __init__(self, root: int, interval: float = 1.0):
        super().__init__(daemon=True)
        self.root = root
        self.interval = interval
        self.samples = 0
        self.max_tree = 0
        self.socket_lines: list[str] = []
        self.outside: list[str] = []
        self._stop_event = threading.Event()
        self.start()

    def run(self):
        seen = set()
        while True:
            pids = process_tree(self.root)
            self.max_tree = max(self.max_tree, len(pids))
            for line in _sockets(pids):
                key = " ".join(line.split()[8:])
                if key not in seen:
                    seen.add(key)
                    self.socket_lines.append(line)
                if _outside(line) and line not in self.outside:
                    self.outside.append(line)
            self.samples += 1
            if self._stop_event.is_set() or not pid_alive(self.root):
                return
            self._stop_event.wait(self.interval)

    def finish(self):
        self._stop_event.set()
        self.join()


def lan_address() -> str | None:
    """This machine's address on its LAN, not loopback, or None when it has none."""
    for iface in ("en0", "en1", "en2"):
        out = subprocess.run(["ipconfig", "getifaddr", iface], capture_output=True, text=True).stdout.strip()
        if out:
            return out
    return None


def watch_a_connection(host: str, seconds: float = 4.0) -> Watcher:
    """Starts a child that connects to host, and watches that child until it ends."""
    listener = socket.socket()
    listener.bind((host, 0))
    listener.listen()
    port = listener.getsockname()[1]
    child = subprocess.Popen(
        [
            sys.executable,
            "-I",
            "-c",
            f"import socket,time; s=socket.create_connection(('{host}',{port})); time.sleep({seconds})",
        ]
    )
    try:
        watcher = Watcher(child.pid, interval=0.5)
        child.wait()
        watcher.join()
    finally:
        listener.close()
    return watcher


# ---------------------------------------------------------------- the shared project

@dataclass
class BuiltProject:
    project_dir: Path
    seed_path: Path
    seed_lines: list  # what the seed file holds, the planted unmapped line last
    first_report: dict  # the reply to seed_report of the first start
    first_start_seconds: float
    watcher: Watcher  # on the first session's process tree


def seeded_project() -> BuiltProject:
    """One project built from a seed file with PLANTED_UNMAPPED appended: import,
    seed, analysis and save, once per test run (about 3 minutes). Classes take
    turns opening it; none writes to it after this build."""
    if "project" in _cache:
        return _cache["project"]
    if "project_error" in _cache:  # a failed 3-minute build is not tried again by every class
        raise AssertionError("the shared project failed to build earlier: %r" % (_cache["project_error"],))
    try:
        return _build_seeded_project()
    except Exception as error:
        _cache["project_error"] = error
        raise


def _build_seeded_project() -> BuiltProject:
    import seed

    root = Path(tempfile.mkdtemp(prefix="genesis-ghidra-test-"))
    atexit.register(shutil.rmtree, root, True)
    project_dir = root / "project"
    project_dir.mkdir()
    lines = seed.seed_lines(client_pe()) + [(seed.PLANTED_UNMAPPED, "function", "seed_planted_unmapped")]
    seed_path = root / "seed.tsv"
    seed.write_seed(lines, seed_path)
    qp = QueryProcess(project_dir, seed=seed_path)
    watcher = Watcher(qp.proc.pid)
    try:
        report = qp.ask("seed_report", timeout=1800).answer
        seconds = qp.first_reply_seconds
        qp.close()
    finally:
        qp.kill()
        watcher.finish()
    _cache["project"] = BuiltProject(project_dir, seed_path, lines, report, seconds, watcher)
    return _cache["project"]


def fresh_unseeded_project() -> tuple[Path, Path]:
    """(root to delete, an empty project directory) for a project made without a seed."""
    root = Path(tempfile.mkdtemp(prefix="genesis-ghidra-test-unseeded-"))
    atexit.register(shutil.rmtree, root, True)
    project_dir = root / "project"
    project_dir.mkdir()
    return root, project_dir
