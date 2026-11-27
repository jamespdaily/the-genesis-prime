//// What a press at another player reads of a spell's target rows (`spell_plan.target_aim_of`).
//// Expected values come from these places.
//// - `opcode.0x9d.target_checks` and `0x1403b2240`: the range limits, the target condition
////   bits (bit 1 of the mask is the combat test: a clear value bit is 108, a set one 109) and
////   the cast group.
//// - `0x1403b0880`: Spell4Base.targetingFlags bits 2 and 3 (255 and 256), skipped for a
////   spell of target type 2, 3, 4, 7 or 8.
//// - `spell_plan.target_mask_read`: the condition bits the server judges; a spell with any
////   other, a target vital requirement (Spell4.targetBeginInnateRequirement, `0x1403b4020`)
////   or a required zone (Spell4Base.worldZoneIdZoneRequired) is left unread, in words.
//// - The 27 tier spells of Mind Over Body, Bolster and Phantasmal Armor (Spell4Base 19030,
////   19031, 19033): `table_rows -- Spell4` gives range 0 to 35 and vertical -1 in each, a
////   target condition row 15 (mask 129), no cast group and no vital or zone requirement;
////   Spell4Base 19031 holds targetingFlags 2 (bit 1), not a pet bit.
//// - `0x1403b2240` and `0x1400a7a40`: Spell4Base.spell4TargetAngleId names a
////   Spell4TargetAngle row (`table_rows -- Spell4TargetAngle`: 1 is 0.0, 2 is 90.0, 3 is
////   120.0, 4 is 135.0, 5 is 180.0), the arc a press at a player is refused 101 beyond;
////   Spell4.propertyFlags bit 18 (0x40000) lets the client skip the test while a movement flag
////   of the caster is clear.

import client_tables
import genesis_prime/shared/spell_plan.{
  type TargetAim, type TargetRows, CombatAllowed, FacesAnywhere, FacesWithin,
  Limits, MustBeInCombat, OutOfCombatOnly, PetBits, TargetAim, TargetRows,
}
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import owned_test
import unitest

const mind_over_body_base = 19_030

const bolster_base = 19_031

const phantasmal_armor_base = 19_033

/// The rows of the three abilities' tier spells: range 0 to 35, no vertical limit, the
/// target condition row 15 (mask 129, value 0), nothing else.
fn rows() -> TargetRows {
  TargetRows(
    limits: Limits(min: 0.0, max: 35.0, vertical: -1.0),
    conditions_mask: 129,
    conditions_value: 0,
    begin_innate_requirement: 0,
    zone_required: 0,
    cast_group_id: 0,
    targeting_flags: 0,
    target_type: 1,
    property_flags: 0,
    target_angle_degrees: 0.0,
  )
}

/// What the three abilities' tier spells plan to.
fn tier_aim() -> TargetAim {
  TargetAim(
    limits: Limits(min: 0.0, max: 35.0, vertical: -1.0),
    combat: CombatAllowed,
    cast_group_id: 0,
    unread: None,
    pets: PetBits(must_be_pet: False, must_be_master: False),
    facing: FacesAnywhere,
  )
}

