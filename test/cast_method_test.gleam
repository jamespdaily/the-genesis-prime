//// The cast rule (`genesis_prime/game/cast`) for the abilities of the Multiphase,
//// Channeled, RapidTap and ChargeRelease methods: what each press sends, on a
//// clock the test drives, as a trace of the frames the caster is written, each cast
//// named k1, k2 and so on in the order its id first appears. The expected traces
//// are the messages the client's own code handles in that order:
//// `opcode.0x7fd`, `opcode.0x7ff.root_parent`, `opcode.0x7f4` with
//// `opcode.0x7f4.phase`, `opcode.0x7fe`, `opcode.0x801`, `opcode.0x814`,
//// `opcode.0x816`, `opcode.0x817`, `cast.stage_root_parent`,
//// `cast.charge_release_base`, `cast.current_cast`, `0x1403bfd60` (the stage a press
//// casts), `0x14053d1f0` (a channel's gos), `0x14053e5a0` and `0x14053e1b0` (the
//// cooldowns of each method) and `Spell4CastResult.vital_cost`. The rows the
//// spells come from are named at each assertion (`spell_tables`); the times of a
//// channel's pulses and of a Multiphase spell's phases are the design's choices,
//// stated where they are asserted.

import cast_support as support
import class_resource_support
import genesis_prime/client_connection.{CastFinished, CastStarted}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/class_resource
import genesis_prime/game/spell_plan.{AtFirstGo, Spell}
import genesis_prime/message/cast_result.{
  type CastResult, CasterVitalCostResource1, CasterVitalCostResource3,
  CasterVitalCostResource5, Other, SpellCancelled,
}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_threshold_closed
import genesis_prime/message/spell_threshold_index
import genesis_prime/message/spell_threshold_opened
import genesis_prime/step.{type TimerId, ConnectionId, LogDebug}
import gleam/int
import gleam/list
import gleam/string
import owned_test

/// One step of a scenario: the time and what the rule did then.
type Step =
  #(Int, List(cast.Effect))

/// The cast ids of the frames of the steps, in the order they first appear.
fn cast_ids(steps steps: List(Step)) -> List(Int) {
  list.flat_map(steps, fn(step) { support.writes(effects: step.1) })
  |> list.filter_map(cast_id_of)
  |> list.unique
}

fn cast_id_of(frame: Frame) -> Result(Int, Nil) {
  case frame.message_id {
    0x07FD -> {
      let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
      Ok(confirmed.server_cast_id)
    }
    0x07FF -> {
      let assert Ok(started) = spell_started.decode(frame.body)
      Ok(started.cast_id)
    }
    0x07F4 -> {
      let assert Ok(go) = spell_go.decode(frame.body)
      Ok(go.cast_id)
    }
    0x07FE -> Ok(support.finished_cast_id(frame))
    _ -> Error(Nil)
  }
}

