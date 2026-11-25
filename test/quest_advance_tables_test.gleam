//// The client's whole tables read for the QuestAdvanceObjective rows (`Spell4Effects.effectType.42`,
//// 251 rows in 184 spells): what the plan makes of every row, and which quest objectives the rows
//// name. Each test reads the client's files and passes only where they are on the machine. The
//// counts are a scratch count of `table_rows -- Spell4Effects effectType=42` joined to the
//// Quest2, QuestObjective, Creature2, ItemSpecial and Item2 tables, which each assert names.

import client_tables
import genesis_prime/game/activate
import genesis_prime/game/item_property
import genesis_prime/game/objective
import genesis_prime/game/objective_action
import genesis_prime/game/quest_log
import genesis_prime/game/spell_plan
import genesis_prime/game/target_group
import genesis_prime/table/creature2
import genesis_prime/table/id.{Faction2Id}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/table/quest2
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import owned_test
import quest_support
import spell_tables
import unitest

fn type_42_rows(tables tables: Tables) -> List(Spell4Effects) {
  spell4_effects.all(tables)
  |> list.filter(fn(row) { row.effect_type == 42 })
}

/// Whether the refusal text `why` of the spell names the effect of one of its type 42 rows
/// (the plan writes `effect N ` for the effect it refuses).
fn refused_for_a_type_42_row(
  why why: String,
  rows rows: List(Spell4Effects),
  spell4_id spell4_id: Int,
) -> Bool {
  list.any(rows, fn(row) {
    row.spell_id == spell4_id
    && string.contains(why, "effect " <> int.to_string(row.id) <> " ")
  })
}

/// What the plan makes of the row, as a name: `applied`, the name of the reason it is left out,
/// or the plan's own refusal.
fn outcome_of(tables tables: Tables, effect effect: Spell4Effects) -> String {
  case
    spell_plan.read_row(
      tables:,
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.pressed,
      effect:,
    )
  {
    Ok(spell_plan.Applied(..)) -> "applied"
    Ok(spell_plan.LeftOut(why: spell_plan.AimedAtOtherUnits)) ->
      "aimed at the area"
    Ok(spell_plan.LeftOut(why: spell_plan.QuestAdvanceColumnNotRead(column:))) ->
      "an unread column: " <> column
    Ok(spell_plan.LeftOut(why: spell_plan.QuestAdvanceAddsNothing)) ->
      "adds nothing"
    Ok(spell_plan.LeftOut(..)) -> "left out for another reason"
    Ok(spell_plan.Held(..)) -> "held"
    Ok(spell_plan.ReadByArea) | Ok(spell_plan.ReadByActivation) -> "read apart"
    Error(error) -> "refused: " <> spell_plan.describe(error:)
  }
}

pub fn every_type_42_row_is_applied_dropped_or_left_out_by_a_named_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = type_42_rows(tables:)
  assert list.length(rows) == 251
    as "Spell4Effects holds 251 rows of effectType 42 (table_rows -- Spell4Effects effectType=42)"
  let counts =
    list.fold(rows, dict.new(), fn(counts, effect) {
      dict.upsert(counts, outcome_of(tables:, effect:), fn(found) {
        case found {
          Some(count) -> count + 1
          None -> 1
        }
      })
    })
  let count = fn(prefix: String) {
    dict.fold(counts, 0, fn(total, outcome, rows) {
      case string.starts_with(outcome, prefix) {
        True -> total + rows
        False -> total
      }
    })
  }
  assert count("applied") == 221
    as "221 rows are applied: aimed at the caster (189 with flags 1, 3 with 3) or at the primary target alone (51 with 2), less the rows below"
  assert count("aimed at the area") == 8
    as "8 rows hold flags 4, which reach no quest log"
  assert count("an unread column") == 18
    as "18 rows hold a column the client does not read: damageType 4, dataBits03 1, dataBits05 4, flags 7 and a caster persistence prerequisite 2"
  assert count("refused") == 4
    as "4 rows (48892, 59788, 59789, 59790) sit behind a caster prerequisite of a type the server does not decode (16 and 27), in spells no table gives a player"
  assert count("adds nothing") == 0 && count("held") == 0
    as "no row has an amount below 1, and every applied row has a phase"
  // Of the 251 rows, 242 name an existing quest and an index inside it, 8 an index past the
  // quest's objectives and 1 a quest with no row (the fact `Spell4Effects.effectType.42`).
  let naming =
    list.count(rows, fn(effect) {
      case quest_log.quest_of(tables:, id: effect.data_bits00) {
        Ok(quest) ->
          effect.data_bits01 >= 0
          && effect.data_bits01 < list.length(quest.objectives)
        Error(..) -> False
      }
    })
  assert naming == 242
    as "242 rows name an objective: the others plan and name none at run time"
}

