//// The lines the Logs page shows, made from the bytes of a log file. Expected
//// values are the scripts' own output (`dev/play_service/lib.sh` writes one
//// stamped line a message, and the real logs hold every shape the level rows
//// name), the project's text-only rule for the dashboard (a line is text,
//// whatever its bytes), and the invariant that how a read was split into
//// chunks never changes the lines.

import dashboard_otp_log_support as support
import genesis_prime/dashboard/log_lines.{
  type Level, type Lines, LaunchdLog, LevelBad, LevelInfo, LevelOk, LevelWarn,
  Line, LogCutShorter, LogReplaced, Marker, UpdaterLog,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import owned_test
import qcheck

const cap = 4096

fn bytes(text: String) -> BitArray {
  bit_array.from_string(text)
}

/// Lines of the updater's log made from the chunks, in order.
fn fed(chunks: List(BitArray)) -> Lines {
  list.fold(chunks, log_lines.new(UpdaterLog), log_lines.feed)
}

/// Each entry's text, marks left out.
fn texts(lines: Lines) -> List(String) {
  list.filter_map(log_lines.entries(lines), fn(entry) {
    case entry {
      Line(text:, ..) -> Ok(text)
      Marker(..) -> Error(Nil)
    }
  })
}

/// Each line's text with whether it was shown cut.
fn shown(lines: Lines) -> List(#(String, Bool)) {
  list.filter_map(log_lines.entries(lines), fn(entry) {
    case entry {
      Line(text:, cut:, ..) -> Ok(#(text, cut))
      Marker(..) -> Error(Nil)
    }
  })
}

pub fn bytes_give_whole_lines_and_the_partial_one_is_kept_test() -> Nil {
  use <- owned_test.run(5000)
  // The row: what the chunks are, the lines they give and the bytes still
  // carried for a line that has not ended.
  let rows = [
    #("one full line", [bytes("a\n")], ["a"], 0),
    #("two lines in one chunk", [bytes("a\nb\n")], ["a", "b"], 0),
    #("a line ended in the next chunk", [bytes("ab"), bytes("c\n")], ["abc"], 0),
    #("no newline, then an empty chunk", [bytes("abc"), <<>>], [], 3),
    #(
      "the cut falls inside a 3-byte character",
      [<<"x":utf8, 0xE2, 0x82>>, <<0xAC, "\n":utf8>>],
      ["x€"],
      0,
    ),
    #(
      "a carriage return before the newline is not text",
      [bytes("a\r\n")],
      ["a"],
      0,
    ),
    #(
      "a carriage return that ends one chunk and a newline that starts the next",
      [bytes("a\r"), bytes("\n")],
      ["a"],
      0,
    ),
    #("blank lines are kept", [bytes("a\n\nb\n")], ["a", "", "b"], 0),
    #("a chunk that is only a newline", [bytes("\n")], [""], 0),
    #("zero bytes", [<<>>], [], 0),
    #(
      "a line after a partial one",
      [bytes("a\nb"), bytes("c\nd")],
      ["a", "bc"],
      1,
    ),
  ]
  list.each(rows, fn(row) {
    let #(name, chunks, expected, carried) = row
    let lines = fed(chunks)
    assert texts(lines) == expected as name
    assert log_lines.carried_bytes(lines) == carried as name
  })
}

pub fn a_line_over_the_cap_is_shown_cut_once_and_the_rest_of_it_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  assert log_lines.line_cap_bytes == cap
  let full = string.repeat("x", cap)
  let rows = [
    #("exactly the cap", [bytes(full <> "\n")], [#(full, False)]),
    #("the cap plus one", [bytes(full <> "x\n")], [#(full, True)]),
    #(
      "ten times the cap in five chunks with no newline, then a newline and a line",
      list.append(list.repeat(bytes(string.repeat("y", 2 * cap)), 5), [
        bytes("\nnext\n"),
      ]),
      [#(string.repeat("y", cap), True), #("next", False)],
    ),
    #(
      "the cap falls inside a character: cut back to the character",
      [bytes(string.repeat("x", cap - 1) <> "€\n")],
      [#(string.repeat("x", cap - 1), True)],
    ),
    #(
      "a line of one byte, a mebibyte long",
      [bytes(string.repeat("z", 1_048_576)), bytes("\n")],
      [#(string.repeat("z", cap), True)],
    ),
  ]
  list.each(rows, fn(row) {
    let #(name, chunks, expected) = row
    // After each chunk the bytes carried stay within the cap.
    let lines =
      list.fold(chunks, log_lines.new(UpdaterLog), fn(lines, chunk) {
        let lines = log_lines.feed(lines, chunk)
        assert log_lines.carried_bytes(lines) <= cap as name
        lines
      })
    assert shown(lines) == expected as name
  })
}

