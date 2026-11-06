//// A press checked against the spell's own cast conditions
//// (`genesis_prime/game/cast`): CasterCast (151) then TargetCast (281) after every other
//// check of the press, the waiver of a failed caster requirement, a held press checked
//// when it starts, and a condition the server cannot read. Expected values come from
//// these places, each named at its assertion:
//// - `0x1403ace00`: the press's last two checks are prerequisiteIdCasterCast (failure
////   151) and prerequisiteIdTargetCast (281), after CheckCast, CheckCastCaster and
////   CheckCastTarget; a press CheckCast marks 317 Queued returns before them and is
////   sent unchecked; a spell whose caster requirement block is set and whose
////   propertyFlags has bit 2 is not refused by CasterCast, which only waives the
////   requirement (`0x1403b1780`).
//// - `0x1403afb10.order`: the order of the caster checks (the dead caster, the
////   cooldowns, the requirements, the costs, the weapon).
//// - `Spell4.prerequisiteIdCasterCast` and the client's rows (`gleam run -m
////   genesis_prime/table_rows -- Prerequisite 903 12939 39321 29484 20117 29568 19750`):
////   the Esper's Spectral Form 58586 needs the caster in combat (903: type 28
////   comparison 1), the Stalker's Stealth 46073 needs it under none of the 11 spells of
////   spell group 313 (39321, nesting 12939), the Spellslinger's Spell Surge 47273 needs
////   Spell Power in slot 4 at least 25 or the caster under its own buff 47439 (29484, OR,
////   nesting 20117), the Warrior's Onslaught 46867 needs it under neither 35458 nor
////   35703 (29568), and Rampage 58524 holds 19750, which waives its requirement of 250
////   Kinetic Energy when the caster is under Overdrive 42908.
//// - `opcode.0x7fc`: a refusal is a 0x7fc {client cast id, Spell4 id, result}; a held
////   key's refusal names client cast id 0 (`cast.hold_answer`).
//// - The server's choice (the cast module's doc): a condition of a type the server
////   does not read, and every type 37 roll (a press draws none), refuses with the result
////   and a warning once for the spell, as a cost in a vital the server does not hold.
//// The planted spells use the bag indices of `cast_support`: base 1 is bag index 8,
//// base 3 is bag index 11.

import cast_support as support
import client_tables
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/class_resource
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, CastGate, NoCasterCast, RequirementWaiver, Spell,
}
import genesis_prime/game/spend
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_refused
import genesis_prime/step.{type TimerId, LogWarning}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support as prerequisites
import unitest

/// Bag index of base 1 and of base 3 (`cast_support.abilities`).
const gated_bag = 8

const under_bag = 11

/// Prerequisite 903 as the client holds it: type 28, comparison 1, in combat.
fn in_combat() -> Prerequisite {
  prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
}

/// A row with a condition of a type the server does not read (type 43, the quest log).
fn unread() -> Prerequisite {
  prerequisites.single(id: 41_834, condition: #(43, 1, 10_518, 4))
}

fn caster_in_combat(in_combat in_combat: Bool) -> Caster {
  cast.Caster(..support.caster(), in_combat:)
}

/// The plans with this spell at base 1, the bag index 8.
fn plans_with(spell spell: Spell) -> Plans {
  support.with_spells(plans: support.plans(), spells: [spell])
}

/// A spell of base 1 with these cast conditions.
fn gated(
  caster_cast caster_cast: spell_plan.CasterCast,
  target_cast target_cast: option.Option(Prerequisite),
) -> Spell {
  Spell(..support.child(spell4_id: 5001, base: 1), caster_cast:, target_cast:)
}

/// A press of the bag index by the caster, its go answered with no unit struck.
fn press(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.pressed_in(plans:, state:, caster:, bag_index: bag, target: 0, at: ms)
}

fn refusals(effects effects: List(Effect)) -> List(Int) {
  support.refusal_results(effects:)
}

/// The Spell4 id and the result of each 0x7fc, and the client cast id.
fn refused_frames(effects effects: List(Effect)) -> List(#(Int, Int, Int)) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_cast_refused.message_id {
      True -> {
        let assert Ok(refused) = spell_cast_refused.decode(frame.body)
          as "a 0x7fc the rule wrote decodes"
        Ok(#(
          refused.client_cast_id,
          refused.spell4_id,
          cast_result.to_value(refused.result),
        ))
      }
      False -> Error(Nil)
    }
  })
}

