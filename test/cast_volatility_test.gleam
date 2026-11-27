//// The Engineer's Volatility gain in the cast rule (`genesis_prime/game/cast` `Gain`,
//// the server's Proxy of `genesis_prime/shared/server_proxy`): a Pulse Blast casts the
//// hidden spell 42148 with the last go of the spell that strikes, and 42148's gain gives
//// +15 of slot 1 behind prerequisite 903 (the caster is in combat). Expected values
//// come from these places, each named at its assertion:
//// - The client's rows:
////   `Spell4.42148` (95337: +15 of vital 6 behind 903), `Prerequisite.prerequisiteTypeId.28`
////   (903: in combat), Pulse Blast 42276 (gos at 0 and 1250 ms, SpellPhase 5390 and
////   5391; Proxy 95881 to the damage spell 37302 at its second go), 37302 (gos at 0, 1, 2
////   and 3 ms, SpellPhase 2820 to 2823; its damage 79090, 79092 and 79093 is in goes 1 to 3,
////   phaseFlags 2, 4 and 8) and Electrocute (41276: innateCostType0 6, innateCost0 8,
////   `Spell4CastResult.vital_cost`).
//// - The server's choices: one +15 for each Pulse Blast cast, at its striking go (the
////   client's prerequisite 903 holds it to combat), and the Pulse Blast that opens a
////   fight gives it too: the gain comes with the damage spell's last go, after the
////   creature's threat, which follows its first answer, has turned the combat flag on
////   (`game_connection_volatility_test`).
//// The bag indices are `cast_support.abilities`'.

import cast_support as support
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/unit_news
import genesis_prime/message/cast_result
import genesis_prime/message/spell_started
import genesis_prime/shared/class_resource.{Gain, Payment}
import genesis_prime/shared/spell_plan
import genesis_prime/table/id.{Spell4Id}
import gleam/dict
import gleam/list
import gleam/string
import owned_test
import spell_tables

/// The damage spell Pulse Blast's second go starts on the caster (`Spell4Effects.effectType.26`:
/// 95881), which strikes the area in its goes 1 to 3 and nothing in its go 0.
const striking_spell = 37_302

/// The same damage spell of Pulse Blast's tier 2 row 53409, whose Proxy 126783 starts it
/// (`table_rows -- Spell4Effects spellId=53409`); its damage rows 133992 to 133994 are in its
/// goes 1 to 3 as tier 1's are.
const striking_spell_at_tier_2 = 56_145

/// An Engineer with nothing in its Volatility, in or out of combat.
fn engineer(in_combat in_combat: Bool) -> Caster {
  cast_state.Caster(
    ..support.caster(),
    resources: support.holding(class_id: 2, value: 0.0),
    in_combat:,
  )
}

/// The units a go strikes: the damage spell strikes `foes` in the goes that hold its damage,
/// and a spell with no area strikes none (42148 has none, `strike.select`).
fn striking(
  foes foes: List(Int),
) -> fn(cast_state.GoAsked) -> List(cast_state.Struck) {
  fn(asked: cast_state.GoAsked) {
    case
      list.contains(
        [Spell4Id(striking_spell), Spell4Id(striking_spell_at_tier_2)],
        asked.spell4_id,
      )
      && asked.phase > 0
    {
      True -> support.hits(foes)
      False -> []
    }
  }
}

/// A press of the bag index at 1000 and every timer it leads to, as (time, effects), each
/// go answered by `striking`.
fn pressed_through(
  caster caster: Caster,
  bag_index bag_index: Int,
  foes foes: List(Int),
) -> #(State, List(#(Int, List(Effect)))) {
  pressed_through_in(
    plans: spell_tables.plans_with_server_proxies(),
    caster:,
    bag_index:,
    foes:,
  )
}

/// The same on these plans.
fn pressed_through_in(
  plans plans: spell_plan.Plans,
  caster caster: Caster,
  bag_index bag_index: Int,
  foes foes: List(Int),
) -> #(State, List(#(Int, List(Effect)))) {
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index:,
      target: 0,
      at: 1000,
    )
  let #(state, pressed) =
    support.answered_each(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck_of: striking(foes:),
      rolls: [],
      poses: dict.new(),
    )
  let #(state, fired) =
    support.run_timers_each(
      caster:,
      state:,
      effects: pressed,
      from_ms: 1000,
      struck_of: striking(foes:),
    )
  #(state, [#(1000, pressed), ..fired])
}

