//// The persistent terms the content tables are kept in once loaded: one term for
//// each table and world, written once at start and never replaced, read by the
//// maps and creatures of the world and never queried from the database during
//// play (genesis_prime/content).
////
//// - **The key is given at start.** The server's terms are stored under
////   `server_key`; a test makes its own with `new_key`, so two loads never share
////   terms (as the client's tables do: genesis_prime/table/loader/store).
//// - **Why it is its own module.** The tables' store keeps its put, get and erase
////   private and tied to the tables' names, and gleam_erlang has no persistent
////   term. Each external here has the exact type of what is stored under the
////   name it is read by: a table's module (`genesis_prime/content/spawn`) writes
////   and reads its own value type and no other module touches its name.
//// - **A term is written once.** Replacing a persistent term makes every process
////   scan its heap, so `put` is for the load, before any map runs.

import gleam/erlang/atom.{type Atom}
import gleam/erlang/reference.{type Reference}

/// What a load's terms are stored under.
pub opaque type Key {
  /// The server's own key, the same in every run.
  ServerKey
  /// A key made for one load.
  LoadKey(Reference)
}

/// The server's key.
pub fn server_key() -> Key {
  ServerKey
}

/// A key no other load has.
pub fn new_key() -> Key {
  LoadKey(reference.new())
}

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

/// The value written under the key for the table's id, or `fallback` when none
/// was written: a world with no rows has no term.
pub fn get(
  key key: Key,
  table table: String,
  id id: Int,
  fallback fallback: value,
) -> value {
  persistent_term_get(#(key, Name(table:, id:)), fallback)
}

/// OTP's `persistent_term:put/2`, which returns the atom `ok`.
@external(erlang, "persistent_term", "put")
fn persistent_term_put(key: #(Key, Name), value: value) -> Atom

/// OTP's `persistent_term:get/2`.
@external(erlang, "persistent_term", "get")
fn persistent_term_get(key: #(Key, Name), default: value) -> value
