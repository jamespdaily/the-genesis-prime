//// The entries of one followed log, made from its bytes: where a line ends,
//// what it shows, what level its words give it, how an OTP report is grouped,
//// and a ring of the newest entries.
////
//// ```text
//// bytes of a read ──feed──► carried partial line ──newline──► clean text ──┬─► header: a new report entry
////                              │ over the cap                              ├─► in a report: the entry grows
////                              └─ cut once, rest dropped to the newline    └─► plain: a line entry
////                                                                              │ the password mask on each text
//// mark (replaced, cut shorter, container replaced) ──────────────────────────► ring of the newest entries
//// ```
////
//// - A line ends at a newline; a `\r` before it is not text. A line that has
////   not ended is carried to the next read, and is never shown before it ends.
//// - A line is cut at 4,096 bytes, a guess (the longest line in either real log
////   is 587 bytes): the line shows its first bytes, cut back to a whole
////   character and marked cut, and the rest of it up to the newline is dropped,
////   so the bytes carried never pass the cap whatever the writer prints.
//// - A line is shown as text: bytes that are not UTF-8 are U+FFFD, a terminal
////   escape sequence and every control character but the tab are removed, and
////   markup is left to the view, which makes text of it.
//// - The ring keeps 500 entries, a guess (a log of this machine holds 2,453
////   lines in 15 days). Each entry has a sequence number, counted from the
////   first line, so the view can tell one new line from the ring.
//// - A mark (the log was replaced, the log was cut shorter, the container was
////   replaced) is an entry that takes a slot and is not a line, and it ends the
////   partial line and the report before it.
//// - An OTP report is one entry, from its header line to the next header or to
////   a blank line, which ends it and is not shown (`otp_report`). The entry
////   takes its slot when its header is read and grows in place, under the same
////   sequence number, as its lines are read. Its level is the level OTP logged it
////   at. A report is cut at `otp_report.report_cap_bytes`. Every source is read
////   so; a header only starts a line, so a line the updater copied from a
////   container (its newlines written as `|`) is one plain line.
//// - The database's password is hidden in each entry's text each time the text
////   changes, so a value that arrives after its key is never shown (`redaction`).
////   A plain line that ends at the key hides the start of the next plain line, for
////   a read that began inside a report.
//// - The level words of a plain line are a guess from the line shapes of the real
////   logs; the scripts write no level, and the server and Postgres write theirs
////   in words. A shape no word names is `LevelInfo`. Gleam's panics and
////   Postgres's multi-line entries (a statement after its error) are not grouped:
////   each of their lines is one entry.
////
//// The chunks a read was cut into never change the entries; the module's
//// property tests hold that.

import genesis_prime/dashboard/otp_report.{type Report}
import genesis_prime/dashboard/redaction
import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// How long a line may be, in bytes, before it is shown cut: a guess, seven
/// times the longest line in either real log.
pub const line_cap_bytes = 4096

/// How many entries the ring keeps: a guess.
pub const ring_lines = 500

/// The log a line belongs to: the file the updater's script writes
/// (`lib.sh`, `log_file`), the file launchd writes the script's output and
/// the tools' own output to (`install.sh`, `StandardOutPath`), or the output
/// of the play server's container or of its database's container.
pub type Source {
  UpdaterLog
  LaunchdLog
  ServerLog
  DatabaseLog
}

/// How a line looks, by its words: the palette's roles for state.
pub type Level {
  LevelOk
  LevelWarn
  LevelBad
  LevelInfo
}

/// A change of the file the follower saw, shown between the lines before and
/// after it.
pub type Mark {
  LogReplaced
  LogCutShorter
  ContainerReplaced
}

/// What the ring holds: a line or a whole report (its lines apart by newlines)
/// with whether it was shown cut, or a mark.
pub type Entry {
  Line(sequence: Int, text: String, level: Level, cut: Bool)
  Marker(sequence: Int, mark: Mark)
}

/// What is done with the bytes of the line being read.
type Partial {
  /// The bytes so far, at most the cap.
  Carrying(bytes: BitArray)
  /// The line passed the cap: its first cap bytes, and the rest is dropped.
  Cutting(bytes: BitArray)
  /// The read began inside a line: its rest is dropped, and no line is made.
  Skipping
}

