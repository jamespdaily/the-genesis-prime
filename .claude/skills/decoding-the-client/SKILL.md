---
name: decoding-the-client
description: How a client fact is found, graded, saved and named. Use for any question only the client can answer - an opcode, a field, a table column, an enum, a formula, a Lua function.
---

# Decoding the client

- A client fact is decoded once and saved as a record in one fact file: keyed by address, opcode, table column, enum or Lua function, with a plain statement, its proof and a grade (sure, fairly sure, guess). Its name is saved in the Ghidra project too.
- Every decode searches the fact file first.
- A client value keeps its number until a decode saves what the client does with it. It is then renamed everywhere in the same change.
- The client is queried through `scripts/ghidra_query.py`: one Ghidra 12.2 process on a saved, analysed project, one JSON request per line on stdin. Its docstring lists the request kinds; `scripts/ghidra_env.py` names the pinned parts and the environment it reads. The first start needs `--seed` with a file written by `scripts/seed.py`.
- A formula's expected values can come from running the client's function with the `emulate` request. Ghidra's p-code wraps an out-of-range float-to-integer conversion where the CPU gives 0x80000000, so a value near that overflow is checked against the CPU's rule.
