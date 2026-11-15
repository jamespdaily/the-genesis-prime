//// A go's strike behind a target apply prerequisite on the game connection
//// (`genesis_prime/game/connection/casting` `strike_begins`), on the client's rows kept in
//// the fixture. Expected values come from these places:
//// - `Spell4Effects.prerequisiteIdTargetApply`: a damage row lands only on the units that
////   pass its gate, so the strike told to a creature carries the rows it passes and no
////   strike is told to a creature that passes none.
//// - Damage row 38307 (`table_rows -- Spell4Effects 38307`) is a damage row (effectType 8)
////   in phase 0 (phaseFlags 1) of a spell no starting ability reaches, so it is copied into
////   Impale's child 39427 (the child each Beast behind the Stalker gets) aimed at the
////   primary target (targetFlags 2: the child holds no area constraints for an area row), behind gate 20210 (`table_rows -- Prerequisite 20210`): three type 38
////   conditions (comparison 1, Creature2 48009, 48404 and 48494, one enough: flags 1), and a
////   type 38 condition passes the unit that is the creature of its row
////   (`Prerequisite.prerequisiteTypeId.38`).
//// - `creature.facing`: both Beasts stand behind the Stalker, so each is the primary target
////   of an Impale child (`game_connection_target_gate_test`).

import fixture_tables
import game_connection_support as support
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import gleam/int
import gleam/list
import gleam/option
import owned_test
import planted_table

/// Impale's Spell4Base (Spell4 38779).
const impale_base = 23_161

const named_creature = 48_404

const unnamed_creature = 1

const gated_damage = 99_915

/// Spell4Effects 86308: the damage row of Spell4 39427 behind no apply prerequisite
/// (`table_rows -- Spell4Effects 86308`).
const ungated_damage = 86_308

const named_unit = 42

const unnamed_unit = 43

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

pub fn strike_tell_carries_only_the_passing_rows_test() -> Nil {
  use <- owned_test.run(120_000)
  // Kept edit: damage row 38307 copied into Impale's child 39427 aimed at the primary target, behind gate 20210; unit 42
  // is the creature 48404 that the gate names and unit 43 is creature 1.
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 38_307,
    id: gated_damage,
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
        unit_id: named_unit,
        creature_id: named_creature,
        yaw: 0.0,
      ),
    )
  let #(state, _) =
    support.feed(
      state,
      support.creature_of_beast_appears_facing(
        unit_id: unnamed_unit,
        creature_id: unnamed_creature,
        yaw: 0.0,
      ),
    )
  let #(_, _, steps) =
    support.pressed_until_answered(
      state:,
      world: Nil,
      bag_index: bag_index_of(base: impale_base),
      client_cast_id: 1,
      ms: 1000,
      until_ms: 3000,
      answer: support.landed_with_its_blows,
    )
  let told =
    list.flat_map(steps, fn(taken) { support.strike_blows_told(taken) })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  assert list.map(told, fn(entry) { entry.0 }) == [named_unit, unnamed_unit]
    as "each Beast is the primary target of its own child and is told a strike"
  assert list.map(told, fn(entry) { list.contains(entry.1, gated_damage) })
    == [True, False]
    as "unit 42 is the creature 48404 that gate 20210 names and is told the gated row; unit 43 is creature 1, none of the three, and is told a strike without it"
  assert list.all(told, fn(entry) { list.contains(entry.1, ungated_damage) })
    as "Spell4Effects 86308 of the same child is behind no gate and strikes both"
  let listed =
    support.listed_by_unit(steps:)
    |> list.filter(fn(entry) {
      entry.0 == named_unit || entry.0 == unnamed_unit
    })
  assert list.map(listed, fn(entry) { entry.0 }) == [named_unit, unnamed_unit]
    as "the go lists effects on both creatures, each with the child's ungated row"
  assert list.map(listed, fn(entry) { list.contains(entry.1, gated_damage) })
    == [True, False]
    as "the go lists the gated damage row only on unit 42, the creature the gate names"
  assert list.all(listed, fn(entry) { list.contains(entry.1, ungated_damage) })
    as "the go lists the ungated damage row on both creatures"
}
