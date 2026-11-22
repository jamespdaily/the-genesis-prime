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
//// - This module imports only the generated tables and their store, so any game module can
////   name a kind.

import genesis_prime/table/id.{type Spell4BaseId, Spell4TargetMechanicsId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_base.{type Spell4Base}
import genesis_prime/table/spell4_target_mechanics.{type Spell4TargetMechanics}
import gleam/int

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

/// The row of the two a spell's target mechanic is read from that the tables lack.
pub type MissingRow {
  /// The Spell4Base row of the id.
  NoBaseRow(id: Int)
  /// The Spell4TargetMechanics row the Spell4Base row names.
  NoTargetMechanicsRow(id: Int)
}

/// The Spell4Base row and the Spell4TargetMechanics row it names, or the one the tables
/// lack.
pub fn rows_of_base(
  tables tables: table_store.Tables,
  base_id base_id: Spell4BaseId,
) -> Result(#(Spell4Base, Spell4TargetMechanics), MissingRow) {
  case spell4_base.get(tables:, id: base_id) {
    Error(Nil) -> Error(NoBaseRow(id: base_id.value))
    Ok(base) ->
      case
        spell4_target_mechanics.get(
          tables:,
          id: Spell4TargetMechanicsId(base.spell4_target_mechanic_id),
        )
      {
        Error(Nil) ->
          Error(NoTargetMechanicsRow(id: base.spell4_target_mechanic_id))
        Ok(mechanics) -> Ok(#(base, mechanics))
      }
  }
}

/// Whether a spell whose target mechanic holds these flags is beneficial: flags bit 0
/// (`Spell4TargetMechanics.flags`) is the client's hostile-or-beneficial split of a spell,
/// the bit its buff list keeps a beneficial one by (`Unit.GetBuffs`) and its faction test
/// reads for a cast at another unit.
pub fn is_beneficial(flags flags: Int) -> Bool {
  int.bitwise_and(flags, 1) == 1
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
