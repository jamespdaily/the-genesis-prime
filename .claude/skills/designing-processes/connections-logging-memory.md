# Connections, logging and memory

## Connections

- Each connection has a packet size cap, a rate limit and socket flow control (active once or active N). The server has a connection cap. Each limit has a test.
- Atoms are made from values the server wrote, not from client input, and `binary_to_term` reads only bytes the server wrote (`test/code_rule/atom.gleam`).

## Logging

- Log through Erlang's logger. Error: a bug, to be looked into. Warning: an outside failure the server recovered from. Info: start, stop, login, logout. Debug: per-message detail, off by default.
- A log line carries who and where as metadata: account, character or unit, process or map, message name and number, and before login the connection's peer address. No password, session key or other secret.

## Memory

- Keep a busy process's live data small; leave data another process owns with that process.
- Data many processes read and nobody changes while running goes in a persistent term, written once at start: replacing one makes every process scan its heap. Its key is a start argument. Each game table is one term, a tuple of its rows indexed by id: a read costs about 76 ns with 12 readers, against 715 ns from ETS, which copies the whole row (issue #32).
- Find nearby units and players by spatial index (grid cells), on rare paths too.
- Players and connections keep waiting messages off the heap.
- Send a process what it needs: an id, not a record.
