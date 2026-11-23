//// How an effect row's aim (`Spell4Effects.targetFlags`) becomes the units it reaches
//// (`genesis_prime/game/spell_plan` `aim_of`, `units_aimed_at`, `spell_hits_foes`,
//// `read_row`). Expected values come from these places.
//// - The client's rows, kept in the fixture (`table_rows -- Spell4Effects <ids>`):
////   196409 (Spell4 75957, type 8, flags 5), 196408 (75957, type 26, flags 5), 60607
////   (32236, type 4, flags 5), 64390 (33262, type 26, flags 5), 43635 (26579, type 17,
////   flags 5), 47702 (28003, type 17, flags 7), 121485 (51546, type 17, flags 3), 72210
////   (35662, type 17, flags 7), 121619 (51524, type 80, flags 5), 112871 (47982, type 81,
////   flags 7), 111951 (47658, type 18, flags 3), 90024 (40529, type 26, flags 3), 123870
////   (52400, type 10, flags 7), 55294 (30356, type 118, flags 5), 3639 (2252, type 11,
////   flags 5), 9717 (5425, type 11, flags 3), 182108 (71091, type 4, flags 3, flags bit 2
////   until removed), 76609 (36562, type 26, flags 5), 180600 (41926, type 26, flags 5)
////   and 180595 to 180599 (70756, type 26, flags 2).
//// - Texts 245408 and 295987 (Mental Boon heals "yourself and ... allies") and 389501
////   (Flash restores health "to yourself and N allies"): the caster is part of each
////   spell, the allies are the area's.
//// - `Spell4Effects.targetFlags.load`: the client refuses only 0.
//// - `Spell4Effects.targetFlags.combined` (a guess): 3, 5 and 7 hold the union of their
////   bits. `Spell4Effects.targetFlags.bit8` (a guess): bit 8 is not read.
//// - `spell_plan.spell_hits_foes` (the server's choice, Jim's decision of 2026-11-15): a
////   spell hits foes when a damage or crowd-control row of it has flags 2 to 7.

import client_tables
import fixture_tables
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  type Aim, type Kind, type RowReading, AimsAtArea, AimsAtCaster,
  AimsAtCasterAndArea, AimsAtCasterAndPrimaryTarget,
  AimsAtCasterPrimaryTargetAndArea, AimsAtPrimaryTarget,
  AimsAtPrimaryTargetAndArea, Applied,
}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

fn client_row(id id: Int) -> spell4_effects.Spell4Effects {
  spell_tables.effect_row_in(tables: fixture_tables.shared(), id:)
}

fn read_client_row(
  id id: Int,
  place place: spell_plan.RowPlace,
) -> Result(RowReading, spell_plan.PlanError) {
  spell_tables.read_row(effect: client_row(id:), place:)
}

/// The planned rows a reading holds, a row of two parts as its two.
fn planned_parts(reading reading: RowReading) -> List(Kind) {
  case reading {
    Applied(spell_plan.ReadEffects(effects:)) ->
      list.map(effects, fn(planned) { planned.kind })
    Applied(spell_plan.ReadProc(..))
    | Applied(spell_plan.ReadProxy(..))
    | spell_plan.Held(_)
    | spell_plan.LeftOut(_)
    | spell_plan.ReadByArea
    | spell_plan.ReadByActivation -> []
  }
}

fn aims_of(reading reading: RowReading) -> List(Aim) {
  list.filter_map(planned_parts(reading:), fn(row) {
    case row {
      spell_plan.LastingEffect(lasting:) -> Ok(lasting.aim)
      spell_plan.RemoveEffect(remove:) -> Ok(remove.aim)
      spell_plan.ControlEffect(control:) -> Ok(control.aim)
      spell_plan.HealEffect(heal: spell_plan.Heal(aim:, ..)) -> Ok(aim)
      spell_plan.HealEffect(heal: spell_plan.TickingHeal(aim:, ..)) -> Ok(aim)
      spell_plan.GainEffect(..)
      | spell_plan.ModifierEffect(..)
      | spell_plan.ForcedMoveEffect(..)
      | spell_plan.StruckMoveEffect(..)
      | spell_plan.CooldownEffect(..)
      | spell_plan.StealthEffect(..)
      | spell_plan.RemoveStealthEffect(..)
      | spell_plan.ProcEffect(..)
      | spell_plan.DespawnEffect(..)
      | spell_plan.UnitStateEffect(..)
      | spell_plan.DelayEffect(..)
      | spell_plan.QuestAdvanceEffect(..)
      | spell_plan.ProxyEffect(..) -> Error(Nil)
    }
  })
}

