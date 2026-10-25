---
name: designing-processes
description: Design rules for processes on the BEAM - actors, services, supervisors, handlers, restarts, shutdown, connections, memory, logging. Use before adding or changing a process, actor, service or supervisor.
---

# Designing processes

The server is designed for the BEAM from the first line. Processes, messages, supervision and the runtime's own tools are the building blocks. Nothing is designed as threads, locks, shared objects or a game loop and then translated.

Apply every section to each change, and check the diff against each before it is done.

## Structure

- Draw the supervision tree before the code: which processes exist, what each owns, how each restarts, and what players see when each dies. Isolated parts of the game get isolated processes.
- A process exists only for state, concurrency or failure isolation. Pure code stays in plain functions.
- Every process starts under a supervisor.
- One process owns each piece of state; others ask it by message. Peers never call each other synchronously; a timed call up the tree, to a registry or a worker, is normal.
- A process's messages are defined by its module, with the functions that send them.
- State is a record with one status field, not several flags. Settings and process names are start arguments, made once.
- A request carries a reply subject and a chosen deadline when the asker must not block. A late reply is expected and handled.
- When sending more than one message to a named process, look it up once and send to the subject or pid.
- No database work inside a busy process's handler or an actor's initialiser. Saves and lookups run in supervised workers with deadlines.
- Moves between two owners (trade, mail with an item, auction, group loot) have one source of truth: a database transaction or a coordinator. Each transfer has a test, including failure halfway.
- Every process that can fall behind has a measured ceiling and a load test. A producer never outruns its consumer: batch, shed or look things up instead.
- Time comes from the monotonic clock and timed messages, never wall-clock time inside a rule. The monotonic clock can be negative, so 0 never means none.
- Rules are deterministic: they take the current time and the random state as inputs.

## Handlers

A handler is the function a process runs for each message.

- A handler matches the message, calls one rule and carries out its effects in order. Game decisions live in rules, never in the handler or its effect runner.
- A handler does only the work its message needs; it never preloads data a rule might read.
- The selector covers every message the process can receive; anything else is logged.

## Restarts and shutdown

- Each supervisor states its restart intensity, period and shutdown timeouts, chosen per level. Each process says what a restart rebuilds its state from.
- Cleanup that must happen (freeing a name, a map slot, a session) runs in a process that monitors the dying one.
- Shutdown is ordered: stop accepting, drain connections, flush saves, then stop. No hot code upgrades in production.
- Saves are versioned, so an older save never overwrites a newer one, and idempotent, so a retry is safe. Each kind of state names how much play a crash can lose.

## Connections

- Each connection has a packet size cap, a rate limit and socket flow control (active once or active N). The server has a connection cap. Each limit has a test.
- Atoms are made only from values the server wrote, never from client input, and `binary_to_term` reads only bytes the server wrote.

## Logging

- Log through Erlang's logger. Error: a bug, always looked into. Warning: an outside failure the server recovered from. Info: start, stop, login, logout. Debug: per-message detail, off by default.
- Every log line carries who and where as metadata: account, character or unit, process or map, message name and number. Never a password, session key or other secret.

## Memory

- Keep a busy process's live data small; leave data another process owns with that process.
- Data many processes read and nobody changes while running goes in a persistent term, written once at start: a few large terms, never many small ones, never replaced while running. Its key is a start argument.
- Find nearby units and players by spatial index (grid cells), on every path, including rare ones.
- Players and connections keep waiting messages off the heap.
- Send a process only what it needs: an id, not a record.
