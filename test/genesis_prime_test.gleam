import envoy
import gleam/list
import literal_area
import unitest

/// Runs the tests. The tests tagged `serial` share a machine-wide resource (a
/// child node's epmd and ports), so they must not run beside each other: with
/// `GENESIS_TEST_SKIP_SERIAL=1` they are skipped, and `./check` runs them in a
/// second run of their own, one at a time (`gleam test -- --tag serial`). The
/// test tagged `world_data` (the whole world database, about a minute) is skipped
/// the same way with `GENESIS_TEST_SKIP_WORLD_DATA=1`, and `./check` runs it in a
/// run of its own beside the other tests (`gleam test -- --tag world_data`).
///
/// With `GENESIS_LITERAL_PEAK_FILE` set to a file, the run keeps the literal
/// allocator's highest carriers size in it (`literal_area`), which `./check`
/// reads when the run has ended.
pub fn main() -> Nil {
  case envoy.get("GENESIS_LITERAL_PEAK_FILE") {
    Ok(file) -> literal_area.record_peak(into: file)
    Error(Nil) -> Nil
  }
  unitest.run(
    unitest.Options(
      ..unitest.default_options(),
      ignored_tags: list.append(
        skipped_when_set("GENESIS_TEST_SKIP_SERIAL", tag: "serial"),
        skipped_when_set("GENESIS_TEST_SKIP_WORLD_DATA", tag: "world_data"),
      ),
    ),
  )
}

fn skipped_when_set(variable: String, tag tag: String) -> List(String) {
  case envoy.get(variable) {
    Ok("1") -> [tag]
    _ -> []
  }
}
