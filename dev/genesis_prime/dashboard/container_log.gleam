//// The rules of reading a container's log through `podman logs`, which the
//// Logs page follows for the play server's container and its database's: what
//// podman printed becomes lines and a cursor, the container's id says whether
//// it is the one being followed, and each way podman cannot answer becomes one
//// reason. Nothing here runs a program.
////
//// ```text
//// inspect ─► id ─► plan(tracking, id) ─► arguments of logs, mark
//// logs ───► output ─► split ─► lines, podman's words
////                         │ take(cursor)
////                         └─► the lines not shown yet ─► bytes for `log_lines.feed`, new cursor
//// ```
////
//// - `podman logs --timestamps` puts the line's second, as the Mac's zone writes
////   it (`2026-11-20T09:10:12-05:00`), and a space before every line's text, and
////   nothing before podman's own error text; a line with that prefix is a log
////   line, any other is podman's words (never a line of the log).
//// - `--since` has a resolution of one second, so a read from the last line's
////   second gives that second's lines again. The cursor is that second's text and
////   the number of its lines already shown, and a read drops that many lines of
////   that second from its head. The token is passed back to podman as it was
////   printed.
//// - A container's id changes when it is replaced (the deploy script removes
////   and runs it again) and stays when it restarts, so the same id continues
////   from the cursor, a new id shows the replaced mark and reads the new
////   container's tail, and a container that is missing for a while and returns
////   with its id is the same one.
//// - A read takes the last `first_tail_lines` lines of a container, or the last
////   `later_tail_lines` since the cursor: a log that gained more between two reads
////   loses its oldest lines without a mark (a stated limit; a read is every two
////   seconds). Both numbers are guesses.
//// - Podman answers a missing container, a machine that is not reachable and a
////   program it cannot run with exit 125 and its own words, so the reason is read
////   from the words. A failure no row names shows its first line, cut at
////   `reason_cap_characters`.
//// - The container names are `lib.sh`'s `server_container` and
////   `postgres_container` (a test holds the two together). No name or argument
////   comes from a request, and none starts with a dash.
////
//// Not handled: a fraction of a second in the prefix (podman prints whole
//// seconds), so such a line would be podman's words; a read cut by the tail
//// that also cut the head of the cursor's own second shows that second's lines
//// the cut took as already shown.

import genesis_prime/dashboard/follow.{
  type Trouble, NotThere, PodmanUnreachable, Unreadable,
}
import genesis_prime/dashboard/log_lines.{
  type Mark, type Source, ContainerReplaced, DatabaseLog, LaunchdLog, ServerLog,
  UpdaterLog,
}
import genesis_prime/dashboard/script.{
  type Failure, type Finished, DeadlineReached, Finished, NotExecutable,
  NotFound, NotStarted,
}
import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The server's container, as `lib.sh` names it (`server_container`).
pub const server_container = "genesis-play"

/// The play database's container, as `lib.sh` names it (`postgres_container`).
pub const database_container = "genesis-play-postgres"

/// How many lines the first read of a container takes, and the read after a
/// replacement: a guess (the play database's log holds 375 lines in 11 days).
const first_tail_lines = 1000

/// How many lines a read since the cursor takes at most: a guess, a read every
/// two seconds of a container that logs 2,500 lines in that time.
const later_tail_lines = 5000

/// How many characters of podman's words show as the reason of a failure no
/// row names: a guess.
const reason_cap_characters = 200

/// The container a source is the log of; the updater's and launchd's logs are
/// files.
pub fn container_name(source: Source) -> Result(String, Nil) {
  case source {
    ServerLog -> Ok(server_container)
    DatabaseLog -> Ok(database_container)
    UpdaterLog | LaunchdLog -> Error(Nil)
  }
}

/// A line of a container's log: the second podman printed before it, as it was
/// printed, and its text as bytes, which need not be UTF-8.
pub type Line {
  Line(token: String, text: BitArray)
}

/// What a read printed: the log's lines, and podman's own words.
pub type Output {
  Output(lines: List(Line), words: List(String))
}

/// Where a container's log was read to: the second of the last line shown and
/// how many lines of that second were shown.
pub type Cursor {
  Cursor(token: String, taken: Int)
}

/// What a follower knows of the container: the id it read last and the cursor.
/// A cursor is none until a line was read.
pub type Tracking {
  Tracking(id: Option(String), cursor: Option(Cursor))
}

/// A container not yet read.
pub const unread = Tracking(id: None, cursor: None)

/// What a read does after the container's id is known: the tracking to read
/// with, the mark to show before the lines, and the arguments of `podman`.
pub type Plan {
  Plan(tracking: Tracking, mark: Option(Mark), arguments: List(String))
}

/// What a read gave: the tracking after it, the mark to show before its lines,
/// and the text of its new lines, each ended by a newline, for
/// `log_lines.feed`.
pub type Read {
  Read(tracking: Tracking, mark: Option(Mark), bytes: BitArray)
}

