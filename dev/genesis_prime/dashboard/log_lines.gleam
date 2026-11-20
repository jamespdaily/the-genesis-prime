//// The lines of one followed log, made from its bytes: where a line ends,
//// what it shows, what level its words give it, and a ring of the newest
//// ones.
////
//// ```text
//// bytes of a read ──feed──► carried partial line ──newline──► clean text ──► Line (with its level)
////                              │ over the cap                                     │
////                              └─ cut once, rest dropped to the newline           ▼
//// mark (replaced, cut shorter) ───────────────────────────────────────► ring of the newest entries
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
//// - A mark (the log was replaced, the log was cut shorter) is an entry that
////   takes a slot and is not a line, and it ends the partial line before it.
//// - The level words are a guess from the line shapes of the two real logs;
////   the scripts write no level. A shape no word names is `LevelInfo`.
////
//// The chunks a read was cut into never change the entries; the module's
//// property test holds that.

import gleam/bit_array
import gleam/list
import gleam/string

/// How long a line may be, in bytes, before it is shown cut: a guess, seven
/// times the longest line in either real log.
pub const line_cap_bytes = 4096

/// How many entries the ring keeps: a guess.
pub const ring_lines = 500

/// The log a line belongs to: the file the updater's script writes
/// (`lib.sh`, `log_file`) or the file launchd writes the script's output and
/// the tools' own output to (`install.sh`, `StandardOutPath`).
pub type Source {
  UpdaterLog
  LaunchdLog
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
}

/// What the ring holds: a line, with whether it was shown cut, or a mark.
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

/// The lines of one log: the partial line and the ring.
pub opaque type Lines {
  Lines(
    source: Source,
    partial: Partial,
    ring: List(Entry),
    kept: Int,
    next_sequence: Int,
  )
}

/// No lines yet, for a log of this source.
pub fn new(source: Source) -> Lines {
  Lines(source:, partial: Carrying(<<>>), ring: [], kept: 0, next_sequence: 0)
}

