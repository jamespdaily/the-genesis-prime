//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/store/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option}
import pog

/// A row you get from running the `buy_from_vendor` query
/// defined in `./src/genesis_prime/store/sql/buy_from_vendor.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type BuyFromVendorRow {
  BuyFromVendorRow(
    credits: Int,
    item_guid: Option(Int),
    location: Option(Int),
    bag_index: Option(Int),
    stack_count: Option(Int),
  )
}

/// A purchase from a vendor, all or none, in one statement: the credits of the character
/// `$1` of the account `$2` are lowered by `$5`, each stack of the lists `$7` to `$9` at the
/// same position (an item's guid, the count it is held with, the count it holds after) is
/// raised, and a stack of the Item2 `$6` is inserted at each place of the lists `$10` to
/// `$12` (a location, a bag index and a count). It changes only while the character is still
/// held by the login that asks, that is while its `session_epoch` ($3) is still the one that
/// login was told (load_character.sql), only while the character holds exactly `$4` credits
/// (the total the login holds) and at least `$5`, and only when each stack to raise is the
/// character's, of the Item2 `$6`, with the count it is held with; otherwise it changes
/// nothing and returns no row. The account's id is in the statement, as for a load.
///
/// The rows it returns are one for each stack made, each with the credits left; one row with
/// no stack when none is made. A place that holds an item breaks the table's
/// `character_item_one_per_slot` at the statement's end and the statement changes nothing,
/// the credits and the raised stacks included. Whether a stack may hold its new count is the
/// Item2's maxStackCount, which the rule checks. The statement runs after
/// lock_character_for_save.sql in one transaction, so it waits for a login that is raising
/// the epoch and then reads the epoch that login stored.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn buy_from_vendor(
  db: pog.Connection,
  character_id: Int,
  character_account_id: Int,
  character_session_epoch: Int,
  credits_amount: Int,
  arg_5: Int,
  held_item2_id: Int,
  arg_7: List(Int),
  arg_8: List(Int),
  arg_9: List(Int),
  arg_10: List(Int),
  arg_11: List(Int),
  arg_12: List(Int),
) -> Result(pog.Returned(BuyFromVendorRow), pog.QueryError) {
  let decoder = {
    use credits <- decode.field(0, decode.int)
    use item_guid <- decode.field(1, decode.optional(decode.int))
    use location <- decode.field(2, decode.optional(decode.int))
    use bag_index <- decode.field(3, decode.optional(decode.int))
    use stack_count <- decode.field(4, decode.optional(decode.int))
    decode.success(BuyFromVendorRow(
      credits:,
      item_guid:,
      location:,
      bag_index:,
      stack_count:,
    ))
  }

  "-- A purchase from a vendor, all or none, in one statement: the credits of the character
-- `$1` of the account `$2` are lowered by `$5`, each stack of the lists `$7` to `$9` at the
-- same position (an item's guid, the count it is held with, the count it holds after) is
-- raised, and a stack of the Item2 `$6` is inserted at each place of the lists `$10` to
-- `$12` (a location, a bag index and a count). It changes only while the character is still
-- held by the login that asks, that is while its `session_epoch` ($3) is still the one that
-- login was told (load_character.sql), only while the character holds exactly `$4` credits
-- (the total the login holds) and at least `$5`, and only when each stack to raise is the
-- character's, of the Item2 `$6`, with the count it is held with; otherwise it changes
-- nothing and returns no row. The account's id is in the statement, as for a load.
--
-- The rows it returns are one for each stack made, each with the credits left; one row with
-- no stack when none is made. A place that holds an item breaks the table's
-- `character_item_one_per_slot` at the statement's end and the statement changes nothing,
-- the credits and the raised stacks included. Whether a stack may hold its new count is the
-- Item2's maxStackCount, which the rule checks. The statement runs after
-- lock_character_for_save.sql in one transaction, so it waits for a login that is raising
-- the epoch and then reads the epoch that login stored.
with grown as (
  select grow.item_guid, grow.held_count, grow.new_count
  from unnest($7::bigint[], $8::int[], $9::int[])
    as grow (item_guid, held_count, new_count)
),
allowed as (
  select credits.character_id
  from character
  join character_currency as credits on credits.character_id = character.character_id
  where character.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and credits.currency_type_id = 1
    and credits.amount = $4
    and $5 >= 0
    and credits.amount >= $5
    and (
      select count(*)
      from grown
      join character_item as held on held.item_guid = grown.item_guid
      where held.character_id = $1
        and held.item2_id = $6
        and held.stack_count = grown.held_count
    ) = (select count(*) from grown)
),
spent as (
  update character_currency as credits
  set amount = credits.amount - $5
  from allowed
  where credits.character_id = allowed.character_id
    and credits.currency_type_id = 1
  returning credits.amount
),
raised as (
  update character_item as held
  set stack_count = grown.new_count
  from grown
  where held.item_guid = grown.item_guid
    and exists (select 1 from allowed)
  returning held.item_guid
),
made as (
  insert into character_item (character_id, item2_id, location, bag_index, stack_count)
  select $1, $6, new_stack.location::smallint, new_stack.bag_index, new_stack.stack_count
  from unnest($10::int[], $11::int[], $12::int[])
    as new_stack (location, bag_index, stack_count)
  where exists (select 1 from allowed)
  returning item_guid, location::int as location, bag_index, stack_count
)
select
  spent.amount as credits,
  made.item_guid,
  made.location,
  made.bag_index,
  made.stack_count
from spent
left join made on true
order by made.item_guid;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(character_account_id))
  |> pog.parameter(pog.int(character_session_epoch))
  |> pog.parameter(pog.int(credits_amount))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.int(held_item2_id))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_7))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_9))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_10))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_11))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_12))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `create_character` query