pub fn aim_of_reads_each_value_one_to_seven_as_the_bits_it_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  // Bit 1 the caster, bit 2 the primary target, bit 4 the area.
  assert list.map([1, 2, 3, 4, 5, 6, 7], fn(flags) {
      spell_plan.aim_of(target_flags: flags)
    })
    == [
      Ok(AimsAtCaster),
      Ok(AimsAtPrimaryTarget),
      Ok(AimsAtCasterAndPrimaryTarget),
      Ok(AimsAtArea),
      Ok(AimsAtCasterAndArea),
      Ok(AimsAtPrimaryTargetAndArea),
      Ok(AimsAtCasterPrimaryTargetAndArea),
    ]
    as "targetFlags 1, 2, 3, 4, 5, 6 and 7 are the caster, the primary target, both, the area, the caster and the area, the primary target and the area, and all three"
  list.each([1, 2, 3, 4, 5, 6, 7], fn(flags) {
    let assert Ok(aim) = spell_plan.aim_of(target_flags: flags)
    assert spell_plan.reaches_caster(aim:) == { flags % 2 == 1 }
      as "bit 1 names the caster"
    assert spell_plan.reaches_primary_target(aim:) == { flags / 2 % 2 == 1 }
      as "bit 2 names the primary target"
    assert spell_plan.reaches_area(aim:) == { flags / 4 % 2 == 1 }
      as "bit 4 names the area"
  })
}

pub fn aim_of_refuses_zero_and_every_bit_eight_value_test() -> Nil {
  use <- owned_test.run(60_000)
  assert list.map([0, 8, 9, 10, 12, 15], fn(flags) {
      spell_plan.aim_of(target_flags: flags)
    })
    == [Error(Nil), Error(Nil), Error(Nil), Error(Nil), Error(Nil), Error(Nil)]
    as "the client refuses 0 (Spell4Effects.targetFlags.load) and bit 8's meaning is not known"
}

pub fn units_aimed_at_lists_caster_then_target_then_area_once_each_test() -> Nil {
  use <- owned_test.run(60_000)
  // The caster is unit 1, the target unit 2, the area holds the target and two others.
  assert spell_plan.units_aimed_at(
      aim: AimsAtCasterPrimaryTargetAndArea,
      caster: 1,
      primary_target: 2,
      area: [2, 3, 4],
    )
    == [1, 2, 3, 4]
    as "flags 7 name the caster, then the target, then the units of the area; the target in the area is listed once"
  assert spell_plan.units_aimed_at(
      aim: AimsAtCasterAndArea,
      caster: 1,
      primary_target: 2,
      area: [2, 3],
    )
    == [1, 2, 3]
    as "flags 5 name the caster and the area"
  assert spell_plan.units_aimed_at(
      aim: AimsAtPrimaryTargetAndArea,
      caster: 1,
      primary_target: 2,
      area: [3, 2],
    )
    == [2, 3]
    as "flags 6 name the target and the area"
  assert spell_plan.units_aimed_at(
      aim: AimsAtCasterAndPrimaryTarget,
      caster: 1,
      primary_target: 2,
      area: [3, 4],
    )
    == [1, 2]
    as "flags 3 name the caster and the target, not the area"
}

pub fn units_aimed_at_lists_the_caster_once_when_it_is_the_primary_target_test() -> Nil {
  use <- owned_test.run(60_000)
  assert spell_plan.units_aimed_at(
      aim: AimsAtCasterAndPrimaryTarget,
      caster: 1,
      primary_target: 1,
      area: [],
    )
    == [1]
    as "a cast on oneself reaches the caster once"
  assert spell_plan.units_aimed_at(
      aim: AimsAtCasterPrimaryTargetAndArea,
      caster: 1,
      primary_target: 1,
      area: [1, 5],
    )
    == [1, 5]
    as "a caster that is its own target and in the area is one unit"
}

