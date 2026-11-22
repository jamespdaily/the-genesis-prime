//// The Overview page: a card for the play service, the play database, the
//// updater and the live lock, each saying its state in words and in the role
//// that state deserves, as of the latest reading the poller sent.
////
//// ```text
//// poller (host) ──Reading──► runtime (one per tab) ──view──► tab
////                  subscribed once the runtime hears the poller (`subscription`)
//// ```
////
//// - A tab's runtime subscribes to the poller when it starts, and the poller
////   drops it when the runtime ends.
//// - A card says "No reading yet" until the first reading arrives.
//// - A fact last read some time ago is shown with its last value, dimmed,
////   with its age and why it is stale; a fact never read says why.
//// - A reason or a line that came from a script is text, never markup.
//// - A state's role is the palette's: green for measurements, amber and red
////   for state only. Which state has which role is a guess: a state that needs
////   a person to act (a stopped server, a lock whose owner is gone) is bad, a
////   state that passes by itself (starting, a lock being taken) warns, and a
////   state with nothing to do is idle.

import genesis_prime/dashboard/host
import genesis_prime/dashboard/host_reading.{
  type ContainerState, type LiveLock, type Reading, type Section,
}
import genesis_prime/dashboard/page.{type Page, OverviewKey, Page}
import genesis_prime/dashboard/read_poll
import genesis_prime/dashboard/subscription
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

/// What the Overview holds: the latest reading, once there is one.
pub type Model {
  Model(reading: Option(Reading))
}

/// What the Overview is told: the poller sent a reading, or its runtime can hear
/// the poller and the page is to subscribe (`join`).
pub type Message {
  Received(reading: Reading)
  Joining(join: fn() -> Nil)
}

/// How a state looks: the palette role its words are shown in.
type Role {
  RoleOk
  RoleWarn
  RoleBad
  RoleIdle
  RoleData
  RolePlain
}

/// A fact's value as the page shows it: its words, their role, and a detail.
type Shown {
  Shown(words: String, role: Role, detail: Option(String))
}

/// The Overview as an entry of the page list.
pub fn page() -> Page {
  Page(key: OverviewKey, title: "Overview", path: "/")
}

/// The Overview as a server component: its start argument is the poller it
/// subscribes to.
pub fn app() -> lustre.App(Subject(host.Message), Model, Message) {
  lustre.application(init, update, view)
}

fn init(poller: Subject(host.Message)) -> #(Model, Effect(Message)) {
  #(
    Model(reading: None),
    subscription.open(
      join: fn(subject) {
        read_poll.subscribe(poll: poller, subscriber: subject)
      },
      received: Received,
      joining: Joining,
    ),
  )
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Received(reading:) -> #(Model(reading: Some(reading)), effect.none())
    Joining(join:) -> #(model, subscription.joined(join))
  }
}

/// The Overview's content.
pub fn view(model: Model) -> Element(Message) {
  html.section([], [
    html.h2([], [html.text("Overview")]),
    html.div([attribute.class("grid")], case model.reading {
      None -> [
        card("Play service", None),
        card("Play database", None),
        card("Updater", None),
        card("Live lock", None),
      ]
      Some(reading) -> [
        card("Play service", Some(play_service(reading))),
        card("Play database", Some(play_database(reading))),
        card("Updater", Some(updater(reading))),
        card("Live lock", Some(live_lock(reading))),
      ]
    }),
  ])
}

fn card(
  title: String,
  facts: Option(List(Element(Message))),
) -> Element(Message) {
  html.div([attribute.class("card")], [
    html.div([attribute.class("label")], [html.text(title)]),
    ..case facts {
      None -> [
        html.p([attribute.class("empty")], [html.text("No reading yet")]),
      ]
      Some(facts) -> facts
    }
  ])
}

fn play_service(reading: Reading) -> List(Element(Message)) {
  [
    fact(reading, "Machine", reading.machine, fn(machine) {
      case machine {
        host_reading.MachineUp -> Shown("up", RoleOk, None)
        host_reading.MachineDown -> Shown("down", RoleBad, None)
      }
    }),
    fact(reading, "Server", reading.server, fn(server) {
      let labels =
        list.filter_map(
          [
            option.map(server.revision, fn(revision) { "revision " <> revision }),
            option.map(server.address, fn(address) { "address " <> address }),
          ],
          option.to_result(_, Nil),
        )
      let shown = container(server.state)
      Shown(..shown, detail: case labels {
        [] -> None
        labels -> Some(string.join(labels, ", "))
      })
    }),
    fact(reading, "Connections", reading.connections, fn(count) {
      Shown(int.to_string(count), RoleData, None)
    }),
  ]
}

fn play_database(reading: Reading) -> List(Element(Message)) {
  [
    fact(reading, "Database", reading.database, fn(database) {
      case database.state, database.ready {
        host_reading.ContainerRunning, True ->
          Shown("running, ready", RoleOk, None)
        host_reading.ContainerRunning, False ->
          Shown("running, not ready", RoleWarn, None)
        state, _ -> container(state)
      }
    }),
  ]
}

