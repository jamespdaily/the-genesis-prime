//// The shared loads of the client's tables: every test in a run that needs the
//// real tables gets the one load, so parallel tests never hold several copies
//// of them in persistent terms at once. `shared` is the server's own tables,
//// as its start loads them, and `every_table` all 384 of the client's.

import client_tables
import genesis_prime/table
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import gleam/erlang/process
import gleam/list
import owned_test
import unitest

const callers = 4

pub fn callers_in_different_processes_at_once_get_the_same_load_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
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

pub fn the_every_table_load_holds_every_one_of_the_clients_384_tables_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let entries = table.entries()
  assert list.length(entries) == 384
    as "game_tables.ClientData: 384 game tables in ClientData"
  let tables = client_tables.every_table()
  // Reading a table's ids crashes when its term was never stored.
  list.each(entries, fn(entry) {
    let _ids = store.ids(entry, tables)
    Nil
  })
}

pub fn the_shared_load_holds_rows_of_every_table_the_servers_list_names_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(server_table.entries(), fn(entry) {
    assert store.ids(entry, tables) != []
      as { store.file(entry) <> ".tbl: the client's table has rows" }
  })
}
