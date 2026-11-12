//// This module contains the code to run the sql queries defined in
//// `./src/genesis_prime/content/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `load_class_resources` query
/// defined in `./src/genesis_prime/content/sql/load_class_resources.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadClassResourcesRow {
  LoadClassResourcesRow(class_id: Int, name: String, value: Float, unit: String)
}

/// Every row of the class_resource table in class and name order: the one query the
/// load makes of the table at start (genesis_prime/content/class_resource). The
/// checks run on these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_class_resources(
  db: pog.Connection,
) -> Result(pog.Returned(LoadClassResourcesRow), pog.QueryError) {
  let decoder = {
    use class_id <- decode.field(0, decode.int)
    use name <- decode.field(1, decode.string)
    use value <- decode.field(2, decode.float)
    use unit <- decode.field(3, decode.string)
    decode.success(LoadClassResourcesRow(class_id:, name:, value:, unit:))
  }

  "-- Every row of the class_resource table in class and name order: the one query the
-- load makes of the table at start (genesis_prime/content/class_resource). The
-- checks run on these rows, not in SQL.
select
  class_id,
  name,
  value,
  unit
from class_resource
order by class_id, name;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_creature_factions` query
/// defined in `./src/genesis_prime/content/sql/load_creature_factions.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadCreatureFactionsRow {
  LoadCreatureFactionsRow(creature_id: Int, faction_id: Int)
}

/// Every row of the creature_faction table in creature id order: the one query the
/// load makes of the table at start (genesis_prime/content/creature_faction). The
/// checks run on these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_creature_factions(
  db: pog.Connection,
) -> Result(pog.Returned(LoadCreatureFactionsRow), pog.QueryError) {
  let decoder = {
    use creature_id <- decode.field(0, decode.int)
    use faction_id <- decode.field(1, decode.int)
    decode.success(LoadCreatureFactionsRow(creature_id:, faction_id:))
  }

  "-- Every row of the creature_faction table in creature id order: the one query the
-- load makes of the table at start (genesis_prime/content/creature_faction). The
-- checks run on these rows, not in SQL.
select
  creature_id,
  faction_id
from creature_faction
order by creature_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

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
    guard_spell4_id: Option(Int),
    opening_spell4_id: Option(Int),
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
    use guard_spell4_id <- decode.field(4, decode.optional(decode.int))
    use opening_spell4_id <- decode.field(5, decode.optional(decode.int))
    decode.success(LoadCreatureKindsRow(
      creature_id:,
      respawn_ms:,
      attack_spell4_id:,
      attack_interval_ms:,
      guard_spell4_id:,
      opening_spell4_id:,
    ))
  }

  "-- Every row of the creature_kind table in creature id order, row 0 the default
-- first: the one query the load makes of the table at start
-- (genesis_prime/content/creature_kind). The checks run on these rows, not in SQL.
select
  creature_id,
  respawn_ms,
  attack_spell4_id,
  attack_interval_ms,
  guard_spell4_id,
  opening_spell4_id
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

/// A row you get from running the `load_projector_landings` query
/// defined in `./src/genesis_prime/content/sql/load_projector_landings.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadProjectorLandingsRow {
  LoadProjectorLandingsRow(
    creature_id: Int,
    faction_enum: Int,
    objective_id: Int,
    world_location2_id: Int,
  )
}

/// Every row of the projector_landing table in key order: the one query the load makes
/// of the table at start (genesis_prime/content/projector_landing). The checks run on
/// these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_projector_landings(
  db: pog.Connection,
) -> Result(pog.Returned(LoadProjectorLandingsRow), pog.QueryError) {
  let decoder = {
    use creature_id <- decode.field(0, decode.int)
    use faction_enum <- decode.field(1, decode.int)
    use objective_id <- decode.field(2, decode.int)
    use world_location2_id <- decode.field(3, decode.int)
    decode.success(LoadProjectorLandingsRow(
      creature_id:,
      faction_enum:,
      objective_id:,
      world_location2_id:,
    ))
  }

  "-- Every row of the projector_landing table in key order: the one query the load makes
-- of the table at start (genesis_prime/content/projector_landing). The checks run on
-- these rows, not in SQL.
select
  creature_id,
  faction_enum,
  objective_id,
  world_location2_id
from projector_landing
order by creature_id, faction_enum;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_server_proxies` query
/// defined in `./src/genesis_prime/content/sql/load_server_proxies.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadServerProxiesRow {
  LoadServerProxiesRow(spell4_base_id: Int, phase: Int, spell4_id: Int)
}

/// Every row of the server_proxy table in key order: the one query the load makes of
/// the table at start (genesis_prime/content/server_proxy). The checks run on these
/// rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_server_proxies(
  db: pog.Connection,
) -> Result(pog.Returned(LoadServerProxiesRow), pog.QueryError) {
  let decoder = {
    use spell4_base_id <- decode.field(0, decode.int)
    use phase <- decode.field(1, decode.int)
    use spell4_id <- decode.field(2, decode.int)
    decode.success(LoadServerProxiesRow(spell4_base_id:, phase:, spell4_id:))
  }

  "-- Every row of the server_proxy table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/server_proxy). The checks run on these
-- rows, not in SQL.
select
  spell4_base_id,
  phase,
  spell4_id
from server_proxy
order by spell4_base_id, phase, spell4_id;
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
    use active_prop_id <- decode.field(15, decode.int)
    use world_socket_id <- decode.field(16, decode.int)
    use health <- decode.field(17, decode.optional(decode.float))
    use level <- decode.field(18, decode.optional(decode.float))
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

/// A row you get from running the `load_tutorial_quests` query
/// defined in `./src/genesis_prime/content/sql/load_tutorial_quests.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadTutorialQuestsRow {
  LoadTutorialQuestsRow(quest_id: Int, follows_quest_id: Option(Int))
}

