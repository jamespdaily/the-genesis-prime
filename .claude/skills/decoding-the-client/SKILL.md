---
name: decoding-the-client
description: How a client fact is found, graded, saved and named. Use for any question only the client can answer - an opcode, a field, a table column, an enum, a formula, a Lua function.
---

# Decoding the client

A client fact is decoded once and saved as a record in one fact file, `references/client-facts.toml`. Each script's docstring or header is its contract: read it before you run the script.

## Every decode

- Search the fact file first, then the saved C ([decompiled-c.md](decompiled-c.md)), and only then ask the query process ([query-process.md](query-process.md)).
- A record is keyed by address, opcode, table column, enum or Lua function, with a plain statement, its proof and a grade (sure, fairly sure, guess). `scripts/check_facts.py` names the fields and checks them.
- A statement says what the client does in the game's or the message's terms: arguments, fields, types, values. Registers, stack and struct offsets and vtables go in the proof.
- A grade says how the fact was read. Sure: the instructions or rows were read, and the proof names them or the test that checks them. Fairly sure: read, with a named gap. Guess: not read, with what would settle it.
- A client address the code or tests cite has a record; an address a test plants on purpose is assigned to a `PLANTED_` name.
- A client value keeps its number until a decode saves what the client does with it. It is then renamed everywhere in the same change, and the function's name is saved in the Ghidra project too, by `scripts/name_functions.py`.
- Reach Ghidra only through `scripts/query.py`. When no request or tool answers the question, a scratch script in your scratch folder is allowed: name it in the proof, and add the missing request to issue 312 (the decoder's tools).
- While other decoders run, return new names to the coordinator, who saves them once all are idle; never stop a holder you did not start.

## Game tables

Read a table's rows with `gleam run -m genesis_prime/table_rows -- <Table> [<id> | <column>=<value> | --columns]`; its module doc (`dev/genesis_prime/table_rows.gleam`) is its contract. It reads rows as the server's own reader does, so a parser of your own can only differ from it. A proof that rests on rows names the command with its arguments, so the read can be rerun. A type-3 column prints a value with the top bit set in both readings; the proof names the client's reader of that column, which decides the reading.

## Which file to read

- [query-process.md](query-process.md): asking Ghidra, saving names, running a client function. Read it before your first request of a session.
- [decompiled-c.md](decompiled-c.md): searching the whole client's C. Read it before your first search of a session.
