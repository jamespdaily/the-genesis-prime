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

/// Compares the retail-record rows of `creature_auto_attack` with the rows the import
/// would write (`$1` to the last parameter are the columns of those rows, in the
/// order of the table's columns): how many of the rows are new, how many are the
/// same row of a creature and spell with another order, how many are the same, and
/// how many rows of the table the import would no longer write, which a run retires.
/// A row is the same when its creature, spell and order are. Rows of any other
/// source and rows a run has retired are not counted.
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

  "-- Compares the retail-record rows of `creature_auto_attack` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another order, how many are the same, and
-- how many rows of the table the import would no longer write, which a run retires.
-- A row is the same when its creature, spell and order are. Rows of any other
-- source and rows a run has retired are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[])
    as t (creature_id, spell4_id, order_index)
),
existing as (
  select creature_id, spell4_id, order_index
  from creature_auto_attack
  where source = 'retail_record' and retired_by_import is null
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as retired,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and existing.order_index is distinct from incoming.order_index
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and existing.order_index is not distinct from incoming.order_index
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

/// Compares the retail-record rows of `creature_special` with the rows the import
/// would write (`$1` to the last parameter are the columns of those rows, in the
/// order of the table's columns): how many of the rows are new, how many are the
/// same row of a creature and spell with another order and cooldown, how many are the same, and
/// how many rows of the table the import would no longer write, which a run retires.
/// A row is the same when its creature, spell, order and cooldown are. Rows of any other
/// source and rows a run has retired are not counted.
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

  "-- Compares the retail-record rows of `creature_special` with the rows the import
-- would write (`$1` to the last parameter are the columns of those rows, in the
-- order of the table's columns): how many of the rows are new, how many are the
-- same row of a creature and spell with another order and cooldown, how many are the same, and
-- how many rows of the table the import would no longer write, which a run retires.
-- A row is the same when its creature, spell, order and cooldown are. Rows of any other
-- source and rows a run has retired are not counted.
with incoming as (
  select * from unnest($1::int[], $2::int[], $3::smallint[], $4::int[])
    as t (creature_id, spell4_id, order_index, cooldown_ms)
),
existing as (
  select creature_id, spell4_id, order_index, cooldown_ms
  from creature_special
  where source = 'retail_record' and retired_by_import is null
)
select
  (count(*) filter (where existing.creature_id is null))::int as inserted,
  (count(*) filter (where incoming.creature_id is null))::int as retired,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.cooldown_ms) is distinct from (incoming.order_index, incoming.cooldown_ms)
  ))::int as changed,
  (count(*) filter (
    where existing.creature_id is not null
      and incoming.creature_id is not null
      and (existing.order_index, existing.cooldown_ms) is not distinct from (incoming.order_index, incoming.cooldown_ms)
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
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Writes the rows the import wants (`$1` is the run that writes them, `$2` to the last
/// parameter their columns) that the table has no unretired retail-record row for, as
/// retail-record rows with no source row. A row of another source with the same creature and
/// spell, or the same place in the creature's list, is refused by the table's own keys.
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

  "-- Writes the rows the import wants (`$1` is the run that writes them, `$2` to the last
-- parameter their columns) that the table has no unretired retail-record row for, as
-- retail-record rows with no source row. A row of another source with the same creature and
-- spell, or the same place in the creature's list, is refused by the table's own keys.
insert into creature_auto_attack (creature_id, spell4_id, order_index, source, import_id)
select creature_id, spell4_id, order_index, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[])
  as incoming (creature_id, spell4_id, order_index)
where not exists (
  select 1
  from creature_auto_attack as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
    and existing.retired_by_import is null
);
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Writes the rows the import wants (`$1` is the run that writes them, `$2` to the last
/// parameter their columns) that the table has no unretired retail-record row for, as
/// retail-record rows with no source row. A row of another source with the same creature and
/// spell, or the same place in the creature's list, is refused by the table's own keys.
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

  "-- Writes the rows the import wants (`$1` is the run that writes them, `$2` to the last
-- parameter their columns) that the table has no unretired retail-record row for, as
-- retail-record rows with no source row. A row of another source with the same creature and
-- spell, or the same place in the creature's list, is refused by the table's own keys.
insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source, import_id)
select creature_id, spell4_id, order_index, cooldown_ms, 'retail_record', $1
from unnest($2::int[], $3::int[], $4::smallint[], $5::int[])
  as incoming (creature_id, spell4_id, order_index, cooldown_ms)
where not exists (
  select 1
  from creature_special as existing
  where existing.creature_id = incoming.creature_id
    and existing.spell4_id = incoming.spell4_id
    and existing.source = 'retail_record'
    and existing.retired_by_import is null
);
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

/// Retires the retail-record rows of `creature_auto_attack` that no run has retired and that
/// are not one of the rows the import would write, whole (`$1` is the run that retires them;
/// `$2` to the last parameter are the columns of the rows to write). Rows of any other
/// source are left alone.
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

  "-- Retires the retail-record rows of `creature_auto_attack` that no run has retired and that
-- are not one of the rows the import would write, whole (`$1` is the run that retires them;
-- `$2` to the last parameter are the columns of the rows to write). Rows of any other
-- source are left alone.
update creature_auto_attack
set retired_by_import = $1
where source = 'retail_record'
  and retired_by_import is null
  and not exists (
    select 1
    from unnest($2::int[], $3::int[], $4::smallint[])
      as incoming (creature_id, spell4_id, order_index)
    where incoming.creature_id = creature_auto_attack.creature_id
      and incoming.spell4_id = creature_auto_attack.spell4_id
      and incoming.order_index = creature_auto_attack.order_index
  );
"
  |> pog.query
  |> pog.parameter(pog.int(retired_by_import))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Retires the retail-record rows of `creature_special` that no run has retired and that
/// are not one of the rows the import would write, whole (`$1` is the run that retires them;
/// `$2` to the last parameter are the columns of the rows to write). Rows of any other
/// source are left alone.
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

  "-- Retires the retail-record rows of `creature_special` that no run has retired and that
-- are not one of the rows the import would write, whole (`$1` is the run that retires them;
-- `$2` to the last parameter are the columns of the rows to write). Rows of any other
-- source are left alone.
update creature_special
set retired_by_import = $1
where source = 'retail_record'
  and retired_by_import is null
  and not exists (
    select 1
    from unnest($2::int[], $3::int[], $4::smallint[], $5::int[])
      as incoming (creature_id, spell4_id, order_index, cooldown_ms)
    where incoming.creature_id = creature_special.creature_id
      and incoming.spell4_id = creature_special.spell4_id
      and incoming.order_index = creature_special.order_index
      and incoming.cooldown_ms = creature_special.cooldown_ms
  );
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
/// server fights with in code (genesis_prime/shared/creature_unit_type).
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
-- server fights with in code (genesis_prime/shared/creature_unit_type).
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
