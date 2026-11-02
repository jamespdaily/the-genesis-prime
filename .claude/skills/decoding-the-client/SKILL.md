---
name: decoding-the-client
description: How a client fact is found, graded, saved and named. Use for any question only the client can answer - an opcode, a field, a table column, an enum, a formula, a Lua function.
---

# Decoding the client

- A client fact is decoded once and saved as a record in one fact file, `references/client-facts.toml`: keyed by address, opcode, table column, enum or Lua function, with a plain statement, its proof and a grade (sure, fairly sure, guess). `scripts/check_facts.py` names the fields and checks them. A function's name is saved in the Ghidra project too, by `scripts/name_functions.py`.
- A statement says what the client does in the game's or the message's terms: arguments, fields, types, values. Registers, stack and struct offsets and vtables go in the proof.
- A grade says how the fact was read. Sure: the instructions or rows were read, and the proof names them or the test that checks them. Fairly sure: read, with a named gap. Guess: not read, with what would settle it.
- Every decode searches the fact file first, then the saved C (below), before it queries the process. Every client address the code or tests cite has a record; an address a test plants on purpose is assigned to a `PLANTED_` name.
- A client value keeps its number until a decode saves what the client does with it. It is then renamed everywhere in the same change.
- The client is queried through `scripts/ghidra_query.py`: one Ghidra 12.2 process on a saved, analysed project, one JSON request per line on stdin. Its docstring lists the request kinds; `scripts/ghidra_env.py` names the pinned parts and the environment it reads. The first start needs `--seed` with a file written by `scripts/seed.py`.
- Query the client only through the query process (`scripts/ghidra_query.py`): decompile, disassemble and run readers with its requests. Never build a scratch Ghidra server or emulator script; a request it lacks goes on an issue.
- The whole client's decompiled C is saved, one file per function, `0x<address>.c`, in `~/.genesis-prime/decompiled/` (`GENESIS_DECOMPILED_DIR` moves it). A search across the client is a grep of that folder: a constant, an opcode, a string's use, a struct offset, a callee's name. Do not decompile function by function to search.
- Before searching, run `python3 -I scripts/decompiled.py check`. It says current, stale (naming each renamed, new or lost function) or no copy, and exits non-zero unless current. Stale or no copy: run `refresh`. A check takes about 10 seconds; a whole refresh about 7 minutes; after a few renames, seconds.
- `refresh` redoes the functions whose name changed or that are new, and every file that names a changed function's old name, its address or a pointer to it. It lists any function whose decompile failed (its file holds the error line) and goes on. It writes its state file last: a refresh that stops midway leaves the old state, `check` says so, and the next run does the work again.
- A file's first line holds its function, its address and the hash it was made under. A proof that cites saved C names the file by address and that hash.
- The query process answers what text cannot: references, bytes, switch tables, the emulator.
- After `scripts/name_functions.py` saves names, run `refresh`. Both need the Ghidra project, so neither runs while a query process or the other holds it.
- The copy is the client's code: `scripts/decompiled.py` refuses a folder inside any git working tree, and nothing in it is committed.
- Scripts start the query process through `scripts/query_client.py`, not their own copy.
- The query process's settings live in `~/.genesis-prime/env.sh`, and `./setup-check` names any that are missing. Ghidra refuses a project path with a folder starting with a dot.
- A formula's expected values can come from running the client's function with the `emulate` request. Ghidra's p-code wraps an out-of-range float-to-integer conversion where the CPU gives 0x80000000, so a value near that overflow is checked against the CPU's rule.
