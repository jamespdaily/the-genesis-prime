//// The creature_faction table's load and checks (`genesis_prime/content/creature_faction`,
//// `genesis_prime/world_map/creature_faction`), on the client's committed rows and a
//// migrated database. Expected values come from these places.
//// - Creature2 73499, the tutorial boss, gives faction 219, which is Friendly to both
////   player factions; Faction2Relationship 746 makes faction 233 Hostile to faction 165,
////   the parent of both, at level 0. The chosen faction of the boss is 233.
//// - Creature2 holds no row 5006 (the objective_spawn_test header, QuestObjective 1889)
////   and Faction2 holds no row 16000; the 0x262 faction field is 14 bits
////   (opcode.0x262), so 16000 would fit the message and still be a faction the client
////   does not have.
//// - Migration 0009's pattern: a source other than the world database states its
////   reason, in a constraint of its own (creature_kind_other_source_states_its_reason).

import content_support
import database_support
import fixture_tables
import genesis_prime/content/creature_faction as content_creature_faction
import genesis_prime/content/refusal.{Refusal, RowId}
import genesis_prime/world_map/creature_faction.{Row}
import gleam/dict
import gleam/string
import owned_test

/// The selection of the rows against the client's rows.
fn selected(
  rows rows: List(creature_faction.Row),
) -> Result(creature_faction.Factions, List(refusal.Refusal)) {
  creature_faction.select(rows:, tables: fixture_tables.shared())
}

/// The rows of the creature_faction table of a migrated database of the test's own.
fn rows_of_a_migrated_database(
  database database: String,
) -> List(creature_faction.Row) {
  let assert Ok(rows) =
    content_creature_faction.rows(db: content_support.connect(database:))
    as "the query ran"
  rows
}

pub fn the_faction_rows_load_into_their_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(factions) =
    selected(rows: rows_of_a_migrated_database(database:))
    as "the migrated rows are rows of the client's Creature2 and Faction2 tables"
  assert creature_faction.chosen_of(factions:, creature2_id: 73_499) == Ok(233)
    as "Faction2Relationship 746 makes 233 hostile to both player factions' parent, which the boss's own 219 is not"
  assert creature_faction.chosen_of(factions:, creature2_id: 73_464)
    == Error(Nil)
    as "a creature with no row has no chosen faction"
  assert creature_faction.chosen_of(factions:, creature2_id: 73_494) == Ok(1441)
    as "the Exile Sim-Turret fights for 1441, which Faction2Relationship 2943 makes hostile to Exiles"
  assert creature_faction.chosen_of(factions:, creature2_id: 74_862) == Ok(1442)
    as "the Dominion Sim-Turret fights for 1442, which Faction2Relationship 2946 makes hostile to Dominion"
  assert dict.size(factions.by_creature) == 3
    as "the migration seeds the boss and the two Sim-Turrets and nothing else"
}

pub fn a_faction_row_of_a_creature_the_client_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([Refusal(table: "creature_faction", row: RowId(5006), rule:)]) =
    selected(rows: [Row(creature_id: 5006, faction_id: 233)])
    as "Creature2 holds no row 5006"
  assert string.contains(rule, "Creature2")
    as "the refusal names the table the creature is missing from"
}

pub fn a_faction_the_client_lacks_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error([
    Refusal(table: "creature_faction", row: RowId(73_499), rule:),
  ]) = selected(rows: [Row(creature_id: 73_499, faction_id: 16_000)])
    as "Faction2 holds no row 16000"
  assert string.contains(rule, "16000")
    as "the refusal names the faction the client lacks"
}

pub fn a_server_choice_row_without_a_reason_is_refused_by_the_database_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Error(failed) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: [
        "-c",
        "insert into creature_faction (creature_id, faction_id, source) values (73464, 233, 'server_choice')",
      ],
    )
    as "the database refuses a server choice with no reason"
  assert string.contains(
    failed.output,
    "creature_faction_other_source_states_its_reason",
  )
    as "the refusal names its constraint"
}
