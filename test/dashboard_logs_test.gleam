//// The Logs page, read as the HTML text its runtime renders and as the page
//// list and routes that serve it. Expected values are the page's rules: a
//// line is text in the role its level gives (never markup), a log that is not
//// there or cannot be read says so with its path or reason, each entry is one
//// keyed element so a new line is one change and not a rewrite of the ring,
//// and the page has a document and a runtime route of its own under the key
//// prefix.

import genesis_prime/dashboard
import genesis_prime/dashboard/follow.{
  type Followed, Followed, NotThere, PodmanUnreachable, Unreadable,
}
import genesis_prime/dashboard/log_lines.{
  type Entry, DatabaseLog, LaunchdLog, Line, LogCutShorter, LogReplaced, Marker,
  ServerLog, UpdaterLog,
}
import genesis_prime/dashboard/logs.{Model}
import genesis_prime/dashboard/overview
import genesis_prime/dashboard/page
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import lustre/vdom/cache
import lustre/vdom/diff
import lustre/vdom/patch.{type Patch}
import owned_test

const updater_path = "/home/play-service.log"

const launchd_path = "/home/play-service.launchd.log"

fn updater(entries: List(Entry)) -> Followed {
  Followed(source: UpdaterLog, path: updater_path, trouble: None, entries:)
}

fn launchd(entries: List(Entry)) -> Followed {
  Followed(source: LaunchdLog, path: launchd_path, trouble: None, entries:)
}

/// The page's markup with each source's part apart: the parts begin at the
/// source's heading.
fn parts(model: logs.Model) -> List(String) {
  let assert [_, updater, launchd, server, database] =
    string.split(element.to_string(logs.view(model)), "<h3>")
  [updater, launchd, server, database]
}

fn count(text: String, word: String) -> Int {
  list.length(string.split(text, word)) - 1
}

/// The markup of the list item that holds `word`: from the item's opening to
/// its closing.
fn item_holding(part: String, word: String) -> String {
  let assert Ok(item) =
    string.split(part, "<li ")
    |> list.find(fn(item) { string.contains(item, word) })
    as { "no item holds " <> word }
  let assert [item, ..] = string.split(item, "</li>")
  item
}

