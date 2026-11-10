//// The modules of this project (its sources and its tests), which the VM loads
//// from disk one at a time, through one process (the code server), the first
//// time any process calls one.
////
//// - **Why the run loads them first:** a test's deadline starts when its body
////   starts, and every module its body calls for the first time waits in that
////   one process's queue. On a machine with more runnable work than cores, a
////   queue of first calls took over 10 s (measured: a run beside twelve busy
////   loops had 37 of its 41 timed-out tests blocked in a code server call, and
////   the code server inside a beam file read in 50 of 52 samples), so tests
////   that need nothing but the project's code ran past their deadline. Loaded
////   before the first test, a module costs no test anything.

/// Loads every module of the project that is not loaded yet, several at a time.
/// A module that cannot be loaded ends the run, since its tests could not use it.
@external(erlang, "module_preload_ffi", "load_project")
pub fn load_project() -> Nil
