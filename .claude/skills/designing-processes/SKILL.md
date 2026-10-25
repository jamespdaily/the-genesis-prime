---
name: designing-processes
description: How to design processes in the-genesis-prime on the BEAM - when a process exists, who owns state, pure rules and handlers, supervision trees, restarts, cleanup and ordered shutdown, saves, requests with deadlines, moves between two owners, limits on the client's connection, memory and heap size, persistent terms, spatial lookups, time, logging and telemetry. Use before changing or adding any process, actor, service, supervisor or message, or when a step's shape includes a supervision change, even if the request only says "add a handler".
---

# Designing processes

The server is designed for the BEAM from the first line. Processes, messages, supervision and the runtime's own tools are the building blocks. Nothing is designed as threads, locks, shared objects or a game loop and then translated.

The process topology, where services run, the heap ceiling, where read-only data lives and how purity is checked are starting defaults, decided in Milestone 1 on their own issues. Read the decision on its issue before building on it.

## The shape of a step

**Draw the supervision tree before the code:** which processes exist, what each owns, how each restarts, and what players see when each dies. It is part of a step's reviewed shape (OTP design principles: supervision trees). One unguarded process could drop every player.

## Processes

- **A process exists only for state, concurrency or failure isolation.** Pure code stays in plain functions (Elixir's process anti-patterns, "Code organization by process"; `~/Projects/reference/elixir-docs-1.20.4/doc/elixir/process-anti-patterns.md`).
- **One process owns each piece of state; others ask it by message.** Peers never call each other synchronously, as peer calls deadlock. A timed call up the supervision tree, to a registry or a worker, is normal OTP.
- **Game logic is pure rules:** state and input in, new state and effects out. The owning process carries out the effects, in the order returned (the sans-io pattern). The code rule test holds it.
- **Every process starts under a supervisor,** never a bare `process.spawn`. The code rule test holds it.
- **A process's messages are defined by its module, with the functions that send them.** Other modules call those functions and never build the messages (Elixir's process anti-patterns, "Scattered process interfaces").
- **State is a record with one status field, not several flags.** Settings and process names are start arguments, made once at start. Process names are atoms, and atoms are never freed, so never make one per player.
- **Send a process only what it needs:** an id, not a record. A message is copied into the receiver.
- **No database work inside a busy process's handler, and none in an actor's initialiser.** gleam_otp's starter waits for the initialiser, and a player once blocked on a query on every message during an outage. Saves and lookups run in supervised workers with deadlines. The code rule test holds the initialiser part.
- **A request carries a reply subject and a deadline when the asker must not block,** and a late reply is expected and handled. `process.call` panics when no reply comes in time or the callee exits, and an unselected late reply is dropped with a warning. For a deadline that returns an error, make a subject with `process.new_subject`, send it in the request, and wait with `process.receive`.
- **A move between two owners** (a trade, mail with an item, an auction, group loot) **has one source of truth:** a database transaction or a coordinator. Two processes each holding one side cannot agree on their own.

## Handlers

A handler is the function a process runs for each message. It routes, and decides nothing about the game.

```
message ─▶ match ─▶ call the rule (pure, may fail safely) ─▶ carry out effects, in order ─▶ next state
```

- **A handler matches the message, calls one rule, and carries out its effects in order.** Game decisions live in rules, never in the handler or its effect runner. Game master commands were once decided in an effect runner, outside every rule.
- **An unexpected error is caught only around the pure rule call, and only an `error`, never an exit or a throw.** The state from before the message is kept and the error logged. After a few failures in a row the process crashes, and its supervisor rebuilds its state from storage. Keeping state is safe only before any effect has run, and only while the state itself is sound.
- **A handler does only the work its message needs.** It never preloads data a rule might read; the rule asks for it. One player rebuilt a whole crowd-control table on every message, save ticks included.
- **The selector covers every message the process can receive; anything else is logged.** gleam_otp drops a message its selector misses, with only a warning. Select raw socket tuples with `select_record` and down messages with `select_monitors`.

