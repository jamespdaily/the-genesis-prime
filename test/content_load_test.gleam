//// The content load at start (`genesis_prime/content`), run on databases of the
//// test's own. Expected values come from these places.
//// - The design of the world spawns (the Design artifact of issue 375, sections 1
////   and 6): the load waits for the database as readiness does and the tree
////   starts after it; a database whose migrations differ stops the start with the
////   difference; a refused row stops the start with the reason, and every refusal
////   of every table is logged first, so two bad rows are both named by table, id
////   and rule; a failed query stops the start with the database's reason.
//// - The migrations' own refusals are those of `genesis_prime/migration` (the
////   sentences `migration_start_test` pins).
//// - The 27 Virtual Defense Daguns are server-choice rows of migration 0008, so a
////   migrated database holds them and the load puts them in World 3460's term.
//// The waits are the load's own settings, shortened here, so no test waits 30 s.

import character_tables
import content_support
import database_support
import genesis_prime/connection/frame.{Frame}
import genesis_prime/content
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/refusal.{Refusal}
import genesis_prime/content/server_proxy as content_server_proxy
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/zone_welcome as content_zone_welcome
import genesis_prime/game/class_resource
import genesis_prime/game/spell_plan
import genesis_prime/game/zone_welcome
import genesis_prime/migration
import genesis_prime/readiness
import genesis_prime/table/id.{ClassId, Creature2Id}
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/spawn
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import log_capture
import mailbox_support
import owned_test
import server_proxy_support
import unitest

/// A spawn row of a creature the client has no row for, as the world database's
/// row `row`.
fn bad_row(row row: Int, creature creature: Int) -> String {
  "insert into spawn (source, source_row, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, active_prop_id, world_socket_id) values ('world_database', "
  <> int.to_string(row)
  <> ", 0, "
  <> int.to_string(creature)
  <> ", 3460, 0, 0, 0, 0, 0, 0, 0, 26565, 0, 1441, 1441, 0, 0)"
}

/// How many of the spawns stand a creature of this Creature2 id.
fn count_of(
  spawns spawns: dict.Dict(a, spawn.Spawn),
  creature creature: Int,
) -> Int {
  list.count(dict.values(spawns), fn(one) {
    one.creature_id == Creature2Id(creature)
  })
}

pub fn the_load_puts_the_migrated_databases_spawns_in_the_worlds_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil) as "a migrated database loads"
  let world = content_spawn.world(key:, world_id: 3460)
  assert dict.size(world.by_id) == 27 + 11
    as "migration 0008's 27 Virtual Defense Daguns, and the 11 creatures that start of the ones the fixture's kill objectives with a marker in World 3460 place"
  assert count_of(spawns: world.by_id, creature: 73_465) == 27
    as "the 27 Virtual Defense Daguns are the stored spawns the template holds"
  assert list.map([73_492, 73_567, 73_473, 73_566], fn(creature) {
      count_of(spawns: world.by_id, creature:)
    })
    == [2, 1, 2, 1]
    as "objective 21290's group 14356 (73492, 73567, 73492) and objective 21317's group 14402 (73473, 73566, 73473) place 3 each, alternating the group's creatures; objective 21296 and 21310's boss 73499 and objective 21316's 74862 are Friendly to both player factions with no quest, so they are left out"
  assert count_of(spawns: world.by_id, creature: 73_464) == 5
    as "objective 21286 (quest 10518) counts 5 of Creature2 73464, which stands 5 times"
  assert dict.size(content_spawn.world(key:, world_id: 22).by_id) == 0
    as "a World row with no spawn that starts has an empty term"
}

pub fn the_load_puts_the_kinds_in_a_term_the_default_row_is_the_60_second_choice_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (73464, 5000, 5649, 1500, 'server_choice', 'a short respawn for the training Beast')",
  )
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let kinds = content_creature_kind.kinds(key:)
  assert creature_kind.kind_of(kinds:, creature2_id: 73_464).respawn_ms == 5000
    as "a creature with a row of its own takes it"
  assert creature_kind.kind_of(kinds:, creature2_id: 73_465).respawn_ms
    == 60_000
    as "any other creature takes the default row of migration 0009 (death.creature_respawn)"
}

pub fn a_database_with_no_default_kind_stops_the_load_naming_the_table_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from creature_kind where creature_id = 0",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "no default row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("creature_kind", refusal.RowId(0))]
}

