//// A gate on the sends of a map to the connections of its players, for a test that
//// asks what a connection is sent when the map's sends are late. The gate is a process:
//// while it is open each send passes at once in the order it came, and while it is
//// closed each is kept in that order until the test opens it, which carries them all
//// out first. The test, not a time, decides how late: the maps' sends are held while the
//// creature goes on, and the test opens the gate when it has seen what it waits for
//// (`held`).
////
//// ```
//// map ── send(Connection, outgoing) ──▶ gate ── open: carried out now ─────────▶ connection
////                                         └─── closed: kept, in order ─ open(): carried out
//// ```

import ask_support
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor

/// A gate, open when made.
pub opaque type Gate {
  Gate(subject: Subject(Input))
}

type Input {
  Send(carry: fn() -> Nil)
  Close(reply: Subject(Nil))
  Open(reply: Subject(Nil))
  Held(reply: Subject(Int))
}

type State {
  State(closed: Bool, held: List(fn() -> Nil))
}

/// A gate that is open, with its own process, linked to the test's.
pub fn start() -> Gate {
  let assert Ok(started) =
    actor.new(State(closed: False, held: []))
    |> actor.on_message(handle)
    |> actor.start
    as "the gate started"
  Gate(subject: started.data)
}

/// Passes a send through the gate: carried out now by the gate's process when it is
/// open, kept when it is closed.
pub fn send(gate gate: Gate, carry carry: fn() -> Nil) -> Nil {
  process.send(gate.subject, Send(carry:))
}

/// Closes the gate: what is sent from now on is kept. Returns once the gate is closed.
pub fn close(gate gate: Gate) -> Nil {
  process.call(gate.subject, ask_support.beyond_the_test_ms, Close)
}

/// Opens the gate: the sends it kept are carried out, in the order they came, and
/// what is sent from now on passes at once. Returns once the kept sends are carried out.
pub fn open(gate gate: Gate) -> Nil {
  process.call(gate.subject, ask_support.beyond_the_test_ms, Open)
}

/// How many sends the gate keeps now.
pub fn held(gate gate: Gate) -> Int {
  process.call(gate.subject, ask_support.beyond_the_test_ms, Held)
}

fn handle(state: State, input: Input) -> actor.Next(State, Input) {
  case input {
    Send(carry:) ->
      case state.closed {
        True -> actor.continue(State(..state, held: [carry, ..state.held]))
        False -> {
          carry()
          actor.continue(state)
        }
      }
    Close(reply:) -> {
      process.send(reply, Nil)
      actor.continue(State(..state, closed: True))
    }
    Open(reply:) -> {
      list.each(list.reverse(state.held), fn(carry) { carry() })
      process.send(reply, Nil)
      actor.continue(State(closed: False, held: []))
    }
    Held(reply:) -> {
      process.send(reply, list.length(state.held))
      actor.continue(state)
    }
  }
}
