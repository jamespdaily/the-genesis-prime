import argv
import character_tables
import client_tables
import code_rule/repository
import envoy
import fixture_tables
import gleam/bool
import gleam/list
import gleam/string
import literal_area
import spawn_support
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
/// build for the run is setup, so no test's deadline holds it. A full run builds
/// every other one-time build that tests call, before the first test, for the
/// same reason: whichever test asks first would otherwise wait for the build
/// inside its deadline, with the rest of the suite taking the processors. They
/// are what the fixture's rows reach (`fixture_tables.reach`, about 3.4 s, which
/// reads every fixture table), the keys of the client's fact file
/// (`repository.fact_keys`, about 0.9 s), the repository's source tree
/// (`repository.sources`, about 0.2 s), the fixture's server tables
/// (`fixture_tables.shared`), the spell areas and server proxies built over
/// them, the content tables, the Virtual Battle Beast the load builds from the
/// rows (`spawn_support.loaded_beast`), and, where the client's files are on the
/// machine, the client's tables (`client_tables.shared`, about 2.7 s, and
/// `client_tables.every_table`, about 1.6 s more). A run of chosen tests
/// (`--test`, `--tag`) leaves them to the tests that need them: those runs hold
/// none or few of them, and run beside other runs.
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
  case runs_chosen_tests(argv.load().arguments) {
    True -> Nil
    False -> {
      let _reach = fixture_tables.reach()
      let _fact_keys = repository.fact_keys()
      let _sources = repository.sources(under: ["src"])
      let _fixture = fixture_tables.shared()
      let _areas = spell_tables.fixture_areas()
      let _server_proxies = spell_tables.server_proxies()
      let _planted_plans = spell_tables.plans_with_server_proxies()
      let _content = character_tables.content_tables()
      let _beast = spawn_support.loaded_beast()
      warm_client_tables()
    }
  }
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

fn warm_client_tables() -> Nil {
  use <- bool.guard(when: !client_tables.present(), return: Nil)
  let _server_tables = client_tables.shared()
  let _every_table = client_tables.every_table()
  Nil
}

fn runs_chosen_tests(arguments: List(String)) -> Bool {
  list.any(arguments, fn(argument) {
    string.starts_with(argument, "--test")
    || string.starts_with(argument, "--tag")
  })
}

fn skipped_when_set(variable: String, tag tag: String) -> List(String) {
  case envoy.get(variable) {
    Ok("1") -> [tag]
    _ -> []
  }
}
