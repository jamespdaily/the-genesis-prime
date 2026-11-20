//// The decode of a QuestObjective row's `type` and `data` into one kind
//// (genesis_prime/game/objective_kind). Expected values and their sources:
//// - What each type is and what its data names: the fact `QuestObjective.type.N`
////   for each N (type 13 has no record of its own; `0x1405517a0` and `0x140550c50`
////   name it with 10, 14 and 18); type 0 is the objective `0x140553790` always
////   reaches.
//// - The kill types 2, 8, 15, 16 and 46: `0x140550c50` ("sets the kill result") and
////   `0x1406113b0`.
//// - The checklist types 10, 13, 14, 18 and, by their PathSoldierActivate row's
////   mode, 27 and 28: `0x1405517a0`.
//// - The types the client's QuestObjective table uses, counted from the extracted
////   table: 40 types, 23 of them with a variant.

import client_tables
import coverage_support
import fixture_tables
import genesis_prime/coverage/engine
import genesis_prime/game/objective_kind.{
  type Kind, CastSpell, ChecklistActivate, ChecklistTalk, ChecklistUse,
  CollectItem, CollectVirtualItem, CraftItem, FinishQuest, GroupOf,
  KillByCluster, KillByDifficulty, KillCreature, KillGroup, OneCreature,
  Placeholder, ReachPlace, Scripted, ServerChecklist, TalkTo, Unconditional,
  UnitOfSoldier, UnitsOfGroup, Unread, UseCreature, UseGroup, VisitZone,
}
import genesis_prime/table/id.{
  Creature2DifficultyId, Creature2Id, Item2Id, PathSoldierActivateId, Quest2Id,
  Spell4Id, TargetGroupId, TradeskillSchematic2Id, VirtualItemId, WorldZoneId,
}
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/quest_objective
import gleam/int
import gleam/list
import owned_test
import unitest

/// A data value no table row needs to hold: the kind must carry it through.
const data = 7777

fn numbers_to_60() -> List(Int) {
  int.range(from: 0, to: 61, with: [], run: list.prepend) |> list.reverse
}

pub fn objective_kind_decodes_each_handled_type_to_its_variant_test() -> Nil {
  use <- owned_test.run(10_000)
  let expected: List(#(Int, Kind)) = [
    #(0, Unconditional),
    #(2, KillCreature(Creature2Id(data))),
    #(3, TalkTo(Creature2Id(data))),
    #(4, CollectItem(Item2Id(data))),
    #(5, Scripted),
    #(8, KillGroup(TargetGroupId(data))),
    #(10, ServerChecklist),
    #(11, CastSpell(Spell4Id(data))),
    #(12, UseCreature(Creature2Id(data))),
    #(13, ServerChecklist),
    #(14, ChecklistUse(TargetGroupId(data))),
    #(15, KillByCluster(cluster: data)),
    #(16, KillGroup(TargetGroupId(data))),
    #(17, VisitZone(WorldZoneId(data))),
    #(18, ChecklistTalk(TargetGroupId(data))),
    #(22, ReachPlace),
    #(23, UseGroup(TargetGroupId(data))),
    #(24, FinishQuest(Quest2Id(data))),
    #(27, ChecklistActivate(PathSoldierActivateId(data))),
    #(28, ChecklistActivate(PathSoldierActivateId(data))),
    #(31, Placeholder),
    #(32, CollectVirtualItem(VirtualItemId(data))),
    #(33, CraftItem(TradeskillSchematic2Id(data))),
    #(46, KillByDifficulty(Creature2DifficultyId(data))),
  ]
  list.each(expected, fn(entry) {
    let #(type_number, kind) = entry
    assert objective_kind.kind_of(type_number:, data:) == kind
      as {
        "QuestObjective.type."
        <> int.to_string(type_number)
        <> " decodes to its variant with its data"
      }
  })
}

pub fn objective_kind_gives_unread_the_number_for_a_type_it_does_not_handle_test() -> Nil {
  use <- owned_test.run(10_000)
  assert objective_kind.kind_of(type_number: 25, data:) == Unread(25)
    as "QuestObjective.type.25 (win a Soldier event) is a type no rule reads"
  assert objective_kind.kind_of(type_number: 38, data:) == Unread(38)
    as "QuestObjective.type.38 (deliver a work order) is a type no rule reads"
}

