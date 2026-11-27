//// This module contains the code to run the sql queries defined in
//// `./dev/genesis_prime/import_retail_record/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import pog

/// A row you get from running the `count_auto_attacks` query
/// defined in `./dev/genesis_prime/import_retail_record/sql/count_auto_attacks.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CountAutoAttacksRow {
  CountAutoAttacksRow(inserted: Int, retired: Int, changed: Int, unchanged: Int)
}

/// Stub: counts nothing.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn count_auto_attacks(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
) -> Result(pog.Returned(CountAutoAttacksRow), pog.QueryError) {
  let decoder = {
    use inserted <- decode.field(0, decode.int)
    use retired <- decode.field(1, decode.int)
    use changed <- decode.field(2, decode.int)
    use unchanged <- decode.field(3, decode.int)
    decode.success(CountAutoAttacksRow(
      inserted:,
      retired:,
      changed:,
      unchanged:,
    ))
  }

  "-- Stub: counts nothing.
select (-1)::int as inserted, (-1)::int as retired, (-1)::int as changed, (-1)::int as unchanged
from unnest($1::int[], $2::int[], $3::smallint[]) as t (creature_id, spell4_id, order_index) limit 1;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `count_specials` query
/// defined in `./dev/genesis_prime/import_retail_record/sql/count_specials.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type CountSpecialsRow {
  CountSpecialsRow(inserted: Int, retired: Int, changed: Int, unchanged: Int)
}

/// Stub: counts nothing.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn count_specials(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
) -> Result(pog.Returned(CountSpecialsRow), pog.QueryError) {
  let decoder = {
    use inserted <- decode.field(0, decode.int)
    use retired <- decode.field(1, decode.int)
    use changed <- decode.field(2, decode.int)
    use unchanged <- decode.field(3, decode.int)
    decode.success(CountSpecialsRow(inserted:, retired:, changed:, unchanged:))
  }

  "-- Stub: counts nothing.
select (-1)::int as inserted, (-1)::int as retired, (-1)::int as changed, (-1)::int as unchanged
from unnest($1::int[], $2::int[], $3::smallint[], $4::int[]) as t (creature_id, spell4_id, order_index, cooldown_ms) limit 1;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Stub: writes nothing.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_new_auto_attacks(
  db: pog.Connection,
  arg_1: Int,
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Stub: writes nothing.
insert into creature_auto_attack (creature_id, spell4_id, order_index, source, import_id)
select creature_id, spell4_id, order_index, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[]) as incoming (creature_id, spell4_id, order_index)
where false;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Stub: writes nothing.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_new_specials(
  db: pog.Connection,
  arg_1: Int,
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
  arg_5: List(Int),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Stub: writes nothing.
insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, import_id)
select creature_id, spell4_id, order_index, cooldown_ms, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[], $5::int[]) as incoming (creature_id, spell4_id, order_index, cooldown_ms)
where false;
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

/// Stub: retires nothing.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn retire_stale_auto_attacks(
  db: pog.Connection,
  retired_by_import: Int,
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Stub: retires nothing.
update creature_auto_attack set retired_by_import = $1 where false and $2::int[] is null and $3::int[] is null and $4::smallint[] is null;
"
  |> pog.query
  |> pog.parameter(pog.int(retired_by_import))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Stub: retires nothing.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn retire_stale_specials(
  db: pog.Connection,
  retired_by_import: Int,
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
  arg_5: List(Int),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Stub: retires nothing.
update creature_special set retired_by_import = $1 where false and $2::int[] is null and $3::int[] is null and $4::smallint[] is null and $5::int[] is null;
"
  |> pog.query
  |> pog.parameter(pog.int(retired_by_import))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `spawned_creatures` query
/// defined in `./dev/genesis_prime/import_retail_record/sql/spawned_creatures.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SpawnedCreaturesRow {
  SpawnedCreaturesRow(
    entity_type: Int,
    creature_id: Int,
    world_id: Int,
    area_id: Int,
    spawns: Int,
  )
}

/// Where each creature has spawns: one row for each creature, world, area and unit
/// type, with how many spawn rows stand there. The import chooses the unit types the
/// server fights with in code (genesis_prime/world_map/creature_unit_type).
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn spawned_creatures(
  db: pog.Connection,
) -> Result(pog.Returned(SpawnedCreaturesRow), pog.QueryError) {
  let decoder = {
    use entity_type <- decode.field(0, decode.int)
    use creature_id <- decode.field(1, decode.int)
    use world_id <- decode.field(2, decode.int)
    use area_id <- decode.field(3, decode.int)
    use spawns <- decode.field(4, decode.int)
    decode.success(SpawnedCreaturesRow(
      entity_type:,
      creature_id:,
      world_id:,
      area_id:,
      spawns:,
    ))
  }

  "-- Where each creature has spawns: one row for each creature, world, area and unit
-- type, with how many spawn rows stand there. The import chooses the unit types the
-- server fights with in code (genesis_prime/world_map/creature_unit_type).
select
  entity_type,
  creature_id,
  world_id,
  area_id,
  count(*)::int as spawns
from spawn
group by entity_type, creature_id, world_id, area_id
order by creature_id, world_id, area_id, entity_type;
"
  |> pog.query
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `start_import` query
/// defined in `./dev/genesis_prime/import_retail_record/sql/start_import.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type StartImportRow {
  StartImportRow(id: Int)
}

/// Records a run of the import with the counts the run will make and the SHA-256 of its
/// input, and gives the run's id: `$1` the digest, then the added, retired and kept counts of
/// the auto-attacks and of the specials.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn start_import(
  db: pog.Connection,
  arg_1: String,
  arg_2: Int,
  arg_3: Int,
  arg_4: Int,
  arg_5: Int,
  arg_6: Int,
  arg_7: Int,
) -> Result(pog.Returned(StartImportRow), pog.QueryError) {
  let decoder = {
    use id <- decode.field(0, decode.int)
    decode.success(StartImportRow(id:))
  }

  "-- Records a run of the import with the counts the run will make and the SHA-256 of its
-- input, and gives the run's id: `$1` the digest, then the added, retired and kept counts of
-- the auto-attacks and of the specials.
insert into retail_record_import (
  input_sha256,
  auto_attacks_added, auto_attacks_retired, auto_attacks_kept,
  specials_added, specials_retired, specials_kept
)
values ($1, $2, $3, $4, $5, $6, $7)
returning id;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.int(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.parameter(pog.int(arg_4))
  |> pog.parameter(pog.int(arg_5))
  |> pog.parameter(pog.int(arg_6))
  |> pog.parameter(pog.int(arg_7))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
