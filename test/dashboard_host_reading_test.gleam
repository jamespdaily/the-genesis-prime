//// The state script's report read into the Overview's facts, and the rule that
//// keeps a fact's last good value when a read does not succeed. Expected
//// values are the `key=value` contract of `dev/play_service/state.sh` (its
//// header lists each key and its values) and the Overview's rule: a true state
//// read successfully is never stale, a read that did not succeed leaves the
//// last value, marked stale with the reason and the age since it was read.

import dashboard_reading_support as support
import genesis_prime/dashboard/host_reading.{
  type Reading, type Report, Database, Fresh, LiveLockClient, LiveLockFree,
  LiveLockGone, LiveLockOwnerless, LiveLockRun, MachineDown, MachineUp, Never,
  NoNewReading, Ran, ReadFailed, Reading, Report, Server, Stale, UpdateLockFree,
  UpdateLockGone, UpdateLockOwnerless, UpdateLockRun, Updater, Waiting,
}
import genesis_prime/dashboard/script
import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test

/// What `healthy_lines` read must give, written out.
fn healthy_report() -> Report {
  Report(
    machine: Ok(MachineUp),
    server: Ok(Server(
      state: host_reading.ContainerRunning,
      revision: Some("9d2015a0"),
      address: Some("192.168.1.5"),
    )),
    connections: Ok(0),
    database: Ok(Database(state: host_reading.ContainerRunning, ready: True)),
    updater: Ok(Updater(
      held: False,
      lock: UpdateLockFree,
      last_line: support.last_line,
    )),
    live_lock: Ok(LiveLockFree),
  )
}

fn unreadable_all(reason: String) -> Report {
  Report(
    machine: Error(host_reading.Unreadable(reason)),
    server: Error(host_reading.Unreadable(reason)),
    connections: Error(host_reading.Unreadable(reason)),
    database: Error(host_reading.Unreadable(reason)),
    updater: Error(host_reading.Unreadable(reason)),
    live_lock: Error(host_reading.Unreadable(reason)),
  )
}

