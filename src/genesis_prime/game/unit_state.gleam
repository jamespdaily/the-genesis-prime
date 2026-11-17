//// The unit states a spell holds on a creature (`Spell4Effects.effectType.15`, a UnitStateSet
//// row), and what each refuses of a cast.
////
//// ```
//// cast.went ─▶ cast/control `unit_states_told`: one `Row` per row of the go
//// creature (world_map/creature_unit_state) holds each `Row` until its end
//// press (0x9d) at the creature ─▶ `cast_refusal` over the states the picture shows ─▶ 0x7fc
//// ```
////
//// - A state is held on a creature and is a number 0 to 23 (`Spell4Effects.dataBits00`); the
////   client reads no row of this type, so a held state shows only through the cast results
////   the server gives (`Spell.CodeEnumCastResult.306_308`).
//// - What each state means is not in the client: the readings of `reading_of` are guesses
////   from the spell names that hold them.
//// - A spell is hostile or beneficial by one bit of its target mechanics, which the client
////   itself tests when it checks a unit's immunity (`Spell4TargetMechanics.flags` bit 0).

import genesis_prime/message/cast_result
import gleam/list
import gleam/option.{type Option, None, Some}

/// One UnitStateSet row of a cast, as the creature holds it: the state `dataBits00` names, the
/// row's `delayTime` and `durationTime` in milliseconds. The state is held from the go plus
/// the delay for the duration, so it blocks and shows from its start only (a server guess:
/// the client reads no row of the type). A row with no duration is never held.
pub type Row {
  Row(state: Int, delay_ms: Int, duration_ms: Int)
}

/// What a held state refuses of a cast.
pub type Reading {
  /// The unit takes no hostile cast: result 306.
  Invulnerable
  /// The unit takes no beneficial cast: result 308.
  ImmuneToBeneficial
  /// The state is held and refuses nothing: its meaning is not known.
  NoReading
}

/// The reading of a state number, a guess from the names of the spells that hold it, which the
/// client does not state (`Spell4Effects.effectType.15`): 6, 7 to 9, 13 to 18, 22 and 3 to 5
/// are invulnerable (spells named "Invulnerability", "Makes the recipient immune to ALL
/// spells" and "Hostile Invulnerability"), 19 is immune to beneficial casts ("Immune
/// (Beneficial)"), and 1 (Block), 0, 2, 10, 23 and every other number hold no reading.
pub fn reading_of(state state: Int) -> Reading {
  case state {
    3 | 4 | 5 | 6 | 7 | 8 | 9 | 13 | 14 | 15 | 16 | 17 | 18 | 22 -> Invulnerable
    19 -> ImmuneToBeneficial
    _ -> NoReading
  }
}

/// Whether any of the held states makes the unit take no hostile cast and no strike with
/// blows or states.
pub fn blocks_hostile(held held: List(Int)) -> Bool {
  list.any(held, fn(state) { reading_of(state:) == Invulnerable })
}

/// The result a cast gets at a unit that holds `held`: 306 for a hostile cast and a held
/// `Invulnerable`, 308 for a beneficial cast and a held `ImmuneToBeneficial`, and none
/// otherwise.
pub fn cast_refusal(
  held held: List(Int),
  beneficial beneficial: Bool,
) -> Option(cast_result.CastResult) {
  let readings = list.map(held, fn(state) { reading_of(state:) })
  case beneficial {
    False ->
      case list.contains(readings, Invulnerable) {
        True -> Some(cast_result.TargetHostileInvulnerability)
        False -> None
      }
    True ->
      case list.contains(readings, ImmuneToBeneficial) {
        True -> Some(cast_result.TargetBeneficialInvulnerability)
        False -> None
      }
  }
}
