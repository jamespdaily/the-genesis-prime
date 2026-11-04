//// The cast rule (`genesis_prime/game/cast`) for the client's 0x4DB, the press of
//// an ability under the hold-to-continue-casting setting that is on by default,
//// on a clock the test drives. Expected values come from the client's facts, each
//// named at the assertion: `opcode.0x4db`, `cast.hold_answer`, `cast.hold_repeat`,
//// `cast.hold_by_method`, `cast.hold_stop`, `opcode.0x7ff.own_cast`, `opcode.0x7fc`,
//// `opcode.0x816`, `opcode.0x814`, `opcode.0x7f4.phase` and the `Spell4`,
//// `SpellCoolDown` and `Spell4Thresholds` rows of the abilities. The repeat while
//// the key is held is the design's choice from the setting's label and the client's
//// hidden result 13 (`cast.hold_repeat`): the client holds no repeat timer.

import cast_support as support
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/cast
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_started
import genesis_prime/step.{ConnectionId, LogWarning}
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test

/// Bag indexes in `cast_support.abilities`: Telekinetic Strike (Spell4 32893, cast
/// time 1250, kind 0 with SpellCoolDown 213: 1000 ms), Mind Burst (Spell4 32809,
/// no cast time, no cooldown, kind 0 with SpellCoolDown 104: 1250 ms) and Kick
/// (Spell4 58591, kind 3, cooldown 20000 ms).
const telekinetic_strike = 0

const mind_burst = 2

const kick = 3

/// The key of the bag index goes down or up, with Mind Burst costless
/// (`cast_support.plans_with_costless_mind_burst`), a go asked and not yet answered.
fn key_raw(
  state state: cast.State,
  bag_index bag_index: Int,
  held held: Int,
  at ms: Int,
) -> #(cast.State, List(cast.Effect)) {
  support.key_raw_in(
    plans: support.plans_with_costless_mind_burst(),
    state:,
    bag_index:,
    held:,
    at: ms,
  )
}

/// The same with each go answered as a round that struck nobody.
fn key(
  state state: cast.State,
  bag_index bag_index: Int,
  held held: Int,
  at ms: Int,
) -> #(cast.State, List(cast.Effect)) {
  support.key_in(
    plans: support.plans_with_costless_mind_burst(),
    state:,
    bag_index:,
    held:,
    at: ms,
  )
}

/// The lines a client reads of the writes of these steps, as `cast_lines` makes
/// them.
fn lines(steps steps: List(#(Int, List(cast.Effect)))) -> List(String) {
  support.cast_lines(
    frames: list.flat_map(steps, fn(step) { support.writes(effects: step.1) }),
  )
}

fn delays_of(effects effects: List(cast.Effect)) -> List(Int) {
  list.map(support.started_timers(effects:), fn(started) { started.1 })
}

/// The cast ids of the 0x7ff among the writes, in order.
fn started_ids(effects effects: List(cast.Effect)) -> List(Int) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id {
      0x07FF -> {
        let assert Ok(started) = spell_started.decode(frame.body)
        Ok(started.cast_id)
      }
      _ -> Error(Nil)
    }
  })
}

pub fn a_held_press_of_a_normal_ability_starts_it_with_a_server_cast_id_and_no_0x7fd_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    key(state: cast.new(), bag_index: mind_burst, held: 1, at: 1000)
  let frames = support.writes(effects:)
  assert support.ids(frames:) == [0x07FF, 0x07F4, 0x07FE]
    as "cast.hold_answer: 0x7ff, then 0x7f4 and 0x7fe as for a 0x9a cast, and no 0x7fd, which needs a pending cast the client makes only for 0x9a"
  let assert [start_frame, ..] = frames
  let assert Ok(started) = spell_started.decode(start_frame.body)
  assert started.cast_id != 0
    as "cast.hold_answer: the server cast id is new and non-zero"
  assert started.spell4_id == 32_809
    as "Spell4.32809, Mind Burst (Spell4Base 19019), the Esper's ability at bag index 2"
  assert started.caster_unit_id == 7 as "cast.hold_answer: the player casts"
  assert started.field_12 == 1 as "opcode.0x7ff.own_cast: the own-cast bit is 1"
  assert list.filter_map(support.tells(effects:), fn(told) {
      case told {
        #(viewer, CastStarted(..)) -> Ok(viewer)
        #(_, _) -> Error(Nil)
      }
    })
    == [ConnectionId(2), ConnectionId(3)]
    as "the players that see the caster are told the start, as for a 0x9a cast"
}

