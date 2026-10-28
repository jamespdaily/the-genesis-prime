//// What the tests of creating a character share. Character rows for the tests
//// that need a character in a database: one insert with the same race,
//// gender, faction, level, world, zone and position for each row, so a test
//// varies only the name, the class and the path it checks. One valid create
//// request, which a test varies with a record update, and the one result a
//// create, a delete or a rename answers with, decoded.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/mark_rename/sql as mark_rename_sql
import genesis_prime/message/create_character.{
  type CreateCharacter, CreateCharacter,
}
import genesis_prime/message/create_character_result.{type CreateCharacterResult}
import genesis_prime/message/delete_character_result.{type DeleteCharacterResult}
import genesis_prime/message/rename_character_result.{type RenameCharacterResult}
import genesis_prime/store.{type AccountId, AccountId}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import pog

/// Why an insert gave no row.
pub type Refused {
  /// The table's constraint of this name refused the row.
  Refused(constraint: String)
  /// The insert failed for another reason.
  NotAConstraint
}

/// Inserts one character row for the account, and gives its id or why the
/// table refused it.
pub fn try_insert(
  pool pool: pog.Connection,
  account account: AccountId,
  name name: String,
  class_id class_id: Int,
  path path: Int,
) -> Result(Int, Refused) {
  let AccountId(account_id) = account
  pog.query(
    "insert into character (account_id, name, gender, race_id, class_id, faction_id, level, path, world_id, world_zone_id, position_x, position_y, position_z) values ($1, $2, 1, 3, $3, 166, 9, $4, 1387, 1100, 1.5, 2.5, 3.5) returning character_id",
  )
  |> pog.parameter(pog.int(account_id))
  |> pog.parameter(pog.text(name))
  |> pog.parameter(pog.int(class_id))
  |> pog.parameter(pog.int(path))
  |> pog.returning(decode.at([0], decode.int))
  |> pog.execute(pool)
  |> result.map_error(fn(error) {
    case error {
      pog.ConstraintViolated(constraint:, ..) -> Refused(constraint:)
      pog.ConnectionUnavailable
      | pog.QueryTimeout
      | pog.PostgresqlError(..)
      | pog.UnexpectedArgumentCount(..)
      | pog.UnexpectedArgumentType(..)
      | pog.UnexpectedResultType(..) -> NotAConstraint
    }
  })
  |> result.map(fn(returned) {
    let assert [id] = returned.rows as "one row inserted"
    id
  })
}

/// Inserts one character row for the account, which the table accepts, and
/// gives its id.
pub fn insert(
  pool pool: pog.Connection,
  account account: AccountId,
  name name: String,
  class_id class_id: Int,
  path path: Int,
) -> Int {
  let assert Ok(id) = try_insert(pool:, account:, name:, class_id:, path:)
    as "the character was inserted"
  id
}

/// Marks the character with the name for a rename, as the developer tool does,
/// and checks that exactly one character has it.
pub fn mark_for_rename(pool pool: pog.Connection, name name: String) -> Nil {
  let assert Ok(returned) = mark_rename_sql.mark_for_rename(pool, name)
    as "the developer tool's query ran"
  assert list.length(returned.rows) == 1 as "one character has the name"
  Nil
}

/// 1 to `count`.
pub fn numbers(count: Int) -> List(Int) {
  list.index_map(list.repeat(0, count), fn(_, index) { index + 1 })
}

/// `count` bone values as float bits, each a finite float just above 1.0
/// (0x3F800000 is 1.0 in IEEE single precision, which ReadFloat 0x14006c1c0
/// keeps as it is), so each differs from its neighbours.
pub fn bones(count: Int) -> List(Int) {
  numbers(count) |> list.map(fn(index) { 0x3F800000 + index })
}

/// A create request for CharacterCreation row 466 (class 1, race 1, sex 1,
/// faction 167; a PreTutorial row with no entitlement and no cost), with the
/// name, a path of 0, no look and the 46 bone values race 1, sex 1 carries
/// (opcode.0x25b.counts).
pub fn create_request(name: String) -> CreateCharacter {
  CreateCharacter(
    creation_id: 466,
    name:,
    path: 0,
    customisation_labels: [],
    customisation_values: [],
    bone_values: bones(46),
  )
}

/// The one 0x00DC among the frames a create was answered with, decoded.
pub fn create_result_in(frames: List(Frame)) -> CreateCharacterResult {
  let assert [Frame(message_id: 0x00DC, body:)] = frames
    as "opcode.0xdc: one result answers a create"
  let assert Ok(result) = create_character_result.decode(body)
    as "0x00DC decodes"
  result
}

/// The one 0x00E6 among the frames a delete was answered with, decoded.
pub fn delete_result_in(frames: List(Frame)) -> DeleteCharacterResult {
  let assert [Frame(message_id: 0x00E6, body:)] = frames
    as "opcode.0xe6: one result answers a delete"
  let assert Ok(result) = delete_character_result.decode(body)
    as "0x00E6 decodes"
  result
}

/// The one 0x014B among the frames a rename was answered with, decoded.
pub fn rename_result_in(frames: List(Frame)) -> RenameCharacterResult {
  let assert [Frame(message_id: 0x014B, body:)] = frames
    as "opcode.0x14b: one result answers a rename"
  let assert Ok(result) = rename_character_result.decode(body)
    as "0x014B decodes"
  result
}