/// The entries of one log: the partial line, the report being read (whose
/// entry is the newest of the ring), whether the last plain line ended at a
/// password key, and the ring.
pub opaque type Lines {
  Lines(
    source: Source,
    partial: Partial,
    open: Option(Report),
    after_key: Bool,
    ring: List(Entry),
    kept: Int,
    next_sequence: Int,
  )
}

/// No lines yet, for a log of this source.
pub fn new(source: Source) -> Lines {
  Lines(
    source:,
    partial: Carrying(<<>>),
    open: None,
    after_key: False,
    ring: [],
    kept: 0,
    next_sequence: 0,
  )
}

/// The name of the file a source is, inside the dashboard's home; a container's
/// log is no file.
pub fn file_name(source: Source) -> Result(String, Nil) {
  case source {
    UpdaterLog -> Ok("play-service.log")
    LaunchdLog -> Ok("play-service.launchd.log")
    ServerLog | DatabaseLog -> Error(Nil)
  }
}

/// The bytes of the line that has not ended.
pub fn carried_bytes(lines: Lines) -> Int {
  case lines.partial {
    Carrying(bytes:) | Cutting(bytes:) -> bit_array.byte_size(bytes)
    Skipping -> 0
  }
}

/// The ring's entries, the oldest first.
pub fn entries(lines: Lines) -> List(Entry) {
  lines.ring |> list.take(ring_lines) |> list.reverse
}

/// The next read begins inside a line, whose rest is dropped up to its newline.
pub fn start_inside_a_line(lines: Lines) -> Lines {
  Lines(..lines, partial: Skipping)
}

/// Adds a mark to the ring. The partial line before it is dropped, since the
/// bytes after it are another file's.
pub fn mark(lines lines: Lines, mark mark: Mark) -> Lines {
  Lines(..lines, partial: Carrying(<<>>))
  |> push(fn(sequence) { Marker(sequence:, mark:) })
}

/// Takes the bytes of a read: each line they end is added to the ring, and the
/// bytes after the last newline are carried.
pub fn feed(lines lines: Lines, bytes bytes: BitArray) -> Lines {
  case newline_at(bytes, 0) {
    Error(Nil) -> absorb(lines, bytes)
    Ok(index) -> {
      let assert Ok(before) = bit_array.slice(bytes, 0, index)
        as "the newline is inside the bytes"
      let assert Ok(after) =
        bit_array.slice(
          bytes,
          index + 1,
          bit_array.byte_size(bytes) - index - 1,
        )
        as "the bytes after the newline are inside the bytes"
      lines |> absorb(before) |> end_line |> feed(bytes: after)
    }
  }
}

/// The index of the first newline in `rest`, counted from `index`.
fn newline_at(rest: BitArray, index: Int) -> Result(Int, Nil) {
  case rest {
    <<0x0A, _:bits>> -> Ok(index)
    <<_, tail:bits>> -> newline_at(tail, index + 1)
    _ -> Error(Nil)
  }
}

/// Adds bytes that hold no newline to the partial line, cutting it once at the
/// cap.
fn absorb(lines: Lines, bytes: BitArray) -> Lines {
  case lines.partial {
    Skipping | Cutting(_) -> lines
    Carrying(carried) -> {
      let all = bit_array.append(carried, bytes)
      let partial = case bit_array.byte_size(all) > line_cap_bytes {
        True -> {
          let assert Ok(kept) = bit_array.slice(all, 0, line_cap_bytes)
            as "the cap is inside the bytes"
          Cutting(kept)
        }
        False -> Carrying(all)
      }
      Lines(..lines, partial:)
    }
  }
}

/// A newline came: the partial line is shown, unless it is the rest of a line
/// whose start was not read.
fn end_line(lines: Lines) -> Lines {
  let ended = Lines(..lines, partial: Carrying(<<>>))
  case lines.partial {
    Skipping -> ended
    Carrying(bytes:) -> line_from(lines: ended, raw: bytes, cut: False)
    Cutting(bytes:) -> line_from(lines: ended, raw: bytes, cut: True)
  }
}

