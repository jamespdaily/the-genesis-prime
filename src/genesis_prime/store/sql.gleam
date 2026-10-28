//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/store/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

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
  position_z
from character
where account_id = $1
order by character_id;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
