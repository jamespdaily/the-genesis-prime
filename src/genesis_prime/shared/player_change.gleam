//// What a caster's connection tells the connection of another player about a cast's
//// change on it: the change, how it keeps when its caster leaves sight, and the tell
//// itself, which the map relays (genesis_prime/game/held_changes keeps what each unit holds).

import genesis_prime/shared/spell_plan
import genesis_prime/shared/unit_casts
import genesis_prime/shared/unit_properties.{type Source}
import genesis_prime/table/id.{type Spell4Id}
import genesis_prime/world_map/unit_address.{type UnitAddress}

/// What a caster's cast changes on a player that is not the caster, as it is told: a
/// property modifier (the UnitPropertyModifier and UnitPropertyConversion rows, and the
/// Proxy-started Interrupt Armor's property), or an absorb pool (an Absorption row) of
/// `amount`, as the caster's formula gave it at the go, that takes the damage types of
/// `mask`.
pub type Change {
  Property(modifier: unit_properties.Modifier)
  Absorb(amount: Int, mask: Int)
}

/// What a start tells a player: a change it applies to itself, or the event of a Proc row
/// the caster holds on it, which changes nothing the player has and is listed in its create
/// as the cast's effect on it. A caster's own change is only ever a `Change`, so it cannot
/// hold a Proc row that applies nothing.
pub type Told {
  /// The player applies `change` and holds it for the caster.
  Applies(change: Change)
  /// The player applies nothing and keeps the source for the caster, which waits for the
  /// event `trigger`.
  Awaits(trigger: spell_plan.Trigger)
}

/// Whether a held change ends when its caster leaves the sight of the unit that holds it.
pub type Sight {
  /// The change ends when the caster is no longer seen: the spell's Spell4 propertyFlags
  /// do not hold 0x100.
  EndsWhenUnseen
  /// The change outlives its caster's sight: the spell's propertyFlags hold 0x100. It ends
  /// by the caster's end tell, or by the caster's unit gone.
  KeptWhenUnseen
}

/// What a caster's connection tells the connection of another player, sent to that
/// player's unit (genesis_prime/client_connection `PlayerTell.Change`).
pub type PlayerChange {
  /// The change `change` of the cast `source` names is put on the player. `from` is the
  /// caster's unit, which the player holds the change
  /// against: the player takes it only while that caster is among its viewers.
  PlayerChangeStarts(
    from: UnitAddress,
    source: Source,
    change: Told,
    sight: Sight,
    spell4_id: Spell4Id,
    effect: unit_casts.HeldEffect,
  )
  /// The cast's node on the player has ended: the change of `source` that `from` started
  /// is taken off.
  PlayerChangeEnds(from: UnitAddress, source: Source)
  /// The go of the cast `cast_id` that `from` started has told the player each of its
  /// changes: the player starts the cast for its viewers, from what it holds of the
  /// cast. The guard is the ledger's (`holds_cast_from`).
  PlayerCastWent(from: UnitAddress, cast_id: Int)
}
