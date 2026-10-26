//// A hand-off holds one-time keys that carry a login from one connection to
//// the next: the game token the STS login issues and the auth login redeems
//// in 0x592, and the session key the auth login issues and the game server
//// redeems in 0x58F (opcode.0x592, opcode.0x58f). A key is 16 random bytes
//// from the operating system's strong source, kept with what it stands for
//// until it is redeemed once or its expiry passes. A restart empties the
//// hand-off: a login in flight fails and the client logs in again.
////
//// The process owns its keys; every other process asks it by message. It
//// reads the monotonic clock the settings give it, in whole milliseconds from
//// an arbitrary start.

import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// What a hand-off starts with. `name` is the name the hand-off registers and
/// its users find it by, made once by whoever starts the tree.
/// `expiry_milliseconds` is how long a key stays valid after it is issued;
/// `clock` reads the monotonic clock in milliseconds.
pub type Settings(held) {
  Settings(
    name: Name(Message(held)),
    expiry_milliseconds: Int,
    clock: fn() -> Int,
  )
}

/// The messages a hand-off receives.
pub opaque type Message(held) {
  Issue(held: held, reply: Subject(BitArray))
  Redeem(key: BitArray, reply: Subject(Result(held, Refusal)))
}

/// Why a key is refused.
pub type Refusal {
  /// No hand-off holds this key: it was never issued, was redeemed already,
  /// or a restart emptied the hand-off.
  Unknown
  /// The key was issued, and its expiry has passed.
  Expired
}

/// How long the top of the tree waits for a hand-off to stop before it is
/// killed, in milliseconds. It holds nothing that must be saved.
const shutdown_ms = 1000

/// How long a caller waits for the hand-off to answer, in milliseconds. A
/// hand-off answers from memory, so an answer later than this means the
/// process is gone, which ends the caller.
const call_ms = 5000

/// The keys held: when each was issued, and what it stands for.
type State(held) {
  State(settings: Settings(held), keys: Dict(BitArray, #(Int, held)))
}

/// The hand-off as a child of a supervisor: restarted whenever it ends.
pub fn supervised(
  settings settings: Settings(held),
) -> supervision.ChildSpecification(Subject(Message(held))) {
  supervision.worker(fn() { start(settings) })
  |> supervision.timeout(ms: shutdown_ms)
}

fn start(
  settings: Settings(held),
) -> Result(actor.Started(Subject(Message(held))), actor.StartError) {
  actor.new(State(settings:, keys: dict.new()))
  |> actor.on_message(handle)
  |> actor.named(settings.name)
  |> actor.start
}

fn handle(
  state: State(held),
  message: Message(held),
) -> actor.Next(State(held), Message(held)) {
  let now = state.settings.clock()
  case message {
    Issue(held:, reply:) -> {
      let live =
        dict.filter(state.keys, fn(_, issued) {
          !has_expired(settings: state.settings, now:, issued_at: issued.0)
        })
      let key = crypto.strong_random_bytes(16)
      process.send(reply, key)
      actor.continue(State(..state, keys: dict.insert(live, key, #(now, held))))
    }
    Redeem(key:, reply:) -> {
      let answer = case dict.get(state.keys, key) {
        Error(Nil) -> Error(Unknown)
        Ok(#(issued_at, held)) ->
          case has_expired(settings: state.settings, now:, issued_at:) {
            True -> Error(Expired)
            False -> Ok(held)
          }
      }
      process.send(reply, answer)
      actor.continue(State(..state, keys: dict.delete(state.keys, key)))
    }
  }
}

/// A key is valid for `expiry_milliseconds` after it is issued.
fn has_expired(
  settings settings: Settings(held),
  now now: Int,
  issued_at issued_at: Int,
) -> Bool {
  now - issued_at >= settings.expiry_milliseconds
}

/// Issues a new key for `held`, and drops the keys already expired.
pub fn issue(name name: Name(Message(held)), held held: held) -> BitArray {
  actor.call(process.named_subject(name), waiting: call_ms, sending: fn(reply) {
    Issue(held:, reply:)
  })
}

/// Redeems a key once: what it was issued for, or why it is refused.
pub fn redeem(
  name name: Name(Message(held)),
  key key: BitArray,
) -> Result(held, Refusal) {
  actor.call(process.named_subject(name), waiting: call_ms, sending: fn(reply) {
    Redeem(key:, reply:)
  })
}
