//// What one accepted connection takes from outside its socket: its seed, the
//// time of each input it takes, and the timers it starts. A
//// listener hands each connection its own `Script` as the shell takes the
//// connection's socket (`Scripts`), so a replay can give every connection of a
//// recorded session the seed, the times and the timers of its own recording.
////
//// ```
//// the shell, after the handshake:   scripts() ─▶ Issued(ordinal, script)
//// each input the shell takes:       script.clock(Input) ─▶ the input's Now, once
////                                   script.node_monotonic_ms(Now) ─▶ the node's own time
//// StartTimer(id, ms):               script.schedule(its subject, id, reference, ms)
////                                     ─▶ Cancel
//// ```
////
//// - **The server's script** (`operating_system`): the seed is drawn from
////   the operating system's strong random source, the clock is the node's
////   (`runtime.now`), the node's own time for an input is that `Now`'s own
////   monotonic reading (the one read serves both, so an ask's deadline the
////   rule writes and the deadline the shell counts are one number) and a timer is the operating system's (`process.send_after`).
////   Its ordinal is a number that grows with each call, so the order of
////   accepts is recorded and never inferred from times.
//// - **A replay's script** (genesis_prime/wire_replay): the seed is the
////   recording's, the clock gives the recording's `Now`s as it is told the input
////   each call serves (the shell's `wire_recording.Input`), and a timer fires
////   when the replay client reaches its line. The shell takes each recorded read as one input: the script
////   tells it how many bytes the next recorded read holds (`next_read`), and the
////   shell keeps reading until it holds that many, so a socket that delivers
////   one recorded read in two parts gives the rule one input. As a safety net,
////   a read takes the `Now` of the recorded read line in which its last byte
////   falls; any other input takes the next recorded input, and one of another
////   kind than the recording's next is an ordering failure of the replay.
//// - **A replay's node time** is a read of the node's own monotonic clock, since
////   the recording's monotonic times are of another run.
//// - **A script is used once.** `Scripts` is called once for each accepted
////   connection. A listener that restarts keeps its `Scripts` (the value is
////   made before the tree, not by the listener), so a connection accepted after
////   the restart is handed the next script, never one already used.
//// - **One call of the clock for each input the shell takes**, told the input,
////   made as the shell takes the input, and none for a message the shell drops. The
////   number of calls is how many inputs the shell has taken, which the replay
////   client reads to know where each connection's shell is.

import genesis_prime/seed.{type Seed}
import genesis_prime/step.{type Now, type TimerId}
import genesis_prime/step/runtime
import genesis_prime/wire_recording.{type Input}
import gleam/erlang/process.{type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/option.{type Option, None}

/// Where a connection reads the time its next input carries, told the input it
/// serves as the wire recording keeps it (the server's clock ignores it; a
/// replay's matches it with a recorded input of the same kind). Each call is one
/// input: the shell makes it as it takes the input and at no other time.
pub type Clock =
  fn(Input) -> Now

/// Ends a timer that was started: a timeout already sent is discarded by the
/// shell when it arrives, since no timer holds its reference.
pub type Cancel =
  fn() -> Nil

/// A timer's firing, as the shell's own subject receives it: which timer, and
/// the reference of the start it came from, which tells it from a stale firing
/// of an earlier timer of the same id.
pub type Elapsed {
  Elapsed(timer: TimerId, reference: Reference)
}

/// Starts a timer: after the given milliseconds, `Elapsed(timer, reference)` is
/// sent to the subject. The server's scheduler is the operating system's timer;
/// a replay's holds the timer until its client reaches the timer's line.
pub type Scheduler =
  fn(Subject(Elapsed), TimerId, Reference, Int) -> Cancel

/// How many bytes the next `Read` input holds, when the script fixes it: the
/// server's script returns `None` and the shell takes what has arrived; a
/// replay's returns the byte count of the next recorded read line not yet taken,
/// and the shell reads on until it holds exactly that many bytes before it takes
/// the input. It only looks: the clock's call for the read advances the script.
pub type NextRead =
  fn() -> Option(Int)

/// The node's own monotonic time, in milliseconds, at the input whose `Now` the
/// clock has just given: what the shell counts an ask's wait from. The server's
/// is that `Now`'s own monotonic reading, so no second read of the clock can
/// differ from it; a replay's reads the node's clock, since a recording's
/// monotonic times are of another run.
pub type NodeClock =
  fn(Now) -> Int

/// What one connection takes from outside its socket.
pub type Script {
  Script(
    seed: Seed,
    clock: Clock,
    node_monotonic_ms: NodeClock,
    schedule: Scheduler,
    next_read: NextRead,
  )
}

/// A connection's script with its accept ordinal: the place of the connection
/// in the order its server accepted connections, which only grows, so a
/// recording names the order and a replay hands out scripts by it.
pub type Issued {
  Issued(ordinal: Int, script: Script)
}

/// Hands out the script of the connection that has just been accepted, once
/// for each connection. `Error(Nil)` when it holds none: a replay whose
/// recording has no more connections. The shell then closes the connection
/// with a warning and takes no input.
pub type Scripts =
  fn() -> Result(Issued, Nil)

/// The server's own script: a seed from the operating system's random source,
/// the node's clock and the operating system's timers.
pub fn operating_system() -> Result(Issued, Nil) {
  Ok(Issued(
    ordinal: runtime.unique_id(),
    script: Script(
      seed: seed.from_system(),
      clock: fn(_taking) { runtime.now() },
      node_monotonic_ms: fn(now) { now.monotonic_ms },
      schedule: operating_system_timer,
      next_read: fn() { None },
    ),
  ))
}

fn operating_system_timer(
  subject subject: Subject(Elapsed),
  timer timer: TimerId,
  reference reference: Reference,
  after_ms after_ms: Int,
) -> Cancel {
  let started =
    process.send_after(subject, after_ms, Elapsed(timer:, reference:))
  fn() {
    let _cancelled = process.cancel_timer(started)
    Nil
  }
}