/// Splits what `podman logs --timestamps` printed. The piece after the last
/// newline is dropped: a read that was cut ends inside a line, which is read
/// whole the next time.
fn split(output: BitArray) -> Output {
  let pieces = pieces_of(whole: output, start: 0, index: 0, found: [])
  let found =
    list.fold(pieces, #([], []), fn(found, piece) {
      let #(lines, words) = found
      case prefixed(piece) {
        Ok(line) -> #([line, ..lines], words)
        Error(Nil) -> #(lines, [words_of(piece), ..words])
      }
    })
  Output(lines: list.reverse(found.0), words: list.reverse(found.1))
}

/// The bytes before each newline of `whole`, in order, counted from `start`;
/// what follows the last newline is dropped.
fn pieces_of(
  whole whole: BitArray,
  start start: Int,
  index index: Int,
  found found: List(BitArray),
) -> List(BitArray) {
  case bit_array.slice(whole, index, 1) {
    Ok(<<0x0A>>) -> {
      let assert Ok(piece) = bit_array.slice(whole, start, index - start)
        as "the piece is inside the bytes"
      pieces_of(whole:, start: index + 1, index: index + 1, found: [
        piece,
        ..found
      ])
    }
    Ok(_) -> pieces_of(whole:, start:, index: index + 1, found:)
    Error(Nil) -> list.reverse(found)
  }
}

/// A piece that starts with the second and a space is a line.
fn prefixed(piece: BitArray) -> Result(Line, Nil) {
  use #(token_bytes, text) <- result.try(split_at_a_space(piece, 0))
  use token <- result.try(bit_array.to_string(token_bytes))
  case is_a_token(token) {
    True -> Ok(Line(token:, text:))
    False -> Error(Nil)
  }
}

