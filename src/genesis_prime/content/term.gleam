//// The persistent terms the content tables are kept in once loaded: one term for
//// each table and world, written once at start and never replaced, read by the
//// maps and creatures of the world and never queried from the database during
//// play (genesis_prime/content).
////
//// - **The key is the table store's** (genesis_prime/table/loader/store `Key`):
////   the server's terms are stored under `server_key`, and a test makes its own
////   with `new_key`, so two loads never share terms, as the client's tables do.
//// - **Why it is its own module.** The tables' store keeps its put and get private
////   and tied to the tables' names, and gleam_erlang has no persistent term. Each
////   external here has the exact type of what is stored under the name it is read
////   by: a table's module (`genesis_prime/content/spawn`) writes and reads its own
////   value type and no other module touches its name.
//// - **A term is written once.** Replacing a persistent term makes every process
////   scan its heap, so `put` is for the load, before any map runs.
//// - **A missing term crashes the reader.** The load puts a term for every id a
////   reader can ask for, so a missing one is a bug, never an empty world.

import genesis_prime/table/loader/store.{type Key}
import gleam/erlang/atom.{type Atom}

/// A table's term for one id (a world) under a key.
type Name {
  Name(table: String, id: Int)
}

/// Writes the value of the table's id under the key.
pub fn put(
  key key: Key,
  table table: String,
  id id: Int,
  value value: value,
) -> Nil {
  let _ok = persistent_term_put(#(key, Name(table:, id:)), value)
  Nil
}

/// The value written under the key for the table's id; the caller crashes when
/// none was written.
pub fn get(key key: Key, table table: String, id id: Int) -> value {
  persistent_term_get(#(key, Name(table:, id:)))
}

/// OTP's `persistent_term:put/2`, which returns the atom `ok`.
@external(erlang, "persistent_term", "put")
fn persistent_term_put(key: #(Key, Name), value: value) -> Atom

/// OTP's `persistent_term:get/1`.
@external(erlang, "persistent_term", "get")
fn persistent_term_get(key: #(Key, Name)) -> value
