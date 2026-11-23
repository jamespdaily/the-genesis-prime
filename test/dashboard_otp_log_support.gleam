//// Shared by the tests of the dashboard's grouped log entries and its
//// password mask: the real captures of a container's log (run by this
//// server's own image, or by this repository's own `pgo`), and the helpers
//// that feed lines to a log and cut bytes into reads.

import genesis_prime/dashboard/log_lines.{
  type Entry, type Level, type Lines, type Source, Line, Marker,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import simplifile

/// The lines of a capture in `test/fixture/otp_log`, as the dashboard's
/// reader gives them: without podman's `--timestamps` prefix, which every
/// line of a container's log has and the pgo captures lack.
pub fn capture(name: String) -> List(String) {
  let assert Ok(text) = simplifile.read("test/fixture/otp_log/" <> name)
    as { "the capture " <> name <> " is in the repository" }
  let assert Ok(lines) = list.reverse(string.split(text, "\n")) |> list.rest
    as "a capture ends with a newline"
  list.reverse(lines) |> list.map(without_podman_prefix)
}

/// A line without the `2026-11-20T09:10:12-05:00 ` that `--timestamps` writes.
fn without_podman_prefix(line: String) -> String {
  case string.split_once(line, " ") {
    Ok(#(prefix, rest)) ->
      case string.length(prefix) == 25 && string.contains(prefix, "T") {
        True -> rest
        False -> line
      }
    Error(Nil) -> line
  }
}

/// The bytes a log holds for these lines, each ended by a newline.
pub fn bytes_of(lines: List(String)) -> BitArray {
  list.map(lines, fn(line) { line <> "\n" })
  |> string.concat
  |> bit_array.from_string
}

/// A log of this source after one read of these lines.
pub fn fed(source source: Source, lines lines: List(String)) -> Lines {
  log_lines.feed(log_lines.new(source), bytes_of(lines))
}

/// Each entry's text and level, marks left out.
pub fn shown(lines: Lines) -> List(#(String, Level)) {
  list.filter_map(log_lines.entries(lines), fn(entry) {
    case entry {
      Line(text:, level:, ..) -> Ok(#(text, level))
      Marker(..) -> Error(Nil)
    }
  })
}

/// An entry's text, or nothing for a mark.
pub fn text_of(entry: Entry) -> String {
  case entry {
    Line(text:, ..) -> text
    Marker(..) -> ""
  }
}

/// The bytes cut into reads at each of the points (each taken modulo the
/// size, and in order).
pub fn split_at(
  bytes bytes: BitArray,
  points points: List(Int),
) -> List(BitArray) {
  let size = bit_array.byte_size(bytes)
  let sorted =
    list.map(points, fn(point) { point % int.max(size + 1, 1) })
    |> list.sort(int.compare)
    |> list.unique
  let #(chunks, start) =
    list.fold(sorted, #([], 0), fn(state, point) {
      let #(chunks, start) = state
      let assert Ok(chunk) = bit_array.slice(bytes, start, point - start)
      #([chunk, ..chunks], point)
    })
  let assert Ok(rest) = bit_array.slice(bytes, start, size - start)
  list.reverse([rest, ..chunks])
}

/// The invariant of the log's reads: these bytes fed to a new log of this
/// source in reads cut at the points give the same entries (text, level,
/// sequence number and cut mark) as one read of all of them, and no entry's
/// text is longer than the cap. A mark has no text.
pub fn reads_do_not_change_the_entries(
  source source: Source,
  bytes bytes: BitArray,
  points points: List(Int),
  cap_bytes cap_bytes: Int,
) -> Nil {
  let together = log_lines.feed(log_lines.new(source), bytes)
  let split =
    list.fold(split_at(bytes:, points:), log_lines.new(source), log_lines.feed)
  assert log_lines.entries(split) == log_lines.entries(together)
    as "the same entries however the bytes were cut into reads"
  list.each(log_lines.entries(split), fn(entry) {
    assert bit_array.byte_size(bit_array.from_string(text_of(entry)))
      <= cap_bytes
      as "an entry is at most the cap"
  })
}