pub fn objective_kind_eight_and_sixteen_decode_alike_test() -> Nil {
  use <- owned_test.run(10_000)
  assert objective_kind.kind_of(type_number: 16, data:)
    == objective_kind.kind_of(type_number: 8, data:)
    as "QuestObjective.type.16: a kill of a unit of a TargetGroup, the same as type 8"
}

pub fn objective_kind_kill_kinds_are_exactly_2_8_15_16_46_test() -> Nil {
  use <- owned_test.run(10_000)
  let kills =
    list.filter(numbers_to_60(), fn(type_number) {
      objective_kind.is_kill(objective_kind.kind_of(type_number:, data:))
    })
  assert kills == [2, 8, 15, 16, 46]
    as "0x140550c50 sets the kill result for types 2, 8 and 16, 15 and 46 and no other; 0x1406113b0 names the same five"
}

pub fn objective_kind_checklist_kinds_are_10_13_14_18_and_the_path_soldier_pair_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let rows = path_soldier_activate.all(tables)
  let counting_bits = fn(row: path_soldier_activate.PathSoldierActivate) {
    row.soldier_activate_mode_enum == 1 || row.soldier_activate_mode_enum == 2
  }
  let assert [soldier_activate_with_bits, ..] = list.filter(rows, counting_bits)
    as "the fixture holds a PathSoldierActivate row of mode 1 or 2"
  let assert [soldier_activate_without_bits, ..] =
    list.filter(rows, fn(row) { !counting_bits(row) })
    as "the fixture holds a PathSoldierActivate row of another mode"
  let id_of = fn(row: path_soldier_activate.PathSoldierActivate) { row.id }
  list.each([10, 13, 14, 18], fn(type_number) {
    assert objective_kind.is_checklist(
      tables:,
      kind: objective_kind.kind_of(type_number:, data: 0),
    )
      as {
        "0x1405517a0: type "
        <> int.to_string(type_number)
        <> " is a checklist whatever its data"
      }
  })
  list.each([27, 28], fn(type_number) {
    assert objective_kind.is_checklist(
      tables:,
      kind: objective_kind.kind_of(
        type_number:,
        data: id_of(soldier_activate_with_bits),
      ),
    )
      as {
        "0x1405517a0: type "
        <> int.to_string(type_number)
        <> " is a checklist when its PathSoldierActivate row's mode is 1 or 2"
      }
    assert !objective_kind.is_checklist(
      tables:,
      kind: objective_kind.kind_of(
        type_number:,
        data: id_of(soldier_activate_without_bits),
      ),
    )
      as {
        "0x1405517a0: type "
        <> int.to_string(type_number)
        <> " is no checklist when its row's mode is not 1 or 2"
      }
    assert !objective_kind.is_checklist(
      tables:,
      kind: objective_kind.kind_of(type_number:, data: 999_999_999),
    )
      as {
        "0x1405517a0: type "
        <> int.to_string(type_number)
        <> " is no checklist when no PathSoldierActivate row is named"
      }
  })
  let others =
    list.filter(numbers_to_60(), fn(type_number) {
      !list.contains([10, 13, 14, 18, 27, 28], type_number)
    })
  list.each(others, fn(type_number) {
    assert !objective_kind.is_checklist(
      tables:,
      kind: objective_kind.kind_of(
        type_number:,
        data: id_of(soldier_activate_with_bits),
      ),
    )
      as {
        "0x1405517a0: no other type is a checklist; type "
        <> int.to_string(type_number)
        <> " is not"
      }
  })
}

/// The types of the client's QuestObjective table no rule reads (the table holds 40
/// types; the other 23 have a variant).
const unread_types = [
  9, 19, 20, 21, 25, 29, 35, 36, 37, 38, 39, 40, 41, 42, 44, 47, 48,
]

pub fn objective_kind_has_a_variant_for_every_type_the_real_tables_use_that_the_code_reads_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("registry")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = quest_objective.all(tables)
  assert rows != [] as "the client's table holds quest objectives"
  let types = list.unique(list.map(rows, fn(row) { row.type_ }))
  assert list.length(types) == 40
    as "QuestObjective.tbl holds 40 distinct types (counted over its 10031 rows)"
  let unread =
    list.filter(types, fn(type_number) {
      objective_kind.of_row(row_of_type(rows:, type_number:))
      == Unread(type_number:)
    })
    |> list.sort(by: int.compare)
  assert unread == unread_types
    as "the types of the table with no variant are the listed ones; a type that gains a variant leaves the list, and a new type in the table joins it or gets a variant"
}

