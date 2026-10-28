//// This module contains the code to run the sql queries defined in
//// `./dev/genesis_prime/add_character/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `insert_character` query
/// defined in `./dev/genesis_prime/add_character/sql/insert_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertCharacterRow {
  InsertCharacterRow(character_id: Int)
}

/// Adds a character to the account with this login name, for a developer's
/// database. The race, sex, class and faction are the values of one
/// CharacterCreation row; the level, path, world, zone and position are what a
/// new character of the character list needs and no more. The database makes
/// the id; no account of that name gives no row.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_character(
  db: pog.Connection,
  login_name: String,
  arg_2: String,
  arg_3: Int,
  arg_4: Int,
  arg_5: Int,
  arg_6: Int,
) -> Result(pog.Returned(InsertCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(InsertCharacterRow(character_id:))
  }

  "-- Adds a character to the account with this login name, for a developer's
-- database. The race, sex, class and faction are the values of one
-- CharacterCreation row; the level, path, world, zone and position are what a
-- new character of the character list needs and no more. The database makes
-- the id; no account of that name gives no row.
insert into character (
  account_id, name, gender, race_id, class_id, faction_id, level, path,
  world_id, world_zone_id, position_x, position_y, position_z
)
select
  account_id, $2, $3, $4, $5, $6, 1, 0, 0, 0, 0, 0, 0
from account
where login_name = $1
returning character_id;
"
  |> pog.query
  |> pog.parameter(pog.text(login_name))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