fn line_from(lines lines: Lines, raw raw: BitArray, cut cut: Bool) -> Lines {
  let whole = case cut {
    True -> without_incomplete_character(raw)
    False -> without_carriage_return(raw)
  }
  let text = clean(whole)
  // A text that grew past the cap (each byte that is not UTF-8 becomes three)
  // is cut again, at a character.
  let #(text, cut) = case bit_array.byte_size(bit_array.from_string(text)) {
    size if size > line_cap_bytes -> #(cut_to_cap(text), True)
    _ -> #(text, cut)
  }
  take_line(lines:, text:, cut:)
}

/// A line of clean text: it starts a report, belongs to the report being read,
/// ends that report, or is a plain line.
fn take_line(lines lines: Lines, text text: String, cut cut: Bool) -> Lines {
  case otp_report.header(text), lines.open {
    Ok(title), _ -> start_report(lines:, title:, header: text)
    Error(Nil), Some(report) ->
      case text {
        "" -> Lines(..lines, open: None)
        _ -> grow_report(lines:, report:, text:, cut:)
      }
    Error(Nil), None -> plain_line(lines:, text:, cut:)
  }
}

fn plain_line(lines lines: Lines, text text: String, cut cut: Bool) -> Lines {
  let masked = case lines.after_key {
    True -> redaction.hide_a_value_after_a_key(text)
    False -> redaction.hide_passwords(text)
  }
  let source = lines.source
  let pushed =
    push(lines, fn(sequence) {
      Line(sequence:, text: masked, level: level(source:, text:), cut:)
    })
  Lines(..pushed, after_key: redaction.ends_at_a_password_key(text))
}

fn start_report(
  lines lines: Lines,
  title title: otp_report.Title,
  header header: String,
) -> Lines {
  let report = otp_report.start(header:)
  let #(text, cut) = shown_report(report)
  let level = report_level(title)
  let pushed =
    push(lines, fn(sequence) { Line(sequence:, text:, level:, cut:) })
  Lines(..pushed, open: Some(report))
}

fn grow_report(
  lines lines: Lines,
  report report: Report,
  text text: String,
  cut cut: Bool,
) -> Lines {
  let report = otp_report.add_line(report:, line: text, line_was_cut: cut)
  let #(text, cut) = shown_report(report)
  let ring = case lines.ring {
    [Line(sequence:, level:, ..), ..older] -> [
      Line(sequence:, text:, level:, cut:),
      ..older
    ]
    [Marker(..), ..] | [] -> lines.ring
  }
  Lines(..lines, open: Some(report), ring:)
}

/// The text a report entry shows: the report with the password hidden, and cut
/// to the report cap again when the mask made it longer.
fn shown_report(report: Report) -> #(String, Bool) {
  let masked = redaction.hide_passwords(otp_report.text(report))
  case string.byte_size(masked) > otp_report.report_cap_bytes {
    True -> #(
      otp_report.cut_to_bytes(
        text: masked,
        cap_bytes: otp_report.report_cap_bytes,
      ),
      True,
    )
    False -> #(masked, otp_report.was_cut(report))
  }
}

fn report_level(title: otp_report.Title) -> Level {
  case otp_report.severity(title) {
    otp_report.SeverityBad -> LevelBad
    otp_report.SeverityWarn -> LevelWarn
    otp_report.SeverityInfo -> LevelInfo
  }
}

fn without_carriage_return(raw: BitArray) -> BitArray {
  let size = bit_array.byte_size(raw)
  case bit_array.slice(raw, size - 1, 1) {
    Ok(<<0x0D>>) -> {
      let assert Ok(before) = bit_array.slice(raw, 0, size - 1)
        as "the bytes before the last one are inside the bytes"
      before
    }
    _ -> raw
  }
}

/// A cut line's bytes up to the last whole character: a trailing lead byte
/// whose continuation bytes were cut off is dropped with the ones before it.
fn without_incomplete_character(raw: BitArray) -> BitArray {
  let size = bit_array.byte_size(raw)
  case lead_of_last_character(raw:, size:, back: 1) {
    Ok(#(back, length)) if length > back -> {
      let assert Ok(whole) = bit_array.slice(raw, 0, size - back)
        as "the bytes before the lead are inside the bytes"
      whole
    }
    Ok(_) | Error(Nil) -> raw
  }
}