/// Every row of the tutorial_quest table in key order: the one query the load makes of
/// the table at start (genesis_prime/content/tutorial_quest). The checks run on these
/// rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_tutorial_quests(
  db: pog.Connection,
) -> Result(pog.Returned(LoadTutorialQuestsRow), pog.QueryError) {
  let decoder = {
    use quest_id <- decode.field(0, decode.int)
    use follows_quest_id <- decode.field(1, decode.optional(decode.int))
    decode.success(LoadTutorialQuestsRow(quest_id:, follows_quest_id:))
  }

  "-- Every row of the tutorial_quest table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/tutorial_quest). The checks run on these
-- rows, not in SQL.
select
  quest_id,
  follows_quest_id
from tutorial_quest
order by quest_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_vendor_items` query
/// defined in `./src/genesis_prime/content/sql/load_vendor_items.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadVendorItemsRow {
  LoadVendorItemsRow(creature_id: Int, position: Int, item_id: Int)
}

/// Every row of the vendor_item table in creature and position order: the other query the
/// load makes of the vendor tables at start (genesis_prime/content/vendor). The checks run
/// on these rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_vendor_items(
  db: pog.Connection,
) -> Result(pog.Returned(LoadVendorItemsRow), pog.QueryError) {
  let decoder = {
    use creature_id <- decode.field(0, decode.int)
    use position <- decode.field(1, decode.int)
    use item_id <- decode.field(2, decode.int)
    decode.success(LoadVendorItemsRow(creature_id:, position:, item_id:))
  }

  "-- Every row of the vendor_item table in creature and position order: the other query the
-- load makes of the vendor tables at start (genesis_prime/content/vendor). The checks run
-- on these rows, not in SQL.
select
  creature_id,
  position,
  item_id
from vendor_item
order by creature_id, position;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_vendors` query
/// defined in `./src/genesis_prime/content/sql/load_vendors.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadVendorsRow {
  LoadVendorsRow(
    creature_id: Int,
    buy_multiplier: Float,
    sell_multiplier: Float,
  )
}

/// Every row of the vendor table in creature order: one of the two queries the load makes
/// of the vendor tables at start (genesis_prime/content/vendor). The checks run on these
/// rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_vendors(
  db: pog.Connection,
) -> Result(pog.Returned(LoadVendorsRow), pog.QueryError) {
  let decoder = {
    use creature_id <- decode.field(0, decode.int)
    use buy_multiplier <- decode.field(1, decode.float)
    use sell_multiplier <- decode.field(2, decode.float)
    decode.success(LoadVendorsRow(
      creature_id:,
      buy_multiplier:,
      sell_multiplier:,
    ))
  }

  "-- Every row of the vendor table in creature order: one of the two queries the load makes
-- of the vendor tables at start (genesis_prime/content/vendor). The checks run on these
-- rows, not in SQL.
select
  creature_id,
  buy_multiplier,
  sell_multiplier
from vendor
order by creature_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `load_zone_welcomes` query
/// defined in `./src/genesis_prime/content/sql/load_zone_welcomes.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type LoadZoneWelcomesRow {
  LoadZoneWelcomesRow(world_zone_id: Int, tutorial_id: Int)
}

/// Every row of the zone_welcome table in key order: the one query the load makes of
/// the table at start (genesis_prime/content/zone_welcome). The checks run on these
/// rows, not in SQL.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn load_zone_welcomes(
  db: pog.Connection,
) -> Result(pog.Returned(LoadZoneWelcomesRow), pog.QueryError) {
  let decoder = {
    use world_zone_id <- decode.field(0, decode.int)
    use tutorial_id <- decode.field(1, decode.int)
    decode.success(LoadZoneWelcomesRow(world_zone_id:, tutorial_id:))
  }

  "-- Every row of the zone_welcome table in key order: the one query the load makes of
-- the table at start (genesis_prime/content/zone_welcome). The checks run on these
-- rows, not in SQL.
select
  world_zone_id,
  tutorial_id
from zone_welcome
order by world_zone_id;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}
