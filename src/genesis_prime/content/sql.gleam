//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/content/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `load_creature_kinds` query
/// defined in `./src/genesis_prime/content/sql/load_creature_kinds.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadCreatureKindsRow {
  LoadCreatureKindsRow(
    creature_id: Int,
    respawn_ms: Int,
    attack_spell4_id: Int,
    attack_interval_ms: Int,
  )
}

/// Every row of the creature_kind table in creature id order, row 0 the default
/// first: the one query the load makes of the table at start
/// (genesis_prime/content/creature_kind). The checks run on these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_creature_kinds(
  db: pog.Connection,
) -> Result(pog.Returned(LoadCreatureKindsRow), pog.QueryError) {
  let decoder = {
    use creature_id <- decode.field(0, decode.int)
    use respawn_ms <- decode.field(1, decode.int)
    use attack_spell4_id <- decode.field(2, decode.int)
    use attack_interval_ms <- decode.field(3, decode.int)
    decode.success(LoadCreatureKindsRow(
      creature_id:,
      respawn_ms:,
      attack_spell4_id:,
      attack_interval_ms:,
    ))
  }

  "-- Every row of the creature_kind table in creature id order, row 0 the default
-- first: the one query the load makes of the table at start
-- (genesis_prime/content/creature_kind). The checks run on these rows, not in SQL.
select
  creature_id,
  respawn_ms,
  attack_spell4_id,
  attack_interval_ms
from creature_kind
order by creature_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_game_numbers` query
/// defined in `./src/genesis_prime/content/sql/load_game_numbers.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadGameNumbersRow {
  LoadGameNumbersRow(name: String, value: Float, unit: String)
}

/// Every row of the game_number table in name order: the one query the load makes
/// of the table at start (genesis_prime/content/game_number). The checks run on
/// these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_game_numbers(
  db: pog.Connection,
) -> Result(pog.Returned(LoadGameNumbersRow), pog.QueryError) {
  let decoder = {
    use name <- decode.field(0, decode.string)
    use value <- decode.field(1, decode.float)
    use unit <- decode.field(2, decode.string)
    decode.success(LoadGameNumbersRow(name:, value:, unit:))
  }

  "-- Every row of the game_number table in name order: the one query the load makes
-- of the table at start (genesis_prime/content/game_number). The checks run on
-- these rows, not in SQL.
select
  name,
  value,
  unit
from game_number
order by name;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_spawns` query
/// defined in `./src/genesis_prime/content/sql/load_spawns.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadSpawnsRow {
  LoadSpawnsRow(
    id: Int,
    entity_type: Int,
    creature_id: Int,
    world_id: Int,
    area_id: Int,
    x: Float,
    y: Float,
    z: Float,
    rotation_x: Float,
    rotation_y: Float,
    rotation_z: Float,
    display_info_id: Int,
    outfit_info_id: Int,
    faction_id: Int,
    base_faction_id: Int,
    quest_checklist_index: Int,
    active_prop_id: Int,
    world_socket_id: Int,
    health: Option(Float),
    level: Option(Float),
  )
}

/// Every row of the spawn table with its health (stat 0) and level (stat 10)
/// when the row has them, in world and id order: the one query the load makes of
/// the table at start (genesis_prime/content/spawn). The selection of which
/// rows start runs on these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_spawns(
  db: pog.Connection,
) -> Result(pog.Returned(LoadSpawnsRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    use entity_type <- decode.field(1, decode.int)
    use creature_id <- decode.field(2, decode.int)
    use world_id <- decode.field(3, decode.int)
    use area_id <- decode.field(4, decode.int)
    use x <- decode.field(5, decode.float)
    use y <- decode.field(6, decode.float)
    use z <- decode.field(7, decode.float)
    use rotation_x <- decode.field(8, decode.float)
    use rotation_y <- decode.field(9, decode.float)
    use rotation_z <- decode.field(10, decode.float)
    use display_info_id <- decode.field(11, decode.int)
    use outfit_info_id <- decode.field(12, decode.int)
    use faction_id <- decode.field(13, decode.int)
    use base_faction_id <- decode.field(14, decode.int)
    use quest_checklist_index <- decode.field(15, decode.int)
    use active_prop_id <- decode.field(16, decode.int)
    use world_socket_id <- decode.field(17, decode.int)
    use health <- decode.field(18, decode.optional(decode.float))
    use level <- decode.field(19, decode.optional(decode.float))
    decode.success(LoadSpawnsRow(
      id:,
      entity_type:,
      creature_id:,
      world_id:,
      area_id:,
      x:,
      y:,
      z:,
      rotation_x:,
      rotation_y:,
      rotation_z:,
      display_info_id:,
      outfit_info_id:,
      faction_id:,
      base_faction_id:,
      quest_checklist_index:,
      active_prop_id:,
      world_socket_id:,
      health:,
      level:,
    ))
  }

  "-- Every row of the spawn table with its health (stat 0) and level (stat 10)
-- when the row has them, in world and id order: the one query the load makes of
-- the table at start (genesis_prime/content/spawn). The selection of which
-- rows start runs on these rows, not in SQL.
select
  spawn.id,
  spawn.entity_type,
  spawn.creature_id,
  spawn.world_id,
  spawn.area_id,
  spawn.x,
  spawn.y,
  spawn.z,
  spawn.rotation_x,
  spawn.rotation_y,
  spawn.rotation_z,
  spawn.display_info_id,
  spawn.outfit_info_id,
  spawn.faction_id,
  spawn.base_faction_id,
  spawn.quest_checklist_index,
  spawn.active_prop_id,
  spawn.world_socket_id,
  health.value as health,
  level.value as level
from spawn
left join spawn_stat as health
  on health.spawn_id = spawn.id and health.stat = 0
left join spawn_stat as level
  on level.spawn_id = spawn.id and level.stat = 10
order by spawn.world_id, spawn.id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}
