"""The client query process: one Ghidra, one open project, many questions.

Reads one JSON request per line on stdin and writes one JSON reply per line on
stdout, until stdin closes. A bad request gets an error reply; the process
goes on. Run with the pinned Python and the environment ghidra_env reads.

Start:    ghidra_query.py [--seed PATH | --unseeded]; --seed names the seed file and is
          used only when the project does not exist yet, so the first start imports,
          seeds, analyses and saves, and later starts only open it. A first start
          needs --seed or --unseeded (an import with no seed, said outright) and
          refuses to import with neither.

Request:  {"id": 1, "kind": "callers", "function": "0x140663030"}
Reply:    {"id": 1, "ok": true, "answer": [...], "ms": 0.4}
          {"id": 1, "ok": false, "error": "unknown kind 'x'"}

Kinds and their arguments (addresses are 0x-prefixed lower-case hex):
  bytes           address, length         -> hex string
  function_at     address                 -> {start, name} or null
  functions                               -> [start, ...]
  callers         function                -> [{function, sites}], tail-call jmps included
  callees         function                -> {internal: [start], imports: ["dll!name"]}
  refs_to         address                 -> [{from, type, function}]
  string_refs     text                    -> [{string, refs: [{from, function}]}]
  switch_targets  jmp                     -> [target, ...]
  seed_report                             -> null, or after the first start
                                             {lines, created, already_present, failed: [hex], unmapped: [hex]}
  decompile       function [, timeout_s]  -> {signature, c}: Ghidra's C for the function, with the
                                             project's names. One decompiler per program is opened on
                                             the first request and kept. timeout_s defaults to 60; a
                                             decompile that fails or passes it is an error reply naming
                                             the cause, and the process goes on.
  disassemble     function                -> [{address, bytes, text}] in address order: the listing of
                  | start, stop              the function with that start, or of [start, stop) up to
                                             1 MiB. bytes is hex; text is Ghidra's syntax with the
                                             project's own names.
  emulate         function | start, stop, -> {"result": {"rax": int, "xmm0_low": int},
                  args, registers, memory,    "registers": {name: int}, "read": [hex], "steps": n,
                  read, stand_ins,            "stopped_at": address}
                  follow_calls, max_steps
    Every request starts from a clean machine: the program's own bytes, a 64 KiB stack and zeroed
    registers, with nothing left by an earlier request.
    function    run that function until it returns; or
    start, stop run the instructions from start until the counter reaches stop (or a return from
                the stack's start). Exactly one of the two forms.
    args        JSON ints go in RCX, RDX, R8, R9 and JSON floats in XMM0..XMM3 as float32, by
                position; at most four. Optional.
    registers   {name: int} set after args, lower-case: rax rbx rcx rdx rsi rdi rbp rsp r8..r15 and
                xmm0..xmm15 (128 bits). Unset registers are 0. rsp defaults to the top of the stack
                with a return address pushed that ends a function run; a request that sets rsp
                itself gets no such return address and should give start and stop.
    memory      [{address, bytes}]: bytes (hex) planted at address before the run, mapping a region
                of any size (up to 64 MiB in all) where nothing is mapped. Mapped memory is the
                program's initialised sections, the stack, these regions and the heap's blocks.
    read        [{address, length}]: bytes (up to 1 MiB each) read back after the run, as hex, in
                order; a range that is not all mapped fails the request.
    stand_ins   {call target: {"kind": ...}}: the target is a function's start, or the address of
                the import table slot a call goes through, as 0x hex; a call the listing shows
                going there is answered in Python and the run goes on after it. Kinds:
                  heap_alloc  RCX bytes (zeroed) from a bump allocator in its own mapped region
                              that starts at 0x600000000000, 16-byte aligned; the pointer in RAX
                  heap_free   nothing happens
                  return      {"kind": "return", "value": int}: RAX = value
                A call to an import with no stand-in fails the request, naming the import as
                dll!name. A call whose target is known only when it runs (through a register) cannot
                have a stand-in.
    follow_calls  true: a call with no stand-in is stepped into; false (default): it fails the
                request, "calls out at <address>".
    max_steps   instructions before the run fails; default 100000, at most 100000000.
    Any load or store outside mapped memory fails the request as unmapped memory.
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import client_emulator  # noqa: E402
import ghidra_env  # noqa: E402

KINDS = (
    "bytes", "function_at", "functions", "callers", "callees", "refs_to",
    "string_refs", "switch_targets", "seed_report", "emulate", "decompile", "disassemble",
)
MAX_BYTES = 1 << 20
TOP = (1 << 64) - 1
MAX_PLANTED = 1 << 26
MAX_STEPS = 100_000_000
DEFAULT_DECOMPILE_TIMEOUT_S = 60


class BadRequest(Exception):
    pass


def _hex(address) -> str:
    return "0x%x" % address.getOffset()


def _need(request: dict, name: str, kind: type):
    value = request.get(name)
    if isinstance(value, bool) or not isinstance(value, kind):
        raise BadRequest("%r needs a %s in %r" % (request["kind"], kind.__name__, name))
    return value


def _address(program, request: dict, name: str):
    text = _need(request, name, str)
    if not (text.startswith("0x") and len(text) > 2 and all(c in "0123456789abcdefABCDEF" for c in text[2:])):
        raise BadRequest("%r is not an address written as 0x and hex digits" % text)
    space = program.getAddressFactory().getDefaultAddressSpace()
    value = int(text, 16)
    if value >= 1 << 64:
        raise BadRequest("%s is beyond the address space" % text)
    return space.getAddress(value - (1 << 64) if value >= 1 << 63 else value)


def _function_start(program, address) -> str | None:
    function = program.getFunctionManager().getFunctionContaining(address)
    return None if function is None else _hex(function.getEntryPoint())


def _function_at_entry(program, request: dict, name: str):
    address = _address(program, request, name)
    function = program.getFunctionManager().getFunctionAt(address)
    if function is None:
        raise BadRequest("no function starts at %s" % _hex(address))
    return function


def _bytes(program, request: dict) -> str:
    from jpype import JArray, JByte
    from ghidra.program.model.mem import MemoryAccessException

    address = _address(program, request, "address")
    length = _need(request, "length", int)
    if not 0 <= length <= MAX_BYTES:
        raise BadRequest("length must be from 0 to %d" % MAX_BYTES)
    buffer = JArray(JByte)(length)
    try:
        program.getMemory().getBytes(address, buffer)
    except MemoryAccessException as error:
        raise BadRequest("cannot read %d bytes at %s: %s" % (length, _hex(address), error)) from error
    return bytes(buffer).hex()


def _callers(program, request: dict) -> list[dict]:
    entry = _function_at_entry(program, request, "function").getEntryPoint()
    sites: dict[str, list[int]] = {}
    for ref in program.getReferenceManager().getReferencesTo(entry):
        if ref.getReferenceType().isCall():
            site = ref.getFromAddress()
            caller = _function_start(program, site)
            if caller is not None:
                sites.setdefault(caller, []).append(site.getOffset())
    return [{"function": f, "sites": ["0x%x" % a for a in sorted(s)]} for f, s in sorted(sites.items())]


def _callees(program, request: dict) -> dict:
    from ghidra.util.task import TaskMonitor

    function = _function_at_entry(program, request, "function")
    internal, imports = set(), set()
    for callee in function.getCalledFunctions(TaskMonitor.DUMMY):
        if callee.isExternal():
            imports.add(client_emulator.import_name(callee))
        else:
            internal.add(callee.getEntryPoint().getOffset())
    return {"internal": ["0x%x" % a for a in sorted(internal)], "imports": sorted(imports)}


def _refs_to(program, request: dict) -> list[dict]:
    target = _address(program, request, "address")
    return [
        {
            "from": _hex(ref.getFromAddress()),
            "type": ref.getReferenceType().getName(),
            "function": _function_start(program, ref.getFromAddress()),
        }
        for ref in sorted(program.getReferenceManager().getReferencesTo(target), key=lambda r: r.getFromAddress())
    ]


_string_indexes: dict[int, tuple[object, dict[str, list]]] = {}


def _strings(program) -> dict[str, list]:
    """Defined string value -> its addresses; read from the listing once per program."""
    held = _string_indexes.get(id(program))
    if held is None or held[0] is not program:
        index: dict[str, list] = {}
        for data in program.getListing().getDefinedData(True):
            if data.hasStringValue():
                index.setdefault(str(data.getValue()), []).append(data.getAddress())
        held = _string_indexes[id(program)] = (program, index)
    return held[1]


def _string_refs(program, request: dict) -> list[dict]:
    text = _need(request, "text", str)
    refs = program.getReferenceManager()
    return [
        {
            "string": _hex(address),
            "refs": [
                {"from": _hex(r.getFromAddress()), "function": _function_start(program, r.getFromAddress())}
                for r in sorted(refs.getReferencesTo(address), key=lambda r: r.getFromAddress())
            ],
        }
        for address in _strings(program).get(text, [])
    ]


def _switch_targets(program, request: dict) -> list[str]:
    address = _address(program, request, "jmp")
    instruction = program.getListing().getInstructionAt(address)
    if instruction is None:
        raise BadRequest("no instruction at %s" % _hex(address))
    targets = {r.getToAddress().getOffset() for r in instruction.getReferencesFrom() if r.getReferenceType().isFlow()}
    return ["0x%x" % t for t in sorted(targets)]


def _number(request: dict, name: str, default):
    value = request.get(name, default)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BadRequest("%r needs a number in %r" % (request["kind"], name))
    return value


def _hex_bytes(text, what: str) -> bytes:
    if not isinstance(text, str):
        raise BadRequest("%s needs hex digits as a string" % what)
    try:
        return bytes.fromhex(text)
    except ValueError as error:
        raise BadRequest("%s is not hex: %s" % (what, error)) from error


def _entries(request: dict, name: str) -> list[dict]:
    entries = request.get(name, [])
    if not isinstance(entries, list) or not all(isinstance(e, dict) for e in entries):
        raise BadRequest("%r needs a list of objects in %r" % (request["kind"], name))
    return entries


def _int_in(entry: dict, name: str, what: str) -> int:
    value = entry.get(name)
    if isinstance(value, bool) or not isinstance(value, int):
        raise BadRequest("%s needs an integer in %r" % (what, name))
    return value


def _plan(program, request: dict):
    if ("function" in request) == ("start" in request or "stop" in request):
        raise BadRequest("'emulate' needs 'function', or 'start' and 'stop', and not both")
    if "function" in request:
        start, stop = _address(program, request, "function").getOffset() & TOP, None
    else:
        start = _address(program, request, "start").getOffset() & TOP
        stop = _address(program, request, "stop").getOffset() & TOP
    args = request.get("args", [])
    if not isinstance(args, list) or not all(isinstance(a, (int, float)) and not isinstance(a, bool) for a in args):
        raise BadRequest("'emulate' needs a list of numbers in 'args'")
    registers = request.get("registers", {})
    if not isinstance(registers, dict):
        raise BadRequest("'emulate' needs an object in 'registers'")
    for name, value in registers.items():
        if name not in client_emulator.REGISTER_NAMES:
            raise BadRequest("%r is not a register name; they are %s" % (name, " ".join(client_emulator.REGISTER_NAMES)))
        if isinstance(value, bool) or not isinstance(value, int):
            raise BadRequest("register %r needs an integer" % name)
    memory, planted = [], 0
    for entry in _entries(request, "memory"):
        data = _hex_bytes(entry.get("bytes"), "'bytes' of a 'memory' entry")
        address = _address(program, entry | {"kind": "emulate"}, "address").getOffset() & TOP
        planted += len(data)
        memory.append((address, data))
    if planted > MAX_PLANTED:
        raise BadRequest("'memory' plants %d bytes; the most is %d" % (planted, MAX_PLANTED))
    read = []
    for entry in _entries(request, "read"):
        length = _int_in(entry, "length", "an entry of 'read'")
        if not 0 <= length <= MAX_BYTES:
            raise BadRequest("a 'read' length must be from 0 to %d" % MAX_BYTES)
        read.append((_address(program, entry | {"kind": "emulate"}, "address").getOffset() & TOP, length))
    stand_ins = request.get("stand_ins", {})
    if not isinstance(stand_ins, dict):
        raise BadRequest("'emulate' needs an object in 'stand_ins'")
    answers = {}
    for target, spec in stand_ins.items():
        address = _address(program, {"kind": "emulate", "target": target}, "target").getOffset() & TOP
        if not isinstance(spec, dict) or spec.get("kind") not in client_emulator.STAND_IN_KINDS:
            raise BadRequest(
                "the stand-in for %s needs a 'kind' of %s" % (target, ", ".join(client_emulator.STAND_IN_KINDS))
            )
        value = _int_in(spec, "value", "the 'return' stand-in for %s" % target) if spec["kind"] == "return" else 0
        answers[address] = client_emulator.StandIn(spec["kind"], value)
    follow_calls = request.get("follow_calls", False)
    if not isinstance(follow_calls, bool):
        raise BadRequest("'follow_calls' is true or false")
    max_steps = request.get("max_steps", client_emulator.DEFAULT_MAX_STEPS)
    if isinstance(max_steps, bool) or not isinstance(max_steps, int) or not 1 <= max_steps <= MAX_STEPS:
        raise BadRequest("'max_steps' is an integer from 1 to %d" % MAX_STEPS)
    return client_emulator.Plan(
        start, stop, tuple(args), registers, tuple(memory), tuple(read), answers, follow_calls, max_steps
    )


def _emulate(program, request: dict) -> dict:
    plan = _plan(program, request)
    try:
        run = client_emulator.emulate(program, plan)
    except client_emulator.EmulationFailed as error:
        raise BadRequest("emulation failed: %s" % error) from error
    return {
        "result": {"rax": run.rax, "xmm0_low": run.xmm0_low},
        "registers": run.registers,
        "read": [data.hex() for data in run.read],
        "steps": run.steps,
        "stopped_at": "0x%x" % run.stopped_at,
    }


_decompilers: dict[int, tuple[object, object]] = {}


def _decompiler(program):
    """The program's DecompInterface, opened on first use and kept."""
    held = _decompilers.get(id(program))
    if held is None or held[0] is not program:
        from ghidra.app.decompiler import DecompInterface

        interface = DecompInterface()
        if not interface.openProgram(program):
            message = str(interface.getLastMessage())
            interface.dispose()
            raise BadRequest("the decompiler could not open the program: %s" % message)
        held = _decompilers[id(program)] = (program, interface)
    return held[1]


