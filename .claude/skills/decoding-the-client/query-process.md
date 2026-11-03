# The query process

`scripts/ghidra_query.py` is one Ghidra process on a saved, analysed project; its docstring lists the request kinds and their arguments. `scripts/query.py` holds that process open for every shell; its docstring says how to ask, read the status and stop. `scripts/ghidra_env.py` names the pinned parts and the settings it reads.

- Ask with `python3 -I scripts/query.py ask '<one JSON request>'`, or `ask --file requests.jsonl` for many. A script that makes many requests goes through the same holder with `query.open_client`.
- The holder is the only way into the project. Never write a driver, a FIFO or a start-and-poll loop for the query process, and never start `scripts/ghidra_query.py` by hand on an existing project: each would fight the holder for the project.
- The query process answers what text cannot: references, bytes, switch tables, the emulator. A text search is a grep of the saved C ([decompiled-c.md](decompiled-c.md)).
- A formula's expected values can come from running the client's function with the `emulate` request.

## Saving names

`scripts/name_functions.py` needs the project to itself, so it refuses while a holder runs. While other decoders run, return your names to the coordinator instead (SKILL.md). When none run: `python3 -I scripts/query.py stop`, then `scripts/name_functions.py` as its docstring says, then `python3 -I scripts/decompiled.py refresh`.