// ---- 5: Spectral Form ----

/// An Esper whose bag holds Spectral Form (Spell4Base 38012) at index 0.
fn esper(in_combat in_combat: Bool) -> Caster {
  cast.Caster(..support.caster(), abilities: [Spell4BaseId(38_012)], in_combat:)
}

pub fn an_esper_out_of_combat_pressing_spectral_form_is_refused_151_and_nothing_else_is_written_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(client_tables.shared())
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: esper(in_combat: False),
      bag: 0,
      at: 1000,
    )
  assert refused_frames(effects:) == [#(9, 58_586, 151)]
    as "Prerequisite 903 needs the caster in combat; the press is refused 0x7fc {client id 9, Spell4 58586, 151} (0x1403ace00)"
  assert support.ids(frames: support.writes(effects:)) == [0x07FC]
    as "nothing else is written: no 0x7fd, no cast"
  assert support.started_timers(effects:) == []
    && support.tells(effects:) == []
    && support.payments(effects:) == []
    as "no timer, no tell to a viewer, no payment"
  let #(_, in_combat_effects) =
    press(plans:, state:, caster: esper(in_combat: True), bag: 0, at: 1001)
  assert list.take(
      support.ids(frames: support.writes(effects: in_combat_effects)),
      1,
    )
    == [0x07FD]
    as "the refusal started no global cooldown: the same press a millisecond later, in combat, is confirmed with a 0x7fd"
}

pub fn an_esper_in_combat_pressing_spectral_form_casts_it_as_before_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(_, effects) =
    press(
      plans: spell_plan.plans(client_tables.shared()),
      state: cast.new(),
      caster: esper(in_combat: True),
      bag: 0,
      at: 1000,
    )
  let ids = support.ids(frames: support.writes(effects:))
  assert list.take(ids, 1) == [0x07FD] && refusals(effects:) == []
    as "in combat 903 passes: the press is confirmed with a 0x7fd and the cast goes on"
  assert list.contains(ids, 0x07F4) as "its go is written"
}

// ---- 6: the client's order ----

/// The result of a press of the planted spell the second time, after a first press that
/// was accepted by a caster in combat.
fn second_press_result(
  spell spell: Spell,
  first first: Caster,
  second second: Caster,
) -> List(Int) {
  let plans = plans_with(spell:)
  let #(state, first_effects) =
    press(plans:, state: cast.new(), caster: first, bag: gated_bag, at: 1000)
  assert refusals(effects: first_effects) == []
    as "the first press passes every check"
  let #(_, effects) =
    press(plans:, state:, caster: second, bag: gated_bag, at: 1100)
  refusals(effects:)
}

pub fn a_press_that_fails_its_cooldown_and_the_cast_condition_gets_15_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    Spell(
      ..gated(
        caster_cast: CastGate(prerequisite: in_combat()),
        target_cast: None,
      ),
      cooldown_ms: 5000,
    )
  assert second_press_result(
      spell:,
      first: caster_in_combat(in_combat: True),
      second: caster_in_combat(in_combat: False),
    )
    == [15]
    as "0x1403afb10.order: the cooldown (4900 ms left, 15) comes before CasterCast"
}

pub fn a_press_that_fails_its_cost_and_the_cast_condition_gets_50_plus_the_slot_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    Spell(
      ..gated(
        caster_cast: CastGate(prerequisite: in_combat()),
        target_cast: None,
      ),
      costs: [spell_plan.SlotCost(slot: 1, amount: 5000, result: 51)],
    )
  let #(_, effects) =
    press(
      plans: plans_with(spell:),
      state: cast.new(),
      caster: caster_in_combat(in_combat: False),
      bag: gated_bag,
      at: 1000,
    )
  assert refusals(effects:) == [51]
    as "the caster's slot 1 holds 1000 of the 5000 the cost asks: 50 + 1 (0x1403b3320), before CasterCast"
}