pub fn spell_hits_foes_when_a_damage_or_control_row_aims_past_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let hitting =
    spell_plan.spells_that_hit_foes(
      effects: spell4_effects.all(fixture_tables.shared()),
    )
  assert set.contains(hitting, 75_957)
    as "spell 75957 holds damage row 196409, flags 5"
  assert set.contains(hitting, 32_236)
    as "spell 32236 holds crowd-control row 60607, flags 5"
  assert !set.contains(hitting, 33_262)
    as "spell 33262 holds Proxy 64390 and no damage or crowd-control row aimed past the caster"
  assert !spell_plan.spell_hits_foes(effects: [
    spell_tables.blank_effect(id: 1, spell: 1, effect_type: 8, target_flags: 1),
  ])
    as "a damage row aimed at the caster alone hits no foe"
  assert !spell_plan.spell_hits_foes(effects: [
    spell_tables.blank_effect(id: 1, spell: 1, effect_type: 4, target_flags: 9),
  ])
    as "a crowd-control row aimed by flags 9 (bit 8) is not read as hitting foes"
  assert spell_plan.spell_hits_foes(effects: [
    spell_tables.blank_effect(id: 1, spell: 1, effect_type: 17, target_flags: 3),
    spell_tables.blank_effect(id: 2, spell: 1, effect_type: 8, target_flags: 2),
  ])
    as "one damage row aimed at the primary target is enough"
}

pub fn union_lasting_rows_without_a_friendly_area_are_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = [
    // id, the place of its spell, the aim its flags name
    #(121_485, spell_tables.pressed, AimsAtCasterAndPrimaryTarget),
    #(
      72_210,
      spell_tables.pressed_hitting_foes,
      AimsAtCasterPrimaryTargetAndArea,
    ),
    #(121_619, spell_tables.pressed_hitting_foes, AimsAtCasterAndArea),
    #(
      112_871,
      spell_tables.pressed_hitting_foes,
      AimsAtCasterPrimaryTargetAndArea,
    ),
    #(111_951, spell_tables.pressed, AimsAtCasterAndPrimaryTarget),
  ]
  list.each(rows, fn(row) {
    let #(id, place, aim) = row
    let assert Ok(reading) = read_client_row(id:, place:)
    assert aims_of(reading:) == [aim]
      as "the row is read with the aim its flags name, each bit its own unit"
  })
}

pub fn union_row_with_the_area_bit_in_a_spell_that_hits_no_foes_is_refused_naming_834_test() -> Nil {
  use <- owned_test.run(60_000)
  // The kinds that keep a state on the area's units (`lasting_aim_of`): Fluff 43635 and
  // 47702, ForceRemove 121619, RavelSignal 112871 and Scale 111951 with its flags set to
  // 7 (a synthetic cell: the client's row has flags 3).
  let rows = [
    #(43_635, 26_579, 5),
    #(47_702, 28_003, 7),
    #(121_619, 51_524, 5),
    #(112_871, 47_982, 7),
    #(111_951, 47_658, 7),
  ]
  let read_aimed_by = fn(id, flags, place) {
    spell_tables.read_row(
      effect: spell4_effects.Spell4Effects(
        ..client_row(id:),
        target_flags: flags,
      ),
      place:,
    )
  }
  list.each(rows, fn(row) {
    let #(id, spell4_id, flags) = row
    let error = read_aimed_by(id, flags, spell_tables.pressed)
    assert error
      == Error(spell_plan.FriendlyAreaNotRead(
        spell4_id:,
        effect_id: id,
        target_flags: flags,
      ))
      as "a state kept on the area's units with the caster's bit and the area's, in a spell that hits no foes, has an area the server cannot find the allies of"
    let assert Error(why) = error
    assert string.ends_with(
      spell_plan.describe(error: why),
      "a friendly spell's area finds the caster's allies, which the server does not read",
    )
      as "the refusal says what is not read and names no issue"
    let assert Ok(Applied(_)) =
      read_aimed_by(id, flags, spell_tables.pressed_hitting_foes)
      as "the same row is read in a spell that hits foes"
  })
  list.each([90_024, 121_485], fn(id) {
    let assert Ok(Applied(_)) =
      read_client_row(id:, place: spell_tables.pressed)
      as "a flag 3 row has no area bit, so it is read in a spell that hits no foes"
  })
}

