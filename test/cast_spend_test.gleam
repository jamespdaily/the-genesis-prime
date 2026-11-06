//// A press of a spell with an innate cost EMM id, paid and chosen by the points
//// spent (`genesis_prime/game/cast` with `genesis_prime/game/spend`). Expected
//// values come from these places, each named at its assertion:
//// - `Spell4.32809`: Mind Burst costs 1 Psi Point (type 6, slot 1) with innateCostEMMId0
////   4, so a press that spends p Psi Points (1 to 5) strikes with the damage effect
////   whose emmValue is p - 1 (61993 to 61997), starts the Proxy 135961 (emmComparison
////   0, emmValue 4) only at p = 5 and the Proxy 230116 (emmComparison 1, emmValue 2)
////   at p of 3 and more, behind its caster gate.
//// - `0x1403b3320`: the client refuses a press with fewer points than the base cost
////   (51 for slot 1) and checks only the base cost; it never lowers a resource itself,
////   so the server takes the points and sends the new value in 0x935 (`opcode.0x935`).
//// - `Spell4.innateCostEMMId0`: an id other than 4 or 7 is not read, so its press is
////   refused with the cost's result.
//// - `Spell4.32812`: Crush has no EMM id; its Proxy 62007 holds a stray (0, 4) and
////   still starts.
//// - The cast rule's doc comment: a cost is paid at the accept, in the step of its
////   check, so a second press taken in the same step is checked against what the
////   first left; a held press is checked when it starts.
//// The bag index 2 is Mind Burst, with the plan of `spell_tables.plans_with_mind_burst_spend`.

import cast_support as support
import class_resource_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast.{type GoAsked}
import genesis_prime/game/class_resource.{type Resources, Payment, Resource}
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Plans, type Spell, Proxy, Spell}
import genesis_prime/game/spend
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug, LogWarning}
import genesis_prime/table/id.{Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import prerequisite_support
import spell_tables

const mind_burst = 2

const crush = 1

/// 2^31 + 7 x 2^11: the caster 7's first cast id.
const first_cast = 2_147_497_984

fn mind_burst_spell() -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.plans_with_mind_burst_spend(),
      base: id.Spell4BaseId(19_019),
    )
    as "the planted Esper holds Mind Burst with its spend"
  spell
}

/// The cast tests' plans with this Mind Burst.
fn plans_with(spell spell: Spell) -> Plans {
  support.with_spells(plans: support.plans(), spells: [spell])
}

/// The Esper's resource (Class 3: slot 1, a maximum of 5) holding `points`.
fn esper_holding(points points: Int) -> Resources {
  class_resource.new(
    resource: Resource(
      ..class_resource_support.resource_of(3),
      start: int.to_float(points),
    ),
  )
}

fn caster_holding(points points: Int) -> cast.Caster {
  support.caster_holding(resources: esper_holding(points:))
}

/// A press of Mind Burst by an Esper holding `points`, as the rule gives it.
fn press(
  spell spell: Spell,
  points points: Int,
) -> #(cast.State, List(cast.Effect)) {
  support.pressed_raw_in(
    plans: plans_with(spell:),
    state: cast.new(),
    caster: caster_holding(points:),
    bag_index: mind_burst,
    target: 0,
    at: 1000,
  )
}

fn asked_goes(effects effects: List(cast.Effect)) -> List(GoAsked) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.Strike(asked:) -> Ok(asked)
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..) -> Error(Nil)
    }
  })
}

fn refusal_results(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == spell_cast_refused.message_id {
      True -> {
        let assert Ok(refused) = spell_cast_refused.decode(frame.body)
          as "0x7fc decodes"
        Ok(cast_result.to_value(refused.result))
      }
      False -> Error(Nil)
    }
  })
}

/// The Spell4 id of each cast the writes start, in order.
fn started(effects effects: List(cast.Effect)) -> List(Int) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "0x7ff decodes"
        Ok(start.spell4_id)
      }
      False -> Error(Nil)
    }
  })
}