pub fn a_press_that_fails_the_weapon_and_the_cast_condition_gets_169_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    Spell(
      ..gated(
        caster_cast: CastGate(prerequisite: in_combat()),
        target_cast: None,
      ),
      weapon: spell_plan.PrimaryWeapon,
    )
  let #(_, effects) =
    press(
      plans: plans_with(spell:),
      state: cast.new(),
      caster: cast.Caster(..caster_in_combat(in_combat: False), weapon: None),
      bag: gated_bag,
      at: 1000,
    )
  assert refusals(effects:) == [169]
    as "no weapon in slot 16: 169 (0x1403afb10), the last of the caster checks and still before CasterCast"
}

pub fn a_dead_caster_whose_press_also_fails_the_cast_condition_gets_57_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    gated(caster_cast: CastGate(prerequisite: in_combat()), target_cast: None)
  let #(_, effects) =
    press(
      plans: plans_with(spell:),
      state: cast.new(),
      caster: cast.Caster(..caster_in_combat(in_combat: False), dead: True),
      bag: gated_bag,
      at: 1000,
    )
  assert refusals(effects:) == [57]
    as "the spell's caster condition row asks for a living caster (Caster_CannotBeDead, 57), the first check"
}

pub fn a_press_that_fails_both_cast_conditions_gets_151_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    gated(
      caster_cast: CastGate(prerequisite: in_combat()),
      target_cast: Some(in_combat()),
    )
  let #(_, effects) =
    press(
      plans: plans_with(spell:),
      state: cast.new(),
      caster: caster_in_combat(in_combat: False),
      bag: gated_bag,
      at: 1000,
    )
  assert refusals(effects:) == [151]
    as "0x1403ace00: CasterCast is checked first and returns its failure"
}

pub fn a_press_that_fails_the_target_cast_alone_gets_281_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = gated(caster_cast: NoCasterCast, target_cast: Some(in_combat()))
  let #(_, effects) =
    press(
      plans: plans_with(spell:),
      state: cast.new(),
      caster: caster_in_combat(in_combat: False),
      bag: gated_bag,
      at: 1000,
    )
  assert refusals(effects:) == [281]
    as "0x1403ace00: TargetCast fails with 281 (Prereq_TargetCast)"
}

pub fn a_refused_press_changes_nothing_else_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    gated(caster_cast: CastGate(prerequisite: in_combat()), target_cast: None)
  let plans = plans_with(spell:)
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: caster_in_combat(in_combat: False),
      bag: gated_bag,
      at: 1000,
    )
  assert support.ids(frames: support.writes(effects:)) == [0x07FC]
    && support.started_timers(effects:) == []
    as "a refusal is one 0x7fc: no 0x7fd, no timer"
  let #(_, again) =
    press(
      plans:,
      state:,
      caster: caster_in_combat(in_combat: True),
      bag: gated_bag,
      at: 1001,
    )
  assert refusals(effects: again) == []
    as "and it starts no cooldown: the next press, in combat, passes"
}

// ---- 7: a held press is checked at its start ----

fn due_timer(effects effects: List(Effect)) -> #(TimerId, Int) {
  let assert [started, ..] = support.started_timers(effects:)
    as "the step started a timer"
  started
}

/// A timer fired by this caster at the time, its go answered with no unit struck.
fn fired_by(
  state state: State,
  caster caster: Caster,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    cast.timer_fired(cast: state, timer:, caster:, now: support.at(ms:))
  support.answered_as(caster:, state:, effects:, at: ms, struck: [], rolls: [])
}

pub fn a_press_within_500_ms_of_its_cooldowns_end_is_held_with_nothing_written_and_checked_at_the_end_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    Spell(
      ..gated(
        caster_cast: CastGate(prerequisite: in_combat()),
        target_cast: None,
      ),
      cooldown_ms: 5000,
    )
  let plans = plans_with(spell:)
  let in_combat_caster = caster_in_combat(in_combat: True)
  let out_of_combat = caster_in_combat(in_combat: False)
  let #(state, _) =
    press(
      plans:,
      state: cast.new(),
      caster: in_combat_caster,
      bag: gated_bag,
      at: 1000,
    )
  // The cooldown ends at 6000; at 5700 300 ms are left, inside the queue window.
  let #(held, effects) =
    press(plans:, state:, caster: out_of_combat, bag: gated_bag, at: 5700)
  assert support.writes(effects:) == []
    as "0x1403ace00: a press CheckCast marks 317 returns before the prerequisites, so the client sends it unchecked and the server writes nothing when it holds it"
  let #(timer, after_ms) = due_timer(effects:)
  assert after_ms == 300 as "the cooldown's end"
  let #(_, at_the_end) =
    fired_by(state: held, caster: out_of_combat, timer:, at: 6000)
  assert refused_frames(effects: at_the_end) == [#(9, 5001, 151)]
    as "at its start the condition is checked as the client would have: 0x7fc {client id 9, Spell4 5001, 151}"
  assert !list.contains(
    support.ids(frames: support.writes(effects: at_the_end)),
    0x07FD,
  )
    as "nothing is started"
}

