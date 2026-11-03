//// This module contains the code to run the sql queries defined in
//// `./dev/genesis_prime/sitting_bot/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `account_character` query
/// defined in `./dev/genesis_prime/sitting_bot/sql/account_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AccountCharacterRow {
  AccountCharacterRow(character_id: Int)
}

/// The character with this name ($2, found as the name's unique index finds it:
/// any case, under the ICU root collation, migration 0005) of the account with
/// this login name ($1). A character of that name that another account has gives
/// no row, so it is never taken for this account's.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn account_character(
  db: pog.Connection,
  account_login_name: String,
  arg_2: String,
) -> Result(pog.Returned(AccountCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(AccountCharacterRow(character_id:))
  }

  "-- The character with this name ($2, found as the name's unique index finds it:
-- any case, under the ICU root collation, migration 0005) of the account with
-- this login name ($1). A character of that name that another account has gives
-- no row, so it is never taken for this account's.
select character_id
from character
join account using (account_id)
where account.login_name = $1
  and lower(character.name collate \"und-x-icu\") = lower($2 collate \"und-x-icu\");
"
  |> pog.query
  |> pog.parameter(pog.text(account_login_name))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `account_with_login_name` query
/// defined in `./dev/genesis_prime/sitting_bot/sql/account_with_login_name.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AccountWithLoginNameRow {
  AccountWithLoginNameRow(account_id: Int)
}

/// The account with this login name, which is stored in lower case. No account
/// of the name gives no row.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn account_with_login_name(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(AccountWithLoginNameRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    decode.success(AccountWithLoginNameRow(account_id:))
  }

  "-- The account with this login name, which is stored in lower case. No account
-- of the name gives no row.
select account_id from account where login_name = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `character_place` query
/// defined in `./dev/genesis_prime/sitting_bot/sql/character_place.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CharacterPlaceRow {
  CharacterPlaceRow(
    character_id: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
  )
}

/// The character with this name, found as the name's unique index finds it (any
/// case, under the ICU root collation: migration 0005), and the place it is
/// saved at. World 0 is no place (migration 0006). No character of the name
/// gives no row.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn character_place(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(CharacterPlaceRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    use world_id <- decode.field(1, decode.int)
    use world_zone_id <- decode.field(2, decode.int)
    use position_x <- decode.field(3, decode.float)
    use position_y <- decode.field(4, decode.float)
    use position_z <- decode.field(5, decode.float)
    decode.success(CharacterPlaceRow(
      character_id:,
      world_id:,
      world_zone_id:,
      position_x:,
      position_y:,
      position_z:,
    ))
  }

  "-- The character with this name, found as the name's unique index finds it (any
-- case, under the ICU root collation: migration 0005), and the place it is
-- saved at. World 0 is no place (migration 0006). No character of the name
-- gives no row.
select character_id, world_id, world_zone_id, position_x, position_y, position_z
from character
where lower(name collate \"und-x-icu\") = lower($1 collate \"und-x-icu\");
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `seat_character` query
/// defined in `./dev/genesis_prime/sitting_bot/sql/seat_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SeatCharacterRow {
  SeatCharacterRow(character_id: Int)
}

/// Puts a character at a place for a developer's database, before the character
/// logs in: its world, zone and position, facing the way a character never saved
/// facing a way does (yaw, pitch and roll 0: migration 0007). A login resets the
/// save sequence, so no save is fenced by this write. Only a character of the
/// account with this login name ($7) is moved: no character of that id of that
/// account gives no row.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn seat_character(
  db: pog.Connection,
  character_id: Int,
  arg_2: Int,
  arg_3: Int,
  arg_4: Float,
  arg_5: Float,
  arg_6: Float,
  arg_7: String,
) -> Result(pog.Returned(SeatCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(SeatCharacterRow(character_id:))
  }

  "-- Puts a character at a place for a developer's database, before the character
-- logs in: its world, zone and position, facing the way a character never saved
-- facing a way does (yaw, pitch and roll 0: migration 0007). A login resets the
-- save sequence, so no save is fenced by this write. Only a character of the
-- account with this login name ($7) is moved: no character of that id of that
-- account gives no row.
update character
set
  world_id = $2,
  world_zone_id = $3,
  position_x = $4,
  position_y = $5,
  position_z = $6,
  rotation_yaw = 0,
  rotation_pitch = 0,
  rotation_roll = 0
where character_id = $1
  and account_id in (select account_id from account where login_name = $7)
returning character_id;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.float(arg_4))
  |> pog.parameter(pog.float(arg_5))
  |> pog.parameter(pog.float(arg_6))
  |> pog.parameter(pog.text(arg_7))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