pub fn the_logs_page_shows_each_source_and_each_line_in_the_role_of_its_level_test() -> Nil {
  use <- owned_test.run(5000)

  // Lines of each level: each line's text in the role its level gives, and the
  // source's name and path in its heading.
  let leveled =
    Model(
      updater: Some(
        updater([
          Line(0, "all went well", log_lines.LevelOk, False),
          Line(1, "something waits", log_lines.LevelWarn, False),
          Line(2, "something broke", log_lines.LevelBad, False),
          Line(3, "something happened", log_lines.LevelInfo, False),
        ]),
      ),
      launchd: Some(launchd([])),
      server: None,
      database: None,
    )
  let assert [updater_part, launchd_part, _, _] = parts(leveled)
  assert string.contains(updater_part, "Updater log")
  assert string.contains(updater_part, updater_path)
  assert string.contains(launchd_part, "launchd log")
  assert string.contains(launchd_part, launchd_path)
  let roles = [
    #("all went well", "role-ok"),
    #("something waits", "role-warn"),
    #("something broke", "role-bad"),
    #("something happened", "role-text"),
  ]
  list.each(roles, fn(row) {
    let item = item_holding(updater_part, row.0)
    assert string.contains(item, row.1) as row.0
    assert string.contains(item, "class=\"line ") as row.0
  })

  // A source with no lines yet, and a source not heard from yet.
  assert string.contains(launchd_part, "No lines yet")
  let unheard =
    parts(Model(updater: None, launchd: None, server: None, database: None))
  list.each(unheard, fn(part) {
    assert string.contains(part, "No lines yet")
  })

  // A log that is not there: its path and the words, no lines asked for.
  let missing =
    Model(
      updater: Some(
        Followed(
          source: UpdaterLog,
          path: updater_path,
          trouble: Some(NotThere),
          entries: [],
        ),
      ),
      launchd: None,
      server: None,
      database: None,
    )
  let assert [missing_part, _, _, _] = parts(missing)
  assert string.contains(missing_part, "no log yet")
  assert string.contains(missing_part, updater_path)

  // A log that cannot be read: the words and the reason, and the lines it
  // had stay, dimmed.
  let unreadable =
    Model(
      updater: Some(
        Followed(
          source: UpdaterLog,
          path: updater_path,
          trouble: Some(Unreadable("eacces")),
          entries: [Line(0, "an older line", log_lines.LevelInfo, False)],
        ),
      ),
      launchd: None,
      server: None,
      database: None,
    )
  let assert [unreadable_part, _, _, _] = parts(unreadable)
  assert string.contains(unreadable_part, "cannot read")
  assert string.contains(unreadable_part, "eacces")
  assert string.contains(unreadable_part, "an older line")
  assert string.contains(unreadable_part, "stale")
  assert !string.contains(updater_part, "stale")

  // A mark is shown as a mark and not as a line.
  let marked =
    Model(
      updater: Some(
        updater([
          Line(0, "before", log_lines.LevelInfo, False),
          Marker(1, LogReplaced),
          Marker(2, LogCutShorter),
          Line(3, "after", log_lines.LevelInfo, False),
        ]),
      ),
      launchd: None,
      server: None,
      database: None,
    )
  let assert [marked_part, _, _, _] = parts(marked)
  let replaced = item_holding(marked_part, "the log was replaced")
  assert string.contains(replaced, "mark")
  assert !string.contains(replaced, "class=\"line ")
  let shorter = item_holding(marked_part, "the log was cut shorter")
  assert string.contains(shorter, "mark")
  assert count(marked_part, "class=\"line ") == 2

  // Text is shown as text: markup in a line is escaped, and a line of 4,096
  // characters is in the page once, whole, with the word that says it was cut.
  let long = string.repeat("q", 4096)
  let hostile =
    Model(
      updater: Some(
        updater([
          Line(0, "<script>alert(1)</script>", log_lines.LevelInfo, False),
          Line(1, long, log_lines.LevelInfo, True),
        ]),
      ),
      launchd: None,
      server: None,
      database: None,
    )
  let assert [hostile_part, _, _, _] = parts(hostile)
  assert !string.contains(hostile_part, "<script>")
  assert string.contains(hostile_part, "&lt;script&gt;alert(1)&lt;/script&gt;")
  assert count(hostile_part, long) == 1
  assert string.contains(item_holding(hostile_part, long), "line cut")
  assert !string.contains(item_holding(hostile_part, "&lt;script"), "line cut")

  // Entries are keyed by sequence number: one new line is one change.
  assert_a_new_line_is_one_change_to_the_page()
}

/// How many changes a patch holds, its children's included.
fn patch_size(patch: Patch(message)) -> Int {
  list.length(patch.changes)
  + patch.removed
  + list.fold(patch.children, 0, fn(total, child) { total + patch_size(child) })
}

fn numbered_lines(first: Int, count: Int) -> List(Entry) {
  int.range(from: first, to: first + count, with: [], run: fn(all, number) {
    [
      Line(number, "line " <> int.to_string(number), log_lines.LevelInfo, False),
      ..all
    ]
  })
  |> list.reverse
}

/// The ring is full and a new line pushes the oldest out.
fn assert_a_new_line_is_one_change_to_the_page() -> Nil {
  // The ring is full: a new line pushes the oldest out. Keyed by sequence
  // number, the page changes by one removed element and one inserted; without
  // keys every element would be rewritten.
  let before =
    Model(
      updater: Some(updater(numbered_lines(0, log_lines.ring_lines))),
      launchd: None,
      server: None,
      database: None,
    )
  let after =
    Model(
      updater: Some(updater(numbered_lines(1, log_lines.ring_lines))),
      launchd: None,
      server: None,
      database: None,
    )
  let changed =
    diff.diff(cache.new(), logs.view(before), logs.view(after)).patch
  assert patch_size(changed) <= 3 as "a new line is not a rewrite of the ring"
  assert patch_size(changed) >= 1
}

