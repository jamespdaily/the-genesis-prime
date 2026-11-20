//// `dev/play_service/state.sh`: the one read of the play service, the play
//// database, the updater and the live lock, run against fake `podman` and
//// `lsof` and planted files (`play_service_support`). Expected values are the
//// words `podman` and `lsof` give, the rules of the lock scripts
//// (`update.sh`, `live_lock.sh`) and the script's own contract: one `key=value`
//// line for each fact, `key=unreadable` with a `key_reason` line for a fact
//// that could not be read.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import play_service_support.{type Ran, type Scene, Answer} as support
import simplifile

const state_script = "dev/play_service/state.sh"

const server = "genesis-play"

const database = "genesis-play-postgres"

/// A row: what its scene plants over the healthy base, the report lines it
/// holds, the keys it leaves out, and the words no fake call may hold.
type Row {
  Row(
    name: String,
    plant: fn(Scene) -> Nil,
    present: List(#(String, String)),
    absent: List(String),
    no_calls: List(String),
  )
}

fn row(name: String, plant: fn(Scene) -> Nil) -> Row {
  Row(name:, plant:, present: [], absent: [], no_calls: [])
}

/// The base every row plants over: the machine up, the server and the database
/// running and the database ready, nobody connected.
fn healthy(scene: Scene) -> Nil {
  support.plant(scene:, key: support.info, answer: support.quiet)
  support.plant_container(
    scene:,
    name: server,
    status: "running",
    labels: "abc123 192.168.1.5 true",
  )
  support.plant_status(scene:, name: database, status: "running")
  support.plant(scene:, key: support.ready, answer: support.quiet)
  support.plant(
    scene:,
    key: support.connections,
    answer: Answer(..support.quiet, exits: [1]),
  )
}

/// The base of the rows about files: the machine is down, so no container is asked.
fn machine_down(scene: Scene) -> Nil {
  support.plant(
    scene:,
    key: support.info,
    answer: Answer(..support.quiet, exits: [125]),
  )
}

fn run_state(scene: Scene, extra: List(#(String, String))) -> Ran {
  support.run_script(scene:, script: state_script, extra:)
}

fn run_row(row: Row, base: fn(Scene) -> Nil) -> #(Ran, List(String)) {
  use scene <- support.with_scene
  base(scene)
  row.plant(scene)
  let ran = run_state(scene, [])
  #(ran, support.calls(scene))
}

fn check_row(row: Row, base: fn(Scene) -> Nil) -> Nil {
  let #(ran, calls) = run_row(row, base)
  let report = support.report(ran)
  list.each(row.present, fn(line) {
    assert dict.get(report, line.0) == Ok(line.1)
      as { row.name <> ": " <> line.0 <> " in " <> ran.output }
  })
  list.each(row.absent, fn(key) {
    assert dict.get(report, key) == Error(Nil)
      as { row.name <> ": " <> key <> " is not printed" }
  })
  list.each(row.no_calls, fn(word) {
    assert !list.any(calls, string.contains(_, word))
      as { row.name <> ": no call holds " <> word }
  })
}

fn server_rows() -> List(Row) {
  let server_is = fn(name, word) {
    Row(
      ..row(name, fn(scene) {
        support.plant_container(
          scene:,
          name: server,
          status: word,
          labels: "abc123 192.168.1.5 true",
        )
      }),
      present: [
        #("server", word),
        #("server_revision", "abc123"),
        #("server_address", "192.168.1.5"),
      ],
    )
  }
  let database_is = fn(name, status, ready_exit, expected) {
    Row(
      ..row(name, fn(scene) {
        support.plant_status(scene:, name: database, status:)
        support.plant(
          scene:,
          key: support.ready,
          answer: Answer(..support.quiet, exits: [ready_exit]),
        )
      }),
      present: [#("database", status), #("database_ready", expected)],
      no_calls: case status {
        "running" -> []
        _ -> ["exec"]
      },
    )
  }
  [
    Row(..server_is("the server running with its labels", "running"), present: [
      #("machine", "up"),
      #("server", "running"),
      #("server_revision", "abc123"),
      #("server_address", "192.168.1.5"),
      #("database", "running"),
      #("database_ready", "yes"),
    ]),
    server_is("the server stopping", "stopping"),
    server_is("the server exited", "exited"),
    server_is("the server created", "created"),
    Row(
      ..row("the server does not exist", fn(scene) {
        support.plant(
          scene:,
          key: support.exists(server),
          answer: Answer(..support.quiet, exits: [1]),
        )
      }),
      present: [#("server", "missing")],
      absent: ["server_revision", "server_address"],
    ),
    Row(
      ..row("podman cannot say whether the server exists", fn(scene) {
        support.plant(
          scene:,
          key: support.exists(server),
          answer: Answer(..support.quiet, exits: [125]),
        )
      }),
      present: [
        #("server", "unreadable"),
        #("server_reason", "podman exited with status 125"),
        #("database", "running"),
      ],
      absent: ["server_revision", "server_address"],
    ),
    database_is("the database running and ready", "running", 0, "yes"),
    database_is("the database running, not ready", "running", 2, "no"),
    database_is("the database exited", "exited", 2, "no"),
    Row(
      ..row("the database does not exist", fn(scene) {
        support.plant(
          scene:,
          key: support.exists(database),
          answer: Answer(..support.quiet, exits: [1]),
        )
      }),
      present: [#("database", "missing"), #("database_ready", "no")],
      no_calls: ["exec"],
    ),
  ]
}

pub fn state_sh_reports_each_container_status_as_podman_gives_it_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(server_rows(), check_row(_, healthy))
}

fn machine_rows() -> List(Row) {
  let down = fn(name, status) {
    Row(
      ..row(name, fn(scene) {
        support.plant(
          scene:,
          key: support.info,
          answer: Answer(..support.quiet, exits: [status]),
        )
      }),
      present: [#("machine", "down")],
      absent: [
        "server",
        "server_revision",
        "database",
        "database_ready",
        "game_connections",
      ],
      no_calls: ["container", "exec", "lsof"],
    )
  }
  [
    down("podman info exits 125, as a failing Podman does", 125),
    down("podman info exits 1", 1),
  ]
}

pub fn state_sh_reports_a_down_machine_and_asks_no_container_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(machine_rows(), check_row(_, healthy))
}

fn connection_rows() -> List(Row) {
  let header = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n"
  let connection =
    "gvproxy 4242 jimd 9u IPv4 0x1 0t0 TCP *:24000->10.0.0.5:51000 (ESTABLISHED)\n"
  let lsof_gives = fn(name, exit, output, error, expected) {
    Row(
      ..row(name, fn(scene) {
        support.plant(
          scene:,
          key: support.connections,
          answer: Answer(exits: [exit], output:, error:),
        )
      }),
      present: [#("game_connections", expected)],
    )
  }
  [
    lsof_gives("no match: exit 1, no output", 1, "", "", "0"),
    lsof_gives(
      "a header and two rows",
      0,
      header <> connection <> connection,
      "",
      "2",
    ),
    lsof_gives("a header and one row", 0, header <> connection, "", "1"),
    Row(
      ..lsof_gives(
        "exit 1 with a line on standard error",
        1,
        "",
        "lsof: WARNING: can't stat() fuse file system\n",
        "unreadable",
      ),
      present: [
        #("game_connections", "unreadable"),
        #(
          "game_connections_reason",
          "lsof exited with status 1: lsof: WARNING: can't stat() fuse file system",
        ),
      ],
    ),
  ]
}

pub fn state_sh_counts_game_connections_without_the_header_row_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(connection_rows(), check_row(_, healthy))
}

fn allowed_call(call: String) -> Bool {
  call == "podman info"
  || string.starts_with(call, "podman container exists ")
  || string.starts_with(call, "podman container inspect ")
  || {
    string.starts_with(call, "podman exec ")
    && string.contains(call, " pg_isready ")
  }
  || call == "lsof -nP -iTCP:24000 -sTCP:ESTABLISHED"
}

pub fn state_sh_only_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = list.flatten([server_rows(), machine_rows(), connection_rows()])
  list.each(rows, fn(row) {
    let #(_, calls) = run_row(row, healthy)
    assert calls != [] as { row.name <> ": the script asked something" }
    list.each(calls, fn(call) {
      assert allowed_call(call)
        as { row.name <> ": a call that reads nothing: " <> call }
    })
  })
}

/// How old a planted lock is when the script reads it: the rows that do not
/// depend on it leave it as made, the others plant it far over or far under the
/// minute the scripts count, so no load decides them.
type Age {
  AnyAge
  UnderAMinute
  OverAMinute
}

fn plant_age(path: String, age: Age) -> Nil {
  case age {
    AnyAge -> Nil
    UnderAMinute -> support.make_young(path)
    OverAMinute -> support.make_old(path)
  }
}

fn locks_and_hold_rows() -> List(Row) {
  let alive = support.os_pid()
  let alive_text = support.started_text(alive)
  let dead = support.ended_pid()
  let update_lock = fn(name, owner, age, expected) {
    Row(
      ..row(name, fn(scene) {
        support.plant_update_lock(scene:, owner:)
        plant_age(support.update_lock_path(scene), age)
      }),
      present: [#("update_lock", expected)],
    )
  }
  let live_lock = fn(name, record, age, expected) {
    Row(
      ..row(name, fn(scene) {
        support.plant_live_lock(scene:, record:)
        plant_age(support.live_lock_path(scene), age)
      }),
      present: [#("live_lock", expected)],
    )
  }
  let record = fn(kind, folder, pid, started) {
    Some(support.owner_record(kind:, folder:, pid:, started:))
  }
  let pid = int.to_string
  [
    Row(
      ..row("the hold is a file", fn(scene) { support.plant_hold(scene) }),
      present: [#("held", "yes")],
    ),
    Row(..row("no hold", fn(_) { Nil }), present: [#("held", "no")]),
    Row(
      ..row("no update lock", fn(_) { Nil }),
      present: [#("update_lock", "free")],
      absent: ["update_lock_pid"],
    ),
    Row(
      ..update_lock(
        "an update lock whose owner runs",
        Some(alive),
        AnyAge,
        "run",
      ),
      present: [#("update_lock", "run"), #("update_lock_pid", pid(alive))],
    ),
    Row(
      ..update_lock(
        "an update lock whose owner is gone",
        Some(dead),
        AnyAge,
        "gone",
      ),
      present: [#("update_lock", "gone"), #("update_lock_pid", pid(dead))],
    ),
    Row(
      ..update_lock(
        "an update lock with no owner file under a minute",
        None,
        UnderAMinute,
        "ownerless",
      ),
      absent: ["update_lock_pid"],
    ),
    Row(
      ..update_lock(
        "an update lock with no owner file over a minute",
        None,
        OverAMinute,
        "gone",
      ),
      absent: ["update_lock_pid"],
    ),
    Row(
      ..row("no live lock", fn(_) { Nil }),
      present: [#("live_lock", "free")],
      absent: ["live_lock_pid", "live_lock_kind", "live_lock_folder"],
    ),
    Row(
      ..live_lock(
        "a client start whose owner runs",
        record("client", "", alive, alive_text),
        AnyAge,
        "client",
      ),
      present: [
        #("live_lock", "client"),
        #("live_lock_pid", pid(alive)),
        #("live_lock_kind", "client"),
      ],
      absent: ["live_lock_folder"],
    ),
    Row(
      ..live_lock(
        "a run whose owner runs",
        record("run", "/sittings/run-1", alive, alive_text),
        AnyAge,
        "run",
      ),
      present: [
        #("live_lock", "run"),
        #("live_lock_pid", pid(alive)),
        #("live_lock_kind", "run"),
        #("live_lock_folder", "/sittings/run-1"),
      ],
    ),
    Row(
      ..live_lock(
        "a run whose owner is gone",
        record("run", "/sittings/run-2", dead, "Mon Jan 1 00:00:00 2001"),
        AnyAge,
        "gone",
      ),
      present: [
        #("live_lock", "gone"),
        #("live_lock_pid", pid(dead)),
        #("live_lock_kind", "run"),
        #("live_lock_folder", "/sittings/run-2"),
      ],
    ),
    Row(
      ..live_lock(
        "a recorded pid a later process reuses",
        record("client", "", alive, "Mon Jan 1 00:00:00 2001"),
        AnyAge,
        "gone",
      ),
      present: [#("live_lock", "gone"), #("live_lock_kind", "client")],
    ),
    Row(
      ..live_lock(
        "a live lock with no owner record under a minute",
        None,
        UnderAMinute,
        "ownerless",
      ),
      absent: ["live_lock_pid", "live_lock_kind"],
    ),
    Row(
      ..live_lock(
        "a live lock with no owner record over a minute",
        None,
        OverAMinute,
        "gone",
      ),
      absent: ["live_lock_pid", "live_lock_kind"],
    ),
    Row(
      ..live_lock(
        "an owner record with no pid line",
        Some("token=planted\nkind=run\nfolder=/sittings/run-3\n"),
        UnderAMinute,
        "ownerless",
      ),
      present: [
        #("live_lock", "ownerless"),
        #("live_lock_kind", "run"),
        #("live_lock_folder", "/sittings/run-3"),
      ],
      absent: ["live_lock_pid"],
    ),
  ]
}

pub fn state_sh_reports_the_hold_and_the_two_locks_from_their_files_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(locks_and_hold_rows(), check_row(_, machine_down))
}

pub fn state_sh_reports_the_updaters_last_log_line_test() -> Nil {
  use <- owned_test.run(60_000)
  let line =
    "2026-11-20 02:41:58 play-service: replacing genesis-play: abc, address a=b -> c=d, running false"
  let rows = [
    #("three lines, the last", Some("one\ntwo\n" <> line <> "\n"), line),
    #("no log file", None, ""),
    #("an empty log", Some(""), ""),
    #("a last line with no newline", Some("one\n" <> line), line),
  ]
  list.each(rows, fn(row) {
    use scene <- support.with_scene
    machine_down(scene)
    case row.1 {
      Some(text) ->
        support.plant_home_file(scene:, name: "play-service.log", text:)
      None -> Nil
    }
    let report = support.report(run_state(scene, []))
    assert dict.get(report, "updater_last_line") == Ok(row.2) as row.0
  })
}

const every_key = [
  "machine", "server", "server_revision", "server_address", "database",
  "database_ready", "game_connections", "held", "update_lock", "live_lock",
  "updater_last_line",
]

pub fn state_sh_needs_no_environment_file_and_prints_none_of_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let secret = "sentinel-6f1c9e-password"
  let environment_files = [
    #("no env.sh", None),
    #(
      "an env.sh holding the play password",
      Some(
        "GENESIS_PLAY_ADDRESS=192.168.1.5\nGENESIS_PLAY_ACCOUNT=jim\nGENESIS_PLAY_PGPASSWORD="
        <> secret
        <> "\n",
      ),
    ),
  ]
  list.each(environment_files, fn(file) {
    use scene <- support.with_scene
    healthy(scene)
    case file.1 {
      Some(text) -> support.plant_home_file(scene:, name: "env.sh", text:)
      None -> Nil
    }
    let ran = run_state(scene, [])
    let report = support.report(ran)
    list.each(every_key, fn(key) {
      assert dict.has_key(report, key)
        as { file.0 <> ": " <> key <> " in " <> ran.output }
    })
    assert !string.contains(ran.output, secret)
      as { file.0 <> ": the password is printed" }
  })
}

/// How a hung call is planted and what the report then holds.
type Hang {
  Hang(
    name: String,
    key: String,
    present: List(#(String, String)),
    absent: List(String),
    still_printed: List(String),
  )
}

const bound = "timed out at its 0.2 s bound"

pub fn a_hung_read_ends_within_its_bound_and_leaves_no_process_test() -> Nil {
  use <- owned_test.run(60_000)
  let hangs = [
    Hang(
      name: "podman info blocks",
      key: support.info,
      present: [#("machine", "unreadable"), #("machine_reason", bound)],
      absent: [],
      still_printed: ["held", "update_lock", "live_lock", "updater_last_line"],
    ),
    Hang(
      name: "the server's status inspect blocks",
      key: support.status(server),
      present: [
        #("machine", "up"),
        #("server", "unreadable"),
        #("server_reason", bound),
        #("database", "running"),
        #("database_ready", "yes"),
        #("game_connections", "0"),
      ],
      absent: [],
      still_printed: ["held", "update_lock", "live_lock", "updater_last_line"],
    ),
    Hang(
      name: "the server's labels inspect blocks",
      key: support.labels(server),
      present: [
        #("machine", "up"),
        #("server", "running"),
        #("server_labels", "unreadable"),
        #("server_labels_reason", bound),
        #("database", "running"),
        #("game_connections", "0"),
      ],
      absent: ["server_revision", "server_address"],
      still_printed: ["held", "update_lock", "live_lock", "updater_last_line"],
    ),
    Hang(
      name: "lsof blocks",
      key: support.connections,
      present: [
        #("machine", "up"),
        #("server", "running"),
        #("database", "running"),
        #("game_connections", "unreadable"),
        #("game_connections_reason", bound),
      ],
      absent: [],
      still_printed: ["held", "update_lock", "live_lock", "updater_last_line"],
    ),
  ]
  list.each(hangs, fn(hang) {
    use scene <- support.with_scene
    healthy(scene)
    support.plant_block(scene:, key: hang.key)
    let ran = run_state(scene, [#("GENESIS_PLAY_COMMAND_BOUND_TENTHS", "2")])
    let report = support.report(ran)
    list.each(hang.present, fn(line) {
      assert dict.get(report, line.0) == Ok(line.1)
        as { hang.name <> ": " <> line.0 <> " in " <> ran.output }
    })
    list.each(hang.absent, fn(key) {
      assert dict.get(report, key) == Error(Nil)
        as { hang.name <> ": " <> key <> " is not printed in " <> ran.output }
    })
    list.each(hang.still_printed, fn(key) {
      assert dict.has_key(report, key)
        as { hang.name <> ": " <> key <> " in " <> ran.output }
    })
    let pids = support.blocked_pids(scene:, key: hang.key)
    assert pids != [] as { hang.name <> ": the blocked call started" }
    list.each(pids, fn(pid) {
      assert !support.alive(pid)
        as { hang.name <> ": the blocked call is gone" }
    })
  })

  // The script itself is killed while `podman info` blocks and its first look is
  // held: the shell that waits for the call (its pid is in look.waiter) goes on
  // when the looks are released, and ends the call at its bound. The test's shell
  // waits for the one event that settles it, the call gone or that shell gone,
  // and prints `left` when the call outlived the shell.
  use scene <- support.with_scene
  healthy(scene)
  support.plant_block(scene:, key: support.info)
  support.hold_looks(scene:)
  let call = support.blocked_pid_path(scene:, key: support.info)
  let waiter = support.look_waiter_path(scene)
  let ran =
    support.run_shell(
      scene:,
      commands: "/bin/bash dev/play_service/state.sh >/dev/null 2>&1 & reader=$!; "
        <> "until { [ -s "
        <> call
        <> " ] && [ -s "
        <> waiter
        <> " ]; } || ! kill -0 $reader 2>/dev/null; do sleep 0.05; done; "
        <> "kill -9 $reader; "
        <> "rm "
        <> scene.fakes
        <> "/look.hold; "
        <> "until ! kill -0 $(cat "
        <> call
        <> ") 2>/dev/null || ! kill -0 $(cat "
        <> waiter
        <> ") 2>/dev/null; do sleep 0.05; done; "
        <> "if kill -0 $(cat "
        <> call
        <> ") 2>/dev/null; then kill -9 $(cat "
        <> call
        <> "); echo left; fi",
      extra: [#("GENESIS_PLAY_COMMAND_BOUND_TENTHS", "2")],
    )
  assert ran.status == 0 as { "the test's shell ended: " <> ran.output }
  assert !string.contains(ran.output, "left")
    as "the call of a killed script was still there when its waiter was gone"
  let pids = support.blocked_pids(scene:, key: support.info)
  assert pids != [] as "the blocked call started"
  list.each(pids, fn(pid) {
    assert !support.alive(pid) as "the call of a killed script is gone"
  })
}

pub fn a_read_that_used_its_budget_asks_nothing_more_test() -> Nil {
  use <- owned_test.run(60_000)
  use scene <- support.with_scene
  healthy(scene)
  support.plant_block(scene:, key: support.status(server))
  let ran =
    run_state(scene, [
      #("GENESIS_PLAY_COMMAND_BOUND_TENTHS", "10"),
      #("GENESIS_PLAY_READ_BUDGET_TENTHS", "3"),
    ])
  let report = support.report(ran)
  let used_up = "not asked: the read's 0.3 s budget was used up"
  let expected = [
    #("server", "unreadable"),
    #("server_reason", "timed out: the read's 0.3 s budget ran out"),
    #("database", "unreadable"),
    #("database_reason", used_up),
    #("database_ready", "unreadable"),
    #("game_connections", "unreadable"),
    #("game_connections_reason", used_up),
  ]
  list.each(expected, fn(line) {
    assert dict.get(report, line.0) == Ok(line.1)
      as { line.0 <> " in " <> ran.output }
  })
  list.each(["held", "update_lock", "live_lock", "updater_last_line"], fn(key) {
    assert dict.has_key(report, key) as { key <> " in " <> ran.output }
  })
  assert !list.any(support.calls(scene), string.contains(_, "lsof"))
    as "lsof is not called once the budget is used up"
}

pub fn a_damaged_update_lock_owner_file_prints_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  use scene <- support.with_scene
  machine_down(scene)
  let pid = int.to_string(support.os_pid())
  support.plant_update_lock(scene:, owner: Some(support.os_pid()))
  let assert Ok(Nil) =
    simplifile.write(
      support.update_lock_path(scene) <> "/owner",
      pid <> "\n4242\n",
    )
  let ran = run_state(scene, [])
  assert dict.get(support.report(ran), "update_lock_pid") == Ok(pid)
    as "the first line of the owner file"
  assert !string.contains(ran.output, "4242")
    as { "the second line of the owner file is not printed: " <> ran.output }
}

/// The bash 4 features the scripts must not use: `/bin/bash` here is 3.2, which
/// launchd runs, and CI's bash is newer, so only a look at the text sees them.
const bash_four_features = [
  "declare -A", "mapfile", "readarray", ",,}", "^^}", "&>>", ";;&", "coproc",
]

/// The features among `bash_four_features` that a line of `text` that is not a
/// comment holds.
pub fn bash_four_features_in(text: String) -> List(String) {
  let code =
    text
    |> string.split("\n")
    |> list.filter(fn(line) { !string.starts_with(string.trim(line), "#") })
    |> string.join("\n")
  list.filter(bash_four_features, string.contains(code, _))
}

pub fn the_play_service_scripts_use_no_bash_four_feature_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(names) = simplifile.read_directory("dev/play_service")
  let scripts = list.filter(names, string.ends_with(_, ".sh"))
  assert scripts != [] as "the scripts are found"
  list.each(scripts, fn(name) {
    let assert Ok(text) = simplifile.read("dev/play_service/" <> name)
    assert bash_four_features_in(text) == []
      as { name <> " uses a bash 4 feature" }
  })

  // The look can fail: each feature, planted in a line, is found.
  list.each(bash_four_features, fn(feature) {
    assert bash_four_features_in("x=1\nrun " <> feature <> " y\n") == [feature]
      as { feature <> " is found" }
  })
  assert bash_four_features_in("# mapfile in a comment\n") == []
    as "a comment is not code"
}