pub fn a_kind_row_for_a_creature_the_client_does_not_hold_stops_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (200001, 5000, 5649, 1500, 'server_choice', 'a creature the client does not hold')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a refused kind row stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("creature_kind", refusal.RowId(200_001))]
}

pub fn a_refused_kind_row_does_not_hide_a_refused_spawn_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source, reason) values (200001, 5000, 5649, 1500, 'server_choice', 'a creature the client does not hold')",
  )
  content_support.change(database:, sql: bad_row(row: 1, creature: 200_002))
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "the refused rows stop the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.rule) })
    == [
      #("spawn", "Creature2 200002 has no row"),
      #("creature_kind", "the client's Creature2 table has no such creature"),
    ]
    as "the spawns are checked with the kinds the load took, so one start names both bad rows"
}

pub fn a_database_that_answers_late_is_waited_for_and_loaded_from_test() -> Nil {
  use <- owned_test.run(60_000)
  // The probe finds the database away for its first five asks, as a database that
  // is still starting is, and then asks the pool: no wall-clock wait, and a
  // window of 100 ms that passes with no answer, which the load warns about and
  // asks again after.
  let database = database_support.new_database(on: database_support.shared())
  let away = process.new_subject()
  list.each(list.repeat(Nil, 5), fn(_) { process.send(away, Nil) })
  let #(loaded, key) =
    content_support.load_asking(
      database:,
      ask: readiness.Settings(within_ms: 100, attempt_ms: 500, pause_ms: 50),
      probe: fn(db) {
        fn(reply) {
          case process.receive(away, within: 0) {
            Ok(Nil) -> Error(Nil)
            Error(Nil) -> content.pool_probe(db)(reply)
          }
        }
      },
    )
  assert loaded == Ok(Nil)
    as "the load asked again until the database answered, and then loaded it"
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(away, within: 0) == Error(Nil)
    as "it was told five times that the database was away"
  assert dict.size(content_spawn.world(key:, world_id: 3460).by_id) == 27 + 11
    as "the 27 stored spawns and the 11 marker-placed ones that start"
}

pub fn a_database_whose_migrations_differ_stops_the_load_with_the_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from schema_migration where name = '0008_spawn'",
  )
  let #(loaded, _key) = content_support.load(database:)
  assert loaded
    == Error(content.MigrationsDiffer(migration.NotApplied(name: "0008_spawn")))
    as "the database has not run the migration 0008_spawn"
}

pub fn two_refused_rows_are_both_logged_with_table_id_and_rule_and_stop_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(database:, sql: bad_row(row: 1, creature: 200_001))
  content_support.change(database:, sql: bad_row(row: 2, creature: 200_002))
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let #(loaded, _key) = content_support.load(database:)
  log_capture.stop(capture)
  let assert Error(content.Refused(refusals:)) = loaded
    as "bad rows stop the load"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.rule) })
    == [
      #("spawn", "Creature2 200001 has no row"),
      #("spawn", "Creature2 200002 has no row"),
    ]
    as "both rows are refused, each naming the table and the rule: one bad row shows its neighbours"
  assert list.all(refusals, fn(refused) {
    case refused.row {
      refusal.RowId(id:) -> id > 0
      refusal.RowName(..) -> False
    }
  })
  let logged =
    mailbox_support.drain(lines)
    |> list.map(fn(line) { line.1 })
    |> list.filter(string.contains(_, "is refused"))
  assert list.length(logged) == 2
    && list.all(refusals, fn(refused) {
      list.contains(logged, refusal.describe(refused))
    })
    as "every refusal is logged before the start stops"
  assert refusal.describe(Refusal(
      table: "spawn",
      row: refusal.RowId(5),
      rule: "a rule",
    ))
    == "the table spawn row 5 is refused: a rule"
}

pub fn a_query_that_fails_stops_the_load_with_the_databases_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "alter table spawn rename column x to east",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.QueryFailed(table: "spawn", reason:)) = loaded
    as "a failed query stops the load"
  assert string.contains(reason, "undefined_column")
    as { "the database's reason is named: " <> reason }
}

