//// The hand-off keys: one-time keys a client carries from one server to the
//// next. The STS login gives the client a game token, which it shows the auth
//// server in its login request (opcode.0x592); the auth server gives it a
//// session key, which it shows the game server (opcode.0x3db, opcode.0x58f).
//// The login rule that makes a key puts it here with who holds it; the rule
//// the client shows it to takes it. A key works once, and only within its
//// lifetime.
////
//// This is the rule of the hand-off service (genesis_prime/service/shell). Its
//// keys live only in the process: a restart loses them, and a client part-way
//// through a login is refused and logs in again.
////
//// Expired keys are dropped on every input, by the input's monotonic time, so
//// the service needs no timer.

import genesis_prime/login/guid.{type Guid}
import genesis_prime/step.{
  type Input, type Rule, type Step, Answered, AnsweredLate, Asked, Effects,
  Reply, Rule, Socket, Started, Stop, Stopping, TimerFired, WatchEnded, Woken,
}
import genesis_prime/store.{type AccountId}
import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/hand_off"

/// A one-time key. The two kinds never match each other, so a game token is
/// never taken as a session key.
pub type Key {
  /// What the STS login's RequestGameToken gives the client, as a GUID, and
  /// the client sends the auth server.
  GameToken(token: Guid)
  /// The 16 bytes the auth server's hand-off gives the client, as a GUID,
  /// and the client sends the game server.
  SessionKey(key: Guid)
}

/// Who a key was made for: the account, its login name, and its game account
/// id, the GUID the client shows as its UserId (opcode.0x592), so the auth
/// rule can check the UserId against the token's account.
pub type Holder {
  Holder(account_id: AccountId, login_name: String, game_account_id: Guid)
}

/// What another process asks the hand-off.
pub type Message {
  /// Keep `key` for `holder` until `lifetime_ms` after the time of this
  /// input.
  Put(key: Key, holder: Holder, lifetime_ms: Int)
  /// Give the key's holder and forget the key.
  Take(key: Key)
}

/// What the hand-off answers.
pub type Answer {
  /// The key is kept.
  Kept
  /// The key is already held, by another holder or the same one; the first
  /// is kept.
  AlreadyHeld
  /// The key's holder; the key is forgotten.
  Taken(holder: Holder)
  /// No live key matches: never put, already taken, or expired.
  NoHolder
}

/// The keys held, each with the monotonic time in milliseconds at which it
/// expires, and the earliest of those times, or `None` when no key is held.
/// An input before it has no key to drop, so it does not look at them; a key
/// taken leaves the earliest time as it was, which is early, never late.
pub opaque type State {
  State(keys: Dict(Key, #(Holder, Int)), next_expiry: Option(Int))
}

/// The rule as its service shell runs it.
pub fn rule() -> Rule(Nil, State, Message, Nil, Answer, Nil) {
  Rule(name: rule_name, settings: Nil, new:, step:)
}

/// The hand-off's first state: no keys.
pub fn new(_settings: Nil) -> State {
  State(keys: dict.new(), next_expiry: None)
}

/// One input in, the new state and what the shell must do out. `Asked` is
/// answered with `Reply`; `Stopping` stops; `Started` does nothing. An input
/// a service's shell never gives is a bug, and crashes the process.
pub fn step(
  state state: State,
  input input: Input(Message, Nil),
) -> #(State, Step(Answer, Nil)) {
  let now = input.now.monotonic_ms
  let state = drop_expired(state, now)
  case input.event {
    Started -> #(state, Effects([]))
    Stopping(..) -> #(state, Effects([Stop]))
    Asked(caller:, message:) -> {
      let #(state, answer) = answer(state:, now:, message:)
      #(state, Effects([Reply(caller, answer)]))
    }
    Socket(..)
    | Woken(..)
    | WatchEnded(..)
    | TimerFired(..)
    | Answered(..)
    | AnsweredLate(..) ->
      panic as "the hand-off takes Started, Asked and Stopping only; its shell gives no Socket, Woken, WatchEnded, TimerFired, Answered or AnsweredLate"
  }
}

/// How many keys the state holds. It exists so a test can see that an expired
/// key is dropped by any input, without a `Take` for that key.
pub fn key_count(state: State) -> Int {
  dict.size(state.keys)
}

/// A key lives until its expiry: at the expiry time it is gone.
fn drop_expired(state: State, now: Int) -> State {
  case state.next_expiry {
    Some(next_expiry) if now >= next_expiry -> {
      let keys = dict.filter(state.keys, fn(_key, kept) { kept.1 > now })
      let next_expiry = dict.fold(keys, None, earliest)
      State(keys:, next_expiry:)
    }
    Some(_) | None -> state
  }
}

fn earliest(
  earliest: Option(Int),
  _key: Key,
  kept: #(Holder, Int),
) -> Option(Int) {
  case earliest {
    Some(time) if time <= kept.1 -> earliest
    Some(_) | None -> Some(kept.1)
  }
}

fn answer(
  state state: State,
  now now: Int,
  message message: Message,
) -> #(State, Answer) {
  case message {
    Put(key:, holder:, lifetime_ms:) ->
      case dict.has_key(state.keys, key) {
        True -> #(state, AlreadyHeld)
        False -> {
          let expiry = now + lifetime_ms
          #(
            State(
              keys: dict.insert(state.keys, key, #(holder, expiry)),
              next_expiry: case state.next_expiry {
                Some(time) if time <= expiry -> state.next_expiry
                Some(_) | None -> Some(expiry)
              },
            ),
            Kept,
          )
        }
      }
    Take(key:) ->
      case dict.get(state.keys, key) {
        Ok(#(holder, _expiry)) -> #(
          State(..state, keys: dict.delete(state.keys, key)),
          Taken(holder:),
        )
        Error(Nil) -> #(state, NoHolder)
      }
  }
}