/// How far back from the end the lead byte of the last character is, and the
/// length of character that lead says. Nil when the last byte is ASCII or no
/// lead is within the last three bytes.
fn lead_of_last_character(
  raw raw: BitArray,
  size size: Int,
  back back: Int,
) -> Result(#(Int, Int), Nil) {
  use <- bool.guard(when: back > 3 || back > size, return: Error(Nil))
  case bit_array.slice(raw, size - back, 1) {
    Ok(<<byte>>) if byte < 0x80 -> Error(Nil)
    // A continuation byte: look one byte further back for its lead.
    Ok(<<byte>>) if byte < 0xC0 ->
      lead_of_last_character(raw:, size:, back: back + 1)
    Ok(<<byte>>) if byte < 0xE0 -> Ok(#(back, 2))
    Ok(<<byte>>) if byte < 0xF0 -> Ok(#(back, 3))
    Ok(<<_>>) -> Ok(#(back, 4))
    _ -> Error(Nil)
  }
}

/// The text cut to the cap, back to a whole character.
fn cut_to_cap(text: String) -> String {
  otp_report.cut_to_bytes(text:, cap_bytes: line_cap_bytes)
}

/// How `clean` is reading: ordinary text, just after an escape, or inside an
/// escape sequence that opened with a bracket.
type Reading {
  Plain
  Escaped
  Sequence
}

/// What `clean` has so far: how it is reading, and the codepoints it keeps,
/// the last first.
type Cleaning {
  Cleaning(reading: Reading, kept: List(Int))
}

/// Bytes as text to show: invalid UTF-8 as U+FFFD, terminal escape sequences
/// and control characters removed, the tab kept.
fn clean(raw: BitArray) -> String {
  let cleaned = list.fold(codes(raw, []), Cleaning(Plain, []), take)
  cleaned.kept
  |> list.reverse
  |> list.filter_map(string.utf_codepoint)
  |> string.from_utf_codepoints
}

/// The codepoint of each character of the bytes; each byte that is not UTF-8
/// is U+FFFD.
fn codes(raw: BitArray, found: List(Int)) -> List(Int) {
  case raw {
    <<code:utf8_codepoint, rest:bits>> ->
      codes(rest, [string.utf_codepoint_to_int(code), ..found])
    <<_, rest:bits>> -> codes(rest, [0xFFFD, ..found])
    _ -> list.reverse(found)
  }
}

fn take(cleaning: Cleaning, code: Int) -> Cleaning {
  case cleaning.reading {
    Plain -> plain(cleaning.kept, code)
    // An escape that opens no sequence is dropped alone.
    Escaped ->
      case code {
        0x5B -> Cleaning(Sequence, cleaning.kept)
        _ -> plain(cleaning.kept, code)
      }
    // Parameters and intermediates, then a final byte; any other character
    // ends the sequence without being part of it.
    Sequence ->
      case code {
        code if code >= 0x20 && code <= 0x3F -> cleaning
        code if code >= 0x40 && code <= 0x7E -> Cleaning(Plain, cleaning.kept)
        _ -> plain(cleaning.kept, code)
      }
  }
}

fn plain(kept: List(Int), code: Int) -> Cleaning {
  case code {
    0x1B -> Cleaning(Escaped, kept)
    0x09 -> Cleaning(Plain, [code, ..kept])
    code if code < 0x20 || code == 0x7F || { code >= 0x80 && code < 0xA0 } ->
      Cleaning(Plain, kept)
    _ -> Cleaning(Plain, [code, ..kept])
  }
}

/// Adds an entry to the ring, numbered after the entries before it; it ends
/// the report being read and the key a plain line ended at. The ring is trimmed
/// to the cap when it holds twice that, so a push costs one step.
fn push(lines: Lines, entry: fn(Int) -> Entry) -> Lines {
  let ring = [entry(lines.next_sequence), ..lines.ring]
  let kept = lines.kept + 1
  let #(ring, kept) = case kept > 2 * ring_lines {
    True -> #(list.take(ring, ring_lines), ring_lines)
    False -> #(ring, kept)
  }
  Lines(
    ..lines,
    open: None,
    after_key: False,
    ring:,
    kept:,
    next_sequence: lines.next_sequence + 1,
  )
}

/// The level a line's words give it. The rules apply to the message the
/// updater's script wrote (after its stamp, before the last lines it copied
/// from a container): a container's own words never change what the updater
/// said. Bad words win over warn words, and warn over ok.
pub fn level(source source: Source, text text: String) -> Level {
  case source {
    UpdaterLog -> words_level(message_of(text))
    LaunchdLog ->
      case words_level(message_of(text)) {
        LevelInfo -> launchd_level(text)
        found -> found
      }
    ServerLog -> server_level(text)
    DatabaseLog -> database_level(text)
  }
}

/// A guess from what the server prints when it cannot run: Gleam's panic line,
/// the runtime's boot failure and the line before a crash dump. Every other line
/// of the server is info.
fn server_level(text: String) -> Level {
  use <- bool.guard(
    when: string.starts_with(text, "runtime error: panic")
      || string.starts_with(text, "Runtime terminating during boot")
      || string.starts_with(text, "Crash dump is being written to:"),
    return: LevelBad,
  )
  LevelInfo
}

/// The level word Postgres prints after its process number (`2026-11-09
/// 00:56:22.092 UTC [69] LOG:  ...`); a line of another shape, such as the
/// image's own entrypoint lines, is info.
fn database_level(text: String) -> Level {
  case postgres_word(text) {
    Ok("ERROR") | Ok("FATAL") | Ok("PANIC") -> LevelBad
    Ok("WARNING") -> LevelWarn
    Ok(_) | Error(Nil) -> LevelInfo
  }
}

fn postgres_word(text: String) -> Result(String, Nil) {
  use #(stamp, rest) <- result.try(string.split_once(text, " ["))
  use #(process, after) <- result.try(string.split_once(rest, "] "))
  use #(word, _) <- result.try(string.split_once(after, ":"))
  let starts_with_a_digit = case string.first(stamp) {
    Ok(first) -> otp_report.is_a_digit(first)
    Error(Nil) -> False
  }
  let is_a_process_number =
    process != ""
    && list.all(string.to_graphemes(process), otp_report.is_a_digit)
  case starts_with_a_digit && is_a_process_number {
    True -> Ok(word)
    False -> Error(Nil)
  }
}

/// The text after the updater's stamp (`2026-11-08 19:58:30 play-service: `),
/// up to the lines it copied from a container, or the whole line when it has
/// no stamp.
fn message_of(text: String) -> String {
  let message = case string.split_once(text, " play-service: ") {
    Ok(#(stamp, message)) ->
      case string.length(stamp) == 19 {
        True -> message
        False -> text
      }
    Error(Nil) -> text
  }
  case string.split_once(message, "its last line") {
    Ok(#(before, _)) -> before
    Error(Nil) -> message
  }
}

/// A guess from the words of the updater's real messages.
fn words_level(message: String) -> Level {
  let holds = fn(words) { string.contains(message, words) }
  case
    holds("did not come up")
    || holds("said no ready line")
    || { holds("building ") && holds(" failed") }
    || holds("could not read main")
    || holds("could not ask")
  {
    True -> LevelBad
    False ->
      case
        holds("nothing done")
        || holds("has not passed or has not finished")
        || holds("a live session holds")
        || holds("another update runs")
        || holds("the Podman machine is not running")
        || holds("a live session took the lock")
        || holds("holds no release/Containerfile")
      {
        True -> LevelWarn
        False ->
          case
            holds("came up")
            || holds("is back up")
            || holds("genesis-play started")
            || holds("alert sent")
          {
            True -> LevelOk
            False -> LevelInfo
          }
      }
  }
}

/// A guess from what git, Podman, gh and bash print into launchd's log.
fn launchd_level(text: String) -> Level {
  use <- bool.guard(
    when: string.starts_with(text, "fatal:")
      || string.starts_with(text, "Error:")
      || string.starts_with(text, "gh: API rate limit")
      || is_a_bash_error(text),
    return: LevelBad,
  )
  LevelInfo
}

/// Whether the line holds `: line N: `, how bash names the line of a script
/// that failed.
fn is_a_bash_error(text: String) -> Bool {
  case string.split(text, ": line ") {
    [_, ..after] ->
      list.any(after, fn(rest) {
        let digits =
          string.to_graphemes(rest) |> list.take_while(otp_report.is_a_digit)
        digits != []
        && string.starts_with(
          string.drop_start(rest, list.length(digits)),
          ": ",
        )
      })
    [] -> False
  }
}
