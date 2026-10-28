//// The client's game tables as extracted on this machine, for the tests that
//// read the real files. Where `GENESIS_NO_CLIENT=1` there are none and those
//// tests skip; anywhere else a missing table fails the test with the fix.

import database_support
import envoy
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/reference
import gleam/list
import gleam/string
import simplifile

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

/// Every one of the client's 384 tables, loaded once per test run: the first
/// caller loads them, every later caller in any test process gets the same
/// `Tables`. A failed load stops the caller, naming the table. Never unload
/// them, and never load the tables again for a test that reads the real files;
/// a test of the load itself loads its own and unloads it.
pub fn shared() -> store.Tables {
  database_support.once("client_tables", fn() {
    case table.load(under: reference.new(), from: folder()) {
      Ok(tables) -> tables
      Error(error) ->
        panic as {
          "the client's 384 tables did not all load: " <> store.describe(error)
        }
    }
  })
}