pub fn a_line_is_shown_as_text_whatever_its_bytes_are_test() -> Nil {
  use <- owned_test.run(5000)
  let escape = <<0x1B>>
  let rows = [
    #(
      "the updater's real shape: colour codes around a source position",
      bit_array.concat([
        bytes("genesis_prime.load_content"),
        escape,
        bytes("[90m src/genesis_prime.gleam:137"),
        escape,
        bytes("[0m"),
      ]),
      "genesis_prime.load_content src/genesis_prime.gleam:137",
    ),
    #("a lone escape", bit_array.concat([bytes("a"), escape, bytes("b")]), "ab"),
    #(
      "an escape and a bracket with no end",
      bit_array.concat([bytes("a"), escape, bytes("[31")]),
      "a",
    ),
    #(
      "an escape sequence cut by a byte it cannot hold",
      bit_array.concat([bytes("a"), escape, bytes("[3"), <<0x01>>, bytes("b")]),
      "ab",
    ),
    #("a NUL", <<"a":utf8, 0, "b":utf8>>, "ab"),
    #("a BEL", <<"a":utf8, 7, "b":utf8>>, "ab"),
    #("a DEL", <<"a":utf8, 0x7F, "b":utf8>>, "ab"),
    #("a C1 control (U+0085)", <<"a":utf8, 0xC2, 0x85, "b":utf8>>, "ab"),
    #("a tab is kept", bytes("a\tb"), "a\tb"),
    #("a byte that is not UTF-8", <<"a":utf8, 0xFF, "b":utf8>>, "a\u{FFFD}b"),
    #("a character is kept", bytes("é€"), "é€"),
    #(
      "markup is not changed here: the view makes it text",
      bytes("<script>alert(1)</script>"),
      "<script>alert(1)</script>",
    ),
  ]
  list.each(rows, fn(row) {
    let #(name, line, expected) = row
    let lines = fed([line, bytes("\n")])
    assert texts(lines) == [expected] as name
  })
}

pub fn the_ring_keeps_the_newest_lines_in_order_and_counts_what_it_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  assert log_lines.ring_lines == 500
  let numbered = fn(count: Int) -> BitArray {
    support.numbers(first: 0, last: count - 1)
    |> list.map(fn(number) { "line " <> int.to_string(number) <> "\n" })
    |> string.concat
    |> bytes
  }
  let sequences = fn(lines: Lines) -> List(Int) {
    list.map(log_lines.entries(lines), fn(entry) { entry.sequence })
  }

  // Fewer than the cap and exactly the cap keep every line.
  let few = fed([numbered(3)])
  assert texts(few) == ["line 0", "line 1", "line 2"]
  assert sequences(few) == [0, 1, 2]
  let exact = fed([numbered(500)])
  assert list.length(log_lines.entries(exact)) == 500
  assert sequences(exact) == support.numbers(first: 0, last: 499)

  // The cap plus 10,000 in one call keeps the last cap lines, in order, and
  // the first of them is numbered after the 10,000 that were dropped.
  let many = fed([numbered(10_500)])
  assert texts(many)
    == list.map(support.numbers(first: 10_000, last: 10_499), fn(number) {
      "line " <> int.to_string(number)
    })
  assert sequences(many) == support.numbers(first: 10_000, last: 10_499)

  // A mark takes one slot and is not a line.
  let marked = log_lines.mark(fed([numbered(499)]), LogReplaced)
  assert list.length(log_lines.entries(marked)) == 500
  assert list.length(texts(marked)) == 499
  let assert Ok(last) = list.last(log_lines.entries(marked))
  assert last == Marker(sequence: 499, mark: LogReplaced)
  let pushed = log_lines.feed(marked, bytes("one more\n"))
  assert list.length(log_lines.entries(pushed)) == 500
  let assert [first, ..] = log_lines.entries(pushed)
  assert first.sequence == 1
    as "the oldest line went out when a new entry came in"
  assert log_lines.mark(few, LogCutShorter)
    |> log_lines.entries
    |> list.last
    == Ok(Marker(sequence: 3, mark: LogCutShorter))

  // A mark ends the partial line before it: the next bytes start a line.
  let after = fed([bytes("par")]) |> log_lines.mark(LogCutShorter)
  assert texts(log_lines.feed(after, bytes("x\n"))) == ["x"]
  assert log_lines.carried_bytes(after) == 0
}

