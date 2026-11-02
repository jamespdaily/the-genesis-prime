//// What the tests of creating a character share. Character rows for the tests
//// that need a character in a database: one insert with the same race,
//// gender, faction, level, world, zone and position for each row, so a test
//// varies only the name, the class and the path it checks. One valid create
//// request, which a test varies with a record update, and the one result a
//// create, a delete or a rename answers with, decoded.

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/appearance
import genesis_prime/game/character_creation
import genesis_prime/game/start_place.{Novice, Veteran}
import genesis_prime/mark_rename/sql as mark_rename_sql
import genesis_prime/message/create_character.{
  type CreateCharacter, CreateCharacter,
}
import genesis_prime/message/create_character_result.{type CreateCharacterResult}
import genesis_prime/message/delete_character_result.{type DeleteCharacterResult}
import genesis_prime/message/rename_character_result.{type RenameCharacterResult}
import genesis_prime/store.{type AccountId, type NewCharacter, AccountId}
import genesis_prime/table/character_creation as creation_table
import genesis_prime/table/loader/store as table_store
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import pog

/// The session epoch with this number, for a test whose number is 1 or more.
pub fn epoch(number number: Int) -> store.SessionEpoch {
  let assert Ok(epoch) = store.session_epoch(number)
    as "the test's epoch is 1 or more"
  epoch
}

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

/// The place a character's row holds, with the numbers that fence a save: its
/// epoch and the sequence of the last save stored.
pub type PlaceRow {
  PlaceRow(
    world_id: Int,
    world_zone_id: Int,
    position: #(Float, Float, Float),
    rotation: #(Float, Float, Float),
    session_epoch: Int,
    save_sequence: Int,
  )
}

/// What the character's row holds of where it stands and of the login that
/// saved, read straight from the database.
pub fn place_row(
  pool pool: pog.Connection,
  character_id character_id: Int,
) -> PlaceRow {
  let decoder = {
    use world_id <- decode.field(0, decode.int)
    use world_zone_id <- decode.field(1, decode.int)
    use x <- decode.field(2, decode.float)
    use y <- decode.field(3, decode.float)
    use z <- decode.field(4, decode.float)
    use yaw <- decode.field(5, decode.float)
    use pitch <- decode.field(6, decode.float)
    use roll <- decode.field(7, decode.float)
    use session_epoch <- decode.field(8, decode.int)
    use save_sequence <- decode.field(9, decode.int)
    decode.success(PlaceRow(
      world_id:,
      world_zone_id:,
      position: #(x, y, z),
      rotation: #(yaw, pitch, roll),
      session_epoch:,
      save_sequence:,
    ))
  }
  let assert Ok(returned) =
    pog.query(
      "select world_id, world_zone_id, position_x::float8, position_y::float8, position_z::float8, rotation_yaw::float8, rotation_pitch::float8, rotation_roll::float8, session_epoch, save_sequence from character where character_id = $1",
    )
    |> pog.parameter(pog.int(character_id))
    |> pog.returning(decoder)
    |> pog.execute(pool)
    as "the row reads"
  let assert [row] = returned.rows as "the character has one row"
  row
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

/// The client's enabled CharacterCreation rows of the Novice and Veteran
/// starts, the ones a player can pick: none is costume-only.
pub fn novice_and_veteran_rows(
  tables: table_store.Tables,
) -> List(creation_table.CharacterCreation) {
  list.filter(creation_table.all(tables), fn(row) {
    row.enabled
    && !row.costume_only
    && list.contains(
      [Novice, Veteran],
      start_place.start(enum_value: row.character_creation_start_enum),
    )
  })
}

/// The character a create of the row makes, from a request with no look and
/// the row's own bone count. The row's entitlement and cost are cleared, since
/// they gate a create and the callers read what the row makes.
pub fn new_character_of_row(
  tables tables: table_store.Tables,
  row row: creation_table.CharacterCreation,
) -> NewCharacter {
  let open =
    creation_table.CharacterCreation(
      ..row,
      entitlement_id_required: 0,
      account_currency_amount_cost: 0,
    )
  let request =
    CreateCharacter(
      ..create_request("Ab Cd"),
      creation_id: row.id,
      bone_values: list.repeat(
        0,
        appearance.bone_count(
          tables:,
          race_id: creation_table.race_id(row),
          sex: row.sex,
        ),
      ),
    )
  let assert Ok(character) = character_creation.check_row(tables, open, request)
    as {
      "a create of CharacterCreation row "
      <> int.to_string(row.id)
      <> " passes the checks"
    }
  character
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