fn debug_lines(effects effects: List(cast.Effect)) -> List(String) {
  list.filter_map(support.logs(effects:), fn(line) {
    case line.0 == LogDebug {
      True -> Ok(line.1)
      False -> Error(Nil)
    }
  })
}

// ---- 5: the accept takes every point and the go carries n ----

pub fn mind_burst_at_p_points_takes_all_p_and_asks_its_go_with_p_minus_1_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([1, 2, 3, 4, 5], fn(points) {
    let #(_, effects) = press(spell: mind_burst_spell(), points:)
    assert support.payments(effects:) == [Payment(slot: 1, amount: points)]
      as "Spell4.innateCostEMMId0 4: every point held is spent; 0x1403b3320 checks the base cost of 1 only"
    let assert [asked] = asked_goes(effects:)
      as "Mind Burst has no cast time: its go is asked at the accept"
    assert asked.spent == Some(points - 1)
      as "Spell4Effects.emmComparison: n is the points spent above the base cost of 1"
    assert asked.spell4_id == Spell4Id(32_809)
  })
}

pub fn the_payment_of_every_point_leaves_0_and_is_one_change_of_the_psi_points_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([1, 2, 3, 4, 5], fn(points) {
    let #(_, effects) = press(spell: mind_burst_spell(), points:)
    let #(left, changes) =
      class_resource.pay(
        resources: esper_holding(points:),
        payments: support.payments(effects:),
      )
    assert class_resource.value(resources: left, slot: 1) == 0.0
    assert list.filter(changes, fn(change) {
        case change {
          class_resource.Changed(..) -> True
          class_resource.StartTimer(..) | class_resource.CancelTimer(..) ->
            False
        }
      })
      == [class_resource.Changed(slot: 1, value: 0.0)]
      as "opcode.0x935: the client never lowers the points itself, so one 0x935 of slot 1 with the new value 0 is sent"
  })
}

// ---- 6: the Proxies are chosen by n ----

/// Mind Burst with the Proxies' gates the client's rows hold replaced: 135961 by none
/// and 230116 by this one, so a test of the choice by n is not stopped by a gate the
/// caster fails: the client's 23344 asks for a cast of 57027, the AMP Reckful, and
/// 44174 holds two type 15 conditions on spells a lasting effect gives. Each Proxy
/// keeps the tag of its row.
fn mind_burst_with_gate(gate gate: prerequisite.Prerequisite) -> Spell {
  let mind_burst = mind_burst_spell()
  Spell(
    ..mind_burst,
    proxies: list.map(mind_burst.proxies, fn(proxy: spell_plan.Proxy) {
      case proxy.spell.spell4_id == Spell4Id(57_030) {
        True -> Proxy(..proxy, condition: spell_plan.Always)
        False ->
          Proxy(..proxy, condition: spell_plan.GatedOnCaster(gates: [gate]))
      }
    }),
  )
}

fn in_combat_gate() -> prerequisite.Prerequisite {
  prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0))
}

/// Every effect of a press of Mind Burst by an Esper holding `points` in combat, its
/// go answered by a round that struck nobody, taking these rolls.
fn pressed_and_gone(
  spell spell: Spell,
  points points: Int,
  rolls rolls: List(Int),
) -> List(cast.Effect) {
  let caster = cast.Caster(..caster_holding(points:), in_combat: True)
  let #(state, raw) =
    support.pressed_raw_in(
      plans: plans_with(spell:),
      state: cast.new(),
      caster:,
      bag_index: mind_burst,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_as(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck: [],
      rolls:,
    )
  effects
}

pub fn proxy_135961_starts_its_spell_only_at_5_points_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = mind_burst_with_gate(gate: in_combat_gate())
  let crit_buff_started = fn(points) {
    list.count(
      started(effects: pressed_and_gone(spell:, points:, rolls: [])),
      fn(spell4_id) { spell4_id == 57_030 },
    )
  }
  assert list.map([1, 2, 3, 4, 5], crit_buff_started) == [0, 0, 0, 0, 1]
    as "Spell4Effects 135961: emmComparison 0, emmValue 4, so the Proxy to 57030 applies when n is 4, which is 5 Psi Points spent"
}