pub fn a_line_has_the_level_its_words_give_test() -> Nil {
  use <- owned_test.run(5000)
  let stamp = "2026-11-08 19:58:30 play-service: "
  let sha = "9e559d87a4114fec0419cc01cd2865f1f1fa7eea"
  let updater = fn(message: String, level: Level) {
    #(UpdaterLog, stamp <> message, level)
  }
  let rows = [
    // The updater's log, bad.
    updater(
      "genesis-play did not come up: state running, exit code 0, restarted 1 times; its last lines: |stacktrace:|  genesis_prime.load_content src/genesis_prime.gleam:137",
      LevelBad,
    ),
    updater(
      "genesis-play did not come up: state exited, exit code 0, restarted 0 times; its last lines: =INFO REPORT==== 9-Nov-2026::09:37:59 ===|SIGTERM received - shutting down||",
      LevelBad,
    ),
    updater(sha <> " did not come up either", LevelBad),
    updater("genesis-play said no ready line in 300 asks", LevelBad),
    updater(
      "building " <> sha <> " failed; the running server is left as it was",
      LevelBad,
    ),
    updater(
      "could not read main from https://github.com/jamespdaily/the-genesis-prime.git; nothing built",
      LevelBad,
    ),
    updater(
      "could not ask GitHub for the check of " <> sha <> "; nothing done for it",
      LevelBad,
    ),
    // The updater's log, warn.
    updater(
      "the check of "
        <> sha
        <> " has not passed or has not finished; nothing done for it",
      LevelWarn,
    ),
    updater(
      "a live session holds /Users/jimd/.genesis-prime/live.lock; nothing done",
      LevelWarn,
    ),
    updater("another update runs (process 88288); nothing done", LevelWarn),
    updater("the Podman machine is not running; starting it", LevelWarn),
    updater(
      "a live session took the lock during the build; "
        <> sha
        <> " is not migrated or deployed",
      LevelWarn,
    ),
    updater(
      sha
        <> " holds no release/Containerfile, so it is not deployed and not asked about again",
      LevelWarn,
    ),
    // The updater's log, ok.
    updater(sha <> " came up", LevelOk),
    updater(sha <> " is back up", LevelOk),
    updater("genesis-play started", LevelOk),
    updater("alert sent to the channel", LevelOk),
    // The updater's log, info.
    updater("genesis-play stopped", LevelInfo),
    updater("building genesis-play:" <> sha, LevelInfo),
    updater(
      "replacing genesis-play: "
        <> sha
        <> " at 192.168.8.238 (was 3a7a04d4cce51f710597b495627532f3e0806ebe)",
      LevelInfo,
    ),
    updater(
      "scripts installed in /Users/jimd/.genesis-prime/play-service/bin; main is read from https://github.com/jamespdaily/the-genesis-prime.git",
      LevelInfo,
    ),
    updater(
      "launchd agent loaded: /Users/jimd/Library/LaunchAgents/com.genesis-prime.play-service.plist",
      LevelInfo,
    ),
    updater(
      "the container's genesis_play holds 12 tables; not seeded",
      LevelInfo,
    ),
    updater(
      "the pod's genesis_play is empty; seeding it from the local genesis_play",
      LevelInfo,
    ),
    updater("starting genesis-play-postgres", LevelInfo),
    updater(
      "applying the migrations of " <> sha <> " to genesis_play",
      LevelInfo,
    ),
    // A shape no word names is plain, in either log.
    #(UpdaterLog, "something a later script says", LevelInfo),
    #(LaunchdLog, "something a later tool says", LevelInfo),
    #(UpdaterLog, "", LevelInfo),
    // The launchd log: git, podman and gh print their own words.
    #(
      LaunchdLog,
      "fatal: unable to access 'https://github.com/jamespdaily/the-genesis-prime.git/': Could not resolve host: github.com",
      LevelBad,
    ),
    #(
      LaunchdLog,
      "Error: building at STEP \"RUN gleam deps download\": while running runtime: exit status 1",
      LevelBad,
    ),
    #(
      LaunchdLog,
      "gh: API rate limit exceeded for user ID 478289. If you reach out to GitHub Support for help, please include the request ID EEC1:11513C",
      LevelBad,
    ),
    #(
      LaunchdLog,
      "/Users/jimd/.genesis-prime/play-service/bin/lib.sh: line 74: GENESIS_PLAY_ADDRESS: set GENESIS_PLAY_ADDRESS in /Users/jimd/.genesis-prime/env.sh",
      LevelBad,
    ),
    #(
      LaunchdLog,
      "check_image: genesis-play:"
        <> sha
        <> " holds none of the 16044 files in /Users/jimd/.genesis-prime/tables",
      LevelInfo,
    ),
    #(LaunchdLog, "applying 0017_character_health_dead_is_0", LevelInfo),
    #(LaunchdLog, "", LevelInfo),
    #(LaunchdLog, "see the manual: line of text", LevelInfo),
    // The updater's own lines also reach launchd's log, stamped.
    #(
      LaunchdLog,
      stamp
        <> "a live session holds /Users/jimd/.genesis-prime/live.lock; nothing done",
      LevelWarn,
    ),
    #(LaunchdLog, stamp <> sha <> " did not come up either", LevelBad),
    // The container's own lines never change what the updater said.
    updater(
      "genesis-play did not come up: state running, exit code 0, restarted 1 times; its last lines: |genesis-play started|alert sent",
      LevelBad,
    ),
    updater(
      "genesis-play stopped; its last lines: |a live session holds the lock; nothing done",
      LevelInfo,
    ),
    // The rules for launchd's own words do not apply to the updater's log.
    #(UpdaterLog, "Error: a line the updater never writes", LevelInfo),
  ]
  list.each(rows, fn(row) {
    let #(source, text, expected) = row
    assert log_lines.level(source, text) == expected as text
  })
}