pub fn a_held_press_the_rule_refuses_gets_0x7fc_with_client_cast_id_0_and_no_hold_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = key(state: cast.new(), bag_index: kick, held: 1, at: 1000)
  let #(state, _) = key(state:, bag_index: kick, held: 0, at: 1100)
  let #(state, effects) = key(state:, bag_index: kick, held: 1, at: 10_000)
  let assert [frame] = support.writes(effects:)
    as "a refused held press writes one 0x7fc"
  let assert Ok(refused) = spell_cast_refused.decode(frame.body)
  assert refused.client_cast_id == 0
    as "cast.hold_answer: the refusal names client cast id 0, which the client shows with no pending cast"
  assert refused.spell4_id == 58_591 && cast_result_value(refused) == 15
    as "Spell4.58591: a cooldown of 20000 ms started by the first press's go at 1000 has 11 s left, refused 15 (opcode.0x7fc)"
  assert support.started_timers(effects:) == [] && support.tells(effects:) == []
    as "a refusal starts no timer: the hold ends with it"
  let #(_, later) = key(state:, bag_index: kick, held: 0, at: 10_100)
  assert later == [] as "the release of a refused hold changes nothing"
  let unarmed = cast.Caster(..support.caster(), weapon: None)
  let assert Ok(#(_, effects)) =
    cast.take(
      cast: cast.new(),
      message: cast.KeyHeld,
      body: support.hold_body(bag_index: 9, target: 0, held: 1),
      caster: unarmed,
      plans: support.plans(),
      now: support.at(ms: 1000),
    )
  assert support.cast_lines(frames: support.writes(effects:))
    == ["refused 41438 169"]
    as "0x1403afb10: Zap, weapon slot 1, needs an item in slot 16: refused 169 as a 0x9a is"
}

fn cast_result_value(refused: spell_cast_refused.SpellCastRefused) -> Int {
  cast_result.to_value(refused.result)
}