pub fn proxy_230116_starts_its_spell_at_3_points_and_more_behind_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = mind_burst_with_gate(gate: in_combat_gate())
  let rune_started = fn(points) {
    list.count(
      started(effects: pressed_and_gone(spell:, points:, rolls: [])),
      fn(spell4_id) { spell4_id == 87_353 },
    )
  }
  assert list.map([1, 2, 3, 4, 5], rune_started) == [0, 0, 1, 1, 1]
    as "Spell4Effects 230116: emmComparison 1, emmValue 2, so the Proxy to 87353 applies when n is at least 2, which is 3 Psi Points spent or more"
  let failing = mind_burst_with_gate(gate: out_of_combat_gate())
  assert started(
      effects: pressed_and_gone(spell: failing, points: 4, rolls: []),
    )
    == []
    as "the caster gate still decides: it fails in combat, so the child does not start (the press itself is confirmed by a 0x7fd, not a 0x7ff)"
}

fn out_of_combat_gate() -> prerequisite.Prerequisite {
  prerequisite_support.single(id: 1, condition: #(28, 2, 0, 0))
}

pub fn the_gate_of_a_proxy_that_n_does_not_choose_is_not_checked_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 4585 is type 37, comparison 6, value 50: a roll is drawn for it
  // only when it is checked.
  let spell =
    mind_burst_with_gate(
      gate: prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50)),
    )
  let rolls_taken = fn(points) {
    let #(state, _) = press(spell:, points:)
    cast.rolls_needed(cast: state, cast_id: first_cast, phase: 0, struck: [])
  }
  assert list.map([1, 2, 3, 4, 5], rolls_taken) == [0, 0, 1, 1, 1]
    as "230116 holds the only gate and applies from 3 Psi Points: below it no gate is checked, so no roll is drawn (Spell4Effects.emmComparison)"
}

/// The client's gate 23344 on the Proxy 135961 asks for the AMP Reckful's spell 57027
/// cast by the caster itself (type 50, `Prerequisite.prerequisiteTypeId.50`;
/// EldanAugmentation 340). A caster that holds no such cast fails it: the crit buff
/// 57030 does not start at any point, and the gate leaves no debug line, since the
/// server reads type 50.
pub fn a_5_point_mind_burst_without_the_reckful_amp_starts_no_crit_buff_test() -> Nil {
  use <- owned_test.run(60_000)
  let crit_buff_started = fn(points) {
    list.count(
      started(
        effects: pressed_and_gone(spell: mind_burst_spell(), points:, rolls: []),
      ),
      fn(spell4_id) { spell4_id == 57_030 },
    )
  }
  assert list.map([1, 2, 3, 4, 5], crit_buff_started) == [0, 0, 0, 0, 0]
    as "Prerequisite 23344 fails: the caster holds no cast of 57027 (the issue's evidence: EldanAugmentation 340)"
  let crit_gate_lines = fn(points) {
    list.count(
      debug_lines(
        effects: pressed_and_gone(spell: mind_burst_spell(), points:, rolls: []),
      ),
      fn(line) { string.contains(line, "prerequisite 23344") },
    )
  }
  assert list.map([1, 2, 3, 4, 5], crit_gate_lines) == [0, 0, 0, 0, 0]
    as "type 50 is read, so its gate decides and says nothing"
}

pub fn a_5_point_mind_burst_with_the_reckful_amp_held_starts_the_crit_buff_test() -> Nil {
  use <- owned_test.run(60_000)
  // A planted spell 57027 on bag index 11 whose go gives the caster a node that
  // lasts until removed, as the AMP's lasting effect does.
  let amp =
    Spell(..support.child(spell4_id: 57_027, base: 3), lasting: [
      spell_plan.Lasting(
        effect_id: id.Spell4EffectsId(1),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: 0,
          until_removed: True,
        ),
        condition: spell_plan.Always,
        tag: spend.always,
      ),
    ])
  let plans =
    support.with_spells(plans: plans_with(spell: mind_burst_spell()), spells: [
      amp,
    ])
  let caster = cast.Caster(..caster_holding(points: 5), in_combat: True)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: 11,
      target: 0,
      at: 500,
    )
  let #(state, _) =
    support.answered_as(
      caster:,
      state:,
      effects: raw,
      at: 500,
      struck: [],
      rolls: [],
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: mind_burst,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_as(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck: [],
      rolls: [],
    )
  assert list.count(started(effects:), fn(spell4_id) { spell4_id == 57_030 })
    == 1
    as "with a cast of 57027 by the caster on it, gate 23344 passes and 57030 starts (Prerequisite.prerequisiteTypeId.50)"
}

