//// The coverage measure's starting set holds the class innates
//// (`genesis_prime/coverage/starting_ability`). Expected values come from these
//// places.
//// - `Class.spell4IdInnateAbilityActive00`, `.trees` and `Passive00`: the nine slot-0
////   roots and the spells each reaches, Proxy children gated or not: Warrior 46867
////   (42908, 60915, 79875), 44926; Engineer 47866 (47860, 79697, 57443, 70599, 52371),
////   45000 (46297); Esper 58586 (70369, 76766, 78078); Medic 69450 (60718, 60796);
////   Stalker 46073 (38784, 83850, 38783), 45057 (60724, 60868); Spellslinger 47273
////   (47439, 78307).
//// - `Prerequisite.prerequisiteTypeId.1`: a type 1 condition compares the unit's level
////   with its value; a level-1 character fails comparison 4 (at least) with 6 or 10.
////   The gates of the Proxies that are closed at level 1 are the ones that name a
////   `FailsAtLevelOne` of the same rows (`level_one_gate`).
//// - `Class.spell4IdInnateAbilityActive00`: slots 1 and 2 are Warrior 47022 / 44932
////   and Engineer 47881 / 41504 and Stalker 46074 / 45058, all behind Prerequisite
////   39778 (type 1, comparison 4, value 6), and Stalker 38782 / 46059 behind 39779
////   (value 10); `0x1405e73e0` unlocks a slot only when its gate passes.
//// Skipped where the client's tables are not on the machine.

import client_tables
import coverage_support
import genesis_prime/coverage/level_one_gate
import genesis_prime/coverage/starting_ability.{InnateSlotClosed}
import genesis_prime/shared/spell_plan
import genesis_prime/table/class
import genesis_prime/table/id
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/int
import gleam/list
import gleam/set
import owned_test
import unitest

fn reached_ids() -> set.Set(Int) {
  let assert Ok(spells) =
    starting_ability.spells(tables: client_tables.every_table())
    as "the client's tables hold the rows the walk names"
  set.from_list(list.map(spells, fn(spell) { spell.spell4_id.value }))
}

pub fn the_starting_set_reaches_the_nine_innate_roots_and_what_a_level_1_gate_lets_through_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let reached = reached_ids()
  list.each(
    [46_867, 44_926, 47_866, 45_000, 58_586, 69_450, 46_073, 45_057, 47_273],
    fn(root) {
      assert set.contains(reached, root)
        as {
          "innate root " <> int.to_string(root) <> " is in the starting set"
        }
    },
  )
  list.each(
    [
      42_908, 47_860, 52_371, 70_599, 46_297, 70_369, 76_766, 38_784, 38_783,
      60_724, 47_439,
    ],
    fn(child) {
      assert set.contains(reached, child)
        as {
          "Spell " <> int.to_string(child) <> " is reached by an open Proxy"
        }
    },
  )
}

pub fn the_spells_behind_a_gate_a_level_1_character_cannot_open_are_not_reached_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let reached = reached_ids()
  list.each(
    [
      60_915, 79_875, 79_697, 57_443, 78_078, 60_718, 60_796, 83_850, 60_868,
      78_307,
    ],
    fn(closed) {
      assert !set.contains(reached, closed)
        as {
          "Spell "
          <> int.to_string(closed)
          <> " is behind a gate level 1 fails (Prerequisite.prerequisiteTypeId.1, or an AMP not held)"
        }
    },
  )
}

pub fn the_innate_slots_behind_a_level_gate_are_listed_with_the_gate_the_tables_name_and_none_is_open_at_level_1_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let left = coverage_support.left_out()
  let closed =
    list.filter_map(left, fn(part) {
      case part {
        InnateSlotClosed(..) -> Ok(part)
        starting_ability.ProxyGateClosed(..)
        | starting_ability.ProcKindNotRead(..)
        | starting_ability.ProcLeftOut(..)
        | starting_ability.RunnerColumnsOnly(..) -> Error(Nil)
      }
    })
  assert closed != [] as "the client's classes hold slots behind a level gate"
  list.each(closed, fn(part) {
    let assert InnateSlotClosed(class_id:, slot:, active:, gate:, why:, ..) =
      part
    let assert Ok(row) = class.get(tables:, id: id.ClassId(class_id))
      as { "the Class row " <> int.to_string(class_id) <> " is in the table" }
    let #(slot_active, slot_gate) = case slot {
      1 -> #(
        row.spell4_id_innate_ability_active01,
        row.prerequisite_id_innate_ability01,
      )
      2 -> #(
        row.spell4_id_innate_ability_active02,
        row.prerequisite_id_innate_ability02,
      )
      _ -> #(0, 0)
    }
    assert slot_active == active && slot_gate == gate
      as {
        "Class "
        <> int.to_string(class_id)
        <> " slot "
        <> int.to_string(slot)
        <> " holds the active spell and the gate the measure lists"
      }
    let assert Ok(gate_row) =
      prerequisite_table.get(tables:, id: id.PrerequisiteId(gate))
      as {
        "the gate Prerequisite " <> int.to_string(gate) <> " is in the table"
      }
    let assert level_one_gate.FailsAtLevelOne(comparison:, value:) = why
      as "an innate slot is closed by a level condition"
    assert list.contains(
      [
        #(
          gate_row.prerequisite_type_id0,
          gate_row.prerequisite_comparison_id0,
          gate_row.value0,
        ),
        #(
          gate_row.prerequisite_type_id1,
          gate_row.prerequisite_comparison_id1,
          gate_row.value1,
        ),
        #(
          gate_row.prerequisite_type_id2,
          gate_row.prerequisite_comparison_id2,
          gate_row.value2,
        ),
      ],
      #(1, comparison, value),
    )
      as {
        "the gate Prerequisite "
        <> int.to_string(gate)
        <> " holds a type 1 condition of the stated comparison and value (Prerequisite.prerequisiteTypeId.1)"
      }
  })
  let named =
    list.flat_map(class.all(tables), fn(row) {
      list.filter(
        [
          row.spell4_id_innate_ability_active01,
          row.spell4_id_innate_ability_active02,
        ],
        fn(active) { active != 0 },
      )
    })
  assert list.length(named) == list.length(closed)
    as "every Class row's slot 1 or 2 with an active spell is listed, so the gate of none is open at level 1 and the server's holding slot 0 only agrees with the measure"
  assert starting_ability.describe_left_out(left_out: InnateSlotClosed(
      class_id: 5,
      slot: 2,
      active: 38_782,
      passive: 46_059,
      gate: 39_779,
      why: level_one_gate.FailsAtLevelOne(comparison: 4, value: 10),
    ))
    == "Class 5 innate slot 2 (Spell4 38782, passive 46059) is not counted: its gate Prerequisite 39779 holds a level condition that needs level 10"
}

pub fn the_starting_ability_report_names_the_unraised_event_not_an_issue_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("coverage")
  assert starting_ability.describe_left_out(
      left_out: starting_ability.ProcLeftOut(
        spell4_id: 38_784,
        effect_id: 178_239,
        why: spell_plan.ProcKindWaits(
          kind: 57,
          event: "the holder entering combat, or its health or shield crossing a value",
        ),
        casts: 72_838,
      ),
    )
    == "Proc effect 178239 of Spell4 38784 is left out by the plan (its kind 57 is not raised: the holder entering combat, or its health or shield crossing a value), so the Spell4 72838 it casts is not counted"
    as "the line names the kind and the event the server does not raise, and no issue"
}
