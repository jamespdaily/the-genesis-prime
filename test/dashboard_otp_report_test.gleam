//// The OTP reports and plain lines of a container's log as the Logs page
//// shows them: a report is one entry from its header to the next header or
//// the blank line that ends it, in the level OTP logged it at, and a plain
//// line has the level its words give. Expected values are OTP 29's own
//// logger (`logger_formatter.erl:589-612` writes the header; `proc_lib.erl:954`,
//// `supervisor.erl:319` and `supervisor.erl:2323` log the three titles that
//// are not a level word), the captures of this server's own image in
//// `test/fixture/otp_log`, and the project's rule that a shape no word names is
//// `LevelInfo`.

import dashboard_otp_log_support as support
import genesis_prime/dashboard/log_lines.{
  type Level, DatabaseLog, LevelBad, LevelInfo, LevelWarn, Line, ServerLog,
  UpdaterLog,
}
import genesis_prime/dashboard/otp_report.{
  type Title, SeverityBad, SeverityInfo, SeverityWarn, TitleAlert, TitleCrash,
  TitleCritical, TitleDebug, TitleEmergency, TitleError, TitleInfo, TitleNotice,
  TitleOther, TitleProgress, TitleSupervisor, TitleWarning,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import owned_test
import qcheck

const report_cap = 16_384

const stamp = "20-Nov-2026::14:10:12.631981 ==="

fn header_of(title: String) -> String {
  "=" <> title <> " REPORT==== " <> stamp
}

pub fn a_header_line_is_found_and_names_its_title_test() -> Nil {
  use <- owned_test.run(5000)
  let titled = fn(title: String, expected: Title) {
    #(title, header_of(title), Ok(expected))
  }
  let rows = [
    titled("NOTICE", TitleNotice),
    titled("WARNING", TitleWarning),
    titled("INFO", TitleInfo),
    titled("ERROR", TitleError),
    titled("CRITICAL", TitleCritical),
    titled("ALERT", TitleAlert),
    titled("EMERGENCY", TitleEmergency),
    titled("DEBUG", TitleDebug),
    titled("CRASH", TitleCrash),
    titled("SUPERVISOR", TitleSupervisor),
    titled("PROGRESS", TitleProgress),
    titled("A TITLE NO TABLE NAMES", TitleOther("A TITLE NO TABLE NAMES")),
    #(
      "a day of one digit, as the updater's log holds it",
      "=INFO REPORT==== 9-Nov-2026::09:37:59.689355 ===",
      Ok(TitleInfo),
    ),
    #(
      "a day of two digits",
      "=INFO REPORT==== 19-Nov-2026::09:37:59.689355 ===",
      Ok(TitleInfo),
    ),
    #(
      "the time given in UTC",
      "=INFO REPORT==== 9-Nov-2026::09:37:59.689355 UTC ===",
      Ok(TitleInfo),
    ),
    #("no ====", "=ERROR REPORT 20-Nov-2026::14:10:12.633320 ===", Error(Nil)),
    #("an indented header", " " <> header_of("ERROR"), Error(Nil)),
    #("a body line that starts with =", "=== a line of a table", Error(Nil)),
    #(
      "a line that holds a header after other text",
      "its last lines: " <> header_of("INFO"),
      Error(Nil),
    ),
    #(
      "the Postgres line shape",
      "2026-11-09 00:56:22.092 UTC [69] LOG:  checkpoint starting: time",
      Error(Nil),
    ),
    #("an empty line", "", Error(Nil)),
    #("a plain line of the capture", "Error! Failed to eval: ", Error(Nil)),
    #("a header with no stamp", "=ERROR REPORT====", Error(Nil)),
  ]
  list.each(rows, fn(row) {
    let #(name, line, expected) = row
    assert otp_report.header(line) == expected as name
  })
  // Every header of the captures is found, each plain line of them is not.
  let found =
    list.flat_map(
      [
        "c1_default_formatter_reports.txt",
        "c2_progress_crash_supervisor_plain.txt",
        "c5b_pgo_crash_long_password_wraps.txt",
      ],
      fn(name) {
        list.filter(support.capture(name), fn(line) {
          otp_report.header(line) != Error(Nil)
        })
      },
    )
  assert list.all(found, fn(line) { string.starts_with(line, "=") })
  assert list.length(found) == 8 + 7 + 3
    as "the captures hold eight, seven and three reports"
}