def _close_decompilers() -> None:
    for _program, interface in _decompilers.values():
        interface.dispose()
    _decompilers.clear()


def _decompile(program, request: dict) -> dict:
    import math

    from java.util.concurrent import TimeUnit
    from ghidra.util.task import TimeoutTaskMonitor

    function = _function_at_entry(program, request, "function")
    timeout = _number(request, "timeout_s", DEFAULT_DECOMPILE_TIMEOUT_S)
    if timeout <= 0:
        raise BadRequest("'timeout_s' must be above 0")
    interface = _decompiler(program)
    monitor = TimeoutTaskMonitor.timeoutIn(max(1, round(timeout * 1000)), TimeUnit.MILLISECONDS)
    result = interface.decompileFunction(function, max(1, math.ceil(timeout)), monitor)
    if result.isTimedOut() or result.isCancelled() or monitor.isCancelled():
        # the decompiler process may have been stopped: drop it so the next request opens a fresh one
        interface.dispose()
        del _decompilers[id(program)]
        raise BadRequest("the decompile of %s passed its timeout of %s s" % (_hex(function.getEntryPoint()), timeout))
    if not result.decompileCompleted():
        raise BadRequest("the decompile of %s failed: %s" % (_hex(function.getEntryPoint()), result.getErrorMessage()))
    decompiled = result.getDecompiledFunction()
    return {"signature": str(decompiled.getSignature()), "c": str(decompiled.getC())}


