//// The Logs page: the newest lines of the updater's log, of launchd's log, of the
//// play server's container and of its database's container, each line in the
//// role its words give, following new lines as they are written.
////
//// ```text
//// follower (updater log)   ──Followed──►┐
//// follower (launchd log)   ──Followed──►┤
////                                       ├─► runtime (one per tab) ──view──► tab
//// follower (server)        ──Followed──►┤      subscribed once its runtime hears them (`subscription`)
//// follower (database)      ──Followed──►┘
//// ```
////
//// - A tab's runtime subscribes to the four followers when it starts, and each
////   follower drops it when the runtime ends. A follower reads only while a tab
////   is subscribed.
//// - A source says "No lines yet" until its follower has sent lines, or has
////   read a file or a container with none. A file shows its path and a container
////   the call that shows its log (`podman logs NAME`).
//// - A log file that is not there says "no log yet", and one that cannot be read
////   says "cannot read" and the reason; the lines it had stay, dimmed only for
////   the second.
//// - A container's log that cannot be read shows its lines dimmed with the
////   reason for every trouble: Podman not reachable (its own words), no
////   container of that name, or a read that failed. The words are a guess.
//// - A line is text, never markup: the view makes a text node of it, and the
////   page shows what `log_lines` made of its bytes. A line that was cut says so.
//// - Each entry is one keyed element, keyed by its sequence number, so a new
////   line is one change to the page and not a rewrite of the ring.
//// - A line's role is the palette's, by its level. The level words are a guess
////   (`log_lines`).
////
//// The page shows what the logs hold: the container's last lines when it did
//// not come up, git's and gh's messages, and this Mac's paths. The page is
//// behind the dashboard's key like every route.

import genesis_prime/dashboard/container_follow
import genesis_prime/dashboard/container_log
import genesis_prime/dashboard/follow.{type Followed}
import genesis_prime/dashboard/log_lines.{type Entry, type Level, type Source}
import genesis_prime/dashboard/otp_report
import genesis_prime/dashboard/page.{type Page, LogsKey, Page}
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
import lustre/element/keyed

/// The followers a tab's runtime subscribes to: the updater's log, launchd's, the
/// play server's container and its database's.
pub type Followers {
  Followers(
    updater: Subject(follow.Message),
    launchd: Subject(follow.Message),
    server: Subject(container_follow.Message),
    database: Subject(container_follow.Message),
  )
}

/// What the Logs page holds: what each follower last sent, once it has.
pub type Model {
  Model(
    updater: Option(Followed),
    launchd: Option(Followed),
    server: Option(Followed),
    database: Option(Followed),
  )
}

/// What the Logs page is told: a follower sent its log, or its runtime can hear
/// the followers and the page is to subscribe (`join`).
pub type Message {
  Received(followed: Followed)
  Joining(join: fn() -> Nil)
}

/// The Logs page as an entry of the page list.
pub fn page() -> Page {
  Page(key: LogsKey, title: "Logs", path: "/logs")
}

/// The Logs page as a server component: its start argument is the followers it
/// subscribes to.
pub fn app() -> lustre.App(Followers, Model, Message) {
  lustre.application(init, update, view)
}

fn init(followers: Followers) -> #(Model, Effect(Message)) {
  #(
    Model(updater: None, launchd: None, server: None, database: None),
    subscription.open(
      join: fn(subject) {
        follow.subscribe(follower: followers.updater, subscriber: subject)
        follow.subscribe(follower: followers.launchd, subscriber: subject)
        read_poll.subscribe(poll: followers.server, subscriber: subject)
        read_poll.subscribe(poll: followers.database, subscriber: subject)
      },
      received: Received,
      joining: Joining,
    ),
  )
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Received(followed:) -> {
      let model = case followed.source {
        log_lines.UpdaterLog -> Model(..model, updater: Some(followed))
        log_lines.LaunchdLog -> Model(..model, launchd: Some(followed))
        log_lines.ServerLog -> Model(..model, server: Some(followed))
        log_lines.DatabaseLog -> Model(..model, database: Some(followed))
      }
      #(model, effect.none())
    }
    Joining(join:) -> #(model, subscription.joined(join))
  }
}

/// The Logs page's content.
pub fn view(model: Model) -> Element(Message) {
  html.section([], [
    html.h2([], [html.text("Logs")]),
    html.div([attribute.class("logs")], [
      log(log_lines.UpdaterLog, model.updater),
      log(log_lines.LaunchdLog, model.launchd),
      log(log_lines.ServerLog, model.server),
      log(log_lines.DatabaseLog, model.database),
    ]),
  ])
}

