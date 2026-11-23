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
//// - Row 66766 (`table_rows -- Spell4Effects 66766`) is a Fluff row aimed at the area that
////   lasts until removed (type 17, flags 2) of a deprecated spell no starting ability
////   reaches, so it is added to the Impale child 39427 (the one the Beasts behind the Stalker get) for the creature gate: gate 20210
////   (`table_rows -- Prerequisite 20210`) holds three type 38 conditions (comparison 1,
////   Creature2 48009, 48404 and 48494, one enough: flags 1), and a type 38 condition passes
////   the unit that is the creature of its row (`Prerequisite.prerequisiteTypeId.38`); a go
////   lists a lasting effect on the units it lands on.
//// - `strike_tell.Deflected`: a creature that deflected the whole strike is no unit the go
////   hit, though a row aimed at the primary target still reaches it
////   (`Spell4Effects.targetFlags`: bit 2 is the primary target).
//// - `creature.facing`: a creature faces the yaw of its 0x262; the Beasts stand 3 m ahead of
////   the Stalker, one at yaw 0 facing away from it and one at a half turn facing it.

import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/message/spell_started
import genesis_prime/step.{type ConnectionStep}
import gleam/int
import gleam/list
import gleam/option
import owned_test
import planted_table

/// Impale's Spell4Base (Spell4 38779).
const impale_base = 23_161

/// The Beast the Stalker stands behind: it faces away from the Stalker.
const unit_behind = 40

/// The Beast that faces the Stalker.
const unit_facing = 41

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
      bag_index: support.stalker_bag_index_of(base: impale_base),
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

const named_creature = 48_404

const unnamed_creature = 1

const area_marker = 99_913

pub fn a_creature_gate_on_an_area_row_lists_the_effect_only_on_the_named_creature_test() -> Nil {
  use <- owned_test.run(120_000)
  // Kept edit: Fluff row 66766 copied into Impale's child 39427, which has the telegraph the root lacks (Spell4 38779 holds no area), behind gate 20210; both creatures stand behind the Stalker, so each gets 39427.
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 66_766,
    id: area_marker,
    with: [
      #("spellId", planted_table.Integer(39_427)),
      #("prerequisiteIdTargetApply", planted_table.Integer(20_210)),
      #("orderIndex", planted_table.Integer(6)),
    ],
  )
  let #(state, _) =
    support.entered_with(
      settings: Settings(..support.settings(), tables:),
      class_id: 5,
      saved_health: option.None,
    )
  let #(state, _) =
    support.feed(
      state,
      support.creature_of_beast_appears_facing(
        unit_id: 42,
        creature_id: named_creature,
        yaw: 0.0,
      ),
    )
  let #(state, _) =
    support.feed(
      state,
      support.creature_of_beast_appears_facing(
        unit_id: 43,
        creature_id: unnamed_creature,
        yaw: 0.0,
      ),
    )
  let #(_, steps) =
    support.pressed_until(
      state:,
      bag_index: support.stalker_bag_index_of(base: impale_base),
      client_cast_id: 1,
      ms: 1000,
      until_ms: 3000,
    )
  let listed = support.listed_by_unit(steps:)
  assert list.contains(listed, #(42, [area_marker]))
    as "unit 42 is the creature 48404 that gate 20210 names: the go lists the Fluff row on it"
  assert list.contains(support.struck_units(steps:), 43)
    as "unit 43 is among the units the child's go strikes, so its having no entry below is the gate's, not the layout's"
  assert !list.any(listed, fn(entry) { entry.0 == 43 })
    as "unit 43 is creature 1, none of the three the gate names: the go lists no effect on it"
}

/// The answer where every strike lands but the ones told to the unit 42.
fn deflected_by_unit_42(
  world world: Nil,
  state state: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(Nil, game_connection.State, List(ConnectionStep(Request))) {
  let #(state, steps) =
    support.landing_but_deflected(state:, ms:, taken:, deflecting: [42])
  #(world, state, steps)
}

pub fn a_creature_gate_on_a_primary_target_row_reads_the_primary_target_it_deflected_test() -> Nil {
  use <- owned_test.run(120_000)
  // Kept edit: Fluff row 66766 copied into Impale's child 39427 with its target flags 2,
  // the primary target, behind gate 20210. Each Beast is the primary target of its own
  // child; the creature 48404 deflects every strike, so no go of its child hit it.
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 66_766,
    id: area_marker,
    with: [
      #("spellId", planted_table.Integer(39_427)),
      #("targetFlags", planted_table.Integer(2)),
      #("prerequisiteIdTargetApply", planted_table.Integer(20_210)),
      #("orderIndex", planted_table.Integer(6)),
    ],
  )
  let #(state, _) =
    support.entered_with(
      settings: Settings(..support.settings(), tables:),
      class_id: 5,
      saved_health: option.None,
    )
  let #(state, _) =
    support.feed(
      state,
      support.creature_of_beast_appears_facing(
        unit_id: 42,
        creature_id: named_creature,
        yaw: 0.0,
      ),
    )
  let #(state, _) =
    support.feed(
      state,
      support.creature_of_beast_appears_facing(
        unit_id: 43,
        creature_id: unnamed_creature,
        yaw: 0.0,
      ),
    )
  let #(_, _, steps) =
    support.pressed_until_answered(
      state:,
      world: Nil,
      bag_index: support.stalker_bag_index_of(base: impale_base),
      client_cast_id: 1,
      ms: 1000,
      until_ms: 3000,
      answer: deflected_by_unit_42,
    )
  let listed = support.listed_by_unit(steps:)
  assert list.contains(listed, #(42, [area_marker]))
    as "unit 42 is the primary target of its child and the creature 48404 that gate 20210 names: the row lands on it though it deflected the strike"
  assert !list.any(listed, fn(entry) { entry.0 == 43 })
    as "unit 43 is creature 1, none of the three the gate names, and no row of the child's go is aimed at it but as its own primary target"
}