type ReadRow {
  ReadRow(name: String, lines: List(#(String, String)), expected: Report)
}

pub fn a_report_gives_each_section_its_state_test() -> Nil {
  use <- owned_test.run(5000)
  let healthy = healthy_report()
  let down = "the Podman machine is down"
  let server = fn(state, revision, address) {
    Ok(Server(state:, revision:, address:))
  }
  let labels = #(Some("9d2015a0"), Some("192.168.1.5"))
  let database = fn(state, ready) { Ok(Database(state:, ready:)) }
  let updater = fn(held, lock) {
    Ok(Updater(held:, lock:, last_line: support.last_line))
  }
  let rows = [
    ReadRow("everything healthy", support.healthy_lines(), healthy),
    ReadRow(
      "the machine is down and no container line is printed",
      [
        #("machine", "down"),
        #("held", "no"),
        #("update_lock", "free"),
        #("live_lock", "free"),
        #("updater_last_line", support.last_line),
      ],
      Report(
        ..healthy,
        machine: Ok(MachineDown),
        server: Error(host_reading.Unreadable(down)),
        connections: Error(host_reading.Unreadable(down)),
        database: Error(host_reading.Unreadable(down)),
      ),
    ),
    ReadRow(
      "the server is stopping",
      support.changed([support.Set("server", "stopping")]),
      Report(
        ..healthy,
        server: server(host_reading.ContainerStopping, labels.0, labels.1),
      ),
    ),
    ReadRow(
      "the server has exited",
      support.changed([support.Set("server", "exited")]),
      Report(
        ..healthy,
        server: server(host_reading.ContainerExited, labels.0, labels.1),
      ),
    ),
    ReadRow(
      "the server is created",
      support.changed([support.Set("server", "created")]),
      Report(
        ..healthy,
        server: server(host_reading.ContainerCreated, labels.0, labels.1),
      ),
    ),
    ReadRow(
      "the server is missing and prints no labels",
      support.changed([
        support.Set("server", "missing"),
        support.Drop("server_revision"),
        support.Drop("server_address"),
      ]),
      Report(
        ..healthy,
        server: server(host_reading.ContainerMissing, None, None),
      ),
    ),
    ReadRow(
      "the server has no labels",
      support.changed([
        support.Set("server_revision", ""),
        support.Set("server_address", ""),
      ]),
      Report(
        ..healthy,
        server: server(host_reading.ContainerRunning, None, None),
      ),
    ),
    ReadRow(
      "the database runs and is not ready",
      support.changed([support.Set("database_ready", "no")]),
      Report(
        ..healthy,
        database: database(host_reading.ContainerRunning, False),
      ),
    ),
    ReadRow(
      "the database has exited",
      support.changed([
        support.Set("database", "exited"),
        support.Set("database_ready", "no"),
      ]),
      Report(..healthy, database: database(host_reading.ContainerExited, False)),
    ),
    ReadRow(
      "the database is missing",
      support.changed([
        support.Set("database", "missing"),
        support.Set("database_ready", "no"),
      ]),
      Report(
        ..healthy,
        database: database(host_reading.ContainerMissing, False),
      ),
    ),
    ReadRow(
      "the service is held",
      support.changed([support.Set("held", "yes")]),
      Report(..healthy, updater: updater(True, UpdateLockFree)),
    ),
    ReadRow(
      "the update lock's owner runs",
      support.changed([
        support.Set("update_lock", "run"),
        support.Set("update_lock_pid", "40826"),
      ]),
      Report(..healthy, updater: updater(False, UpdateLockRun(40_826))),
    ),
    ReadRow(
      "the update lock has no owner yet",
      support.changed([support.Set("update_lock", "ownerless")]),
      Report(..healthy, updater: updater(False, UpdateLockOwnerless)),
    ),
    ReadRow(
      "the update lock's owner is gone",
      support.changed([
        support.Set("update_lock", "gone"),
        support.Set("update_lock_pid", "4242"),
      ]),
      Report(..healthy, updater: updater(False, UpdateLockGone(Some(4242)))),
    ),
    ReadRow(
      "the update lock has no owner and is old",
      support.changed([support.Set("update_lock", "gone")]),
      Report(..healthy, updater: updater(False, UpdateLockGone(None))),
    ),
    ReadRow(
      "a client start holds the live lock",
      support.changed([
        support.Set("live_lock", "client"),
        support.Set("live_lock_kind", "client"),
        support.Set("live_lock_pid", "777"),
      ]),
      Report(..healthy, live_lock: Ok(LiveLockClient(pid: 777, folder: None))),
    ),
    ReadRow(
      "a run holds the live lock from a folder",
      support.changed([
        support.Set("live_lock", "run"),
        support.Set("live_lock_kind", "run"),
        support.Set("live_lock_pid", "888"),
        support.Set("live_lock_folder", "/Users/jimd/sittings/a b"),
      ]),
      Report(
        ..healthy,
        live_lock: Ok(LiveLockRun(
          pid: 888,
          folder: Some("/Users/jimd/sittings/a b"),
        )),
      ),
    ),
    ReadRow(
      "the live lock has no owner yet",
      support.changed([support.Set("live_lock", "ownerless")]),
      Report(
        ..healthy,
        live_lock: Ok(LiveLockOwnerless(kind: None, folder: None)),
      ),
    ),
    ReadRow(
      "the live lock's owner is gone",
      support.changed([
        support.Set("live_lock", "gone"),
        support.Set("live_lock_kind", "run"),
        support.Set("live_lock_pid", "999"),
        support.Set("live_lock_folder", "/sittings/x"),
      ]),
      Report(
        ..healthy,
        live_lock: Ok(LiveLockGone(
          kind: Some("run"),
          pid: Some(999),
          folder: Some("/sittings/x"),
        )),
      ),
    ),
    ReadRow(
      "three game connections",
      support.changed([support.Set("game_connections", "3")]),
      Report(..healthy, connections: Ok(3)),
    ),
    ReadRow(
      "the updater's last line holds an equals sign and spaces and is passed through",
      support.changed([support.Set("updater_last_line", "  a=b  c = d ")]),
      Report(
        ..healthy,
        updater: Ok(Updater(
          held: False,
          lock: UpdateLockFree,
          last_line: "  a=b  c = d ",
        )),
      ),
    ),
    ReadRow(
      "no log gives an empty last line",
      support.changed([support.Set("updater_last_line", "")]),
      Report(
        ..healthy,
        updater: Ok(Updater(held: False, lock: UpdateLockFree, last_line: "")),
      ),
    ),
  ]
  list.each(rows, fn(row) {
    assert host_reading.parse(support.text(row.lines)) == row.expected
      as row.name
  })
}

pub fn a_wrong_or_missing_line_makes_only_its_section_unreadable_test() -> Nil {
  use <- owned_test.run(5000)
  let healthy = healthy_report()
  let not_text = <<255, 254, 253, 10>>
  let rows = [
    ReadRow(
      "no server line",
      support.changed([
        support.Drop("server"),
        support.Drop("server_revision"),
        support.Drop("server_address"),
      ]),
      Report(
        ..healthy,
        server: Error(host_reading.Unreadable("the report has no server line")),
      ),
    ),
    ReadRow(
      "a server state Podman words that the dashboard does not know",
      support.changed([support.Set("server", "paused")]),
      Report(
        ..healthy,
        server: Error(host_reading.Unreadable(
          "the server's state is \"paused\"",
        )),
      ),
    ),
    ReadRow(
      "a server the script could not read gives its reason",
      support.changed([
        support.Set("server", "unreadable"),
        support.Set("server_reason", "podman exited with status 125"),
        support.Drop("server_revision"),
        support.Drop("server_address"),
      ]),
      Report(
        ..healthy,
        server: Error(host_reading.Unreadable("podman exited with status 125")),
      ),
    ),
    ReadRow(
      "game connections that are not a number",
      support.changed([support.Set("game_connections", "x")]),
      Report(
        ..healthy,
        connections: Error(host_reading.Unreadable(
          "the game connections are \"x\", not a number",
        )),
      ),
    ),
    ReadRow(
      "game connections the script could not read",
      support.changed([
        support.Set("game_connections", "unreadable"),
        support.Set(
          "game_connections_reason",
          "lsof exited with status 1: no access",
        ),
      ]),
      Report(
        ..healthy,
        connections: Error(host_reading.Unreadable(
          "lsof exited with status 1: no access",
        )),
      ),
    ),
    ReadRow(
      "a live lock pid that is not a number",
      support.changed([
        support.Set("live_lock", "client"),
        support.Set("live_lock_kind", "client"),
        support.Set("live_lock_pid", "x"),
      ]),
      Report(
        ..healthy,
        live_lock: Error(host_reading.Unreadable(
          "the live lock's process is \"x\", not a number",
        )),
      ),
    ),
    ReadRow(
      "a live lock with a live owner and no pid",
      support.changed([support.Set("live_lock", "run")]),
      Report(
        ..healthy,
        live_lock: Error(host_reading.Unreadable(
          "the live lock has an owner but no process",
        )),
      ),
    ),
    ReadRow(
      "a database that has exited and is ready",
      support.changed([
        support.Set("database", "exited"),
        support.Set("database_ready", "yes"),
      ]),
      Report(
        ..healthy,
        database: Error(host_reading.Unreadable(
          "the database is exited and ready at once",
        )),
      ),
    ),
    ReadRow(
      "a database that runs and says nothing of readiness",
      support.changed([support.Drop("database_ready")]),
      Report(
        ..healthy,
        database: Error(host_reading.Unreadable(
          "the report has no database_ready line",
        )),
      ),
    ),
    ReadRow(
      "the update lock with a pid that is not a number",
      support.changed([
        support.Set("update_lock", "run"),
        support.Set("update_lock_pid", "?"),
      ]),
      Report(
        ..healthy,
        updater: Error(host_reading.Unreadable(
          "the update lock's process is \"?\", not a number",
        )),
      ),
    ),
    ReadRow(
      "a hold that is neither yes nor no",
      support.changed([support.Set("held", "maybe")]),
      Report(
        ..healthy,
        updater: Error(host_reading.Unreadable(
          "held is \"maybe\", not yes or no",
        )),
      ),
    ),
    ReadRow(
      "no line for the updater's last line",
      support.changed([support.Drop("updater_last_line")]),
      Report(
        ..healthy,
        updater: Error(host_reading.Unreadable(
          "the report has no updater_last_line line",
        )),
      ),
    ),
    ReadRow(
      "an unknown key is ignored",
      list.append(support.healthy_lines(), [#("colour", "red")]),
      healthy,
    ),
  ]
  list.each(rows, fn(row) {
    assert host_reading.parse(support.text(row.lines)) == row.expected
      as row.name
  })

  // Lines that are not `key=value` (diagnostic text from the merged standard
  // error) and a line with a key the script never prints are ignored.
  let noisy =
    "warning: something\n"
    <> "a sentence with = in it\n"
    <> string.concat(
      list.map(support.healthy_lines(), fn(line) {
        line.0 <> "=" <> line.1 <> "\n"
      }),
    )
    <> "trailing words\n"
  assert host_reading.parse(bit_array.from_string(noisy)) == healthy
    as "diagnostic lines are ignored"

  // An empty report and bytes that are not text give no fact.
  assert host_reading.parse(<<>>) == unreadable_all("the report is empty")
  assert host_reading.parse(not_text)
    == unreadable_all("the report is not text")
}

/// The same reading with every fact stale for `cause`, composed at `now`.
fn stale(
  from from: Int,
  now now: Int,
  cause cause: host_reading.Cause,
) -> Reading {
  let good = support.fresh(from)
  let assert Fresh(machine, _) = good.machine
  let assert Fresh(server, _) = good.server
  let assert Fresh(connections, _) = good.connections
  let assert Fresh(database, _) = good.database
  let assert Fresh(updater, _) = good.updater
  let assert Fresh(live_lock, _) = good.live_lock
  Reading(
    composed_ms: now,
    machine: Stale(machine, cause, from),
    server: Stale(server, cause, from),
    connections: Stale(connections, cause, from),
    database: Stale(database, cause, from),
    updater: Stale(updater, cause, from),
    live_lock: Stale(live_lock, cause, from),
  )
}

fn never(reason: String, at: Int) -> Reading {
  Reading(
    composed_ms: at,
    machine: Never(reason),
    server: Never(reason),
    connections: Never(reason),
    database: Never(reason),
    updater: Never(reason),
    live_lock: Never(reason),
  )
}

fn finished(lines: List(#(String, String))) -> host_reading.Outcome {
  Ran(Ok(script.Finished(output: support.text(lines), status: 0)))
}

type MergeRow {
  MergeRow(
    name: String,
    previous: option.Option(Reading),
    outcome: host_reading.Outcome,
    now: Int,
    expected: option.Option(Reading),
  )
}

pub fn a_failed_read_keeps_each_sections_last_value_and_marks_it_stale_test() -> Nil {
  use <- owned_test.run(5000)
  let failed = fn(reason) { ReadFailed(reason) }
  let status_three =
    Ran(Ok(script.Finished(output: <<"boom\nsecond line\n":utf8>>, status: 3)))
  let exit_three = failed("the state script exited with status 3: boom")
  let rows = [
    MergeRow(
      "the first read fails and there is no earlier value",
      None,
      status_three,
      1000,
      Some(never("the state script exited with status 3: boom", 1000)),
    ),
    MergeRow(
      "a good read is fresh as of its time",
      None,
      finished(support.healthy_lines()),
      1000,
      Some(support.fresh(1000)),
    ),
    MergeRow(
      "a good read then an exit status of 3 marks every fact stale with the first line",
      Some(support.fresh(1000)),
      status_three,
      5000,
      Some(stale(from: 1000, now: 5000, cause: exit_three)),
    ),
    MergeRow(
      "a good read then a script with no output",
      Some(support.fresh(1000)),
      Ran(Ok(script.Finished(output: <<>>, status: 3))),
      5000,
      Some(stale(
        from: 1000,
        now: 5000,
        cause: failed("the state script exited with status 3"),
      )),
    ),
    MergeRow(
      "a good read then the deadline passed",
      Some(support.fresh(1000)),
      Ran(Error(script.DeadlineReached(15_000))),
      16_000,
      Some(stale(
        from: 1000,
        now: 16_000,
        cause: failed("the state script did not finish in 15 s"),
      )),
    ),
    MergeRow(
      "a good read then the script is absent",
      Some(support.fresh(1000)),
      Ran(Error(script.NotFound("dev/play_service/state.sh"))),
      5000,
      Some(stale(
        from: 1000,
        now: 5000,
        cause: failed(
          "the state script is not found: dev/play_service/state.sh",
        ),
      )),
    ),
    MergeRow(
      "a good read then a script that cannot run",
      Some(support.fresh(1000)),
      Ran(Error(script.NotExecutable("dev/play_service/state.sh"))),
      5000,
      Some(stale(
        from: 1000,
        now: 5000,
        cause: failed(
          "the state script is not executable: dev/play_service/state.sh",
        ),
      )),
    ),
    MergeRow(
      "a good read then a script that did not start",
      Some(support.fresh(1000)),
      Ran(Error(script.NotStarted("dev/play_service/state.sh", "emfile"))),
      5000,
      Some(stale(
        from: 1000,
        now: 5000,
        cause: failed(
          "the state script did not start (dev/play_service/state.sh): emfile",
        ),
      )),
    ),
    MergeRow(
      "a good read then a report with no server line stales only the server",
      Some(support.fresh(1000)),
      finished(
        support.changed([
          support.Drop("server"),
          support.Drop("server_revision"),
        ]),
      ),
      5000,
      Some(
        Reading(
          ..support.fresh(5000),
          server: Stale(
            Server(
              state: host_reading.ContainerRunning,
              revision: Some("9d2015a0"),
              address: Some("192.168.1.5"),
            ),
            failed("the report has no server line"),
            1000,
          ),
        ),
      ),
    ),
    MergeRow(
      "a good read then the machine goes down: it is a true state, and what the machine hides is stale",
      Some(support.fresh(1000)),
      finished([
        #("machine", "down"),
        #("held", "no"),
        #("update_lock", "free"),
        #("live_lock", "free"),
        #("updater_last_line", support.last_line),
      ]),
      5000,
      Some(
        Reading(
          ..support.fresh(5000),
          machine: Fresh(MachineDown, 5000),
          server: Stale(
            Server(
              state: host_reading.ContainerRunning,
              revision: Some("9d2015a0"),
              address: Some("192.168.1.5"),
            ),
            failed("the Podman machine is down"),
            1000,
          ),
          connections: Stale(0, failed("the Podman machine is down"), 1000),
          database: Stale(
            Database(state: host_reading.ContainerRunning, ready: True),
            failed("the Podman machine is down"),
            1000,
          ),
        ),
      ),
    ),
    MergeRow(
      "stale then good: every fact is fresh again",
      Some(stale(from: 1000, now: 5000, cause: exit_three)),
      finished(support.healthy_lines()),
      9000,
      Some(support.fresh(9000)),
    ),
    MergeRow(
      "stale then another failure: the age still counts from the last good read",
      Some(stale(from: 1000, now: 5000, cause: exit_three)),
      Ran(Error(script.DeadlineReached(15_000))),
      9000,
      Some(stale(
        from: 1000,
        now: 9000,
        cause: failed("the state script did not finish in 15 s"),
      )),
    ),
    MergeRow(
      "a read in flight under three intervals leaves the reading as it is",
      Some(support.fresh(1000)),
      Waiting,
      6999,
      Some(support.fresh(1000)),
    ),
    MergeRow(
      "a read in flight for three intervals marks every fresh fact stale though nothing failed",
      Some(support.fresh(1000)),
      Waiting,
      7000,
      Some(stale(from: 1000, now: 7000, cause: NoNewReading)),
    ),
    MergeRow(
      "a read still in flight keeps the age counting",
      Some(stale(from: 1000, now: 7000, cause: NoNewReading)),
      Waiting,
      9000,
      Some(stale(from: 1000, now: 9000, cause: NoNewReading)),
    ),
    MergeRow(
      "a read in flight when nothing was ever read gives no reading",
      None,
      Waiting,
      60_000,
      None,
    ),
    MergeRow(
      "a read in flight leaves facts that were never read as they are",
      Some(never("the state script is not found: x", 1000)),
      Waiting,
      60_000,
      Some(never("the state script is not found: x", 1000)),
    ),
  ]
  list.each(rows, fn(row) {
    assert host_reading.after_read(row.previous, row.outcome, row.now)
      == row.expected
      as row.name
  })
}
