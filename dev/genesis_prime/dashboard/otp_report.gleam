//// An OTP report in a container's log: its header line, the level OTP logged
//// it at, and the text it grows into, one line at a time.
////
//// ```text
//// line ──header──► Title ──severity──► Severity
////   │
////   └─ start (header) ──add_line──► add_line ──► text, cut or not
//// ```
////
//// - A header is `=TITLE REPORT==== D-Mon-YYYY::HH:MM:SS.ffffff ===`, with
////   `UTC ` before the closing `===` when the node logs in UTC; the day has one
////   or two digits (`logger_formatter.erl:589-612`). A line of any other shape
////   is not a header.
//// - The title is the level word for `NOTICE`, `WARNING`, `INFO`, `ERROR`,
////   `CRITICAL`, `ALERT`, `EMERGENCY` and `DEBUG`; `CRASH` and `SUPERVISOR` are
////   logged at error (`proc_lib.erl:954`, `supervisor.erl:319`) and `PROGRESS`
////   at info (`supervisor.erl:2323`). A title no word names is info: the project's
////   rule for a shape nothing names.
//// - A report holds at most `report_cap_bytes`, a guess against the largest real
////   report (6.1 KB, a pgo crash): a longer one is cut once at a whole
////   character and the lines after it are dropped.
////
//// A report ends at the next header or at a blank line; that is the reader's
//// to say (`log_lines`), since a blank line is not part of the report.

import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/result
import gleam/string

/// How many bytes a report's text may hold before it is shown cut: a guess,
/// about two and a half times the largest report of a real crash.
pub const report_cap_bytes = 16_384

/// The title of a report's header: the level word OTP's logger prints for a
/// level, or one of the three titles OTP sets itself.
pub type Title {
  TitleNotice
  TitleWarning
  TitleInfo
  TitleError
  TitleCritical
  TitleAlert
  TitleEmergency
  TitleDebug
  TitleCrash
  TitleSupervisor
  TitleProgress
  TitleOther(name: String)
}

/// How bad a report is, by the level OTP logged it at.
pub type Severity {
  SeverityBad
  SeverityWarn
  SeverityInfo
}

/// How much of a report is kept: all of it so far, with a line of it cut, or
/// no more because the cap was reached.
type Growth {
  Whole
  LineCut
  CapReached
}

/// A report: the lines of it read so far.
pub opaque type Report {
  Report(text: String, growth: Growth)
}

/// The title a header line names, or nothing when the line is not a header.
pub fn header(line: String) -> Result(Title, Nil) {
  use rest <- result.try(case line {
    "=" <> rest -> Ok(rest)
    _ -> Error(Nil)
  })
  use #(name, stamp) <- result.try(string.split_once(rest, " REPORT==== "))
  use <- bool.guard(when: !is_a_title_word(name), return: Error(Nil))
  use <- bool.guard(when: !is_a_stamp(stamp), return: Error(Nil))
  Ok(title_of(name))
}

fn title_of(name: String) -> Title {
  case name {
    "NOTICE" -> TitleNotice
    "WARNING" -> TitleWarning
    "INFO" -> TitleInfo
    "ERROR" -> TitleError
    "CRITICAL" -> TitleCritical
    "ALERT" -> TitleAlert
    "EMERGENCY" -> TitleEmergency
    "DEBUG" -> TitleDebug
    "CRASH" -> TitleCrash
    "SUPERVISOR" -> TitleSupervisor
    "PROGRESS" -> TitleProgress
    other -> TitleOther(other)
  }
}

/// The level OTP logged a report at, by its title.
pub fn severity(title: Title) -> Severity {
  case title {
    TitleEmergency
    | TitleAlert
    | TitleCritical
    | TitleError
    | TitleCrash
    | TitleSupervisor -> SeverityBad
    TitleWarning -> SeverityWarn
    TitleNotice | TitleInfo | TitleDebug | TitleProgress | TitleOther(_) ->
      SeverityInfo
  }
}

