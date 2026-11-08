import envoy
import gleam/list
import literal_area
import spell_tables
import unitest

/// Runs the tests. The tests tagged `serial` share a machine-wide resource (a
/// child node's epmd and ports), so they must not run beside each other: with
/// `GENESIS_TEST_SKIP_SERIAL=1` they are skipped, and `./check` runs them in a
/// second run of their own, one at a time (`gleam test -- --tag serial`). The
/// test tagged `world_data` (the whole world database, about a minute) is skipped
/// the same way with `GENESIS_TEST_SKIP_WORLD_DATA=1`, and `./check` runs it in a
/// run of its own beside the other tests (`gleam test -- --tag world_data`).
/// The test tagged `client_rows` (the committed client rows against the client's
/// own tables) is skipped the same way with `GENESIS_TEST_SKIP_CLIENT_ROWS=1`, and
/// `./check` runs it in its client-suite part (`gleam test -- --tag client_rows`).
/// The tests tagged `dev_tool` (the developer tools' own tests: the coverage
/// measure, the load runs, the sitting bot, the recording and table readers) are
/// skipped the same way with `GENESIS_TEST_SKIP_DEV_TOOL=1`, which `./check` sets:
/// they guard no client outcome, so no merge waits for them. They run by hand
/// with `gleam test -- --tag dev_tool`; the coverage measure's own are also
/// tagged `coverage` (`gleam test -- --tag coverage`).
///
/// The client's spell plans are built before the first test starts: their one
/// build for the run is setup, so no test's deadline holds it.
///
/// With `GENESIS_LITERAL_PEAK_FILE` set to a file, the run keeps the literal
/// allocator's highest carriers size in it (`literal_area`), which `./check`
/// reads when the run has ended.
pub fn main() -> Nil {
  case envoy.get("GENESIS_LITERAL_PEAK_FILE") {
    Ok(file) -> literal_area.record_peak(into: file)
    Error(Nil) -> Nil
  }
  let _plans = spell_tables.fixture_plans()
  unitest.run(
    unitest.Options(
      ..unitest.default_options(),
      ignored_tags: list.append(
        skipped_when_set("GENESIS_TEST_SKIP_SERIAL", tag: "serial"),
        list.flatten([
          skipped_when_set("GENESIS_TEST_SKIP_WORLD_DATA", tag: "world_data"),
          skipped_when_set("GENESIS_TEST_SKIP_CLIENT_ROWS", tag: "client_rows"),
          skipped_when_set("GENESIS_TEST_SKIP_DEV_TOOL", tag: "dev_tool"),
        ]),
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
