import argv
import character_tables
import client_tables
import code_rule/repository
import envoy
import filepath
import fixture_tables
import gleam/bool
import gleam/list
import gleam/result
import gleam/string
import literal_area
import module_preload
import simplifile
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
/// The test tagged `real_start` (the real server's boot with a bot playing the
/// opening, most of a minute) is skipped the same way with
/// `GENESIS_TEST_SKIP_REAL_START=1`, and `./check` runs it in a run of its own
/// beside the other tests (`gleam test -- --tag real_start`).
/// The test tagged `client_rows` (the committed client rows against the client's
/// own tables) is skipped the same way with `GENESIS_TEST_SKIP_CLIENT_ROWS=1`, and
/// `./check` runs it in its client-suite part (`gleam test -- --tag client_rows`).
/// The tests tagged `dev_tool` (the developer tools' own tests: the coverage
/// measure, the load runs, the sitting bot, the recording and table readers) are
/// skipped the same way with `GENESIS_TEST_SKIP_DEV_TOOL=1`, which `./check` sets:
/// they guard no client outcome, so no merge waits for them. They run by hand
/// with `gleam test -- --tag dev_tool`; the coverage measure's own are also
/// tagged `coverage` (`gleam test -- --tag coverage`).
/// The test tagged `github` (the open issues a comment in `src` names, read from
/// GitHub) is skipped with `GENESIS_TEST_SKIP_GITHUB=1`, which CI's repeat job
/// sets because it reads the network, not the code under repeat.
///
/// A one-time build (`database_support.once`) never counts against a test's
/// deadline: `owned_test.run` stops the clock while its body is inside one, so
/// whichever test asks first does not pay for it. The client's spell plans are
/// built before the first test starts, and a full run does the same, before the
/// first test, for every module of the project and every other one-time build
/// that tests call, because that saves wall time: the builds run once, ahead of
/// tests that run side by side, instead of inside the first of them while the
/// rest of the suite takes the processors. Modules are loaded through one
/// process the first time anything calls them, which is not a one-time build,
/// so on a machine with more runnable work than cores the queue of first calls
/// ran past tests' 10 s deadlines (`module_preload`, about 0.8 s). The builds
/// are what the fixture's rows reach (`fixture_tables.reach`, about 3.4 s,
/// which reads every fixture table), the keys of the client's fact file
/// (`repository.fact_keys`, about 0.9 s), the repository's source tree
/// (`repository.sources`, about 0.2 s), the fixture's server tables
/// (`fixture_tables.shared`), the spell areas and server proxies built over
/// them, the content tables, the Virtual Battle Beast the load builds from the
/// rows (`spawn_support.loaded_beast`), and, where the client's files are on the
/// machine, the client's tables (`client_tables.shared`, about 2.7 s, and
/// `client_tables.every_table`, about 1.6 s more). A run of chosen tests
/// (`--test`, `--tag`) leaves them to the tests that need them: those runs hold
/// none or few of them, and run beside other runs, and the world-data run's
/// literal area is 60% of its region, which the modules' literals would
/// push toward the limit.
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
      module_preload.load_project()
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
      test_directory: chosen_test_directory(argv.load().arguments)
        |> result.unwrap(unitest.default_options().test_directory),
      ignored_tags: list.append(
        skipped_when_set("GENESIS_TEST_SKIP_SERIAL", tag: "serial"),
        list.flatten([
          skipped_when_set("GENESIS_TEST_SKIP_WORLD_DATA", tag: "world_data"),
          skipped_when_set("GENESIS_TEST_SKIP_REAL_START", tag: "real_start"),
          skipped_when_set("GENESIS_TEST_SKIP_CLIENT_ROWS", tag: "client_rows"),
          skipped_when_set("GENESIS_TEST_SKIP_DEV_TOOL", tag: "dev_tool"),
          skipped_when_set("GENESIS_TEST_SKIP_GITHUB", tag: "github"),
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

/// The folder unitest reads its tests from when the run names a test file
/// (`test/x_test.gleam` or `test/x_test.gleam:LINE`, with no `--test` or `--tag`).
/// unitest parses every file under its test folder before it applies the file
/// name, which takes about 10 s for the whole suite, so the folder is a new one
/// under `build/chosen_tests` holding only a symlink to the named file, at the
/// same path below `test` (the folder ends in `test`, so the module name and the
/// file name unitest matches stay the same). unitest takes one file name; the
/// first one is used. Any other arguments give `Error(Nil)`, and the run reads
/// the whole `test` folder.
fn chosen_test_directory(arguments: List(String)) -> Result(String, Nil) {
  use <- bool.guard(when: runs_chosen_tests(arguments), return: Error(Nil))
  let files =
    list.map(arguments, fn(argument) {
      string.split_once(argument, ":")
      |> result.map(fn(parts) { parts.0 })
      |> result.unwrap(argument)
    })
  use path <- result.try(
    list.find(files, fn(file) {
      string.starts_with(file, "test/") && string.ends_with(file, ".gleam")
    }),
  )
  use <- bool.guard(
    when: simplifile.is_file(path) != Ok(True),
    return: Error(Nil),
  )
  use current <- result.try(
    simplifile.current_directory() |> result.replace_error(Nil),
  )
  let directory =
    "build/chosen_tests/"
    <> string.replace(string.drop_end(path, 6), each: "/", with: "__")
    <> "/test"
  let link = directory <> string.drop_start(path, string.length("test"))
  use _ <- result.try(
    simplifile.create_directory_all(filepath.directory_name(link))
    |> result.replace_error(Nil),
  )
  case simplifile.create_symlink(to: current <> "/" <> path, from: link) {
    Ok(Nil) | Error(simplifile.Eexist) -> Ok(directory)
    Error(_) -> Error(Nil)
  }
}

fn skipped_when_set(variable: String, tag tag: String) -> List(String) {
  case envoy.get(variable) {
    Ok("1") -> [tag]
    _ -> []
  }
}
