//// Whether the plan reads a Spell4Effects row, which the effect measure counts rows by and
//// the use of an item's spell is judged by.
////
//// ```
//// Spell4Effects rows ─▶ spell_plan.read_row (the plan's own decision, in the place the
////                         row's spell is planned) ─▶ Applied: read
////                                                  ─▶ Held, LeftOut or an error: not read
////                       a damage row ─▶ spell_area.damage_row_of (the area load's own)
////                       a UnitStateSet row the plan applies ─▶ `unit_state_refuses`
//// a spell's tree ─▶ `first_unplayed`: the first row of it no item's cast plays
//// ```
////
//// - A row is read exactly when a list of the plan holds it and a go applies it, or, for a
////   damage row, when the area load builds it and it strikes a unit but its caster
////   (`spell_area.strikes_past_caster`); the callers use the functions the load calls and
////   restate none of their rules.
//// - A UnitStateSet row the plan applies is read only when what it holds can refuse a cast
////   or a strike: its state has a reading (`unit_state.reading_of`), it has a duration, and
////   its spell has a Spell4 row to be cast from. The other rows are held where they can be
////   and counted not read, each by a reason the type's gap names.
//// - A spell the plan refuses for a column of its own (a cost, a requirement, a cycle) is
////   not refused here: each of its rows is counted by its own columns. A row a Proxy or Proc
////   names is counted on the child's rows.
//// - The place of a row is worked out from the rows given: the spells a Proxy among them
////   starts on each struck unit, whether a spell's costs spend every point held, and whether
////   a spell's own rows hit foes.
//// - An item's cast plays a row when the plan reads it and it is no Activate row (the
////   right-click of a unit), holds no suspend prerequisite (a Prerequisite the server does
////   not read gates when the row works).

import genesis_prime/game/effect_kind
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/unit_state
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set

/// Where each spell of these rows is planned, by the spell's Spell4 id: whether a Proxy
/// among the rows starts it on each struck unit, whether its costs spend every point held, and
/// whether its own rows hit foes and whether they throw the units they strike.
pub fn places(
  tables tables: store.Tables,
  effects effects: List(Spell4Effects),
) -> fn(Int) -> spell_plan.RowPlace {
  let struck = spell_plan.struck_unit_children(effects:)
  let spends = spends_all_by_spell(tables:, effects:)
  let hitting = spell_plan.spells_that_hit_foes(effects:)
  let throwing = spell_plan.spells_that_throw_target(effects:)
  fn(spell4_id) {
    spell_plan.RowPlace(
      struck_by: option.from_result(dict.get(struck, spell4_id)),
      spends_all: result.unwrap(dict.get(spends, spell4_id), False),
      hits_foes: set.contains(hitting, spell4_id),
      throws_target: set.contains(throwing, spell4_id),
    )
  }
}

/// Whether the plan reads this row in this place: its list holds it and a go applies it,
/// or the area load builds it.
pub fn is_read(
  tables tables: store.Tables,
  sources sources: spell_plan.Sources,
  place place: spell_plan.RowPlace,
  effect effect: Spell4Effects,
) -> Bool {
  case spell_plan.read_row(tables:, sources:, place:, effect:) {
    Ok(spell_plan.Applied(..)) ->
      effect_kind.kind_of(effect_type: effect.effect_type)
      != effect_kind.UnitState
      || unit_state_refuses(tables:, effect:)
    Ok(spell_plan.ReadByActivation) -> True
    Ok(spell_plan.ReadByArea) ->
      case
        spell_area.damage_row_of(tables:, spell4_id: effect.spell_id, effect:)
      {
        Ok(row) -> spell_area.strikes_past_caster(row:)
        Error(..) -> False
      }
    Ok(spell_plan.Held(..)) | Ok(spell_plan.LeftOut(..)) | Error(..) -> False
  }
}

/// The reason an item's cast of `spell` does not play the first row of its tree that it
/// cannot, naming the row and its type, or `None` when it plays every row of it. `place_of`
/// is `places` of every row of the tables.
pub fn first_unplayed(
  tables tables: store.Tables,
  sources sources: spell_plan.Sources,
  place_of place_of: fn(Int) -> spell_plan.RowPlace,
  spell spell: spell_plan.Spell,
) -> Option(String) {
  spell_plan.tree(spell:, started: fn(_) { True })
  |> list.flat_map(fn(below) {
    spell_plan.effects_of(sources:, spell4_id: below.spell4_id.value)
  })
  |> list.find_map(fn(effect) {
    case unplayed_why(tables:, sources:, place_of:, effect:) {
      Some(why) -> Ok(why)
      None -> Error(Nil)
    }
  })
  |> option.from_result
}

fn unplayed_why(
  tables tables: store.Tables,
  sources sources: spell_plan.Sources,
  place_of place_of: fn(Int) -> spell_plan.RowPlace,
  effect effect: Spell4Effects,
) -> Option(String) {
  let row =
    "the row "
    <> int.to_string(effect.id)
    <> " (type "
    <> int.to_string(effect.effect_type)
    <> ")"
  let suspend = effect.prerequisite_id_target_suspend
  let is_activate =
    effect_kind.kind_of(effect_type: effect.effect_type) == effect_kind.Activate
  case is_read(tables:, sources:, place: place_of(effect.spell_id), effect:) {
    False -> Some(row <> " is not read by any rule")
    True if is_activate ->
      Some(row <> " is an Activate row, which an item does not play")
    True if suspend != 0 ->
      Some(
        row
        <> " holds the suspend prerequisite "
        <> int.to_string(suspend)
        <> ", which the server does not read",
      )
    True -> None
  }
}

/// Whether the state a UnitStateSet row holds can refuse anything: it has a reading
/// (`unit_state.reading_of`), a duration (a row with none is never held), and a spell with a
/// Spell4 row, which a cast needs.
fn unit_state_refuses(
  tables tables: store.Tables,
  effect effect: Spell4Effects,
) -> Bool {
  unit_state.reading_of(state: effect.data_bits00) != unit_state.NoReading
  && effect.duration_time > 0
  && result.is_ok(spell4.get(tables:, id: Spell4Id(effect.spell_id)))
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
            dict.insert(found, effect.spell_id, spell_plan.spends_all(row:))
          Error(Nil) -> found
        }
    }
  })
}
