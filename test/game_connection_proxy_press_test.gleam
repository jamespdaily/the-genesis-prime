//// A press of a threshold ability with no threshold time on the game connection: the client
//// is told the Proxy's spell started, with the ability as its root. Expected values come from
//// these places, each named at its assertion:
//// - ResolveProxyByCasterApply `0x1403d3520` (fact `cast.proxy_press`): the press walks the
////   ability's effects in row order and casts the spell of the first Proxy whose caster apply
////   passes. Spell4 42603 (Spell4Base 26793, RapidTap, thresholdTime 0) holds Proxy rows
////   96985 (orderIndex 0, spell 42604, caster apply 16450), 96992 (1, 42605, 16451) and 96993
////   (2, 42606, 16452), each gate one type 59 condition on the stacks of Spell4 42607 (equal
////   0, 1 and 2), so a caster with no stack passes 16450 only until the test edits the gates
////   (`table_rows -- Spell4Effects 96985 96992 96993`, `-- Prerequisite 16450 16451 16452`).
//// - Fact `cast.stage_root_parent` and `opcode.0x7ff.root_spell4_id`: the 0x7ff a viewer is
////   told names the Proxy's spell, the ability as its root and parent 0; the ability itself
////   is never told. The pressing player's own client is told by 0x7fd, which names no spell.
//// - The ability is a SpellLevel row of the Spellslinger (class 7) planted for the test, since
////   no class holds Spell4 42603 in the client's table.

import fixture_tables
import game_connection_support as connection_support
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/table/loader/store
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table
import server_proxy_support

/// The planted level-one ability row of the Spellslinger, a copy of Quick Draw's row.
const planted_row = 999_001

/// The bag index the planted ability takes: after the Spellslinger's three level-one abilities
/// and before its innate, Spell Surge (`loadout.bag`).
const press_bag = 3

fn settings(tables tables: store.Tables) -> game_connection.Settings {
  Settings(
    ..connection_support.settings(),
    tables:,
    server_proxies: server_proxy_support.none(),
  )
}

pub fn proxy_press_spell_started_names_the_proxy_spell_with_the_ability_as_root_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edits: the SpellLevel row planted for the ability; Prerequisite 16450, the gate of
  // row 96985 (orderIndex 0), made equal to 9 nodes of 42607; and Prerequisite 16451, the
  // gate of row 96992 (orderIndex 1), made equal to 0 nodes. A caster with no stack then
  // passes only row 96992, so the press resolves to 42605, the spell the test list names,
  // not to the first row's 42604.
  let rows =
    fixture_tables.rows()
    |> edited(
      fixture_tables.add(
        rows: _,
        table: "SpellLevel",
        copy_of: 1011,
        id: planted_row,
        with: [#("spell4Id", planted_table.Integer(42_603))],
      ),
    )
    |> edited(
      fixture_tables.change(rows: _, table: "Prerequisite", id: 16_450, with: [
        #("value0", planted_table.Integer(9)),
      ]),
    )
    |> edited(
      fixture_tables.change(rows: _, table: "Prerequisite", id: 16_451, with: [
        #("value0", planted_table.Integer(0)),
      ]),
    )
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  let #(state, _) =
    connection_support.entered_with(
      settings: settings(tables:),
      class_id: 7,
      saved_health: None,
    )
  let #(_, steps) =
    connection_support.pressed_until(
      state: connection_support.watched_by(state:, viewers: [2]),
      bag_index: press_bag,
      client_cast_id: 1000,
      ms: 1000,
      until_ms: 3500,
    )
  let assert [pressed, ..] = steps
  assert connection_support.refusal_results(taken: pressed) == []
    as "a caster with no stack of 42607 passes gate 16451, so the press is not refused"
  let started =
    list.flat_map(steps, fn(taken) {
      connection_support.cast_starts(connection_support.news_broadcast(taken))
    })
    |> list.map(fn(start) {
      #(start.spell4_id, start.root_spell4_id, start.parent_spell4_id)
    })
  assert started == [#(42_605, 42_603, 0)]
    as "0x1403d3520 skips row 96985 (its gate fails) and takes row 96992's spell 42605; its root is the ability 42603 and its parent 0, and 42603 itself is never told"
}

/// The rows after one edit, or the test stopped with the edit's refusal.
fn edited(
  rows: fixture_tables.Rows,
  edit: fn(fixture_tables.Rows) ->
    Result(fixture_tables.Rows, fixture_tables.Refusal),
) -> fixture_tables.Rows {
  case edit(rows) {
    Ok(edited) -> edited
    Error(refusal) -> panic as fixture_tables.describe(refusal)
  }
}