// ---- 7 to 9: what the costs check ----

pub fn mind_burst_with_no_psi_point_is_refused_51_and_pays_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, effects) = press(spell: mind_burst_spell(), points: 0)
  assert refusal_results(frames: support.writes(effects:)) == [51]
    as "0x1403b3320: 0 of slot 1 is below the base cost of 1, refused 51 (CasterVitalCostResource1)"
  assert support.payments(effects:) == []
  assert asked_goes(effects:) == []
}

/// Mind Burst with no global cooldown, so a second press of it in the same step
/// meets only its cost.
fn quick_mind_burst() -> Spell {
  Spell(
    ..mind_burst_spell(),
    global_cooldown: spell_plan.GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
  )
}

pub fn a_second_press_in_the_same_step_is_refused_51_after_a_spend_of_all_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = plans_with(spell: quick_mind_burst())
  let caster = caster_holding(points: 3)
  let take = fn(state, message, body, at) {
    let assert Ok(taken) =
      cast.take(
        cast: state,
        message:,
        body:,
        caster:,
        plans:,
        now: support.at(ms: at),
      )
      as "taken"
    taken
  }
  // Telekinetic Strike's 1250 ms cast bar is the current cast from 1000.
  let #(state, started) =
    take(
      cast.new(),
      cast.Pressed,
      support.press_body(client_cast_id: 8, bag_index: 0, target: 0, press: 1),
      1000,
    )
  // Mind Burst pressed with 450 ms of it left is held for the go that clears it, and
  // its key held down waits behind the held press.
  let #(state, _) =
    take(
      state,
      cast.Pressed,
      support.press_body(
        client_cast_id: 9,
        bag_index: mind_burst,
        target: 0,
        press: 1,
      ),
      1800,
    )
  let #(state, _) =
    take(
      state,
      cast.KeyHeld,
      support.hold_body(bag_index: mind_burst, target: 0, held: 1),
      1900,
    )
  let assert [#(go_timer, _), ..] = support.started_timers(effects: started)
  let #(state, fired) =
    cast.timer_fired(
      cast: state,
      timer: go_timer,
      caster:,
      now: support.at(ms: 2250),
    )
  let assert [cast.Strike(asked:)] = fired as "the go is asked"
  let #(_, effects) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 2250),
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
  assert support.payments(effects:) == [Payment(slot: 1, amount: 3)]
    as "the held press spends all 3 Psi Points"
  assert refusal_results(frames: support.writes(effects:)) == [51]
    as "the hold's press in the same step meets the 0 the first left, not the 3 the step began with: 51 (0x1403b3320)"
}

