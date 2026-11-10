//// Whether the plan reads a Spell4Effects row, which the effect measure counts rows by.
////
//// ```
//// Spell4Effects rows ─▶ spell_plan.read_row (the plan's own decision, in the place the
////                         row's spell is planned) ─▶ Applied: read
////                                                  ─▶ Held, LeftOut or an error: not read
////                       a damage row ─▶ spell_area.damage_row_of (the area load's own)
//// ```
////
//// - A row is read exactly when a list of the plan holds it and a go applies it, or, for a
////   damage row, when the area load builds it; the measure calls the functions the load
////   calls and restates none of their rules.
//// - A spell the plan refuses for a column of its own (a cost, a requirement, a cycle) is
////   not refused here: each of its rows is counted by its own columns. A row a Proxy or Proc
////   names is counted on the child's rows.
//// - The place of a row is worked out from the rows given: the spells a Proxy among them
////   starts on each struck unit, and whether a spell's costs spend every point held.

import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result
import gleam/set.{type Set}

/// How many of these rows the plan does not read, by effect type. A type with no such row
/// has no entry.
pub fn unread_by_type(
  tables tables: store.Tables,
  effects effects: List(Spell4Effects),
) -> Dict(Int, Int) {
  let spell_groups = spell_plan.spell_groups(tables:)
  let place_of = places(tables:, effects:)
  list.fold(effects, dict.new(), fn(counts, effect) {
    case
      is_read(tables:, spell_groups:, place: place_of(effect.spell_id), effect:)
    {
      True -> counts
      False ->
        dict.upsert(counts, effect.effect_type, fn(found) {
          option.unwrap(found, 0) + 1
        })
    }
  })
}

/// Where each spell of these rows is planned, by the spell's Spell4 id: whether a Proxy
/// among the rows starts it on each struck unit, and whether its costs spend every point held.
pub fn places(
  tables tables: store.Tables,
  effects effects: List(Spell4Effects),
) -> fn(Int) -> spell_plan.RowPlace {
  let struck = spell_plan.struck_unit_children(effects:)
  let spends = spends_all_by_spell(tables:, effects:)
  fn(spell4_id) {
    spell_plan.RowPlace(
      struck_by: option.from_result(dict.get(struck, spell4_id)),
      spends_all: result.unwrap(dict.get(spends, spell4_id), False),
    )
  }
}

/// Whether the plan reads this row in this place: its list holds it and a go applies it,
/// or the area load builds it.
pub fn is_read(
  tables tables: store.Tables,
  spell_groups spell_groups: Set(Int),
  place place: spell_plan.RowPlace,
  effect effect: Spell4Effects,
) -> Bool {
  case spell_plan.read_row(tables:, spell_groups:, place:, effect:) {
    Ok(spell_plan.Applied(..)) | Ok(spell_plan.ReadByActivation) -> True
    Ok(spell_plan.ReadByArea) ->
      result.is_ok(spell_area.damage_row_of(spell4_id: effect.spell_id, effect:))
    Ok(spell_plan.Held(..)) | Ok(spell_plan.LeftOut(..)) | Error(..) -> False
  }
}

/// Whether each spell of these rows spends every point held, by its Spell4 row's costs.
fn spends_all_by_spell(
  tables tables: store.Tables,
  effects effects: List(Spell4Effects),
) -> Dict(Int, Bool) {
  list.fold(effects, dict.new(), fn(found, effect) {
    case dict.has_key(found, effect.spell_id) {
      True -> found
      False ->
        case spell4.get(tables:, id: Spell4Id(effect.spell_id)) {
          Ok(row) ->
            dict.insert(
              found,
              effect.spell_id,
              spell_plan.spends_all(tables:, row:),
            )
          Error(Nil) -> found
        }
    }
  })
}
