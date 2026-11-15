//// A go's Proxies behind a target apply prerequisite on the game connection
//// (`genesis_prime/game/connection/casting`), on the client's rows kept in the fixture.
//// Expected values come from these places:
//// - `Spell4Effects.prerequisiteIdTargetApply`: an effect lands only on the units that
////   pass its gate, the struck unit first and the caster second; a Proxy that fails for
////   a unit starts nothing on it, so the unit is sent no start of the child.
//// - Impale (Spell4 38779) holds the only gated rows a level-1 ability's tree reaches
////   (`table_rows -- Spell4Effects 83818 83819 85673 85682` and `-- Prerequisite 5734
////   5735`): Proxy 85673 starts 39427 on a unit the Stalker stands behind (positional row
////   53, the 140 degrees behind its facing) and 83818 starts 39426 on a unit it does not.
//// - `creature.facing`: a creature faces the yaw of its 0x262; the Beasts stand 3 m ahead of
////   the Stalker, one at yaw 0 facing away from it and one at a half turn facing it.

import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/message/spell_started
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import gleam/int
import gleam/list
import gleam/option
import owned_test

/// Impale's Spell4Base (Spell4 38779).
const impale_base = 23_161

/// The Beast the Stalker stands behind: it faces away from the Stalker.
const unit_behind = 40

/// The Beast that faces the Stalker.
const unit_facing = 41

fn bag_index_of(base base: Int) -> Int {
  let assert Ok(set) =
    loadout.of(
      tables: fixture_tables.shared(),
      class_id: ClassId(5),
      faction_id: 166,
    )
    as "the fixture holds the Stalker's Novice set"
  let assert Ok(index) =
    list.index_map(loadout.bag(loadout: set), fn(held, index) { #(held, index) })
    |> list.key_find(Spell4BaseId(base))
    as "the Stalker's bag holds the ability"
  index
}

/// A Stalker in the world with both Beasts shown to its client.
fn stalker_with_two_beasts() -> game_connection.State {
  let #(state, _) =
    support.entered_with(
      settings: Settings(..support.settings(), tables: fixture_tables.shared()),
      class_id: 5,
      saved_health: option.None,
    )
  let #(state, _) =
    support.feed(
      state,
      support.beast_appears_facing(unit_id: unit_behind, yaw: 0.0),
    )
  support.feed(
    state,
    support.beast_appears_facing(unit_id: unit_facing, yaw: 3.1415927410125732),
  ).0
}

/// The children of Impale's four Proxies the steps start, as (Spell4 id, primary target
/// unit), in unit order.
fn impale_children(
  steps steps: List(ConnectionStep(Request)),
) -> List(#(Int, Int)) {
  list.flat_map(steps, fn(taken) { support.heard(taken, support.keyed()) })
  |> support.decoded(spell_started.message_id, spell_started.decode)
  |> list.filter(fn(start) {
    start.spell4_id == 39_426 || start.spell4_id == 39_427
  })
  |> list.map(fn(start) { #(start.spell4_id, start.primary_target_unit_id) })
  |> list.sort(fn(first, second) { int.compare(first.1, second.1) })
}

pub fn failed_target_gate_sends_nothing_for_that_unit_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, steps) =
    support.pressed_until(
      state: stalker_with_two_beasts(),
      bag_index: bag_index_of(base: impale_base),
      client_cast_id: 1,
      ms: 1000,
      until_ms: 3000,
    )
  let children = impale_children(steps:)
  assert children == [#(39_427, unit_behind), #(39_426, unit_facing)]
    as "Proxy 85673 (target gate 5734, behind) starts 39427 on the Beast the Stalker stands behind and 83818 starts 39426 on the Beast that faces it: each unit is told of its own child"
  assert !list.contains(children, #(39_427, unit_facing))
    as "the Beast facing the Stalker fails gate 5734: it is sent no start of 39427"
  assert !list.contains(children, #(39_426, unit_behind))
    as "the Beast the Stalker stands behind fails 83818's gate: it is sent no start of 39426"
}
