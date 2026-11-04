//// The creature_kind table's checks (`genesis_prime/world_map/creature_kind`), on
//// planted Creature2 rows. Expected values come from these places.
//// - Migration 0009 and the shared pattern of the content tables
////   (`genesis_prime/content`): row 0 is the default every creature without a row
////   takes, a table without it stops the start, a row for a Creature2 id the
////   client does not hold or a respawn time below 1 is refused, and every refusal
////   is collected and named by its table, its id and its rule.
//// - A respawn time below the strike deadline (1000 ms) is refused: a creature that
////   stood again before the round it was struck in closed could take that round's
////   held news (`genesis_prime/game/strike_tell.deadline_ms`).
//// - The default is 60 000 ms, a server choice: the client holds no respawn time
////   (`death.creature_respawn`).
//// - The Virtual Battle Beast is Creature2 73464 (`Creature2.73464`).
//// - The attack (migration 0010): Spell4 5649, the auto-attack whose two damage
////   effects carry caster prerequisites of type 179, the difficulty
////   (`Spell4Effects.184741`, `0x14049eeb0`), every 1500 ms, a server choice; an
////   interval below the strike deadline would open a second strike round while
////   the first waits.

import character_tables
import content_support
import database_support
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal.{Refusal, RowId}
import genesis_prime/game/strike_tell
import genesis_prime/table/creature2
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/creature_kind.{Kind, Kinds, Row}
import gleam/dict
import gleam/list
import gleam/string
import novice_tables
import owned_key
import owned_test
import planted_table.{Integer}

/// The planted Creature2 table with the Virtual Battle Beast and the client's rows
/// of its attack spell 5649 (Spell4, its two damage effects and their
/// prerequisites), with `prerequisites` in place of the client's, loaded for the body.
fn with_beast(
  prerequisites prerequisites: List(List(planted_table.Cell)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  use folder <- planted_table.in_folder([
    planted_table.file(creature2.schema, [
      planted_table.row(creature2.schema, [#("ID", Integer(73_464))]),
    ]),
    planted_table.file(
      spell4.schema,
      novice_tables.creature_attack_spell4_rows(),
    ),
    planted_table.file(
      spell4_effects.schema,
      novice_tables.creature_attack_effect_rows(),
    ),
    planted_table.file(prerequisite.schema, prerequisites),
  ])
  let assert Ok(tables) =
    table_store.load(
      under: owned_key.new(),
      from: folder,
      entries: [
        creature2.entry(),
        spell4.entry(),
        spell4_effects.entry(),
        prerequisite.entry(),
      ],
      requirements: [],
      derivations: [],
    )
    as "the planted tables load"
  let result = body(tables)
  table_store.unload(tables)
  result
}

fn selected(
  rows rows: List(creature_kind.Row),
) -> Result(creature_kind.Kinds, List(refusal.Refusal)) {
  with_beast(
    prerequisites: character_tables.prerequisite_rows(),
    body: fn(tables) { creature_kind.select(rows:, tables:) },
  )
}

/// The default row, as migration 0010 leaves it.
const default_row =
  Row(
    creature_id: 0,
    respawn_ms: 60_000,
    attack_spell4_id: 5649,
    attack_interval_ms: 1500,
  )

pub fn an_attack_interval_below_the_strike_deadline_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_kind", row: RowId(73_464), rule:)]) =
    selected(rows: [
      default_row,
      Row(..default_row, creature_id: 73_464, attack_interval_ms: 999),
    ])
    as "an interval of 999 ms would start a strike round while the last waits for its 1000 ms deadline"
  assert string.contains(rule, "999") && string.contains(rule, "1000")
    as "the refusal names the interval and the deadline"
  let assert Ok(_) =
    selected(rows: [
      default_row,
      Row(..default_row, creature_id: 73_464, attack_interval_ms: 1000),
    ])
    as "an interval of the deadline itself is taken"
  Nil
}

pub fn an_attack_spell_the_client_does_not_hold_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_kind", row: RowId(73_464), rule:)]) =
    selected(rows: [
      default_row,
      Row(..default_row, creature_id: 73_464, attack_spell4_id: 5650),
    ])
    as "the planted Spell4 holds 5649 alone"
  assert string.contains(rule, "5650") as "the refusal names the spell"
}

pub fn an_attack_effect_whose_caster_prerequisite_the_server_does_not_evaluate_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let other_type =
    list.map(character_tables.prerequisite_rows(), fn(row) {
      case row {
        [Integer(30_527), ..] ->
          planted_table.row(prerequisite.schema, [
            #("ID", Integer(30_527)),
            #("prerequisiteTypeId0", Integer(180)),
            #("prerequisiteComparisonId0", Integer(4)),
            #("objectId0", Integer(7)),
          ])
        _ -> row
      }
    })
  let assert Error([Refusal(table: "creature_kind", row: RowId(0), rule:)]) =
    with_beast(prerequisites: other_type, body: fn(tables) {
      creature_kind.select(rows: [default_row], tables:)
    })
    as "effect 184777's prerequisite 30527 is of type 180: the server would apply it to every creature or none (0x14049eeb0 evaluates type 179 only), so the start stops"
  assert string.contains(rule, "184777") && string.contains(rule, "180")
    as "the refusal names the effect and the type"
}

