//// The Logs page, read as the HTML text its runtime renders and as the page
//// list and routes that serve it. Expected values are the page's rules: a
//// line is text in the role its level gives (never markup), a log that is not
//// there or cannot be read says so with its path or reason, each entry is one
//// keyed element so a new line is one change and not a rewrite of the ring,
//// and the page has a document and a runtime route of its own under the key
//// prefix.

import genesis_prime/dashboard
import genesis_prime/dashboard/follow.{
  type Followed, Followed, NotThere, Unreadable,
}
import genesis_prime/dashboard/log_lines.{
  type Entry, LaunchdLog, Line, LogCutShorter, LogReplaced, Marker, UpdaterLog,
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
  let assert [_, updater, launchd] =
    string.split(element.to_string(logs.view(model)), "<h3>")
  [updater, launchd]
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
    )
  let assert [updater_part, launchd_part] = parts(leveled)
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
  let unheard = parts(Model(updater: None, launchd: None))
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
    )
  let assert [missing_part, _] = parts(missing)
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
    )
  let assert [unreadable_part, _] = parts(unreadable)
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
    )
  let assert [marked_part, _] = parts(marked)
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
    )
  let assert [hostile_part, _] = parts(hostile)
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
    )
  let after =
    Model(
      updater: Some(updater(numbered_lines(1, log_lines.ring_lines))),
      launchd: None,
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