def _disassemble(program, request: dict) -> list[dict]:
    from ghidra.program.model.address import AddressSet

    listing = program.getListing()
    if ("function" in request) == ("start" in request or "stop" in request):
        raise BadRequest("'disassemble' needs 'function', or 'start' and 'stop', and not both")
    if "function" in request:
        instructions = listing.getInstructions(_function_at_entry(program, request, "function").getBody(), True)
    else:
        start, stop = _address(program, request, "start"), _address(program, request, "stop")
        length = (stop.getOffset() & TOP) - (start.getOffset() & TOP)
        if not 0 < length <= MAX_BYTES:
            raise BadRequest("'stop' must be above 'start' and at most %d bytes after it" % MAX_BYTES)
        instructions = listing.getInstructions(AddressSet(start, stop.subtract(1)), True)
    return [
        {"address": _hex(i.getAddress()), "bytes": bytes(i.getBytes()).hex(), "text": str(i)} for i in instructions
    ]


def _seed_report(opened) -> dict | None:
    report = opened.seed_report
    if report is None:
        return None
    return {
        "lines": report.lines,
        "created": report.created,
        "already_present": report.already_present,
        "failed": ["0x%x" % a for a in report.failed],
        "unmapped": ["0x%x" % a for a in report.unmapped],
    }