pub fn read_today_union_row_in_a_spell_that_hits_no_foes_keeps_its_caster_and_target_parts_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(urgency) =
    read_client_row(id: 123_870, place: spell_tables.pressed)
  assert aims_of(reading: urgency) == [AimsAtCasterAndPrimaryTarget]
    as "urgency, flags 7 in a spell that hits no foes: a heal for the caster and the primary target, the area part finds no allies"
  let assert Ok(shield_surge) =
    read_client_row(id: 55_294, place: spell_tables.pressed)
  assert aims_of(reading: shield_surge) == [AimsAtCaster]
    as "Shield Surge, flags 5 in a spell that hits no foes: a heal for the caster alone"
  let assert Ok(modifier) =
    read_client_row(id: 3639, place: spell_tables.pressed)
  assert case planned_parts(reading: modifier) {
    [
      spell_plan.ModifierEffect(spell_plan.PropertyModifier(
        change: spell_plan.PropertyChange(..),
        ..,
      )),
    ] -> True
    _ -> False
  }
    as "a UnitPropertyModifier with flags 5 in a spell that hits no foes changes the caster only, with no struck change"
}

pub fn bit_eight_rows_are_still_refused_naming_the_bit_eight_question_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let refusals = [
    #(
      "type 17, flags 10",
      read_client_row_aimed_by(id: 121_485, flags: 10),
      spell_plan.LastingAimNotRead(
        spell4_id: 51_546,
        effect_id: 121_485,
        target_flags: 10,
      ),
    ),
    #(
      "type 4, flags 9",
      read_client_row_aimed_by(id: 60_607, flags: 9),
      spell_plan.ControlAimNotRead(
        spell4_id: 32_236,
        effect_id: 60_607,
        target_flags: 9,
      ),
    ),
    #(
      "type 26, flags 10",
      read_client_row_aimed_by(id: 64_390, flags: 10),
      spell_plan.ProxyAimNotRead(
        spell4_id: 33_262,
        effect_id: 64_390,
        target_flags: 10,
      ),
    ),
  ]
  list.each(refusals, fn(refusal) {
    let #(name, read, expected) = refusal
    assert read == Error(expected) as name
    assert string.contains(
      spell_plan.describe(error: expected),
      "bit 8's meaning is not known",
    )
      as name
    assert !string.contains(spell_plan.describe(error: expected), "#") as name
  })
  let refused =
    spell_area.AimNotRead(
      spell4_id: 75_957,
      effect_id: 196_409,
      target_flags: 12,
    )
  assert spell_area.damage_row_of(
      tables:,
      spell4_id: 75_957,
      effect: spell4_effects.Spell4Effects(
        ..client_row(id: 196_409),
        target_flags: 12,
      ),
    )
    == Error(refused)
    as "a type 8 row with flags 12 is refused by the area"
  assert string.contains(
    spell_area.describe(error: refused),
    "bit 8's meaning is not known",
  )
    as "the damage refusal says bit 8's meaning is not known"
}

/// The client's row `id` with its targetFlags set to `flags`, read in a spell that hits foes.
fn read_client_row_aimed_by(
  id id: Int,
  flags flags: Int,
) -> Result(RowReading, spell_plan.PlanError) {
  spell_tables.read_row(
    effect: spell4_effects.Spell4Effects(..client_row(id:), target_flags: flags),
    place: spell_tables.pressed_hitting_foes,
  )
}

pub fn union_property_modifier_plans_a_caster_change_and_a_struck_change_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(reading) =
    read_client_row(id: 9717, place: spell_tables.pressed)
  let assert [
    spell_plan.ModifierEffect(caster),
    spell_plan.ModifierEffect(struck),
  ] = planned_parts(reading:)
    as "a UnitPropertyModifier with flags 3 is read as two parts"
  assert caster.effect_id == Spell4EffectsId(9717)
  assert struck.effect_id == Spell4EffectsId(9717)
    as "both parts keep the row's effect id"
  let assert spell_plan.PropertyChange(caster_modifier) = caster.change
    as "the caster's part is a change of the caster's property"
  let assert spell_plan.StruckChange(modifier: struck_modifier, aim:) =
    struck.change
    as "the part past the caster is a change of a struck creature"
  assert aim == AimsAtPrimaryTarget
    as "flags 3 name the caster and the primary target, so the part past the caster names the primary target"
  assert caster_modifier == struck_modifier
    as "both parts change the same property by the same amount"
}

