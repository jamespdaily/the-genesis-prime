//// The characters in Postgres: what character select asks of the database, run
//// through the pool, and each row read into a `Character` where it is read. A
//// character's statements name its account, so an account never reaches a
//// character of another.

import genesis_prime/character/character.{
  type Character, type NewCharacter, Appearance, Character, Place,
}
import genesis_prime/character/select.{
  type Answer, type Command, Deleted, Inserted, Loaded, NameInUse, NotFound,
  Renamed, Unavailable, Unknown,
}
import genesis_prime/character/sql
import genesis_prime/map/position.{Position}
import gleam/erlang/process
import gleam/list
import pog

/// The unique index on the lower case of a character's name
/// (`priv/migrations/0004_character_name_case.sql`), whose violation says that
/// another character has the name in some case.
const name_constraint = "character_name_lower_key"

/// Carries out a command of character select against the database and says
/// how it went. A name another character has is `NameInUse`; an account with no
/// such character is `NotFound`; a database that cannot be reached, or whose
/// reply to a read does not come, is `Unavailable`. A write whose connection
/// closes under it is `Unknown`: it may have committed before the reply was
/// lost, because pog's deadline for a query closes the socket whatever the
/// statement is doing. Any other failure of a statement is a bug in the
/// statement or the migration and crashes the caller.
pub fn run(db db: pog.Connection, command command: Command) -> Answer {
  carry_out(db:, command:, closed: closed_answer(command))
}

/// Runs the command's statement; `closed` is the answer when the connection
/// closes under it.
fn carry_out(
  db db: pog.Connection,
  command command: Command,
  closed closed: Answer,
) -> Answer {
  case command {
    select.LoadCharacters(account_id:) -> load(db:, account_id:, closed:)
    select.InsertCharacter(new) -> insert(db:, new:, closed:)
    select.RenameStored(account_id:, character_id:, name:) ->
      rename(db:, account_id:, character_id:, name:, closed:)
    select.DeleteStored(account_id:, character_id:) ->
      delete(db:, account_id:, character_id:, closed:)
  }
}

/// The answer of a command whose statement was sent when its connection closes.
/// A write may have committed before the reply was lost, so it is `Unknown`; a
/// read changes nothing, so it is `Unavailable`.
fn closed_answer(command: Command) -> Answer {
  case command {
    select.LoadCharacters(..) -> Unavailable
    select.InsertCharacter(..)
    | select.RenameStored(..)
    | select.DeleteStored(..) -> Unknown
  }
}

/// What the caller of `run_held` says once it knows its command holds a
/// connection: send the statement, or do not.
pub type Permission {
  Go
  Withheld
}

/// Carries out a command as `run` does, in a transaction, and calls
/// `connection_held` once the command has a connection of the pool and before
/// its first statement is sent; the statement is sent only when the call gives
/// `Go`. Once the call has said `Go` the statement can commit whatever the
/// caller does next, so the answer is the only truth about the command. A pool
/// that gives no connection, or a call that gives `Withheld`, is `Unavailable`
/// with nothing sent. A statement the database cancelled leaves the transaction
/// failed, and the commit that follows rolls it back, so the answer
/// `Unavailable` is true of the stored data. A connection that closes after the
/// go, whether Postgres ended the session or pgo's checkout deadline closed the
/// socket, leaves a write's outcome unknown: the answer is `Unknown`. A read
/// whose connection closes is `Unavailable`.
pub fn run_held(
  db db: pog.Connection,
  command command: Command,
  connection_held connection_held: fn() -> Permission,
) -> Answer {
  let closed = closed_answer(command)
  let sent = process.new_subject()
  let carried_out =
    pog.transaction(db, fn(transaction) {
      case connection_held() {
        Go -> {
          process.send(sent, Nil)
          Ok(carry_out(db: transaction, command:, closed:))
        }
        Withheld -> Error(Unavailable)
      }
    })
  let was_told_to_go = process.receive(sent, 0) == Ok(Nil)
  case carried_out {
    Ok(answer) -> answer
    Error(pog.TransactionQueryError(error)) ->
      case was_told_to_go {
        True -> failed(error, closed:)
        False -> failed(error, closed: Unavailable)
      }
    Error(pog.TransactionRolledBack(answer)) -> answer
  }
}

fn load(
  db db: pog.Connection,
  account_id account_id: Int,
  closed closed: Answer,
) -> Answer {
  case sql.characters_of_account(db, account_id) {
    Ok(returned) ->
      Loaded(list.map(returned.rows, fn(row) { from_list_row(row) }))
    Error(error) -> failed(error, closed:)
  }
}

fn insert(
  db db: pog.Connection,
  new new: NewCharacter,
  closed closed: Answer,
) -> Answer {
  let result =
    sql.insert_character(
      db,
      new.account_id,
      new.name,
      new.creation_id,
      new.gender,
      new.race_id,
      new.class_id,
      new.faction_id,
      new.experience,
      new.level,
      new.path,
      new.place.world_id,
      new.place.world_zone_id,
      new.place.position.x,
      new.place.position.y,
      new.place.position.z,
      new.appearance.customisation_labels,
      new.appearance.customisation_values,
      new.appearance.bone_values,
    )
  case result {
    Ok(pog.Returned(rows: [row], ..)) -> Inserted(from_insert_row(row))
    Ok(pog.Returned(..)) ->
      panic as "an insert of one character returned another number of rows"
    Error(error) -> failed(error, closed:)
  }
}

