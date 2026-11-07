//// A test body that ends with persistent terms stored under the keys it made
//// fails (`owned_test.run`), so no test takes room in the literal area for the
//// rest of the run.

import ask_support
import event_wait
import genesis_prime/table/loader/store
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import owned_key
import owned_test
import unitest

/// Starts a process that makes a key, writes one content term under it and
/// stays alive until the process that started it ends, however it ends, so it
/// holds no place among the loads past its test; gives the process and the key.
fn owner_with_a_term() -> #(Pid, store.Key) {
  let reply = process.new_subject()
  let starter = process.self()
  let owner =
    process.spawn_unlinked(fn() {
      let key = owned_key.unlimited(owned_key.new_key)
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      process.send(reply, key)
      let _down =
        process.new_selector()
        |> process.select_specific_monitor(process.monitor(starter), fn(down) {
          down
        })
        |> process.selector_receive_forever
      Nil
    })
  let assert Ok(key) = process.receive(reply, within: 5000)
    as "the owner made its key"
  #(owner, key)
}

pub fn a_term_stored_under_a_key_a_process_made_is_counted_as_left_behind_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(owner, key) = owner_with_a_term()
  assert owned_key.left_behind(owner) == 1
    as "one content term was written under the owner's key"
  owned_key.erase_left(owner)
  assert owned_key.terms_under(key) == 0
    as "erasing what the owner left removes its term"
  assert owned_key.left_behind(owner) == 0
    as "nothing is left once it is erased"
  process.kill(owner)
}

pub fn an_owner_ends_when_the_body_that_started_it_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let started = process.new_subject()
  let body =
    process.spawn_unlinked(fn() {
      let #(owner, _key) = owner_with_a_term()
      process.send(started, owner)
      process.sleep_forever()
    })
  let assert Ok(owner) = process.receive(started, within: 5000)
    as "the body started its owner"
  process.kill(body)
  event_wait.until("the owner ended with the body that started it", fn() {
    !process.is_alive(owner)
  })
}

pub fn a_term_under_a_key_no_process_made_through_owned_key_is_not_counted_test() -> Nil {
  use <- owned_test.run(10_000)
  let key = store.new_key()
  store.put_content(key:, table: "Planted", id: 1, value: "a value")
  assert owned_key.left_behind(process.self()) == 0
    as "the key was not made through owned_key, so no body is asked about it"
  assert owned_key.terms_under(key) == 1
  owned_key.erase(key)
  assert owned_key.terms_under(key) == 0
}

/// Runs a body of `owned_test.run` in a process of its own and gives how it
/// ended: whether that process crashed.
fn crashes(body: fn() -> Nil) -> Bool {
  crashes_within(10_000, body)
}

fn crashes_within(timeout_ms: Int, body: fn() -> Nil) -> Bool {
  let monitor =
    process.spawn_unlinked(fn() { owned_test.run(timeout_ms, body) })
    |> process.monitor
  let assert Ok(down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 10_000)
    as "the test process ended"
  case down.reason {
    process.Normal -> False
    process.Killed | process.Abnormal(_) -> True
  }
}

pub fn a_body_that_ends_with_terms_under_its_keys_fails_and_its_terms_are_erased_test() -> Nil {
  use <- owned_test.run(10_000)
  let reply = process.new_subject()
  let failed =
    crashes(fn() {
      let key = owned_key.new_key()
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      process.send(reply, key)
    })
  assert failed as "the body left a term behind"
  let assert Ok(key) = process.receive(reply, within: 5000)
    as "the body made its key"
  assert owned_key.terms_under(key) == 0
    as "the failed test's term was erased so the tests after it do not carry it"
}

pub fn a_body_that_ends_with_terms_under_a_fixture_key_passes_and_its_terms_are_erased_test() -> Nil {
  use <- owned_test.run(10_000)
  let reply = process.new_subject()
  let failed =
    crashes(fn() {
      let key = owned_key.new_fixture_key()
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      process.send(reply, key)
    })
  assert !failed as "a fixture key is erased by the test run, not by the body"
  let assert Ok(key) = process.receive(reply, within: 5000)
    as "the body made its key"
  assert owned_key.terms_under(key) == 0
    as "the terms of a fixture key are erased when the body ends"
}

pub fn a_body_that_erases_the_terms_under_its_keys_passes_test() -> Nil {
  use <- owned_test.run(10_000)
  let failed =
    crashes(fn() {
      let key = owned_key.new_key()
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      owned_key.erase(key)
    })
  assert !failed as "the body erased what it wrote"
}

pub fn a_body_that_crashes_after_putting_terms_under_a_key_has_them_erased_test() -> Nil {
  use <- owned_test.run(10_000)
  let reply = process.new_subject()
  let failed =
    crashes(fn() {
      let key = owned_key.new_fixture_key()
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      process.send(reply, key)
      panic as "the planted crash of the body"
    })
  assert failed as "a body that panics fails its test"
  let assert Ok(key) = process.receive(reply, within: 5000)
    as "the body made its key"
  assert owned_key.terms_under(key) == 0
    as "the body died before its terms were counted, and they were erased all the same"
}

