//// The kind of a Spell4TargetMechanics row, decoded once from its `targetType`: the one
//// place the server names whom a spell is cast at. A rule that aims a spell matches on
//// `Kind`, so a new variant names every place that must handle it; a kind the client's
//// picker has no case for is `Unread`.
////
//// ```text
//// Spell4TargetMechanics row (targetType) -> kind_of / of_row -> Kind -> a rule's case
//// ```
////
//// - The client's picker takes the caster for kinds 0, 2, 6 and 7 and a target for 1, 3, 5
////   and 8 (`0x14055bdc0`, `Spell4TargetMechanics.targetType`, fairly sure); the client
////   gives the kinds no names.
//// - Kind 4 is placed on the ground: `CastAbilityBagSpell` sends 0x9b for it.
//// - This module imports only the generated tables, so any game module can name a kind.

import genesis_prime/table/spell4_target_mechanics.{type Spell4TargetMechanics}

/// Whom a spell of a target mechanic is cast at.
pub type Kind {
  /// Kinds 0, 2, 6 and 7: the caster, whatever the player has targeted.
  Caster
  /// Kinds 1, 3, 5 and 8: a unit the cast names.
  Targeted
  /// Kind 4: a place on the ground.
  Ground
  /// Any other kind: the client's picker has no case for it.
  Unread(target_type: Int)
}

/// The kind of a target mechanic of type `target_type` (`Spell4TargetMechanics.targetType`).
pub fn kind_of(target_type target_type: Int) -> Kind {
  case target_type {
    0 | 2 | 6 | 7 -> Caster
    1 | 3 | 5 | 8 -> Targeted
    4 -> Ground
    other -> Unread(target_type: other)
  }
}

/// The kind of a Spell4TargetMechanics row.
pub fn of_row(row: Spell4TargetMechanics) -> Kind {
  kind_of(target_type: row.target_type)
}

/// Whether a spell of the kind is cast at the caster, whatever the player has targeted.
pub fn takes_caster(kind: Kind) -> Bool {
  case kind {
    Caster -> True
    Targeted | Ground | Unread(..) -> False
  }
}

/// Whether a spell of the kind is cast at a unit the cast names (the player's target for
/// an item use).
pub fn takes_target(kind: Kind) -> Bool {
  case kind {
    Targeted -> True
    Caster | Ground | Unread(..) -> False
  }
}
