//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/content/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

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
    use health <- decode.field(15, decode.optional(decode.float))
    use level <- decode.field(16, decode.optional(decode.float))
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
