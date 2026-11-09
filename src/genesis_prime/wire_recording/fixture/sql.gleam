//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/wire_recording/fixture/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `account_sequence` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/account_sequence.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AccountSequenceRow {
  AccountSequenceRow(last_value: Int, is_called: Bool)
}

/// Where the account id sequence stands: the last value it gave (or the value it
/// gives first, when it has given none) and whether it has given one, which the
/// fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
/// with `setval`, so an account a replay makes gets the id it got live.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn account_sequence(
  db: pog.Connection,
) -> Result(pog.Returned(AccountSequenceRow), pog.QueryError) {
  let decoder = {
    use last_value <- decode.field(0, decode.int)
    use is_called <- decode.field(1, decode.bool)
    decode.success(AccountSequenceRow(last_value:, is_called:))
  }

  "-- Where the account id sequence stands: the last value it gave (or the value it
-- gives first, when it has given none) and whether it has given one, which the
-- fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
-- with `setval`, so an account a replay makes gets the id it got live.
select last_value, is_called from account_account_id_seq;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `accounts_named` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/accounts_named.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type AccountsNamedRow {
  AccountsNamedRow(
    account_id: Int,
    login_name: String,
    srp_salt: BitArray,
    srp_verifier: BitArray,
    game_account_id: String,
  )
}

/// The accounts with these login names, in the order of their ids, with every
/// column the fixture of a recorded session keeps
/// (genesis_prime/wire_recording/fixture): the id the session's rows name, the
/// login name, the SRP salt and verifier and the game account's GUID as its
/// 8-4-4-4-12 text. `created_at` is left out: it is the time a row was made,
/// which no flow reads.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn accounts_named(
  db: pog.Connection,
  arg_1: List(String),
) -> Result(pog.Returned(AccountsNamedRow), pog.QueryError) {
  let decoder = {
    use account_id <- decode.field(0, decode.int)
    use login_name <- decode.field(1, decode.string)
    use srp_salt <- decode.field(2, decode.bit_array)
    use srp_verifier <- decode.field(3, decode.bit_array)
    use game_account_id <- decode.field(4, decode.string)
    decode.success(AccountsNamedRow(
      account_id:,
      login_name:,
      srp_salt:,
      srp_verifier:,
      game_account_id:,
    ))
  }

  "-- The accounts with these login names, in the order of their ids, with every
-- column the fixture of a recorded session keeps
-- (genesis_prime/wire_recording/fixture): the id the session's rows name, the
-- login name, the SRP salt and verifier and the game account's GUID as its
-- 8-4-4-4-12 text. `created_at` is left out: it is the time a row was made,
-- which no flow reads.
select
  account_id,
  login_name,
  srp_salt,
  srp_verifier,
  game_account_id::text as game_account_id
from account
where login_name = any($1)
order by account_id;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `character_item_sequence` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/character_item_sequence.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CharacterItemSequenceRow {
  CharacterItemSequenceRow(last_value: Int, is_called: Bool)
}

/// Where the item guid sequence stands: the last value it gave (or the value it
/// gives first, when it has given none) and whether it has given one, which the
/// fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
/// with `setval`, so an item a replay makes gets the guid it got live.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn character_item_sequence(
  db: pog.Connection,
) -> Result(pog.Returned(CharacterItemSequenceRow), pog.QueryError) {
  let decoder = {
    use last_value <- decode.field(0, decode.int)
    use is_called <- decode.field(1, decode.bool)
    decode.success(CharacterItemSequenceRow(last_value:, is_called:))
  }

  "-- Where the item guid sequence stands: the last value it gave (or the value it
-- gives first, when it has given none) and whether it has given one, which the
-- fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
-- with `setval`, so an item a replay makes gets the guid it got live.
select last_value, is_called from character_item_item_guid_seq;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `character_sequence` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/character_sequence.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CharacterSequenceRow {
  CharacterSequenceRow(last_value: Int, is_called: Bool)
}

/// Where the character id sequence stands: the last value it gave (or the value it
/// gives first, when it has given none) and whether it has given one, which the
/// fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
/// with `setval`, so a character a replay makes gets the id it got live.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn character_sequence(
  db: pog.Connection,
) -> Result(pog.Returned(CharacterSequenceRow), pog.QueryError) {
  let decoder = {
    use last_value <- decode.field(0, decode.int)
    use is_called <- decode.field(1, decode.bool)
    decode.success(CharacterSequenceRow(last_value:, is_called:))
  }

  "-- Where the character id sequence stands: the last value it gave (or the value it
-- gives first, when it has given none) and whether it has given one, which the
-- fixture of a recorded session (genesis_prime/wire_recording/fixture) restores
-- with `setval`, so a character a replay makes gets the id it got live.
select last_value, is_called from character_character_id_seq;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `characters_of_accounts_named` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/characters_of_accounts_named.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CharactersOfAccountsNamedRow {
  CharactersOfAccountsNamedRow(
    character_id: Int,
    account_id: Int,
    session_epoch: Int,
    save_sequence: Int,
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
    rotation_yaw: Float,
    rotation_pitch: Float,
    rotation_roll: Float,
    look_labels: List(Int),
    look_values: List(Int),
    bones: List(Int),
    needs_rename: Bool,
    health: Option(Int),
    experience: Option(Int),
  )
}

