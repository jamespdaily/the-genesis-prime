//// The activate cast's pick of a spell (genesis_prime/game/activate): which of a creature's
//// four activate columns the client casts when the player right-clicks it. Expected values
//// come from the client's pick, `0x14046c580` (fact `opcode.0x97.pick`), and the rows of the
//// Seaspine Mollusk, Creature2 26462, in the client's tables.

import client_tables
import fixture_tables
import genesis_prime/game/activate.{
  ActivateEffect, CannotBePlanned, Column, Creature, Limits, NoActivateSpell,
  Picked, Planned, Unread,
}
import genesis_prime/game/prerequisite.{Fails, NotRead, Passes}
import genesis_prime/game/spell_plan
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Spell4EffectsId}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/set
import gleam/string
import owned_test
import prerequisite_support
import unitest

/// A creature of these columns, with the cast time and range of no row.
fn creature_of(columns columns: List(#(Int, Int))) -> activate.Creature {
  Creature(
    columns: list.map(columns, fn(column) {
      Column(prerequisite_id: column.0, spell4_id: column.1)
    }),
    cast_time_ms: 0,
    min_range: 0.0,
    max_range: 0.0,
    flags: 0,
  )
}

pub fn activate_pick_takes_first_passing_column_test() -> Nil {
  use <- owned_test.run(5000)
  // The prerequisites the check answers: 11 and 13 pass, 12 fails, 14 holds a condition the
  // server does not read.
  let check = fn(prerequisite_id) {
    case prerequisite_id {
      11 | 13 -> Passes
      14 -> NotRead(prerequisite_type: 999)
      _ -> Fails
    }
  }
  let picked = fn(columns) {
    activate.pick(creature: creature_of(columns:), default_spell: 8, check:)
  }
  assert picked([#(0, 100), #(11, 200)]) == Picked(spell4_id: 100)
    as "0x14046c580: a column whose prerequisite is 0 wins without a check"
  assert picked([#(12, 100), #(13, 200), #(11, 300)]) == Picked(spell4_id: 200)
    as "0x14046c580: a failing first column is skipped, and the first passing one wins even when a later one passes too"
  assert picked([#(12, 100), #(12, 200)]) == Picked(spell4_id: 8)
    as "0x14046c580: when no column passes the pick stays GameFormula 414's dataint0, 8"
  assert picked([#(12, 100), #(11, 0), #(13, 300)]) == NoActivateSpell
    as "0x14046c580: a passing column whose spell is 0 wins and the client refuses with result 100 (TargetIsNotUseable)"
  assert picked([#(0, 0)]) == NoActivateSpell
    as "0x14046c580: a column of prerequisite 0 and spell 0 is the same refusal"
  assert picked([#(12, 100), #(14, 200), #(11, 300)])
    == Unread(prerequisite_type: 999)
    as "a column the server cannot read stops the pick, so the cast is refused as not built, never another column's spell"
  assert picked([#(11, 100), #(14, 200)]) == Picked(spell4_id: 100)
    as "a column after the winner is never checked"
}

pub fn seaspine_mollusk_activates_with_1817_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let assert Ok(row) = creature2.get(tables:, id: Creature2Id(26_462))
    as "Creature2 26462, the Seaspine Mollusk, is a root of the fixture"
  let creature = activate.creature_of(row:)
  let activations = activate.activations(tables:)
  assert activations.default_spell == 8
    as "GameFormula 414's dataint0 (0x14046c580)"
  assert creature.cast_time_ms == 2000
    as "Creature2 26462's activateSpellCastTime is 2000"
  let player_with_it =
    prerequisite.Subject(
      ..prerequisite_support.holding(held: [], second_unit: Some(5000)),
      player: Some(prerequisite_support.player()),
    )
  assert activate.pick(
      creature:,
      default_spell: activations.default_spell,
      check: activate.checker(activations:, subject: player_with_it),
    )
    == Picked(spell4_id: 1817)
    as "the creature's first column names Prerequisite 9358, which passes for a player with no challenge record (type 125 comparison 2), so the pick is Spell4 1817"
  let assert Ok(Planned(effects:, ..)) =
    activate.planned_of(activations:, spell4_id: 1817)
    as "the load plans Spell4 1817"
  assert effects
    == [ActivateEffect(effect_id: Spell4EffectsId(2821), delay_ms: 0)]
    as "Spell4 1817's one Activate row is Spell4Effects 2821, delay 0"
}

pub fn activate_spell_that_strikes_cannot_be_planned_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  let assert Ok(CannotBePlanned(why:)) =
    activate.planned_of(activations:, spell4_id: 38_392)
    as "Spell4 38392, Creature2 19232's activate spell, is held with a reason"
  assert string.contains(why, "82255") && string.contains(why, "38392")
    as "Spell4Effects 82255 of Spell4 38392 is a Proxy (effectType 26) aimed at the primary target (targetFlags 2) beside its Activate row 82254: the activate cast strikes no one, so the reason names that row"
}

pub fn activate_spell_with_a_ravel_signal_aimed_at_the_target_is_planned_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  let assert Ok(Planned(effects:, dropped_signals:, ..)) =
    activate.planned_of(activations:, spell4_id: 39_244)
    as "Spell4 39244 is planned: its other row, Spell4Effects 85564, is a RavelSignal (effectType 81) aimed at the primary target (targetFlags 2), which starts a script on the server (Spell4Effects.effectType.81) that the server does not have yet, so the plan holds the row as dropped (`dropped_signals`) and the cast logs it"
  assert list.length(effects) == 1 as "Spell4 39244 has one Activate row"
  assert dropped_signals == [Spell4EffectsId(85_564)]
    as "the RavelSignal row 85564 is the one the plan drops"
  assert case activate.planned_of(activations:, spell4_id: 85_452) {
    Ok(Planned(..)) -> True
    Ok(CannotBePlanned(..)) | Ok(activate.NoSpell4Row) | Error(Nil) -> False
  }
    as "Spell4 85452, the tutorial mine's activate spell, is planned: its rows are a RavelSignal aimed at the primary target (targetFlags 2) and a SetBusy (effectType 107), and nothing else strikes"
}

pub fn activate_spell_with_an_unread_target_effect_is_planned_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  let assert Ok(Planned(effects:, ..)) =
    activate.planned_of(activations:, spell4_id: 34_512)
    as "Spell4 34512 is planned: its only other row, Spell4Effects 179989, is effectType 107 aimed at the primary target (targetFlags 2), a type no server rule reads, which the strike drops on every path"
  assert effects
    == [ActivateEffect(effect_id: Spell4EffectsId(68_310), delay_ms: 0)]
    as "Spell4Effects 68310 is Spell4 34512's Activate row, delay 0"
}

pub fn every_client_side_interaction_activate_spell_is_planned_or_names_its_gap_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let activations = activate.activations(tables:)
  let interaction_spells =
    list.flat_map(creature2.all(tables), fn(row) {
      list.map(activate.creature_of(row:).columns, fn(column) {
        column.spell4_id
      })
    })
    |> list.filter(fn(spell4_id) { spell4_id != 0 })
    |> set.from_list
    |> set.to_list
    |> list.sort(by: int.compare)
    |> list.filter(fn(spell4_id) {
      case spell4.get(tables:, id: id.Spell4Id(spell4_id)) {
        Ok(row) ->
          case
            spell4_base.get(tables:, id: spell4.spell4_base_id_base_spell(row))
          {
            Ok(base) -> base.cast_method == 5
            Error(Nil) -> False
          }
        Error(Nil) -> False
      }
    })
  assert list.length(interaction_spells) == 767
    as "Creature2 spell4IdActivate00-03 name 767 distinct spells whose Spell4Base castMethod is 5 (Spell.CodeEnumCastMethod: ClientSideInteraction)"
  let refusals =
    list.filter_map(interaction_spells, fn(spell4_id) {
      case activate.planned_of(activations:, spell4_id:) {
        Ok(Planned(spell:, ..)) -> {
          assert spell.method == spell_plan.ClientSideInteraction
            as "a planned castMethod 5 spell is planned as ClientSideInteraction"
          Error(Nil)
        }
        Ok(CannotBePlanned(why:)) -> Ok(refusal_reason(why:))
        Ok(activate.NoSpell4Row) | Error(Nil) ->
          panic as "a castMethod 5 activate spell is planned or names its reason, never refused as not built"
      }
    })
  let count_of = fn(reason) {
    list.count(refusals, fn(found) { found == reason })
  }
  assert count_of("aimed at the target") == 33
    as "33 hold a Spell4Effects row aimed at the target or an area that the strike applies, which an activate cast strikes no one with (Spell4Effects targetFlags); the other 39 of the 72 held only a RavelSignal row aimed there, which the plan drops with a log when the cast starts (Spell4Effects.effectType.81)"
  assert count_of("control state") == 11
    as "11 hold a CCStateSet effect of a state other than Stun (0) and Knockdown (8) (Unit.CodeEnumCCState). Gap: the issue Spells work in depth on the real client (#336) owns it"
  assert count_of("disguise") == 4
    as "4 hold a DisguiseOutfit effect the server does not read (Spell4Effects.effectType.112). Gap: the issue Spells work in depth on the real client (#336) owns it"
  assert count_of("force remove counts") == 2
    as "2 hold a SpellForceRemove effect whose dataBits03 differs from its dataBits04 (Spell4Effects.effectType.80). Gap: the issue Spells work in depth on the real client (#336) owns it"
  assert count_of("lasting aim") == 2
    as "2 hold a Fluff, SpellForceRemove, Scale or RavelSignal effect aimed by flags the server does not read (Spell4Effects.targetFlags). Gap: the issue Spells work in depth on the real client (#336) owns it"
  assert count_of("stealth condition") == 1
    as "1 holds a Spell4Conditions row whose mask tests stealth, with the refusals 65 and 114 not checked. Gap: the issue Spells work in depth on the real client (#336) owns it"
  assert count_of("control aim") == 1
    as "1 holds a CCStateSet effect aimed by flags the server does not read (Spell4Effects.targetFlags). Gap: the issue Spells work in depth on the real client (#336) owns it"
  assert list.length(refusals) == 54
    as "54 of the 767 are refused, each for one of the reasons above, so 713 are planned"
}

/// The short name of a refusal's reason, by the text of the plan's own reason; a reason
/// this list does not name stops the test.
fn refusal_reason(why why: String) -> String {
  let reasons = [
    #("aims at the target or an area", "aimed at the target"),
    #("of state", "control state"),
    #("DisguiseOutfit", "disguise"),
    #("differs from its dataBits04", "force remove counts"),
    #("Fluff, SpellForceRemove, Scale or RavelSignal", "lasting aim"),
    #("whose mask tests stealth", "stealth condition"),
    #("CCStateSet effect", "control aim"),
  ]
  let assert Ok(#(_, reason)) =
    list.find(reasons, fn(reason) { string.contains(why, reason.0) })
    as { "the plan's reason is one the test names: " <> why }
  reason
}

/// Spell4 26663 (Spell4Effects 43805, effectType 7) and Spell4 1545 (Spell4Effects 2348,
/// effectType 7) are the ItemSpecial 4363 and 4350 spells of items 12444 and 12402; each
/// holds an Activate row. Spell4 41914 (ItemSpecial 5410's) holds only Spell4Effects
/// 94446, a RavelSignal (effectType 81), so it has no Activate row and is not planned.
pub fn the_activations_plan_item_spells_with_an_activate_effect_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = activate.activations(tables: fixture_tables.shared())
  let assert Ok(Planned(effects:, limits:, ..)) =
    activate.planned_of(activations:, spell4_id: 26_663)
    as "Spell4 26663, ItemSpecial 4363's spell, is planned"
  assert effects
    == [ActivateEffect(effect_id: Spell4EffectsId(43_805), delay_ms: 0)]
    as "Spell4Effects 43805 is its Activate row, delay 0"
  assert limits == Limits(min: 0.0, max: 30.0, vertical: -1.0)
    as "Spell4 26663: targetMaxRange 30.0, no minimum, targetVerticalRange -1"
  let assert Ok(Planned(effects:, limits:, ..)) =
    activate.planned_of(activations:, spell4_id: 1545)
    as "Spell4 1545, ItemSpecial 4350's spell, is planned"
  assert effects
    == [ActivateEffect(effect_id: Spell4EffectsId(2348), delay_ms: 0)]
    as "Spell4Effects 2348 is its Activate row, delay 0"
  assert limits.max == 5.0 as "Spell4 1545: targetMaxRange 5.0"
  assert activate.planned_of(activations:, spell4_id: 41_914) == Error(Nil)
    as "Spell4 41914 has no Activate row, so no plan is held"
}

/// What the client's cast-group check (`CheckCastActivateSpell` `0x1403b44b0`) says of a
/// creature, for a spell of cast group `group` (0 for none), where the creature's pick is
/// `picked`, its flags are `flags` and the group holds it or not.
fn cast_group_of(
  group group: Int,
  picked picked: activate.Pick,
  flags flags: Int,
  holds holds: Bool,
) -> activate.CastGroup {
  activate.passes_cast_group(
    spell4_id: 26_663,
    cast_group_id: group,
    creature: Creature(..creature_of(columns: [#(0, 26_663)]), flags:),
    picked:,
    in_cast_group: fn(_) { holds },
  )
}

pub fn a_spell_with_a_cast_group_passes_its_members_and_refuses_the_rest_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_group_of(
      group: 1691,
      picked: NoActivateSpell,
      flags: 0,
      holds: True,
    )
    == activate.InCastGroup
    as "a unit in the spell's group passes (TargetGroupContainsUnit answers 0)"
  assert cast_group_of(
      group: 1691,
      picked: NoActivateSpell,
      flags: 0,
      holds: False,
    )
    == activate.OutsideCastGroup
    as "a unit outside the group is refused 89 (TargetGroup)"
  assert cast_group_of(
      group: 1691,
      picked: Picked(spell4_id: 99),
      flags: 1,
      holds: False,
    )
    == activate.OutsideCastGroup
    as "the creature's activate spell being another spell does not pass it"
}

pub fn a_creature_whose_activate_spell_is_the_spell_passes_whatever_the_group_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_group_of(
      group: 1691,
      picked: Picked(spell4_id: 26_663),
      flags: 0,
      holds: False,
    )
    == activate.InCastGroup
    as "GetUnitActivateSpell equals the spell: the check passes before it reads the group"
  assert cast_group_of(
      group: 0,
      picked: Picked(spell4_id: 26_663),
      flags: 1,
      holds: False,
    )
    == activate.InCastGroup
    as "and before it reads the creature's flags bit 0"
}

pub fn a_spell_with_no_cast_group_refuses_a_creature_with_flags_bit_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_group_of(
      group: 0,
      picked: NoActivateSpell,
      flags: 16_385,
      holds: True,
    )
    == activate.OutsideCastGroup
    as "Creature2.flags 16385 (the Cartel Slaver Shack's) has bit 0: refused 89"
  assert cast_group_of(
      group: 0,
      picked: NoActivateSpell,
      flags: 24_576,
      holds: False,
    )
    == activate.InCastGroup
    as "Creature2.flags 24576 (the farmhand's) has bit 0 clear: passes"
}

pub fn a_pick_through_an_unread_prerequisite_is_judged_only_when_a_column_names_the_spell_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_group_of(
      group: 1691,
      picked: Unread(prerequisite_type: 76),
      flags: 0,
      holds: False,
    )
    == activate.CastGroupUnread(prerequisite_type: 76)
    as "a column names the spell, so whether it is the creature's activate spell is not told"
  assert activate.passes_cast_group(
      spell4_id: 26_663,
      cast_group_id: 1691,
      creature: creature_of(columns: [#(5, 41_914)]),
      picked: Unread(prerequisite_type: 76),
      in_cast_group: fn(_) { False },
    )
    == activate.OutsideCastGroup
    as "no column names the spell, so the unread pick cannot make it the activate spell"
}

pub fn a_pick_through_an_unread_prerequisite_is_not_read_where_the_group_or_flags_pass_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_group_of(
      group: 1691,
      picked: Unread(prerequisite_type: 76),
      flags: 1,
      holds: True,
    )
    == activate.InCastGroup
    as "a group that holds the unit passes it, whichever spell the creature's pick is, so the unread pick does not matter"
  assert cast_group_of(
      group: 0,
      picked: Unread(prerequisite_type: 76),
      flags: 0,
      holds: False,
    )
    == activate.InCastGroup
    as "no group and flags bit 0 clear passes, whichever spell the creature's pick is"
}
