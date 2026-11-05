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

/// Makes the bot's account when the database has none: the login name ($1), the
/// salt ($2) and verifier ($3) of its password and the game account id ($4) as
/// its 8-4-4-4-12 text. An account with the login name already there is left as
/// it is, so a run beside another, or after one, finds the same account.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_bot_account(
  db: pog.Connection,
  arg_1: String,
  arg_2: BitArray,
  arg_3: BitArray,
  arg_4: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Makes the bot's account when the database has none: the login name ($1), the
-- salt ($2) and verifier ($3) of its password and the game account id ($4) as
-- its 8-4-4-4-12 text. An account with the login name already there is left as
-- it is, so a run beside another, or after one, finds the same account.
insert into account (login_name, srp_salt, srp_verifier, game_account_id)
values ($1, $2, $3, $4::text::uuid)
on conflict (login_name) do nothing;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.bytea(arg_2))
  |> pog.parameter(pog.bytea(arg_3))
  |> pog.parameter(pog.text(arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Makes the bot's character for the account with this login name ($1), named $2,
/// unless the account already has a character of that name (found as the name's
/// unique index finds it: any case, under the ICU root collation, migration
/// 0005). The race, sex, class and faction are those of CharacterCreation row 466
/// (race 1, sex 1, class 1, faction 167); it has no saved place (world 0).
/// A name another account's character holds breaks the name's unique index and
/// is refused, so the bot never takes another account's character.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_bot_character(
  db: pog.Connection,
  login_name: String,
  arg_2: String,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Makes the bot's character for the account with this login name ($1), named $2,
-- unless the account already has a character of that name (found as the name's
-- unique index finds it: any case, under the ICU root collation, migration
-- 0005). The race, sex, class and faction are those of CharacterCreation row 466
-- (race 1, sex 1, class 1, faction 167); it has no saved place (world 0).
-- A name another account's character holds breaks the name's unique index and
-- is refused, so the bot never takes another account's character.
insert into character (
  account_id, name, gender, race_id, class_id, faction_id, level, path,
  world_id, world_zone_id, position_x, position_y, position_z
)
select account_id, $2::text, 1, 1, 1, 167, 1, 0, 0, 0, 0, 0, 0
from account
where login_name = $1
  and not exists (
    select 1
    from character
    where character.account_id = account.account_id
      and lower(character.name collate \"und-x-icu\")
        = lower($2::text collate \"und-x-icu\")
  );
"
  |> pog.query
  |> pog.parameter(pog.text(login_name))
  |> pog.parameter(pog.text(arg_2))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `lock_bot_account` query
/// defined in `./dev/genesis_prime/sitting_bot/sql/lock_bot_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LockBotAccountRow {
  LockBotAccountRow(account_id: Int)
}

/// Takes the row lock of the account with this login name until the transaction
/// ends, so two runs make the bot's character one after another, and the second
/// finds the first's.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn lock_bot_account(
  db: pog.Connection,
  login_name: String,
) -> Result(pog.Returned(LockBotAccountRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    decode.success(LockBotAccountRow(account_id:))
  }

  "-- Takes the row lock of the account with this login name until the transaction
-- ends, so two runs make the bot's character one after another, and the second
-- finds the first's.
select account_id
from account
where login_name = $1
for update;
"
  |> pog.query
  |> pog.parameter(pog.text(login_name))
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
