//// A recording of what one connection's shell took and wrote: each input it
//// took, with the time it carried, and each write, as bytes. It holds nothing
//// of the server's own types, so a change to a rule's internal types never
//// makes a recording refuse to replay.
////
//// The file is JSON lines, one file for each connection, written as the shell
//// takes inputs and writes:
////
//// ```
//// header   {"format":1,"rule":"genesis_prime/login/auth_connection",
////           "client_build":16042,"tables_digest":null,"seed":"<hex>",
////           "accept_ordinal":3,
////           "realm":{"id":1,"name":"Genesis","address":..,"port":..}}
//// an input {"sequence":41,"monotonic_ms":..,"filetime":..,"in":"read","bytes":"<hex>"}
////          {"sequence":43,"monotonic_ms":..,"filetime":..,"in":"answered","outcome":"answer"}
////          {"sequence":47,"monotonic_ms":..,"filetime":..,"in":"timer_fired","timer":2}
////          "in" is one of accepted, read, answered, timer_fired, peer_closed,
////          read_failed, write_failed, woken, watch_ended, stopping
//// a write  {"sequence":42,"out":"<hex>"}
//// the end  {"sequence":52,"closed":"client"}     or "server"
//// ```
////
//// - **Sequence.** Every line holds a number from the node's one counter
////   (`runtime.unique_id`), taken as the line's event happens: before the
////   socket is given a write's bytes, and as an input is taken. The lines of
////   every connection of a session, sorted by it, are the order the node saw
////   them in, so a replay walks them in that order.
//// - **Settings in the bytes.** A server setting that shows in the bytes the
////   server writes is recorded in the header, so a replay builds the server
////   from the recording and no machine's value lives in the repository: the
////   realm the auth server hands the client to (`realm`, `null` for a rule
////   that writes none).
//// - **Time.** An input line holds the whole `Now` the shell's clock gave the
////   input: the monotonic clock and the FILETIME. A write line holds none: the
////   bytes depend on the time of the input whose step wrote them, and a replay
////   gives that input the same `Now`.
//// - **Accept ordinal.** The place of the connection among those its server
////   accepted, given with its script as the shell took the socket, so the
////   order of accepts is recorded and never inferred from times.
//// - **The end.** The closing line names the side that ended the connection:
////   the client when the shell's last input was the socket's close, the server
////   otherwise. A file with no closing line, or whose last line is cut, is a
////   cut recording.
//// - **What an input line leaves out.** The messages of other processes, the
////   answers to asks and the failures' reasons are the rule's own types, so a
////   line holds only the kind of input and, for an answer, how the ask ended.
////   A replay gets the same messages and answers by running the real services.

import genesis_prime/seed.{type Seed}
import genesis_prime/step.{type Now, Now}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The version of this file format; a reader refuses any other.
pub const format = 1

/// What a replay must match before it plays the lines.
pub type Header {
  Header(
    format: Int,
    /// The rule's module, such as `genesis_prime/login/sts_connection`.
    rule: String,
    /// The client build the session was played on.
    client_build: Int,
    /// A digest of the game table files the rule reads, or `None` for a rule
    /// that reads no table.
    tables_digest: Option(String),
    /// The seed the rule's random values are all drawn from.
    seed: Seed,
    /// The place of the connection among those its server accepted.
    accept_ordinal: Int,
    /// The realm the auth server handed the client to, when the rule writes
    /// it.
    realm: Option(Realm),
  )
}

/// The realm the auth server hands the client to, as the server writes it: its
/// id and name, and the address and port of its game server.
pub type Realm {
  Realm(id: Int, name: String, address: Int, port: Int)
}

/// How an ask ended, without the answer, which is the rule's own type.
pub type Outcome {
  Answer
  NotRunning
  EndedBeforeAnswer
  NoAnswerInTime
  StoppedWaiting
}

/// One kind of input the shell takes. Only what the replay needs to cause or
/// to wait for is kept.
pub type Input {
  /// The connection's socket is the process's own: the first input.
  Accepted
  /// Bytes the client sent, as the socket delivered them.
  Read(bytes: BitArray)
  /// The outcome of the ask that ended the rule's last step.
  Answered(outcome: Outcome)
  /// A timer the rule started fired; `timer` is the number inside its
  /// `TimerId`.
  TimerFired(timer: Int)
  /// The client closed the connection.
  PeerClosed
  ReadFailed
  WriteFailed
  /// Another process sent the connection a message.
  Woken
  /// A process the rule watched ended.
  WatchEnded
  /// The server is stopping.
  Stopping
}