pub fn a_title_has_the_level_otp_logs_that_report_at_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(TitleCrash, SeverityBad, "proc_lib.erl:954 logs a crash with ?LOG_ERROR"),
    #(
      TitleSupervisor,
      SeverityBad,
      "supervisor.erl:319 logs a supervisor report with ?LOG_ERROR",
    ),
    #(
      TitleProgress,
      SeverityInfo,
      "supervisor.erl:2323 logs a progress report with ?LOG_INFO",
    ),
    #(TitleEmergency, SeverityBad, "a level word at error or above"),
    #(TitleAlert, SeverityBad, "a level word at error or above"),
    #(TitleCritical, SeverityBad, "a level word at error or above"),
    #(TitleError, SeverityBad, "a level word at error or above"),
    #(TitleWarning, SeverityWarn, "the warning level"),
    #(TitleNotice, SeverityInfo, "below warning"),
    #(TitleInfo, SeverityInfo, "below warning"),
    #(TitleDebug, SeverityInfo, "below warning"),
    #(TitleOther("A TITLE NO TABLE NAMES"), SeverityInfo, "no word names it"),
  ]
  list.each(rows, fn(row) {
    let #(title, expected, reason) = row
    assert otp_report.severity(title) == expected as reason
  })
  // The entry of an unknown title is one entry, in the level of no word.
  let lines =
    support.fed(source: ServerLog, lines: [
      header_of("A TITLE NO TABLE NAMES"),
      "x",
    ])
  assert support.shown(lines)
    == [#(header_of("A TITLE NO TABLE NAMES") <> "\nx", LevelInfo)]
}

/// The entries of a source after one read of these lines, each as its first
/// line, how many lines it holds, and its level.
fn grouped(
  source: log_lines.Source,
  lines: List(String),
) -> List(#(String, Int, Level)) {
  list.map(support.shown(support.fed(source: source, lines: lines)), fn(entry) {
    let #(text, level) = entry
    let held = string.split(text, "\n")
    let assert [first, ..] = held
    #(first, list.length(held), level)
  })
}

fn crash_header() -> String {
  header_of("CRASH")
}

pub fn a_report_is_one_entry_from_its_header_to_the_next_header_or_the_blank_line_that_ends_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let error = header_of("ERROR")
  let rows = [
    #(
      "a one-line body (C1: a notice line)",
      [header_of("NOTICE"), "a notice line"],
      [#(header_of("NOTICE"), 2, LevelInfo)],
    ),
    #(
      "a two-line body",
      [error, "** State machine terminating", "** Last event = boom"],
      [#(error, 3, LevelBad)],
    ),
    #(
      "a map report with an indented body (C1)",
      [error, "    what: a map report", "    n: 1"],
      [#(error, 3, LevelBad)],
    ),
    #(
      "the Error in process report ends in a blank line (C1)",
      [error, "Error in process <0.83.0> with exit value:", "{boom,[]}", ""],
      [#(error, 3, LevelBad)],
    ),
    #(
      "a report followed at once by a header",
      [header_of("WARNING"), "a warning with text", header_of("INFO"), "a line"],
      [
        #(header_of("WARNING"), 2, LevelWarn),
        #(header_of("INFO"), 2, LevelInfo),
      ],
    ),
    #("a header alone is a one-line entry", [error], [#(error, 1, LevelBad)]),
    #(
      "a report, a blank line, then the plain line to stderr (C2): the plain line is its own entry",
      [
        header_of("PROGRESS"),
        "    supervisor: {<0.83.0>,s4sup}",
        "",
        "to stderr",
      ],
      [#(header_of("PROGRESS"), 2, LevelInfo), #("to stderr", 1, LevelInfo)],
    ),
    #(
      "blank lines in a row: the first ends the report, the rest are plain empty lines",
      [error, "a body", "", "", ""],
      [#(error, 2, LevelBad), #("", 1, LevelInfo), #("", 1, LevelInfo)],
    ),
    #(
      "lines before the first header (a tail that began inside a report) are plain entries",
      ["    n: 1", "  neighbours:", "", "after", error, "body"],
      [
        #("    n: 1", 1, LevelInfo),
        #("  neighbours:", 1, LevelInfo),
        #("", 1, LevelInfo),
        #("after", 1, LevelInfo),
        #(error, 2, LevelBad),
      ],
    ),
    #("a body line that starts with = is body", [error, "=== a table", "x"], [
      #(error, 3, LevelBad),
    ]),
  ]
  list.each(rows, fn(row) {
    let #(name, lines, expected) = row
    assert grouped(ServerLog, lines) == expected as name
  })
  assert_the_captures_group_as_their_reports_do()
  assert_a_long_report_is_cut_once_and_the_next_one_is_whole()
  assert_a_report_grows_in_place_across_reads()
}

