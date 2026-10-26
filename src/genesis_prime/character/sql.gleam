//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/character/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `characters_of_account` query
/// defined in `./src/genesis_prime/character/sql/characters_of_account.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CharactersOfAccountRow {
  CharactersOfAccountRow(
    id: Int,
    account_id: Int,
    name: String,
    creation_id: Int,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    experience: Int,
    level: Int,
    path: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
    customisation_labels: List(Int),
    customisation_values: List(Int),
    bone_values: List(Int),
    requires_rename: Bool,
    disabled: Bool,
  )
}

/// Every character of one account, oldest first.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn characters_of_account(
  db: pog.Connection,
  account_id: Int,
) -> Result(pog.Returned(CharactersOfAccountRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use account_id <- decode.field(1, decode.int)
    use name <- decode.field(2, decode.string)
    use creation_id <- decode.field(3, decode.int)
    use gender <- decode.field(4, decode.int)
    use race_id <- decode.field(5, decode.int)
    use class_id <- decode.field(6, decode.int)
    use faction_id <- decode.field(7, decode.int)
    use experience <- decode.field(8, decode.int)
    use level <- decode.field(9, decode.int)
    use path <- decode.field(10, decode.int)
    use world_id <- decode.field(11, decode.int)
    use world_zone_id <- decode.field(12, decode.int)
    use position_x <- decode.field(13, decode.float)
    use position_y <- decode.field(14, decode.float)
    use position_z <- decode.field(15, decode.float)
    use customisation_labels <- decode.field(16, decode.list(decode.int))
    use customisation_values <- decode.field(17, decode.list(decode.int))
    use bone_values <- decode.field(18, decode.list(decode.int))
    use requires_rename <- decode.field(19, decode.bool)
    use disabled <- decode.field(20, decode.bool)
    decode.success(CharactersOfAccountRow(
      id:,
      account_id:,
      name:,
      creation_id:,
      gender:,
      race_id:,
      class_id:,
      faction_id:,
      experience:,
      level:,
      path:,
      world_id:,
      world_zone_id:,
      position_x:,
      position_y:,
      position_z:,
      customisation_labels:,
      customisation_values:,
      bone_values:,
      requires_rename:,
      disabled:,
    ))
  }

  "-- Every character of one account, oldest first.
select
  id,
  account_id,
  name,
  creation_id,
  gender,
  race_id,
  class_id,
  faction_id,
  experience,
  level,
  path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  customisation_labels,
  customisation_values,
  bone_values,
  requires_rename,
  disabled
from character
where account_id = $1
order by id;
"
  |> pog.query
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `delete_character` query
/// defined in `./src/genesis_prime/character/sql/delete_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DeleteCharacterRow {
  DeleteCharacterRow(id: Int)
}

/// Deletes a character of the account and returns its id. No row is returned
/// when the account has no such character.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_character(
  db: pog.Connection,
  id: Int,
  account_id: Int,
) -> Result(pog.Returned(DeleteCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    decode.success(DeleteCharacterRow(id:))
  }

  "-- Deletes a character of the account and returns its id. No row is returned
-- when the account has no such character.
delete from character
where id = $1 and account_id = $2
returning id;
"
  |> pog.query
  |> pog.parameter(pog.int(id))
  |> pog.parameter(pog.int(account_id))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `insert_character` query
/// defined in `./src/genesis_prime/character/sql/insert_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type InsertCharacterRow {
  InsertCharacterRow(
    id: Int,
    account_id: Int,
    name: String,
    creation_id: Int,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    experience: Int,
    level: Int,
    path: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
    customisation_labels: List(Int),
    customisation_values: List(Int),
    bone_values: List(Int),
    requires_rename: Bool,
    disabled: Bool,
  )
}

