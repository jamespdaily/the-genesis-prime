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
- A map process owns every unit of its map, with a grid for each kind of unit. It hands each update, with its recipients, to one of a pool of senders, one per scheduler, chosen by the unit's id, so one unit's updates reach each player in order (measured on issue #28).
- The server runs one scheduler per core, the BEAM's default. A lower count needs a load run that weighs the CPU it saves, in absolute terms, against the headroom it loses (issue #29).
- The server runs as one node. Auth and game are each a subtree under the top supervisor; a fault that survives every restart stops the node, and the host restarts it (`test/one_node_test.gleam`).
- A map is keyed by its world and its instance. A rule picks the instance: open worlds share one, an instanced world has one per group.
- A process's messages are defined by its module, with the functions that send them.
- State is a record with one status field, not several flags. Settings and process names are start arguments, made once.
- A request carries a reply subject and a chosen deadline when the asker must not block. A late reply is expected and handled.
- When sending more than one message to a named process, look it up once and send to the subject or pid.
- No database work inside a busy process's handler or an actor's initialiser. Saves and lookups run in supervised workers with deadlines (the storing-data skill).
- Every process that can fall behind has a measured ceiling and a load test. A producer never outruns its consumer: batch, shed or look things up instead.
- Time comes from the monotonic clock and timed messages, never wall-clock time inside a rule. The monotonic clock can be negative, so 0 never means none.
- Rules are deterministic: they take the current time and the random state as inputs.

## Shells and rules

A process with state is a shell plus one rule. A recorded session replays through the rule alone, so every decision must be in it.

- The shell turns everything that reaches the process into the rule's inputs: socket reads, other processes' messages, a monitor's down, a late reply, a failed write, the server stopping. Each input carries the monotonic time and the system time, read once as the shell takes it.
- The shell carries out the rule's effects in order and decides nothing. It never branches on a message's content.
- Asking another process is an effect that ends the rule's step: the shell asks, waits up to the deadline and feeds back the outcome, which is the reply, not running, timed out or ended. Work the rule had not finished stays in its state.
- Watching a process and starting a timer are effects, named by role or id, never by a process id, monitor or subject.
- No type a rule takes or returns holds a function.
- A shell does only the work its message needs; it never preloads data a rule might read.
- Older modules that still mix the shell and the rule are fixed by their own rebuild cards. Other cards leave them as they are.

## Restarts and shutdown

- Each supervisor states its restart intensity, period and shutdown timeouts, chosen per level. Each process says what a restart rebuilds its state from.
- Cleanup that must happen (freeing a name, a map slot, a session) runs in a process that monitors the dying one.
- Shutdown is ordered: stop accepting, drain connections, flush saves, then stop. No hot code upgrades in production.
- Each kind of state names how much play a crash can lose.

## Connections

- Each connection has a packet size cap, a rate limit and socket flow control (active once or active N). The server has a connection cap. Each limit has a test.
- Atoms are made only from values the server wrote, never from client input, and `binary_to_term` reads only bytes the server wrote.

## Logging

- Log through Erlang's logger. Error: a bug, always looked into. Warning: an outside failure the server recovered from. Info: start, stop, login, logout. Debug: per-message detail, off by default.
- Every log line carries who and where as metadata: account, character or unit, process or map, message name and number, and before login the connection's peer address. Never a password, session key or other secret.

## Memory

- Keep a busy process's live data small; leave data another process owns with that process.
- Every busy process sets `max_heap_size`, kill on, at four times its measured peak heap rounded up to a power of two words: a collection needs up to about twice the sampled peak (issue #31). A process that holds packets also counts shared binaries; an ETS table that grows while running has a row cap kept by its owner.
- Data many processes read and nobody changes while running goes in a persistent term, written once at start and never replaced while running. Its key is a start argument. Each game table is one term, a tuple of its rows indexed by id: a read costs about 76 ns with 12 readers, against 715 ns from ETS, which copies the whole row (issue #32).
- Find nearby units and players by spatial index (grid cells), on every path, including rare ones.
- Players and connections keep waiting messages off the heap.
- Send a process only what it needs: an id, not a record.