/// Whether two inputs are of one kind, whatever they carry: a replay matches the
/// input its shell took with the recorded one by kind, and the bytes, the
/// outcome or the timer's number may differ.
pub fn same_kind(first first: Input, second second: Input) -> Bool {
  case first, second {
    Accepted, Accepted -> True
    Read(..), Read(..) -> True
    Answered(..), Answered(..) -> True
    TimerFired(..), TimerFired(..) -> True
    PeerClosed, PeerClosed -> True
    ReadFailed, ReadFailed -> True
    WriteFailed, WriteFailed -> True
    Woken, Woken -> True
    WatchEnded, WatchEnded -> True
    Stopping, Stopping -> True
    Accepted, _
    | Read(..), _
    | Answered(..), _
    | TimerFired(..), _
    | PeerClosed, _
    | ReadFailed, _
    | WriteFailed, _
    | Woken, _
    | WatchEnded, _
    | Stopping, _
    -> False
  }
}

/// Which side ended the connection.
pub type Side {
  Client
  Server
}

/// One line after the header and before the closing line.
pub type Line {
  /// An input the shell took, with the `Now` its clock gave it.
  Took(sequence: Int, at: Now, input: Input)
  /// Bytes the shell wrote to the socket, which the socket took.
  Wrote(sequence: Int, bytes: BitArray)
}

/// The last line: the connection ended.
pub type Closing {
  Closing(sequence: Int, by: Side)
}

/// A recording read whole: its header, its lines in the order written and its
/// closing line.
pub type Recording {
  Recording(header: Header, lines: List(Line), closing: Closing)
}

/// Why a file is not a recording that can be played.
pub type ReadFailure {
  /// The file ends before its closing line, or inside a line: the server
  /// stopped mid-session or the file was cut. `lines` counts the whole lines
  /// read, the header included.
  Cut(lines: Int)
  /// The header is of another format; the session must be recorded again.
  OtherFormat(found: Int)
  /// The line at `line` (from 0, the header being 0) is not a line of this
  /// format, or its sequence number does not grow, with what is wrong with it.
  NotALine(line: Int, reason: String)
}

/// The header as one JSON line, ending in a line feed.
pub fn encode_header(header header: Header) -> String {
  line_of([
    #("format", json.int(header.format)),
    #("rule", json.string(header.rule)),
    #("client_build", json.int(header.client_build)),
    #("tables_digest", json.nullable(header.tables_digest, json.string)),
    #("seed", json.string(hex(bytes: seed.bytes(header.seed)))),
    #("accept_ordinal", json.int(header.accept_ordinal)),
    #("realm", json.nullable(header.realm, realm_json)),
  ])
}

/// A line as one JSON line, ending in a line feed.
pub fn encode_line(line line: Line) -> String {
  case line {
    Took(sequence:, at:, input:) ->
      line_of(list.append(
        [
          #("sequence", json.int(sequence)),
          #("monotonic_ms", json.int(at.monotonic_ms)),
          #("filetime", json.int(at.filetime)),
        ],
        input_entries(input),
      ))
    Wrote(sequence:, bytes:) ->
      line_of([
        #("sequence", json.int(sequence)),
        #("out", json.string(hex(bytes:))),
      ])
  }
}

/// The closing line as one JSON line, ending in a line feed.
pub fn encode_closing(closing closing: Closing) -> String {
  line_of([
    #("sequence", json.int(closing.sequence)),
    #("closed", json.string(side_name(closing.by))),
  ])
}