fn row_of_type(
  rows rows: List(quest_objective.QuestObjective),
  type_number type_number: Int,
) -> quest_objective.QuestObjective {
  let assert Ok(row) = list.find(rows, fn(row) { row.type_ == type_number })
    as "a row of the type"
  row
}

/// Asserts an accessor answers `Ok` with the listed value for the listed types, and
/// `Error(Nil)` for every other type number.
fn assert_answers(
  accessor accessor: fn(Kind) -> Result(a, Nil),
  yes yes: List(#(Int, a)),
  evidence evidence: String,
) -> Nil {
  list.each(numbers_to_60(), fn(type_number) {
    let expected = case list.key_find(yes, type_number) {
      Ok(value) -> Ok(value)
      Error(Nil) -> Error(Nil)
    }
    assert accessor(objective_kind.kind_of(type_number:, data:)) == expected
      as { "type " <> int.to_string(type_number) <> ": " <> evidence }
  })
}

pub fn objective_kind_used_creature_is_type_12_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.used_creature,
    yes: [#(12, Creature2Id(data))],
    evidence: "QuestObjective.type.12 is a use of the Creature2 its data names",
  )
}

pub fn objective_kind_visited_zone_is_type_17_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.visited_zone,
    yes: [#(17, WorldZoneId(data))],
    evidence: "QuestObjective.type.17 is a visit of the WorldZone its data names",
  )
}

pub fn objective_kind_cast_spell_is_type_11_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.cast_spell,
    yes: [#(11, Spell4Id(data))],
    evidence: "QuestObjective.type.11 is a cast of the Spell4 its data names",
  )
}

pub fn objective_kind_used_group_is_type_23_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.used_group,
    yes: [#(23, TargetGroupId(data))],
    evidence: "QuestObjective.type.23 is a use of a unit of the TargetGroup its data names",
  )
}

pub fn objective_kind_used_checklist_group_is_type_14_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.used_checklist_group,
    yes: [#(14, TargetGroupId(data))],
    evidence: "QuestObjective.type.14 is a use of each unit of the TargetGroup its data names, counted as bits (0x1405517a0)",
  )
}

pub fn objective_kind_placed_target_is_a_kill_of_type_2_8_or_16_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.placed_target,
    yes: [
      #(2, OneCreature(Creature2Id(data))),
      #(8, GroupOf(TargetGroupId(data))),
      #(16, GroupOf(TargetGroupId(data))),
    ],
    evidence: "QuestObjective.type.2 names a Creature2 and QuestObjective.type.8 and QuestObjective.type.16 a TargetGroup to kill; no other type names a unit to place",
  )
}

pub fn objective_kind_checklist_target_is_a_group_for_14_and_18_and_a_soldier_for_27_and_28_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_answers(
    accessor: objective_kind.checklist_target,
    yes: [
      #(14, UnitsOfGroup(TargetGroupId(data))),
      #(18, UnitsOfGroup(TargetGroupId(data))),
      #(27, UnitOfSoldier(PathSoldierActivateId(data))),
      #(28, UnitOfSoldier(PathSoldierActivateId(data))),
    ],
    evidence: "0x1405517a0 counts 14 and 18 by the units of the TargetGroup in the data (QuestObjective.type.14, QuestObjective.type.18) and 27 and 28 by the unit of the PathSoldierActivate row in the data (QuestObjective.type.28); 10 and 13 take their progress from the server only",
  )
}

pub fn coverage_quest_objective_handled_ids_agree_with_objective_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  let declared = coverage_support.engine_named("Quest objectives")
  let handled =
    list.filter(numbers_to_60(), fn(type_number) {
      engine.handles(engine: declared, type_number:)
    })
  assert handled
    == [2, 3, 4, 5, 8, 11, 12, 14, 16, 17, 18, 22, 23, 24, 27, 28, 32, 33]
    as "the types whose rule advances an objective: kills of 2, 8 and 16 (genesis_prime/game/objective), talks 3 and 18, uses 12, 14 and 23, collects 4, 32 and 33, visits 17, places 22, finishes 24, scripted 5 and path soldier 27 and 28 (0x1405517a0); type 11 since a cast of the objective's spell completes it (objective_test a_cast_of_the_objective_spell_completes_it_test). Not 15 and 46 (no kill advances them: the server holds no cluster or rank), 10 and 13 (progress only from the server) and 31 (hidden, never counted)"
  assert list.filter(numbers_to_60(), objective_kind.is_counted) == handled
    as "the engine's handled set is the kind module's is_counted"
}