pub fn the_target_aim_of_a_spell_is_planned_from_its_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let tiers =
    list.filter(spell4.all(tables), fn(row) {
      list.contains(
        [mind_over_body_base, bolster_base, phantasmal_armor_base],
        row.spell4_base_id_base_spell,
      )
    })
  assert tiers != [] as "the client's tables hold the tier spells"
  list.each(tiers, fn(row) {
    let assert Ok(spell) =
      spell_plan.spell_alone(tables:, sources:, spell4_id: row.id, chain: [])
      as "a tier spell plans"
    assert spell.target_aim == tier_aim()
      as { "Spell4 " <> int.to_string(row.id) <> " plans to the rows above" }
  })
  list.each(
    [
      #(
        "target condition mask bit 1 with value 0: the target must be out of combat (108)",
        TargetRows(..rows(), conditions_mask: 2),
        TargetAim(..tier_aim(), combat: OutOfCombatOnly),
        None,
      ),
      #(
        "target condition mask bit 1 with value 2: the target must be in combat (109)",
        TargetRows(..rows(), conditions_mask: 2, conditions_value: 2),
        TargetAim(..tier_aim(), combat: MustBeInCombat),
        None,
      ),
      #(
        "bits 0 and 7 are judged elsewhere, so mask 129 tests no combat and reads everything",
        TargetRows(..rows(), conditions_mask: 129),
        tier_aim(),
        None,
      ),
      #(
        "mask bit 3 is outside target_mask_read: unread, as a condition",
        TargetRows(..rows(), conditions_mask: 8),
        tier_aim(),
        Some("condition"),
      ),
      #(
        "a target vital requirement (Spell4.targetBeginInnateRequirement, 0x1403b4020) is unread",
        TargetRows(..rows(), begin_innate_requirement: 5),
        tier_aim(),
        Some("vital"),
      ),
      #(
        "a required zone (Spell4Base.worldZoneIdZoneRequired) is unread",
        TargetRows(..rows(), zone_required: 100),
        tier_aim(),
        Some("zone"),
      ),
      #(
        "the client tests the zone before the vital: a spell with both is unread for the zone",
        TargetRows(..rows(), zone_required: 100, begin_innate_requirement: 5),
        tier_aim(),
        Some("zone"),
      ),
      #(
        "a condition value with bit 5 set (mask 33, value 32: the target piloting) is unread",
        TargetRows(..rows(), conditions_mask: 33, conditions_value: 32),
        tier_aim(),
        Some("seated"),
      ),
      #(
        "a condition value with bit 7 set (mask 129, value 128: the target on a taxi) is unread",
        TargetRows(..rows(), conditions_mask: 129, conditions_value: 128),
        tier_aim(),
        Some("seated"),
      ),
      #(
        "a condition value with bit 5 clear (mask 33, value 1) is read: the target must not be piloting",
        TargetRows(..rows(), conditions_mask: 33, conditions_value: 1),
        tier_aim(),
        None,
      ),
      #(
        "a target angle of 90 is the facing arc",
        TargetRows(..rows(), target_angle_degrees: 90.0),
        TargetAim(..tier_aim(), facing: FacesWithin(arc_degrees: 90.0)),
        None,
      ),
      #(
        "a target angle of 0 is no facing test",
        TargetRows(..rows(), target_angle_degrees: 0.0),
        tier_aim(),
        None,
      ),
      #(
        "a target angle with propertyFlags bit 18 is unread: the client can skip it",
        TargetRows(
          ..rows(),
          target_angle_degrees: 90.0,
          property_flags: 0x40000,
        ),
        TargetAim(..tier_aim(), facing: FacesWithin(arc_degrees: 90.0)),
        Some("movement flag"),
      ),
      #(
        "propertyFlags bit 18 with no target angle changes nothing",
        TargetRows(..rows(), property_flags: 0x40000),
        tier_aim(),
        None,
      ),
      #(
        "a non-zero targetGroupIdCastGroup is the cast group, and it is read",
        TargetRows(..rows(), cast_group_id: 77),
        TargetAim(..tier_aim(), cast_group_id: 77),
        None,
      ),
      #(
        "targetingFlags bit 2 is the pet bit",
        TargetRows(..rows(), targeting_flags: 4),
        TargetAim(
          ..tier_aim(),
          pets: PetBits(must_be_pet: True, must_be_master: False),
        ),
        None,
      ),
      #(
        "targetingFlags bit 3 is the master bit",
        TargetRows(..rows(), targeting_flags: 8),
        TargetAim(
          ..tier_aim(),
          pets: PetBits(must_be_pet: False, must_be_master: True),
        ),
        None,
      ),
      #(
        "targetingFlags 2 (Spell4Base 19031) is bit 1, not a pet bit",
        TargetRows(..rows(), targeting_flags: 2),
        tier_aim(),
        None,
      ),
      #(
        "a spell of target type 3 is never tested for either pet bit (0x1403b0880)",
        TargetRows(..rows(), targeting_flags: 12, target_type: 3),
        tier_aim(),
        None,
      ),
      #(
        "a spell of target type 8 is never tested for either pet bit",
        TargetRows(..rows(), targeting_flags: 12, target_type: 8),
        tier_aim(),
        None,
      ),
      #(
        "the limits are the Spell4 row's",
        TargetRows(..rows(), limits: Limits(min: 5.0, max: 12.0, vertical: 3.0)),
        TargetAim(
          ..tier_aim(),
          limits: Limits(min: 5.0, max: 12.0, vertical: 3.0),
        ),
        None,
      ),
    ],
    fn(row) {
      let #(why, given, expected, unread_words) = row
      let planned = spell_plan.target_aim_of(rows: given)
      assert TargetAim(..planned, unread: None) == expected as why
      assert unread_matches(unread: planned.unread, words: unread_words) as why
    },
  )
}

/// Whether the unread cause holds the words, or both are none.
fn unread_matches(
  unread unread: Option(String),
  words words: Option(String),
) -> Bool {
  case unread, words {
    None, None -> True
    Some(text), Some(words) -> string.contains(text, words)
    Some(_), None | None, Some(_) -> False
  }
}

pub fn a_spells_facing_is_the_arc_of_its_bases_target_angle_row_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let planned = fn(spell4_id) {
    spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
  }
  let with_angle = fn(angle_id, skipped) {
    list.filter(spell4.all(tables), fn(row) {
      let assert Ok(base) =
        spell4_base.get(
          tables:,
          // the base row of every Spell4 row exists in the client's tables
          id: Spell4BaseId(row.spell4_base_id_base_spell),
        )
      base.spell4_target_angle_id == angle_id
      && { int.bitwise_and(row.property_flags, 0x40000) != 0 } == skipped
    })
    |> list.find_map(fn(row) { planned(row.id) })
  }
  // Spell4TargetAngle rows 2 to 5: `table_rows -- Spell4TargetAngle 2 3 4 5`.
  list.each([#(2, 90.0), #(3, 120.0), #(4, 135.0), #(5, 180.0)], fn(row) {
    let #(angle_id, degrees) = row
    let assert Ok(spell) = with_angle(angle_id, False)
      as "the client holds a plannable spell of the angle"
    assert spell.target_aim.facing == FacesWithin(arc_degrees: degrees)
      as { "Spell4TargetAngle " <> int.to_string(angle_id) }
  })
  let assert Ok(skippable) = with_angle(5, True)
    as "the client holds a plannable spell of angle 5 with propertyFlags bit 18"
  assert unread_matches(
    unread: skippable.target_aim.unread,
    words: Some("movement flag"),
  )
    as "a target angle the client can skip is unread"
}
