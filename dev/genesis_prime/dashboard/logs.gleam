//// The Logs page: the newest lines of the updater's log and of launchd's log,
//// each line in the role its words give, following new lines as they are
//// written.
////
//// ```text
//// follower (updater log)  ──Followed──►┐
////                                      ├─► runtime (one per tab) ──view──► tab
//// follower (launchd log)  ──Followed──►┘      subscribed in init, by server_component.select
//// ```
////
//// - A tab's runtime subscribes to both followers when it starts, and each
////   follower drops it when the runtime ends. A follower reads its file only
////   while a tab is subscribed.
//// - A source says "No lines yet" until its follower has sent lines, or has
////   read a file with none.
//// - A log that is not there says "no log yet", and one that cannot be read
////   says "cannot read" and the reason; the lines it had stay, dimmed.
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

import genesis_prime/dashboard/follow.{type Followed}
import genesis_prime/dashboard/log_lines.{type Entry, type Level, type Source}
import genesis_prime/dashboard/page.{type Page, Page}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/server_component

/// The followers a tab's runtime subscribes to: the updater's log and launchd's.
pub type Followers {
  Followers(updater: Subject(follow.Message), launchd: Subject(follow.Message))
}

/// What the Logs page holds: what each follower last sent, once it has.
pub type Model {
  Model(updater: Option(Followed), launchd: Option(Followed))
}

/// What the Logs page is told: a follower sent its log.
pub type Message {
  Received(followed: Followed)
}

/// The Logs page as an entry of the page list.
pub fn page() -> Page {
  Page(title: "Logs", path: "/logs")
}

/// The Logs page as a server component: its start argument is the followers it
/// subscribes to.
pub fn app() -> lustre.App(Followers, Model, Message) {
  lustre.application(init, update, view)
}

fn init(followers: Followers) -> #(Model, Effect(Message)) {
  #(
    Model(updater: None, launchd: None),
    server_component.select(fn(_dispatch, subject) {
      follow.subscribe(follower: followers.updater, subscriber: subject)
      follow.subscribe(follower: followers.launchd, subscriber: subject)
      process.new_selector() |> process.select_map(subject, Received)
    }),
  )
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  let Received(followed:) = message
  let model = case followed.source {
    log_lines.UpdaterLog -> Model(..model, updater: Some(followed))
    log_lines.LaunchdLog -> Model(..model, launchd: Some(followed))
  }
  #(model, effect.none())
}

/// The Logs page's content.
pub fn view(model: Model) -> Element(Message) {
  html.section([], [
    html.h2([], [html.text("Logs")]),
    html.div([attribute.class("logs")], [
      log(log_lines.UpdaterLog, model.updater),
      log(log_lines.LaunchdLog, model.launchd),
    ]),
  ])
}

fn title(source: Source) -> String {
  case source {
    log_lines.UpdaterLog -> "Updater log"
    log_lines.LaunchdLog -> "launchd log"
  }
}

/// One source: its name and path, what is known of its file, and its lines.
fn log(source: Source, followed: Option(Followed)) -> Element(Message) {
  let #(path, status, entries, stale) = case followed {
    None -> #(None, [empty()], [], False)
    Some(followed) -> {
      let path = Some(followed.path)
      case followed.trouble {
        None -> #(
          path,
          case followed.entries {
            [] -> [empty()]
            [_, ..] -> []
          },
          followed.entries,
          False,
        )
        Some(follow.NotThere) -> #(
          path,
          [status("no log yet", "role-warn")],
          followed.entries,
          False,
        )
        Some(follow.Unreadable(reason:)) -> #(
          path,
          [status("cannot read: " <> reason, "role-bad")],
          followed.entries,
          True,
        )
      }
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
            html.span([attribute.class("cut")], [
              html.text(
                "line cut at "
                <> int.to_string(log_lines.line_cap_bytes)
                <> " bytes",
              ),
            ]),
          ]
          False -> [html.text(text)]
        },
      )
    log_lines.Marker(mark:, ..) ->
      html.li([attribute.class("mark")], [
        html.text(case mark {
          log_lines.LogReplaced -> "the log was replaced"
          log_lines.LogCutShorter -> "the log was cut shorter"
        }),
      ])
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
