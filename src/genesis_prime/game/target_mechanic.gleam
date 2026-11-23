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

import genesis_prime/table/id.{
  type Spell4BaseId, Spell4TargetMechanicsId, Spell4ValidTargetsId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_base.{type Spell4Base}
import genesis_prime/table/spell4_target_mechanics.{type Spell4TargetMechanics}
import genesis_prime/table/spell4_valid_targets
import gleam/int
import gleam/result

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

/// Whether the client tests a spell of this target mechanic type for the target being the
/// caster's pet or master (`Spell4Base.targetingFlags` bits 2 and 3, results 255 and 256):
/// not for types 2, 3, 4, 7 and 8 (`CheckCastTarget` `0x1403b0880`, which skips them when
/// `(type - 2) <= 2` or `(type - 7) <= 1`). The kinds cannot say it: each of 2 and 7 shares
/// its kind with a type that is tested.
pub fn tests_pet_bits(target_type target_type: Int) -> Bool {
  case target_type {
    2 | 3 | 4 | 7 | 8 -> False
    _ -> True
  }
}

/// The kind of a Spell4TargetMechanics row.
pub fn of_row(row: Spell4TargetMechanics) -> Kind {
  kind_of(target_type: row.target_type)
}

/// What a spell's target rows say of whom it may be cast at: the kind of its
/// Spell4TargetMechanics row, that row's `flags` (bit 0 beneficial, bit 1 the caster may
/// be its own primary target) and the `targetBitmask` of its Spell4ValidTargets row, 0 for a
/// spell that names none (bit 0 refuses a player).
pub type Targeting {
  Targeting(kind: Kind, mechanics_flags: Int, valid_targets: Int)
}

/// The targeting of a spell that is cast at its caster and refuses nothing.
pub const at_the_caster =
  Targeting(kind: Caster, mechanics_flags: 0, valid_targets: 0)

/// A row a spell's targeting is read from that the tables lack.
pub type TargetingError {
  /// The Spell4Base row or its Spell4TargetMechanics row.
  NoMechanicsRow(missing: MissingRow)
  /// The Spell4ValidTargets row the Spell4Base row names.
  NoValidTargetsRow(id: Int)
}

/// The targeting of the spell whose Spell4Base is `base_id`, or the row the tables lack.
pub fn targeting_of(
  tables tables: table_store.Tables,
  base_id base_id: Spell4BaseId,
) -> Result(Targeting, TargetingError) {
  use #(base, mechanics) <- result.try(
    rows_of_base(tables:, base_id:) |> result.map_error(NoMechanicsRow),
  )
  targeting_of_rows(tables:, base:, mechanics:)
}

/// The targeting of a spell from its Spell4Base row and the Spell4TargetMechanics row that
/// row names; the only row it can find missing is the Spell4ValidTargets row
/// (`NoValidTargetsRow`).
pub fn targeting_of_rows(
  tables tables: table_store.Tables,
  base base: Spell4Base,
  mechanics mechanics: Spell4TargetMechanics,
) -> Result(Targeting, TargetingError) {
  use valid_targets <- result.map(case base.spell4_valid_target_id {
    0 -> Ok(0)
    valid_id ->
      spell4_valid_targets.get(tables:, id: Spell4ValidTargetsId(valid_id))
      |> result.map(fn(valid) { valid.target_bitmask })
      |> result.replace_error(NoValidTargetsRow(id: valid_id))
  })
  Targeting(
    kind: of_row(mechanics),
    mechanics_flags: mechanics.flags,
    valid_targets:,
  )
}

/// The table and id of the row a spell's targeting could not be read for: the one place
/// that says which table each missing row belongs to.
pub fn missing_targeting_row(error error: TargetingError) -> #(String, Int) {
  case error {
    NoMechanicsRow(missing: NoBaseRow(id:)) -> #("Spell4Base", id)
    NoMechanicsRow(missing: NoTargetMechanicsRow(id:)) -> #(
      "Spell4TargetMechanics",
      id,
    )
    NoValidTargetsRow(id:) -> #("Spell4ValidTargets", id)
  }
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