/// Each report of C1, C2 and C5b is one entry in the level of its title; the
/// plain lines between them are entries of their own.
fn assert_the_captures_group_as_their_reports_do() -> Nil {
  // C1: the first six reports (the map and format variants), then the
  // Error in process report, the crash report of 27 lines, and plain lines.
  let first = fn(name: String) {
    list.map(grouped(ServerLog, support.capture(name)), fn(entry) {
      #(entry.0, entry.1, entry.2)
    })
  }
  let c1 = first("c1_default_formatter_reports.txt")
  let reports = list.filter(c1, fn(entry) { string.starts_with(entry.0, "=") })
  assert list.map(reports, fn(entry) { #(entry.1, entry.2) })
    == [
      #(2, LevelInfo),
      #(2, LevelWarn),
      #(2, LevelInfo),
      #(2, LevelBad),
      #(3, LevelBad),
      #(2, LevelBad),
      #(3, LevelBad),
      #(27, LevelBad),
    ]
    as "C1's eight reports: line counts and levels"
  let plain = list.filter(c1, fn(entry) { !string.starts_with(entry.0, "=") })
  assert list.all(plain, fn(entry) { entry.1 == 1 })
    as "every line after C1's crash report's blank line is a plain entry"
  assert list.contains(plain, #(
    "Crash dump is being written to: erl_crash.dump...done",
    1,
    LevelBad,
  ))

  // C2: PROGRESS, CRASH, SUPERVISOR in sequence, then the same again after the
  // restart, then SUPERVISOR for the shutdown, and the two plain lines.
  let c2 = first("c2_progress_crash_supervisor_plain.txt")
  assert c2
    == [
      #("=PROGRESS REPORT==== 20-Nov-2026::14:10:51.209437 ===", 9, LevelInfo),
      #("=CRASH REPORT==== 20-Nov-2026::14:10:51.212935 ===", 18, LevelBad),
      #("=SUPERVISOR REPORT==== 20-Nov-2026::14:10:51.227194 ===", 11, LevelBad),
      #("=PROGRESS REPORT==== 20-Nov-2026::14:10:51.227275 ===", 9, LevelInfo),
      #("=CRASH REPORT==== 20-Nov-2026::14:10:51.419133 ===", 18, LevelBad),
      #("=SUPERVISOR REPORT==== 20-Nov-2026::14:10:51.419318 ===", 11, LevelBad),
      #("=SUPERVISOR REPORT==== 20-Nov-2026::14:10:51.419360 ===", 11, LevelBad),
      #("to stderr", 1, LevelInfo),
      #("to stdout", 1, LevelInfo),
    ]
    as "C2's reports in sequence, each whole, and the plain lines apart"

  // C5b: the three reports of one pgo crash.
  let c5b = first("c5b_pgo_crash_long_password_wraps.txt")
  assert c5b
    == [
      #("=ERROR REPORT==== 20-Nov-2026::09:13:33.274688 ===", 34, LevelBad),
      #("=CRASH REPORT==== 20-Nov-2026::09:13:33.274893 ===", 33, LevelBad),
      #("=SUPERVISOR REPORT==== 20-Nov-2026::09:13:33.276800 ===", 36, LevelBad),
    ]
}

/// A body over the cap is shown cut once and the next report is whole; a body
/// line of 20 KB is cut by the line cap inside the report.
fn assert_a_long_report_is_cut_once_and_the_next_one_is_whole() -> Nil {
  let line = string.repeat("b", 1000)
  // A report a little over the cap (17 lines of 1,000 bytes and a header of
  // 51) is cut to the cap, and one a little under it is whole.
  let just_over =
    support.fed(source: ServerLog, lines: [
      header_of("ERROR"),
      ..list.repeat(line, 17)
    ])
  let assert [Line(text: over_text, cut: True, ..)] =
    log_lines.entries(just_over)
  assert bit_array.byte_size(bit_array.from_string(over_text)) == report_cap
  let just_under =
    support.fed(source: ServerLog, lines: [
      header_of("ERROR"),
      ..list.repeat(line, 16)
    ])
  let assert [Line(cut: False, ..)] = log_lines.entries(just_under)
  // A report of exactly the cap whose short password the mark lengthens is cut
  // again after the mask, and its text still fits the cap.
  let key_line = "password => \"x\""
  let without_padding =
    [header_of("ERROR"), ..list.repeat(line, 16)]
    |> list.append(["", key_line])
    |> string.join("\n")
  let padding =
    string.repeat("p", report_cap - string.byte_size(without_padding))
  let at_the_cap_lines =
    list.flatten([
      [header_of("ERROR")],
      list.repeat(line, 16),
      [padding, key_line],
    ])
  assert bit_array.byte_size(
      bit_array.from_string(string.join(at_the_cap_lines, "\n")),
    )
    == report_cap
    as "the report is exactly the cap before its mask"
  let assert [Line(text: masked_text, cut: True, ..)] =
    log_lines.entries(support.fed(source: ServerLog, lines: at_the_cap_lines))
  assert bit_array.byte_size(bit_array.from_string(masked_text)) <= report_cap
    as "the masked report is cut to the cap again"
  assert !string.contains(masked_text, "\"x\"")
  let long_body = list.repeat(line, 40)
  let lines =
    list.flatten([
      [header_of("ERROR")],
      long_body,
      [header_of("INFO"), "short"],
    ])
  let assert [long, next] =
    log_lines.entries(support.fed(source: ServerLog, lines: lines))
  let assert Line(text: long_text, cut: True, level: LevelBad, ..) = long
  assert bit_array.byte_size(bit_array.from_string(long_text)) <= report_cap
  assert string.starts_with(long_text, header_of("ERROR") <> "\n" <> line)
  assert string.length(long_text) > report_cap - 1100
    as "the report is cut at the cap, not much before it"
  let assert Line(text: next_text, cut: False, level: LevelInfo, ..) = next
  assert next_text == header_of("INFO") <> "\nshort"

  // A cut report drops its body up to the blank line; a plain line after it
  // is its own entry.
  let blank_ended =
    list.flatten([[header_of("ERROR")], long_body, [""], ["after"]])
  let assert [_, after] =
    log_lines.entries(support.fed(source: ServerLog, lines: blank_ended))
  let assert Line(text: "after", level: LevelInfo, ..) = after

  // A body line of 20 KB: the line cap cuts it, so the report holds the cut
  // line and says it was cut, and the next line still belongs to the report.
  let huge = string.repeat("x", 20_000)
  let assert [only] =
    log_lines.entries(
      support.fed(source: ServerLog, lines: [header_of("ERROR"), huge, "tail"]),
    )
  let assert Line(text:, cut: True, ..) = only
  assert string.contains(text, string.repeat("x", 4096))
  assert !string.contains(text, string.repeat("x", 4097))
  assert string.ends_with(text, "\ntail")
  Nil
}

/// A read that ends inside a report: the next read goes on with the same
/// entry, under the same sequence number, with more text.
fn assert_a_report_grows_in_place_across_reads() -> Nil {
  let first =
    log_lines.feed(
      log_lines.new(ServerLog),
      support.bytes_of([header_of("ERROR"), "one"]),
    )
  let assert [Line(sequence: before, text: shorter, ..)] =
    log_lines.entries(first)
  assert shorter == header_of("ERROR") <> "\none"
  let second = log_lines.feed(first, support.bytes_of(["two", "three"]))
  let assert [Line(sequence: after, text: longer, ..)] =
    log_lines.entries(second)
  assert after == before
  assert longer == header_of("ERROR") <> "\none\ntwo\nthree"
  // The next report is the next entry and takes the next number.
  let third = log_lines.feed(second, support.bytes_of([crash_header(), "x"]))
  let assert [Line(sequence: kept, ..), Line(sequence: next, ..)] =
    log_lines.entries(third)
  assert kept == before
  assert next == before + 1
  // A line that is carried, not ended, is not in the entry.
  let carried =
    log_lines.feed(second, bit_array.from_string("four with no end"))
  let assert [Line(text:, ..)] = log_lines.entries(carried)
  assert text == longer
  Nil
}

pub fn the_entries_do_not_depend_on_how_the_lines_were_split_into_reads_test() -> Nil {
  use <- owned_test.run(120_000)
  let crash = support.capture("c5b_pgo_crash_long_password_wraps.txt")
  // The captures, and the crash without its first line: a tail that begins
  // inside the report, whose `password =>` lines are plain lines with their
  // values on the next line.
  let sources = [
    support.capture("c1_default_formatter_reports.txt"),
    support.capture("c2_progress_crash_supervisor_plain.txt"),
    crash,
    list.drop(crash, 1),
  ]
  let draws =
    qcheck.tuple2(
      qcheck.bounded_int(from: 0, to: list.length(sources) - 1),
      qcheck.list_from(qcheck.bounded_int(from: 0, to: 30_000)),
    )
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(80),
    draws,
    fn(drawn) {
      let #(index, points) = drawn
      let assert Ok(lines) = list.drop(sources, index) |> list.first
      support.reads_do_not_change_the_entries(
        source: ServerLog,
        bytes: support.bytes_of(lines),
        points:,
        cap_bytes: report_cap,
      )
    },
  )
  // The invariant holds for a report of many lines too, which the captures
  // do not hold: a body over the cap, split at any points.
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(40),
    qcheck.tuple3(
      qcheck.bounded_int(from: 1, to: 60),
      qcheck.bounded_int(from: 1, to: 1500),
      qcheck.list_from(qcheck.bounded_int(from: 0, to: 100_000)),
    ),
    fn(drawn) {
      let #(lines_in_body, line_length, points) = drawn
      let body =
        list.map(support.numbers(first: 1, last: lines_in_body), fn(number) {
          int.to_string(number) <> string.repeat("z", line_length)
        })
      let lines = list.flatten([[header_of("ERROR")], body, [""], ["after"]])
      support.reads_do_not_change_the_entries(
        source: UpdaterLog,
        bytes: support.bytes_of(lines),
        points:,
        cap_bytes: report_cap,
      )
    },
  )
}

