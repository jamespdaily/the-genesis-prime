//// The client's game tables as extracted on this machine, for the tests that
//// read the real files. Where `GENESIS_NO_CLIENT=1` there are none and those
//// tests skip; anywhere else a missing table fails the test with the fix.

import database_support
import envoy
import genesis_prime/table
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import gleam/list
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
  let assert Ok(names) = store.table_files(folder())
    as {
      "the tables folder is missing: "
      <> folder()
      <> "; run python3.13 -I setup_check/extract_tables.py"
    }
  names
}

/// The server's own tables (`server_table.entries`), read once per test run
/// with the server's requirements and derivations, exactly as the server's start
/// reads them, and stored once for the run: the first caller reads them, every
/// later caller in any test process gets the same `Tables`, which a read or a
/// message does not copy. A failed load stops the caller, naming the table.
/// Never load the tables again for a test that reads the real files; a test of
/// the load itself reads its own on its heap.
pub fn shared() -> store.Tables {
  database_support.once("client_tables", fn() {
    case server_table.read(from: folder()) {
      Ok(tables) -> store.store_under(tables:)
      Error(error) ->
        panic as {
          "the server's tables did not load from the client's files: "
          <> store.describe(error)
        }
    }
  })
}

/// The server's tables (`shared`) and the content tables the server's start adds to them.
pub fn with_content_tables() -> store.Tables {
  case server_table.load_content_tables(over: shared(), from: folder()) {
    Ok(tables) -> tables
    Error(error) ->
      panic as {
        "the content tables did not load from the client's files: "
        <> store.describe(error)
      }
  }
}

/// Every one of the client's 384 tables, for the tests that read a table no rule
/// of the server reads, such as the measure of the client's tables: the server's
/// own (`shared`) and the other 348 tables beside them. The other tables are
/// stored once, apart from `shared`'s, and each caller joins the two handles
/// (`store.merge`, a list of keys, no table copied), so no table is held twice
/// in the literal area (the server's 36 take 306 MiB, and a second copy of them filled the area).
/// The first caller reads, every later caller in any test process gets the same
/// tables. The digest (`store.digest`) is `shared`'s, which is
/// of every table file of the folder, so it is the same for any read of it.
pub fn every_table() -> store.Tables {
  store.merge(tables: shared(), more: the_other_tables())
}

/// The digest (`store.digest`) of a read of `entries` alone from the client's
/// folder, taken from a read of its own that is dropped at once: the digest is of
/// the folder's files, so it is `shared`'s whatever entries are read.
pub fn digest_of_a_read_of(entries entries: List(store.Entry)) -> String {
  case store.read(from: folder(), entries:, requirements: [], derivations: []) {
    Ok(tables) -> store.digest(tables)
    Error(error) ->
      panic as { "the client's tables did not read: " <> store.describe(error) }
  }
}

fn the_other_tables() -> store.Tables {
  database_support.once("client_other_tables", fn() {
    let server_files = list.map(server_table.entries(), store.file)
    let others =
      list.filter(table.entries(), fn(entry) {
        !list.contains(server_files, store.file(entry))
      })
    case
      store.read(
        from: folder(),
        entries: others,
        requirements: [],
        derivations: [],
      )
    {
      Ok(tables) -> store.store_under(tables:)
      Error(error) ->
        panic as {
          "the client's 384 tables did not all load: " <> store.describe(error)
        }
    }
  })
}