pub fn union_proxy_plans_one_child_on_the_caster_and_one_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(Applied(spell_plan.ReadProxy(targets:, condition: _, ..))) =
    read_client_row(id: 196_408, place: spell_tables.pressed_hitting_foes)
    as "a Proxy with flags 5 in a spell that hits foes"
  assert targets == [spell_plan.OnCaster, spell_plan.OnEachStruck]
    as "flags 5 start the child on the caster and on each struck unit"
  let assert Ok(Applied(spell_plan.ReadProxy(targets: gate_targets, ..))) =
    read_client_row(id: 90_024, place: spell_tables.pressed)
    as "a Proxy with flags 3 in a spell that hits no foes"
  assert gate_targets == [spell_plan.OnCaster]
    as "flags 3 start the child on the caster; the primary target is the caster of a spell cast on oneself"
  let proxies =
    list.filter(
      spell_plan.payloads(
        spell: spell_tables.client_spell(spell4_id: 75_957),
        as_kind: spell_plan.as_proxy,
      ),
      fn(proxy) { proxy.effect_id == Spell4EffectsId(196_408) },
    )
  assert list.map(proxies, fn(proxy) { proxy.target })
    == [spell_plan.OnCaster, spell_plan.OnEachStruck]
    as "the spell holds one Proxy of the row for the caster and one for each struck unit"
}

/// The Proxy row `id` with its targetFlags set to `flags`, read in the place: the units it
/// starts its child on, or what refuses it.
fn proxy_targets_aimed_by(
  id id: Int,
  flags flags: Int,
  place place: spell_plan.RowPlace,
) -> Result(List(spell_plan.ProxyTarget), spell_plan.PlanError) {
  let effect =
    spell4_effects.Spell4Effects(..client_row(id:), target_flags: flags)
  case spell_tables.read_row(effect:, place:) {
    Ok(Applied(spell_plan.ReadProxy(targets:, ..))) -> Ok(targets)
    Ok(_) -> panic as "the Proxy row was not read as a Proxy"
    Error(error) -> Error(error)
  }
}

pub fn a_proxy_aimed_at_the_primary_target_is_planned_on_the_press_target_and_a_proxy_aimed_at_the_caster_and_the_primary_target_stays_on_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.targetFlags: 1 the caster, 2 the primary target, 4 the area. The client
  // starts no Proxy (`Spell4Effects.effectType.26`); the server starts a flags 2 Proxy's
  // child on the player the press named. Proxy 83947 (Spell4 32823, flags 2) and 90024
  // (Spell4 40529, flags 3) are the client's rows; the hits-foes cell is a synthetic one of
  // 196408. The primary-target bit of 3, 6 and 7 is not read for a Proxy.
  [
    #(
      "83947 as read: flags 2, the spell hits no foes",
      proxy_targets_aimed_by(id: 83_947, flags: 2, place: spell_tables.pressed),
      Ok([spell_plan.OnPrimaryTarget]),
    ),
    #(
      "196408 with flags 2 (synthetic), the spell hits foes",
      proxy_targets_aimed_by(
        id: 196_408,
        flags: 2,
        place: spell_tables.pressed_hitting_foes,
      ),
      Ok([spell_plan.OnPrimaryTarget]),
    ),
    #(
      "90024 as read: flags 3, the primary-target bit is not read",
      proxy_targets_aimed_by(id: 90_024, flags: 3, place: spell_tables.pressed),
      Ok([spell_plan.OnCaster]),
    ),
  ]
  |> list.each(fn(row) {
    let #(name, read, expected) = row
    assert read == expected as name
  })
}

