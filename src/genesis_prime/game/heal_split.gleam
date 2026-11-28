//// What a heal of a player's vital comes to: the amount after the heal multipliers,
//// the part the shield takes, the part the health takes and the part the vital had no
//// room for. The go (genesis_prime/game/cast/heal `healed_on`) tells the client this amount and
//// overheal, and the life (genesis_prime/game/player_life `healed`, `healed_by`) raises the
//// vital by the same split, so what the client shows is what the health does.
////
//// - The amount is the formula's value times HealingMultiplierOutgoing (162) and
////   HealingMultiplierIncoming (163), rounded half away from zero (`UnitProperty2`'s
////   damage_heal_multipliers); a heal of the player's own vital reads both from the
////   player.
//// - A health heal of a player whose HealToShieldConversion (111) is not 0 gives the
////   shield int(amount x property), up to the shield's room, and the health the rest
////   (`0x1405d8350`). The client shows that shield part as a second, HealShields event.
//// - The shield part of a health heal is also capped at the amount: the client lowers the
////   amount by int(amount x property) without that cap, so a share above 1 (modifiers add,
////   and Great Aegis with Reserve Power reaches 1.2) would wrap its unsigned health
////   figure. The cap is the server's guess from texts 530923 and 708902, which call the
////   share a part "of incoming healing".
//// - The overheal is the amount less what the shield and the health took, never below 0
////   (`spell.heal_result_log`).

import genesis_prime/gap
import genesis_prime/shared/effect_kind
import genesis_prime/shared/heal_parts.{type Split, Split}
import genesis_prime/shared/unit_properties.{type Properties}
import gleam/float
import gleam/int

/// The three properties a heal reads: the healer's outgoing multiplier, and the healed
/// player's incoming multiplier and heal-to-shield conversion.
pub type Scaling {
  Scaling(outgoing: Float, incoming: Float, to_shield: Float)
}

/// No multiplier and no conversion: the properties of a player with none of them set.
pub const unscaled = Scaling(outgoing: 1.0, incoming: 1.0, to_shield: 0.0)

/// What a heal of the player's own vital reads of its `properties`.
pub fn scaling_of(properties properties: Properties) -> Scaling {
  scaling_between(
    outgoing: unit_properties.value(
      properties:,
      property: unit_properties.healing_multiplier_outgoing,
    ),
    properties:,
  )
}

/// What a heal told by another player reads: the healer's HealingMultiplierOutgoing
/// (162) as `outgoing`, and the healed player's own HealingMultiplierIncoming (163) and
/// HealToShieldConversion (111) from its `properties`.
pub fn scaling_between(
  outgoing outgoing: Float,
  properties properties: Properties,
) -> Scaling {
  Scaling(
    outgoing:,
    incoming: unit_properties.value(
      properties:,
      property: unit_properties.healing_multiplier_incoming,
    ),
    to_shield: unit_properties.value(
      properties:,
      property: unit_properties.heal_to_shield_conversion,
    ),
  )
}

/// A heal of `vital` by the formula's `amount`, for a player whose health has
/// `health_room` below its maximum and whose shield has `shield_room`; a room below 0
/// counts as 0.
pub fn split(
  vital vital: effect_kind.Vital,
  amount amount: Int,
  scaling scaling: Scaling,
  health_room health_room: Int,
  shield_room shield_room: Int,
) -> Split {
  let amount =
    float.round(int.to_float(amount) *. scaling.outgoing *. scaling.incoming)
    |> int.max(0)
  let health_room = int.max(health_room, 0)
  let shield_room = int.max(shield_room, 0)
  case vital {
    effect_kind.Shield -> {
      let shield = int.min(amount, shield_room)
      Split(amount:, shield:, health: 0, overheal: amount - shield)
    }
    effect_kind.Health -> {
      let shield =
        float.truncate(int.to_float(amount) *. scaling.to_shield)
        |> int.min(shield_room)
        |> int.min(amount)
        |> int.max(0)
      let health = int.min(amount - shield, health_room)
      Split(amount:, shield:, health:, overheal: amount - shield - health)
    }
  }
}

/// What a heal's split does that the client's reader does not show.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Casting",
      missing: "A health heal whose HealToShieldConversion is above 1 gives the shield at most the heal's amount and the health 0, a server's guess because the client's reader wraps there; the client is still sent the property as computed, so its floater and combat log show the uncapped shield part and a health part below 0.",
    ),
  ]
}