pub fn a_held_press_whose_condition_passes_at_its_start_casts_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    Spell(
      ..gated(
        caster_cast: CastGate(prerequisite: in_combat()),
        target_cast: None,
      ),
      cooldown_ms: 5000,
    )
  let plans = plans_with(spell:)
  let in_combat_caster = caster_in_combat(in_combat: True)
  let #(state, _) =
    press(
      plans:,
      state: cast.new(),
      caster: in_combat_caster,
      bag: gated_bag,
      at: 1000,
    )
  let #(held, effects) =
    press(plans:, state:, caster: in_combat_caster, bag: gated_bag, at: 5700)
  let #(timer, _) = due_timer(effects:)
  let #(_, at_the_end) =
    fired_by(state: held, caster: in_combat_caster, timer:, at: 6000)
  assert refusals(effects: at_the_end) == []
    && list.take(support.ids(frames: support.writes(effects: at_the_end)), 1)
    == [0x07FD]
    as "a condition that holds at the start lets the held press start: confirmed with a 0x7fd"
}

/// The planted spell of base 3 with a cast bar and a 1000 ms cast time, which is the
/// caster's current cast while it is live.
fn blocker() -> Spell {
  Spell(
    ..support.child(spell4_id: 5002, base: 3),
    cast_time_ms: 1000,
    cast_bar: spell_plan.ShowsCastBar,
  )
}

pub fn a_press_held_behind_the_current_cast_is_checked_again_when_that_cast_clears_test() -> Nil {
  use <- owned_test.run(5000)
  let gate =
    gated(caster_cast: CastGate(prerequisite: in_combat()), target_cast: None)
  let plans =
    support.with_spells(plans: support.plans(), spells: [gate, blocker()])
  let in_combat_caster = caster_in_combat(in_combat: True)
  let out_of_combat = caster_in_combat(in_combat: False)
  // The blocker starts at 1000 and its go, which clears the current cast, is at 2000.
  let #(state, started) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: in_combat_caster,
      bag_index: under_bag,
      target: 0,
      at: 1000,
    )
  let #(go_timer, _) = due_timer(effects: started)
  // 400 ms before the go: inside the window, so the press waits for the clear.
  let #(held, held_effects) =
    press(plans:, state:, caster: in_combat_caster, bag: gated_bag, at: 1600)
  assert support.writes(effects: held_effects) == []
    as "a press with 500 ms or less of the current cast left is held and nothing is written (cast.press_queue)"
  let #(_, cleared) =
    fired_by(state: held, caster: out_of_combat, timer: go_timer, at: 2000)
  assert refused_frames(effects: cleared) == [#(9, 5001, 151)]
    as "when the go clears the current cast the held press starts and its condition is checked then: out of combat, 151"
}