fn title(source: Source) -> String {
  case source {
    log_lines.UpdaterLog -> "Updater log"
    log_lines.LaunchdLog -> "launchd log"
    log_lines.ServerLog -> "Server log"
    log_lines.DatabaseLog -> "Database log"
  }
}

/// One source: its name and path, what is known of its file or container, and
/// its lines.
fn log(source: Source, followed: Option(Followed)) -> Element(Message) {
  let #(path, status, entries, stale) = case followed {
    None -> #(None, [empty()], [], False)
    Some(followed) -> {
      let #(status, stale) = trouble_view(followed)
      #(Some(followed.path), status, followed.entries, stale)
    }
  }
  html.section([attribute.class("log")], [
    html.header([attribute.class("log-head")], [
      html.h3([], [html.text(title(source))]),
      ..case path {
        Some(path) -> [html.span([attribute.class("path")], [html.text(path)])]
        None -> []
      }
    ]),
    ..list.append(status, [lines(entries, stale)])
  ])
}

/// What a source says of its last read, and whether its lines are dimmed. A
/// container's lines are dimmed for every trouble: the lines of a container that
/// is gone or cannot be reached are not current. A file that is not there has
/// no lines to dim.
fn trouble_view(followed: Followed) -> #(List(Element(Message)), Bool) {
  case followed.trouble {
    None -> #(
      case followed.entries {
        [] -> [empty()]
        [_, ..] -> []
      },
      False,
    )
    Some(follow.NotThere) ->
      case container_log.container_name(followed.source) {
        Ok(name) -> #(
          [status("no container named " <> name, "role-warn")],
          True,
        )
        Error(Nil) -> #([status("no log yet", "role-warn")], False)
      }
    Some(follow.PodmanUnreachable(reason:)) -> #(
      [status("Podman is not reachable: " <> reason, "role-warn")],
      True,
    )
    Some(follow.Unreadable(reason:)) -> #(
      [status("cannot read: " <> reason, "role-bad")],
      True,
    )
  }
}

fn empty() -> Element(Message) {
  html.p([attribute.class("empty")], [html.text("No lines yet")])
}

fn status(words: String, role: String) -> Element(Message) {
  html.p([attribute.classes([#("status", True), #(role, True)])], [
    html.text(words),
  ])
}

fn lines(entries: List(Entry), stale: Bool) -> Element(Message) {
  html.div([attribute.class("log-body")], [
    keyed.ol(
      [attribute.classes([#("lines", True), #("stale", stale)])],
      list.map(entries, fn(entry) {
        #(int.to_string(entry.sequence), entry_view(entry))
      }),
    ),
  ])
}

fn entry_view(entry: Entry) -> Element(Message) {
  case entry {
    log_lines.Line(text:, level:, cut:, ..) ->
      html.li(
        [attribute.classes([#("line", True), #(role_class(level), True)])],
        case cut {
          True -> [
            html.text(text),
            html.span([attribute.class("cut")], [html.text(cut_words(text))]),
          ]
          False -> [html.text(text)]
        },
      )
    log_lines.Marker(mark:, ..) ->
      html.li([attribute.class("mark")], [
        html.text(case mark {
          log_lines.LogReplaced -> "the log was replaced"
          log_lines.LogCutShorter -> "the log was cut shorter"
          log_lines.ContainerReplaced -> "the container was replaced"
        }),
      ])
  }
}

/// What a cut entry says: a plain line holds no newline, so a cut entry that
/// holds one is a report, cut because a line of it or the report was too long.
fn cut_words(text: String) -> String {
  case string.contains(text, "\n") {
    True ->
      "report cut (a line at "
      <> int.to_string(log_lines.line_cap_bytes)
      <> " bytes, the report at "
      <> int.to_string(otp_report.report_cap_bytes)
      <> " bytes)"
    False ->
      "line cut at " <> int.to_string(log_lines.line_cap_bytes) <> " bytes"
  }
}

fn role_class(level: Level) -> String {
  case level {
    log_lines.LevelOk -> "role-ok"
    log_lines.LevelWarn -> "role-warn"
    log_lines.LevelBad -> "role-bad"
    log_lines.LevelInfo -> "role-text"
  }
}
