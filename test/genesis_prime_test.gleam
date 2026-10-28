import envoy
import unitest

/// Runs the tests. The tests tagged `serial` share a machine-wide resource (a
/// child node's epmd and ports), so they must not run beside each other: with
/// `GENESIS_TEST_SKIP_SERIAL=1` they are skipped, and `./check` runs them in a
/// second run of their own, one at a time (`gleam test -- --tag serial`).
pub fn main() -> Nil {
  let skipped = case envoy.get("GENESIS_TEST_SKIP_SERIAL") {
    Ok("1") -> ["serial"]
    _ -> []
  }
  unitest.run(
    unitest.Options(..unitest.default_options(), ignored_tags: skipped),
  )
}