/// defined in `./src/genesis_prime/store/sql/create_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CreateCharacterRow {
  CreateCharacterRow(character_id: Int)
}

/// Makes a character of an account: at the level the create gave, standing at
/// the start place the create gave (a world, a zone, a position and a facing),
/// with the experience the create gave, the credits the create gave (no row when
/// they are 0, the client's start value) and the values the create request gave.
/// It makes none, and gives no row, when the
/// account already has as many characters as its slots. A name that another
/// character holds in any case breaks the unique index on
/// lower(name collate "und-x-icu"), which the caller reports as its own error.
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
  arg_12: Int,
  arg_13: Int,
  arg_14: Float,
  arg_15: Float,
  arg_16: Float,
  arg_17: Int,
  arg_18: Float,
  arg_19: Float,
  arg_20: Float,
  arg_21: Int,
  arg_22: Int,
) -> Result(pog.Returned(CreateCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(CreateCharacterRow(character_id:))
  }

  "-- Makes a character of an account: at the level the create gave, standing at
-- the start place the create gave (a world, a zone, a position and a facing),
-- with the experience the create gave, the credits the create gave (no row when
-- they are 0, the client's start value) and the values the create request gave.
-- It makes none, and gives no row, when the
-- account already has as many characters as its slots. A name that another
-- character holds in any case breaks the unique index on
-- lower(name collate \"und-x-icu\"), which the caller reports as its own error.
with made as (
  insert into character (
    account_id, name, gender, race_id, class_id, faction_id, level, path,
    world_id, world_zone_id, position_x, position_y, position_z,
    rotation_yaw, rotation_pitch, rotation_roll,
    look_labels, look_values, bones, experience
  )
  select
    $1::bigint, $2::text, $3::int, $4::int, $5::int, $6::int, $17::int, $7::int,
    $12::int, $13::int, $14::real, $15::real, $16::real,
    $18::real, $19::real, $20::real,
    $8::bigint[], $9::bigint[], $10::bigint[], $21::int
  where (select count(*) from character where account_id = $1::bigint) < $11::bigint
  returning character_id
),
credited as (
  insert into character_currency (character_id, currency_type_id, amount)
  select character_id, 1, $22::bigint from made where $22::bigint > 0
)
select character_id from made;
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
  |> pog.parameter(pog.int(arg_12))
  |> pog.parameter(pog.int(arg_13))
  |> pog.parameter(pog.float(arg_14))
  |> pog.parameter(pog.float(arg_15))
  |> pog.parameter(pog.float(arg_16))
  |> pog.parameter(pog.int(arg_17))
  |> pog.parameter(pog.float(arg_18))
  |> pog.parameter(pog.float(arg_19))
  |> pog.parameter(pog.float(arg_20))
  |> pog.parameter(pog.int(arg_21))
  |> pog.parameter(pog.int(arg_22))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Stores the items a new character starts with, one row each, in the places
/// the lists give at the same position. The database gives each row its guid.
/// A place the character already holds an item in breaks
/// `character_item_one_per_slot`, and any other value its checks refuse breaks
/// that check; no ask of the create can, so the worker ends on either.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn create_character_items(
  db: pog.Connection,
  arg_1: Int,
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
  arg_5: List(Int),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Stores the items a new character starts with, one row each, in the places
-- the lists give at the same position. The database gives each row its guid.
-- A place the character already holds an item in breaks
-- `character_item_one_per_slot`, and any other value its checks refuse breaks
-- that check; no ask of the create can, so the worker ends on either.
insert into character_item (character_id, item2_id, location, bag_index, stack_count)
select $1::bigint, item2_id, location::smallint, bag_index, stack_count
from unnest($2::int[], $3::int[], $4::int[], $5::int[])
  as new_item (item2_id, location, bag_index, stack_count);
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `delete_character` query
/// defined in `./src/genesis_prime/store/sql/delete_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DeleteCharacterRow {
  DeleteCharacterRow(character_id: Int)
}

/// Deletes the account's character with this id. The account's id is in the
/// statement, so another account's character, which a modified client could
/// name, is never touched. No row means the account has no such character.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_character(
  db: pog.Connection,
  character_id: Int,
  account_id: Int,
) -> Result(pog.Returned(DeleteCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(DeleteCharacterRow(character_id:))
  }

  "-- Deletes the account's character with this id. The account's id is in the
-- statement, so another account's character, which a modified client could
-- name, is never touched. No row means the account has no such character.
delete from character
where character_id = $1 and account_id = $2
returning character_id;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `delete_character_item` query
/// defined in `./src/genesis_prime/store/sql/delete_character_item.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DeleteCharacterItemRow {
  DeleteCharacterItemRow(item_guid: Int)
}

/// Deletes the whole stack of the item `$4` of the character `$1` of the account
/// `$2`, in one statement. It deletes only while the character is still held by
/// the login that asks, that is while its `session_epoch` ($3) is still the one
/// that login was told (load_character.sql), and only when the item is as the
/// request holds it, at the place `$5` and `$6` with the count `$7`; otherwise it
/// changes nothing and returns no row. The account's id is in the statement, as
/// for a load. The row it returns is the item it deleted.
///
/// The statement runs after lock_character_for_save.sql in one transaction, so it
/// waits for a login that is raising the epoch and then reads the epoch that login
/// stored.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_character_item(
  db: pog.Connection,
  item_character_id: Int,
  character_account_id: Int,
  character_session_epoch: Int,
  item_guid: Int,
  item_location: Int,
  item_bag_index: Int,
  item_stack_count: Int,
) -> Result(pog.Returned(DeleteCharacterItemRow), pog.QueryError) {
  let decoder = {
    use item_guid <- decode.field(0, decode.int)
    decode.success(DeleteCharacterItemRow(item_guid:))
  }

  "-- Deletes the whole stack of the item `$4` of the character `$1` of the account
-- `$2`, in one statement. It deletes only while the character is still held by
-- the login that asks, that is while its `session_epoch` ($3) is still the one
-- that login was told (load_character.sql), and only when the item is as the
-- request holds it, at the place `$5` and `$6` with the count `$7`; otherwise it
-- changes nothing and returns no row. The account's id is in the statement, as
-- for a load. The row it returns is the item it deleted.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it
-- waits for a login that is raising the epoch and then reads the epoch that login
-- stored.
delete from character_item as item
using character
where character.character_id = item.character_id
  and item.item_guid = $4
  and item.character_id = $1
  and character.account_id = $2
  and character.session_epoch = $3
  and item.location = $5
  and item.bag_index = $6
  and item.stack_count = $7
returning item.item_guid;
"
  |> pog.query
  |> pog.parameter(pog.int(item_character_id))
  |> pog.parameter(pog.int(character_account_id))
  |> pog.parameter(pog.int(character_session_epoch))
  |> pog.parameter(pog.int(item_guid))
  |> pog.parameter(pog.int(item_location))
  |> pog.parameter(pog.int(item_bag_index))
  |> pog.parameter(pog.int(item_stack_count))
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
    rotation_yaw: Float,
    rotation_pitch: Float,
    rotation_roll: Float,
    look_labels: List(Int),
    look_values: List(Int),
    bones: List(Int),
    needs_rename: Bool,
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
    use rotation_yaw <- decode.field(13, decode.float)
    use rotation_pitch <- decode.field(14, decode.float)
    use rotation_roll <- decode.field(15, decode.float)
    use look_labels <- decode.field(16, decode.list(decode.int))
    use look_values <- decode.field(17, decode.list(decode.int))
    use bones <- decode.field(18, decode.list(decode.int))
    use needs_rename <- decode.field(19, decode.bool)
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
      rotation_yaw:,
      rotation_pitch:,
      rotation_roll:,
      look_labels:,
      look_values:,
      bones:,
      needs_rename:,
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
  rotation_yaw,
  rotation_pitch,
  rotation_roll,
  look_labels,
  look_values,
  bones,
  needs_rename
from character
where account_id = $1
order by character_id;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `list_migrations` query
/// defined in `./src/genesis_prime/store/sql/list_migrations.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type ListMigrationsRow {
  ListMigrationsRow(name: String, sha256: String)
}

