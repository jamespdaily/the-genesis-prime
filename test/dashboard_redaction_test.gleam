//// The mask on the database's password in what the Logs page shows. Expected
//// values are the forms measured in this repository's own `pgo` 0.20.0
//// (`test/fixture/otp_log`: the key and its string on one line, the string
//// on the next line when it is long, five times in one crash), the updater's
//// copy of a container's last lines (`dev/play_service/lib.sh` turns each
//// newline into `|`), and the rule that a line without a measured form is
//// shown whole.

import dashboard_otp_log_support as support
import genesis_prime/dashboard/log_lines.{
  DatabaseLog, LaunchdLog, ServerLog, UpdaterLog,
}
import genesis_prime/dashboard/redaction
import gleam/bit_array
import gleam/list
import gleam/string
import owned_test

/// The value of the capture of a long password (the planted one).
const planted =
  "ZZ0123456789abcdefghijklmnopqrstuvwxyzQQ0123456789abcdefghijklmnopqrstuvwxyzQQ0123456789abcdefgZZ"

const short_planted = "ZZSECRETZZ"

pub fn a_password_a_report_prints_is_hidden_wherever_it_sits_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "the key and its string on one line (C5)",
      "#{port => 1,user => \"u\",host => \"127.0.0.1\",password => \"x\",database => \"d\"}",
      "#{port => 1,user => \"u\",host => \"127.0.0.1\",password => \"[hidden]\",database => \"d\"}",
    ),
    #(
      "the string on the next line (C5b, the measured wrap)",
      "                                  password =>\n                                      \"x\",\n                                  database => \"d\"",
      "                                  password =>\n                                      \"[hidden]\",\n                                  database => \"d\"",
    ),
    #(
      "the binary form",
      "#{password => <<\"x\">>,database => <<\"d\">>}",
      "#{password => <<\"[hidden]\">>,database => <<\"d\">>}",
    ),
    #(
      "the updater's copy, each newline a |",
      "its last lines: =ERROR REPORT====|#{password =>|   \"x\",|   database => \"d\"}|",
      "its last lines: =ERROR REPORT====|#{password =>|   \"[hidden]\",|   database => \"d\"}|",
    ),
    #(
      "a value with an escaped quote and the word password inside it",
      "password => \"my \\\" password => \\\"x\"",
      "password => \"[hidden]\"",
    ),
    #(
      "a value that is empty",
      "password => \"\",user => \"u\"",
      "password => \"[hidden]\",user => \"u\"",
    ),
    #(
      "a value a cut left open",
      "password => \"abc",
      "password => \"[hidden]\"",
    ),
    #(
      "two keys on one line",
      "password => \"a\",password => \"b\"",
      "password => \"[hidden]\",password => \"[hidden]\"",
    ),
    #(
      "the key with no value yet is shown as it is",
      "password =>",
      "password =>",
    ),
    #(
      "the word with no value after it",
      "FATAL:  password authentication failed for user \"play\"",
      "FATAL:  password authentication failed for user \"play\"",
    ),
    #(
      "a key whose value is not a string",
      "password => undefined,user => \"u\"",
      "password => undefined,user => \"u\"",
    ),
    #(
      "no password at all",
      "a line of an ordinary log",
      "a line of an ordinary log",
    ),
    #("an empty text", "", ""),
  ]
  list.each(rows, fn(row) {
    let #(name, text, expected) = row
    assert redaction.hide_passwords(text) == expected as name
  })

  // The mark does not say how long the value was.
  let widths = ["", "a", "abcdefghij", planted]
  let marked =
    list.map(widths, fn(value) {
      redaction.hide_passwords("password => \"" <> value <> "\"")
    })
  assert list.unique(marked) == ["password => \"[hidden]\""]
    as "the same text whatever the value's length"

  // The capture of the crash: five occurrences, all hidden, and nothing else
  // changed.
  let crash =
    string.join(support.capture("c5b_pgo_crash_long_password_wraps.txt"), "\n")
  assert string.contains(crash, planted)
  let hidden = redaction.hide_passwords(crash)
  assert !string.contains(hidden, planted)
  assert list.length(string.split(hidden, "\"[hidden]\"")) - 1 == 5
    as "the state, the stack arguments, the crash report and the supervisor's reason and offender"
  assert string.replace(hidden, "\"[hidden]\"", "\"" <> planted <> "\"")
    == crash
    as "only the five values changed"
  let short_crash =
    string.join(support.capture("c5_pgo_crash_prints_the_password.txt"), "\n")
  assert string.contains(short_crash, short_planted)
  assert !string.contains(redaction.hide_passwords(short_crash), short_planted)

  // A report with no password is the same bytes.
  list.each(
    [
      "c1_default_formatter_reports.txt",
      "c2_progress_crash_supervisor_plain.txt",
      "c3_gleam_boot_panic.txt",
      "c4_postgres_container_sample.txt",
    ],
    fn(name) {
      let text = string.join(support.capture(name), "\n")
      assert redaction.hide_passwords(text) == text as name
    },
  )

  // A line that ends at a key is a key with its value on the next line.
  assert redaction.ends_at_a_password_key("                password =>")
  assert redaction.ends_at_a_password_key("password => ")
  assert !redaction.ends_at_a_password_key("password => \"x\",")
  assert !redaction.ends_at_a_password_key("a line")
}