pub fn no_activate_spell_is_refused_for_a_type_42_row_and_the_use_rule_counts_the_rows_it_does_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let activations = activate.activations(tables:)
  let rows = type_42_rows(tables:)
  let spells = set.from_list(list.map(rows, fn(row) { row.spell_id }))
  assert set.size(spells) == 184
    as "184 spells hold a type 42 row (table_rows -- Spell4Effects effectType=42)"
  let routed =
    set.intersection(spells, activate.activated_spell_ids(tables:, sources:))
  assert set.size(routed) == 80
    as "80 of them are an activate spell of a creature or an item"
  let refused_for_a_row =
    list.filter(set.to_list(routed), fn(spell4_id) {
      case activate.planned_of(activations:, spell4_id:) {
        Ok(activate.CannotBePlanned(why:)) ->
          refused_for_a_type_42_row(why:, rows:, spell4_id:)
        Ok(activate.Planned(..)) | Ok(activate.NoSpell4Row) | Error(Nil) ->
          False
      }
    })
  assert refused_for_a_row == []
    as "a spell the activate cast cannot plan is refused for an effect of another type, as it was before the rows were read"
  // For each row of a creature's activate spell aimed at the caster, whether the use of the
  // creature counts the objective the row names (`objective.counts`): for every creature that
  // holds the spell, for some of them or for none.
  let holders =
    creature2.all(tables)
    |> list.fold(dict.new(), fn(holders, row) {
      list.fold(
        activate.creature_of(row:).columns,
        holders,
        fn(holders, column) {
          dict.upsert(holders, column.spell4_id, fn(found) {
            [row, ..option.unwrap(found, [])]
          })
        },
      )
    })
  let categories =
    list.filter_map(rows, fn(effect) {
      use creatures <- result_try(dict.get(holders, effect.spell_id))
      use quest <- result_try(quest_log.quest_of(
        tables:,
        id: effect.data_bits00,
      ))
      use objective <- result_try(
        list.drop(quest.objectives, effect.data_bits01) |> list.first,
      )
      let counted =
        list.map(creatures, fn(row) {
          objective.counts(
            tables:,
            event: objective.Used(
              target: target_group.Unit(
                creature_id: creature2.id(row),
                faction_id: Faction2Id(0),
                unit_race_id: creature2.unit_race_id(row),
              ),
              checklist_index: 0,
              unit: quest_support.unit_ref(unit_id: { creature2.id(row) }.value),
              by_item: False,
            ),
            quest_id: quest.id,
            index: effect.data_bits01,
            objective:,
            scripts: objective.no_rows(),
          )
        })
      Ok(
        case
          list.all(counted, fn(one) { one }),
          list.any(counted, fn(one) { one })
        {
          True, _ -> "every creature"
          False, True -> "some creatures"
          False, False -> "no creature"
        },
      )
    })
  let counts =
    list.fold(categories, dict.new(), fn(counts, category) {
      dict.upsert(counts, category, fn(found) { option.unwrap(found, 0) + 1 })
    })
  assert list.length(categories) == 112
    as "112 rows of a creature's activate spells name an objective of their quest (the issue's approximate count by the use rule was 115 rows with 2 naming none)"
  assert dict.to_list(counts)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    == [
      #("every creature", 59),
      #("no creature", 36),
      #("some creatures", 17),
    ]
    as "a regression pin of what `objective.counts` answers on the client's rows, not a count made apart from it: the use of every creature that holds the spell counts the row's objective for 59 rows, of some creatures for 17 and of none for 36, so a count above 1 would finish early if both counted"
  Nil
}

fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, Nil),
) -> Result(b, Nil) {
  case result {
    Ok(value) -> next(value)
    Error(..) -> Error(Nil)
  }
}

