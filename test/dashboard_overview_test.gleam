//// The Overview's view of a reading, read as the HTML text a browser receives.
//// Expected values are the Overview's rules: a card says its state in words
//// and in the role that state deserves (the palette's rule: green for
//// measurements, amber and red for state only), a fact last read some time ago
//// is shown dimmed with its age and why, and a reason that came from a script
//// is text, never markup. Which state has which role is a guess (a stopped
//// server is bad, a starting one warns); the words and roles are written out
//// in each row.

import dashboard_reading_support as support
import genesis_prime/dashboard/host_reading.{
  type Reading, Database, Fresh, LiveLockClient, LiveLockGone, LiveLockOwnerless,
  LiveLockRun, MachineDown, Reading, Server, UpdateLockFree, UpdateLockGone,
  UpdateLockOwnerless, UpdateLockRun, Updater,
}
import genesis_prime/dashboard/overview.{Model}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import owned_test

fn html_of(reading: Reading) -> String {
  element.to_string(overview.view(Model(reading: Some(reading))))
}

/// The markup of the fact named `name`: from its opening tag to the next
/// fact's, or to the end of the document.
fn fact(html: String, name: String) -> String {
  let assert [_, ..facts] = string.split(html, "<div class=\"fact")
    as "the view holds no fact"
  let assert Ok(found) =
    list.find(facts, string.contains(_, ">" <> name <> "<"))
    as { "the view holds no fact named " <> name }
  "<div class=\"fact" <> found
}

fn fresh() -> Reading {
  support.fresh(1000)
}

type Case {
  Case(
    name: String,
    reading: Reading,
    fact: String,
    words: List(String),
    role: String,
    absent: List(String),
  )
}