/// The frames the caster is written, each as the time and a line: `7fd k1`,
/// `7ff k2 <spell> root <root> parent <parent>`, `7f4 k1 p<phase>`, `7fe k1`,
/// `816 <spell> <resolving> <cooldown> k1`, `817 <spell> <index>`,
/// `814 <spell> <bit>` and `7fc <spell> <result>`.
fn trace(steps steps: List(Step)) -> List(#(Int, String)) {
  let ids = cast_ids(steps:)
  let label = fn(id) {
    case
      list.index_map(ids, fn(known, index) { #(known, index) })
      |> list.key_find(id)
    {
      Ok(index) -> "k" <> int.to_string(index + 1)
      Error(Nil) -> "id " <> int.to_string(id)
    }
  }
  list.flat_map(steps, fn(step) {
    list.map(support.writes(effects: step.1), fn(frame) {
      #(step.0, line(frame:, label:))
    })
  })
}

fn line(frame frame: Frame, label label: fn(Int) -> String) -> String {
  case frame.message_id {
    0x07FD -> {
      let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
      "7fd " <> label(confirmed.server_cast_id)
    }
    0x07FF -> {
      let assert Ok(started) = spell_started.decode(frame.body)
      string.join(
        [
          "7ff",
          label(started.cast_id),
          int.to_string(started.spell4_id),
          "root",
          int.to_string(started.root_spell4_id),
          "parent",
          int.to_string(started.parent_spell4_id),
        ],
        " ",
      )
    }
    0x07F4 -> {
      let assert Ok(go) = spell_go.decode(frame.body)
      "7f4 " <> label(go.cast_id) <> " p" <> int.to_string(go.phase)
    }
    0x07FE -> "7fe " <> label(support.finished_cast_id(frame))
    0x0816 -> {
      let assert Ok(opened) = spell_threshold_opened.decode(frame.body)
      string.join(
        [
          "816",
          int.to_string(opened.spell4_id),
          int.to_string(opened.resolving_spell4_id),
          int.to_string(opened.cooldown_spell4_id),
          label(opened.cancel_cast_id),
        ],
        " ",
      )
    }
    0x0817 -> {
      let assert Ok(index) = spell_threshold_index.decode(frame.body)
      "817 "
      <> int.to_string(index.spell4_id)
      <> " "
      <> int.to_string(index.index)
    }
    0x0814 -> {
      let assert Ok(closed) = spell_threshold_closed.decode(frame.body)
      "814 "
      <> int.to_string(closed.spell4_id)
      <> " "
      <> int.to_string(closed.start_cooldowns)
    }
    0x07FC -> {
      let assert Ok(refused) = spell_cast_refused.decode(frame.body)
      "7fc "
      <> int.to_string(refused.spell4_id)
      <> " "
      <> int.to_string(cast_result.to_value(refused.result))
    }
    other -> "unexpected frame " <> int.to_string(other)
  }
}

/// The lines of a trace at one time.
fn lines(trace trace: List(#(Int, String))) -> List(String) {
  list.map(trace, fn(entry) { entry.1 })
}

/// The press, then every timer it starts and each that starts, at the time each
/// is due: the steps in order, the first being the press at `at`.
fn run(
  state state: cast.State,
  pressed pressed: List(cast.Effect),
  at ms: Int,
) -> #(cast.State, List(Step)) {
  let #(state, fired) =
    support.run_timers(state:, effects: pressed, from_ms: ms)
  #(state, [#(ms, pressed), ..fired])
}

/// The refusal a press at the time gets, as `<spell> <result>`.
fn refusal_line(effects effects: List(cast.Effect)) -> String {
  let assert [entry] = trace(steps: [#(0, effects)])
    as "a refused press writes one 0x7fc and nothing else"
  assert support.tells(effects:) == [] && support.started_timers(effects:) == []
  entry.1
}

fn result_value(result: CastResult) -> String {
  int.to_string(cast_result.to_value(result))
}

/// The server id 0x7fd gave the pressed cast.
fn pressed_id_of(effects effects: List(cast.Effect)) -> Int {
  let assert [confirmed, ..] = support.writes(effects:)
    as "a press writes its 0x7fd first"
  let assert Ok(id) = cast_id_of(confirmed)
  id
}

/// The spell, root and parent of each cast started, as the first viewer is told.
fn started_by_viewer(
  effects effects: List(cast.Effect),
) -> List(#(Int, Int, Int)) {
  list.filter_map(support.tells(effects:), fn(told) {
    case told {
      #(ConnectionId(2), CastStarted(start:)) ->
        Ok(#(start.spell4_id, start.root_spell4_id, start.parent_spell4_id))
      _ -> Error(Nil)
    }
  })
}

fn timers_of(effects effects: List(cast.Effect)) -> List(TimerId) {
  list.map(support.started_timers(effects:), fn(started) { started.0 })
}

fn delays_of(effects effects: List(cast.Effect)) -> List(Int) {
  list.map(support.started_timers(effects:), fn(started) { started.1 })
}

fn is_accepted(effects effects: List(cast.Effect)) -> Bool {
  list.first(support.ids(frames: support.writes(effects:))) == Ok(0x07FD)
}

/// Whether the press was held: nothing is written and one timer waits.
fn is_held(effects effects: List(cast.Effect)) -> Bool {
  support.writes(effects:) == [] && list.length(timers_of(effects:)) == 1
}

fn press(
  state state: cast.State,
  bag_index bag_index: Int,
  at ms: Int,
) -> #(cast.State, List(cast.Effect)) {
  support.pressed(state:, bag_index:, target: 0, at: ms)
}

// ---------------------------------------------------------------- Multiphase

pub fn pulse_blast_goes_at_0_and_1250_ms_starts_its_child_in_phase_1_and_finishes_before_the_child_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.pulse_blast, at: 1000)
  let #(_, steps) = run(state:, pressed:, at: 1000)
  assert trace(steps:)
    == [
      #(1000, "7fd k1"),
      #(1000, "7f4 k1 p0"),
      #(2250, "7f4 k1 p1"),
      #(2250, "7ff k2 37302 root 42276 parent 42276"),
      #(2250, "7f4 k2 p0"),
      #(2250, "7fe k1"),
      #(2251, "7f4 k2 p1"),
      #(2252, "7f4 k2 p2"),
      #(2253, "7f4 k2 p3"),
      #(2253, "7fe k2"),
    ]
    as "SpellPhase 5390 and 5391: Pulse Blast's phases at the running sums 0 and 1250 ms; Spell4Effects 95881 (phaseFlags 2) proxies 37302 in phase 1; SpellPhase 2820 to 2823: 37302's phases at 0, 1, 1 and 1 ms after its start; each Multiphase cast finishes after its last go (the design's sequence)"
}

pub fn quick_draw_goes_in_5_phases_and_starts_the_proxies_whose_caster_gate_passes_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.quick_draw, at: 1000)
  let #(_, steps) = run(state:, pressed:, at: 1000)
  assert trace(steps:)
    == [
      #(1000, "7fd k1"),
      #(1000, "7f4 k1 p0"),
      #(1366, "7f4 k1 p1"),
      #(1366, "7ff k2 43498 root 43468 parent 43468"),
      #(1366, "7f4 k2 p0"),
      #(1366, "7fe k2"),
      #(1566, "7f4 k1 p2"),
      #(1566, "7ff k3 43499 root 43468 parent 43468"),
      #(1566, "7f4 k3 p0"),
      #(1566, "7fe k3"),
      #(1766, "7f4 k1 p3"),
      #(1766, "7ff k4 43498 root 43468 parent 43468"),
      #(1766, "7f4 k4 p0"),
      #(1766, "7fe k4"),
      #(1766, "7ff k5 43500 root 43468 parent 43468"),
      #(1766, "7f4 k5 p0"),
      #(1766, "7fe k5"),
      #(2000, "7f4 k1 p4"),
      #(2000, "7fe k1"),
    ]
    as "SpellPhase 5882 to 5886: delays 0, 366, 200, 200 and 234, so gos at 0, 366, 566, 766 and 1000 ms with the phase index as the byte (opcode.0x7f4.phase). Spell4Effects 196513 to 196522 have type 26 effects aimed at the caster behind caster apply 17301 (type 15, comparison 2 on 43500: the caster is not under cast 43500) or 17302 (comparison 1: it is); no cast of 43500 is live at a go, so 17301's start and 17302's do not: phase 1 (phaseFlags 2) starts 43498 by 196513, phase 2 (4) 43499 by 196514 and phase 3 (8) 43498 by 196515 and 43500 by 196516; phases 0 and 4 hold only 196522 (17302) and effect 196521 (type 80), which start nothing"
  assert list.flat_map(steps, fn(step) { started_by_viewer(effects: step.1) })
    == [
      #(43_468, 43_468, 0),
      #(43_498, 43_468, 43_468),
      #(43_499, 43_468, 43_468),
      #(43_498, 43_468, 43_468),
      #(43_500, 43_468, 43_468),
    ]
    as "the viewers are told Quick Draw's own start and each child the gates let start"
}

// ------------------------------------------------------------ the current cast

