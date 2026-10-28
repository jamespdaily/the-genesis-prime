//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/store/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `create_character` query
/// defined in `./src/genesis_prime/store/sql/create_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateCharacterRow {
  CreateCharacterRow(character_id: Int)
}

/// Makes a character of an account: level 1, no world, zone or position (the
/// world's entry gives them), and the values the create request gave. It makes
/// none, and gives no row, when the account already has as many characters as
/// its slots. A name that another character holds in any case breaks the unique
/// index on lower(name), which the caller reports as its own error.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_character(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: Int,
  arg_4: Int,
  arg_5: Int,
  arg_6: Int,
  arg_7: Int,
  arg_8: List(Int),
  arg_9: List(Int),
  arg_10: List(Int),
  arg_11: Int,
) -> Result(pog.Returned(CreateCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(CreateCharacterRow(character_id:))
  }

  "-- Makes a character of an account: level 1, no world, zone or position (the
-- world's entry gives them), and the values the create request gave. It makes
-- none, and gives no row, when the account already has as many characters as
-- its slots. A name that another character holds in any case breaks the unique
-- index on lower(name), which the caller reports as its own error.
insert into character (
  account_id, name, gender, race_id, class_id, faction_id, level, path,
  world_id, world_zone_id, position_x, position_y, position_z,
  look_labels, look_values, bones
)
select
  $1::bigint, $2::text, $3::int, $4::int, $5::int, $6::int, 1, $7::int, 0, 0,
  0, 0, 0, $8::bigint[], $9::bigint[], $10::bigint[]
where (select count(*) from character where account_id = $1::bigint) < $11::bigint
returning character_id;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.parameter(pog.int(arg_7))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_9))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `find_account` query
/// defined in `./src/genesis_prime/store/sql/find_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type FindAccountRow {
  FindAccountRow(
    account_id: Int,
    login_name: String,
    srp_salt: BitArray,
    srp_verifier: BitArray,
    game_account_id: String,
  )
}

/// The account with this login name, as the STS login needs it. The game
/// account id is read as its 8-4-4-4-12 text, the form the STS login's GUIDs
/// are parsed from.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn find_account(
  db: pog.Connection,
  arg_1: String,
) -> Result(pog.Returned(FindAccountRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    use login_name <- decode.field(1, decode.string)
    use srp_salt <- decode.field(2, decode.bit_array)
    use srp_verifier <- decode.field(3, decode.bit_array)
    use game_account_id <- decode.field(4, decode.string)
    decode.success(FindAccountRow(
      account_id:,
      login_name:,
      srp_salt:,
      srp_verifier:,
      game_account_id:,
    ))
  }

  "-- The account with this login name, as the STS login needs it. The game
-- account id is read as its 8-4-4-4-12 text, the form the STS login's GUIDs
-- are parsed from.
select
  account_id,
  login_name,
  srp_salt,
  srp_verifier,
  game_account_id::text as game_account_id
from account
where login_name = $1;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_characters` query
/// defined in `./src/genesis_prime/store/sql/list_characters.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListCharactersRow {
  ListCharactersRow(
    character_id: Int,
    name: String,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    level: Int,
    path: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
    look_labels: List(Int),
    look_values: List(Int),
    bones: List(Int),
  )
}

/// The account's characters as the character list needs them, in the order they
/// were created.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_characters(
  db: pog.Connection,
  account_id: Int,
) -> Result(pog.Returned(ListCharactersRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use gender <- decode.field(2, decode.int)
    use race_id <- decode.field(3, decode.int)
    use class_id <- decode.field(4, decode.int)
    use faction_id <- decode.field(5, decode.int)
    use level <- decode.field(6, decode.int)
    use path <- decode.field(7, decode.int)
    use world_id <- decode.field(8, decode.int)
    use world_zone_id <- decode.field(9, decode.int)
    use position_x <- decode.field(10, decode.float)
    use position_y <- decode.field(11, decode.float)
    use position_z <- decode.field(12, decode.float)
    use look_labels <- decode.field(13, decode.list(decode.int))
    use look_values <- decode.field(14, decode.list(decode.int))
    use bones <- decode.field(15, decode.list(decode.int))
    decode.success(ListCharactersRow(
      character_id:,
      name:,
      gender:,
      race_id:,
      class_id:,
      faction_id:,
      level:,
      path:,
      world_id:,
      world_zone_id:,
      position_x:,
      position_y:,
      position_z:,
      look_labels:,
      look_values:,
      bones:,
    ))
  }

  "-- The account's characters as the character list needs them, in the order they
-- were created.
select
  character_id,
  name,
  gender::int as gender,
  race_id::int as race_id,
  class_id::int as class_id,
  faction_id,
  level,
  path::int as path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  look_labels,
  look_values,
  bones
from character
where account_id = $1
order by character_id;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `lock_account` query
/// defined in `./src/genesis_prime/store/sql/lock_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LockAccountRow {
  LockAccountRow(account_id: Int)
}

/// Takes the account's row lock until the transaction ends, so the creates of
/// one account run one after another and each counts the characters the one
/// before it made. No row means no such account.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn lock_account(
  db: pog.Connection,
  account_id: Int,
) -> Result(pog.Returned(LockAccountRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    decode.success(LockAccountRow(account_id:))
  }

  "-- Takes the account's row lock until the transaction ends, so the creates of
-- one account run one after another and each counts the characters the one
-- before it made. No row means no such account.
select account_id
from account
where account_id = $1
for update;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