pub fn a_card_shows_its_state_in_words_and_in_the_role_that_state_deserves_test() -> Nil {
  use <- owned_test.run(5000)
  let at = 1000
  let server = fn(state) {
    Reading(
      ..fresh(),
      server: Fresh(
        Server(state:, revision: Some("9d2015a0"), address: Some("192.168.1.5")),
        at,
      ),
    )
  }
  let missing_server =
    Reading(
      ..fresh(),
      server: Fresh(
        Server(
          state: host_reading.ContainerMissing,
          revision: None,
          address: None,
        ),
        at,
      ),
    )
  let database = fn(state, ready) {
    Reading(..fresh(), database: Fresh(Database(state:, ready:), at))
  }
  let updater = fn(held, lock) {
    Reading(
      ..fresh(),
      updater: Fresh(Updater(held:, lock:, last_line: support.last_line), at),
    )
  }
  let live = fn(lock) { Reading(..fresh(), live_lock: Fresh(lock, at)) }
  let cases = [
    Case(
      name: "the server runs: its revision and address are shown",
      reading: fresh(),
      fact: "Server",
      words: ["running", "9d2015a0", "192.168.1.5"],
      role: "role-ok",
      absent: [],
    ),
    Case(
      name: "the server is stopping",
      reading: server(host_reading.ContainerStopping),
      fact: "Server",
      words: ["stopping"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the server is created",
      reading: server(host_reading.ContainerCreated),
      fact: "Server",
      words: ["created"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the server has exited",
      reading: server(host_reading.ContainerExited),
      fact: "Server",
      words: ["exited"],
      role: "role-bad",
      absent: [],
    ),
    Case(
      name: "the server is missing",
      reading: missing_server,
      fact: "Server",
      words: ["missing"],
      role: "role-bad",
      absent: [],
    ),
    Case(
      name: "the machine is up",
      reading: fresh(),
      fact: "Machine",
      words: ["up"],
      role: "role-ok",
      absent: [],
    ),
    Case(
      name: "the machine is down",
      reading: Reading(..fresh(), machine: Fresh(MachineDown, at)),
      fact: "Machine",
      words: ["down"],
      role: "role-bad",
      absent: [],
    ),
    Case(
      name: "three game connections are a number in the measurement role",
      reading: Reading(..fresh(), connections: Fresh(3, at)),
      fact: "Connections",
      words: ["3"],
      role: "role-data",
      absent: [],
    ),
    Case(
      name: "the database is ready",
      reading: fresh(),
      fact: "Database",
      words: ["running", "ready"],
      role: "role-ok",
      absent: ["not ready"],
    ),
    Case(
      name: "the database runs and is not ready",
      reading: database(host_reading.ContainerRunning, False),
      fact: "Database",
      words: ["running, not ready"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the database has exited",
      reading: database(host_reading.ContainerExited, False),
      fact: "Database",
      words: ["exited"],
      role: "role-bad",
      absent: [],
    ),
    Case(
      name: "the database is missing",
      reading: database(host_reading.ContainerMissing, False),
      fact: "Database",
      words: ["missing"],
      role: "role-bad",
      absent: [],
    ),
    Case(
      name: "the service is held",
      reading: updater(True, UpdateLockFree),
      fact: "Hold",
      words: [
        "held",
      ],
      role: "role-warn",
      absent: ["not held"],
    ),
    Case(
      name: "the service is not held",
      reading: fresh(),
      fact: "Hold",
      words: ["not held"],
      role: "role-idle",
      absent: [],
    ),
    Case(
      name: "the update lock is free",
      reading: fresh(),
      fact: "Update lock",
      words: ["free"],
      role: "role-idle",
      absent: [],
    ),
    Case(
      name: "the update lock's owner runs",
      reading: updater(False, UpdateLockRun(40_826)),
      fact: "Update lock",
      words: ["running", "40826"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the update lock has no owner yet",
      reading: updater(False, UpdateLockOwnerless),
      fact: "Update lock",
      words: ["being taken"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the update lock's owner is gone",
      reading: updater(False, UpdateLockGone(Some(4242))),
      fact: "Update lock",
      words: ["owner gone", "4242"],
      role: "role-bad",
      absent: [],
    ),
    Case(
      name: "the updater's last line is shown as it is",
      reading: fresh(),
      fact: "Last line",
      words: [support.last_line],
      role: "role-text",
      absent: [],
    ),
    Case(
      name: "the live lock is free",
      reading: fresh(),
      fact: "Lock",
      words: ["free"],
      role: "role-idle",
      absent: [],
    ),
    Case(
      name: "a client start holds the live lock",
      reading: live(LiveLockClient(pid: 777, folder: None)),
      fact: "Lock",
      words: ["client", "777"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "a run holds the live lock from a folder",
      reading: live(LiveLockRun(
        pid: 888,
        folder: Some("/Users/jimd/sittings/a b"),
      )),
      fact: "Lock",
      words: ["run", "888", "/Users/jimd/sittings/a b"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the live lock has no owner yet",
      reading: live(LiveLockOwnerless(kind: None, folder: None)),
      fact: "Lock",
      words: ["being written"],
      role: "role-warn",
      absent: [],
    ),
    Case(
      name: "the live lock's owner is gone",
      reading: live(LiveLockGone(
        kind: Some("run"),
        pid: Some(999),
        folder: Some("/sittings/x"),
      )),
      fact: "Lock",
      words: ["owner gone", "999", "run", "/sittings/x"],
      role: "role-bad",
      absent: [],
    ),
  ]
  list.each(cases, fn(row) {
    let found = fact(html_of(row.reading), row.fact)
    list.each(row.words, fn(word) {
      assert string.contains(found, word) as { row.name <> ": " <> word }
    })
    list.each(row.absent, fn(word) {
      assert !string.contains(found, word) as { row.name <> ": not " <> word }
    })
    assert string.contains(found, row.role) as { row.name <> ": " <> row.role }
    list.each(
      [
        "role-ok",
        "role-warn",
        "role-bad",
        "role-idle",
        "role-data",
        "role-text",
      ]
        |> list.filter(fn(role) { role != row.role }),
      fn(other) {
        assert !string.contains(found, other)
          as { row.name <> ": only " <> row.role }
      },
    )
    assert !string.contains(found, "stale") as { row.name <> ": a fresh fact" }
  })
}