def handle(opened, request: dict) -> object:
    """The answer to one request; raises BadRequest for a malformed one."""
    kind = request.get("kind")
    if kind not in KINDS:
        raise BadRequest("unknown kind %r" % (kind,))
    program = opened.program
    if kind == "bytes":
        return _bytes(program, request)
    if kind == "function_at":
        function = program.getFunctionManager().getFunctionContaining(_address(program, request, "address"))
        return None if function is None else {"start": _hex(function.getEntryPoint()), "name": function.getName()}
    if kind == "functions":
        return [_hex(f.getEntryPoint()) for f in program.getFunctionManager().getFunctions(True)]
    if kind == "callers":
        return _callers(program, request)
    if kind == "callees":
        return _callees(program, request)
    if kind == "refs_to":
        return _refs_to(program, request)
    if kind == "string_refs":
        return _string_refs(program, request)
    if kind == "switch_targets":
        return _switch_targets(program, request)
    if kind == "seed_report":
        return _seed_report(opened)
    if kind == "decompile":
        return _decompile(program, request)
    if kind == "disassemble":
        return _disassemble(program, request)
    return _emulate(program, request)


def _reply(request_id, started: float, **fields) -> str:
    return json.dumps({"id": request_id, **fields, "ms": round((time.perf_counter() - started) * 1000, 3)})


