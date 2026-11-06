//// Keys a test body makes for the persistent terms of its loads, so a body that
//// ends with terms still stored under them fails (`owned_test.run`). A load or a
//// content table written under a key stays in the VM's literal area until it is
//// erased, and the area holds every test's terms and the client's tables at
//// once, so a term no one erases takes room from every later test.
////
//// - **A key made here is remembered as the calling process's**, in its process
////   dictionary; `owned_test.run` asks the body's process, when the body ends,
////   how many terms are still stored under its keys.
//// - **Two kinds.** A key from `new` or `new_key` is erased by the test, and the
////   body fails if it ends with terms under it. A key from `new_fixture_key`
////   belongs to a fixture the test's processes read until the test ends, so
////   `owned_test.run` erases it then.
//// - **A shared load** that every test reads for the whole run
////   (`database_support.once`) is made with `reference.new()`, or with
////   `new_shared_key` for content terms, and is never erased.
//// - **The limit:** a key made in a process the body started is that process's,
////   and the body is not asked about it.
//// - **A key waits for room.** Every key made here first waits for the literal
////   area to be released (`literal_area.wait_until_released`) and, when the
////   process holds no load, for the loads held to be fewer than
////   `loads_held_limit`: a planted load is 6 to 23 MB (its tables are tuples
////   as long as their highest id), so the loads of twelve tests at once are
////   most of 100 MB beside the client's tables. A process that holds a load
////   never waits for another, and a creator of a shared load
////   (`database_support.once`) never waits, so no wait is for a process that is
////   itself waiting.

import genesis_prime/table/loader/store
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference.{type Reference}

/// A new reference for a load under it (`store.load(under:)`), made by the
/// calling process, whose body must erase the terms stored under it.
@external(erlang, "owned_key_ffi", "new")
pub fn new() -> Reference

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

/// How many loads the tests hold now: the keys made through this module that
/// have a term stored under them.
@external(erlang, "owned_key_ffi", "loads_held")
pub fn loads_held() -> Int

/// The most loads that are held when a process holding none makes a key (the
/// bytes of a planted load, 6 to 23 MB, are why: see the module's doc).
@external(erlang, "owned_key_ffi", "loads_held_limit")
pub fn loads_held_limit() -> Int

/// How many processes wait now for the loads held to fall below the limit.
@external(erlang, "owned_key_ffi", "waiting_for_room")
pub fn waiting_for_room() -> Int