/// The bytes the property draws from: lines end often, and each of the other
/// bytes is one the logs or a hostile writer may hold (an escape and its
/// bracket, a control byte, the three bytes of a euro sign, a byte that is not
/// UTF-8).
fn alphabet(index: Int) -> Int {
  let assert Ok(byte) =
    list.drop(
      [0x0A, 0x0A, 0x0D, 0x1B, 0x5B, 0x41, 0x00, 0x20, 0xE2, 0x82, 0xAC, 0xFF],
      index,
    )
    |> list.first
  byte
}

pub fn the_lines_do_not_depend_on_how_the_bytes_were_split_test() -> Nil {
  use <- owned_test.run(60_000)
  // Runs of one byte, up to past the cap, so the long-line cut is reached.
  let draws =
    qcheck.tuple2(
      qcheck.list_from(qcheck.tuple2(
        qcheck.bounded_int(from: 0, to: 11),
        qcheck.bounded_int(from: 1, to: 2500),
      )),
      qcheck.list_from(qcheck.bounded_int(from: 0, to: 20_000)),
    )
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(100),
    draws,
    fn(drawn) {
      let #(runs, points) = drawn
      let whole =
        list.map(runs, fn(run) {
          let #(index, length) = run
          list.repeat(<<alphabet(index):8>>, length) |> bit_array.concat
        })
        |> bit_array.concat
      support.reads_do_not_change_the_entries(
        source: UpdaterLog,
        bytes: whole,
        points:,
        cap_bytes: cap,
      )
    },
  )
}
