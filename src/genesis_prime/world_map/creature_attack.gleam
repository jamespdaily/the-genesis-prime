//// Which damage effects of a creature's attack spell apply to a creature, by each
//// effect's caster prerequisite: the one rule the content load (the creature kind's
//// check, genesis_prime/world_map/creature_kind, and the spawn's attack,
//// genesis_prime/world_map/spawn) reads them by.
////
//// ```
//// Spell4Effects of the spell, type 8 (Damage), in order
////   no caster prerequisite                       ─▶ applies
////   a prerequisite of type 179 (the difficulty)  ─▶ applies when the creature's difficulty passes it
////   a prerequisite of any other type             ─▶ the load refuses the spell (`unevaluated`)
//// ```
////
//// - **Type 179** compares the unit's difficulty with the condition's object id,
////   unsigned: 1 equal, 2 not equal, 3 above, 4 at least, 5 below, 6 at most
////   (`0x14049eeb0`, decoded and checked by genesis_prime/game/prerequisite). A
////   creature's difficulty is its Creature2 row's (`0x14045ba40`).
//// - **One condition is read.** Prerequisite rows hold three; a row that keeps
////   a second condition (the client keeps those before the first of type 0,
////   `0x1404a5190`) is not evaluated, and the load refuses it as an unevaluated type.
//// - **The client applies no effect itself**: the server names the effect in
////   0x7f4, so the server follows the table's prerequisite (`Spell4Effects.184741`).

import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite as game_prerequisite
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/int
import gleam/list
import gleam/order
import gleam/result

/// The prerequisite type of the unit's difficulty (`0x14049eeb0`).
const difficulty_type = 179

/// Why a damage effect's caster prerequisite is not one the server evaluates.
pub type Unevaluated {
  /// The prerequisite row is missing from the client's table.
  NoPrerequisiteRow(spell4_effects_id: Int, prerequisite_id: Int)
  /// The prerequisite's condition is of a type other than 179, or it holds more
  /// than one condition.
  OtherType(spell4_effects_id: Int, prerequisite_id: Int, type_id: Int)
}

/// The damage effects (type 8) of the spell, in the order they take effect
/// (`Spell4Effects.orderIndex`, then the row id).
fn damage_effects(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(Spell4Effects) {
  spell4_effects.all(tables)
  |> list.filter(fn(effect) {
    effect.spell_id == spell4_id
    && effect_kind.kind_of(effect.effect_type) == effect_kind.Damage
  })
  |> list.sort(fn(first, second) {
    int.compare(first.order_index, second.order_index)
    |> order.break_tie(int.compare(first.id, second.id))
  })
}

/// The first damage effect of the spell whose caster prerequisite the server does
/// not evaluate, or `Ok(Nil)` when it evaluates them all.
pub fn evaluated(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  damage_effects(tables:, spell4_id:)
  |> list.try_each(fn(effect) {
    condition(tables:, effect:) |> result.replace(Nil)
  })
}

/// The damage effects of the spell that apply to a creature of `difficulty`.
pub fn applying(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  difficulty difficulty: Int,
) -> Result(List(Spell4Effects), Unevaluated) {
  damage_effects(tables:, spell4_id:)
  |> list.try_fold([], fn(applying, effect) {
    use found <- result.try(condition(tables:, effect:))
    case found {
      Unconditional -> Ok([effect, ..applying])
      Gated(prerequisite:) ->
        case
          game_prerequisite.check(
            prerequisite:,
            subject: game_prerequisite.of_difficulty(difficulty:),
          )
        {
          game_prerequisite.Passes -> Ok([effect, ..applying])
          game_prerequisite.Fails -> Ok(applying)
          game_prerequisite.NotRead(prerequisite_type:) ->
            Error(OtherType(
              spell4_effects_id: effect.id,
              prerequisite_id: game_prerequisite.id(prerequisite:).value,
              type_id: prerequisite_type,
            ))
        }
    }
  })
  |> result.map(list.reverse)
}

/// An effect's caster prerequisite as the server evaluates it.
type Condition {
  Unconditional
  /// A row whose one kept condition is of type 179.
  Gated(prerequisite: game_prerequisite.Prerequisite)
}

fn condition(
  tables tables: table_store.Tables,
  effect effect: Spell4Effects,
) -> Result(Condition, Unevaluated) {
  case effect.prerequisite_id_caster_apply {
    0 -> Ok(Unconditional)
    id -> {
      use row <- result.try(
        prerequisite.get(tables, PrerequisiteId(id))
        |> result.replace_error(NoPrerequisiteRow(
          spell4_effects_id: effect.id,
          prerequisite_id: id,
        )),
      )
      case game_prerequisite.condition_types(row:) {
        [type_id] if type_id == difficulty_type ->
          Ok(Gated(prerequisite: game_prerequisite.of_row(row:)))
        [type_id, ..] ->
          Error(OtherType(
            spell4_effects_id: effect.id,
            prerequisite_id: id,
            type_id:,
          ))
        [] ->
          Error(OtherType(
            spell4_effects_id: effect.id,
            prerequisite_id: id,
            type_id: 0,
          ))
      }
    }
  }
}

/// A sentence for the load's refusal.
pub fn describe(unevaluated unevaluated: Unevaluated) -> String {
  case unevaluated {
    NoPrerequisiteRow(spell4_effects_id:, prerequisite_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " names caster prerequisite "
      <> int.to_string(prerequisite_id)
      <> ", which the client's Prerequisite table does not hold"
    OtherType(spell4_effects_id:, prerequisite_id:, type_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has caster prerequisite "
      <> int.to_string(prerequisite_id)
      <> " of type "
      <> int.to_string(type_id)
      <> ", which the server does not evaluate (only one condition of type 179, the difficulty)"
  }
}
