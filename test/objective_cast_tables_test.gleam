//// The client's whole tables read for the cast-a-spell objectives (`QuestObjective.type.11`):
//// which of them name a spell, which belong to a timed quest, and which spells the server
//// plans. Each test reads the client's files and passes only where they are on the machine.

import client_tables
import genesis_prime/game/shortcut_spell.{CannotBePlanned, Planned, Targeted}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/set
import gleam/string
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
        Targeted(..) | shortcut_spell.NoSpell4Row | CannotBePlanned(..) ->
          Error(Nil)
      }
    })
  // The spells of rows 5197, 13884, 5181 and 18165 are aimed at the caster, and plan.
  list.each([25_306, 40_471, 25_287, 70_503], fn(spell4_id) {
    assert list.contains(planned_ids, spell4_id)
      as "the spell of a self-aimed cast objective plans (`spell_plan.spell_alone`)"
  })
  let targeted =
    dict.values(shortcuts.spells)
    |> list.count(fn(planned) {
      case planned {
        Targeted(..) -> True
        Planned(..) | shortcut_spell.NoSpell4Row | CannotBePlanned(..) -> False
      }
    })
  let cannot_be_planned =
    dict.to_list(shortcuts.spells)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        CannotBePlanned(why:) -> Ok(int.to_string(entry.0) <> ": " <> why)
        Planned(..) | Targeted(..) | shortcut_spell.NoSpell4Row -> Error(Nil)
      }
    })
  io.println(
    "type 11 spells: "
    <> int.to_string(dict.size(shortcuts.spells))
    <> ", planned "
    <> int.to_string(list.length(planned_ids))
    <> ", targeted "
    <> int.to_string(targeted)
    <> ", cannot be planned "
    <> string.join(cannot_be_planned, ", "),
  )
}
