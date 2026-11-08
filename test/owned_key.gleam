//// Keys a test body makes for the content tables it writes
//// (`store.put_content`), so a body that ends with terms still stored under them
//// fails (`owned_test.run`). A content table written under a key stays in the
//// VM's literal area until it is erased, and the area holds every test's terms
//// and the client's tables at once, so a term no one erases takes room from
//// every later test. A test's game tables are not stored: they are a value on
//// the test's own heap (`store.read`, `store.edit`).
////
//// - **A key made here is remembered as the calling process's**, in its process
////   dictionary; `owned_test.run` asks the body's process, when the body ends,
////   how many terms are still stored under its keys.
//// - **Two kinds.** A key from `new_key` is erased by the test, and the body
////   fails if it ends with terms under it. A key from `new_fixture_key`
////   belongs to a fixture the test's processes read until the test ends, so
////   `owned_test.run` erases it then.
//// - **A shared value** that every test reads for the whole run
////   (`database_support.once`) is stored once and never erased; content terms
////   shared the same way use `new_shared_key`.
//// - **The limit:** a key made in a process the body started is that process's,
////   and the body is not asked about it.

import genesis_prime/table/loader/store
import gleam/erlang/process.{type Pid}

/// A new store key for a content table (`store.put_content`), made by the
/// calling process, whose body must erase the terms stored under it.
pub fn new_key() -> store.Key {
  own(store.new_key(), ErasedByTheTest)
}

/// A new store key for a fixture the test's processes read until it ends:
/// `owned_test.run` erases the terms stored under it when the body ends.
pub fn new_fixture_key() -> store.Key {
  own(store.new_key(), ErasedWithTheTest)
}

/// A new store key for terms every test shares for the whole run
/// (`database_support.once`): no process owns it and nothing erases it.
pub fn new_shared_key() -> store.Key {
  store.new_key()
}

type Kind {
  ErasedByTheTest
  ErasedWithTheTest
}

@external(erlang, "owned_key_ffi", "own")
fn own(key: store.Key, kind: Kind) -> store.Key

/// How many persistent terms are stored under the keys the process made to be
/// erased by its test.
@external(erlang, "owned_key_ffi", "left_behind")
pub fn left_behind(owner: Pid) -> Int

/// Erases every persistent term stored under the keys the process made, of
/// either kind.
@external(erlang, "owned_key_ffi", "erase_left")
pub fn erase_left(owner: Pid) -> Nil

/// How many persistent terms are stored under the key.
@external(erlang, "owned_key_ffi", "terms_under")
pub fn terms_under(key: store.Key) -> Int

/// Erases every persistent term stored under the key: the terms of a load and
/// the values of content tables written with `store.put_content`.
@external(erlang, "owned_key_ffi", "erase")
pub fn erase(key: store.Key) -> Nil