pub fn a_proxy_aimed_by_5_or_7_in_a_spell_that_hits_no_foes_starts_its_child_on_the_caster_alone_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects.targetFlags: 1 the caster, 2 the primary target, 4 the area. Proxies
  // 64390 (Spell4 33262, flags 5), 196408 (75957, flags 5) and 90024 (40529, flags 3)
  // are the client's rows; the flags 7 and 13 cases are synthetic cells of them.
  [
    #(
      "64390 as read: flags 5, the spell hits no foes",
      proxy_targets_aimed_by(id: 64_390, flags: 5, place: spell_tables.pressed),
      Ok([spell_plan.OnCaster]),
    ),
    #(
      "64390 with flags 7 (synthetic), the spell hits no foes",
      proxy_targets_aimed_by(id: 64_390, flags: 7, place: spell_tables.pressed),
      Ok([spell_plan.OnCaster]),
    ),
    #(
      "196408 as read: flags 5, the spell hits foes",
      proxy_targets_aimed_by(
        id: 196_408,
        flags: 5,
        place: spell_tables.pressed_hitting_foes,
      ),
      Ok([spell_plan.OnCaster, spell_plan.OnEachStruck]),
    ),
    #(
      "196408 with flags 7 (synthetic), the spell hits foes",
      proxy_targets_aimed_by(
        id: 196_408,
        flags: 7,
        place: spell_tables.pressed_hitting_foes,
      ),
      Ok([spell_plan.OnCaster, spell_plan.OnEachStruck]),
    ),
    #(
      "90024 as read: flags 3, the spell hits no foes",
      proxy_targets_aimed_by(id: 90_024, flags: 3, place: spell_tables.pressed),
      Ok([spell_plan.OnCaster]),
    ),
    #(
      "64390 with flags 13 (synthetic, bit 8), the spell hits no foes",
      proxy_targets_aimed_by(id: 64_390, flags: 13, place: spell_tables.pressed),
      Error(spell_plan.ProxyAimNotRead(
        spell4_id: 33_262,
        effect_id: 64_390,
        target_flags: 13,
      )),
    ),
  ]
  |> list.each(fn(row) {
    let #(name, read, expected) = row
    assert read == expected as name
  })
  // Mental Boon's one-point tier (Spell4 36562) holds Proxy 76609, which names 33258.
  let proxies =
    spell_plan.payloads(
      spell: spell_tables.client_spell(spell4_id: 36_562),
      as_kind: spell_plan.as_proxy,
    )
  let assert [proxy] =
    list.filter(proxies, fn(proxy) {
      proxy.effect_id == Spell4EffectsId(76_609)
    })
    as "the spell holds Proxy 76609 once"
  assert proxy.target == spell_plan.OnCaster
    as "texts 245408 and 295987 heal the caster; the allies are the area's, which the server does not find"
  assert proxy.spell.spell4_id == Spell4Id(33_258)
    as "the Proxy names 33258, the heal"
}