fn line_of(entries: List(#(String, Json))) -> String {
  json.to_string(json.object(entries)) <> "\n"
}

/// The keys an input adds to its line after the time: its kind, and the bytes,
/// the outcome or the timer's number where it has one.
fn input_entries(input: Input) -> List(#(String, Json)) {
  case input {
    Accepted -> [kind("accepted")]
    Read(bytes:) -> [kind("read"), #("bytes", json.string(hex(bytes:)))]
    Answered(outcome:) -> [
      kind("answered"),
      #("outcome", json.string(outcome_name(outcome))),
    ]
    TimerFired(timer:) -> [kind("timer_fired"), #("timer", json.int(timer))]
    PeerClosed -> [kind("peer_closed")]
    ReadFailed -> [kind("read_failed")]
    WriteFailed -> [kind("write_failed")]
    Woken -> [kind("woken")]
    WatchEnded -> [kind("watch_ended")]
    Stopping -> [kind("stopping")]
  }
}

fn kind(name: String) -> #(String, Json) {
  #("in", json.string(name))
}

fn outcome_name(outcome: Outcome) -> String {
  case outcome {
    Answer -> "answer"
    NotRunning -> "not_running"
    EndedBeforeAnswer -> "ended_before_answer"
    NoAnswerInTime -> "no_answer_in_time"
    StoppedWaiting -> "stopped_waiting"
  }
}

fn side_name(side: Side) -> String {
  case side {
    Client -> "client"
    Server -> "server"
  }
}

fn realm_json(realm: Realm) -> Json {
  json.object([
    #("id", json.int(realm.id)),
    #("name", json.string(realm.name)),
    #("address", json.int(realm.address)),
    #("port", json.int(realm.port)),
  ])
}

/// The bytes as lower-case hexadecimal, the way a recording, a fixture and a
/// failure's text write them.
pub fn hex(bytes bytes: BitArray) -> String {
  string.lowercase(bit_array.base16_encode(bytes))
}

/// The recording a file's text holds. A file whose last line is cut, or that
/// has no closing line, is `Cut`; each line's sequence number must be larger
/// than the one before.
pub fn read(text text: String) -> Result(Recording, ReadFailure) {
  // Every line ends in a line feed, so what follows the last one is a line
  // the writer did not finish, or nothing.
  let pieces = string.split(text, "\n")
  let whole = list.take(pieces, list.length(pieces) - 1)
  let unfinished = list.last(pieces) |> result.unwrap("")
  case whole {
    [] -> Error(Cut(lines: 0))
    [first, ..rest] -> {
      use header <- result.try(read_header(first))
      use #(lines, closing) <- result.try(
        read_lines(lines: rest, number: 1, after: None, so_far: []),
      )
      case closing, unfinished {
        Some(closing), "" -> Ok(Recording(header:, lines:, closing:))
        Some(_), _ ->
          Error(NotALine(
            line: list.length(whole),
            reason: "text follows the closing line",
          ))
        None, _ -> Error(Cut(lines: list.length(whole)))
      }
    }
  }
}

/// The header of the first line: its format is read first, so a file of
/// another format is refused as that and not as a line it cannot read.
fn read_header(text: String) -> Result(Header, ReadFailure) {
  let format_only = {
    use found <- decode.field("format", decode.int)
    decode.success(found)
  }
  use found <- result.try(parse(text:, line: 0, using: format_only))
  case found == format {
    False -> Error(OtherFormat(found:))
    True -> parse(text:, line: 0, using: header_decoder())
  }
}

fn header_decoder() -> decode.Decoder(Header) {
  use format <- decode.field("format", decode.int)
  use rule <- decode.field("rule", decode.string)
  use client_build <- decode.field("client_build", decode.int)
  use tables_digest <- decode.field(
    "tables_digest",
    decode.optional(decode.string),
  )
  use seed <- decode.field("seed", seed_decoder())
  use accept_ordinal <- decode.field("accept_ordinal", decode.int)
  use realm <- decode.field("realm", decode.optional(realm_decoder()))
  decode.success(Header(
    format:,
    rule:,
    client_build:,
    tables_digest:,
    seed:,
    accept_ordinal:,
    realm:,
  ))
}

fn realm_decoder() -> decode.Decoder(Realm) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use address <- decode.field("address", decode.int)
  use port <- decode.field("port", decode.int)
  decode.success(Realm(id:, name:, address:, port:))
}

/// A seed written as hexadecimal: 32 bytes, no other length.
fn seed_decoder() -> decode.Decoder(Seed) {
  decode.then(hex_decoder(), fn(bytes) {
    case seed.from_bytes(bytes) {
      Ok(seed) -> decode.success(seed)
      Error(seed.WrongLength(..)) ->
        decode.failure(
          seed.zeros(),
          "a seed of " <> int.to_string(seed.byte_count) <> " bytes",
        )
    }
  })
}