/// The bytes before the first space and the bytes after it, when there is a
/// space within a token's length.
fn split_at_a_space(
  piece: BitArray,
  index: Int,
) -> Result(#(BitArray, BitArray), Nil) {
  use <- bool.guard(when: index > 32, return: Error(Nil))
  case bit_array.slice(piece, index, 1) {
    Ok(<<0x20>>) -> {
      let assert Ok(token) = bit_array.slice(piece, 0, index)
        as "the token is inside the bytes"
      let assert Ok(text) =
        bit_array.slice(
          piece,
          index + 1,
          bit_array.byte_size(piece) - index - 1,
        )
        as "the text is inside the bytes"
      Ok(#(token, text))
    }
    Ok(_) -> split_at_a_space(piece, index + 1)
    Error(Nil) -> Error(Nil)
  }
}

/// Whether the text is a second as podman prints it: `YYYY-MM-DDThh:mm:ss`
/// and a zone, `Z` or `+hh:mm` or `-hh:mm`.
fn is_a_token(token: String) -> Bool {
  case string.to_graphemes(token) {
    [
      y1,
      y2,
      y3,
      y4,
      "-",
      m1,
      m2,
      "-",
      d1,
      d2,
      "T",
      h1,
      h2,
      ":",
      n1,
      n2,
      ":",
      s1,
      s2,
      ..zone
    ] ->
      list.all(
        [y1, y2, y3, y4, m1, m2, d1, d2, h1, h2, n1, n2, s1, s2],
        is_a_digit,
      )
      && case zone {
        ["Z"] -> True
        [sign, z1, z2, ":", z3, z4] ->
          { sign == "+" || sign == "-" }
          && list.all([z1, z2, z3, z4], is_a_digit)
        _ -> False
      }
    _ -> False
  }
}

fn is_a_digit(character: String) -> Bool {
  case character {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

/// Podman's words as text; a byte that is not UTF-8 is U+FFFD.
fn words_of(piece: BitArray) -> String {
  case bit_array.to_string(piece) {
    Ok(text) -> text
    Error(Nil) -> text_of_codepoints(piece, [])
  }
}

fn text_of_codepoints(rest: BitArray, found: List(UtfCodepoint)) -> String {
  case rest {
    <<code:utf8_codepoint, tail:bits>> ->
      text_of_codepoints(tail, [code, ..found])
    <<_, tail:bits>> -> {
      let assert Ok(replacement) = string.utf_codepoint(0xFFFD)
        as "U+FFFD is a codepoint"
      text_of_codepoints(tail, [replacement, ..found])
    }
    _ -> found |> list.reverse |> string.from_utf_codepoints
  }
}

/// Drops from the head of a read the lines of the cursor's second that were
/// shown already, and gives the lines that are new and the cursor after them.
/// The cursor stays when no line is new.
fn take(
  cursor cursor: Option(Cursor),
  lines lines: List(Line),
) -> #(List(Line), Option(Cursor)) {
  let new = case cursor {
    None -> lines
    Some(Cursor(token:, taken:)) -> drop_taken(lines:, token:, taken:)
  }
  case list.last(new) {
    Error(Nil) -> #(new, cursor)
    Ok(last) -> {
      let at_last = list.count(new, fn(line) { line.token == last.token })
      let before = case cursor {
        Some(Cursor(token:, taken:)) if token == last.token -> taken
        Some(_) | None -> 0
      }
      #(new, Some(Cursor(token: last.token, taken: before + at_last)))
    }
  }
}

/// The lines without the first `taken` lines of the head that are at `token`.
fn drop_taken(
  lines lines: List(Line),
  token token: String,
  taken taken: Int,
) -> List(Line) {
  case lines {
    [Line(token: at, ..), ..rest] if at == token && taken > 0 ->
      drop_taken(lines: rest, token:, taken: taken - 1)
    _ -> lines
  }
}

/// What to read of `container`, whose id is `id`, knowing what was tracked: a
/// first read, and a replaced container's, take the tail; the same container
/// continues from the cursor. A replaced container shows the mark.
pub fn plan(
  tracking tracking: Tracking,
  container container: String,
  id id: String,
) -> Plan {
  let replaced = case tracking.id {
    Some(known) -> known != id
    None -> False
  }
  let tracking = case replaced {
    True -> Tracking(id: Some(id), cursor: None)
    False -> Tracking(..tracking, id: Some(id))
  }
  Plan(
    tracking:,
    mark: case replaced {
      True -> Some(ContainerReplaced)
      False -> None
    },
    arguments: case tracking.cursor {
      Some(Cursor(token:, ..)) -> [
        "logs",
        "--timestamps",
        "--since",
        token,
        "--tail",
        int.to_string(later_tail_lines),
        container,
      ]
      None -> [
        "logs",
        "--timestamps",
        "--tail",
        int.to_string(first_tail_lines),
        container,
      ]
    },
  )
}

/// What a read gave after its plan: the new lines of its output and the
/// tracking with the cursor after them.
pub fn read(plan plan: Plan, output output: Output) -> Read {
  let #(new, cursor) = take(cursor: plan.tracking.cursor, lines: output.lines)
  Read(
    tracking: Tracking(..plan.tracking, cursor:),
    mark: plan.mark,
    bytes: bit_array.concat(
      list.map(new, fn(line) { <<line.text:bits, 0x0A>> }),
    ),
  )
}

/// The id `podman container inspect --format {{.Id}}` printed: 64 hexadecimal
/// characters on a line of their own.
pub fn container_id(
  answer: Result(Finished, Failure),
) -> Result(String, Trouble) {
  use output <- result.try(answered(answer))
  let text = bit_array.to_string(output) |> result.unwrap("")
  case string.split(text, "\n") {
    [id, ""] ->
      case
        string.length(id) == 64 && list.all(string.to_graphemes(id), is_hex)
      {
        True -> Ok(id)
        False -> Error(Unreadable("unreadable answer"))
      }
    _ -> Error(Unreadable("unreadable answer"))
  }
}

fn is_hex(character: String) -> Bool {
  is_a_digit(character)
  || case character {
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    _ -> False
  }
}

/// What `podman logs` printed, split; the output of a call that failed is
/// never taken for log text.
pub fn log_output(
  answer: Result(Finished, Failure),
) -> Result(Output, Trouble) {
  use output <- result.map(answered(answer))
  split(output)
}

/// The output of a call that ended with status 0, or the reason of any other
/// end.
fn answered(answer: Result(Finished, Failure)) -> Result(BitArray, Trouble) {
  case answer {
    Ok(Finished(output:, status: 0)) -> Ok(output)
    Ok(Finished(output:, status:)) -> Error(podman_said(split(output), status))
    Error(DeadlineReached(deadline_ms:)) -> Error(timed_out(deadline_ms))
    Error(NotFound(path:)) -> Error(Unreadable("cannot find " <> path))
    Error(NotExecutable(path:)) ->
      Error(Unreadable("cannot run " <> path <> ": it is not executable"))
    Error(NotStarted(path:, reason:)) ->
      Error(Unreadable("cannot start " <> path <> ": " <> reason))
  }
}

/// The reason of a read that was ended at its deadline.
pub fn timed_out(deadline_ms: Int) -> Trouble {
  Unreadable("timed out after " <> duration(deadline_ms))
}

fn duration(milliseconds: Int) -> String {
  case milliseconds % 1000 {
    0 -> int.to_string(milliseconds / 1000) <> " s"
    _ -> int.to_string(milliseconds) <> " ms"
  }
}

/// The reason in podman's words after a call that failed.
fn podman_said(output: Output, status: Int) -> Trouble {
  let words = list.filter(output.words, fn(words) { words != "" })
  let holds = fn(text) { list.any(words, string.contains(_, text)) }
  case holds("no such container"), holds("Cannot connect to Podman.") {
    True, _ -> NotThere
    False, True ->
      PodmanUnreachable(
        reason: case list.find(words, string.starts_with(_, "Error: ")) {
          Ok(error_line) -> string.drop_start(error_line, 7)
          Error(Nil) -> list.first(words) |> result.unwrap("")
        },
      )
    False, False ->
      case words {
        [first, ..] -> Unreadable(string.slice(first, 0, reason_cap_characters))
        [] -> Unreadable("exit status " <> int.to_string(status))
      }
  }
}