/// The migration files the database has run, with the SHA-256 each file had
/// (lower-case hex) when it ran, which the server compares with the files in
/// priv/migrations at start (genesis_prime/migration). Fails with an undefined
/// table on a database that has no schema_migration, which the store answers as
/// a database with no record.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn list_migrations(
  db: pog.Connection,
) -> Result(pog.Returned(ListMigrationsRow), pog.QueryError) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    use sha256 <- decode.field(1, decode.string)
    decode.success(ListMigrationsRow(name:, sha256:))
  }

  "-- The migration files the database has run, with the SHA-256 each file had
-- (lower-case hex) when it ran, which the server compares with the files in
-- priv/migrations at start (genesis_prime/migration). Fails with an undefined
-- table on a database that has no schema_migration, which the store answers as
-- a database with no record.
select name, sha256
from schema_migration
order by name;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_character` query
/// defined in `./src/genesis_prime/store/sql/load_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadCharacterRow {
  LoadCharacterRow(
    character_id: Int,
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

/// The account's character with this id, as the world's entry needs it: the
/// same columns as the list, with the saved place and the saved health and
/// experience (NULL when none was saved), and the character taken by
/// this login: `session_epoch` is raised by one in the same statement, with
/// `save_sequence` back to 0 for the new login, and the new epoch returned, so
/// the login that read the character is the one that holds that epoch, and a
/// save made under an earlier epoch (an older login's) finds no row to change
/// (save_place.sql). The account's id is in the
/// statement, so another account's character, which a modified client could
/// name, is never taken. No row means the account has no such character.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_character(
  db: pog.Connection,
  character_id: Int,
  account_id: Int,
) -> Result(pog.Returned(LoadCharacterRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    use session_epoch <- decode.field(1, decode.int)
    use name <- decode.field(2, decode.string)
    use gender <- decode.field(3, decode.int)
    use race_id <- decode.field(4, decode.int)
    use class_id <- decode.field(5, decode.int)
    use faction_id <- decode.field(6, decode.int)
    use level <- decode.field(7, decode.int)
    use path <- decode.field(8, decode.int)
    use world_id <- decode.field(9, decode.int)
    use world_zone_id <- decode.field(10, decode.int)
    use position_x <- decode.field(11, decode.float)
    use position_y <- decode.field(12, decode.float)
    use position_z <- decode.field(13, decode.float)
    use rotation_yaw <- decode.field(14, decode.float)
    use rotation_pitch <- decode.field(15, decode.float)
    use rotation_roll <- decode.field(16, decode.float)
    use look_labels <- decode.field(17, decode.list(decode.int))
    use look_values <- decode.field(18, decode.list(decode.int))
    use bones <- decode.field(19, decode.list(decode.int))
    use needs_rename <- decode.field(20, decode.bool)
    use health <- decode.field(21, decode.optional(decode.int))
    use experience <- decode.field(22, decode.optional(decode.int))
    decode.success(LoadCharacterRow(
      character_id:,
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

  "-- The account's character with this id, as the world's entry needs it: the
-- same columns as the list, with the saved place and the saved health and
-- experience (NULL when none was saved), and the character taken by
-- this login: `session_epoch` is raised by one in the same statement, with
-- `save_sequence` back to 0 for the new login, and the new epoch returned, so
-- the login that read the character is the one that holds that epoch, and a
-- save made under an earlier epoch (an older login's) finds no row to change
-- (save_place.sql). The account's id is in the
-- statement, so another account's character, which a modified client could
-- name, is never taken. No row means the account has no such character.
update character
set session_epoch = session_epoch + 1, save_sequence = 0
where character_id = $1 and account_id = $2
returning
  character_id,
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
  rotation_yaw,
  rotation_pitch,
  rotation_roll,
  look_labels,
  look_values,
  bones,
  needs_rename,
  health,
  experience;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_character_currencies` query
/// defined in `./src/genesis_prime/store/sql/load_character_currencies.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadCharacterCurrenciesRow {
  LoadCharacterCurrenciesRow(currency_type_id: Int, amount: Int)
}

/// The currencies a character holds, one row each, by type. A currency with no row is 0.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_character_currencies(
  db: pog.Connection,
  character_id: Int,
) -> Result(pog.Returned(LoadCharacterCurrenciesRow), pog.QueryError) {
  let decoder = {
    use currency_type_id <- decode.field(0, decode.int)
    use amount <- decode.field(1, decode.int)
    decode.success(LoadCharacterCurrenciesRow(currency_type_id:, amount:))
  }

  "-- The currencies a character holds, one row each, by type. A currency with no row is 0.
select
  currency_type_id::int as currency_type_id,
  amount
from character_currency
where character_id = $1
order by currency_type_id;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_character_items` query
/// defined in `./src/genesis_prime/store/sql/load_character_items.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadCharacterItemsRow {
  LoadCharacterItemsRow(
    item_guid: Int,
    item2_id: Int,
    location: Int,
    bag_index: Int,
    stack_count: Int,
  )
}

/// The items a character holds in its equipped slots, inventory and bank, in
/// the order world entry sends them: by location, then bag index.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_character_items(
  db: pog.Connection,
  character_id: Int,
) -> Result(pog.Returned(LoadCharacterItemsRow), pog.QueryError) {
  let decoder = {
    use item_guid <- decode.field(0, decode.int)
    use item2_id <- decode.field(1, decode.int)
    use location <- decode.field(2, decode.int)
    use bag_index <- decode.field(3, decode.int)
    use stack_count <- decode.field(4, decode.int)
    decode.success(LoadCharacterItemsRow(
      item_guid:,
      item2_id:,
      location:,
      bag_index:,
      stack_count:,
    ))
  }

  "-- The items a character holds in its equipped slots, inventory and bank, in
-- the order world entry sends them: by location, then bag index.
select
  item_guid,
  item2_id,
  location::int as location,
  bag_index,
  stack_count
from character_item
where character_id = $1
order by location, bag_index;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_quest_log` query
/// defined in `./src/genesis_prime/store/sql/load_quest_log.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadQuestLogRow {
  LoadQuestLogRow(
    quest_id: Int,
    state: Int,
    completed_at: Int,
    placeholder_objective_id: Option(Int),
    tracked: Option(Bool),
    done_mask: Option(Int),
    progress: Option(List(Int)),
    quest_ms_left: Option(Int),
    objective_ms_left: Option(List(Int)),
  )
}

/// The quests a character has a record of, in quest id order, as the load hands
/// them to the quest log's decode (genesis_prime/game/quest_log). A row of any state
/// but 1 and 2 has no active entry, so its active columns are NULL (the table's
/// `character_quest_active_has_its_entry`). Only a completed row has a time
/// (`character_quest_completed_has_a_time`): `completed_at` is its whole Unix seconds,
/// and 0 for a row of another state, which the decode does not read, since squirrel
/// cannot type a timestamptz or a computed column that may be NULL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_quest_log(
  db: pog.Connection,
  character_id: Int,
) -> Result(pog.Returned(LoadQuestLogRow), pog.QueryError) {
  let decoder = {
    use quest_id <- decode.field(0, decode.int)
    use state <- decode.field(1, decode.int)
    use completed_at <- decode.field(2, decode.int)
    use placeholder_objective_id <- decode.field(3, decode.optional(decode.int))
    use tracked <- decode.field(4, decode.optional(decode.bool))
    use done_mask <- decode.field(5, decode.optional(decode.int))
    use progress <- decode.field(6, decode.optional(decode.list(decode.int)))
    use quest_ms_left <- decode.field(7, decode.optional(decode.int))
    use objective_ms_left <- decode.field(
      8,
      decode.optional(decode.list(decode.int)),
    )
    decode.success(LoadQuestLogRow(
      quest_id:,
      state:,
      completed_at:,
      placeholder_objective_id:,
      tracked:,
      done_mask:,
      progress:,
      quest_ms_left:,
      objective_ms_left:,
    ))
  }

  "-- The quests a character has a record of, in quest id order, as the load hands
-- them to the quest log's decode (genesis_prime/game/quest_log). A row of any state
-- but 1 and 2 has no active entry, so its active columns are NULL (the table's
-- `character_quest_active_has_its_entry`). Only a completed row has a time
-- (`character_quest_completed_has_a_time`): `completed_at` is its whole Unix seconds,
-- and 0 for a row of another state, which the decode does not read, since squirrel
-- cannot type a timestamptz or a computed column that may be NULL.
select
  quest_id,
  state::int as state,
  coalesce(extract(epoch from completed_at), 0)::bigint as completed_at,
  placeholder_objective_id,
  tracked,
  done_mask,
  progress,
  quest_ms_left,
  objective_ms_left
from character_quest
where character_id = $1
order by quest_id;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
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

/// A row you get from running the `lock_character_for_save` query
/// defined in `./src/genesis_prime/store/sql/lock_character_for_save.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LockCharacterForSaveRow {
  LockCharacterForSaveRow(character_id: Int)
}

/// Takes the character's row lock until the transaction ends, so the saves of
/// one character run one after another and the save that follows reads the quest
/// rows the one before it committed (save_place.sql). The statement after it in
/// the transaction takes its snapshot once the lock is held. No row means no such
/// character for the account.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn lock_character_for_save(
  db: pog.Connection,
  character_id: Int,
  account_id: Int,
) -> Result(pog.Returned(LockCharacterForSaveRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(LockCharacterForSaveRow(character_id:))
  }

  "-- Takes the character's row lock until the transaction ends, so the saves of
-- one character run one after another and the save that follows reads the quest
-- rows the one before it committed (save_place.sql). The statement after it in
-- the transaction takes its snapshot once the lock is held. No row means no such
-- character for the account.
select character_id
from character
where character_id = $1 and account_id = $2
for update;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `merge_character_items` query
/// defined in `./src/genesis_prime/store/sql/merge_character_items.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MergeCharacterItemsRow {
  MergeCharacterItemsRow(item_guid: Int)
}

/// Puts `$12` of the stack of the item `$4` onto the stack of the item `$8`, in
/// one statement: the target's count is raised by `$12`, and the source's is
/// lowered by it, or the source is deleted when `$12` is all of it. The source is
/// the item held at `$5` and `$6` with the count `$7`, the target the item held at
/// `$9` and `$10` with the count `$11`, both of the character `$1` of the account
/// `$2`. It changes only while the character is still held by the login that asks,
/// that is while its `session_epoch` ($3) is still the one that login was told
/// (load_character.sql), only when both items are as the request holds them, and
/// only when `$12` is at least 1 and at most `$7`; otherwise it changes nothing and
/// returns no row. The account's id is in the statement, as for a load. The rows it
/// returns are the two items it changed: two, or none. Whether the target may hold
/// the sum is the Item2's maxStackCount, which the rule checks.
///
/// The statement runs after lock_character_for_save.sql in one transaction, so it
/// waits for a login that is raising the epoch and then reads the epoch that login
/// stored.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn merge_character_items(
  db: pog.Connection,
  held_character_id: Int,
  character_account_id: Int,
  character_session_epoch: Int,
  held_item_guid: Int,
  held_location: Int,
  held_bag_index: Int,
  held_stack_count: Int,
  held_item_guid_1: Int,
  held_location_1: Int,
  held_bag_index_1: Int,
  held_stack_count_1: Int,
  source_stack_count: Int,
) -> Result(pog.Returned(MergeCharacterItemsRow), pog.QueryError) {
  let decoder = {
    use item_guid <- decode.field(0, decode.int)
    decode.success(MergeCharacterItemsRow(item_guid:))
  }

  "-- Puts `$12` of the stack of the item `$4` onto the stack of the item `$8`, in
-- one statement: the target's count is raised by `$12`, and the source's is
-- lowered by it, or the source is deleted when `$12` is all of it. The source is
-- the item held at `$5` and `$6` with the count `$7`, the target the item held at
-- `$9` and `$10` with the count `$11`, both of the character `$1` of the account
-- `$2`. It changes only while the character is still held by the login that asks,
-- that is while its `session_epoch` ($3) is still the one that login was told
-- (load_character.sql), only when both items are as the request holds them, and
-- only when `$12` is at least 1 and at most `$7`; otherwise it changes nothing and
-- returns no row. The account's id is in the statement, as for a load. The rows it
-- returns are the two items it changed: two, or none. Whether the target may hold
-- the sum is the Item2's maxStackCount, which the rule checks.
--
-- The statement runs after lock_character_for_save.sql in one transaction, so it
-- waits for a login that is raising the epoch and then reads the epoch that login
-- stored.
with matched as (
  select held.item_guid
  from character_item as held
  join character on character.character_id = held.character_id
  where held.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and $12 >= 1
    and $12 <= $7
    and (
      (
        held.item_guid = $4
        and held.location = $5
        and held.bag_index = $6
        and held.stack_count = $7
      ) or (
        held.item_guid = $8
        and held.location = $9
        and held.bag_index = $10
        and held.stack_count = $11
      )
    )
),
raised as (
  update character_item as target
  set stack_count = target.stack_count + $12
  where target.item_guid = $8
    and (select count(*) from matched) = 2
  returning target.item_guid
),
lowered as (
  update character_item as source
  set stack_count = source.stack_count - $12
  where source.item_guid = $4
    and source.stack_count > $12
    and (select count(*) from matched) = 2
  returning source.item_guid
),
removed as (
  delete from character_item as source
  where source.item_guid = $4
    and source.stack_count = $12
    and (select count(*) from matched) = 2
  returning source.item_guid
)
select item_guid from raised
union all
select item_guid from lowered
union all
select item_guid from removed;
"
  |> pog.query
  |> pog.parameter(pog.int(held_character_id))
  |> pog.parameter(pog.int(character_account_id))
  |> pog.parameter(pog.int(character_session_epoch))
  |> pog.parameter(pog.int(held_item_guid))
  |> pog.parameter(pog.int(held_location))
  |> pog.parameter(pog.int(held_bag_index))
  |> pog.parameter(pog.int(held_stack_count))
  |> pog.parameter(pog.int(held_item_guid_1))
  |> pog.parameter(pog.int(held_location_1))
  |> pog.parameter(pog.int(held_bag_index_1))
  |> pog.parameter(pog.int(held_stack_count_1))
  |> pog.parameter(pog.int(source_stack_count))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `move_character_items` query
/// defined in `./src/genesis_prime/store/sql/move_character_items.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type MoveCharacterItemsRow {
  MoveCharacterItemsRow(item_guid: Int)
}

/// Moves held items to other places, all or none, in one statement: the moves are
/// the lists $4 to $8 at the same position (an item's guid, the location and bag
/// index it is held at, the location and bag index it goes to). It moves only
/// while the character is still held by the login that asks, that is while its
/// `session_epoch` ($3) is still the one that login was told (load_character.sql),
/// and only when every item is at the place its move leaves; otherwise it changes
/// nothing and returns no row. The account's id ($2) is in the statement, as for a
/// load. The rows it returns are the items it moved: as many as the moves, or none.
///
/// The places are swapped by one update under the table's deferrable unique key
/// `character_item_one_per_slot`, which is checked at the statement's end, so two
/// items that trade places pass it together. A place a check of the table refuses
/// breaks that check and nothing is moved. The statement runs after
/// lock_character_for_save.sql in one transaction, so it waits for a login that
/// is raising the epoch and then reads the epoch that login stored.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn move_character_items(
  db: pog.Connection,
  held_character_id: Int,
  character_account_id: Int,
  character_session_epoch: Int,
  arg_4: List(Int),
  arg_5: List(Int),
  arg_6: List(Int),
  arg_7: List(Int),
  arg_8: List(Int),
) -> Result(pog.Returned(MoveCharacterItemsRow), pog.QueryError) {
  let decoder = {
    use item_guid <- decode.field(0, decode.int)
    decode.success(MoveCharacterItemsRow(item_guid:))
  }

  "-- Moves held items to other places, all or none, in one statement: the moves are
-- the lists $4 to $8 at the same position (an item's guid, the location and bag
-- index it is held at, the location and bag index it goes to). It moves only
-- while the character is still held by the login that asks, that is while its
-- `session_epoch` ($3) is still the one that login was told (load_character.sql),
-- and only when every item is at the place its move leaves; otherwise it changes
-- nothing and returns no row. The account's id ($2) is in the statement, as for a
-- load. The rows it returns are the items it moved: as many as the moves, or none.
--
-- The places are swapped by one update under the table's deferrable unique key
-- `character_item_one_per_slot`, which is checked at the statement's end, so two
-- items that trade places pass it together. A place a check of the table refuses
-- breaks that check and nothing is moved. The statement runs after
-- lock_character_for_save.sql in one transaction, so it waits for a login that
-- is raising the epoch and then reads the epoch that login stored.
with incoming as (
  select *
  from unnest($4::bigint[], $5::int[], $6::int[], $7::int[], $8::int[])
    as move (item_guid, from_location, from_index, to_location, to_index)
),
matched as (
  select held.item_guid, incoming.to_location, incoming.to_index
  from incoming
  join character_item as held on held.item_guid = incoming.item_guid
  join character on character.character_id = held.character_id
  where held.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and held.location = incoming.from_location
    and held.bag_index = incoming.from_index
)
update character_item as held
set location = matched.to_location::smallint, bag_index = matched.to_index
from matched
where held.item_guid = matched.item_guid
  and (select count(*) from matched) = (select count(*) from incoming)
returning held.item_guid;
"
  |> pog.query
  |> pog.parameter(pog.int(held_character_id))
  |> pog.parameter(pog.int(character_account_id))
  |> pog.parameter(pog.int(character_session_epoch))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_5))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_6))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_7))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_8))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `rename_character` query