pub fn no_entry_ever_holds_the_password_whatever_the_read_boundaries_are_test() -> Nil {
  use <- owned_test.run(300_000)
  let lines = support.capture("c5b_pgo_crash_long_password_wraps.txt")
  let whole = support.bytes_of(lines)
  let size = bit_array.byte_size(whole)
  let holds_the_value = fn(lines: log_lines.Lines) {
    list.any(support.texts(lines), string.contains(_, planted))
  }

  // The capture in two reads, split at each possible byte: no ring holds the
  // value.
  list.each(support.numbers(first: 0, last: size), fn(point) {
    let assert Ok(first) = bit_array.slice(whole, 0, point)
    let assert Ok(second) = bit_array.slice(whole, point, size - point)
    let after_first = log_lines.feed(log_lines.new(ServerLog), first)
    let after_second = log_lines.feed(after_first, second)
    assert !holds_the_value(after_first)
      as "the ring after the first read holds the value"
    assert !holds_the_value(after_second)
      as "the ring after the second read holds the value"
  })

  // The other sources, in one read.
  list.each([DatabaseLog, UpdaterLog, LaunchdLog], fn(source) {
    let ring = log_lines.feed(log_lines.new(source), whole)
    assert !holds_the_value(ring)
    assert list.any(support.texts(ring), string.contains(_, "\"[hidden]\""))
  })

  // The capture a line at a time, so a value that arrives after its key is
  // seen in each ring on its way; the last ring shows the mask.
  list.each([ServerLog, DatabaseLog, UpdaterLog, LaunchdLog], fn(source) {
    let rings = support.fed_line_by_line(source: source, lines: lines)
    list.each(rings, fn(ring) {
      assert !holds_the_value(ring)
    })
    let assert Ok(last) = list.last(rings)
    assert list.any(support.texts(last), string.contains(_, "\"[hidden]\""))
  })

  // The updater's copy of the last lines holds the report on one line.
  let copied =
    "2026-11-09 04:38:00 play-service: genesis-play did not come up: state exited, its last lines: "
    <> string.join(lines, "|")
  let updater = support.fed(source: UpdaterLog, lines: [copied])
  assert !holds_the_value(updater)
  assert list.any(support.texts(updater), string.contains(_, "\"[hidden]\""))

  // A tail that began inside the report: the key ends a plain line and the
  // value is the next line; the value is hidden in its own entry.
  let assert Ok(key_line) =
    list.find(lines, fn(line) { string.trim(line) == "password =>" })
  let tail =
    support.fed(source: ServerLog, lines: [
      key_line,
      "      \"" <> planted <> "\",",
      "      database => \"d\"",
    ])
  assert !holds_the_value(tail)
  assert support.texts(tail)
    == [key_line, "      \"[hidden]\",", "      database => \"d\""]
}