pub fn a_plain_line_of_the_server_or_the_database_has_the_level_its_words_give_test() -> Nil {
  use <- owned_test.run(5000)
  let panic_line = list.first(support.capture("c3_gleam_boot_panic.txt"))
  let assert Ok(panic_line) = panic_line
  let postgres = support.capture("c4_postgres_container_sample.txt")
  let from_postgres = fn(word: String) {
    let assert Ok(line) =
      list.find(postgres, fn(line) {
        string.contains(line, "] " <> word <> ":")
      })
    line
  }
  let rows = [
    #(
      "a Gleam panic, as the capture has it with its colour codes (C3)",
      ServerLog,
      panic_line,
      LevelBad,
    ),
    #(
      "the runtime's boot failure",
      ServerLog,
      "Runtime terminating during boot ({{badmatch,{error,{function_clause",
      LevelBad,
    ),
    #(
      "the crash dump line (C1)",
      ServerLog,
      "Crash dump is being written to: erl_crash.dump...done",
      LevelBad,
    ),
    #(
      "the ready line",
      ServerLog,
      "the server loaded 3 game tables and serves the STS login on port 6600, the auth login on port 23115 and the game server on port 24000",
      LevelInfo,
    ),
    #(
      "a stack frame of a panic (C3)",
      ServerLog,
      "  genesis_prime.run src/genesis_prime.gleam:89",
      LevelInfo,
    ),
    #("a line printed to stdout (C2)", ServerLog, "to stdout", LevelInfo),
    #(
      "a server line that holds the word ERROR is not a bad line",
      ServerLog,
      "loaded 3 tables, 0 ERROR rows",
      LevelInfo,
    ),
    #(
      "the database's ERROR line (C4)",
      DatabaseLog,
      from_postgres("ERROR"),
      LevelBad,
    ),
    #(
      "the database's FATAL line (C4)",
      DatabaseLog,
      from_postgres("FATAL"),
      LevelBad,
    ),
    #(
      "the database's PANIC line",
      DatabaseLog,
      "2026-11-17 05:10:50.466 UTC [29] PANIC:  could not write to file",
      LevelBad,
    ),
    #(
      "the database's WARNING line",
      DatabaseLog,
      "2026-11-17 05:10:50.466 UTC [29] WARNING:  there is no transaction in progress",
      LevelWarn,
    ),
    #(
      "the database's LOG line (C4)",
      DatabaseLog,
      from_postgres("LOG"),
      LevelInfo,
    ),
    #(
      "the database's STATEMENT line (C4)",
      DatabaseLog,
      from_postgres("STATEMENT"),
      LevelInfo,
    ),
    #(
      "the database's HINT line (C4)",
      DatabaseLog,
      from_postgres("HINT"),
      LevelInfo,
    ),
    #(
      "the database's DETAIL line",
      DatabaseLog,
      "2026-11-17 05:10:50.466 UTC [29] DETAIL:  Process 29 waits for ShareLock",
      LevelInfo,
    ),
    #(
      "the entrypoint line of the image (C4)",
      DatabaseLog,
      "PostgreSQL Database directory appears to contain a database; Skipping initialization",
      LevelInfo,
    ),
    #(
      "a LOG line whose message holds the word ERROR",
      DatabaseLog,
      "2026-11-17 05:10:50.466 UTC [29] LOG:  statement: select 'ERROR:'",
      LevelInfo,
    ),
    #(
      "a database line of no known shape that starts with ERROR:",
      DatabaseLog,
      "ERROR: not after a process number",
      LevelInfo,
    ),
  ]
  list.each(rows, fn(row) {
    let #(name, source, line, expected) = row
    let lines = support.fed(source: source, lines: [line])
    let assert [#(_, level)] = support.shown(lines)
    assert level == expected as name
  })
}
