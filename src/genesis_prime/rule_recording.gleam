//// A recording of one process's rule: every input the rule took and the step
//// it returned, from the process's first input to its last. Replaying it folds
//// the inputs through the rule and compares the steps, with no other process,
//// socket, clock or database.
////
//// The file is a series of records, each a 32-bit big-endian length then that
//// many bytes of one Erlang external term: the header first, then one `Taken`
//// per input, then `End`. A file without `End`, or whose `End` count differs
//// from the records before it, is incomplete and never replays.

import genesis_prime/step.{type Input, type Rule, type Step}
import gleam/bit_array
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// The version of this file format; a reader refuses any other.
pub const format = 1

/// What a replay must match before it folds the inputs through the rule.
pub type Header(settings) {
  Header(
    format: Int,
    /// The rule's module, such as `genesis_prime/login/connection`.
    rule: String,
    /// The client build the session was played on.
    client_build: Int,
    /// A digest of the game table files the rule reads, or `None` for a rule
    /// that reads no table.
    tables_digest: Option(String),
    /// The settings the rule was made with.
    settings: settings,
    /// A digest of every type the rule's state, input, step and settings
    /// reach. A replay whose rule's digest differs fails with "record again".
    types_digest: String,
  )
}

/// One record after the header.
pub type Record(message, answer, outgoing, request) {
  /// An input and the step the rule returned for it.
  Taken(input: Input(message, answer), step: Step(outgoing, request))
  /// The last record: how many `Taken` records came before it.
  End(count: Int)
}

/// Why a recording does not replay.
pub type ReplayFailure(outgoing, request) {
  /// The bytes end inside a record, or before `End`: the process crashed or
  /// the file was cut. `records` counts the whole records read.
  Incomplete(records: Int)
  /// `End` counts another number of records than the file holds.
  CountDiffers(end: Int, records: Int)
  /// The header is of another format, rule, settings or type digest, so the
  /// session must be recorded again; `reason` names which.
  RecordAgain(reason: String)
  /// The record at `index` (from 0, the header being 0) is not a term of
  /// this format: a byte of it changed, or it was cut.
  NotARecord(index: Int)
  /// Folding the input at `index` (from 0) gives another step than the one
  /// recorded.
  StepDiffers(
    index: Int,
    recorded: Step(outgoing, request),
    replayed: Step(outgoing, request),
  )
}

/// The bytes of one record: its 32-bit big-endian length, then the record as
/// an Erlang external term.
pub fn encode(record: a) -> BitArray {
  let term = term_to_binary(record)
  <<bit_array.byte_size(term):size(32), term:bits>>
}

/// Folds every recorded input through `rule`, from its first state, and
/// compares each step with the recorded one. `types_digest` is the digest of
/// the rule's types as the code stands; a header with another refuses to
/// replay. Returns how many inputs replayed. The header's rule name and type
/// digest are checked before any input is read as the rule's types.
pub fn replay(
  bytes bytes: BitArray,
  rule rule: Rule(settings, state, message, answer, outgoing, request),
  types_digest types_digest: String,
) -> Result(Int, ReplayFailure(outgoing, request)) {
  use records <- result.try(split(bytes, []))
  case records {
    [] -> Error(Incomplete(records: 0))
    [first, ..rest] -> {
      use header <- result.try(
        decode_header(first) |> result.replace_error(NotARecord(index: 0)),
      )
      use Nil <- result.try(check_header(header:, rule:, types_digest:))
      fold(records: rest, rule:, state: rule.new(rule.settings), index: 0)
    }
  }
}

/// The header and every record a recording holds, in order, for a person or
/// a test to look at; it checks no header and folds nothing.
pub fn read(
  bytes: BitArray,
) -> Result(
  #(Header(settings), List(Record(message, answer, outgoing, request))),
  ReplayFailure(outgoing, request),
) {
  use records <- result.try(split(bytes, []))
  case records {
    [] -> Error(Incomplete(records: 0))
    [first, ..rest] -> {
      use header <- result.try(
        decode_header(first) |> result.replace_error(NotARecord(index: 0)),
      )
      use decoded <- result.map(
        list.index_map(rest, fn(record, index) { #(record, index + 1) })
        |> list.try_map(fn(numbered) {
          decode_record(numbered.0)
          |> result.replace_error(NotARecord(index: numbered.1))
        }),
      )
      #(header, decoded)
    }
  }
}

/// The records' bytes, each without its length, or `Incomplete` when the
/// bytes end inside one.
fn split(
  bytes: BitArray,
  records: List(BitArray),
) -> Result(List(BitArray), ReplayFailure(outgoing, request)) {
  case bytes {
    <<>> -> Ok(list.reverse(records))
    <<length:size(32), record:bytes-size(length), rest:bytes>> ->
      split(rest, [record, ..records])
    _ -> Error(Incomplete(records: list.length(records)))
  }
}

fn check_header(
  header header: Header(settings),
  rule rule: Rule(settings, state, message, answer, outgoing, request),
  types_digest types_digest: String,
) -> Result(Nil, ReplayFailure(outgoing, request)) {
  case header {
    Header(format: version, ..) if version != format ->
      Error(RecordAgain(reason: "the file format"))
    Header(rule: name, ..) if name != rule.name ->
      Error(RecordAgain(reason: "the rule"))
    Header(types_digest: digest, ..) if digest != types_digest ->
      Error(RecordAgain(reason: "the rule's types"))
    Header(settings:, ..) if settings != rule.settings ->
      Error(RecordAgain(reason: "the rule's settings"))
    Header(..) -> Ok(Nil)
  }
}

fn fold(
  records records: List(BitArray),
  rule rule: Rule(settings, state, message, answer, outgoing, request),
  state state: state,
  index index: Int,
) -> Result(Int, ReplayFailure(outgoing, request)) {
  case records {
    [] -> Error(Incomplete(records: index + 1))
    [bytes, ..rest] ->
      case decode_record(bytes) {
        Error(Nil) -> Error(NotARecord(index: index + 1))
        Ok(End(count:)) ->
          case rest, count == index {
            [], True -> Ok(index)
            [], False -> Error(CountDiffers(end: count, records: index))
            [_, ..], _ -> Error(NotARecord(index: index + 2))
          }
        Ok(Taken(input:, step: recorded)) -> {
          let #(state, replayed) = rule.step(state, input)
          case replayed == recorded {
            True -> fold(records: rest, rule:, state:, index: index + 1)
            False -> Error(StepDiffers(index:, recorded:, replayed:))
          }
        }
      }
  }
}

@external(erlang, "erlang", "term_to_binary")
fn term_to_binary(term: a) -> BitArray

/// The header the bytes hold, when they are a header term.
@external(erlang, "rule_recording_ffi", "decode_header")
fn decode_header(bytes: BitArray) -> Result(Header(settings), Nil)

/// The record the bytes hold, when they are a `Taken` or `End` term.
@external(erlang, "rule_recording_ffi", "decode_record")
fn decode_record(
  bytes: BitArray,
) -> Result(Record(message, answer, outgoing, request), Nil)