/// A Pulse Blast pressed by this caster and every effect of its timers, in order.
fn pulse_blast(
  caster caster: Caster,
  foes foes: List(Int),
) -> List(#(Int, List(Effect))) {
  pressed_through(caster:, bag_index: support.pulse_blast, foes:).1
}

fn every(steps: List(#(Int, List(Effect)))) -> List(Effect) {
  list.flat_map(steps, fn(step) { step.1 })
}

/// The times at which each step gave resource points, and what it gave.
fn gains_at(
  steps: List(#(Int, List(Effect))),
) -> List(#(Int, List(List(class_resource.Gain)))) {
  list.filter_map(steps, fn(step) {
    case support.gains(effects: step.1) {
      [] -> Error(Nil)
      gains -> Ok(#(step.0, gains))
    }
  })
}

/// The lines the client reads of 42148's cast among the casts the effects write, the cast's
/// label written `k`.
fn lines_of_42148(effects: List(Effect)) -> List(String) {
  let lines = support.cast_lines(frames: support.writes(effects:))
  let ids =
    list.filter_map(lines, fn(line) {
      case string.split(line, " ") {
        ["started", id, "42148", ..] -> Ok(id)
        _ -> Error(Nil)
      }
    })
  list.filter_map(lines, fn(line) {
    case string.split(line, " ") {
      [word, id, ..rest] ->
        case list.contains(ids, id) {
          True -> Ok(string.join([word, "k", ..rest], " "))
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

// ---- 2 ----

pub fn a_pulse_blast_that_hits_a_foe_in_combat_gives_15_volatility_at_its_striking_go_test() -> Nil {
  use <- owned_test.run(5000)
  let steps = pulse_blast(caster: engineer(in_combat: True), foes: [10])
  assert gains_at(steps) == [#(2253, [[Gain(slot: 1, amount: 15)]])]
    as "one +15 of slot 1 (Spell4Effects 95337, behind 903, which an in-combat caster passes) with the damage spell's last go, 1253 ms after the press, and not at the press or the first go"
  let assert [#(_, with_the_gain)] =
    list.filter(steps, fn(step) { support.gains(effects: step.1) != [] })
  assert lines_of_42148(with_the_gain)
    == [
      "started k 42148 root 42276 parent 37302",
      "went k p0",
      "finished k",
    ]
    as "42148 starts with the damage spell as its parent and Pulse Blast as its root (opcode.0x7ff.root_parent), goes once and finishes"
  // The player holds Pulse Blast at tier 2: the plan under its base is the tier 2 row's
  // (root 53409, whose Proxy 126783 starts 56145), the server's Proxy is planted into it, and
  // 42148 goes with 56145's last go, so the striking go gives 15 as at tier 1.
  let tier_2 =
    pressed_through_in(
      plans: spell_tables.plans_with_server_proxies_at(base: 26_468, tier: 2),
      caster: engineer(in_combat: True),
      bag_index: support.pulse_blast,
      foes: [10],
    ).1
  assert gains_at(tier_2) == [#(2253, [[Gain(slot: 1, amount: 15)]])]
    as "the tier 2 cast gives its +15 with 56145's last go, 1253 ms after the press"
  assert lines_of_42148(every(tier_2))
    == [
      "started k 42148 root 53409 parent 56145",
      "went k p0",
      "finished k",
    ]
    as "42148 starts with tier 2's damage spell as its parent and tier 2's root: the server's Proxy is planted into the tier's own plan"
}

// ---- 3 ----

pub fn a_pulse_blast_that_strikes_no_foe_out_of_combat_casts_42148_and_gives_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let steps = pulse_blast(caster: engineer(in_combat: False), foes: [])
  assert gains_at(steps) == []
    as "903 fails for a caster that is not in combat and hit nobody"
  assert lines_of_42148(every(steps))
    == [
      "started k 42148 root 42276 parent 37302",
      "went k p0",
      "finished k",
    ]
    as "42148 is still cast: the prerequisite gates the gain, not the Proxy"
}

// ---- 5 ----

pub fn one_gain_for_each_cast_whether_it_strikes_three_foes_or_none_in_combat_test() -> Nil {
  use <- owned_test.run(5000)
  let three = pulse_blast(caster: engineer(in_combat: True), foes: [10, 11, 12])
  assert gains_at(three) == [#(2253, [[Gain(slot: 1, amount: 15)]])]
    as "tooltips 376222, 491167 and 491176 say 'generate' once with no 'per foe' (server choice): one gain for three foes"
  let none = pulse_blast(caster: engineer(in_combat: True), foes: [])
  assert gains_at(none) == [#(2253, [[Gain(slot: 1, amount: 15)]])]
    as "an in-combat cast that strikes none still gives 15 (the server's choice)"
}

// ---- 7 ----

pub fn a_pulse_blast_cancelled_before_1250_ms_casts_no_42148_and_gives_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let caster = engineer(in_combat: True)
  let #(state, raw) =
    support.pressed_raw_in(
      plans: spell_tables.plans_with_server_proxies(),
      state: cast_state.new(),
      caster:,
      bag_index: support.pulse_blast,
      target: 0,
      at: 1000,
    )
  let #(state, pressed) =
    support.answered_each(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck_of: striking(foes: [10]),
      rolls: [],
      poses: dict.new(),
    )
  let cast_id = support.pressed_id(effects: pressed)
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans: spell_tables.plans_with_server_proxies(),
      state:,
      cast_id:,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 2000,
    )
  assert list.length(support.cancelled_timers(effects: cancelled)) >= 1
    as "0x801 cancels the pending go"
  let #(_, late) =
    support.run_timers_each(
      caster:,
      state:,
      effects: pressed,
      from_ms: 1000,
      struck_of: striking(foes: [10]),
    )
  assert gains_at(late) == []
    as "a go that fires after the cancel finds no live cast: no 42148 and no gain (opcode.0x801)"
  assert lines_of_42148(every(late)) == []
}

// ---- 8 ----

pub fn electrocute_is_refused_51_at_0_volatility_and_accepted_after_a_pulse_blast_pays_8_at_its_go_test() -> Nil {
  use <- owned_test.run(5000)
  let empty = engineer(in_combat: True)
  let #(_, refused) =
    support.pressed_raw_in(
      plans: spell_tables.plans_with_server_proxies(),
      state: cast_state.new(),
      caster: empty,
      bag_index: support.electrocute,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: refused) == [51]
    as "Electrocute costs 8 of vital 6 (Spell4 41276: innateCostType0 6, innateCost0 8); an empty slot 1 refuses 50 + 1 (`Spell4CastResult.vital_cost`, 0x1403b3320)"
  let gained =
    cast_state.Caster(
      ..empty,
      resources: support.holding(class_id: 2, value: 15.0),
    )
  let accepted =
    every(
      pressed_through(caster: gained, bag_index: support.electrocute, foes: []).1,
    )
  assert support.refusal_results(effects: accepted) == []
    as "with the 15 a Pulse Blast gave, Electrocute is accepted"
  assert support.payments(effects: accepted) == [Payment(slot: 1, amount: 8)]
    as "its first go pays 8, so the slot shows 15 - 8 = 7, and the second go finds 7 below its 8, so the channel ends there: one payment, not one a go"
}

// ---- 9 ----

/// The 0x7ff the map is told of, as the starts it relays.
fn started_told(effects: List(Effect)) -> List(spell_started.SpellStarted) {
  list.filter_map(support.tells(effects:), fn(tell) {
    case tell {
      unit_news.CastStarted(start:) -> Ok(start)
      _ -> Error(Nil)
    }
  })
}

pub fn a_viewer_of_the_engineer_is_told_42148s_cast_test() -> Nil {
  use <- owned_test.run(5000)
  let effects =
    every(pulse_blast(caster: engineer(in_combat: True), foes: [10]))
  let told_of_42148 =
    list.filter(started_told(effects), fn(told) { told.spell4_id == 42_148 })
  assert list.length(told_of_42148) == 1
    as "the map is told 42148's start once, as of any child (opcode.0x7ff), for each connection that sees the caster. That a viewer is sent no 0x935 is shown on the connection (game_connection_volatility_test)"
}
