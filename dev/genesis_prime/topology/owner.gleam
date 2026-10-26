//// What a simulated player uses to act on a prototype, and what the harness
//// uses to watch it. Both prototypes hand out the same record, so one player
//// drives either.

import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/update.{type Delivery}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// A prototype's door. Every function sends a message and returns at once; a
/// player never waits for the owner.
pub type Owner {
  Owner(
    /// Joins a player's connection to its unit, as a player entering the map:
    /// the unit's id and the connection updates are sent to. The owner sends
    /// `Joined` on the connection once updates will reach it. A unit with no
    /// connection joined is told nothing.
    join: fn(Int, Subject(Delivery)) -> Nil,
    /// Moves a player's unit to a position: the unit's id, the position and
    /// the monotonic time in microseconds at which the move was sent.
    move: fn(Int, Position, Int) -> Nil,
    /// Makes a player's unit hit the nearest creature in visibility range,
    /// once: the unit's id and the time the attack was sent. The answer comes
    /// to the player's connection.
    attack_nearest_creature: fn(Int, Int) -> Nil,
    /// The processes that own units at this moment, whose message queues the
    /// harness samples. After a crash this is the rebuilt processes.
    owner_processes: fn() -> List(Pid),
    /// The owner processes that only carry out deliveries for another owner
    /// process and own no units: prototype C's senders, none for the others.
    /// Every other owner process is a map process, or for prototype A a
    /// unit's. After a crash this is the rebuilt processes.
    sender_processes: fn() -> List(Pid),
    /// Messages the owners have handled since the prototype started.
    messages_handled: fn() -> Int,
    /// Words of memory the owners hold for their units: process memory, and
    /// for the one-process-per-unit prototype the table's rows as well.
    memory_words: fn() -> Int,
    /// Stops the prototype and every process it started.
    stop: fn() -> Nil,
  )
}

/// Stops a supervisor the calling process started, and waits until it and
/// everything under it has stopped. Both prototypes' `stop` use it.
pub fn stop_supervisor(supervisor: Pid) -> Nil {
  let monitor = process.monitor(supervisor)
  process.send_exit(supervisor)
  let assert Ok(_down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 60_000)
    as "the prototype did not stop"
  Nil
}

/// A child specification that sends what its child started with to `subject`,
/// so the process that starts the supervisor can reach the child.
pub fn reporting(
  child child: ChildSpecification(data),
  subject subject: Subject(data),
) -> ChildSpecification(data) {
  supervision.ChildSpecification(..child, start: fn() {
    use started <- result.map(child.start())
    process.send(subject, started.data)
    started
  })
}