fn hex_decoder() -> decode.Decoder(BitArray) {
  decode.then(decode.string, fn(text) {
    case bit_array.base16_decode(text) {
      Ok(bytes) -> decode.success(bytes)
      Error(Nil) -> decode.failure(<<>>, "bytes in hexadecimal")
    }
  })
}

/// One line after the header, as the keys it may hold: which of the three
/// kinds of line it is is told by `in`, `out` and `closed`.
type Raw {
  Raw(
    sequence: Int,
    kind: Option(String),
    out: Option(BitArray),
    closed: Option(String),
    monotonic_ms: Option(Int),
    filetime: Option(Int),
    bytes: Option(BitArray),
    outcome: Option(String),
    timer: Option(Int),
  )
}

fn raw_decoder() -> decode.Decoder(Raw) {
  use sequence <- decode.field("sequence", decode.int)
  use kind <- decode.optional_field("in", None, decode.optional(decode.string))
  use out <- decode.optional_field("out", None, decode.optional(hex_decoder()))
  use closed <- decode.optional_field(
    "closed",
    None,
    decode.optional(decode.string),
  )
  use monotonic_ms <- decode.optional_field(
    "monotonic_ms",
    None,
    decode.optional(decode.int),
  )
  use filetime <- decode.optional_field(
    "filetime",
    None,
    decode.optional(decode.int),
  )
  use bytes <- decode.optional_field(
    "bytes",
    None,
    decode.optional(hex_decoder()),
  )
  use outcome <- decode.optional_field(
    "outcome",
    None,
    decode.optional(decode.string),
  )
  use timer <- decode.optional_field("timer", None, decode.optional(decode.int))
  decode.success(Raw(
    sequence:,
    kind:,
    out:,
    closed:,
    monotonic_ms:,
    filetime:,
    bytes:,
    outcome:,
    timer:,
  ))
}

