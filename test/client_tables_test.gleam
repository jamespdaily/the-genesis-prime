//// The shared load of the client's tables: every test in a run that needs the
//// real tables gets the one load, so parallel tests never hold several copies
//// of the 384 tables in persistent terms at once.

import client_tables
import environment
import genesis_prime/table
import genesis_prime/table/character_creation
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/game_formula
import genesis_prime/table/loader/store
import genesis_prime/table/reward_property_premium_modifier
import genesis_prime/table/world
import genesis_prime/table/xp_per_level
import gleam/erlang/process
import gleam/list
import owned_test
import unitest

fn client_present() -> Bool {
  environment.get("GENESIS_NO_CLIENT") != Ok("1")
}

const callers = 4

pub fn callers_in_different_processes_at_once_get_the_same_load_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_present())
  let replies = process.new_subject()
  list.each(list.repeat(Nil, callers), fn(_) {
    process.spawn(fn() { process.send(replies, client_tables.shared()) })
  })
  let loads =
    list.map(list.repeat(Nil, callers), fn(_) {
      let assert Ok(tables) = process.receive(replies, within: 600_000)
        as "a caller of the shared load did not answer"
      tables
    })
  let assert [first, ..rest] = loads
  assert list.all(rest, fn(other) { other == first })
    as "one load per run: every caller holds the same Tables, so no caller loaded its own"
  assert client_tables.shared() == first
    as "a caller after the others gets the same load too"
}

pub fn the_shared_load_holds_every_one_of_the_clients_384_tables_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_present())
  let entries = table.entries()
  assert list.length(entries) == 384
    as "game_tables.ClientData: 384 game tables in ClientData"
  let tables = client_tables.shared()
  // Reading a table's ids crashes when its term was never stored.
  list.each(entries, fn(entry) {
    let _ids = store.ids(entry, tables)
    Nil
  })
}

pub fn the_shared_load_holds_rows_of_the_tables_the_tests_that_moved_to_it_read_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_present())
  let tables = client_tables.shared()
  // The tables the game server and the character tests read (test/game_server.gleam).
  let read = [
    character_creation.entry(),
    character_customization_label.entry(),
    customization_parameter.entry(),
    customization_parameter_map.entry(),
    game_formula.entry(),
    reward_property_premium_modifier.entry(),
    world.entry(),
    xp_per_level.entry(),
  ]
  list.each(read, fn(entry) {
    assert store.ids(entry, tables) != []
      as { store.file(entry) <> ".tbl: the client's table has rows" }
  })
}