pub fn a_held_key_whose_repeat_fails_the_condition_gets_0x7fc_with_client_id_0_and_the_hold_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    Spell(
      ..gated(
        caster_cast: CastGate(prerequisite: in_combat()),
        target_cast: None,
      ),
      cooldown_ms: 2000,
    )
  let plans = plans_with(spell:)
  let in_combat_caster = caster_in_combat(in_combat: True)
  let out_of_combat = caster_in_combat(in_combat: False)
  let key = fn(state, caster, held, ms) {
    let assert Ok(#(state, effects)) =
      cast.take(
        cast: state,
        message: cast.KeyHeld,
        body: support.hold_body(bag_index: gated_bag, target: 0, held:),
        caster:,
        plans:,
        now: support.at(ms:),
      )
      as "a 0x4db that fits the message is taken"
    support.answered_as(
      caster:,
      state:,
      effects:,
      at: ms,
      struck: [],
      rolls: [],
    )
  }
  let #(state, first) = key(cast.new(), in_combat_caster, 1, 1000)
  assert refusals(effects: first) == []
    && list.contains(
      support.ids(frames: support.writes(effects: first)),
      0x07FF,
    )
    as "the first press of the held key passes in combat"
  // The cast over, the held key waits for the spell's cooldown on a timer of its own.
  let #(repeat_timer, after_ms) = due_timer(effects: first)
  assert after_ms == 2000
    as "the spell's cooldown of 2000 ms from the go at 1000"
  let #(state, repeated) =
    fired_by(state:, caster: out_of_combat, timer: repeat_timer, at: 3000)
  assert refused_frames(effects: repeated) == [#(0, 5001, 151)]
    as "the repeat is checked and refused 0x7fc {client id 0, Spell4 5001, 151}"
  let #(_, after_release) = key(state, out_of_combat, 0, 3100)
  assert support.started_timers(effects: after_release) == []
    as "the refusal ended the hold: no repeat is armed"
}

// ---- 8: Stealth, Spell Surge and Onslaught at the press ----

/// A planted spell of base 3 that, pressed, is a live cast with this Spell4 id and
/// these spell groups, for 1000 ms, aimed at the caster.
fn live_cast_of(spell4_id spell4_id: Int, groups groups: List(Int)) -> Spell {
  Spell(..support.child(spell4_id:, base: 3), cast_time_ms: 1000, groups:)
}

/// The real plans with the planted live-cast spell at base 3.
fn real_plans_with(spell spell: Spell) -> Plans {
  support.with_spells(plans: spell_plan.plans(client_tables.shared()), spells: [
    spell,
  ])
}

/// A caster of a class: the innate's base at bag index 0 and the planted spell at 1,
/// holding the class resource given or the default planted one.
fn classed(
  base base: Int,
  resources resources: option.Option(class_resource.Resources),
) -> Caster {
  let caster =
    cast.Caster(..support.caster(), abilities: [
      Spell4BaseId(base),
      Spell4BaseId(3),
    ])
  case resources {
    Some(held) -> cast.Caster(..caster, resources: held)
    None -> caster
  }
}

/// A press of the innate at bag index 0 after the planted spell was pressed at 1000, so
/// that the caster is under it, or after nothing: the refusals the innate's press gets.
fn innate_press(
  plans plans: Plans,
  caster caster: Caster,
  under under: Bool,
) -> List(Int) {
  let #(state, _) = case under {
    True -> press(plans:, state: cast.new(), caster:, bag: 1, at: 1000)
    False -> #(cast.new(), [])
  }
  let #(_, effects) = press(plans:, state:, caster:, bag: 0, at: 1100)
  refusals(effects:)
}

pub fn stealth_is_refused_151_under_a_spell_of_group_313_and_accepted_under_none_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans =
    real_plans_with(spell: live_cast_of(spell4_id: 40_838, groups: [313]))
  let stalker = classed(base: 30_075, resources: None)
  assert innate_press(plans:, caster: stalker, under: True) == [151]
    as "Prerequisite 39321 nests 12939: not under any spell of group 313, and 40838 is one of its 11 spells (Spell4GroupList 845)"
  assert innate_press(plans:, caster: stalker, under: False) == []
    as "under none, the press is accepted"
}

pub fn a_live_cast_of_another_group_does_not_stop_stealth_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans =
    real_plans_with(spell: live_cast_of(spell4_id: 40_838, groups: [5, 6]))
  assert innate_press(
      plans:,
      caster: classed(base: 30_075, resources: None),
      under: True,
    )
    == []
    as "group 313 is not among the groups of the cast the caster is under"
}

pub fn spell_surge_is_refused_151_at_24_spell_power_and_not_under_its_buff_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let spellslinger = fn(power) {
    classed(
      base: 31_213,
      resources: Some(support.holding(class_id: 7, value: power)),
    )
  }
  let plans =
    real_plans_with(spell: live_cast_of(spell4_id: 47_439, groups: []))
  assert innate_press(plans:, caster: spellslinger(24.0), under: False) == [151]
    as "Prerequisite 29484 is OR: slot 4 at least 25 fails at 24 and the nested 20117 (under 47439) fails"
  assert innate_press(plans:, caster: spellslinger(24.0), under: True) == []
    as "under Spell Surge's own buff 47439 the nested row passes: the press, which toggles it off, is accepted"
  assert innate_press(plans:, caster: spellslinger(25.0), under: False) == []
    as "at 25 Spell Power the first condition passes"
}

