//// A hand-off holds one-time keys that carry a login from one connection to
//// the next: the game token the STS login issues and the auth login redeems
//// in 0x592, and the session key the auth login issues and the game server
//// redeems in 0x58F (opcode.0x592, opcode.0x58f). A key is 16 random bytes
//// from the operating system's strong source, kept with what it stands for
//// until it is redeemed once or its expiry passes. A restart empties the
//// hand-off: a login in flight fails and the client logs in again.
////
//// The process owns its keys; every other process asks it by message. It
//// reads the monotonic clock the settings give it.

import gleam/erlang/process.{type Name}
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
  Issue(held: held, reply: process.Subject(BitArray))
  Redeem(key: BitArray, reply: process.Subject(Result(held, Refusal)))
}

/// Why a key is refused.
pub type Refusal {
  /// No hand-off holds this key: it was never issued, was redeemed already,
  /// or a restart emptied the hand-off.
  Unknown
  /// The key was issued, and its expiry has passed.
  Expired
}

/// The monotonic clock in milliseconds, the default for `Settings.clock`
/// (`erlang:monotonic_time/1`).
pub fn monotonic_milliseconds() -> Int {
  todo as "the monotonic clock"
}

/// The hand-off as a child of a supervisor: restarted whenever it ends.
pub fn supervised(
  settings settings: Settings(held),
) -> supervision.ChildSpecification(process.Subject(Message(held))) {
  todo as "the hand-off's child specification"
}

/// Issues a new key for `held`, and drops the keys already expired.
pub fn issue(name name: Name(Message(held)), held held: held) -> BitArray {
  todo as "issue a key"
}

/// Redeems a key once: what it was issued for, or why it is refused.
pub fn redeem(
  name name: Name(Message(held)),
  key key: BitArray,
) -> Result(held, Refusal) {
  todo as "redeem a key"
}
