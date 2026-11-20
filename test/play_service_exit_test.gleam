//// The exit status of the play service's scripts when a value they need is
//// missing (`dev/play_service/lib.sh`'s `load_environment` and `load_config`),
//// run under `/bin/bash` (3.2 on a Mac, which launchd runs). Under 3.2 a
//// `${x:?word}`, or a `.` of a missing file, ends a script that sets an EXIT
//// trap with status 0, because the trap already sees `$?` as 0; bash 5, and a
//// script with no trap, end with 1. A failed update must be seen as failed, so
//// every row must end non-zero.

import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import owned_test
import play_service_support.{type Scene} as support
import simplifile

/// The three values `load_environment` requires, as env.sh sets them.
const environment_values = [
  #("GENESIS_PLAY_ADDRESS", "192.0.2.1"),
  #("GENESIS_PLAY_ACCOUNT", "planted"),
  #("GENESIS_PLAY_PGPASSWORD", "planted"),
]

/// The two values `load_config` requires, as config.sh sets them.
const config_values = [
  #("remote", "'planted'"),
  #("repository", "planted/planted"),
]

/// A shell file that sets every value but `missing`: `export` lines for env.sh,
/// plain assignments for config.sh.
fn setting_all_but(
  values values: List(#(String, String)),
  missing missing: String,
  prefix prefix: String,
) -> String {
  values
  |> list.filter(fn(pair) { pair.0 != missing })
  |> list.map(fn(pair) { prefix <> pair.0 <> "=" <> pair.1 <> "\n" })
  |> string.concat
}

/// Plants a complete env.sh and config.sh, then leaves `missing` out of the one
/// that holds it. A name no file holds leaves both complete.
fn plant_missing(scene scene: Scene, missing missing: String) -> Nil {
  support.plant_home_file(
    scene:,
    name: "env.sh",
    text: setting_all_but(
      values: environment_values,
      missing:,
      prefix: "export ",
    ),
  )
  support.plant_home_file(
    scene:,
    name: "play-service/config.sh",
    text: setting_all_but(values: config_values, missing:, prefix: ""),
  )
}

fn log_of(scene: Scene) -> String {
  result.unwrap(simplifile.read(scene.home <> "/play-service.log"), "")
}

type Row {
  /// One value left out of the file that holds it.
  Unset(name: String)
  /// config.sh is not there at all.
  NoConfigFile
}

/// Every way a required value can be missing, each planted by `plant_row`.
fn missing_rows() -> List(Row) {
  list.flatten([
    list.map(environment_values, fn(pair) { Unset(pair.0) }),
    list.map(config_values, fn(pair) { Unset(pair.0) }),
    [NoConfigFile],
  ])
}

/// Plants the row's missing value and gives the row's label and the word the
/// log line names it by.
fn plant_row(scene scene: Scene, row row: Row) -> #(String, String) {
  case row {
    Unset(name) -> {
      plant_missing(scene:, missing: name)
      #(name, name)
    }
    NoConfigFile -> {
      plant_missing(scene:, missing: "")
      let assert Ok(Nil) =
        simplifile.delete(scene.home <> "/play-service/config.sh")
      #("no config.sh", "config.sh")
    }
  }
}

fn log_lines(scene: Scene) -> List(String) {
  log_of(scene) |> string.split("\n") |> list.filter(fn(line) { line != "" })
}

pub fn a_missing_environment_value_ends_update_sh_non_zero_under_bash_3_2_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(missing_rows(), fn(row) {
    use scene <- support.with_scene
    let #(label, says) = plant_row(scene:, row:)
    let ran =
      support.run_script(
        scene:,
        script: "dev/play_service/update.sh",
        extra: [],
      )
    assert ran.status != 0 as { label <> ": ends well: " <> ran.output }
    assert string.contains(log_of(scene), says)
      as { label <> ": the log names it, it holds " <> log_of(scene) }
    assert support.calls(scene) == []
      as { label <> ": a tool was called, so a step ran on" }
  })
}

pub fn a_refusal_the_next_run_repeats_is_written_once_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(missing_rows(), fn(row) {
    use scene <- support.with_scene
    let #(label, _) = plant_row(scene:, row:)
    let first =
      support.run_script(
        scene:,
        script: "dev/play_service/update.sh",
        extra: [],
      )
    let second =
      support.run_script(
        scene:,
        script: "dev/play_service/update.sh",
        extra: [],
      )
    assert first.status != 0 && second.status != 0
      as { label <> ": a run ends well" }
    assert list.length(log_lines(scene)) == 1
      as { label <> ": two runs wrote " <> log_of(scene) }
    assert second.output == ""
      as { label <> ": the repeat printed " <> second.output }
  })
}

pub fn a_stale_stand_with_an_incomplete_config_leaves_the_stand_line_written_once_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(config_values, fn(pair) {
    use scene <- support.with_scene
    plant_missing(scene:, missing: pair.0)
    support.plant_live_lock(
      scene:,
      record: Some(support.owner_record(
        kind: "session",
        folder: "planted",
        pid: support.ended_pid(),
        started: "planted",
      )),
    )
    support.make_old(path: support.live_lock_path(scene) <> "/owner")
    list.each([1, 2, 3], fn(_) {
      let ran =
        support.run_script(
          scene:,
          script: "dev/play_service/update.sh",
          extra: [],
        )
      assert ran.status == 0 as { pair.0 <> ": a held lock ends well" }
    })
    let lines = log_lines(scene)
    assert list.length(lines) == 1
      as { pair.0 <> ": three runs wrote " <> log_of(scene) }
    assert string.contains(log_of(scene), "a live session holds")
      as {
        pair.0 <> ": the one line is the lock's, it holds " <> log_of(scene)
      }
  })
}

/// The play scripts that set an EXIT trap and call a loader of lib.sh, found by
/// reading the folder, each with whether it calls `load_config`.
fn trapped_loading_scripts() -> List(#(String, Bool)) {
  let folder = "dev/play_service"
  let assert Ok(names) = simplifile.read_directory(folder)
  names
  |> list.filter(string.ends_with(_, ".sh"))
  |> list.sort(string.compare)
  |> list.filter_map(fn(name) {
    let assert Ok(text) = simplifile.read(folder <> "/" <> name)
    let lines = string.split(text, "\n") |> list.map(string.trim)
    let sets_trap =
      list.any(lines, fn(line) {
        string.starts_with(line, "trap ") && string.ends_with(line, " EXIT")
      })
    let loads_environment = list.contains(lines, "load_environment")
    let loads_config = list.contains(lines, "load_config")
    case sets_trap && { loads_environment || loads_config } {
      True -> Ok(#(folder <> "/" <> name, loads_config))
      False -> Error(Nil)
    }
  })
}

pub fn every_play_script_with_an_exit_trap_ends_non_zero_when_a_required_value_is_missing_test() -> Nil {
  use <- owned_test.run(60_000)
  let scripts = trapped_loading_scripts()
  assert scripts != [] as "the folder holds a script that traps EXIT and loads"
  list.each(scripts, fn(script) {
    let #(path, loads_config) = script
    let missing = case loads_config {
      True -> [
        #("GENESIS_PLAY_ADDRESS", "an environment"),
        #("remote", "a config"),
      ]
      False -> [#("GENESIS_PLAY_ADDRESS", "an environment")]
    }
    list.each(missing, fn(row) {
      use scene <- support.with_scene
      plant_missing(scene:, missing: row.0)
      let ran = support.run_script(scene:, script: path, extra: [])
      assert ran.status != 0
        as {
          path <> " with " <> row.1 <> " value unset ends well: " <> ran.output
        }
    })
  })
}
