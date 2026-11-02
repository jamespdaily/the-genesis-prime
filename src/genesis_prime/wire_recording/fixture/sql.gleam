//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/wire_recording/fixture/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `all_accounts` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/all_accounts.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AllAccountsRow {
  AllAccountsRow(
    account_id: Int,
    login_name: String,
    srp_salt: BitArray,
    srp_verifier: BitArray,
    game_account_id: String,
  )
}

/// Every account, in the order of its id, with every column the fixture of a
/// recorded session keeps (genesis_prime/wire_recording/fixture): the id the
/// session's rows name, the login name, the SRP salt and verifier and the game
/// account's GUID as its 8-4-4-4-12 text. `created_at` is left out: it is the
/// time a row was made, which no flow reads.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn all_accounts(
  db: pog.Connection,
) -> Result(pog.Returned(AllAccountsRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    use login_name <- decode.field(1, decode.string)
    use srp_salt <- decode.field(2, decode.bit_array)
    use srp_verifier <- decode.field(3, decode.bit_array)
    use game_account_id <- decode.field(4, decode.string)
    decode.success(AllAccountsRow(
      account_id:,
      login_name:,
      srp_salt:,
      srp_verifier:,
      game_account_id:,
    ))
  }

  "-- Every account, in the order of its id, with every column the fixture of a
-- recorded session keeps (genesis_prime/wire_recording/fixture): the id the
-- session's rows name, the login name, the SRP salt and verifier and the game
-- account's GUID as its 8-4-4-4-12 text. `created_at` is left out: it is the
-- time a row was made, which no flow reads.
select
  account_id,
  login_name,
  srp_salt,
  srp_verifier,
  game_account_id::text as game_account_id
from account
order by account_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `all_characters` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/all_characters.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AllCharactersRow {
  AllCharactersRow(
    character_id: Int,
    account_id: Int,
    session_epoch: Int,
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
    needs_rename: Bool,
  )
}

/// Every character, in the order of its id, with every column the fixture of a
/// recorded session keeps (genesis_prime/wire_recording/fixture): the id, the
/// account it belongs to, the session epoch that fences a stale save, what the
/// character list shows, where it stands, its look and bones and its rename
/// mark. `created_at` is left out: it is the time a row was made, which no flow
/// reads.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn all_characters(
  db: pog.Connection,
) -> Result(pog.Returned(AllCharactersRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    use account_id <- decode.field(1, decode.int)
    use session_epoch <- decode.field(2, decode.int)
    use name <- decode.field(3, decode.string)
    use gender <- decode.field(4, decode.int)
    use race_id <- decode.field(5, decode.int)
    use class_id <- decode.field(6, decode.int)
    use faction_id <- decode.field(7, decode.int)
    use level <- decode.field(8, decode.int)
    use path <- decode.field(9, decode.int)
    use world_id <- decode.field(10, decode.int)
    use world_zone_id <- decode.field(11, decode.int)
    use position_x <- decode.field(12, decode.float)
    use position_y <- decode.field(13, decode.float)
    use position_z <- decode.field(14, decode.float)
    use look_labels <- decode.field(15, decode.list(decode.int))
    use look_values <- decode.field(16, decode.list(decode.int))
    use bones <- decode.field(17, decode.list(decode.int))
    use needs_rename <- decode.field(18, decode.bool)
    decode.success(AllCharactersRow(
      character_id:,
      account_id:,
      session_epoch:,
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
      needs_rename:,
    ))
  }

  "-- Every character, in the order of its id, with every column the fixture of a
-- recorded session keeps (genesis_prime/wire_recording/fixture): the id, the
-- account it belongs to, the session epoch that fences a stale save, what the
-- character list shows, where it stands, its look and bones and its rename
-- mark. `created_at` is left out: it is the time a row was made, which no flow
-- reads.
select
  character_id,
  account_id,
  session_epoch,
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
  bones,
  needs_rename
from character
order by character_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}