pub fn a_press_during_pulse_blast_is_refused_13_while_more_than_500_ms_of_its_casts_are_left_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.pulse_blast, at: 1000)
  let assert [#(go_timer, 1250)] = support.started_timers(effects: pressed)
  let #(_, during) = press(state:, bag_index: support.pulse_blast, at: 1500)
  assert refusal_line(effects: during) == "7fc 42276 13"
    as "cast.current_cast: Pulse Blast (Multiphase, cast time 1250) is the current cast from its start and its go does not clear it; Spell4.42276 propertyFlags 0x4000002 has neither 0x1, 0x10 nor 0x40; 750 ms of its bar are left, more than the queue window"
  let #(state, step) = support.fired(state:, timer: go_timer, at: 2250)
  let #(state, held) = press(state:, bag_index: support.pulse_blast, at: 2251)
  assert support.writes(effects: held) == []
    as "cast.current_cast: Pulse Blast's finish at 2250 leaves its child 37302, which shows a cast bar of 3 ms (SpellPhase 2820 to 2823), as the current cast: 2 ms are left, so the press is held"
  let #(_, steps) = support.run_timers(state:, effects: step, from_ms: 2250)
  let assert Ok(#(_, last)) = list.find(steps, fn(step) { step.0 == 2253 })
    as "the child's last phase is at 2253"
  assert list.take(ids_of(effects: last), 2) == [0x07F4, 0x07FE]
  assert list.drop(ids_of(effects: last), 2) |> list.first == Ok(0x07FD)
    as "cast.current_cast: the finish of the child clears the current cast, and the held press is taken then"
}

pub fn quick_draw_is_refused_13_during_a_charge_while_gate_and_shred_pass_a_live_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let #(_, quick_draw) = press(state:, bag_index: support.quick_draw, at: 2500)
  assert refusal_line(effects: quick_draw) == "7fc 43468 13"
    as "cast.current_cast: Charged Shot's base cast 34718 has a thresholdTime, so it shows a bar and is current; Spell4.43468 propertyFlags 0x4100002 has neither 0x1, 0x10 nor 0x40"
  let #(_, gate) = press(state:, bag_index: 5, at: 2500)
  assert is_accepted(effects: gate)
    as "Spell4.34355: propertyFlags 0x3 has 0x1, so Gate is never refused 13 (0x1403afb10)"
  let #(_, shred) = press(state:, bag_index: support.shred, at: 2500)
  assert is_accepted(effects: shred)
    as "Spell4.38766 and Spell4.38765: propertyFlags 0x4040003 has 0x1"
}

pub fn a_press_during_discharge_passes_because_discharge_has_the_flag_0x40_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    press(state: cast.new(), bag_index: support.discharge, at: 1000)
  let #(_, kick) = press(state:, bag_index: 3, at: 1100)
  assert is_accepted(effects: kick)
    as "Spell4.58832: propertyFlags 0x4000042 has 0x40, so a live Discharge leaves the caster free (0x1403afb10); Kick has no global cooldown (kind 3)"
  let #(state, _) =
    press(state: cast.new(), bag_index: support.pulse_blast, at: 1000)
  let #(_, kick) = press(state:, bag_index: 3, at: 1100)
  assert refusal_line(effects: kick) == "7fc 58591 13"
    as "the same press during Pulse Blast is refused 13"
}

// ------------------------------------------------------------------ Channeled

pub fn discharge_pulses_3_times_each_starting_80382_and_finishes_at_1250_ms_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.discharge, at: 1000)
  assert delays_of(effects: pressed) == [410, 820, 1230, 1250]
    as "Spell4.58832: channelInitialDelay 410, channelPulseTime 410, channelMaxTime 1250: three pulses and the finish (0x14053d1f0; the times are the design's choice)"
  let #(_, steps) = run(state:, pressed:, at: 1000)
  assert trace(steps:)
    == [
      #(1000, "7fd k1"),
      #(1410, "7f4 k1 p0"),
      #(1410, "7ff k2 80382 root 58832 parent 58832"),
      #(1410, "7f4 k2 p0"),
      #(1410, "7fe k2"),
      #(1820, "7f4 k1 p1"),
      #(1820, "7ff k3 80382 root 58832 parent 58832"),
      #(1820, "7f4 k3 p0"),
      #(1820, "7fe k3"),
      #(2230, "7f4 k1 p2"),
      #(2230, "7ff k4 80382 root 58832 parent 58832"),
      #(2230, "7f4 k4 p0"),
      #(2230, "7fe k4"),
      #(2250, "7fe k1"),
    ]
    as "opcode.0x7f4.phase: the pulse index is the go's phase byte; Spell4Effects 173926 (phaseFlags -1) proxies 80382 in every phase; the cast ends at channelMaxTime. Gap: the effect 141368 (damage, phaseFlags 1: pulse 0 only) is not in any go, since no go of this step names an effect; it lands with the damage step"
  let #(state, _) =
    press(state: cast.new(), bag_index: support.discharge, at: 1000)
  let #(_, quick_draw) = press(state:, bag_index: support.quick_draw, at: 1100)
  assert refusal_line(effects: quick_draw) == "7fc 43468 14"
    as "Spell4.58832: kind 0 with SpellCoolDown 159 (1250 ms) starts the global cooldown at the accept, so a kind 0 press 100 ms later is refused 14 (0x14046afc0)"
}

pub fn electrocute_pulses_6_times_and_finishes_with_its_last_pulse_test() -> Nil {
  use <- owned_test.run(10_000)
  assert support.ability(base: 25_473).spell4_id.value == 41_276
  let costless = Spell(..support.ability(base: 25_473), costs: [])
  let plans = support.with_spells(plans: support.plans(), spells: [costless])
  let #(state, pressed) =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: 7,
      target: 0,
      at: 1000,
    )
  assert delays_of(effects: pressed) == [500, 1000, 1500, 2000, 2500, 3000]
    as "Spell4.41276: channelInitialDelay 500, channelPulseTime 500, channelMaxTime 3000: six pulses, the last at the max time, which ends the cast (0x14053d1f0)"
  let #(_, steps) = run(state:, pressed:, at: 1000)
  let gos =
    list.filter(trace(steps:), fn(entry) { string.starts_with(entry.1, "7f4") })
  assert list.map(gos, fn(entry) { entry.1 })
    == [
      "7f4 k1 p0",
      "7f4 k1 p1",
      "7f4 k1 p2",
      "7f4 k1 p3",
      "7f4 k1 p4",
      "7f4 k1 p5",
    ]
    as "opcode.0x7f4.phase: the phases 0 to 5"
  assert list.last(trace(steps:)) == Ok(#(4000, "7fe k1"))
    as "the finish comes at channelMaxTime, 3000 ms after the accept"
}

pub fn a_0x801_for_a_live_channel_cancels_its_pulses_and_finish_and_ends_it_for_all_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([#(SpellCancelled, 1), #(Other(11), 1)], fn(cancel) {
    let #(state, pressed) =
      press(state: cast.new(), bag_index: support.discharge, at: 1000)
    let id = pressed_id_of(effects: pressed)
    let assert Ok(#(_, effects)) =
      support.cancelled(
        state:,
        cast_id: id,
        reason: cancel.0,
        bit: cancel.1,
        at: 1500,
      )
      as "opcode.0x801: 6 and 11 with the bit 1 are what the client sends for a cast that ends"
    assert list.sort(support.cancelled_timers(effects:), fn(first, second) {
        int.compare(timer_number(first), timer_number(second))
      })
      == list.sort(timers_of(effects: pressed), fn(first, second) {
        int.compare(timer_number(first), timer_number(second))
      })
      as "the three pulses and the finish are cancelled"
    assert support.ids(frames: support.writes(effects:)) == [0x07FE]
      as "no go, only the finish"
    assert list.map(support.tells(effects:), fn(told) { told.1 })
      == [CastFinished(cast_id: id), CastFinished(cast_id: id)]
      as "the audience is told too"
  })
}

