"""The client query process: one Ghidra, one open project, many questions.

Reads one JSON request per line on stdin and writes one JSON reply per line on
stdout, until stdin closes. A bad request gets an error reply; the process
goes on. Run with the pinned Python and the environment ghidra_env reads.

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
  seed_report                             -> the SeedReport of the first open, or null
  emulate         function, args          -> {result, steps}
"""

KINDS = (
    "bytes", "function_at", "functions", "callers", "callees", "refs_to",
    "string_refs", "switch_targets", "seed_report", "emulate",
)


class BadRequest(Exception):
    pass


def handle(opened, request: dict) -> object:
    """The answer to one request; raises BadRequest for a malformed one."""
    raise NotImplementedError


def main() -> None:
    raise NotImplementedError


if __name__ == "__main__":
    main()
