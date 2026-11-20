//// What the updater does with its lock, the Podman machine and Postgres
//// (`dev/play_service/update.sh` and `lib.sh`), run against fake `podman` and
//// planted files (`play_service_support`). These pin the behaviour that
//// `state.sh` shares through `lib.sh`: the functions it reads were moved or
//// extracted from the updater, and each row here passed before that and must
//// pass after. Expected values are `update.sh`'s header (a lock whose owner is
//// gone is taken over, and one with no owner file stays held for a minute),
//// `machine_up`'s and `wait_for_postgres`'s own words in `lib.sh`.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import play_service_support.{type Scene, Answer} as support
import simplifile

/// The updater's log; empty when it wrote none.
fn log_of(scene: Scene) -> String {
  result.unwrap(simplifile.read(scene.home <> "/play-service.log"), "")
}

type Stand {
  /// The run stands down and the log holds the words.
  Stands(says: String)
  /// The run took the lock over and went on to `load_environment`.
  TakesOver
}

type UpdateRow {
  UpdateRow(
    name: String,
    plant: fn(Scene) -> Nil,
    outcome: fn(Scene) -> Stand,
    lock_remains: Bool,
  )
}

pub fn update_sh_still_decides_by_the_moved_lock_check_test() -> Nil {
  use <- owned_test.run(60_000)
  let alive = support.os_pid()
  let dead = support.ended_pid()
  let pid = fn(number) { int.to_string(number) }
  let rows = [
    UpdateRow(
      "a live session holds the live lock",
      fn(scene) {
        support.plant_live_lock(
          scene:,
          record: Some(support.owner_record(
            kind: "client",
            folder: "",
            pid: alive,
            started: support.started_text(alive),
          )),
        )
      },
      fn(scene) {
        Stands(
          "a live session holds " <> scene.home <> "/live.lock; nothing done",
        )
      },
      False,
    ),
    UpdateRow(
      "the service is held",
      support.plant_hold,
      fn(_) {
        Stands(
          "the service is held (stop.sh --hold; start.sh releases it); nothing done",
        )
      },
      False,
    ),
    UpdateRow(
      "the update lock's owner runs",
      fn(scene) { support.plant_update_lock(scene:, owner: Some(alive)) },
      fn(_) {
        Stands(
          "another update runs (process " <> pid(alive) <> "); nothing done",
        )
      },
      True,
    ),
    UpdateRow(
      "the update lock's owner is gone",
      fn(scene) { support.plant_update_lock(scene:, owner: Some(dead)) },
      fn(_) { TakesOver },
      False,
    ),
    UpdateRow(
      "no owner file under a minute",
      fn(scene) { support.plant_update_lock(scene:, owner: None) },
      fn(_) { Stands("another update runs (process ); nothing done") },
      True,
    ),
    UpdateRow(
      "no owner file over a minute",
      fn(scene) {
        support.plant_update_lock(scene:, owner: None)
        support.make_old(support.update_lock_path(scene))
      },
      fn(_) { TakesOver },
      False,
    ),
  ]
  list.each(rows, fn(row) {
    use scene <- support.with_scene
    row.plant(scene)
    let ran =
      support.run_script(
        scene:,
        script: "dev/play_service/update.sh",
        extra: [],
      )
    case row.outcome(scene) {
      Stands(says:) -> {
        assert ran.status == 0 as { row.name <> ": ends well: " <> ran.output }
        assert string.contains(log_of(scene), says)
          as {
            row.name
            <> ": the log says "
            <> says
            <> ", it holds "
            <> log_of(scene)
          }
      }
      TakesOver -> {
        assert string.contains(ran.output, "GENESIS_PLAY_ADDRESS")
          as { row.name <> ": ends at load_environment: " <> ran.output }
      }
    }
    let assert Ok(lock_is_there) =
      simplifile.is_directory(support.update_lock_path(scene))
    assert lock_is_there == row.lock_remains
      as { row.name <> ": the update lock folder" }
  })
}

pub fn machine_up_starts_the_machine_only_when_it_is_down_test() -> Nil {
  use <- owned_test.run(60_000)
  let starts = fn(calls) {
    list.count(calls, fn(call) { call == "podman machine start" })
  }
  // The machine answers: nothing is started.
  {
    use scene <- support.with_scene
    support.plant(scene:, key: support.info, answer: support.quiet)
    let ran = support.run_library(scene:, commands: "machine_up", extra: [])
    assert support.returned(ran) == Ok(0) as ran.output
    assert starts(support.calls(scene)) == 0
    assert !string.contains(log_of(scene), "starting it")
  }
  // The machine is down at the first ask and up after one start.
  {
    use scene <- support.with_scene
    support.plant(
      scene:,
      key: support.info,
      answer: Answer(..support.quiet, exits: [125, 0]),
    )
    support.plant(scene:, key: support.machine_start, answer: support.quiet)
    let ran = support.run_library(scene:, commands: "machine_up", extra: [])
    assert support.returned(ran) == Ok(0) as ran.output
    assert starts(support.calls(scene)) == 1
    assert string.contains(
      log_of(scene),
      "the Podman machine is not running; starting it",
    )
  }
  // The machine never answers: one start, and the answer is no.
  {
    use scene <- support.with_scene
    support.plant(
      scene:,
      key: support.info,
      answer: Answer(..support.quiet, exits: [1]),
    )
    support.plant(
      scene:,
      key: support.machine_start,
      answer: Answer(..support.quiet, exits: [1]),
    )
    let ran = support.run_library(scene:, commands: "machine_up", extra: [])
    assert support.returned(ran) == Ok(1) as ran.output
    assert starts(support.calls(scene)) == 1
    assert string.contains(
      log_of(scene),
      "the Podman machine is not running; starting it",
    )
  }
}

pub fn wait_for_postgres_asks_until_ready_or_the_asks_are_spent_test() -> Nil {
  use <- owned_test.run(60_000)
  let asks = fn(calls) {
    list.count(calls, fn(call) { string.starts_with(call, "podman exec ") })
  }
  let quick = [#("GENESIS_PLAY_POLL_SECONDS", "0")]
  // Ready at the third ask.
  {
    use scene <- support.with_scene
    support.plant(
      scene:,
      key: support.ready,
      answer: Answer(..support.quiet, exits: [2, 2, 0]),
    )
    let ran =
      support.run_library(scene:, commands: "wait_for_postgres", extra: quick)
    assert support.returned(ran) == Ok(0) as ran.output
    assert asks(support.calls(scene)) == 3
  }
  // Never ready: the asks are spent, and the log says so.
  {
    use scene <- support.with_scene
    support.plant(
      scene:,
      key: support.ready,
      answer: Answer(..support.quiet, exits: [2]),
    )
    let ran =
      support.run_library(scene:, commands: "wait_for_postgres", extra: [
        #("GENESIS_PLAY_POSTGRES_ATTEMPTS", "2"),
        ..quick
      ])
    assert support.returned(ran) == Ok(1) as ran.output
    assert asks(support.calls(scene)) == 2
    assert string.contains(
      log_of(scene),
      "Postgres did not accept a connection in 2 asks",
    )
  }
}
