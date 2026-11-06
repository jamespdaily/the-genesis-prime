//// Whether a Proxy's gate can open for a level-1 character, which decides whether
//// the coverage measure counts the Proxy's child (genesis_prime/coverage/starting_ability).
////
//// ```
//// Proxy ─▶ its gate prerequisites (caster apply, dataBits06)
////   ─▶ each kept condition: closed, or open as far as the measure can tell
////   ─▶ the row: AND closed when any condition is, OR closed when every one is
////   ─▶ the Proxy: closed when either gate row is
//// ```
////
//// - **A level-1 character** is a unit at level 1: a new unit starts there
////   (`0x1404543c1`).
//// - **Type 15 or 50, comparison 1** needs a live cast of the Spell4 in the
////   condition's value on the unit (`Prerequisite.prerequisiteTypeId.15`,
////   `Prerequisite.prerequisiteTypeId.50`). When that Spell4 is the spell of an AMP
////   (`EldanAugmentation.spell4IdAugment`) and AMPs are offered at a level above 1
////   (`LevelUpUnlock` row 26, `LevelUpUnlock.level`), a level-1 character holds no
////   such cast: the gate is closed. Comparison 2 asks that no such cast exist, which
////   holds.
//// - **Type 1** compares the unit's level for formulas with the condition's value
////   (`0x1404a2100` case 1 reads the two words `0x1403b5030` reads) by the
////   comparison's relation (`0x1404a2090`); a condition level 1 fails is closed.
//// - **Any other condition** is open: the measure has no evidence that it cannot
////   pass at level 1.

import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Proxy}
import genesis_prime/table/eldan_augmentation
import genesis_prime/table/id.{LevelUpUnlockId}
import genesis_prime/table/level_up_unlock
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The level of a new character.
const starting_level = 1

/// The LevelUpUnlock row that offers the AMP system: its `level` is the level
/// from which AMPs can be held.
pub const amp_unlock_id = 26

/// What decides the gates: the spell of each AMP and the level AMPs are offered at.
pub opaque type Gates {
  Gates(amps: Dict(Int, Int), amp_level: Int)
}

/// Why a gate cannot open for a level-1 character.
pub type Closed {
  /// A condition of type 15 or 50 that needs a live cast of the spell of an AMP
  /// (an EldanAugmentation row), which is offered from `level`.
  NeedsAmp(spell4_id: Int, eldan_augmentation_id: Int, level: Int)
  /// A condition of type 1 whose comparison a level-1 character fails.
  FailsAtLevelOne(comparison: Int, value: Int)
}

/// The gates' evidence: each AMP's spell with its EldanAugmentation id, and the
/// level AMPs are offered from.
pub fn gates(amps amps: List(#(Int, Int)), amp_level amp_level: Int) -> Gates {
  Gates(amps: dict.from_list(list.reverse(amps)), amp_level:)
}

/// The AMPs' spells and the AMP unlock's level, read from the tables; an error
/// when the table has no AMP unlock row.
pub fn load(tables tables: store.Tables) -> Result(Gates, Nil) {
  use unlock <- result.map(level_up_unlock.get(
    tables:,
    id: LevelUpUnlockId(amp_unlock_id),
  ))
  gates(
    amps: list.map(eldan_augmentation.all(tables), fn(row) {
      #(row.spell4_id_augment, row.id)
    }),
    amp_level: unlock.level,
  )
}

/// The gate prerequisite that keeps a level-1 character from starting the Proxy,
/// with why, or an error when the Proxy can start. Only a gate on the caster is
/// read; a gate on the target, which the plan does not check, leaves the Proxy
/// counted.
pub fn closed_by(
  gates gates: Gates,
  tables tables: store.Tables,
  proxy proxy: Proxy,
) -> Result(#(Int, Closed), Nil) {
  case proxy.condition {
    spell_plan.GatedOnCaster(gates: prerequisites) ->
      list.find_map(prerequisites, fn(prerequisite) {
        let prerequisite_id = prerequisite.id(prerequisite)
        use row <- result.try(prerequisite_table.get(
          tables:,
          id: prerequisite_id,
        ))
        row_closed(gates:, row:)
        |> result.map(fn(why) { #(prerequisite_id.value, why) })
      })
    spell_plan.Always | spell_plan.GatedOnTarget(..) -> Error(Nil)
  }
}

/// Why the row cannot pass for a level-1 character: under AND the first condition
/// that cannot, under OR only when none can.
pub fn row_closed(
  gates gates: Gates,
  row row: prerequisite_table.Prerequisite,
) -> Result(Closed, Nil) {
  let verdicts =
    list.map(prerequisite.kept_conditions(row:), fn(condition) {
      condition_closed(gates:, condition:)
    })
  case prerequisite.is_any(row:) {
    False -> list.find_map(verdicts, fn(verdict) { verdict })
    True -> result.try(result.all(verdicts), list.first)
  }
}

fn condition_closed(
  gates gates: Gates,
  condition condition: #(Int, Int, Int, Int),
) -> Result(Closed, Nil) {
  let #(type_id, comparison, _object_id, value) = condition
  case type_id, comparison {
    15, 1 | 50, 1 -> {
      use eldan_augmentation_id <- result.try(dict.get(gates.amps, value))
      case gates.amp_level > starting_level {
        True ->
          Ok(NeedsAmp(
            spell4_id: value,
            eldan_augmentation_id:,
            level: gates.amp_level,
          ))
        False -> Error(Nil)
      }
    }
    1, _ ->
      case
        prerequisite.compare(
          relation: prerequisite.relation_of(code: comparison),
          measured: starting_level,
          value:,
        )
      {
        True -> Error(Nil)
        False -> Ok(FailsAtLevelOne(comparison:, value:))
      }
    _, _ -> Error(Nil)
  }
}

/// A sentence for the gate prerequisite and why it cannot open.
pub fn describe(gate gate: Int, closed closed: Closed) -> String {
  let prefix = "its gate Prerequisite " <> int.to_string(gate)
  case closed {
    NeedsAmp(spell4_id:, eldan_augmentation_id:, level:) ->
      prefix
      <> " needs a cast of Spell4 "
      <> int.to_string(spell4_id)
      <> ", the spell of EldanAugmentation "
      <> int.to_string(eldan_augmentation_id)
      <> ", an AMP offered at level "
      <> int.to_string(level)
      <> " (LevelUpUnlock "
      <> int.to_string(amp_unlock_id)
      <> "), which a level-1 character does not hold"
    FailsAtLevelOne(comparison:, value:) ->
      prefix
      <> " holds a level condition "
      <> case comparison {
        1 | 4 -> "that needs level " <> int.to_string(value)
        3 -> "that needs level " <> int.to_string(value + 1)
        _ ->
          "(comparison "
          <> int.to_string(comparison)
          <> ", value "
          <> int.to_string(value)
          <> ") that level 1 fails"
      }
  }
}