/// Adds a character to an account and returns it as saved. A name another
/// character has violates the unique name constraint.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_character(
  db: pog.Connection,
  arg_1: Int,
  arg_2: String,
  arg_3: Int,
  arg_4: Int,
  arg_5: Int,
  arg_6: Int,
  arg_7: Int,
  arg_8: Int,
  arg_9: Int,
  arg_10: Int,
  arg_11: Int,
  arg_12: Int,
  arg_13: Float,
  arg_14: Float,
  arg_15: Float,
  arg_16: List(Int),
  arg_17: List(Int),
  arg_18: List(Int),
) -> Result(pog.Returned(InsertCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use account_id <- decode.field(1, decode.int)
    use name <- decode.field(2, decode.string)
    use creation_id <- decode.field(3, decode.int)
    use gender <- decode.field(4, decode.int)
    use race_id <- decode.field(5, decode.int)
    use class_id <- decode.field(6, decode.int)
    use faction_id <- decode.field(7, decode.int)
    use experience <- decode.field(8, decode.int)
    use level <- decode.field(9, decode.int)
    use path <- decode.field(10, decode.int)
    use world_id <- decode.field(11, decode.int)
    use world_zone_id <- decode.field(12, decode.int)
    use position_x <- decode.field(13, decode.float)
    use position_y <- decode.field(14, decode.float)
    use position_z <- decode.field(15, decode.float)
    use customisation_labels <- decode.field(16, decode.list(decode.int))
    use customisation_values <- decode.field(17, decode.list(decode.int))
    use bone_values <- decode.field(18, decode.list(decode.int))
    use requires_rename <- decode.field(19, decode.bool)
    use disabled <- decode.field(20, decode.bool)
    decode.success(InsertCharacterRow(
      id:,
      account_id:,
      name:,
      creation_id:,
      gender:,
      race_id:,
      class_id:,
      faction_id:,
      experience:,
      level:,
      path:,
      world_id:,
      world_zone_id:,
      position_x:,
      position_y:,
      position_z:,
      customisation_labels:,
      customisation_values:,
      bone_values:,
      requires_rename:,
      disabled:,
    ))
  }

  "-- Adds a character to an account and returns it as saved. A name another
-- character has violates the unique name constraint.
insert into character (
  account_id,
  name,
  creation_id,
  gender,
  race_id,
  class_id,
  faction_id,
  experience,
  level,
  path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  customisation_labels,
  customisation_values,
  bone_values
)
values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
returning
  id,
  account_id,
  name,
  creation_id,
  gender,
  race_id,
  class_id,
  faction_id,
  experience,
  level,
  path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  customisation_labels,
  customisation_values,
  bone_values,
  requires_rename,
  disabled;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.parameter(pog.int(arg_7))
  |> pog.parameter(pog.int(arg_8))
  |> pog.parameter(pog.int(arg_9))
  |> pog.parameter(pog.int(arg_10))
  |> pog.parameter(pog.int(arg_11))
  |> pog.parameter(pog.int(arg_12))
  |> pog.parameter(pog.float(arg_13))
  |> pog.parameter(pog.float(arg_14))
  |> pog.parameter(pog.float(arg_15))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_16))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_17))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_18))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `rename_character` query
/// defined in `./src/genesis_prime/character/sql/rename_character.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type RenameCharacterRow {
  RenameCharacterRow(
    id: Int,
    account_id: Int,
    name: String,
    creation_id: Int,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    experience: Int,
    level: Int,
    path: Int,
    world_id: Int,
    world_zone_id: Int,
    position_x: Float,
    position_y: Float,
    position_z: Float,
    customisation_labels: List(Int),
    customisation_values: List(Int),
    bone_values: List(Int),
    requires_rename: Bool,
    disabled: Bool,
  )
}

/// Gives a character of the account a new name, clears its need to be renamed
/// and returns it. No row is returned when the account has no such character.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn rename_character(
  db: pog.Connection,
  id: Int,
  account_id: Int,
  arg_3: String,
) -> Result(pog.Returned(RenameCharacterRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use account_id <- decode.field(1, decode.int)
    use name <- decode.field(2, decode.string)
    use creation_id <- decode.field(3, decode.int)
    use gender <- decode.field(4, decode.int)
    use race_id <- decode.field(5, decode.int)
    use class_id <- decode.field(6, decode.int)
    use faction_id <- decode.field(7, decode.int)
    use experience <- decode.field(8, decode.int)
    use level <- decode.field(9, decode.int)
    use path <- decode.field(10, decode.int)
    use world_id <- decode.field(11, decode.int)
    use world_zone_id <- decode.field(12, decode.int)
    use position_x <- decode.field(13, decode.float)
    use position_y <- decode.field(14, decode.float)
    use position_z <- decode.field(15, decode.float)
    use customisation_labels <- decode.field(16, decode.list(decode.int))
    use customisation_values <- decode.field(17, decode.list(decode.int))
    use bone_values <- decode.field(18, decode.list(decode.int))
    use requires_rename <- decode.field(19, decode.bool)
    use disabled <- decode.field(20, decode.bool)
    decode.success(RenameCharacterRow(
      id:,
      account_id:,
      name:,
      creation_id:,
      gender:,
      race_id:,
      class_id:,
      faction_id:,
      experience:,
      level:,
      path:,
      world_id:,
      world_zone_id:,
      position_x:,
      position_y:,
      position_z:,
      customisation_labels:,
      customisation_values:,
      bone_values:,
      requires_rename:,
      disabled:,
    ))
  }

  "-- Gives a character of the account a new name, clears its need to be renamed
-- and returns it. No row is returned when the account has no such character.
update character
set name = $3, requires_rename = false
where id = $1 and account_id = $2
returning
  id,
  account_id,
  name,
  creation_id,
  gender,
  race_id,
  class_id,
  faction_id,
  experience,
  level,
  path,
  world_id,
  world_zone_id,
  position_x,
  position_y,
  position_z,
  customisation_labels,
  customisation_values,
  bone_values,
  requires_rename,
  disabled;
"
  |> pog.query
  |> pog.parameter(pog.int(id))
  |> pog.parameter(pog.int(account_id))
  |> pog.parameter(pog.text(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
