//// The hand-off rule, pure. Expected values come from the rule's own contract
//// in the doc comment of `genesis_prime/hand_off`, as approved on the login
//// processes card: a key works once, only within its lifetime, a second put
//// of a held key is refused, and the two kinds of key never match each other.
//// The times are monotonic milliseconds the test chooses.

import genesis_prime/hand_off.{
  type Answer, type Holder, type State, AlreadyHeld, GameToken, Holder, Kept,
  NoHolder, Put, SessionKey, Take, Taken,
}
import genesis_prime/login/guid
import genesis_prime/step.{Asked, CallerId, Effects, Input, Now, Reply}
import genesis_prime/store.{AccountId}
import owned_test

pub fn a_put_then_a_take_gives_the_holder_and_a_second_take_gives_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let key = SessionKey(a_guid(1))
  let #(state, answer) =
    ask(state: hand_off.new(Nil), at: 0, message: Put(key, anna(), 1000))
  assert answer == Kept as "a new key is kept"
  let #(state, answer) = ask(state: state, at: 10, message: Take(key))
  assert answer == Taken(anna()) as "the take gives the holder the put named"
  let #(_, answer) = ask(state: state, at: 20, message: Take(key))
  assert answer == NoHolder as "a key works once"
}

pub fn a_take_after_the_keys_lifetime_gives_nothing_and_the_expired_key_is_gone_after_any_input_test() -> Nil {
  use <- owned_test.run(5000)
  let key = GameToken(a_guid(1))
  let #(state, _) =
    ask(state: hand_off.new(Nil), at: 0, message: Put(key, anna(), 1000))
  assert hand_off.key_count(state) == 1 as "the key is held"
  // 1001 ms after the put, 1 ms past its lifetime, a take of another key: the
  // expired key goes though nobody asked for it.
  let #(swept, answer) =
    ask(state: state, at: 1001, message: Take(GameToken(a_guid(2))))
  assert answer == NoHolder as "no such key"
  assert hand_off.key_count(swept) == 0
    as "any input drops the keys whose lifetime has passed"
  let #(_, answer) = ask(state: state, at: 1001, message: Take(key))
  assert answer == NoHolder as "a key is gone after its lifetime"
}

pub fn a_put_of_a_key_already_held_is_refused_and_the_first_holder_is_kept_test() -> Nil {
  use <- owned_test.run(5000)
  let key = SessionKey(a_guid(1))
  let #(state, _) =
    ask(state: hand_off.new(Nil), at: 0, message: Put(key, anna(), 1000))
  let #(state, answer) =
    ask(state: state, at: 10, message: Put(key, ben(), 5000))
  assert answer == AlreadyHeld as "the key is held, by another holder"
  let #(state, answer) =
    ask(state: state, at: 20, message: Put(key, anna(), 5000))
  assert answer == AlreadyHeld as "the key is held, by the same holder"
  let #(_, answer) = ask(state: state, at: 30, message: Take(key))
  assert answer == Taken(anna()) as "the first holder is kept"
}

pub fn a_take_of_an_unknown_key_gives_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, answer) =
    ask(state: hand_off.new(Nil), at: 0, message: Take(SessionKey(a_guid(1))))
  assert answer == NoHolder as "nothing was ever put"
  let #(state, _) =
    ask(state: state, at: 10, message: Put(GameToken(a_guid(1)), anna(), 1000))
  let #(_, answer) =
    ask(state: state, at: 20, message: Take(SessionKey(a_guid(1))))
  assert answer == NoHolder
    as "a game token is never taken as a session key of the same GUID"
}

// ---- helpers ----

/// Gives the rule one ask at the time `at`, and the rule's answer.
fn ask(
  state state: State,
  at at: Int,
  message message: hand_off.Message,
) -> #(State, Answer) {
  let caller = CallerId(1)
  let #(state, step) =
    hand_off.step(
      state,
      Input(
        now: Now(monotonic_ms: at, filetime: 0),
        event: Asked(caller:, message:),
      ),
    )
  let assert Effects([Reply(caller: CallerId(1), answer:)]) = step
    as "an ask is answered once, to its caller"
  #(state, answer)
}

fn anna() -> Holder {
  Holder(
    account_id: AccountId(1),
    login_name: "anna",
    game_account_id: a_guid(0xA1),
  )
}

fn ben() -> Holder {
  Holder(
    account_id: AccountId(2),
    login_name: "ben",
    game_account_id: a_guid(0xB2),
  )
}

fn a_guid(seed: Int) -> guid.Guid {
  let assert Ok(guid) = guid.from_wire(<<seed:size(128)>>)
    as "sixteen bytes are a GUID"
  guid
}
