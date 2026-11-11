//// The client's whole tables read for the cast-a-spell objectives (`QuestObjective.type.11`):
//// which of them name a spell, which belong to a timed quest, and which spells the server
//// plans. Each test reads the client's files and passes only where they are on the machine.

import client_tables
import genesis_prime/game/area
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log
import genesis_prime/game/shortcut_spell.{Aimed, CannotBePlanned, Planned}
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{Spell4Id, Spell4TargetMechanicsId}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_target_mechanics
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import unitest

fn cast_rows(tables tables: Tables) -> List(quest_objective.QuestObjective) {
  quest_objective.all(tables)
  |> list.filter(fn(row) { row.type_ == shortcut_spell.cast_type })
}

pub fn the_cast_objectives_without_a_spell_are_the_known_six_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let without =
    cast_rows(tables:)
    |> list.filter(fn(row) {
      case spell4.get(tables:, id: Spell4Id(row.data)) {
        Ok(_) -> False
        Error(Nil) -> True
      }
    })
    |> list.map(fn(row) { row.id })
    |> list.sort(by: int.compare)
  assert without == [7378, 8042, 9882, 15_816, 16_525, 16_577]
    as "QuestObjective rows of type 11 whose data has no Spell4 row (measured over the client's table): the client refuses the press of such a spell (0x14039b340, 22), so no button is given for them and they cannot be finished"
}

pub fn no_cast_objective_belongs_to_a_timed_quest_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = cast_rows(tables:)
  assert rows != [] as "the client's table holds type 11 objectives"
  assert list.filter(rows, fn(row) { row.max_time_allowed_ms != 0 }) == []
    as "every type 11 objective has maxTimeAllowedMS 0"
  let cast_ids = set.from_list(list.map(rows, fn(row) { row.id }))
  let timed =
    quest2.all(tables)
    |> list.filter(fn(quest) {
      quest.max_time_allowed_ms != 0
      && list.any(
        [
          quest.objective0,
          quest.objective01,
          quest.objective02,
          quest.objective03,
          quest.objective04,
          quest.objective05,
        ],
        set.contains(cast_ids, _),
      )
    })
    |> list.map(fn(quest) { quest.id })
  assert timed == []
    as "every quest that lists a type 11 objective has maxTimeAllowedMS 0, so no cast button closes by a deadline and the expiry sends no 0x176"
}

pub fn the_self_aimed_objective_spells_plan_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let shortcuts = shortcut_spell.shortcuts(tables:)
  let planned_ids =
    dict.to_list(shortcuts.spells)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        Planned(..) -> Ok(entry.0)
        Aimed(..) | shortcut_spell.NoSpell4Row | CannotBePlanned(..) ->
          Error(Nil)
      }
    })
  // The spells of rows 5197, 13884, 5181 and 18165 are aimed at the caster, and plan.
  list.each([25_306, 40_471, 25_287, 70_503], fn(spell4_id) {
    assert list.contains(planned_ids, spell4_id)
      as "the spell of a self-aimed cast objective plans (`spell_plan.spell_alone`)"
  })
}

fn aimed_ids(shortcuts shortcuts: shortcut_spell.Shortcuts) -> List(Int) {
  dict.to_list(shortcuts.spells)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      Aimed(..) -> Ok(entry.0)
      Planned(..) | shortcut_spell.NoSpell4Row | CannotBePlanned(..) ->
        Error(Nil)
    }
  })
  |> list.sort(by: int.compare)
}

/// Whether the spell's Spell4TargetMechanics row takes a target of the player's choice
/// (targetType 1, 3, 5 or 8), by the rows themselves.
fn targeted(tables tables: Tables, spell4_id spell4_id: Int) -> Bool {
  let assert Ok(row) = spell4.get(tables:, id: Spell4Id(spell4_id))
    as "the spell has a Spell4 row"
  let assert Ok(base) =
    spell4_base.get(tables:, id: spell4.spell4_base_id_base_spell(row))
    as "the spell has a Spell4Base row"
  let assert Ok(mechanics) =
    spell4_target_mechanics.get(
      tables:,
      id: Spell4TargetMechanicsId(base.spell4_target_mechanic_id),
    )
    as "the base has a Spell4TargetMechanics row"
  list.contains([1, 3, 5, 8], mechanics.target_type)
}