/// Capital letters and single spaces between words.
fn is_a_title_word(name: String) -> Bool {
  name != ""
  && list.all(string.split(name, " "), fn(word) {
    word != "" && list.all(string.to_graphemes(word), is_a_capital_letter)
  })
}

fn is_a_capital_letter(character: String) -> Bool {
  case string.to_utf_codepoints(character) {
    [code] -> {
      let number = string.utf_codepoint_to_int(code)
      number >= 0x41 && number <= 0x5A
    }
    _ -> False
  }
}

/// What follows `==== ` in a header: `D-Mon-YYYY::HH:MM:SS.ffffff ===`, with
/// `UTC ` before the closing `===` for a node that logs in UTC.
fn is_a_stamp(stamp: String) -> Bool {
  case string.split(stamp, " ") {
    [moment, "==="] | [moment, "UTC", "==="] -> is_a_moment(moment)
    _ -> False
  }
}

fn is_a_moment(moment: String) -> Bool {
  case string.split(moment, "::") {
    [date, time] -> is_a_date(date) && is_a_time(time)
    _ -> False
  }
}

fn is_a_date(date: String) -> Bool {
  case string.split(date, "-") {
    [day, month, year] ->
      is_digits(text: day, from: 1, to: 2)
      && list.contains(months, month)
      && is_digits(text: year, from: 4, to: 4)
    _ -> False
  }
}

fn is_a_time(time: String) -> Bool {
  case string.split(time, ".") {
    [clock, microseconds] ->
      is_digits(text: microseconds, from: 6, to: 6)
      && case string.split(clock, ":") {
        [hours, minutes, seconds] ->
          is_digits(text: hours, from: 2, to: 2)
          && is_digits(text: minutes, from: 2, to: 2)
          && is_digits(text: seconds, from: 2, to: 2)
        _ -> False
      }
    _ -> False
  }
}

/// The month names `logger_formatter.erl` prints.
const months = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
  "Dec",
]

fn is_digits(text text: String, from least: Int, to most: Int) -> Bool {
  let size = string.length(text)
  size >= least
  && size <= most
  && list.all(string.to_graphemes(text), is_a_digit)
}

/// Whether the character is one of `0` to `9`.
pub fn is_a_digit(character: String) -> Bool {
  case character {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

/// A report that has read its header line.
pub fn start(header header: String) -> Report {
  Report(text: header, growth: Whole)
}

/// The report with one more line, after the lines it has: a report that was
/// cut at the cap takes no more; one that reaches the cap is cut there, back to
/// a whole character. A line that was itself cut marks the report cut.
pub fn add_line(
  report report: Report,
  line line: String,
  line_was_cut line_was_cut: Bool,
) -> Report {
  case report.growth {
    CapReached -> report
    Whole | LineCut -> {
      let text = report.text <> "\n" <> line
      case string.byte_size(text) > report_cap_bytes {
        True ->
          Report(
            text: cut_to_bytes(text:, cap_bytes: report_cap_bytes),
            growth: CapReached,
          )
        False ->
          Report(text:, growth: case line_was_cut {
            True -> LineCut
            False -> report.growth
          })
      }
    }
  }
}

/// The report's lines read so far, one string with a newline between lines.
pub fn text(report: Report) -> String {
  report.text
}

/// Whether the report was cut: a line of it, or its end, did not fit.
pub fn was_cut(report: Report) -> Bool {
  case report.growth {
    Whole -> False
    LineCut | CapReached -> True
  }
}

/// The text cut to at most this many bytes, back to a whole character.
pub fn cut_to_bytes(text text: String, cap_bytes cap_bytes: Int) -> String {
  use <- bool.guard(when: string.byte_size(text) <= cap_bytes, return: text)
  let bytes = bit_array.from_string(text)
  whole_characters(bytes:, size: cap_bytes)
}

fn whole_characters(bytes bytes: BitArray, size size: Int) -> String {
  let assert Ok(head) = bit_array.slice(bytes, 0, size)
    as "the size is inside the bytes"
  case bit_array.to_string(head) {
    Ok(text) -> text
    Error(Nil) -> whole_characters(bytes:, size: size - 1)
  }
}
