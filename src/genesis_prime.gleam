//// Starts the server: it loads the client's game tables from the folder named
//// by GENESIS_TABLE_DIR, stopping at once with the reason when one does not
//// load, then starts the supervision tree and keeps the node alive. It serves
//// no client.

import envoy
import genesis_prime/server
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/io
import gleam/list

pub fn main() -> Nil {
  let folder = case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  let entries = table.entries()
  case
    store.load(under: reference.new(), from: folder, entries:, requirements: [])
  {
    Ok(_tables) -> Nil
    Error(error) -> panic as store.describe(error)
  }
  let assert Ok(_) = server.start() as "the supervision tree did not start"
  io.println(
    "the server loaded "
    <> int.to_string(list.length(entries))
    <> " game tables and serves no client",
  )
  process.sleep_forever()
}
