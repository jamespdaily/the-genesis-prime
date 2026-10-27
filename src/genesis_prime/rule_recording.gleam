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
import gleam/option.{type Option}

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
  todo as "the build follows the shape commit"
}

/// Folds every recorded input through `rule`, from its first state, and
/// compares each step with the recorded one. `types_digest` is the digest of
/// the rule's types as the code stands; a header with another refuses to
/// replay. Returns how many inputs replayed. The terms are read with
/// `binary_to_term` and `[safe]`, and only bytes the server wrote are read.
pub fn replay(
  bytes bytes: BitArray,
  rule rule: Rule(settings, state, message, answer, outgoing, request),
  types_digest types_digest: String,
) -> Result(Int, ReplayFailure(outgoing, request)) {
  todo as "the build follows the shape commit"
}