/// The name of the file a source is, inside the dashboard's home.
pub fn file_name(source: Source) -> String {
  case source {
    UpdaterLog -> "play-service.log"
    LaunchdLog -> "play-service.launchd.log"
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
pub fn mark(lines: Lines, mark: Mark) -> Lines {
  Lines(..lines, partial: Carrying(<<>>))
  |> push(fn(sequence) { Marker(sequence:, mark:) })
}

/// Takes the bytes of a read: each line they end is added to the ring, and the
/// bytes after the last newline are carried.
pub fn feed(lines: Lines, bytes: BitArray) -> Lines {
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
      lines |> absorb(before) |> end_line |> feed(after)
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
    Carrying(bytes:) -> line_from(ended, bytes, cut: False)
    Cutting(bytes:) -> line_from(ended, bytes, cut: True)
  }
}

fn line_from(lines: Lines, raw: BitArray, cut cut: Bool) -> Lines {
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
  let source = lines.source
  push(lines, fn(sequence) {
    Line(sequence:, text:, level: level(source, text), cut:)
  })
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
  incomplete_from(raw, size, 1)
}

fn incomplete_from(raw: BitArray, size: Int, back: Int) -> BitArray {
  case back > 3 || back > size {
    True -> raw
    False ->
      case bit_array.slice(raw, size - back, 1) {
        Ok(<<byte>>) if byte < 0x80 -> raw
        // A continuation byte: look one byte further back for its lead.
        Ok(<<byte>>) if byte < 0xC0 -> incomplete_from(raw, size, back + 1)
        Ok(<<byte>>) -> {
          let needed = case byte {
            byte if byte < 0xE0 -> 2
            byte if byte < 0xF0 -> 3
            _ -> 4
          }
          case needed > back {
            True -> {
              let assert Ok(whole) = bit_array.slice(raw, 0, size - back)
                as "the bytes before the lead are inside the bytes"
              whole
            }
            False -> raw
          }
        }
        _ -> raw
      }
  }
}

/// The text cut to the cap, back to a whole character.
fn cut_to_cap(text: String) -> String {
  cut_to_cap_from(string.to_graphemes(text), 0, [])
}

fn cut_to_cap_from(
  characters: List(String),
  size: Int,
  kept: List(String),
) -> String {
  case characters {
    [] -> string.concat(list.reverse(kept))
    [character, ..rest] -> {
      let size = size + bit_array.byte_size(bit_array.from_string(character))
      case size > line_cap_bytes {
        True -> string.concat(list.reverse(kept))
        False -> cut_to_cap_from(rest, size, [character, ..kept])
      }
    }
  }
}

/// How `clean` is reading: ordinary text, just after an escape, or inside an
/// escape sequence that opened with a bracket.
type Reading {
  Plain
  Escaped
  Sequence
}

/// Bytes as text to show: invalid UTF-8 as U+FFFD, terminal escape sequences
/// and control characters removed, the tab kept.
fn clean(raw: BitArray) -> String {
  clean_from(raw, Plain, [])
}

fn clean_from(
  raw: BitArray,
  reading: Reading,
  kept: List(UtfCodepoint),
) -> String {
  case raw {
    <<>> -> string.from_utf_codepoints(list.reverse(kept))
    <<code:utf8_codepoint, rest:bits>> ->
      step(rest, reading, kept, string.utf_codepoint_to_int(code), code)
    <<_, rest:bits>> -> {
      let assert Ok(replacement) = string.utf_codepoint(0xFFFD)
        as "U+FFFD is a codepoint"
      step(rest, reading, kept, 0xFFFD, replacement)
    }
    _ -> string.from_utf_codepoints(list.reverse(kept))
  }
}

fn step(
  rest: BitArray,
  reading: Reading,
  kept: List(UtfCodepoint),
  code: Int,
  codepoint: UtfCodepoint,
) -> String {
  case reading {
    Plain ->
      case code {
        0x1B -> clean_from(rest, Escaped, kept)
        code if code == 0x09 -> clean_from(rest, Plain, [codepoint, ..kept])
        code if code < 0x20 || code == 0x7F || { code >= 0x80 && code < 0xA0 } ->
          clean_from(rest, Plain, kept)
        _ -> clean_from(rest, Plain, [codepoint, ..kept])
      }
    // An escape that opens no sequence is dropped alone.
    Escaped ->
      case code {
        0x5B -> clean_from(rest, Sequence, kept)
        _ -> step(rest, Plain, kept, code, codepoint)
      }
    // Parameters and intermediates, then a final byte; any other character
    // ends the sequence without being part of it.
    Sequence ->
      case code {
        code if code >= 0x20 && code <= 0x3F -> clean_from(rest, Sequence, kept)
        code if code >= 0x40 && code <= 0x7E -> clean_from(rest, Plain, kept)
        _ -> step(rest, Plain, kept, code, codepoint)
      }
  }
}

/// Adds an entry to the ring, numbered after the entries before it. The ring
/// is trimmed to the cap when it holds twice that, so a push costs one step.
fn push(lines: Lines, entry: fn(Int) -> Entry) -> Lines {
  let ring = [entry(lines.next_sequence), ..lines.ring]
  let kept = lines.kept + 1
  let #(ring, kept) = case kept > 2 * ring_lines {
    True -> #(list.take(ring, ring_lines), ring_lines)
    False -> #(ring, kept)
  }
  Lines(..lines, ring:, kept:, next_sequence: lines.next_sequence + 1)
}

/// The level a line's words give it. The rules apply to the message the
/// updater's script wrote (after its stamp, before the last lines it copied
/// from a container): a container's own words never change what the updater
/// said. Bad words win over warn words, and warn over ok.
pub fn level(source: Source, text: String) -> Level {
  let message = message_of(text)
  case words_level(message), source {
    LevelInfo, LaunchdLog -> launchd_level(text)
    found, _ -> found
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
  case
    string.starts_with(text, "fatal:")
    || string.starts_with(text, "Error:")
    || string.starts_with(text, "gh: API rate limit")
    || is_a_bash_error(text)
  {
    True -> LevelBad
    False -> LevelInfo
  }
}

/// Whether the line holds `: line N: `, how bash names the line of a script
/// that failed.
fn is_a_bash_error(text: String) -> Bool {
  case string.split(text, ": line ") {
    [_, ..after] ->
      list.any(after, fn(rest) {
        let digits = string.to_graphemes(rest) |> list.take_while(is_a_digit)
        digits != []
        && string.starts_with(
          string.drop_start(rest, list.length(digits)),
          ": ",
        )
      })
    [] -> False
  }
}

fn is_a_digit(character: String) -> Bool {
  case character {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