pub fn the_logs_page_is_in_the_page_list_and_its_runtime_route_is_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let pages = dashboard.pages()
  assert pages == [overview.page(), logs.page()]
  assert list.map(pages, fn(page) { page.title }) == ["Overview", "Logs"]
  assert list.map(pages, fn(page) { page.key })
    == [page.OverviewKey, page.LogsKey]
    as "each page's socket is picked by its own key"

  let navigation =
    element.to_string(page.navigation(pages, current: logs.page()))
  assert string.contains(navigation, "href=\"logs\"")
  assert string.contains(navigation, "href=\"./\"")

  // Each document's runtime route is its own, and every link in it is
  // relative, so it stays under the key prefix the document was opened at.
  let overview_document = page.document(pages:, current: overview.page())
  let logs_document = page.document(pages:, current: logs.page())
  assert string.contains(overview_document, "route=\"ws\"")
  assert !string.contains(overview_document, "logs-ws")
  assert string.contains(logs_document, "route=\"logs-ws\"")
  list.each([overview_document, logs_document], fn(document) {
    list.each(["href=\"", "src=\"", "route=\""], fn(attribute) {
      let assert [_, ..values] = string.split(document, attribute)
      list.each(values, fn(value) {
        let assert [value, ..] = string.split(value, "\"")
        assert !string.starts_with(value, "/") as value
        assert !string.contains(value, "://") as value
      })
    })
  })
}

pub fn an_entry_of_several_lines_is_one_item_with_one_role_and_its_lines_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let report =
    "=CRASH REPORT==== 20-Nov-2026::14:10:51.212935 ===\n  crasher:\n    pid: <0.84.0>\n  neighbours:"
  let page =
    Model(
      updater: Some(
        updater([
          Line(0, "before", log_lines.LevelInfo, False),
          Line(1, report, log_lines.LevelBad, False),
          Marker(2, log_lines.ContainerReplaced),
          Line(
            3,
            "=ERROR REPORT====\n<script>alert(1)</script>",
            log_lines.LevelBad,
            False,
          ),
          Line(
            4,
            "=ERROR REPORT====\nthe rest was dropped",
            log_lines.LevelBad,
            True,
          ),
          Line(5, "after", log_lines.LevelInfo, False),
        ]),
      ),
      launchd: None,
      server: None,
      database: None,
    )
  let assert [part, _, _, _] = parts(page)

  // The report is one item, in the role of its level, with its lines in order.
  let item = item_holding(part, "=CRASH REPORT")
  assert count(part, "<li ") == 6
    as "one item for each entry, a report included"
  assert string.contains(item, "role-bad")
  assert string.contains(item, "class=\"line ")
  let in_order = [
    "=CRASH REPORT", "crasher:", "pid: &lt;0.84.0&gt;", "neighbours:",
  ]
  list.fold(in_order, 0, fn(from, word) {
    let after = string.drop_start(item, from)
    let assert Ok(#(before, _)) = string.split_once(after, word)
      as { word <> " is in the report, after the words before it" }
    from + string.length(before) + string.length(word)
  })

  // A mark of a replaced container is a mark, not a line.
  let replaced = item_holding(part, "the container was replaced")
  assert string.contains(replaced, "mark")
  assert !string.contains(replaced, "class=\"line ")

  // Markup inside a report is text.
  assert !string.contains(part, "<script>")
  assert string.contains(
    item_holding(part, "&lt;script&gt;alert(1)&lt;/script&gt;"),
    "role-bad",
  )

  // A report that was cut says so, in words that name the report's limit; a
  // report that was not cut says nothing.
  assert string.contains(
    item_holding(part, "the rest was dropped"),
    "report cut",
  )
  assert !string.contains(item, "cut")
  assert !string.contains(item_holding(part, "&lt;script"), "cut")
  assert !string.contains(item_holding(part, "after"), "cut")
}

const server_path = "podman logs genesis-play"

const database_path = "podman logs genesis-play-postgres"