def serve(opened, lines, out) -> None:
    for line in lines:
        if not line.strip():
            continue
        started = time.perf_counter()
        request_id = None
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise BadRequest("a request is a JSON object")
            request_id = request.get("id")
            reply = _reply(request_id, started, ok=True, answer=handle(opened, request))
        except (json.JSONDecodeError, BadRequest) as error:
            reply = _reply(request_id, started, ok=False, error=str(error))
        out.write(reply + "\n")
        out.flush()


def main() -> None:
    parser = argparse.ArgumentParser(description="Answers JSON requests about the client, one per line on stdin.")
    seeding = parser.add_mutually_exclusive_group()
    seeding.add_argument("--seed", type=Path, help="the seed file, used only when the project does not exist yet")
    seeding.add_argument(
        "--unseeded", action="store_true", help="import with no seed when the project does not exist yet"
    )
    arguments = parser.parse_args()
    try:
        settings = ghidra_env.settings_from_env(os.environ)
        ghidra_env.check_parts(settings)
    except ghidra_env.WrongVersion as error:
        sys.exit("ghidra_query: %s" % error)
    import ghidra_project

    try:
        opened = ghidra_project.open_project(settings, ghidra_project.UNSEEDED if arguments.unseeded else arguments.seed)
    except ghidra_project.SeedRequired as error:
        sys.exit("ghidra_query: %s" % error)
    try:
        _strings(opened.program)
        serve(opened, sys.stdin, sys.stdout)
    finally:
        _close_decompilers()
        opened.close()


if __name__ == "__main__":
    main()