pub fn onslaught_is_refused_151_under_35458_and_accepted_otherwise_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let warrior = classed(base: 30_828, resources: None)
  let under_35458 =
    real_plans_with(spell: live_cast_of(spell4_id: 35_458, groups: []))
  assert innate_press(plans: under_35458, caster: warrior, under: True) == [151]
    as "Prerequisite 29568: not under 35458 and not under 35703, both comparison 2 under AND"
  let under_35703 =
    real_plans_with(spell: live_cast_of(spell4_id: 35_703, groups: []))
  assert innate_press(plans: under_35703, caster: warrior, under: True) == [151]
    as "35703 is the second condition"
  let under_other =
    real_plans_with(spell: live_cast_of(spell4_id: 35_459, groups: []))
  assert innate_press(plans: under_other, caster: warrior, under: True) == []
    as "under a cast of another spell it is accepted"
  assert innate_press(plans: under_35458, caster: warrior, under: False) == []
    as "under none it is accepted"
}

// ---- 9: Rampage's waiver ----

fn kinetic_energy(value value: Float) -> Caster {
  support.caster_holding(resources: support.holding(class_id: 1, value:))
}

/// The planted plans with the live-cast spell of Overdrive 42908 at base 3.
fn plans_with_overdrive() -> Plans {
  plans_with(spell: live_cast_of(spell4_id: 42_908, groups: []))
}

/// The planted spell of base 3 sits at the bag index 11.
fn rampage_press(caster caster: Caster, under under: Bool) -> List(Int) {
  let plans = plans_with_overdrive()
  let #(state, _) = case under {
    True -> press(plans:, state: cast.new(), caster:, bag: under_bag, at: 1000)
    False -> #(cast.new(), [])
  }
  let #(_, effects) =
    press(plans:, state:, caster:, bag: support.rampage, at: 1100)
  refusals(effects:)
}

pub fn rampage_at_249_kinetic_energy_is_refused_51_unless_the_caster_is_under_overdrive_test() -> Nil {
  use <- owned_test.run(5000)
  assert rampage_press(caster: kinetic_energy(value: 249.0), under: False)
    == [51]
    as "0x1403b1780: the requirement (250) fails and the waiver 19750 (under 42908) does not pass"
  assert rampage_press(caster: kinetic_energy(value: 249.0), under: True) == []
    as "under Overdrive 42908 the waiver passes: the client sends the press, and so does the server accept it"
  assert rampage_press(caster: kinetic_energy(value: 250.0), under: False) == []
    as "at 250 the requirement holds: 19750 is no gate, so not being under 42908 refuses nothing (0x1403ace00 skips CasterCast for a spell with the block and bit 2)"
}

pub fn a_waiver_of_a_type_the_server_does_not_read_refuses_with_the_requirements_result_and_one_warning_test() -> Nil {
  use <- owned_test.run(5000)
  let rampage =
    Spell(
      ..support.ability(base: 37_968),
      caster_cast: RequirementWaiver(prerequisite: unread()),
    )
  let plans = plans_with(spell: rampage)
  let caster = kinetic_energy(value: 249.0)
  let #(state, first) =
    press(plans:, state: cast.new(), caster:, bag: support.rampage, at: 1000)
  assert refusals(effects: first) == [51]
    as "the requirement fails, its waiver cannot be read: the requirement's result 51"
  let warnings =
    list.filter(support.logs(effects: first), fn(line) { line.0 == LogWarning })
  assert list.length(warnings) == 1
    as "one warning for the spell on the connection"
  let #(_, second) =
    press(plans:, state:, caster:, bag: support.rampage, at: 1100)
  assert refusals(effects: second) == [51]
    && support.logs(effects: second) == []
    as "a second press writes the 0x7fc alone"
}

// ---- 10: a cast condition the server cannot read ----

