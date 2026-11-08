//// A test body that ends with persistent terms stored under the keys it made
//// fails (`owned_test.run`), so no test takes room in the literal area for the
//// rest of the run.

import genesis_prime/table/loader/store
import gleam/erlang/process.{type Pid}
import owned_key
import owned_test

/// Starts a process that makes a key, writes one content term under it and
/// stays alive; gives the process and the key.
fn owner_with_a_term() -> #(Pid, store.Key) {
  let reply = process.new_subject()
  let owner =
    process.spawn_unlinked(fn() {
      let key = owned_key.new_key()
      store.put_content(key:, table: "Planted", id: 1, value: "a value")
      process.send(reply, key)
      process.sleep_forever()
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
