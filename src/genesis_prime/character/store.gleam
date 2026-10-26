//// The characters in Postgres: what character select asks of the database, run
//// through the pool, and each row read into a `Character` where it is read. A
//// character's statements name its account, so an account never reaches a
//// character of another.

import genesis_prime/character/select.{type Answer, type Command}
import pog

/// Carries out a command of character select against the database and says
/// how it went. A name another character has is `NameInUse`; an account with no
/// such character is `NotFound`; anything the database could not do is
/// `Unavailable`.
pub fn run(db db: pog.Connection, command command: Command) -> Answer {
  todo as "runs a command of character select"
}
