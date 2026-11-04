//// The client's game tables as extracted on this machine, for the tests that
//// read the real files. Where `GENESIS_NO_CLIENT=1` there are none and those
//// tests skip; anywhere else a missing table fails the test with the fix.

import database_support
import envoy
import genesis_prime/table
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import gleam/list
import gleam/string
import simplifile

/// Whether the client's files are on this machine: false only where
/// `GENESIS_NO_CLIENT=1`, which CI sets. A test whose point is the client's real
/// data begins with `use <- unitest.guard(client_tables.present())`.
pub fn present() -> Bool {
  envoy.get("GENESIS_NO_CLIENT") != Ok("1")
}

/// The folder `setup_check/extract_tables.py` fills: `GENESIS_TABLE_DIR`, else
/// `tables` under `GENESIS_HOME`, else under `~/.genesis-prime`.
pub fn folder() -> String {
  case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      case envoy.get("GENESIS_HOME") {
        Ok(home) -> home <> "/tables"
        Error(Nil) -> {
          let assert Ok(home) = envoy.get("HOME")
            as "neither GENESIS_TABLE_DIR, GENESIS_HOME nor HOME is set"
          home <> "/.genesis-prime/tables"
        }
      }
  }
}

/// The bytes of one extracted table file, by its file name without `.tbl`.
pub fn read(file: String) -> BitArray {
  let path = folder() <> "/" <> file <> ".tbl"
  let assert Ok(bytes) = simplifile.read_bits(path)
    as {
      "the client's table is missing or unreadable: "
      <> path
      <> "; run python3.13 -I setup_check/extract_tables.py"
    }
  bytes
}

/// The names of every extracted table file, without `.tbl`, in order.
pub fn files() -> List(String) {
  let assert Ok(names) = simplifile.read_directory(folder())
    as {
      "the tables folder is missing: "
      <> folder()
      <> "; run python3.13 -I setup_check/extract_tables.py"
    }
  names
  |> list.filter(string.ends_with(_, ".tbl"))
  |> list.map(string.remove_suffix(_, ".tbl"))
  |> list.sort(string.compare)
}

/// The server's own tables (`server_table.entries`), loaded once per test run
/// under the server's own key exactly as the server's start loads them: the
/// first caller loads them, every later caller in any test process gets the
/// same `Tables`, and the game rule's settings hold the tables under that key.
/// A failed load stops the caller,
/// naming the table. Never unload them, and never load the tables again for a
/// test that reads the real files; a test of the load itself loads its own
/// under a key of its own and unloads it.
pub fn shared() -> store.Tables {
  database_support.once("client_tables", fn() {
    case server_table.load(from: folder()) {
      Ok(tables) -> tables
      Error(error) ->
        panic as {
          "the server's tables did not load from the client's files: "
          <> store.describe(error)
        }
    }
  })
}

/// Every one of the client's 384 tables, for the tests that read a table no rule
/// of the server reads, such as the measure of the client's tables: the server's
/// own (`shared`) and the other tables loaded beside them under the same key, so
/// no table is held twice in the literal area (the server's 36 take 306 MiB, and
/// a second copy of them filled the area). The first caller loads, every later
/// caller in any test process gets the same `Tables`. Never unload them.
///
/// The value is the load of the other 348 tables only: its `terms` and its
/// `digest` (`store.digest`) cover those files, not the server's 36, whose are
/// `shared`'s. Reads by table key work for all 384, because both hold the
/// server's key (`store.server_key`), the key the server loads its content
/// tables under (`genesis_prime.load_content`): a load of those over either
/// value writes under the key both read.
pub fn every_table() -> store.Tables {
  database_support.once("client_every_table", fn() {
    let server_files = list.map(server_table.entries(), store.file)
    let others =
      list.filter(table.entries(), fn(entry) {
        !list.contains(server_files, store.file(entry))
      })
    case store.load_more(over: shared(), from: folder(), entries: others) {
      Ok(tables) -> tables
      Error(error) ->
        panic as {
          "the client's 384 tables did not all load: " <> store.describe(error)
        }
    }
  })
}