fn unread_refusal(spell spell: Spell, expecting expecting: Int) -> Nil {
  let plans = plans_with(spell:)
  let caster = caster_in_combat(in_combat: True)
  let #(state, first) =
    press(plans:, state: cast.new(), caster:, bag: gated_bag, at: 1000)
  assert refusals(effects: first) == [expecting]
    as "a condition of a type the server does not read refuses with the check's result"
  let warnings =
    list.filter(support.logs(effects: first), fn(line) { line.0 == LogWarning })
  assert list.length(warnings) == 1 as "and writes one warning for the spell"
  let #(_, second) = press(plans:, state:, caster:, bag: gated_bag, at: 1100)
  assert refusals(effects: second) == [expecting]
    && support.logs(effects: second) == []
    as "a second press writes the 0x7fc alone"
}

pub fn a_cast_condition_of_an_unread_type_refuses_151_with_one_warning_test() -> Nil {
  use <- owned_test.run(5000)
  unread_refusal(
    spell: gated(
      caster_cast: CastGate(prerequisite: unread()),
      target_cast: None,
    ),
    expecting: 151,
  )
}

pub fn a_target_cast_of_an_unread_type_refuses_281_with_one_warning_test() -> Nil {
  use <- owned_test.run(5000)
  unread_refusal(
    spell: gated(caster_cast: NoCasterCast, target_cast: Some(unread())),
    expecting: 281,
  )
}

pub fn a_type_37_roll_in_a_cast_condition_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  unread_refusal(
    spell: gated(
      caster_cast: CastGate(
        prerequisite: prerequisites.single(id: 4585, condition: #(37, 6, 0, 50)),
      ),
      target_cast: None,
    ),
    expecting: 151,
  )
}

// ---- 129: which casts the caster is under ----

/// A planted spell of base 3 with no cast time whose go holds a node of its cast on the
/// caster for a minute: the cast lingers after its go.
fn lingering_cast_of(
  spell4_id spell4_id: Int,
  groups groups: List(Int),
) -> Spell {
  Spell(..support.child(spell4_id:, base: 3), groups:, lasting: [
    spell_plan.Lasting(
      effect_id: Spell4EffectsId(1),
      phase_flags: -1,
      aim: spell_plan.AimsAtCaster,
      row: lasting.LastingRow(
        delay_ms: 0,
        duration_ms: 60_000,
        until_removed: False,
      ),
      condition: spell_plan.Always,
      tag: spend.always,
    ),
  ])
}

pub fn a_lingering_cast_of_group_313_stops_stealth_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans =
    real_plans_with(spell: lingering_cast_of(spell4_id: 40_838, groups: [313]))
  assert innate_press(
      plans:,
      caster: classed(base: 30_075, resources: None),
      under: True,
    )
    == [151]
    as "the cast's go has gone and its node on the caster still lives: the caster is under it (Prerequisite.prerequisiteTypeId.129 reads the unit's cast target nodes)"
}

pub fn a_live_cast_whose_primary_target_is_another_unit_does_not_stop_stealth_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // A Proxy aimed at each struck unit starts its child with that unit as the child's
  // primary target (`cast.child`); the child is a live cast of group 313's 40838.
  let child =
    Spell(
      ..support.child(spell4_id: 40_838, base: 40_838),
      cast_time_ms: 1000,
      groups: [313],
    )
  let parent =
    Spell(..support.child(spell4_id: 5003, base: 3), proxies: [
      spell_plan.Proxy(
        effect_id: Spell4EffectsId(2),
        delay_ms: 0,
        phase_flags: -1,
        condition: spell_plan.Always,
        tag: spend.always,
        target: spell_plan.OnEachStruck,
        spell: child,
        gains: [],
      ),
    ])
  let plans = real_plans_with(spell: parent)
  let stalker = classed(base: 30_075, resources: None)
  let #(state, started) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: stalker,
      bag_index: 1,
      target: 0,
      at: 1000,
    )
  let #(state, _) =
    support.answered_as(
      caster: stalker,
      state:,
      effects: started,
      at: 1000,
      struck: [cast.Hit(unit_id: 99, descriptions: [], controls: [])],
      rolls: [],
    )
  let #(_, effects) = press(plans:, state:, caster: stalker, bag: 0, at: 1100)
  assert refusals(effects:) == []
    as "the child's primary target is the unit 99, not the caster: the caster is not under it, and the press is accepted"
}
