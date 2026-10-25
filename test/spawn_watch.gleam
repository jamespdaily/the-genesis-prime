//// Finds the processes a test started that no supervisor owns: the check
//// behind "every process is supervised". A test begins a watch, starts what it
//// tests, then asks which processes started since are outside a supervisor's
//// tree. The tree is read through the supervisor's own children list.

import gleam/erlang/process.{type Pid}

/// A running watch of the processes the calling process starts.
pub type Watch

/// Starts watching every process the caller starts, and every process those
/// start. The watch ends with the caller.
@external(erlang, "spawn_watch_ffi", "begin_watch")
pub fn begin() -> Watch

/// The processes started since the watch began that are still alive, are not
/// the caller and are not the supervisor or anything in its tree. The watch
/// ends with this call.
@external(erlang, "spawn_watch_ffi", "unsupervised")
pub fn unsupervised(watch: Watch, supervisor: Pid) -> List(Pid)

/// The supervisor and every process under it, found through the children of it
/// and of each supervisor child.
@external(erlang, "spawn_watch_ffi", "tree")
pub fn tree(supervisor: Pid) -> List(Pid)
