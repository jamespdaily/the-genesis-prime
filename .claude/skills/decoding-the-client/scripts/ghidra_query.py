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
  emulate         function, args          -> {"result": {"rax": int, "xmm0_low": int}, "steps": n}
                                             args: JSON ints go in RCX, RDX, R8, R9 and JSON floats
                                             in XMM0..XMM3 as float32, by position
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ghidra_env  # noqa: E402

KINDS = (
    "bytes", "function_at", "functions", "callers", "callees", "refs_to",
    "string_refs", "switch_targets", "seed_report", "emulate",
)
MAX_BYTES = 1 << 20


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


def _imported(function) -> str:
    """'dll!name' with the dll lower-case, as the PE import table names it."""
    dll, _, name = function.getName(True).partition("::")
    if name.startswith("Ordinal_"):
        name = "#" + name[len("Ordinal_"):]
    return "%s!%s" % (dll.lower(), name)


def _callees(program, request: dict) -> dict:
    from ghidra.util.task import TaskMonitor

    function = _function_at_entry(program, request, "function")
    internal, imports = set(), set()
    for callee in function.getCalledFunctions(TaskMonitor.DUMMY):
        if callee.isExternal():
            imports.add(_imported(callee))
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


def _emulate(program, request: dict) -> dict:
    import client_emulator

    address = _address(program, request, "function")
    args = request.get("args")
    if not isinstance(args, list) or not all(
        isinstance(a, (int, float)) and not isinstance(a, bool) for a in args
    ):
        raise BadRequest("'emulate' needs a list of numbers in 'args'")
    try:
        run = client_emulator.run_function(program, address.getOffset(), args)
    except client_emulator.EmulationFailed as error:
        raise BadRequest("emulation failed: %s" % error) from error
    return {"result": {"rax": run.rax, "xmm0_low": run.xmm0_low}, "steps": run.steps}


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
        opened.close()


if __name__ == "__main__":
    main()