pub fn a_body_that_runs_past_its_deadline_has_its_terms_erased_test() -> Nil {
  use <- owned_test.run(10_000)
  let reply = process.new_subject()
  // The deadline is what is under test: the body puts its term in microseconds
  // and then waits for ever, so only the deadline ends it.
  let failed =
    crashes_within(300, fn() {
      let key = owned_key.new_key()
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      process.send(reply, key)
      process.sleep_forever()
    })
  assert failed as "a body that never ends fails its test at the deadline"
  let assert Ok(key) = process.receive(reply, within: 5000)
    as "the body made its key"
  assert owned_key.terms_under(key) == 0
    as "the body was ended before its terms were erased, so it put nothing after"
}

/// What a holder is asked to do.
type HolderMessage {
  MakeAnotherKey(reply: Subject(Nil))
  Stop
}

/// A process that holds a place among the loads, linked to the test body, so it
/// ends with it however the body ends.
type Holder {
  Holder(pid: Pid, messages: Subject(HolderMessage))
}

/// Starts a process that makes a key, which takes a place among the loads, and
/// then makes a second key whenever it is asked, telling the asker, until it is
/// told to stop. Gives it once its first key is made.
fn start_holder() -> Holder {
  let started = process.new_subject()
  let pid =
    process.spawn(fn() {
      let _key = owned_key.new_key()
      let messages = process.new_subject()
      process.send(started, messages)
      hold(messages)
    })
  let assert Ok(messages) =
    process.receive(started, within: ask_support.event_wait_ms)
    as "the holder made its key"
  Holder(pid:, messages:)
}

fn hold(messages: Subject(HolderMessage)) -> Nil {
  case process.receive_forever(messages) {
    MakeAnotherKey(reply) -> {
      let _second = owned_key.new_key()
      process.send(reply, Nil)
      hold(messages)
    }
    Stop -> Nil
  }
}

/// Starts as many holders as the limit of loads allows.
fn holders_up_to_the_limit() -> List(Holder) {
  list.repeat(Nil, owned_key.loads_held_limit())
  |> list.map(fn(_) { start_holder() })
}

pub fn a_process_holding_no_place_waits_while_the_limit_of_places_is_held_test() -> Nil {
  use <- owned_test.run(30_000)
  // Other tests' places count too, so only the serial run, which has the VM to
  // itself, holds exactly the limit.
  use <- unitest.tag("serial")
  let holders = holders_up_to_the_limit()
  assert owned_key.loads_held() == owned_key.loads_held_limit()
    as "the holders hold the limit"
  let made = process.new_subject()
  let _waiter =
    process.spawn(fn() {
      let key = owned_key.new_key()
      process.send(made, key)
    })
  event_wait.until("the waiter is waiting for room", fn() {
    owned_key.waiting_for_room() == 1
  })
  assert process.receive(made, within: 0) == Error(Nil)
    as "a key is not handed out while the limit of places is held"
  let assert [first, ..] = holders
  process.send(first.messages, Stop)
  let assert Ok(_key) = process.receive(made, within: ask_support.event_wait_ms)
    as "the waiter gets its key once a holder ends"
  assert owned_key.waiting_for_room() == 0
    as "the waiter no longer waits once it has its key"
}

pub fn a_process_that_holds_a_place_is_not_made_to_wait_for_another_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let holders = holders_up_to_the_limit()
  let assert [first, ..] = holders
  let second = process.new_subject()
  process.send(first.messages, MakeAnotherKey(second))
  let assert Ok(Nil) =
    process.receive(second, within: ask_support.event_wait_ms)
    as "a holder makes a second key at once, though the limit of places is held"
  assert owned_key.waiting_for_room() == 0 as "no process waited for room"
}

pub fn a_killed_process_that_waited_for_a_place_is_no_longer_counted_as_waiting_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let _holders = holders_up_to_the_limit()
  let waiter =
    process.spawn_unlinked(fn() {
      let _key = owned_key.new_key()
      Nil
    })
  event_wait.until("the waiter is waiting for room", fn() {
    owned_key.waiting_for_room() == 1
  })
  process.kill(waiter)
  assert owned_key.waiting_for_room() == 0
    as "a process killed inside the wait leaves no count behind"
}

pub fn a_deadline_leaves_out_the_time_a_body_waited_for_room_test() -> Nil {
  // The inner body does no work; it waits for a place for longer than its
  // deadline of 100 ms, so it ends well only if the wait is added to the deadline.
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let holders = holders_up_to_the_limit()
  let body_pid = process.new_subject()
  let outcome = process.new_subject()
  let _worker =
    process.spawn(fn() {
      owned_test.run(100, fn() {
        process.send(body_pid, process.self())
        let _key = owned_key.new_key()
        Nil
      })
      process.send(outcome, Nil)
    })
  let assert Ok(body) =
    process.receive(body_pid, within: ask_support.event_wait_ms)
    as "the body started"
  event_wait.until("the body has waited twice its deadline", fn() {
    owned_key.waited_ms(of: body) > 200
  })
  let assert [first, ..] = holders
  process.send(first.messages, Stop)
  let assert Ok(Nil) =
    process.receive(outcome, within: ask_support.event_wait_ms)
    as "the body got its key and returned, though it waited twice its deadline"
  Nil
}
