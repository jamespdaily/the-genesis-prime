//// The one place the server writes a log line, over Erlang's logger. Every
//// line takes a `Who`, so each carries who and where as metadata under a
//// fixed key: `account`, `character` or `unit`, `process` or `map`, and
//// `message_name` and `message_number`. `Who` has no field for a password, a
//// session key or any other secret, so none can be logged through here, and
//// a code rule refuses a call to `logger`, `io:format` or `io:fwrite` from
//// anywhere else in `src/`.
////
//// The levels are the designing-processes skill's. Error is a bug, always
//// looked into. Warning is an outside failure the server recovered from.
//// Info is start, stop, login and logout. Debug is per-message detail, off
//// unless `configure` is told to turn it on.

import gleam/dict.{type Dict}
import gleam/option.{type Option, None}

/// Who and where a line is about. Each part is optional, because a line
/// about the server itself has no account and a line about a login has no
/// character.
pub type Who {
  Who(
    /// The account the line is about.
    account: Option(Int),
    /// The character or the unit the line is about.
    actor: Option(Actor),
    /// The process kind or the map the line is written from.
    place: Option(Place),
    /// The client message the line is about.
    message: Option(Message),
  )
}

/// The player's character or a unit of the world, which a line names by its
/// id, under the metadata key `character` or `unit`.
pub type Actor {
  Character(id: Int)
  Unit(id: Int)
}

/// Where a line is written from: a kind of process, named by the process's
/// own name, under the key `process`, or a map, named by its id, under the
/// key `map`.
pub type Place {
  Process(name: String)
  Map(id: Int)
}

/// A client message a line is about. A message the client's data names has
/// its name and its number, under the keys `message_name` and
/// `message_number`; one with no name in the client's data has its number
/// alone.
pub type Message {
  Named(name: String, number: Int)
  Numbered(number: Int)
}

/// One number a line carries beyond who and where: a count or a ratio.
pub type Number {
  Count(Int)
  Ratio(Float)
}

/// A line about nobody in particular: no account, no actor, no place and no
/// message.
pub const nobody = Who(account: None, actor: None, place: None, message: None)

/// Writes a line at error level: a bug, always looked into.
pub fn error(who: Who, text: String) -> Nil {
  todo as "write the line at logger's error level"
}

/// Writes a line at warning level: an outside failure the server recovered
/// from.
pub fn warning(who: Who, text: String) -> Nil {
  todo as "write the line at logger's warning level"
}

/// Writes a line at info level: start, stop, login or logout.
pub fn info(who: Who, text: String) -> Nil {
  todo as "write the line at logger's info level"
}

/// Writes a line at debug level: per-message detail. Nothing is written
/// unless `configure` turned debug on.
pub fn debug(who: Who, text: String) -> Nil {
  todo as "write the line at logger's debug level"
}

/// Writes a line at info level that also carries numbers, in one map under
/// the metadata key `numbers`, each under its name. A number's name is the
/// writer's own text, never client input.
pub fn info_with_numbers(
  who: Who,
  text: String,
  numbers: Dict(String, Number),
) -> Nil {
  todo as "write the line at info level with its numbers"
}

/// Sets which lines are written, from the start argument that says whether
/// debug is on: with it off, info and above are written, and with it on,
/// debug too. It sets the level of logger itself, which belongs to the whole
/// node, so the server's entry point calls it once, before the tree starts.
pub fn configure(debug debug: Bool) -> Nil {
  todo as "set logger's primary level from the debug argument"
}
