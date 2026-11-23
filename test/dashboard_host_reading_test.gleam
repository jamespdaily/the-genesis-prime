//// The state script's report read into the Overview's facts, and the rule that
//// keeps a fact's last good value when a read does not succeed. Expected
//// values are the `key=value` contract of `dev/play_service/state.sh` (its
//// header lists each key and its values) and the Overview's rule: a true state
//// read successfully is never stale, a read that did not succeed leaves the
//// last value, marked stale with the reason and the age since it was read.

import dashboard_reading_support as support
import genesis_prime/dashboard/host_reading.{
  type Report, Database, LiveLockClient, LiveLockFree, LiveLockGone,
  LiveLockOwnerless, LiveLockRun, MachineDown, MachineUp, Report, Server,
  UpdateLockFree, UpdateLockGone, UpdateLockOwnerless, UpdateLockRun, Updater,
}
import gleam/list
import gleam/option.{None, Some}
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
    assert host_reading.parse(support.text(row.lines)) == Ok(row.expected)
      as row.name
  })
}