## Restarts and shutdown

- **Each supervisor states its restart intensity, period and shutdown timeouts, and each process says what a restart rebuilds its state from** (OTP design principles: restart strategy).
- **Cleanup that must happen** (freeing a name, a map slot, a session) **runs in a process that monitors the dying one.** A process's own terminate code runs only when it traps exits and its shutdown allows, and never on a kill.
- **Shutdown is ordered:** stop accepting, drain connections, flush saves, then stop. A stop that skips saves loses play. The server ships as an OTP release (`gleam export erlang-shipment`), with runtime settings from the environment. Hot code upgrades in production are off.
- **Saves are versioned,** so an older save never overwrites a newer one, **and idempotent,** so a retry is safe. Each kind of state names how much play a crash can lose.

## The client's connection

- **Each connection has a packet size cap, a rate limit and socket flow control** (active once or active N). **The server has a connection cap, and a decode failure ends the connection.** A client can otherwise grow a buffer or a mailbox without bound.
- **Players and connections keep waiting messages off the heap** (Erlang efficiency guide, `message_queue_data`).

## Memory and load

- **Keep a busy process's live data small.** Leave data another process owns with that process, not as a second copy. Above 128 K words (1 MB), every collection of the process goes to a dirty scheduler. On OTP 29.1.2 a collector bug then let a map grow to 25–29 GB from about 9 M words of state; at 0.2 M words it stayed near 60 MB. The exact ceiling is a starting default.
- **Data many processes read and nobody changes while running goes in a persistent term,** written once at start: a few large terms, never many small ones, never replaced while running. An update or erase runs a collection over every process (`persistent_term` docs). Its key is a start argument, so a test can load its own. A term is never copied into a heap, so a state can hold it at no cost. Literals and persistent terms share 1 GB of reserved space (`+MIscs`).
- **Find nearby units and players by spatial index (grid cells), on every path, including rare ones.** Pairing each move with every player took a map to 100% busy and a queue of 50,056 messages at 400 players; with cells it was 38–47% busy.
- **Take what each check needs in one pass** over the units in sight; never filter a result again with a second lookup each. A move went from 55 to 47 µs at 400 players when the sight checks joined one fold.
- **Every process that can fall behind has a measured ceiling and a load test.** A producer never outruns its consumer: batch, shed or look things up instead.

## Time and determinism

- **Time comes from the monotonic clock and timed messages,** never wall-clock time inside a rule (ERTS "Time and Time Correction"). The monotonic clock starts far below zero, so 0 can never mean "none": use an `Option`, or the time now.
- **Rules are deterministic:** they take the current time and the random state as inputs, so recorded inputs replay exactly.
- **A timer is a start argument,** so a test sets it to a few milliseconds or sends the timer's message itself.

## Logging and telemetry

- **Each log level means one thing.** Error: a bug, always looked into. Warning: an outside failure the server recovered from. Info: start, stop, login, logout. Debug: per-message detail, off by default.
- **Every log line carries who and where as logger metadata:** account, character or unit, process or map, message name and number. Never a password, session key or other secret.
- **Always-on telemetry:** scheduler use, run queue, memory, process count, and the longest mailboxes with their owners, exported continuously. The launcher shows it. A problem seen only by ad hoc inspection is found late.

## Reviewing a process change

| Rule | Check |
|---|---|
| The tree is drawn | The step's shape shows each new process, its owner, its restart and what players see when it dies |
| One owner, no peer calls | Every new `process.call` goes up the tree or to a worker, never to a peer |
| Selector covers everything | Every message type the process can be sent appears in its selector |
| Handler decides nothing | Every new branch in a handler or effect runner that reads game state |
| Small heap, one pass | Every new `dict.keys`, `dict.values`, `dict.to_list`, `dict.fold` or `set.to_list` over a whole map or player collection, in a function a frequent message reaches |
| Deadlines | Every new request names its deadline and what a late reply does |
| Cleanup by monitor | Every new name, slot or session a process claims is freed by a monitoring process |