pub fn a_missing_and_an_unknown_game_number_stop_the_load_each_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from game_number where name = 'leash_range'",
  )
  // The table refuses a name nobody listed, so the name is listed first (a new
  // name is one insert, migration 0014); the server still has no use for it.
  content_support.change(
    database:,
    sql: "insert into game_number_name (name, unit) values ('evade_range', 'units')",
  )
  content_support.change(
    database:,
    sql: "insert into game_number (name, value, unit, source, reason) values ('evade_range', 30, 'units', 'server_choice', 'a number the server has no use for')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a game number the server does not know, or one it reads and does not find, stops the start (the design of step F, section 2)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("game_number", refusal.RowName("evade_range")),
      #("game_number", refusal.RowName("leash_range")),
    ]
    as "each refusal names the table and the number by its name"
}

pub fn a_missing_armor_refill_time_stops_the_load_named_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from game_number where name = 'interrupt_armor_refill_ms'",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a creature that cannot refill its armor stops the start (migration 0016)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("game_number", refusal.RowName("interrupt_armor_refill_ms"))]
}

pub fn the_load_puts_each_playable_classs_resource_in_a_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let assert Ok(stalker) =
    class_resource.of_class(
      classes: content_class_resource.classes(key:),
      class_id: ClassId(5),
    )
    as "migration 0011 holds the Stalker's rows"
  assert stalker
    == class_resource.Resource(
      slot: 3,
      max: 100.0,
      start: 100.0,
      regen: option.Some(class_resource.Regen(per_tick: 7.0, tick_ms: 1000)),
      refill_after_combat_ms: option.None,
      drain: option.None,
      empty_after_combat_ms: option.None,
    )
    as "the design: Suit Power in slot 3, 100, full at the start, +7 each second"
}

pub fn a_playable_class_with_no_max_row_stops_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from class_resource where class_id = 3 and name = 'max'",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a playable class with no maximum stops the start (the design, test 14)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [#("class_resource", refusal.RowName("3 max"))]
}

pub fn a_class_missing_the_rows_of_its_refill_stops_the_load_naming_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "delete from class_resource where (class_id = 4 and name = 'refill_after_combat_ms') or (class_id = 5 and name like 'regen%') or (class_id = 7 and name = 'regen_amount')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "the Medic's refill, the Stalker's and the Spellslinger's regeneration each need their rows (the design's values table): a class that would never refill stops the start"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("class_resource", refusal.RowName("4 refill_after_combat_ms")),
      #("class_resource", refusal.RowName("5 regen_amount")),
      #("class_resource", refusal.RowName("5 regen_period_ms")),
      #("class_resource", refusal.RowName("5 regen_tick_ms")),
      #("class_resource", refusal.RowName("7 regen_amount")),
    ]
    as "each missing row is named by its class and number"
}

pub fn the_load_puts_the_servers_proxies_in_a_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  assert server_proxy_support.changes(
    proxies: content_server_proxy.proxies(key:),
    plans: spell_plan.plans(character_tables.content_tables()),
    base: 26_468,
  )
    as "migration 0018's seed row, Pulse Blast's go 1 casting 42148, is selected over the committed spell trees and kept"
}

pub fn the_load_puts_the_zones_welcomes_from_the_seed_in_a_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let #(loaded, key) = content_support.load(database:)
  assert loaded == Ok(Nil)
  let welcomes = content_zone_welcome.zone_welcomes(key:)
  assert zone_welcome.on_terrain_loaded(welcomes:, world_zone_id: 648)
    == [Frame(message_id: 0x0179, body: <<0x4c, 0x01, 0x00, 0x00>>)]
    as "migration 0020 seeds WorldZone 35 with Tutorial 332 (the Northern Wilds welcome), and 648 Landing Site's parent is 35; 0x179 carries 332 in 32 bits, least significant byte first"
}

pub fn a_server_proxy_row_that_cannot_be_planned_stops_the_load_naming_each_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  content_support.change(
    database:,
    sql: "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (99999, 0, 42148, 'server_choice', 'a base with no plan'), (26468, 2, 42148, 'server_choice', 'a go Pulse Blast does not have'), (26468, 0, 99999, 'server_choice', 'a spell the tables lack')",
  )
  let #(loaded, _key) = content_support.load(database:)
  let assert Error(content.Refused(refusals:)) = loaded
    as "a row that names no plan, no go or no spell stops the start (the design, tests 10 to 12)"
  assert list.map(refusals, fn(refused) { #(refused.table, refused.row) })
    == [
      #("server_proxy", refusal.RowName("26468 0 99999")),
      #("server_proxy", refusal.RowName("26468 2 42148")),
      #("server_proxy", refusal.RowName("99999 0 42148")),
    ]
    as "each bad row is named by its key, in the table's key order, and the seed row is not"
}
