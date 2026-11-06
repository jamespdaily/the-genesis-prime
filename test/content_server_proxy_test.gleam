//// The server_proxy content table (migration 0018, `genesis_prime/content/server_proxy`):
//// the seed row and the table's own refusals. Expected values come from these places:
//// - Jim's decision of 2026-11-06 (issue 419): one row, Pulse Blast's Spell4Base 26468,
////   go 1 (its striking go, SpellPhase 5391), cast 42148, a server choice that states its
////   reason.
//// - The client keeps phase rows below 32 (`0x14055e180`), so a phase is 0 to 31.
//// - The pattern of `class_resource` (migration 0011): a world-database row names its source
////   row and any other row states its reason, and a repeated key, an unknown source and a
////   blank reason are refused by the table.

import content_support
import database_support
import genesis_prime/content/server_proxy as content_server_proxy
import genesis_prime/game/server_proxy.{Row}
import gleam/list
import gleam/string
import owned_test

pub fn a_migrated_database_holds_the_seed_row_with_its_source_and_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_server_proxy.rows(db: content_support.connect(database:))
    as "the query ran"
  assert rows == [Row(spell4_base_id: 26_468, phase: 1, spell4_id: 42_148)]
    as "Jim's decision: Pulse Blast's striking go casts 42148"
  assert content_support.count(
      database:,
      sql: "select count(*) from server_proxy where source = 'server_choice' and reason is not null and source_row is null",
    )
    == 1
    as "the row is the server's choice and states its reason"
}

pub fn the_database_refuses_each_bad_row_under_its_own_constraint_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source) values (1, 0, 2, 'server_choice')",
        "server_proxy_other_source_states_its_reason",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (1, 0, 2, 'server_choice', '   ')",
        "server_proxy_reason_says_something",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (1, 32, 2, 'server_choice', 'x')",
        "server_proxy_phase_is_below_32",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (1, -1, 2, 'server_choice', 'x')",
        "server_proxy_phase_is_below_32",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (1, 0, 2, 'nobody', 'x')",
        "server_proxy_source_is_a_content_source",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (26468, 1, 42148, 'server_choice', 'x')",
        "server_proxy_pkey",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (0, 0, 2, 'server_choice', 'x')",
        "server_proxy_ids_are_positive",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, source_row, reason) values (1, 0, 2, 'server_choice', 5, 'x')",
        "server_proxy_world_database_row_has_a_source_row",
      ),
      #(
        "insert into server_proxy (spell4_base_id, phase, spell4_id, source, reason) values (1, 0, 2, 'world_database', 'x')",
        "server_proxy_world_database_row_has_a_source_row",
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
