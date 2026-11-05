---
name: decoding-the-client
description: How a client fact is found, graded, saved and named. Use for any question only the client can answer - an opcode, a field, a table column, an enum, a formula, a Lua function.
---

# Decoding the client

A client fact is decoded once and saved as a record in one fact file, `references/client-facts.toml`. Each script's docstring or header is its contract: read it before you run the script.

## Every decode

- Search the fact file first; for an address, a function name or an opcode, run `python3.13 -I scripts/client_trace.py <subject>`, which returns the function's saved C, callers, callees, strings, shared globals and records in one call. Then search the saved C ([decompiled-c.md](decompiled-c.md)) for what it does not show, and only then ask the query process ([query-process.md](query-process.md)).
- A record is keyed by address, opcode, table column, enum or Lua function, with a plain statement, its proof and a grade (sure, fairly sure, guess). `scripts/check_facts.py` names the fields and checks them.
- A statement says what the client does in the game's or the message's terms: arguments, fields, types, values. Registers, stack and struct offsets and vtables go in the proof.
- A grade says how the fact was read. Sure: the instructions or rows were read, and the proof names them or the test that checks them. Fairly sure: read, with a named gap. Guess: not read, with what would settle it.
- A client address the code or tests cite has a record; an address a test plants on purpose is assigned to a `PLANTED_` name.
- A client value keeps its number until a decode saves what the client does with it. It is then renamed everywhere in the same change, and the function's name is saved in the Ghidra project too, by `scripts/name_functions.py`.
- Reach Ghidra only through `scripts/query.py`. When no request or tool answers the question, a scratch script in your scratch folder is allowed: name it in the proof, and add the missing tool as a new line on issue 3 (Milestone 2, the parent of the decoder's tools), for the coordinator to make an issue.
- While other decoders run, return new names to the coordinator, who saves them once all are idle; never stop a holder you did not start.

## The client's texts, UI files and call paths

Each script's docstring is its contract. Run them with `~/.genesis-prime/env.sh` read.

- A text by id, or every text holding some words: `python3.13 -I scripts/client_files.py text <id>...` or `text --search <words>`. It reads en-US.bin, which `table_rows` cannot. Never write a reader of the file or dump it to search it.
- The UI folder's files (forms, Lua, art) and en-US.bin, as files outside the repository: `scripts/client_files.py extract`, then `check` once per session. Search the folder it names ($GENESIS_CLIENT_FILES_DIR, else `~/.genesis-prime/client-files`) rather than writing a puller of the archive.
- Which functions a function reaches, or what reaches it, to a depth: `python3.13 -I scripts/call_paths.py <function> --to <target>... [--up]`. It walks the objdump reference index, which sees the case blocks Ghidra's references miss, and states the hops it cannot take (a call through memory, a function reached only as data). Never write a breadth-first walk of `callees` or `callers` requests.

## Game tables

Read a table's rows with `gleam run -m genesis_prime/table_rows -- <Table> [<id>... | <column>=<value> | --columns]` (several ids read the table once, so name them all in one run); its module doc (`dev/genesis_prime/table_rows.gleam`) is its contract. It reads rows as the server's own reader does, so a parser of your own can only differ from it. A proof that rests on rows names the command with its arguments, so the read can be rerun. A type-3 column prints a value with the top bit set in both readings; the proof names the client's reader of that column, which decides the reading.

## Which file to read

- [query-process.md](query-process.md): asking Ghidra, saving names, running a client function. Read it before your first request of a session.
- [decompiled-c.md](decompiled-c.md): searching the whole client's C. Read it before your first search of a session.