/// Reads the whole lines after the header, `number` being the first one's
/// place (the header is 0). Stops at the closing line, and refuses any line
/// after it.
fn read_lines(
  lines lines: List(String),
  number number: Int,
  after previous: Option(Int),
  so_far so_far: List(Line),
) -> Result(#(List(Line), Option(Closing)), ReadFailure) {
  case lines {
    [] -> Ok(#(list.reverse(so_far), None))
    [text, ..rest] -> {
      use raw <- result.try(parse(text:, line: number, using: raw_decoder()))
      use <- check_growing(raw:, number:, after: previous)
      use line <- result.try(line_of_raw(raw:, number:))
      case line {
        Ok(line) ->
          read_lines(
            lines: rest,
            number: number + 1,
            after: Some(raw.sequence),
            so_far: [line, ..so_far],
          )
        Error(closing) ->
          case rest {
            [] -> Ok(#(list.reverse(so_far), Some(closing)))
            [_, ..] ->
              Error(NotALine(
                line: number + 1,
                reason: "a line follows the closing line",
              ))
          }
      }
    }
  }
}

fn check_growing(
  raw raw: Raw,
  number number: Int,
  after previous: Option(Int),
  next next: fn() -> Result(a, ReadFailure),
) -> Result(a, ReadFailure) {
  case previous {
    Some(before) if raw.sequence <= before ->
      Error(NotALine(
        line: number,
        reason: "its sequence number "
          <> int.to_string(raw.sequence)
          <> " is not above the one before it, "
          <> int.to_string(before),
      ))
    Some(_) | None -> next()
  }
}

/// Why the keys of a line are no line of the format.
type Problem {
  NoTime
  MixedKinds
  NoSuchSide(name: String)
  NoSuchInput(name: String)
  NoBytes
  NoOutcome
  NoSuchOutcome(name: String)
  NoTimer
}

fn describe_problem(problem: Problem) -> String {
  case problem {
    NoTime -> "an input line holds no monotonic_ms and filetime"
    MixedKinds -> "a line is one of an input, a write and the closing line"
    NoSuchSide(name:) -> "no side closes as \"" <> name <> "\""
    NoSuchInput(name:) -> "no input is called \"" <> name <> "\""
    NoBytes -> "a read line holds no bytes"
    NoOutcome -> "an answered line holds no outcome"
    NoSuchOutcome(name:) -> "no ask ends as \"" <> name <> "\""
    NoTimer -> "a timer line holds no timer"
  }
}

/// The line the keys make: `Ok` a line before the end, `Error` the closing
/// line.
fn line_of_raw(
  raw raw: Raw,
  number number: Int,
) -> Result(Result(Line, Closing), ReadFailure) {
  line_of_keys(raw)
  |> result.map_error(fn(problem) {
    NotALine(line: number, reason: describe_problem(problem))
  })
}

fn line_of_keys(raw: Raw) -> Result(Result(Line, Closing), Problem) {
  case raw.kind, raw.out, raw.closed {
    Some(kind), None, None ->
      case raw.monotonic_ms, raw.filetime {
        Some(monotonic_ms), Some(filetime) ->
          input_of(kind:, raw:)
          |> result.map(fn(input) {
            Ok(Took(
              sequence: raw.sequence,
              at: Now(monotonic_ms:, filetime:),
              input:,
            ))
          })
        _, _ -> Error(NoTime)
      }
    None, Some(bytes), None -> Ok(Ok(Wrote(sequence: raw.sequence, bytes:)))
    None, None, Some("client") ->
      Ok(Error(Closing(sequence: raw.sequence, by: Client)))
    None, None, Some("server") ->
      Ok(Error(Closing(sequence: raw.sequence, by: Server)))
    None, None, Some(other) -> Error(NoSuchSide(name: other))
    _, _, _ -> Error(MixedKinds)
  }
}

fn input_of(kind kind: String, raw raw: Raw) -> Result(Input, Problem) {
  case kind, raw.bytes, raw.outcome, raw.timer {
    "accepted", _, _, _ -> Ok(Accepted)
    "read", Some(bytes), _, _ -> Ok(Read(bytes:))
    "read", None, _, _ -> Error(NoBytes)
    "answered", _, Some(outcome), _ ->
      outcome_of(outcome) |> result.map(fn(outcome) { Answered(outcome:) })
    "answered", _, None, _ -> Error(NoOutcome)
    "timer_fired", _, _, Some(timer) -> Ok(TimerFired(timer:))
    "timer_fired", _, _, None -> Error(NoTimer)
    "peer_closed", _, _, _ -> Ok(PeerClosed)
    "read_failed", _, _, _ -> Ok(ReadFailed)
    "write_failed", _, _, _ -> Ok(WriteFailed)
    "woken", _, _, _ -> Ok(Woken)
    "watch_ended", _, _, _ -> Ok(WatchEnded)
    "stopping", _, _, _ -> Ok(Stopping)
    other, _, _, _ -> Error(NoSuchInput(name: other))
  }
}

fn outcome_of(name: String) -> Result(Outcome, Problem) {
  case name {
    "answer" -> Ok(Answer)
    "not_running" -> Ok(NotRunning)
    "ended_before_answer" -> Ok(EndedBeforeAnswer)
    "no_answer_in_time" -> Ok(NoAnswerInTime)
    "stopped_waiting" -> Ok(StoppedWaiting)
    other -> Error(NoSuchOutcome(name: other))
  }
}

/// Reads one line of text with a decoder, naming the line when it is not JSON
/// of the shape.
fn parse(
  text text: String,
  line line: Int,
  using decoder: decode.Decoder(a),
) -> Result(a, ReadFailure) {
  json.parse(from: text, using: decoder)
  |> result.map_error(fn(error) {
    NotALine(line:, reason: describe_json_error(error))
  })
}

fn describe_json_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "the JSON ends before the line does"
    json.UnexpectedByte(byte) -> "the JSON has an unexpected byte " <> byte
    json.UnexpectedSequence(sequence) ->
      "the JSON has an unexpected sequence " <> sequence
    json.UnableToDecode(errors) ->
      "the JSON does not hold what a line holds: "
      <> string.join(
        list.map(errors, fn(error) {
          "expected "
          <> error.expected
          <> ", found "
          <> error.found
          <> " at "
          <> string.join(error.path, "/")
        }),
        "; ",
      )
  }
}