/// The characters of the accounts with these login names, in the order of their
/// ids, with every column the fixture of a recorded session keeps
/// (genesis_prime/wire_recording/fixture): the id, the account it belongs to, the
/// session epoch that fences a stale save and the number of the last save of that
/// login, what the character list shows, where it stands and which way it faces,
/// its look and bones, its rename mark and the health and the experience it was
/// saved with (NULL when none was). `created_at` is left out:
/// it is the time a row was made, which no flow reads.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn characters_of_accounts_named(
  db: pog.Connection,
  arg_1: List(String),
) -> Result(pog.Returned(CharactersOfAccountsNamedRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    use account_id <- decode.field(1, decode.int)
    use session_epoch <- decode.field(2, decode.int)
    use save_sequence <- decode.field(3, decode.int)
    use name <- decode.field(4, decode.string)
    use gender <- decode.field(5, decode.int)
    use race_id <- decode.field(6, decode.int)
    use class_id <- decode.field(7, decode.int)
    use faction_id <- decode.field(8, decode.int)
    use level <- decode.field(9, decode.int)
    use path <- decode.field(10, decode.int)
    use world_id <- decode.field(11, decode.int)
    use world_zone_id <- decode.field(12, decode.int)
    use position_x <- decode.field(13, decode.float)
    use position_y <- decode.field(14, decode.float)
    use position_z <- decode.field(15, decode.float)
    use rotation_yaw <- decode.field(16, decode.float)
    use rotation_pitch <- decode.field(17, decode.float)
    use rotation_roll <- decode.field(18, decode.float)
    use look_labels <- decode.field(19, decode.list(decode.int))
    use look_values <- decode.field(20, decode.list(decode.int))
    use bones <- decode.field(21, decode.list(decode.int))
    use needs_rename <- decode.field(22, decode.bool)
    use health <- decode.field(23, decode.optional(decode.int))
    use experience <- decode.field(24, decode.optional(decode.int))
    decode.success(CharactersOfAccountsNamedRow(
      character_id:,
      account_id:,
      session_epoch:,
      save_sequence:,
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
      rotation_yaw:,
      rotation_pitch:,
      rotation_roll:,
      look_labels:,
      look_values:,
      bones:,
      needs_rename:,
      health:,
      experience:,
    ))
  }

  "-- The characters of the accounts with these login names, in the order of their
-- ids, with every column the fixture of a recorded session keeps
-- (genesis_prime/wire_recording/fixture): the id, the account it belongs to, the
-- session epoch that fences a stale save and the number of the last save of that
-- login, what the character list shows, where it stands and which way it faces,
-- its look and bones, its rename mark and the health and the experience it was
-- saved with (NULL when none was). `created_at` is left out:
-- it is the time a row was made, which no flow reads.
select
  character_id,
  account_id,
  session_epoch,
  save_sequence,
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
  rotation_yaw,
  rotation_pitch,
  rotation_roll,
  look_labels,
  look_values,
  bones,
  needs_rename,
  health,
  experience
from character
where account_id in (
  select account_id from account where login_name = any($1)
)
order by character_id;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `items_of_characters_of_accounts_named` query
/// defined in `./src/genesis_prime/wire_recording/fixture/sql/items_of_characters_of_accounts_named.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ItemsOfCharactersOfAccountsNamedRow {
  ItemsOfCharactersOfAccountsNamedRow(
    item_guid: Int,
    character_id: Int,
    item2_id: Int,
    location: Int,
    bag_index: Int,
    stack_count: Int,
  )
}

/// The items held by the characters of the accounts with these login names, in
/// the order of their guids, with every column the fixture of a recorded session
/// keeps (genesis_prime/wire_recording/fixture): the guid, the character that
/// holds it, the item's id, its place and its stack count.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn items_of_characters_of_accounts_named(
  db: pog.Connection,
  arg_1: List(String),
) -> Result(pog.Returned(ItemsOfCharactersOfAccountsNamedRow), pog.QueryError) {
  let decoder = {
    use item_guid <- decode.field(0, decode.int)
    use character_id <- decode.field(1, decode.int)
    use item2_id <- decode.field(2, decode.int)
    use location <- decode.field(3, decode.int)
    use bag_index <- decode.field(4, decode.int)
    use stack_count <- decode.field(5, decode.int)
    decode.success(ItemsOfCharactersOfAccountsNamedRow(
      item_guid:,
      character_id:,
      item2_id:,
      location:,
      bag_index:,
      stack_count:,
    ))
  }

  "-- The items held by the characters of the accounts with these login names, in
-- the order of their guids, with every column the fixture of a recorded session
-- keeps (genesis_prime/wire_recording/fixture): the guid, the character that
-- holds it, the item's id, its place and its stack count.
select
  item_guid,
  character_id,
  item2_id,
  location::int as location,
  bag_index,
  stack_count
from character_item
where character_id in (
  select character_id
  from character
  where account_id in (
    select account_id from account where login_name = any($1)
  )
)
order by item_guid;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