pub fn a_held_ability_starts_again_each_time_its_cast_ends_and_its_global_cooldown_has_run_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    key(state: cast.new(), bag_index: mind_burst, held: 1, at: 1000)
  assert delays_of(effects: first) == [1250]
    as "SpellCoolDown 104: the global cooldown of Spell4.32809 is 1250 ms, so the next cast waits for it on one timer"
  let assert [#(timer, _)] = support.started_timers(effects: first)
  let #(state, second) = support.fired(state:, timer:, at: 2250)
  assert delays_of(effects: second) == [1250]
  let assert [#(timer, _)] = support.started_timers(effects: second)
  let #(state, third) = support.fired(state:, timer:, at: 3500)
  assert delays_of(effects: third) == [1250]
  let assert [#(timer, _)] = support.started_timers(effects: third)
  let #(_, fourth) = support.fired(state:, timer:, at: 4750)
  assert lines(steps: [#(2250, second), #(3500, third), #(4750, fourth)])
    == [
      "started k1 32809 root 32809 parent 0",
      "went k1 p0",
      "finished k1",
      "started k2 32809 root 32809 parent 0",
      "went k2 p0",
      "finished k2",
      "started k3 32809 root 32809 parent 0",
      "went k3 p0",
      "finished k3",
    ]
    as "cast.hold_repeat: one cast on each of three timers"
  let ids =
    list.flat_map([second, third, fourth], fn(effects) { started_ids(effects:) })
  assert list.unique(ids) |> list.length == 3
    as "each repeat has a new server cast id"
  assert list.contains(ids, 0) == False
}

pub fn a_release_before_the_cast_ends_lets_it_finish_and_starts_no_repeat_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, down) =
    key_raw(state: cast.new(), bag_index: telekinetic_strike, held: 1, at: 1000)
  let assert [#(go, 1250)] = support.started_timers(effects: down)
    as "Spell4.32893: a cast time of 1250 ms, whose go is the one timer"
  let #(state, up) =
    key_raw(state:, bag_index: telekinetic_strike, held: 0, at: 1500)
  assert up == []
    as "cast.hold_stop: the release writes nothing and cuts nothing short"
  let #(_, finished) = support.fired(state:, timer: go, at: 2250)
  assert support.cast_lines(frames: support.writes(effects: finished))
    == ["went k1 p0", "finished k1"]
    as "the cast under way goes and finishes after the release"
  assert support.started_timers(effects: finished) == []
    as "and no repeat follows"
}

pub fn a_repeat_timer_that_fires_after_the_release_starts_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, down) =
    key(state: cast.new(), bag_index: mind_burst, held: 1, at: 1000)
  let assert [#(timer, 1250)] = support.started_timers(effects: down)
  let #(state, up) = key(state:, bag_index: mind_burst, held: 0, at: 1500)
  assert support.cancelled_timers(effects: up) == [timer]
    as "cast.hold_stop: the release cancels the timer that waits to repeat"
  let #(_, fired) = support.fired_raw(state:, timer:, at: 2250)
  assert fired == []
    as "a firing that was already on its way when it was cancelled starts nothing"
}

pub fn a_held_press_during_another_cast_waits_for_its_end_and_is_never_refused_13_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, pressed) =
    support.pressed_raw(
      state: cast.new(),
      caster: support.caster(),
      bag_index: telekinetic_strike,
      target: 0,
      at: 1000,
    )
  let assert [#(go, 1250)] = support.started_timers(effects: pressed)
  let #(state, waiting) =
    key_raw(state:, bag_index: mind_burst, held: 1, at: 1100)
  assert waiting == []
    as "cast.hold_answer: the client hides result 13 under the setting, so the press writes nothing and waits for the cast bar to end"
  let #(_, ended) = support.fired(state:, timer: go, at: 2250)
  assert support.cast_lines(frames: support.writes(effects: ended))
    == [
      "went k1 p0",
      "finished k1",
      "started k2 32809 root 32809 parent 0",
      "went k2 p0",
      "finished k2",
    ]
    as "the held ability starts at the finish of the current cast, 1000 ms of its global cooldown having ended at 2000"
}

pub fn a_second_abilitys_held_press_replaces_the_held_one_and_the_firsts_release_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    key_raw(state: cast.new(), bag_index: telekinetic_strike, held: 1, at: 1000)
  let assert [#(go, 1250)] = support.started_timers(effects: first)
  let #(state, second) =
    key_raw(state:, bag_index: mind_burst, held: 1, at: 1100)
  assert second == []
  let #(state, ended) = support.fired(state:, timer: go, at: 2250)
  assert support.cast_lines(frames: support.writes(effects: ended))
    == [
      "went k1 p0",
      "finished k1",
      "started k2 32809 root 32809 parent 0",
      "went k2 p0",
      "finished k2",
    ]
    as "the newest press wins (the design's choice): the cast of Telekinetic Strike ends by itself and Mind Burst starts, not a second Telekinetic Strike"
  let assert [#(repeat, 1250)] = support.started_timers(effects: ended)
  let #(state, up) =
    key(state:, bag_index: telekinetic_strike, held: 0, at: 2500)
  assert up == [] as "the release of the replaced key changes nothing"
  let #(state, again) = support.fired(state:, timer: repeat, at: 3500)
  assert support.cast_lines(frames: support.writes(effects: again))
    == ["started k1 32809 root 32809 parent 0", "went k1 p0", "finished k1"]
    as "the repeats are the new ability's"
  let assert [#(next, 1250)] = support.started_timers(effects: again)
  let #(_, up) = key(state:, bag_index: mind_burst, held: 0, at: 3600)
  assert support.cancelled_timers(effects: up) == [next]
}

pub fn a_held_key_down_twice_without_a_release_is_one_hold_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    key(state: cast.new(), bag_index: mind_burst, held: 1, at: 1000)
  let assert [#(timer, 1250)] = support.started_timers(effects: first)
  let #(state, second) = key(state:, bag_index: mind_burst, held: 1, at: 1100)
  assert second == []
    as "opcode.0x4db: the client never sends it; the second key down starts no cast and no timer"
  let #(state, repeat) = support.fired(state:, timer:, at: 2250)
  assert list.length(started_ids(effects: repeat)) == 1
  let assert [#(next, _)] = support.started_timers(effects: repeat)
  let #(_, up) = key(state:, bag_index: mind_burst, held: 0, at: 2300)
  assert support.cancelled_timers(effects: up) == [next]
    as "one release ends the hold"
}

pub fn shred_taps_the_first_stage_then_each_next_stage_within_the_window_and_the_release_stops_the_taps_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    key(state: cast.new(), bag_index: support.shred, held: 1, at: 1000)
  let #(state, steps) =
    support.run_timers_until(
      state:,
      effects: first,
      from_ms: 1000,
      until_ms: 2000,
    )
  assert lines(steps: [#(1000, first), ..steps])
    == [
      "started k1 38765 root 38765 parent 0",
      "opened 38765 k1",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
      "started k3 38766 root 38765 parent 38765",
      "went k3 p0",
      "started k4 39467 root 38765 parent 38766",
      "finished k3",
      "closed 38765 1",
    ]
    as "opcode.0x816 and Spell4Thresholds 238: the first tap casts 38765 (thresholdTime 4000) and opens the threshold; one global cooldown later (SpellCoolDown 115: 1000 ms), inside the 4000 ms window, the repeat is the next stage 38766, the last, and 0x814 closes the threshold with the cooldown bit"
  let assert Ok(#(_, last)) = list.last(steps)
  let assert [#(timer, 1000), ..] =
    list.filter(support.started_timers(effects: last), fn(started) {
      started.1 == 1000
    })
    as "the stage's own global cooldown (Spell4.38766: SpellCoolDown 115) makes the next tap wait on a timer"
  let #(state, repeat) = support.fired(state:, timer:, at: 3000)
  assert list.take(
      support.cast_lines(frames: support.writes(effects: repeat)),
      2,
    )
    == ["started k1 38765 root 38765 parent 0", "opened 38765 k1"]
    as "the key still down, the closed threshold gives the next repeat the first tap again"
  let #(_, up) = key(state:, bag_index: support.shred, held: 0, at: 3100)
  assert list.length(support.cancelled_timers(effects: up)) >= 1
    as "cast.hold_by_method: held 0 stops the taps"
}

pub fn charged_shot_is_charged_by_the_press_and_fired_at_its_stage_by_the_release_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, down) =
    key(state: cast.new(), bag_index: support.charged_shot, held: 1, at: 1000)
  assert lines(steps: [#(1000, down)])
    == ["started k1 34718 root 34718 parent 0", "opened 34718 k1"]
    as "cast.hold_by_method: held 1 starts the charge, opening the threshold with the cast's id (opcode.0x816) and no go (cast.charge_release_base)"
  let #(_, up) = key(state:, bag_index: support.charged_shot, held: 0, at: 1500)
  assert lines(steps: [#(1500, up)])
    == [
      "started k1 34720 root 34718 parent 34718",
      "went k1 p0",
      "finished k1",
      "closed 34718 0",
      "finished k2",
    ]
    as "Spell4Thresholds 125: held 0 before 1000 ms of charge fires the stage 34720 as a 0x9a release does, then 0x814 closes the threshold and the base cast ends with its 0x7fe"
}

pub fn a_held_pulse_blast_goes_in_its_two_phases_and_a_held_discharge_pulses_three_times_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, down) =
    key(state: cast.new(), bag_index: support.pulse_blast, held: 1, at: 1000)
  let #(state, _) =
    key(state:, bag_index: support.pulse_blast, held: 0, at: 1000)
  let #(_, steps) = support.run_timers(state:, effects: down, from_ms: 1000)
  assert list.map(steps, fn(step) { step.0 }) == [2250, 2251, 2252, 2253]
    as "SpellPhase 5391: Pulse Blast's second phase 1250 ms after the first; SpellPhase 2820 to 2823: 37302's phases at 0, 1, 1 and 1 ms after its start, so each at the time of the cast that came before"
  assert lines(steps: [#(1000, down), ..steps])
    == [
      "started k1 42276 root 42276 parent 0",
      "went k1 p0",
      "went k1 p1",
      "started k2 37302 root 42276 parent 42276",
      "went k2 p0",
      "finished k1",
      "went k2 p1",
      "went k2 p2",
      "went k2 p3",
      "finished k2",
    ]
    as "SpellPhase 5390 and 5391: Pulse Blast's phases 0 and 1; Spell4Effects 95881 proxies 37302 in phase 1: the same gos and phases as the 0x9a press, and the release between them cut nothing short"
  let #(state, down) =
    key(state: cast.new(), bag_index: support.discharge, held: 1, at: 1000)
  let #(state, _) = key(state:, bag_index: support.discharge, held: 0, at: 1000)
  let #(_, steps) = support.run_timers(state:, effects: down, from_ms: 1000)
  let pulse = fn(pulse, child) {
    [
      "went k1 p" <> int.to_string(pulse),
      "started " <> child <> " 80382 root 58832 parent 58832",
      "went " <> child <> " p0",
      "finished " <> child,
    ]
  }
  assert lines(steps: [#(1000, down), ..steps])
    == list.flatten([
      ["started k1 58832 root 58832 parent 0"],
      pulse(0, "k2"),
      pulse(1, "k3"),
      pulse(2, "k4"),
      ["finished k1"],
    ])
    as "Spell4.58832, Discharge: a go for each of its three pulses (channelPulseTime 410, channelMaxTime 1250), each starting its Proxy 80382 with the pulse index as its phase, then the finish; the release cut nothing short"
}

pub fn a_held_press_of_a_method_the_rule_does_not_cast_is_refused_285_and_logged_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    key(
      state: cast.new(),
      bag_index: support.unbuilt_bag_index,
      held: 1,
      at: 1000,
    )
  assert support.cast_lines(frames: support.writes(effects:))
    == ["refused 4 285"]
    as "Spell.CodeEnumCastMethod: a PressHold spell is refused 285 (IllegalSpellCast), as the 0x9a path refuses it"
  assert list.map(support.logs(effects:), fn(line) { line.0 }) == [LogWarning]
    as "the coverage log is a warning"
  let #(_, again) =
    key(state:, bag_index: support.unbuilt_bag_index, held: 1, at: 1100)
  assert support.logs(effects: again) == []
    as "the coverage log is once for each spell"
}

pub fn a_hold_body_the_clients_reader_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let valid = support.hold_body(bag_index: 2, target: 0x12345, held: 1)
  list.each([<<valid:bits, 0>>, <<1, 2, 3>>, <<>>], fn(body) {
    let assert Error(cast.NotDecoded(..)) =
      cast.take(
        cast: cast.new(),
        message: cast.KeyHeld,
        body:,
        caster: support.caster(),
        plans: support.plans(),
        now: support.at(ms: 1000),
      )
      as "opcode.0x4db: the body is 16 + 32 + 1 bits, read to its end; a longer or shorter body is one the client's reader refuses"
  })
}

pub fn a_bag_index_with_no_ability_is_refused_0x7fc_with_spell_id_0_and_result_4_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    key(state: cast.new(), bag_index: 99, held: 1, at: 1000)
  let assert [frame] = support.writes(effects:)
  let assert Ok(refused) = spell_cast_refused.decode(frame.body)
  assert refused.client_cast_id == 0
    && refused.spell4_id == 0
    && cast_result_value(refused) == 4
    as "0x14039a040 gives 4 (SpellUnknown) for a bag index past the bag, as for a 0x9a (the server's choice, which the client allows); the client cast id is 0 (cast.hold_answer)"
  let #(_, up) = key(state:, bag_index: 99, held: 0, at: 1100)
  assert support.writes(effects: up) == []
    as "the key up of such a key writes nothing"
}

pub fn the_player_leaving_the_world_mid_hold_ends_the_hold_and_every_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, down) =
    key(state: cast.new(), bag_index: mind_burst, held: 1, at: 1000)
  let assert [#(timer, 1250)] = support.started_timers(effects: down)
  let #(state, effects) = cast.left(cast: state)
  assert support.cancelled_timers(effects:) == [timer]
    as "the timer that waits to repeat is cancelled with the others"
  let #(_, fired) = support.fired_raw(state:, timer:, at: 2250)
  assert fired == [] as "a firing that comes anyway starts nothing"
}