pub fn a_held_press_chooses_by_the_points_held_when_it_starts_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = plans_with(spell: mind_burst_spell())
  let pressing = caster_holding(points: 2)
  let at_the_go = caster_holding(points: 5)
  let take = fn(state, body, at) {
    let assert Ok(taken) =
      cast.take(
        cast: state,
        message: cast.Pressed,
        body:,
        caster: pressing,
        plans:,
        now: support.at(ms: at),
      )
      as "taken"
    taken
  }
  let #(state, started) =
    take(
      cast.new(),
      support.press_body(client_cast_id: 8, bag_index: 0, target: 0, press: 1),
      1000,
    )
  let #(state, held) =
    take(
      state,
      support.press_body(
        client_cast_id: 9,
        bag_index: mind_burst,
        target: 0,
        press: 1,
      ),
      1800,
    )
  assert held == []
    as "Mind Burst is pressed with 450 ms of the current cast left: held, nothing paid or written"
  let assert [#(go_timer, _), ..] = support.started_timers(effects: started)
  let #(state, fired) =
    cast.timer_fired(
      cast: state,
      timer: go_timer,
      caster: at_the_go,
      now: support.at(ms: 2250),
    )
  let assert [cast.Strike(asked: first)] = fired as "the go is asked"
  let #(_, effects) =
    support.went(
      cast: state,
      caster: at_the_go,
      now: support.at(ms: 2250),
      cast_id: first.cast_id,
      phase: first.phase,
      struck: [],
    )
  assert support.payments(effects:) == [Payment(slot: 1, amount: 5)]
    as "the held press is checked and paid when it starts, against the 5 points then held, not the 2 held at the press"
  let assert [mind_burst_go] = asked_goes(effects:)
  assert mind_burst_go.spell4_id == Spell4Id(32_809)
    && mind_burst_go.spent == Some(4)
    as "n is 5 - 1, from the points held when the press starts"
}

// ---- 10: a spend the server does not read ----

pub fn an_unread_emm_id_is_refused_with_its_costs_result_logged_once_and_pays_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(plans) =
    spell_tables.with_loaded(
      rows: spell_tables.rows_with_mind_burst_spend(
        emm_id: 5,
        cost: #(6, 1),
        damage: spell_tables.mind_burst_damage,
      ),
      body: fn(tables) { spell_plan.build(tables:) },
    )
    as "the planted rows with an EMM id of 5 build"
  let assert Ok(unread) =
    spell_plan.in_plans(plans:, base: id.Spell4BaseId(19_019))
  let take = fn(state, at) {
    support.pressed_raw_in(
      plans: plans_with(spell: unread),
      state:,
      caster: caster_holding(points: 3),
      bag_index: mind_burst,
      target: 0,
      at:,
    )
  }
  let #(state, first) = take(cast.new(), 1000)
  assert refusal_results(frames: support.writes(effects: first)) == [51]
    as "Spell4.innateCostEMMId0: the meaning of 5 is not in the client, so the press is refused with the cost's result, type 6: 51"
  assert support.payments(effects: first) == []
  assert asked_goes(effects: first) == []
  let assert [#(LogWarning, text)] = support.logs(effects: first)
    as "the first refusal is logged once, as a cost in a vital the server does not hold is"
  assert string.contains(text, "32809") && string.contains(text, "51")
  let #(_, second) = take(state, 3000)
  assert refusal_results(frames: support.writes(effects: second)) == [51]
  assert support.logs(effects: second) == []
    as "the same Spell4 is logged once on the connection"
}

// ---- 11: a spell with no EMM id keeps every effect ----

pub fn crush_keeps_every_effect_at_any_points_held_test() -> Nil {
  use <- owned_test.run(60_000)
  let crush_spell = support.ability(base: 19_022)
  assert list.map(crush_spell.proxies, fn(proxy) { proxy.tag })
    == [spend.EqualTo(value: 4)]
    as "Spell4.32812: the Proxy 62007 holds a stray (emmComparison 0, emmValue 4) and the spell has no EMM id"
  list.each([0, 3, 5], fn(points) {
    let #(state, raw) =
      support.pressed_raw(
        state: cast.new(),
        caster: caster_holding(points:),
        bag_index: crush,
        target: 0,
        at: 1000,
      )
    assert support.payments(effects: raw) == [] as "Crush has no cost"
    let assert [asked] = asked_goes(effects: raw)
    assert asked.spent == None
      as "Spell4.32812 has no EMM id, so its cast has no n and chooses nothing"
    let #(_, effects) =
      support.went(
        cast: state,
        caster: caster_holding(points:),
        now: support.at(ms: 1000),
        cast_id: asked.cast_id,
        phase: 0,
        struck: [cast.Hit(unit_id: 10, descriptions: [], controls: [])],
      )
    assert list.any(support.started_timers(effects:), fn(timer) {
      timer.1 == 100
    })
      as "Spell4Effects 62007: the Proxy to 42297 starts 100 ms after the go whatever its stray tag says"
  })
}