pub fn no_ability_a_player_holds_names_an_objective_left_open_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let rows = type_42_rows(tables:)
  let routed = activate.activated_spell_ids(tables:, sources:)
  let activations = activate.activations(tables:)
  // A spell a creature or an item routes is castable only when the activate plan holds it:
  // 43650 and 45904 to 45909 are routed and refused 285 for a Fluff row aimed at the target.
  let reached =
    list.filter(rows, fn(row) {
      set.contains(routed, row.spell_id)
      && outcome_of(tables:, effect: row) == "applied"
      && case activate.planned_of(activations:, spell4_id: row.spell_id) {
        Ok(activate.Planned(..)) -> True
        Ok(activate.CannotBePlanned(..))
        | Ok(activate.NoSpell4Row)
        | Error(Nil) -> False
      }
    })
    |> list.map(fn(row) { #(row.data_bits00, row.data_bits01) })
    |> set.from_list
  // The visible, required, marked objectives of type 5 that no creature links and a type 42 row
  // names stay open until a cast advances them (`objective.NamedAction`).
  let named =
    quest2.all(tables)
    |> list.flat_map(fn(row) {
      case quest_log.quest_of(tables:, id: row.id) {
        Ok(quest) ->
          list.index_map(quest.objectives, fn(objective, index) {
            #(quest.id, index, objective)
          })
        Error(..) -> []
      }
    })
    |> list.filter(fn(found) {
      let #(quest_id, index, objective) = found
      objective_action.by_effect(tables:, quest_id:, index:)
      && objective.script_of(
        tables:,
        quest_id:,
        index:,
        objective:,
        arrival_objectives: set.new(),
        scripts: objective.no_rows(),
      )
      == objective.NamedAction
    })
  let #(with_a_route, without) =
    list.partition(named, fn(found) {
      set.contains(reached, #(found.0, found.1))
    })
  assert list.length(named) == 53
    as "53 visible, required, marked type 5 objectives no creature links are named by a type 42 row"
  assert list.length(with_a_route) == 12
    as "12 of them have a row of an activate spell of a creature or an item that the plan applies and the activate cast plans, so a cast that starts can finish them"
  assert without != []
    as "some named objective has no route, so the check below has objectives to hold"
  // The spells a player holds: every ability the server plans, with the spells its tree casts.
  let ability_spells =
    dict.values(spell_plan.plans_with_later(tables:))
    |> list.flat_map(spell_plan.tree(spell: _, started: fn(_) { True }))
    |> list.map(fn(spell) { spell.spell4_id.value })
    |> set.from_list
  list.each(without, fn(found) {
    let #(quest_id, index, objective) = found
    list.each(rows, fn(row) {
      case row.data_bits00 == quest_id && row.data_bits01 == index {
        True -> {
          assert !set.contains(ability_spells, row.spell_id)
            as {
              "QuestObjective "
              <> int.to_string(objective.objective_id)
              <> " is named by the row of Spell4 "
              <> int.to_string(row.spell_id)
              <> ", an ability a player holds, yet no cast of it can advance the objective"
            }
          Nil
        }
        False -> Nil
      }
    })
  })
}

/// An item's spell with a type 42 row and no Activate row (type 7) is castable when it plans
/// (`activate.planned_of`), and where it does not plan the refusal names a row of another type,
/// never a type 42 row: a type 42 row alone does not keep an item's cast from starting. The
/// client's own item check (`0x140398cc0`) runs before the spell and refuses what it refuses.
pub fn an_item_spell_with_a_type_42_row_and_no_activate_row_is_planned_or_refused_for_another_type_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let activations = activate.activations(tables:)
  let rows = type_42_rows(tables:)
  let with_a_row = set.from_list(list.map(rows, fn(row) { row.spell_id }))
  let outcomes =
    item_property.spells_on_activate(tables:)
    |> list.filter(fn(spell4_id) {
      set.contains(with_a_row, spell4_id)
      && !list.any(spell_plan.effects_of(sources:, spell4_id:), fn(effect) {
        effect.effect_type == 7
      })
    })
    |> list.map(fn(spell4_id) {
      case activate.planned_of(activations:, spell4_id:) {
        Ok(activate.Planned(..)) -> True
        Ok(activate.CannotBePlanned(why:)) -> {
          assert !refused_for_a_type_42_row(why:, rows:, spell4_id:)
            as {
              "Spell4 "
              <> int.to_string(spell4_id)
              <> " is refused for a type 42 row: "
              <> why
            }
          False
        }
        Ok(activate.NoSpell4Row) | Error(Nil) ->
          panic as {
            "the item spell "
            <> int.to_string(spell4_id)
            <> " is not among the activate spells the load plans"
          }
      }
    })
  assert list.any(outcomes, fn(planned) { planned })
    as "an item spell holds a type 42 row and no Activate row, and plans"
}