/// defined in `./src/genesis_prime/store/sql/rename_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RenameCharacterRow {
  RenameCharacterRow(name: String)
}

/// Gives the account's marked character the name and clears the mark, in one
/// update. No row means the account has no such character or it is not marked.
/// A name that another character holds in any case breaks the unique index on
/// lower(name collate "und-x-icu"), which the caller reports as its own error,
/// and the mark stays.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn rename_character(
  db: pog.Connection,
  character_id: Int,
  account_id: Int,
  arg_3: String,
) -> Result(pog.Returned(RenameCharacterRow), pog.QueryError) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    decode.success(RenameCharacterRow(name:))
  }

  "-- Gives the account's marked character the name and clears the mark, in one
-- update. No row means the account has no such character or it is not marked.
-- A name that another character holds in any case breaks the unique index on
-- lower(name collate \"und-x-icu\"), which the caller reports as its own error,
-- and the mark stays.
update character
set name = $3, needs_rename = false
where character_id = $1 and account_id = $2 and needs_rename
returning name;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(account_id))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `save_place` query
/// defined in `./src/genesis_prime/store/sql/save_place.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SavePlaceRow {
  SavePlaceRow(character_id: Int)
}

/// Saves where a character stands: its world, zone, position and facing, and the
/// health, experience and level it has, and its quest log, in one statement, so
/// they are saved together or not at all; the experience is $15 and the level it
/// makes $16. The health is $13 when $14 is true, and NULL (nothing saved: the
/// next entry is alive at full health) when it is false, since
/// squirrel cannot type a parameter that may be NULL. A dead player saves 0,
/// which its next entry is dead at. It writes only
/// while the character is still held by the login that made the save, that is
/// while its `session_epoch` is still the one that login raised it to
/// (load_character.sql), and only when the save is newer than the last one stored
/// for that login: `save_sequence` ($12) is above the stored one. A login that
/// came after raised the epoch, so a save from an older login matches no row and
/// changes nothing; a save of this login that comes after a newer one of its own
/// matches none either. The account's id is in the statement, as for a load. No
/// row means the epoch moved on, a newer save was stored first, or the account
/// has no such character.
///
/// The quest log is $17, a JSON array with one object for each quest the character
/// has a record of, whose keys are the columns of `character_quest` (a completed
/// time in whole Unix seconds): it is unpacked here so that squirrel needs no array
/// of arrays. The log is the whole log, so a row the character no longer has is
/// deleted and a row that changed is written, both only through the row the fence
/// above matched, so a save the fence refuses writes no quest row either. A row
/// that did not change is not written. The statement runs after
/// lock_character_for_save.sql in one transaction: a statement takes its snapshot
/// before it waits for a row another save holds, so without the lock a save that
/// waited would delete or keep quest rows by the log the earlier save had not yet
/// written, and leave a quest the later log dropped.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn save_place(
  db: pog.Connection,
  character_id: Int,
  account_id: Int,
  session_epoch: Int,
  arg_4: Int,
  arg_5: Int,
  arg_6: Float,
  arg_7: Float,
  arg_8: Float,
  arg_9: Float,
  arg_10: Float,
  arg_11: Float,
  arg_12: Int,
  arg_13: Int,
  arg_14: Bool,
  arg_15: Int,
  arg_16: Int,
  arg_17: Json,
) -> Result(pog.Returned(SavePlaceRow), pog.QueryError) {
  let decoder = {
    use character_id <- decode.field(0, decode.int)
    decode.success(SavePlaceRow(character_id:))
  }

  "-- Saves where a character stands: its world, zone, position and facing, and the
-- health, experience and level it has, and its quest log, in one statement, so
-- they are saved together or not at all; the experience is $15 and the level it
-- makes $16. The health is $13 when $14 is true, and NULL (nothing saved: the
-- next entry is alive at full health) when it is false, since
-- squirrel cannot type a parameter that may be NULL. A dead player saves 0,
-- which its next entry is dead at. It writes only
-- while the character is still held by the login that made the save, that is
-- while its `session_epoch` is still the one that login raised it to
-- (load_character.sql), and only when the save is newer than the last one stored
-- for that login: `save_sequence` ($12) is above the stored one. A login that
-- came after raised the epoch, so a save from an older login matches no row and
-- changes nothing; a save of this login that comes after a newer one of its own
-- matches none either. The account's id is in the statement, as for a load. No
-- row means the epoch moved on, a newer save was stored first, or the account
-- has no such character.
--
-- The quest log is $17, a JSON array with one object for each quest the character
-- has a record of, whose keys are the columns of `character_quest` (a completed
-- time in whole Unix seconds): it is unpacked here so that squirrel needs no array
-- of arrays. The log is the whole log, so a row the character no longer has is
-- deleted and a row that changed is written, both only through the row the fence
-- above matched, so a save the fence refuses writes no quest row either. A row
-- that did not change is not written. The statement runs after
-- lock_character_for_save.sql in one transaction: a statement takes its snapshot
-- before it waits for a row another save holds, so without the lock a save that
-- waited would delete or keep quest rows by the log the earlier save had not yet
-- written, and leave a quest the later log dropped.
with saved as (
  update character
  set
    world_id = $4,
    world_zone_id = $5,
    position_x = $6,
    position_y = $7,
    position_z = $8,
    rotation_yaw = $9,
    rotation_pitch = $10,
    rotation_roll = $11,
    save_sequence = $12,
    health = case when $14 then $13::int end,
    experience = $15::int,
    level = $16::int
  where character_id = $1 and account_id = $2 and session_epoch = $3
    and save_sequence < $12
  returning character_id
),
incoming as (
  select *
  from jsonb_to_recordset($17::jsonb) as quest(
    quest_id integer,
    state smallint,
    completed_at bigint,
    placeholder_objective_id integer,
    tracked boolean,
    done_mask smallint,
    progress integer[],
    quest_ms_left integer,
    objective_ms_left integer[]
  )
),
gone as (
  delete from character_quest as held
  using saved
  where held.character_id = saved.character_id
    and not exists (
      select 1 from incoming where incoming.quest_id = held.quest_id
    )
),
put as (
  insert into character_quest (
    character_id,
    quest_id,
    state,
    completed_at,
    placeholder_objective_id,
    tracked,
    done_mask,
    progress,
    quest_ms_left,
    objective_ms_left
  )
  select
    saved.character_id,
    incoming.quest_id,
    incoming.state,
    to_timestamp(incoming.completed_at),
    incoming.placeholder_objective_id,
    incoming.tracked,
    incoming.done_mask,
    incoming.progress,
    incoming.quest_ms_left,
    incoming.objective_ms_left
  from saved
  cross join incoming
  on conflict (character_id, quest_id) do update
  set
    state = excluded.state,
    completed_at = excluded.completed_at,
    placeholder_objective_id = excluded.placeholder_objective_id,
    tracked = excluded.tracked,
    done_mask = excluded.done_mask,
    progress = excluded.progress,
    quest_ms_left = excluded.quest_ms_left,
    objective_ms_left = excluded.objective_ms_left
  where (
    character_quest.state,
    character_quest.completed_at,
    character_quest.placeholder_objective_id,
    character_quest.tracked,
    character_quest.done_mask,
    character_quest.progress,
    character_quest.quest_ms_left,
    character_quest.objective_ms_left
  ) is distinct from (
    excluded.state,
    excluded.completed_at,
    excluded.placeholder_objective_id,
    excluded.tracked,
    excluded.done_mask,
    excluded.progress,
    excluded.quest_ms_left,
    excluded.objective_ms_left
  )
)
select character_id from saved;
"
  |> pog.query
  |> pog.parameter(pog.int(character_id))
  |> pog.parameter(pog.int(account_id))
  |> pog.parameter(pog.int(session_epoch))
  |> pog.parameter(pog.int(arg_4))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.float(arg_6))
  |> pog.parameter(pog.float(arg_7))
  |> pog.parameter(pog.float(arg_8))
  |> pog.parameter(pog.float(arg_9))
  |> pog.parameter(pog.float(arg_10))
  |> pog.parameter(pog.float(arg_11))
  |> pog.parameter(pog.int(arg_12))
  |> pog.parameter(pog.int(arg_13))
  |> pog.parameter(pog.bool(arg_14))
  |> pog.parameter(pog.int(arg_15))
  |> pog.parameter(pog.int(arg_16))
  |> pog.parameter(pog.text(json.to_string(arg_17)))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `select_one` query