pub fn the_targeted_objective_spells_plan_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let shortcuts = shortcut_spell.shortcuts(tables:)
  // The spells of the self-aimed rows that cannot be planned (1316 and 32620, whose
  // Spell4TargetMechanics row 1 aims at the caster) are not among the targeted ones.
  let cannot_be_planned =
    dict.to_list(shortcuts.spells)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        CannotBePlanned(..) ->
          case targeted(tables:, spell4_id: entry.0) {
            True -> Ok(entry.0)
            False -> Error(Nil)
          }
        Planned(..) | Aimed(..) | shortcut_spell.NoSpell4Row -> Error(Nil)
      }
    })
    |> list.sort(by: int.compare)
  assert list.length(aimed_ids(shortcuts:)) == 52
    as "52 of the 59 distinct spells the 73 targeted type 11 rows name plan as Aimed (`spell_plan.spell_alone`, measured over the client's table)"
  assert cannot_be_planned
    == [23_229, 30_173, 34_470, 34_471, 34_474, 34_684, 42_891]
    as "the other 7 spells cannot be planned (`spell_plan.spell_alone`), so their presses are refused 285 as not built"
}

/// The rows whose Aimed spell has a CasterCast the server reads none of, or a TargetCast
/// the connection cannot judge on a creature it holds no life, vital or faction of.
fn unjudgeable_rows(tables tables: Tables) -> List(Int) {
  let shortcuts = shortcut_spell.shortcuts(tables:)
  let assert Ok(quests) = quest_log.from_rows(rows: [], tables:)
    as "an empty quest log holds no row to refuse"
  let pose = area.Pose(at: area.Point(x: 0.0, z: 0.0), yaw: 0.0)
  let target =
    prerequisite.of_target(
      under: [],
      caster_unit: 1,
      in_combat: False,
      target: pose,
      caster: pose,
      quests:,
    )
  cast_rows(tables:)
  |> list.filter(fn(row) {
    case shortcut_spell.planned_of(shortcuts:, spell4_id: row.data) {
      Ok(Aimed(spell:, ..)) ->
        caster_cast_unread(spell:) || target_cast_unread(spell:, target:)
      Ok(Planned(..)) | Ok(shortcut_spell.NoSpell4Row) -> False
      Ok(CannotBePlanned(..)) | Error(Nil) -> False
    }
  })
  |> list.map(fn(row) { row.id })
  |> list.sort(by: int.compare)
}

fn caster_cast_unread(spell spell: spell_plan.Spell) -> Bool {
  case spell.caster_cast {
    spell_plan.CastGate(prerequisite: gate) ->
      prerequisite.unread_types(prerequisite: gate) != []
    spell_plan.RequirementWaiver(..) | spell_plan.NoCasterCast -> False
  }
}

fn target_cast_unread(
  spell spell: spell_plan.Spell,
  target target: prerequisite.Subject,
) -> Bool {
  case spell.target_cast {
    Some(gate) ->
      case prerequisite.check(prerequisite: gate, subject: target) {
        prerequisite.NotRead(..) -> True
        prerequisite.Passes | prerequisite.Fails -> False
      }
    None -> False
  }
}

pub fn every_targeted_rows_cast_conditions_are_read_but_the_known_eleven_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  assert unjudgeable_rows(tables:)
    == [
      8389, 9399, 9401, 9768, 9770, 9771, 15_193, 15_340, 15_363, 17_880, 17_933,
    ]
    as "the targeted type 11 rows whose spell has a CasterCast of a PrerequisiteType the server does not read (16, 47, 102) or a TargetCast of type 4 or 71, which the connection cannot judge on a creature (measured over the client's table), besides rows 14966 and 15332, whose spells cannot be planned"
}
