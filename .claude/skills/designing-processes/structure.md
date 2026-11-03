# Structure, restarts and shutdown

## Structure

- Isolated parts of the game get isolated processes.
- A short-lived job (one query, one task) runs as a supervised worker, such as a factory supervisor's temporary child; gleam_otp has no task module.
- Data one process writes and many read while the server runs goes in ETS owned by that process, read directly by the others: a spatial grid, a counter. Data nobody changes while running goes in a persistent term ([connections-logging-memory.md](connections-logging-memory.md)).
- Peers send to each other rather than call: two peers that wait on each other can deadlock. A timed call up the tree, to a registry or a worker, is normal.
- The server runs one scheduler per core, the BEAM's default. A lower count needs a load run that weighs the CPU it saves, in absolute terms, against the headroom it loses (issue #29).
- The server runs as one node. Auth and game are each a subtree under the top supervisor; a fault that survives every restart stops the node, and the host restarts it (issue #30).
- A map is keyed by its world and its instance. A rule picks the instance: open worlds share one, an instanced world has one per group.
- A process's messages are defined by its module, with the functions that send them.
- State is a record with one status field, not several flags. Settings and process names are start arguments, made once.
- A request carries a reply subject and a chosen deadline when the asker must not block. A late reply is expected and handled.
- When sending more than one message to a named process, look it up once and send to the subject or pid.
- Database work runs in supervised workers with deadlines, not inside a busy process's handler or an actor's initialiser (the storing-data skill).
- A process that can fall behind has a measured ceiling and a load test. Keep a producer from outrunning its consumer: batch, shed or look things up instead.
- Time comes from the monotonic clock and timed messages; a rule takes the time as an input and does not read the wall clock. The monotonic clock can be negative, so 0 does not mean none.
- Rules are deterministic: they take the current time and the random state as inputs.

## Restarts and shutdown

- Each supervisor's restart limit and each worker's shutdown time is chosen per level, not left to a library default (`test/code_rule/supervision_setting.gleam` checks it is stated). Each process says what a restart rebuilds its state from.
- Cleanup that has to happen (freeing a name, a map slot, a session) runs in a process that monitors the dying one, since the dying one may not get to run it.
- Shutdown is ordered: stop accepting, drain connections, flush saves, then stop. No hot code upgrades in production.
- Each kind of state names how much play a crash can lose.