/// The Proxy `id` read in the place on the fixture's tables with these cells of other rows
/// changed (`fixture_tables.changes`): what it starts, or why it is left out.
fn proxy_read_with(
  id id: Int,
  place place: spell_plan.RowPlace,
  edits edits: List(#(String, Int, List(#(String, planted_table.Cell)))),
) -> Result(RowReading, spell_plan.PlanError) {
  use tables <- fixture_tables.changes(edits:)
  spell_plan.read_row(
    tables:,
    sources: spell_plan.sources_of(tables:),
    place:,
    effect: spell_tables.effect_row_in(tables:, id:),
  )
}

pub fn a_proxy_that_starts_a_spell_holding_tier_proxies_with_no_choice_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 70756 holds Proxies 180595 to 180599, each naming one tier (Spell4.tierIndex 1
  // to 5) of Spell4Base 26252 with the same aim, phases and gates and the same tag
  // (emmComparison 0, emmValue 0), so nothing picks a tier; Proxy 180600 (Spell4 41926,
  // Flash, flags 5) starts it. Text 389501 promises Flash's own heal only.
  let left_out =
    Ok(spell_plan.LeftOut(why: spell_plan.ProxyStartsTiersNoChoice))
  [
    #("no foes", spell_tables.pressed),
    #("hits foes", spell_tables.pressed_hitting_foes),
  ]
  |> list.each(fn(place) {
    assert proxy_read_with(id: 180_600, place: place.1, edits: []) == left_out
      as {
        "Flash's Proxy 180600 is left out, the spell "
        <> place.0
        <> ": the shape, not the place, is what is wrong"
      }
  })
  let assert Ok(Applied(spell_plan.ReadProxy(targets: single, ..))) =
    proxy_read_with(id: 76_609, place: spell_tables.pressed, edits: [])
    as "Mental Boon's Proxy 76609 names one spell and holds no siblings: read"
  assert single == [spell_plan.OnCaster]
  // Synthetic cells of the real rows: each field the rule compares, given a different
  // value in each of the five tier Proxies (one edited Proxy would leave the other four
  // alike), so no two siblings are alike and the Proxy that starts the spell is read.
  let tier_proxies = [180_595, 180_596, 180_597, 180_598, 180_599]
  [
    #(
      "emmValue",
      "spend tag (as Mental Boon's rows 76772 to 76776 carry theirs)",
    ),
    #("targetFlags", "aim"),
    #("phaseFlags", "phases"),
    #("flags", "flags"),
    #("prerequisiteIdCasterApply", "caster apply gate"),
    #("prerequisiteIdTargetApply", "target apply gate"),
    #("dataBits06", "dataBits06"),
  ]
  |> list.each(fn(field) {
    let differing =
      list.index_map(tier_proxies, fn(id, index) {
        #("Spell4Effects", id, [#(field.0, Integer(index + 1))])
      })
    let assert Ok(Applied(spell_plan.ReadProxy(targets: chosen, ..))) =
      proxy_read_with(
        id: 180_600,
        place: spell_tables.pressed,
        edits: differing,
      )
      as {
        "tier Proxies that differ in their "
        <> field.1
        <> ": something picks the tier, so the Proxy is read"
      }
    assert chosen == [spell_plan.OnCaster]
  })
  let one_tier =
    list.map([180_596, 180_597, 180_598, 180_599], fn(id) {
      #("Spell4Effects", id, [#("spellId", Integer(33_262))])
    })
  let assert Ok(Applied(spell_plan.ReadProxy(targets: alone, ..))) =
    proxy_read_with(id: 180_600, place: spell_tables.pressed, edits: one_tier)
    as "one tier Proxy left in the spell: one tier is no choice to make, so the Proxy is read"
  assert alone == [spell_plan.OnCaster]
}

pub fn union_gain_row_is_still_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [spell_tables.pressed, spell_tables.pressed_hitting_foes],
    fn(place) {
      let result =
        spell_tables.read_row(
          effect: spell_tables.blank_effect(
            id: 1,
            spell: 1,
            effect_type: 1,
            target_flags: 5,
          ),
          place:,
        )
      assert result
        == Error(spell_plan.GainAimNotRead(
          spell4_id: 1,
          effect_id: 1,
          target_flags: 5,
        ))
        as "a VitalModifier row is read for the caster alone, whether or not its spell hits foes"
    },
  )
}

pub fn until_removed_union_control_row_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  assert read_client_row(id: 182_108, place: spell_tables.pressed)
    == Ok(spell_plan.LeftOut(why: spell_plan.StateUntilRemovedNotRead))
    as "CCStateSet row 182108 has flags bit 2, so it lasts until removed: the server drops it, as it drops a flag 2 row of that kind, whatever its aim"
}

pub fn no_absorb_or_armor_row_aimed_by_flags_3_or_7_is_in_a_child_started_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let effects = spell4_effects.all(client_tables.shared())
  let rows =
    effects
    |> list.filter(fn(effect) {
      { effect.effect_type == 29 || effect.effect_type == 52 }
      && { effect.target_flags == 3 || effect.target_flags == 7 }
    })
    |> list.sort(fn(a, b) { int.compare(a.id, b.id) })
    |> list.map(fn(effect) { #(effect.effect_type, effect.id, effect.spell_id) })
  assert rows == [#(29, 10_457, 5844), #(29, 14_809, 8285)]
    as "table_rows -- Spell4Effects effectType=29 holds two rows with targetFlags 3 or 7, 10457 (Spell4 5844, flags 7) and 14809 (Spell4 8285, flags 3), and effectType=52 holds none"
  assert list.filter(effects, fn(effect) {
      effect.effect_type == 26
      && list.contains([5844, 8285], effect.data_bits00)
    })
    == []
    as "table_rows -- Spell4Effects dataBits00=5844 and dataBits00=8285 find no row, so no Proxy starts either spell, on each struck unit or otherwise"
}