fn timer_number(timer: TimerId) -> Int {
  let step.TimerId(number) = timer
  number
}

// ------------------------------------------------------------------ cooldowns

pub fn a_channels_cooldown_starts_at_its_count_go_or_at_a_cancels_finish_test() -> Nil {
  use <- owned_test.run(10_000)
  let discharge = Spell(..support.ability(base: 38_201), cooldown_ms: 20_000)
  let plans = support.with_spells(plans: support.plans(), spells: [discharge])
  let press_in = fn(state, bag_index, at) {
    support.pressed_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index:,
      target: 0,
      at:,
    )
  }
  let #(state, pressed) = press_in(cast.new(), support.discharge, 1000)
  let assert [#(first, 410), #(second, 820), #(third, 1230), #(_, 1250)] =
    support.started_timers(effects: pressed)
  let #(state, _) = support.fired(state:, timer: first, at: 1410)
  let #(state, _) = support.fired(state:, timer: second, at: 1820)
  let #(_, before_count) = press_in(state, support.discharge, 2100)
  assert is_held(effects: before_count)
    as "0x14053e5a0: the cooldown starts at the go that reaches the count, so after two of three pulses a press is only held for the global cooldown, not refused 15"
  let #(state, _) = support.fired(state:, timer: third, at: 2230)
  let #(_, after_count) = press_in(state, support.discharge, 2300)
  assert refusal_line(effects: after_count) == "7fc 58832 15"
    as "the third pulse starts the cooldown: 20000 ms from 2230 leaves 19930 at 2300"
  let #(state, pressed) = press_in(cast.new(), support.discharge, 1000)
  let id = pressed_id_of(effects: pressed)
  let assert Ok(#(state, _)) =
    support.cancelled(
      state:,
      cast_id: id,
      reason: SpellCancelled,
      bit: 1,
      at: 1500,
    )
  let #(_, after_cancel) = press_in(state, support.discharge, 2000)
  assert refusal_line(effects: after_cancel) == "7fc 58832 15"
    as "0x14053e1b0: a channel's 0x7fe starts its cooldown, so a cancel at 1500 starts 20000 ms that have 19500 ms left at 2000"
}

pub fn a_multiphase_spells_cooldown_starts_at_its_last_phase_with_the_flag_0x200_else_at_phase_0_test() -> Nil {
  use <- owned_test.run(10_000)
  let pulse_blast =
    Spell(
      ..support.ability(base: 26_468),
      cooldown_ms: 20_000,
      ignores_casting: True,
    )
  let press_in = fn(spell, state, at) {
    let plans = support.with_spells(plans: support.plans(), spells: [spell])
    support.pressed_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index: support.pulse_blast,
      target: 0,
      at:,
    )
  }
  let #(state, pressed) = press_in(pulse_blast, cast.new(), 1000)
  let assert [#(last_phase, 1250)] = support.started_timers(effects: pressed)
  let #(_, during) = press_in(pulse_blast, state, 2100)
  assert is_held(effects: during)
    as "0x14053e5a0: with the flag 0x200 on SpellPhase 5391 the cooldown waits for the last phase, so at 2100 only the global cooldown (until 2250) holds the press"
  let #(state, step) = support.fired(state:, timer: last_phase, at: 2250)
  let #(state, _) = support.run_timers(state:, effects: step, from_ms: 2250)
  let #(_, after) = press_in(pulse_blast, state, 3500)
  assert refusal_line(effects: after) == "7fc 42276 15"
    as "the last phase's go at 2250 starts 20000 ms"
  let at_phase_0 = Spell(..pulse_blast, cooldown_start: AtFirstGo)
  let #(state, _) = press_in(at_phase_0, cast.new(), 1000)
  let #(_, during) = press_in(at_phase_0, state, 2100)
  assert refusal_line(effects: during) == "7fc 42276 15"
    as "0x14053e5a0: a Multiphase spell with no phase of the flag 0x200 starts its cooldown at phase 0, at 1000"
}

// ------------------------------------------------------------------- RapidTap

pub fn shred_opens_a_threshold_on_its_first_tap_and_its_second_casts_the_stage_and_closes_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    press(state: cast.new(), bag_index: support.shred, at: 1000)
  assert trace(steps: [#(1000, first)])
    == [
      #(1000, "7fd k1"),
      #(1000, "816 38765 38765 0 k1"),
      #(1000, "7f4 k1 p0"),
      #(1000, "7ff k2 38767 root 38765 parent 38765"),
      #(1000, "7fe k1"),
    ]
    as "opcode.0x816: the first tap casts 38765 (Spell4.38765 thresholdTime 4000) and opens the threshold with the spell twice, 0 and the cast id k1; Spell4Effects 83776 proxies 38767 in phase 0"
  assert started_by_viewer(effects: first)
    == [#(38_765, 38_765, 0), #(38_767, 38_765, 38_765)]
    as "opcode.0x7ff.root_parent: the base cast has parent 0"
  assert delays_of(effects: first) == [4000, 133, 433, 766]
    as "the threshold's time 4000 (Spell4.38765), then the child 38767's phases at 133, 433 and 766 ms (SpellPhase 3712 to 3714)"
  let #(state, second) = press(state:, bag_index: support.shred, at: 2000)
  assert trace(steps: [#(1000, first), #(2000, second)])
    |> list.drop(5)
    == [
      #(2000, "7fd k3"),
      #(2000, "7f4 k3 p0"),
      #(2000, "7ff k4 39467 root 38765 parent 38766"),
      #(2000, "7fe k3"),
      #(2000, "814 38765 1"),
    ]
    as "Spell4Thresholds 238: the second tap casts 38766; it is the last stage, so 0x814 closes the threshold with the cooldown bit; Spell4Effects 83782 proxies 39467"
  assert started_by_viewer(effects: second)
    == [#(38_766, 38_765, 38_765), #(39_467, 38_765, 38_766)]
    as "cast.stage_root_parent: the stage has root 38765 and parent 38765"
  let #(_, third) = press(state:, bag_index: support.shred, at: 3000)
  assert list.map(trace(steps: [#(3000, third)]), fn(entry) { entry.1 })
    |> list.take(2)
    == ["7fd k1", "816 38765 38765 0 k1"]
    as "the closed threshold gives the next tap the base spell and a new threshold"
}

pub fn a_tap_within_500_ms_of_the_global_cooldowns_end_is_held_and_one_before_is_refused_14_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = press(state: cast.new(), bag_index: support.shred, at: 1000)
  let #(_, early) = press(state:, bag_index: support.shred, at: 1400)
  assert refusal_line(effects: early) == "7fc 38766 14"
    as "Spell4.38766 is kind 0 with SpellCoolDown 115 (1000 ms): at 1400 600 ms are left, more than the queue window of 500 (0x1403b14c0)"
  let #(_, held) = press(state:, bag_index: support.shred, at: 1600)
  assert is_held(effects: held) && delays_of(effects: held) == [400]
    as "at 1600 400 ms are left: the press is held until 2000"
  let #(_, none_left) = press(state:, bag_index: support.shred, at: 2000)
  assert is_accepted(effects: none_left)
}

pub fn relentless_strikes_moves_to_its_second_stage_with_0x817_and_closes_after_its_third_tap_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    press(state: cast.new(), bag_index: support.relentless_strikes, at: 1000)
  assert list.take(lines(trace: trace(steps: [#(1000, first)])), 2)
    == ["7fd k1", "816 32078 32078 0 k1"]
  let #(state, second) =
    press(state:, bag_index: support.relentless_strikes, at: 1750)
  assert lines(trace: trace(steps: [#(1750, second)]))
    == ["7fd k1", "817 32078 1", "7f4 k1 p0", "7fe k1"]
    as "Spell4Thresholds 9 and 10: after the tap that casts 32079 the next press casts the row at index 1, which 0x817 sets"
  assert started_by_viewer(effects: second) == [#(32_079, 32_078, 32_078)]
  let #(_, third) =
    press(state:, bag_index: support.relentless_strikes, at: 2500)
  assert lines(trace: trace(steps: [#(2500, third)]))
    == ["7fd k1", "7f4 k1 p0", "7fe k1", "814 32078 1"]
    as "the third tap casts 32080, the last stage, and closes the threshold"
  assert started_by_viewer(effects: third) == [#(32_080, 32_078, 32_078)]
}

pub fn rampage_taps_four_times_with_its_gcds_of_500_333_and_333_ms_and_its_cooldown_starts_at_the_close_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    press(state: cast.new(), bag_index: support.rampage, at: 1000)
  assert lines(trace: trace(steps: [#(1000, first)]))
    == ["7fd k1", "816 58524 58524 0 k1", "7f4 k1 p0", "7fe k1"]
    as "Spell4.58524: thresholdTime 4000, a cooldown of 8000 that no go starts (0x14053e5a0)"
  let #(state, held) = press(state:, bag_index: support.rampage, at: 1000)
  let assert [#(timer, 500)] = support.started_timers(effects: held)
    as "Spell4.58524: kind 0 with SpellCoolDown 103 (500 ms), so the next tap waits for it"
  let #(state, second) = support.fired(state:, timer:, at: 1500)
  assert lines(trace: trace(steps: [#(1500, second)]))
    == ["7fd k1", "817 58524 1", "7f4 k1 p0", "7fe k1"]
  assert started_by_viewer(effects: second) == [#(66_987, 58_524, 58_524)]
    as "Spell4Thresholds 1073: the second tap casts 66987"
  assert delays_of(effects: second) == [100]
    as "Spell4Effects 177498: 66987's Proxy to 71392 starts 100 ms after its go, from a timer"
  let #(state, held) = press(state:, bag_index: support.rampage, at: 1500)
  let assert [#(timer, 333)] = support.started_timers(effects: held)
    as "Spell4.66987: SpellCoolDown 107 (333 ms)"
  let #(state, third) = support.fired(state:, timer:, at: 1833)
  assert lines(trace: trace(steps: [#(1833, third)]))
    == ["7fd k1", "817 58524 2", "7f4 k1 p0", "7fe k1"]
  let #(state, held) = press(state:, bag_index: support.rampage, at: 1833)
  let assert [#(timer, 333)] = support.started_timers(effects: held)
    as "Spell4.71125: SpellCoolDown 107 (333 ms)"
  let #(state, fourth) = support.fired(state:, timer:, at: 2166)
  assert list.last(lines(trace: trace(steps: [#(2166, fourth)])))
    == Ok("814 58524 1")
    as "Spell4Thresholds 1075: the fourth tap casts 71126, the last stage, and 0x814 closes the threshold"
  let #(_, soon) = press(state:, bag_index: support.rampage, at: 3166)
  assert refusal_line(effects: soon) == "7fc 58524 15"
    as "Spell4.58524: the 8000 ms cooldown starts at the close (2166), so 1 s later it is refused 15"
  let #(_, later) = press(state:, bag_index: support.rampage, at: 10_100)
  assert is_held(effects: later)
    as "8000 ms from 2166 end at 10166: 66 ms left at 10100 is within the queue window"
}

pub fn the_taps_window_ending_closes_the_threshold_writes_nothing_and_starts_the_cooldown_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    press(state: cast.new(), bag_index: support.rampage, at: 1000)
  let assert [#(window, 4000), ..] = support.started_timers(effects: first)
    as "opcode.0x816: the client's threshold lasts the spell's thresholdTime, 4000 ms for Rampage"
  let #(state, ended) = support.fired(state:, timer: window, at: 5000)
  assert ended == []
    as "the client closes the threshold by itself and starts its cooldowns (opcode.0x816), so the server writes nothing"
  let #(_, refused) = press(state:, bag_index: support.rampage, at: 5500)
  assert refusal_line(effects: refused) == "7fc 58524 15"
    as "Spell4.58524: the 8000 ms cooldown starts when the threshold closes, at 5000"
  let #(_, next) = press(state:, bag_index: support.rampage, at: 13_100)
  assert list.take(lines(trace: trace(steps: [#(13_100, next)])), 2)
    == ["7fd k1", "816 58524 58524 0 k1"]
    as "after the cooldown the next tap casts the base spell and opens a threshold"
  let #(state, first) =
    press(state: cast.new(), bag_index: support.shred, at: 1000)
  let assert [#(window, 4000), ..] = support.started_timers(effects: first)
  let #(state, _) = support.fired(state:, timer: window, at: 5000)
  let #(_, again) = press(state:, bag_index: support.shred, at: 6000)
  assert list.take(lines(trace: trace(steps: [#(6000, again)])), 2)
    == ["7fd k1", "816 38765 38765 0 k1"]
    as "a tap after the window casts the base spell again, not the stage"
}

// -------------------------------------------------------------- ChargeRelease

pub fn charged_shots_first_press_opens_a_threshold_and_holds_its_cast_with_no_go_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  assert lines(trace: trace(steps: [#(1000, pressed)]))
    == ["7fd k1", "816 34718 34718 0 k1"]
    as "opcode.0x816 and cast.charge_release_base: the base cast 34718 needs no go before its 0x7fe, and the value is its own id"
  assert started_by_viewer(effects: pressed) == [#(34_718, 34_718, 0)]
  assert delays_of(effects: pressed) == [1000]
    as "Spell4Thresholds 123: the charge reaches level 1 after thresholdDuration 1000"
  let #(_, steps) = run(state:, pressed:, at: 1000)
  assert trace(steps:)
    == [
      #(1000, "7fd k1"),
      #(1000, "816 34718 34718 0 k1"),
      #(2000, "817 34718 1"),
      #(3400, "817 34718 2"),
    ]
    as "Spell4Thresholds 123 and 124: level 1 after 1000 ms, level 2 after 1400 ms more, and none past index 2; nothing is sent at the 8.2 s mark, which the client only marks (cast.charge_release_base), and 34718 gets no 0x7f4"
}

pub fn charged_shots_release_casts_the_row_at_the_level_reached_and_ends_the_charge_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let #(_, early) = press(state:, bag_index: support.charged_shot, at: 1500)
  assert lines(trace: trace(steps: [#(1000, pressed), #(1500, early)]))
    == [
      "7fd k1",
      "816 34718 34718 0 k1",
      "7fd k2",
      "7f4 k2 p0",
      "7fe k2",
      "814 34718 0",
      "7fe k1",
    ]
    as "Spell4Thresholds 125: a release before 1000 ms casts 34720; the stage's 0x7f4 comes before the 0x814 that closes the threshold (cast.stage_root_parent), and the base cast ends last with 0x7fe"
  assert started_by_viewer(effects: early) == [#(34_720, 34_718, 34_718)]
    as "cast.stage_root_parent: root 34718 and parent 34718"
  assert list.map(support.tells(effects: early), fn(told) { told.1 })
    |> list.filter(fn(news) {
      case news {
        CastFinished(..) -> True
        CastStarted(..)
        | client_connection.CastWent(..)
        | client_connection.Appeared(..)
        | client_connection.CreatureAppeared(..)
        | client_connection.Moving(..)
        | client_connection.CastMissed(..)
        | client_connection.CastTargetsRemoved(..)
        | client_connection.CastStackRemoved(..)
        | client_connection.Health(..)
        | client_connection.Died
        | client_connection.Removed
        | client_connection.CreatureMoved(..)
        | client_connection.CreaturePlaced(..)
        | client_connection.Targeting(..)
        | client_connection.Threat(..)
        | client_connection.CombatState(..)
        | client_connection.CameBack
        | client_connection.DeathLogged
        | client_connection.CameBackLogged
        | client_connection.Shield(..)
        | client_connection.CrowdControlApplied(..)
        | client_connection.CrowdControlEnded(..) -> False
      }
    })
    |> list.length
    == 4
    as "the viewers are told the stage's finish and the base cast's finish, each by both connections"
  assert support.cancelled_timers(effects: early) == timers_of(effects: pressed)
    as "the charge timer is cancelled with the threshold"
}

pub fn charged_shot_casts_34722_after_level_1_and_36691_after_level_2_and_after_8200_ms_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let assert [#(level_1, 1000)] = support.started_timers(effects: pressed)
  let #(state_1, level_1_effects) =
    support.fired(state:, timer: level_1, at: 2000)
  let #(_, release_1) =
    press(state: state_1, bag_index: support.charged_shot, at: 2500)
  assert started_by_viewer(effects: release_1) == [#(34_722, 34_718, 34_718)]
    as "Spell4Thresholds 123: a release after 1000 ms and before 2400 ms casts 34722"
  let assert [#(level_2, 1400)] =
    support.started_timers(effects: level_1_effects)
  let #(state_2, level_2_effects) =
    support.fired(state: state_1, timer: level_2, at: 3400)
  assert support.started_timers(effects: level_2_effects) == []
    as "no level is reached past index 2"
  let #(_, release_2) =
    press(state: state_2, bag_index: support.charged_shot, at: 4000)
  assert started_by_viewer(effects: release_2) == [#(36_691, 34_718, 34_718)]
    as "Spell4Thresholds 124: a release after 2400 ms casts 36691"
  let #(_, late) =
    press(state: state_2, bag_index: support.charged_shot, at: 9500)
  assert started_by_viewer(effects: late) == [#(36_691, 34_718, 34_718)]
    as "cast.charge_release_base: a release after the 8.2 s mark still casts the row at the current index"
}

pub fn charged_shots_cooldown_runs_10_s_from_the_stages_go_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(state, _) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let #(state, _) = press(state:, bag_index: support.charged_shot, at: 1500)
  let #(_, soon) = press(state:, bag_index: support.charged_shot, at: 5000)
  assert refusal_line(effects: soon) == "7fc 34718 15"
    as "Spell4.34718: spellCoolDown 10000, started by the release's first go (0x14053e5a0, opcode.0x814)"
  let #(_, near_the_end) =
    press(state:, bag_index: support.charged_shot, at: 11_200)
  assert is_held(effects: near_the_end)
    as "10000 ms from the stage's go at 1500 end at 11500: 300 ms left is within the queue window; from the base press at 1000 it would be over"
  let #(_, over) = press(state:, bag_index: support.charged_shot, at: 11_600)
  assert is_accepted(effects: over)
}

pub fn a_cancel_of_the_charge_closes_the_threshold_and_ends_only_the_base_cast_test() -> Nil {
  use <- owned_test.run(20_000)
  list.each([#(Other(0), 0), #(SpellCancelled, 1), #(Other(11), 1)], fn(cancel) {
    let #(state, pressed) =
      press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
    let id = pressed_id_of(effects: pressed)
    let assert Ok(#(state, effects)) =
      support.cancelled(
        state:,
        cast_id: id,
        reason: cancel.0,
        bit: cancel.1,
        at: 1500,
      )
      as "opcode.0x801: (0, 0) with the 0x816 value, or (6 or 11, 1) for the base cast"
    assert lines(trace: trace(steps: [#(1000, pressed), #(1500, effects)]))
      == ["7fd k1", "816 34718 34718 0 k1", "814 34718 0", "7fe k1"]
      as "cast.charge_release_base: the server ends 34718 only with 0x7fe, after the 0x814 that closes the threshold"
    assert support.cancelled_timers(effects:) == timers_of(effects: pressed)
      as "the charge timer is cancelled"
    assert list.map(support.tells(effects:), fn(told) { told.1 })
      == [CastFinished(cast_id: id), CastFinished(cast_id: id)]
    let #(_, quick_draw) =
      press(state:, bag_index: support.quick_draw, at: 2500)
    assert is_accepted(effects: quick_draw)
      as "the base cast no longer counts as casting"
    let #(_, again) = press(state:, bag_index: support.charged_shot, at: 2500)
    assert list.take(lines(trace: trace(steps: [#(2500, again)])), 2)
      == ["7fd k1", "816 34718 34718 0 k1"]
      as "the threshold is closed, so the next press casts the base spell"
  })
}

pub fn a_0x801_naming_no_open_threshold_is_a_debug_line_and_no_change_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(state, _) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let assert Ok(#(_, effects)) =
    support.cancelled(
      state:,
      cast_id: 12_345,
      reason: Other(0),
      bit: 0,
      at: 1500,
    )
  assert support.writes(effects:) == []
    && support.cancelled_timers(effects:) == []
  assert case effects {
    [cast.Log(level: LogDebug, ..)] -> True
    _ -> False
  }
    as "opcode.0x801: an id that is no open charge's gives a debug line"
  let #(_, still_charging) =
    press(state:, bag_index: support.charged_shot, at: 1500)
  assert started_by_viewer(effects: still_charging)
    == [#(34_720, 34_718, 34_718)]
    as "the threshold is still open"
}

// ------------------------------------------------------------------- refusals

pub fn the_four_costed_abilities_are_refused_with_their_slots_by_a_caster_that_holds_none_and_nothing_is_logged_test() -> Nil {
  use <- owned_test.run(10_000)
  let costed = [
    #(support.impale, "7fc 38779 ", CasterVitalCostResource3),
    #(7, "7fc 41276 ", CasterVitalCostResource1),
    #(2, "7fc 32809 ", CasterVitalCostResource1),
    #(6, "7fc 29874 ", CasterVitalCostResource5),
  ]
  // A Warrior at its start: 0 Kinetic Energy in slot 1, and nothing in slot 3.
  let empty =
    support.caster_holding(
      resources: class_resource.new(
        resource: class_resource_support.resource_of(1),
      ),
    )
  list.each(costed, fn(ability) {
    let #(_, first) =
      support.pressed_by(
        state: cast.new(),
        caster: empty,
        bag_index: ability.0,
        target: 0,
        at: 1000,
      )
    assert refusal_line_with_logs(effects: first)
      == ability.1 <> result_value(ability.2)
      as "Spell4CastResult.vital_cost: Impale (type 8: 53), Electrocute (type 6: 51), Mind Burst (type 6: 51) and Gamma Rays (type 18: 55) are refused with the client's own result (0x1403b3320, 0x1405e7980)"
    assert count_logs(effects: first) == 0
      as "a cost the caster cannot pay is the client's own refusal, not a cost the server does not hold"
  })
}

fn count_logs(effects effects: List(cast.Effect)) -> Int {
  list.filter(effects, fn(effect) {
    case effect {
      cast.Log(..) -> True
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.Strike(..)
      | cast.CancelTimer(..)
      | cast.Pay(..)
      | cast.Gain(..) -> False
    }
  })
  |> list.length
}

fn refusal_line_with_logs(effects effects: List(cast.Effect)) -> String {
  let assert [entry] = trace(steps: [#(0, effects)])
    as "a refused press writes one 0x7fc"
  entry.1
}

// ------------------------------------------------------------ leaving the world

pub fn leaving_the_world_with_a_threshold_open_cancels_every_timer_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, shred) =
    press(state: cast.new(), bag_index: support.shred, at: 1000)
  let #(state, left) = cast.left(cast: state)
  assert list.sort(support.cancelled_timers(effects: left), fn(first, second) {
      int.compare(timer_number(first), timer_number(second))
    })
    == list.sort(timers_of(effects: shred), fn(first, second) {
      int.compare(timer_number(first), timer_number(second))
    })
    as "the threshold's time and the child's phases are all cancelled"
  assert support.writes(effects: left) == []
    && support.tells(effects: left) == []
  let #(_, again) = press(state:, bag_index: support.shred, at: 2000)
  assert list.take(lines(trace: trace(steps: [#(2000, again)])), 2)
    == ["7fd k1", "816 38765 38765 0 k1"]
    as "the threshold is gone with the world"
  let #(state, charged) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let #(_, left) = cast.left(cast: state)
  assert support.cancelled_timers(effects: left) == timers_of(effects: charged)
    && support.writes(effects: left) == []
    as "a charge's timer is cancelled and nothing is written"
}

// ------------------------------------------------- a press queued behind a cast

/// The write ids of a step, in order.
fn ids_of(effects effects: List(cast.Effect)) -> List(Int) {
  support.ids(frames: support.writes(effects:))
}

pub fn a_press_with_500_ms_or_less_of_the_current_cast_left_is_held_and_starts_at_the_go_that_clears_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) = press(state: cast.new(), bag_index: 0, at: 1000)
  let assert [#(go_timer, 1250)] = support.started_timers(effects: pressed)
    as "Spell4.32893: Telekinetic Strike's bar is 1250 ms and its go is the one timer"
  let #(_, early) = press(state:, bag_index: support.pulse_blast, at: 1700)
  assert refusal_line(effects: early) == "7fc 42276 13"
    as "550 ms of the cast are left, more than the queue window of 500 (player.abilityQueueMax): refused 13, the server's choice"
  let #(state, queued) = press(state:, bag_index: support.pulse_blast, at: 1800)
  assert support.writes(effects: queued) == []
    && support.started_timers(effects: queued) == []
    as "450 ms are left: the press is held with no timer, since it starts at the go that clears the current cast, not at a time"
  let #(_, second) = press(state:, bag_index: support.quick_draw, at: 1850)
  assert refusal_line(effects: second) == "7fc 43468 13"
    as "a second press while one is held is refused 13"
  let #(state, go) = support.fired(state:, timer: go_timer, at: 2250)
  assert list.take(ids_of(effects: go), 2) == [0x07F4, 0x07FE]
    as "cast.current_cast: the go of a Normal cast clears the current cast; Telekinetic Strike's go and its finish come first, and its Proxy 62204 is aimed at the area (targetFlags 4), so it starts a child for each struck unit and none for a go that struck nobody (Spell4Effects.effectType.26)"
  assert list.drop(ids_of(effects: go), 2) |> list.take(2) == [0x07FD, 0x07F4]
    as "then the held press is taken at the same go: Pulse Blast's 0x7fd and its first go"
  assert support.started_timers(effects: go) |> list.map(fn(timer) { timer.1 })
    == [1250]
    as "the only timer is Pulse Blast's own phase 1 (SpellPhase 5391): none starts the held press"
  let #(_, after) = press(state:, bag_index: support.pulse_blast, at: 2300)
  assert refusal_line(effects: after) == "7fc 42276 13"
    as "the held press is Pulse Blast, now the current cast"
}

pub fn a_held_press_behind_a_multiphase_cast_starts_when_the_last_cast_that_is_current_finishes_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    press(state: cast.new(), bag_index: support.pulse_blast, at: 1000)
  let assert [#(phase_1, 1250)] = support.started_timers(effects: pressed)
  let #(state, queued) = press(state:, bag_index: 3, at: 1800)
  assert support.writes(effects: queued) == []
    && support.started_timers(effects: queued) == []
    as "Pulse Blast's bar is 1250 ms: 450 ms are left at 1800, so Kick is held"
  let #(state, at_phase_1) = support.fired(state:, timer: phase_1, at: 2250)
  assert !list.contains(ids_of(effects: at_phase_1), 0x07FD)
    as "cast.current_cast: Pulse Blast's finish leaves its child 37302, which shows a bar, as the current cast, so the held press waits"
  let assert [#(second, 1), #(third, 2), #(fourth, 3)] =
    support.started_timers(effects: at_phase_1)
  let #(state, _) = support.fired(state:, timer: second, at: 2251)
  let #(state, _) = support.fired(state:, timer: third, at: 2252)
  let #(_, last) = support.fired(state:, timer: fourth, at: 2253)
  assert ids_of(effects: last) == [0x07F4, 0x07FE, 0x07FD, 0x07F4, 0x07FE]
    as "the finish of 37302 clears the current cast, and Kick (Spell4.58591: instant) is taken right after"
}

pub fn a_held_press_behind_a_cast_the_client_cancels_starts_after_its_finish_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) = press(state: cast.new(), bag_index: 0, at: 1000)
  let id = pressed_id_of(effects: pressed)
  let #(state, _) = press(state:, bag_index: 3, at: 1800)
  let assert Ok(#(_, cancelled)) =
    support.cancelled(
      state:,
      cast_id: id,
      reason: SpellCancelled,
      bit: 1,
      at: 1900,
    )
  assert ids_of(effects: cancelled) |> list.take(2) == [0x07FE, 0x07FD]
    as "opcode.0x801: the cancel clears the current cast; the 0x7fe comes first and the held press is taken after it"
}

// ------------------------------------------------ the fix round of the review

pub fn a_held_press_does_not_refuse_the_charged_shot_release_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    press(state: cast.new(), bag_index: support.charged_shot, at: 1000)
  let #(state, held) = press(state:, bag_index: support.shred, at: 1600)
  assert is_held(effects: held) && delays_of(effects: held) == [400]
    as "Charged Shot's gcd (SpellCoolDown 82, 1000 ms) has 400 ms left: Shred is held"
  let #(state, release) =
    press(state:, bag_index: support.charged_shot, at: 1700)
  assert list.first(lines(trace: trace(steps: [#(1700, release)])))
    == Ok("7fd k1")
    as "0x1403bfd60: the release is resolved through the open threshold whatever the caster holds, so it is accepted"
  assert started_by_viewer(effects: release) == [#(34_720, 34_718, 34_718)]
  let assert [#(held_timer, 400)] = support.started_timers(effects: held)
  let #(_, shred) = support.fired(state:, timer: held_timer, at: 2000)
  assert is_accepted(effects: shred)
    as "the held press is left alone and starts when its cooldown ends"
}

pub fn a_0x801_for_no_open_threshold_still_clears_the_current_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = press(state: cast.new(), bag_index: 0, at: 1000)
  let assert Ok(#(state, effects)) =
    support.cancelled(
      state:,
      cast_id: 12_345,
      reason: Other(0),
      bit: 0,
      at: 1100,
    )
  assert support.writes(effects:) == []
  let #(_, kick) = press(state:, bag_index: 3, at: 1200)
  assert is_accepted(effects: kick)
    as "0x14039cc30: the client clears the player's current cast before every 0x801 it sends, so Telekinetic Strike (1250 ms) no longer counts as casting"
}

pub fn a_multiphase_cast_cancelled_after_its_0x200_phase_starts_its_cooldown_at_the_finish_test() -> Nil {
  use <- owned_test.run(10_000)
  let quick_draw =
    Spell(
      ..support.ability(base: 27_638),
      cooldown_ms: 20_000,
      ignores_casting: True,
    )
  let plans = support.with_spells(plans: support.plans(), spells: [quick_draw])
  let press_in = fn(state, at) {
    support.pressed_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index: support.quick_draw,
      target: 0,
      at:,
    )
  }
  let cancel_after = fn(fired_phases, cancel_at) {
    let #(state, pressed) = press_in(cast.new(), 1000)
    let id = pressed_id_of(effects: pressed)
    let state =
      list.fold(
        list.take(support.started_timers(effects: pressed), fired_phases),
        state,
        fn(state, started) {
          support.fired(state:, timer: started.0, at: 1000 + started.1).0
        },
      )
    let assert Ok(#(state, _)) =
      support.cancelled(
        state:,
        cast_id: id,
        reason: SpellCancelled,
        bit: 1,
        at: cancel_at,
      )
    state
  }
  let #(_, after) = press_in(cancel_after(1, 1400), 2500)
  assert refusal_line(effects: after) == "7fc 43468 15"
    as "0x14053e1b0: SpellPhase 5883 (phase 1, flag 0x200) was reached at 1366, so the 0x7fe of a cancel at 1400 starts the cooldown"
  let #(_, before) = press_in(cancel_after(0, 1100), 2500)
  assert is_accepted(effects: before)
    as "a cancel before the phase with the flag starts none"
}