fn container(
  source source: log_lines.Source,
  trouble trouble: option.Option(follow.Trouble),
  entries entries: List(Entry),
) -> Followed {
  let path = case source {
    ServerLog -> server_path
    DatabaseLog | UpdaterLog | LaunchdLog -> database_path
  }
  Followed(source:, path:, trouble:, entries:)
}

/// A row of the container sources: what the follower sent and the words, the
/// role and the dimming the page shows for it.
type TroubleRow {
  TroubleRow(
    name: String,
    trouble: option.Option(follow.Trouble),
    words: String,
    role: String,
    dimmed: Bool,
  )
}

pub fn a_container_log_says_why_it_is_stale_and_dims_its_lines_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    TroubleRow(
      "podman unreachable",
      Some(PodmanUnreachable("unable to connect to Podman socket")),
      "Podman is not reachable: unable to connect to Podman socket",
      "role-warn",
      True,
    ),
    TroubleRow(
      "the container is not there",
      Some(NotThere),
      "no container named genesis-play",
      "role-warn",
      True,
    ),
    TroubleRow(
      "the read failed",
      Some(Unreadable("timed out after 5 s")),
      "cannot read: timed out after 5 s",
      "role-bad",
      True,
    ),
    TroubleRow("a good read", None, "", "", False),
  ]
  list.each(rows, fn(row) {
    let model =
      Model(
        updater: None,
        launchd: None,
        server: Some(
          container(source: ServerLog, trouble: row.trouble, entries: [
            Line(0, "the ready line", log_lines.LevelInfo, False),
          ]),
        ),
        database: None,
      )
    let assert [_, _, part, _] = parts(model)
    assert string.contains(part, "the ready line") as row.name
    assert string.contains(part, server_path) as row.name
    assert string.contains(part, "stale") == row.dimmed as row.name
    case row.words {
      "" -> {
        assert !string.contains(part, "class=\"status") as row.name
        assert !string.contains(part, "No lines yet") as row.name
      }
      words -> {
        let assert Ok(status) =
          string.split(part, "<p ")
          |> list.find(fn(piece) { string.contains(piece, "status") })
          as row.name
        assert string.contains(status, words) as row.name
        assert string.contains(status, row.role) as row.name
      }
    }
  })

  // The database's own container has its own name in the words.
  let database_missing =
    Model(
      updater: None,
      launchd: None,
      server: None,
      database: Some(
        container(source: DatabaseLog, trouble: Some(NotThere), entries: []),
      ),
    )
  let assert [_, _, _, database_part] = parts(database_missing)
  assert string.contains(
    database_part,
    "no container named genesis-play-postgres",
  )
  assert string.contains(database_part, database_path)

  // A container not heard from yet has no lines yet, and a file's missing log
  // is still "no log yet" and not dimmed.
  let unheard =
    Model(updater: None, launchd: None, server: None, database: None)
  list.each(parts(unheard), fn(part) {
    assert string.contains(part, "No lines yet")
  })
  let file_missing =
    Model(
      updater: Some(
        Followed(
          source: UpdaterLog,
          path: updater_path,
          trouble: Some(NotThere),
          entries: [],
        ),
      ),
      launchd: None,
      server: None,
      database: None,
    )
  let assert [updater_part, _, _, _] = parts(file_missing)
  assert string.contains(updater_part, "no log yet")
  assert !string.contains(updater_part, "stale")

  // The four sources come in the order updater, launchd, server, database.
  let heard =
    Model(
      updater: Some(updater([])),
      launchd: Some(launchd([])),
      server: Some(container(source: ServerLog, trouble: None, entries: [])),
      database: Some(container(source: DatabaseLog, trouble: None, entries: [])),
    )
  let assert [
    updater_heading,
    launchd_heading,
    server_heading,
    database_heading,
  ] = parts(heard)
  assert string.starts_with(updater_heading, "Updater log")
  assert string.starts_with(launchd_heading, "launchd log")
  assert string.starts_with(server_heading, "Server log")
  assert string.starts_with(database_heading, "Database log")
  assert string.contains(updater_heading, updater_path)
  assert string.contains(server_heading, server_path)
  assert !string.contains(server_heading, "play-service.log")
}