fn rename(
  db db: pog.Connection,
  account_id account_id: Int,
  character_id character_id: Int,
  name name: String,
  closed closed: Answer,
) -> Answer {
  case sql.rename_character(db, character_id, account_id, name) {
    Ok(pog.Returned(rows: [row], ..)) -> Renamed(from_rename_row(row))
    Ok(pog.Returned(rows: [], ..)) -> NotFound
    Ok(pog.Returned(..)) ->
      panic as "a rename of one character returned another number of rows"
    Error(error) -> failed(error, closed:)
  }
}

fn delete(
  db db: pog.Connection,
  account_id account_id: Int,
  character_id character_id: Int,
  closed closed: Answer,
) -> Answer {
  case sql.delete_character(db, character_id, account_id) {
    Ok(pog.Returned(rows: [row], ..)) -> Deleted(row.id)
    Ok(pog.Returned(rows: [], ..)) -> NotFound
    Ok(pog.Returned(..)) ->
      panic as "a delete of one character returned another number of rows"
    Error(error) -> failed(error, closed:)
  }
}

/// The code of Postgres's error for a statement it cancelled at the pool's
/// statement timeout (`pool.statement_timeout_ms`): query_canceled.
const query_canceled = "57014"

/// The code of Postgres's error transaction_timeout, raised when a transaction
/// outlives the pool's transaction timeout (`pool.transaction_timeout_ms`).
/// Postgres rolls the transaction back, so nothing of it committed.
const transaction_timeout = "25P04"

/// What a failed statement means: a database that is away, or one that
/// cancelled a statement, is an outside failure the server recovers from; a
/// name another character has is the player's own; anything else is a mistake
/// in a statement or the migration. A connection that closed under the
/// statement (`pog.QueryTimeout`) is `closed`, which the caller chooses by what
/// the command does to the data. A transaction that outlives its limit is ended
/// by Postgres with a FATAL error that closes the session, and pgo drops that
/// message and returns a closed socket (`pgo_handler.erl` lines 551-570 and
/// 593-594), so it reaches the store as `pog.QueryTimeout`; the
/// transaction_timeout branch covers that error only when Postgres returns it
/// without closing the connection.
fn failed(error: pog.QueryError, closed closed: Answer) -> Answer {
  case error {
    pog.ConnectionUnavailable -> Unavailable
    pog.QueryTimeout -> closed
    pog.PostgresqlError(code:, ..) if code == query_canceled -> Unavailable
    pog.PostgresqlError(code:, ..) if code == transaction_timeout -> Unavailable
    pog.ConstraintViolated(constraint:, ..) if constraint == name_constraint ->
      NameInUse
    pog.ConstraintViolated(..)
    | pog.PostgresqlError(..)
    | pog.UnexpectedArgumentCount(..)
    | pog.UnexpectedArgumentType(..)
    | pog.UnexpectedResultType(..) ->
      panic as "a character statement failed in a way the server does not expect: the statement or the migration is wrong"
  }
}

fn from_list_row(row: sql.CharactersOfAccountRow) -> Character {
  character_of(
    id: row.id,
    account_id: row.account_id,
    name: row.name,
    creation_id: row.creation_id,
    gender: row.gender,
    race_id: row.race_id,
    class_id: row.class_id,
    faction_id: row.faction_id,
    experience: row.experience,
    level: row.level,
    path: row.path,
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    position: Position(x: row.position_x, y: row.position_y, z: row.position_z),
    labels: row.customisation_labels,
    values: row.customisation_values,
    bones: row.bone_values,
    requires_rename: row.requires_rename,
    disabled: row.disabled,
  )
}

fn from_insert_row(row: sql.InsertCharacterRow) -> Character {
  character_of(
    id: row.id,
    account_id: row.account_id,
    name: row.name,
    creation_id: row.creation_id,
    gender: row.gender,
    race_id: row.race_id,
    class_id: row.class_id,
    faction_id: row.faction_id,
    experience: row.experience,
    level: row.level,
    path: row.path,
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    position: Position(x: row.position_x, y: row.position_y, z: row.position_z),
    labels: row.customisation_labels,
    values: row.customisation_values,
    bones: row.bone_values,
    requires_rename: row.requires_rename,
    disabled: row.disabled,
  )
}

fn from_rename_row(row: sql.RenameCharacterRow) -> Character {
  character_of(
    id: row.id,
    account_id: row.account_id,
    name: row.name,
    creation_id: row.creation_id,
    gender: row.gender,
    race_id: row.race_id,
    class_id: row.class_id,
    faction_id: row.faction_id,
    experience: row.experience,
    level: row.level,
    path: row.path,
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    position: Position(x: row.position_x, y: row.position_y, z: row.position_z),
    labels: row.customisation_labels,
    values: row.customisation_values,
    bones: row.bone_values,
    requires_rename: row.requires_rename,
    disabled: row.disabled,
  )
}

/// A character from the columns of one of its rows.
fn character_of(
  id id: Int,
  account_id account_id: Int,
  name name: String,
  creation_id creation_id: Int,
  gender gender: Int,
  race_id race_id: Int,
  class_id class_id: Int,
  faction_id faction_id: Int,
  experience experience: Int,
  level level: Int,
  path path: Int,
  world_id world_id: Int,
  world_zone_id world_zone_id: Int,
  position position: position.Position,
  labels labels: List(Int),
  values values: List(Int),
  bones bones: List(Int),
  requires_rename requires_rename: Bool,
  disabled disabled: Bool,
) -> Character {
  Character(
    id:,
    account_id:,
    name:,
    creation_id:,
    gender:,
    race_id:,
    class_id:,
    faction_id:,
    experience:,
    level:,
    path:,
    place: Place(world_id:, world_zone_id:, position:),
    appearance: Appearance(
      customisation_labels: labels,
      customisation_values: values,
      bone_values: bones,
    ),
    requires_rename:,
    disabled:,
  )
}