/// defined in `./src/genesis_prime/store/sql/select_one.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SelectOneRow {
  SelectOneRow(one: Int)
}

/// The readiness probe: a read that needs no table, so it succeeds exactly when
/// the pool can run a query on a connection.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn select_one(
  db: pog.Connection,
) -> Result(pog.Returned(SelectOneRow), pog.QueryError) {
  let decoder = {
    use one <- decode.field(0, decode.int)
    decode.success(SelectOneRow(one:))
  }

  "-- The readiness probe: a read that needs no table, so it succeeds exactly when
-- the pool can run a query on a connection.
select 1 as one;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `split_character_item` query
/// defined in `./src/genesis_prime/store/sql/split_character_item.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SplitCharacterItemRow {
  SplitCharacterItemRow(item_guid: Int)
}

/// Takes `$8` off the stack of the item `$4` and makes a new stack of them at the
/// place `$9` and `$10`, in one statement. The source is the item the login holds
/// at `$5` and `$6` with the count `$7`; it is lowered only while the character is
/// still held by the login that asks, that is while its `session_epoch` ($3) is
/// still the one that login was told (load_character.sql), and only when that item
/// is as the request holds it, of the character `$1` of the account `$2`, and
/// `$8` is at least 1 and less than `$7`, which leaves the source at 1 or more.
/// Otherwise it changes nothing and returns no row. The account's id is in the
/// statement, as for a load. The row it returns is the new stack's, whose guid
/// the database makes (opcode.0x111.guid).
///
/// A place that holds an item breaks the table's `character_item_one_per_slot` at
/// the statement's end and the statement changes nothing, the source included. The
/// statement runs after lock_character_for_save.sql in one transaction, so it waits
/// for a login that is raising the epoch and then reads the epoch that login
/// stored.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn split_character_item(
  db: pog.Connection,
  source_character_id: Int,
  character_account_id: Int,
  character_session_epoch: Int,
  source_item_guid: Int,
  source_location: Int,
  source_bag_index: Int,
  source_stack_count: Int,
  arg_8: Int,
  arg_9: Int,
  arg_10: Int,
) -> Result(pog.Returned(SplitCharacterItemRow), pog.QueryError) {
  let decoder = {
    use item_guid <- decode.field(0, decode.int)
    decode.success(SplitCharacterItemRow(item_guid:))
  }

  "-- Takes `$8` off the stack of the item `$4` and makes a new stack of them at the
-- place `$9` and `$10`, in one statement. The source is the item the login holds
-- at `$5` and `$6` with the count `$7`; it is lowered only while the character is
-- still held by the login that asks, that is while its `session_epoch` ($3) is
-- still the one that login was told (load_character.sql), and only when that item
-- is as the request holds it, of the character `$1` of the account `$2`, and
-- `$8` is at least 1 and less than `$7`, which leaves the source at 1 or more.
-- Otherwise it changes nothing and returns no row. The account's id is in the
-- statement, as for a load. The row it returns is the new stack's, whose guid
-- the database makes (opcode.0x111.guid).
--
-- A place that holds an item breaks the table's `character_item_one_per_slot` at
-- the statement's end and the statement changes nothing, the source included. The
-- statement runs after lock_character_for_save.sql in one transaction, so it waits
-- for a login that is raising the epoch and then reads the epoch that login
-- stored.
with lowered as (
  update character_item as source
  set stack_count = source.stack_count - $8
  from character
  where character.character_id = source.character_id
    and source.item_guid = $4
    and source.character_id = $1
    and character.account_id = $2
    and character.session_epoch = $3
    and source.location = $5
    and source.bag_index = $6
    and source.stack_count = $7
    and $8 >= 1
    and $8 < $7
  returning source.item2_id
)
insert into character_item (character_id, item2_id, location, bag_index, stack_count)
select $1, lowered.item2_id, $9, $10, $8
from lowered
returning item_guid;
"
  |> pog.query
  |> pog.parameter(pog.int(source_character_id))
  |> pog.parameter(pog.int(character_account_id))
  |> pog.parameter(pog.int(character_session_epoch))
  |> pog.parameter(pog.int(source_item_guid))
  |> pog.parameter(pog.int(source_location))
  |> pog.parameter(pog.int(source_bag_index))
  |> pog.parameter(pog.int(source_stack_count))
  |> pog.parameter(pog.int(arg_8))
  |> pog.parameter(pog.int(arg_9))
  |> pog.parameter(pog.int(arg_10))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