pub fn planted_rows_load_into_the_kinds_a_creature_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(kinds) =
    selected(rows: [
      Row(
        creature_id: 0,
        respawn_ms: 60_000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
      Row(
        creature_id: 73_464,
        respawn_ms: 5000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
  assert kinds
    == Kinds(
      default: Kind(
        respawn_ms: 60_000,
        attack_spell4_id: Spell4Id(5649),
        attack_interval_ms: 1500,
      ),
      by_creature: dict.from_list([
        #(
          73_464,
          Kind(
            respawn_ms: 5000,
            attack_spell4_id: Spell4Id(5649),
            attack_interval_ms: 1500,
          ),
        ),
      ]),
    )
  assert creature_kind.kind_of(kinds:, creature2_id: 73_464)
    == Kind(
      respawn_ms: 5000,
      attack_spell4_id: Spell4Id(5649),
      attack_interval_ms: 1500,
    )
    as "a creature with a row of its own takes it"
  assert creature_kind.kind_of(kinds:, creature2_id: 73_465)
    == Kind(
      respawn_ms: 60_000,
      attack_spell4_id: Spell4Id(5649),
      attack_interval_ms: 1500,
    )
    as "any other creature takes the default row 0"
}

pub fn a_table_with_no_default_row_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_kind", row: RowId(0), rule:)]) =
    selected(rows: [
      Row(
        creature_id: 73_464,
        respawn_ms: 5000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
    as "the start stops: a creature must always have a kind"
  assert rule != "" as "the refusal says which rule"
}

pub fn a_row_for_a_creature_the_client_does_not_hold_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_kind", row: RowId(99), ..)]) =
    selected(rows: [
      Row(
        creature_id: 0,
        respawn_ms: 60_000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
      Row(
        creature_id: 99,
        respawn_ms: 5000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
    as "Creature2 99 has no row in the client's table"
  Nil
}

pub fn a_respawn_time_below_one_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_kind", row: RowId(73_464), ..)]) =
    selected(rows: [
      Row(
        creature_id: 0,
        respawn_ms: 60_000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
      Row(
        creature_id: 73_464,
        respawn_ms: 0,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
    as "a creature that respawns in no time has no corpse: migration 0009 refuses it too"
  Nil
}

pub fn a_respawn_time_below_the_strike_deadline_is_refused_by_name_and_the_deadline_itself_is_taken_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_kind", row: RowId(73_464), rule:)]) =
    selected(rows: [
      Row(
        creature_id: 0,
        respawn_ms: 60_000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
      Row(
        creature_id: 73_464,
        respawn_ms: strike_tell.deadline_ms - 1,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
    as "a creature that stands again before the round it was struck in has closed would take the held news of its earlier unit"
  assert string.contains(rule, "1000")
    as "the refusal names the strike deadline, 1000 ms"
  let assert Ok(_) =
    selected(rows: [
      Row(
        creature_id: 0,
        respawn_ms: 60_000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
      Row(
        creature_id: 73_464,
        respawn_ms: strike_tell.deadline_ms,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
    as "a respawn time of the deadline itself is taken"
  Nil
}

pub fn every_refused_row_is_collected_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(refusals) =
    selected(rows: [
      Row(
        creature_id: 99,
        respawn_ms: 5000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
      Row(
        creature_id: 73_464,
        respawn_ms: -1,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ])
  assert list.map(refusals, fn(refused) { refused.row })
    == [RowId(0), RowId(99), RowId(73_464)]
    as "one bad row shows its neighbours: the missing default, the unknown creature and the bad time, in id order"
}

/// The rows of the creature_kind table of a migrated database of the test's own.
fn rows_of_a_migrated_database(
  database database: String,
) -> List(creature_kind.Row) {
  let assert Ok(rows) =
    content_creature_kind.rows(db: content_support.connect(database:))
    as "the query ran"
  rows
}

pub fn a_migrated_database_holds_the_60_second_default_row_and_nothing_else_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  assert rows_of_a_migrated_database(database:)
    == [
      Row(
        creature_id: 0,
        respawn_ms: 60_000,
        attack_spell4_id: 5649,
        attack_interval_ms: 1500,
      ),
    ]
    as "migration 0009 seeds row 0, the server's choice of 60 000 ms"
  assert content_support.psql(
      database:,
      sql: "select source || ': ' || reason from creature_kind where creature_id = 0",
    )
    == "server_choice: no table holds a respawn time for a creature (death.creature_respawn); attack: no client link (Spell4.5649), interval a server choice"
    as "a server choice states its reason (death.creature_respawn, Spell4.5649)"
}

pub fn the_database_refuses_each_bad_row_under_its_own_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 0, 5649, 1500, 'server_choice', 'x')",
        "creature_kind_respawn_ms_is_positive",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source) values (73464, 5000, 5649, 1500, 'server_choice')",
        "creature_kind_other_source_states_its_reason",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 5649, 1500, 'server_choice', '  ')",
        "creature_kind_reason_says_something",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, source_row) values (73464, 5000, 5649, 1500, 'world_database', null)",
        "creature_kind_world_database_row_has_a_source_row",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, source_row) values (73464, 5000, 5649, 1500, 'world_database', 1), (73465, 5000, 5649, 1500, 'world_database', 1)",
        "creature_kind_source_row_is_unique",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, source_row) values (73464, 5000, 5649, 1500, 'world_database', 0)",
        "creature_kind_source_row_is_positive",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (0, 5000, 5649, 1500, 'server_choice', 'x')",
        "creature_kind_pkey",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (262144, 5000, 5649, 1500, 'server_choice', 'x')",
        "creature_kind_creature_id_is_in_18_bits",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 5649, 1500, 'nobody', 'x')",
        "creature_kind_source_is_a_content_source",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 0, 1500, 'server_choice', 'x')",
        "creature_kind_attack_spell4_id_is_positive",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 5649, 0, 'server_choice', 'x')",
        "creature_kind_attack_interval_ms_is_positive",
      ),
      #(
        "insert into creature_kind (creature_id, respawn_ms, source, reason) values (73464, 5000, 'server_choice', 'x')",
        "attack_spell4_id",
      ),
    ],
    fn(bad) {
      let assert Error(failed) =
        database_support.psql(
          with: database_support.settings(),
          database:,
          arguments: ["-c", bad.0],
        )
        as "the database refuses the row"
      assert string.contains(failed.output, bad.1)
        as "the refusal names its constraint"
    },
  )
}

pub fn planted_kinds_put_under_a_key_are_read_back_test() -> Nil {
  use <- owned_test.run(60_000)
  let key = owned_key.new_key()
  let kinds =
    Kinds(
      default: Kind(
        respawn_ms: 60_000,
        attack_spell4_id: Spell4Id(5649),
        attack_interval_ms: 1500,
      ),
      by_creature: dict.from_list([
        #(
          73_464,
          Kind(
            respawn_ms: 5000,
            attack_spell4_id: Spell4Id(5649),
            attack_interval_ms: 1500,
          ),
        ),
      ]),
    )
  content_creature_kind.put(key:, kinds:)
  assert content_creature_kind.kinds(key:) == kinds
    as "one term for the whole table, put once"
  assert content_creature_kind.table == "creature_kind"
  owned_key.erase(key)
}
