import envoy
import literal_area
import unitest

/// Runs the tests. The tests tagged `serial` share a machine-wide resource (a
/// child node's epmd and ports), so they must not run beside each other: with
/// `GENESIS_TEST_SKIP_SERIAL=1` they are skipped, and `./check` runs them in a
/// second run of their own, one at a time (`gleam test -- --tag serial`).
///
/// With `GENESIS_LITERAL_PEAK_FILE` set to a file, the run keeps the literal
/// allocator's highest carriers size in it (`literal_area`), which `./check`
/// reads when the run has ended.
pub fn main() -> Nil {
  case envoy.get("GENESIS_LITERAL_PEAK_FILE") {
    Ok(file) -> literal_area.record_peak(into: file)
    Error(Nil) -> Nil
  }
  let skipped = case envoy.get("GENESIS_TEST_SKIP_SERIAL") {
    Ok("1") -> ["serial"]
    _ -> []
  }
  unitest.run(
    unitest.Options(..unitest.default_options(), ignored_tags: skipped),
  )
}
