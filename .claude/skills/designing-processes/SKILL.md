---
name: designing-processes
description: Sets the design rules for processes on the BEAM here - supervision trees, ownership, messages, shells and rules, restarts, shutdown, connections, logging and memory. Use before adding or changing a process, actor, service, supervisor, rule or shell.
---

# Designing processes

Design in processes, messages and supervision from the start, never by translating threads, locks, shared objects or a game loop. For any process change:
- Draw the supervision tree before the code: which processes exist, what each owns, how each restarts, and what players see when each dies.
- Make a process for state, concurrency or failure isolation; anything else is a plain function. Decoding, ciphers and game calculations are calls, not processes.
- Start each process under a supervisor. One process owns each piece of state; others ask it by message.
- A process that decides anything the client or the game can observe is a shell plus one rule (CLAUDE.md's terms).

Read the file for the part you change:
- [structure.md](structure.md): the tree, ownership, messages, requests and deadlines, time, restarts and shutdown. Read it for a new process, a new message between processes, or a supervisor change.
- [shells-and-rules.md](shells-and-rules.md): what a shell turns into inputs, how effects run, recordings and replays. Read it for any change to a rule or a shell.
- [connections-logging-memory.md](connections-logging-memory.md): connection limits, atoms, log levels and metadata, what a busy process keeps, persistent terms. Read it for a connection, a log line, or data many processes read.
