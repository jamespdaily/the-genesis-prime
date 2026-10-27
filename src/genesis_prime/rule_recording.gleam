//// A recording of one process's rule: every input the rule took and the step
//// it returned, from the process's first input to its last. Replaying it folds
//// the inputs through the rule and compares the steps, with no other process,
//// socket, clock or database.
////
//// The file is a series of records, each a 32-bit big-endian length then that
//// many bytes of one Erlang external term: the header first, then one `Taken`
//// per input, then `End`. A file without `End`, or whose `End` count differs
//// from the records before it, is incomplete and never replays.

import genesis_prime/step.{type Input, type Step}

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
    /// A digest of the game table files the server loaded.
    tables_digest: String,
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
