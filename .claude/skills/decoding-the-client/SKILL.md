---
name: decoding-the-client
description: How a client fact is found, graded, saved and named. Use for any question only the client can answer - an opcode, a field, a table column, an enum, a formula, a Lua function.
---

# Decoding the client

- A client fact is decoded once and saved as a record in one fact file: keyed by address, opcode, table column, enum or Lua function, with a plain statement, its proof and a grade (sure, fairly sure, guess). Its name is saved in the Ghidra project too.
- Every decode searches the fact file first.
- A client value keeps its number until a decode saves what the client does with it. It is then renamed everywhere in the same change.
