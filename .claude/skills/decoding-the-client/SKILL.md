---
name: decoding-the-client
description: Sets how a WildStar client fact is found, graded, saved and named, with the scripts that search the fact file, the saved C, Ghidra, the client's texts and its tables. Use for any question only the client can answer - an opcode, a field, a table column, an enum, a formula, a Lua function.
---

# Decoding the client

A client fact is decoded once and saved as a record in one fact file, `references/client-facts.toml`. Each script's docstring or header is its contract: read it before you run the script.

## Every decode

- Search in this order. First the fact file; for an address, a function name or an opcode, `python3.13 -I scripts/client_trace.py <subject>` returns the function's saved C, callers, callees, strings, shared globals and records in one call. Then the saved C ([decompiled-c.md](decompiled-c.md), read before your first search of a session). Only then the query process ([query-process.md](query-process.md), read before your first request of a session).
- A record is keyed by address, opcode, table column, enum or Lua function, with a plain statement, its proof and a grade; `scripts/check_facts.py` names the fields and checks them.
- A statement says what the client does in the game's or the message's terms: arguments, fields, types, values. Registers, stack and struct offsets and vtables go in the proof.
- Grades: **sure**, the instructions or rows were read and the proof names them or the test that checks them; **fairly sure**, read, with a named gap; **guess**, not read, with what would settle it.
- When a statement says what the player sees while the server sends a value (an empty list, a 0), return that effect to the coordinator, who puts it on the open issue that will fill it. "The client accepts it" is not "the player sees it right".
- A client address the code or tests cite has a record; an address a test plants on purpose is assigned to a `PLANTED_` name.
- A client value keeps its number until a decode saves what the client does with it; it is then renamed everywhere in the same change, and in the Ghidra project by `scripts/name_functions.py`.
- Reach Ghidra only through `scripts/query.py`. When no request or tool answers, a scratch script in your scratch folder is allowed: name it in the proof, and add the missing tool as a line on the milestone's parent issue.
- While other decoders run, return new names to the coordinator, who saves them once all are idle; never stop a holder you did not start.

## Texts, UI files and call paths

Run these with `~/.genesis-prime/env.sh` read.

- A text by id, or every text holding some words: `python3.13 -I scripts/client_files.py text <id>...` or `text --search <words>`. Never write a reader of en-US.bin or dump it to search it.
- The UI folder's files (forms, Lua, art) and en-US.bin: `scripts/client_files.py extract`, then `check` once per session; search the folder it names rather than writing a puller of the archive.
- Which functions a function reaches, or what reaches it: `python3.13 -I scripts/call_paths.py <function> --to <target>... [--up]`. Never write a breadth-first walk of `callees` or `callers` requests.

## Game tables

`gleam run -m genesis_prime/table_rows -- <Table> [<id>... | <column>=<value> | --columns]` reads rows as the server's own reader does (contract: `dev/genesis_prime/table_rows.gleam`); never write a parser of your own. Name all ids in one run. A proof that rests on rows names the command with its arguments. A type-3 column prints a value with the top bit set in both readings; the proof names the client's reader of that column, which decides the reading.
