//// A test function run in a fresh node, where no module is loaded but what
//// the call itself loads, as when a test runs alone.

/// Why the function did not return in the fresh node.
pub type NotReturned {
  /// It raised, or the node ended; `raised` is the error as text.
  NotReturned(raised: String)
}

/// Runs `module.function()` in a fresh node and stops the test unless it
/// returns there, within 50 seconds.
pub fn must_return(module module: String, function function: String) -> Nil {
  assert run(module:, function:, timeout_ms: 50_000) == Ok(Nil)
    as { function <> " returns in a fresh node, with nothing loaded before it" }
}

/// Runs `function` in a fresh node and stops the test unless it returns there,
/// within 50 seconds. The function is one of the test's own module, which the
/// node loads when it calls it.
pub fn must_return_function(function: fn() -> Nil) -> Nil {
  assert run_function(function:, timeout_ms: 50_000) == Ok(Nil)
    as "the function returns in a fresh node, with nothing loaded before it"
}

@external(erlang, "fresh_node_ffi", "run_function")
fn run_function(
  function function: fn() -> Nil,
  timeout_ms timeout_ms: Int,
) -> Result(Nil, NotReturned)

/// Runs `module.function()` in a fresh node: `Ok(Nil)` when it returns.
@external(erlang, "fresh_node_ffi", "run")
pub fn run(
  module module: String,
  function function: String,
  timeout_ms timeout_ms: Int,
) -> Result(Nil, NotReturned)
