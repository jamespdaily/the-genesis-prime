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
//// - **No spend.** A spell whose Spell4 row holds an innate cost EMM id spends and
////   chooses its effects by the points spent (genesis_prime/game/spend), which a
////   creature's attack has none of, so the load refuses it
////   (`Spell4.innateCostEMMId0`).
//// - **The client applies no effect itself**: the server names the effect in
////   0x7f4, so the server follows the table's prerequisite (`Spell4Effects.184741`).

import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite as game_prerequisite
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

/// The prerequisite type of the unit's difficulty (`0x14049eeb0`).
const difficulty_type = 179

/// Why a damage effect's caster prerequisite is not one the server evaluates.
pub type Unevaluated {
  /// The prerequisite row is missing from the client's table.
  NoPrerequisiteRow(spell4_effects_id: Int, prerequisite_id: Int)
  /// The prerequisite's condition is of a type other than 179, or it holds more
  /// than one condition.
  OtherType(spell4_effects_id: Int, prerequisite_id: Int, type_id: Int)
  /// The prerequisite nests itself through the rows it nests (type 11): the ids from the
  /// named row to the one that repeats.
  NestedCycle(spell4_effects_id: Int, path: List(Int))
  /// The prerequisite nests a row with a type 108 condition naming a PositionalRequirement
  /// row the client's table lacks.
  NoPositionalRequirementRow(
    spell4_effects_id: Int,
    positional_requirement_id: Int,
  )
  /// The spell's Spell4 row holds an innate cost EMM id, which would choose its
  /// damage effects by points a creature's attack does not spend.
  SpendsByEmmId(spell4_id: Int, emm_id: Int)
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

/// An innate cost EMM id of the spell's Spell4 row, a spend a creature's attack
/// cannot make; `Ok(Nil)` for a spell with none or with no Spell4 row.
fn spends_nothing(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> Ok(Nil)
    Ok(row) ->
      case
        list.find(
          [row.innate_cost_emm_id0, row.innate_cost_emm_id1],
          fn(emm_id) { emm_id != 0 },
        )
      {
        Ok(emm_id) -> Error(SpendsByEmmId(spell4_id:, emm_id:))
        Error(Nil) -> Ok(Nil)
      }
  }
}

/// The first reason the spell is not one the server applies to a creature: an
/// innate cost EMM id, or a damage effect whose caster prerequisite it does not
/// evaluate; `Ok(Nil)` when there is none.
pub fn evaluated(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unevaluated) {
  use Nil <- result.try(spends_nothing(tables:, spell4_id:))
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
        [type_id] if type_id == difficulty_type -> loaded(tables:, effect:, id:)
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

/// The prerequisite with its nested rows loaded from the client's tables.
fn loaded(
  tables tables: table_store.Tables,
  effect effect: Spell4Effects,
  id id: Int,
) -> Result(Condition, Unevaluated) {
  game_prerequisite.load(
    id: PrerequisiteId(id),
    rows: game_prerequisite.table_rows(tables:),
    arcs: game_prerequisite.table_arcs(tables:),
  )
  |> result.map(fn(loaded) { Gated(prerequisite: loaded) })
  |> result.map_error(fn(error) {
    case error {
      game_prerequisite.NoPrerequisiteRow(..) ->
        NoPrerequisiteRow(spell4_effects_id: effect.id, prerequisite_id: id)
      game_prerequisite.PrerequisiteCycle(path:) ->
        NestedCycle(
          spell4_effects_id: effect.id,
          path: list.map(path, fn(on_the_way) { on_the_way.value }),
        )
      game_prerequisite.NoPositionalRequirementRow(id: arc_id) ->
        NoPositionalRequirementRow(
          spell4_effects_id: effect.id,
          positional_requirement_id: arc_id,
        )
    }
  })
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
    NestedCycle(spell4_effects_id:, path:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has a caster prerequisite whose rows nest each other round a cycle: "
      <> string.join(list.map(path, int.to_string), " to ")
    NoPositionalRequirementRow(spell4_effects_id:, positional_requirement_id:) ->
      "Spell4Effects "
      <> int.to_string(spell4_effects_id)
      <> " has a caster prerequisite with a type 108 condition naming PositionalRequirement "
      <> int.to_string(positional_requirement_id)
      <> ", which the client's table does not hold"
    SpendsByEmmId(spell4_id:, emm_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " has innate cost EMM id "
      <> int.to_string(emm_id)
      <> ", which chooses its effects by points a creature's attack does not spend"
  }
}
