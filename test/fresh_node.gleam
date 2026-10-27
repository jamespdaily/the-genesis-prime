//// A test function run in a fresh node, where no module is loaded but what
//// the call itself loads, as when a test runs alone.

/// Why the function did not return in the fresh node.
pub type NotReturned {
  /// It raised, or the node ended; `raised` is the error as text.
  NotReturned(raised: String)
}

/// Runs `module.function()` in a fresh node: `Ok(Nil)` when it returns.
@external(erlang, "fresh_node_ffi", "run")
pub fn run(
  module module: String,
  function function: String,
  timeout_ms timeout_ms: Int,
) -> Result(Nil, NotReturned)