fn updater(reading: Reading) -> List(Element(Message)) {
  [
    fact(reading, "Hold", reading.updater, fn(updater) {
      case updater.held {
        True -> Shown("held", RoleWarn, None)
        False -> Shown("not held", RoleIdle, None)
      }
    }),
    fact(reading, "Update lock", reading.updater, fn(updater) {
      case updater.lock {
        host_reading.UpdateLockFree -> Shown("free", RoleIdle, None)
        host_reading.UpdateLockRun(pid:) ->
          Shown(
            "running (process " <> int.to_string(pid) <> ")",
            RoleWarn,
            None,
          )
        host_reading.UpdateLockOwnerless -> Shown("being taken", RoleWarn, None)
        host_reading.UpdateLockGone(pid:) ->
          Shown("owner gone" <> process_words(pid), RoleBad, None)
      }
    }),
    fact(reading, "Last line", reading.updater, fn(updater) {
      case updater.last_line {
        "" -> Shown("no log line", RoleIdle, None)
        line -> Shown(line, RolePlain, None)
      }
    }),
  ]
}

fn live_lock(reading: Reading) -> List(Element(Message)) {
  [
    fact(reading, "Lock", reading.live_lock, fn(lock: LiveLock) {
      case lock {
        host_reading.LiveLockFree -> Shown("free", RoleIdle, None)
        host_reading.LiveLockClient(pid:, folder:) ->
          Shown(
            "held by a client start (process " <> int.to_string(pid) <> ")",
            RoleWarn,
            folder,
          )
        host_reading.LiveLockRun(pid:, folder:) ->
          Shown(
            "held by a run (process " <> int.to_string(pid) <> ")",
            RoleWarn,
            folder,
          )
        host_reading.LiveLockOwnerless(kind:, folder:) ->
          Shown("being written", RoleWarn, owner_detail(kind, folder))
        host_reading.LiveLockGone(kind:, pid:, folder:) ->
          Shown(
            "owner gone" <> process_words(pid),
            RoleBad,
            owner_detail(kind, folder),
          )
      }
    }),
  ]
}

fn process_words(pid: Option(Int)) -> String {
  case pid {
    Some(pid) -> " (process " <> int.to_string(pid) <> ")"
    None -> ""
  }
}

fn owner_detail(
  kind: Option(String),
  folder: Option(String),
) -> Option(String) {
  let parts =
    list.filter_map(
      [
        option.map(kind, fn(kind) { "kind " <> kind }),
        option.map(folder, fn(folder) { "folder " <> folder }),
      ],
      option.to_result(_, Nil),
    )
  case parts {
    [] -> None
    parts -> Some(string.join(parts, ", "))
  }
}

fn container(state: ContainerState) -> Shown {
  case state {
    host_reading.ContainerRunning -> Shown("running", RoleOk, None)
    host_reading.ContainerStopping -> Shown("stopping", RoleWarn, None)
    host_reading.ContainerCreated -> Shown("created", RoleWarn, None)
    host_reading.ContainerExited -> Shown("exited", RoleBad, None)
    host_reading.ContainerMissing -> Shown("missing", RoleBad, None)
  }
}

/// One fact of a card, from its section of the reading: its value in words,
/// with its age and reason when it is stale, or why it was never read.
fn fact(
  reading: Reading,
  name: String,
  section: Section(a),
  show: fn(a) -> Shown,
) -> Element(Message) {
  case section {
    host_reading.Never(reason:) ->
      html.div([attribute.class("fact")], [
        html.span([attribute.class("name")], [html.text(name)]),
        html.span([attribute.class("empty")], [
          html.text("No reading: " <> reason),
        ]),
      ])
    host_reading.Fresh(value:, ..) ->
      shown(name:, shown: show(value), stale: None)
    host_reading.Stale(value:, cause:, read_ms:) -> {
      let age = reading.composed_ms - read_ms
      shown(name:, shown: show(value), stale: Some(stale_words(cause, age)))
    }
  }
}

fn shown(
  name name: String,
  shown shown: Shown,
  stale stale: Option(String),
) -> Element(Message) {
  html.div(
    [
      attribute.classes([
        #("fact", True),
        #("stale", option.is_some(stale)),
        #(role_class(shown.role), True),
      ]),
    ],
    list.flatten([
      [
        html.span([attribute.class("name")], [html.text(name)]),
        html.span([attribute.class("state")], [html.text(shown.words)]),
      ],
      case shown.detail {
        Some(detail) -> [
          html.span([attribute.class("detail")], [html.text(detail)]),
        ]
        None -> []
      },
      case stale {
        Some(words) -> [html.span([attribute.class("why")], [html.text(words)])]
        None -> []
      },
    ]),
  )
}

fn role_class(role: Role) -> String {
  case role {
    RoleOk -> "role-ok"
    RoleWarn -> "role-warn"
    RoleBad -> "role-bad"
    RoleIdle -> "role-idle"
    RoleData -> "role-data"
    RolePlain -> "role-text"
  }
}

/// "stale 12 s: the reason", the age in the largest whole unit.
fn stale_words(cause: host_reading.Cause, age_ms: Int) -> String {
  let seconds = int.max(0, age_ms) / 1000
  let age = case seconds {
    seconds if seconds < 60 -> int.to_string(seconds) <> " s"
    seconds if seconds < 3600 -> int.to_string(seconds / 60) <> " min"
    seconds -> int.to_string(seconds / 3600) <> " h"
  }
  let reason = case cause {
    host_reading.ReadFailed(reason:) -> reason
    host_reading.NoNewReading ->
      "no new reading for " <> int.to_string(int.max(0, age_ms) / 1000) <> " s"
  }
  "stale " <> age <> ": " <> reason
}
