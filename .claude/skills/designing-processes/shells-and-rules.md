# Shells and rules

A process that decides anything the client or the game can observe is a shell plus one rule. OTP plumbing (supervisors, registries, worker factories) is not, and makes no such decision. The decisions are in the rule, so a test drives it with inputs alone, and a recorded session replays through the whole server. `test/code_rule/purity.gleam` checks that a rule module imports no process, OTP, database or logging module.

- A recording holds only what crossed the wire (`src/genesis_prime/wire_recording.gleam`), so a change to a rule's types replays as before. A replay that differs after a change meant to alter what the client receives is recorded again live. Editing a recording to match is a shortcut that makes a check pass.
- The shell turns everything that reaches the process into the rule's inputs: socket reads, other processes' messages, a monitor's down, a late reply, a failed write, the server stopping. Each input carries the monotonic time and the system time, read once as the shell takes it.
- The shell carries out the rule's effects in order and decides nothing: a branch on a message's content belongs in the rule.
- Asking another process is an effect that ends the rule's step: the shell asks, waits up to the deadline and feeds back the outcome, which is the reply, not running, timed out or ended. Work the rule had not finished stays in its state.
- Watching a process and starting a timer are effects, named by role or id, so the rule's types hold no process id, monitor or subject.
- A rule's input and output types hold no function, so a recording and a test can build and compare them.
- A shell does the work its message needs and no more: it does not preload data a rule might read.
