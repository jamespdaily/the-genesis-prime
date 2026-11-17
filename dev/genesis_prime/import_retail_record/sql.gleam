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
  CountAutoAttacksRow(inserted: Int, removed: Int, changed: Int, unchanged: Int)
}

/// Compares the retail-record rows of `creature_auto_attack` with the rows the import
/// would write (`$1` to the last parameter are the columns of those rows, in the
/// order of the table's columns): how many of the rows are new, how many are the
/// same row of a creature and spell with another value, how many are the same, and
/// how many rows of the table the import would no longer write. Rows of any other
/// source are not counted.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn count_auto_attacks(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(String),
) -> Result(pog.Returned(CountAutoAttacksRow), pog.QueryError) {
  let decoder = {
    use inserted <- decode.field(0, decode.int)
    use removed <- decode.field(1, decode.int)
    use changed <- decode.field(2, decode.int)
    use unchanged <- decode.field(3, decode.int)
    decode.success(CountAutoAttacksRow(
      inserted:,
      removed:,
      changed:,
      unchanged:,
    ))
  }

  "-- Compares the retail-record rows of `creature_auto_attack` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another value, how many are the same, and
-- how many rows of the table the import would no longer write. Rows of any other
-- source are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[], $4::text[])
    as t (creature_id, spell4_id, order_index, reason)
),
existing as (
  select creature_id, spell4_id, order_index, reason
  from creature_auto_attack
  where source = 'retail_record'
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as removed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.reason) is distinct from (incoming.order_index, incoming.reason)
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.reason) is not distinct from (incoming.order_index, incoming.reason)
  ))::int as unchanged
from incoming
full join existing
  on existing.creature_id = incoming.creature_id
  and existing.spell4_id = incoming.spell4_id;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_4))
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
  CountSpecialsRow(inserted: Int, removed: Int, changed: Int, unchanged: Int)
}

/// Compares the retail-record rows of `creature_special` with the rows the import
/// would write (`$1` to the last parameter are the columns of those rows, in the
/// order of the table's columns): how many of the rows are new, how many are the
/// same row of a creature and spell with another value, how many are the same, and
/// how many rows of the table the import would no longer write. Rows of any other
/// source are not counted.
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
  arg_5: List(String),
) -> Result(pog.Returned(CountSpecialsRow), pog.QueryError) {
  let decoder = {
    use inserted <- decode.field(0, decode.int)
    use removed <- decode.field(1, decode.int)
    use changed <- decode.field(2, decode.int)
    use unchanged <- decode.field(3, decode.int)
    decode.success(CountSpecialsRow(inserted:, removed:, changed:, unchanged:))
  }

  "-- Compares the retail-record rows of `creature_special` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another value, how many are the same, and
-- how many rows of the table the import would no longer write. Rows of any other
-- source are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[], $4::int[], $5::text[])
    as t (creature_id, spell4_id, order_index, cooldown_ms, reason)
),
existing as (
  select creature_id, spell4_id, order_index, cooldown_ms, reason
  from creature_special
  where source = 'retail_record'
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as removed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.cooldown_ms, existing.reason) is distinct from (incoming.order_index, incoming.cooldown_ms, incoming.reason)
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.cooldown_ms, existing.reason) is not distinct from (incoming.order_index, incoming.cooldown_ms, incoming.reason)
  ))::int as unchanged
from incoming
full join existing
  on existing.creature_id = incoming.creature_id
  and existing.spell4_id = incoming.spell4_id;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Deletes the retail-record rows of `creature_auto_attack` that are not one of the rows the
/// import would write, whole (`$1` to the last parameter are the columns of those
/// rows). Rows of any other source are left alone.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_stale_auto_attacks(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(String),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Deletes the retail-record rows of `creature_auto_attack` that are not one of the rows the
-- import would write, whole (`$1` to the last parameter are the columns of those
-- rows). Rows of any other source are left alone.
delete from creature_auto_attack
where source = 'retail_record'
  and not exists (
    select 1
    from unnest($1::int[], $2::int[], $3::smallint[], $4::text[])
      as incoming (creature_id, spell4_id, order_index, reason)
    where incoming.creature_id = creature_auto_attack.creature_id
      and incoming.spell4_id = creature_auto_attack.spell4_id
      and incoming.order_index = creature_auto_attack.order_index
      and incoming.reason = creature_auto_attack.reason
  );
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Deletes the retail-record rows of `creature_special` that are not one of the rows the
/// import would write, whole (`$1` to the last parameter are the columns of those
/// rows). Rows of any other source are left alone.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_stale_specials(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
  arg_5: List(String),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Deletes the retail-record rows of `creature_special` that are not one of the rows the
-- import would write, whole (`$1` to the last parameter are the columns of those
-- rows). Rows of any other source are left alone.
delete from creature_special
where source = 'retail_record'
  and not exists (
    select 1
    from unnest($1::int[], $2::int[], $3::smallint[], $4::int[], $5::text[])
      as incoming (creature_id, spell4_id, order_index, cooldown_ms, reason)
    where incoming.creature_id = creature_special.creature_id
      and incoming.spell4_id = creature_special.spell4_id
      and incoming.order_index = creature_special.order_index
      and incoming.cooldown_ms = creature_special.cooldown_ms
      and incoming.reason = creature_special.reason
  );
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_5))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Writes the rows the import wants (`$1` to the last parameter are their columns)
/// that the table has no retail-record row for, as retail-record rows with no source
/// row. A row of another source with the same creature and spell, or the same place in
/// the creature's list, is refused by the table's own keys.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_new_auto_attacks(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(String),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Writes the rows the import wants (`$1` to the last parameter are their columns)
-- that the table has no retail-record row for, as retail-record rows with no source
-- row. A row of another source with the same creature and spell, or the same place in
-- the creature's list, is refused by the table's own keys.
insert into creature_auto_attack (creature_id, spell4_id, order_index, source, reason)
select creature_id, spell4_id, order_index, 'retail_record', reason
from unnest($1::int[], $2::int[], $3::smallint[], $4::text[])
  as incoming (creature_id, spell4_id, order_index, reason)
where not exists (
  select 1
  from creature_auto_attack as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
);
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Writes the rows the import wants (`$1` to the last parameter are their columns)
/// that the table has no retail-record row for, as retail-record rows with no source
/// row. A row of another source with the same creature and spell, or the same place in
/// the creature's list, is refused by the table's own keys.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn insert_new_specials(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
  arg_5: List(String),
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Writes the rows the import wants (`$1` to the last parameter are their columns)
-- that the table has no retail-record row for, as retail-record rows with no source
-- row. A row of another source with the same creature and spell, or the same place in
-- the creature's list, is refused by the table's own keys.
insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, reason)
select creature_id, spell4_id, order_index, cooldown_ms, 'retail_record', reason
from unnest($1::int[], $2::int[], $3::smallint[], $4::int[], $5::text[])
  as incoming (creature_id, spell4_id, order_index, cooldown_ms, reason)
where not exists (
  select 1
  from creature_special as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
);
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.text(value) }, arg_5))
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
