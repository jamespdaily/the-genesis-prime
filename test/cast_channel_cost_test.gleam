//// What a pressed Channeled spell pays and how it ends (`genesis_prime/game/cast`,
//// `cast_cost.pulse_costs`): its cost is paid at every go, and the channel ends, as a
//// cancel ends it, at the first go whose cost the caster cannot pay. Each test is one rule
//// and its rows are the cases, run through one check. Expected values come from these
//// places, each named in the row's reason:
//// - `UI/ToolTips/ToolTips.lua` 2458-2491: the cost line of a Channeled spell is wrapped
////   in text 469255 (`$1n/tick`), a cost per pulse; no other cast method gets that label.
//// - The client's rows (`table_rows -- Spell4 41276 34658 39366 58841`): Electrocute
////   cost 8 of type 6 with a channel of delay 500, maximum 3000 and
////   pulse 500 (6 gos); Particle Ejector 34658 costs 5 of type 6 with the same times;
////   Frenzy 39366 costs 10 of type 8 with delay 0, maximum 2500 and pulse 500 (6 gos);
////   Emission 58841 costs 15 of type 15 (Focus) with delay 410, maximum 1250 and pulse 410
////   (3 gos).
//// - `Spell4.innateCost0.timing` (`0x1403b3320`): the client checks one pulse's cost
////   before it sends a press, reads a slot as a whole number, and never spends: when to pay
////   is the server's. A server choice: a channel whose pulse cannot be paid
////   ends.
//// - `opcode.0x7fe`: the client reads a 0x7fe alone as a complete end of a cast, as it reads
////   the end of a cancel; a 0x7f9 would destroy every target node on the client
////   (`opcode.0x7f9`).
//// - `0x14053e1b0`: a Channeled cast's cooldown starts when the cast ends.
//// The caster's slot, the other casts' spends and the clock are the test's: each step's
//// payments are taken into the caster the next timer meets (`channel_support`).

import cast_support as support
import channel_support.{type Run, type Scene, type Step}
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/message/cast_result
import genesis_prime/shared/class_resource.{type Payment, Payment}
import genesis_prime/shared/cooldown
import genesis_prime/shared/prerequisite.{type Prerequisite}
import genesis_prime/shared/spell_plan.{type Spell, Spell}
import genesis_prime/step.{type TimerId}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import prerequisite_support as prerequisites
import spell_tables

const engineer = 2

const esper = 3

const medic = 4

const stalker = 5

/// Electrocute, Engineer, Volatility (slot 1).
fn electrocute() -> Spell {
  spell_tables.client_spell(41_276)
}

/// Particle Ejector, Engineer, Volatility (slot 1).
fn particle_ejector() -> Spell {
  spell_tables.client_spell(34_658)
}

/// Frenzy, Stalker, Suit Power (slot 3).
fn frenzy() -> Spell {
  spell_tables.client_spell(39_366)
}

/// Emission as the client's rows plan it: its cost is Focus, which the server does not
/// hold.
fn emission() -> Spell {
  spell_tables.client_spell(58_841)
}

/// Emission with a cost of 3 of slot 1 in place of its Focus cost, held by an Engineer
/// (the Medic's slot 1 holds at most 4, too little for 3 gos of 3), so its own go times,
/// 410 ms apart, show the rule pays by the cast method and not by the vital.
fn emission_costing_three() -> Spell {
  Spell(..emission(), costs: [
    spell_plan.SlotCost(slot: 1, amount: 3, result: 51),
  ])
}

/// Discharge, Esper: a channel whose rows hold no cost.
fn discharge() -> Spell {
  support.ability(base: 38_201)
}

/// The spell with a cooldown of 8000 ms, which no channel above has, so a cooldown that
/// starts shows.
fn with_cooldown(spell: Spell) -> Spell {
  Spell(..spell, cooldown_ms: 8000)
}

fn each(at times: List(Int), pays payment: Payment) -> List(#(Int, Payment)) {
  list.map(times, fn(after_ms) { #(after_ms, payment) })
}

fn volatility(points: Int) -> Payment {
  Payment(slot: 1, amount: points)
}

fn suit_power(points: Int) -> Payment {
  Payment(slot: 3, amount: points)
}

fn near(first: Float, second: Float) -> Bool {
  float.loosely_equals(first, second, tolerating: 0.0001)
}

// ---- 1: a channel pays at each go ----

type Pays {
  Pays(
    name: String,
    spell: Spell,
    class_id: Int,
    holding: Float,
    slot: Int,
    paid: List(#(Int, Payment)),
    left: Float,
    reason: String,
  )
}

pub fn a_channel_pays_its_cost_at_each_go_test() -> Nil {
  use <- owned_test.run(10_000)
  let six_gos = [500, 1000, 1500, 2000, 2500, 3000]
  [
    Pays(
      name: "1.1",
      spell: electrocute(),
      class_id: engineer,
      holding: 100.0,
      slot: 1,
      paid: each(at: six_gos, pays: volatility(8)),
      left: 52.0,
      reason: "ToolTips.lua 2486-2487: the cost of a Channeled spell is 'per tick'; Spell4 41276: type 6 cost 8, delay 500, max 3000, pulse 500, so 6 gos of 8 leave 100 - 48",
    ),
    Pays(
      name: "1.2",
      spell: particle_ejector(),
      class_id: engineer,
      holding: 100.0,
      slot: 1,
      paid: each(at: six_gos, pays: volatility(5)),
      left: 70.0,
      reason: "Spell4 34658: type 6 cost 5, the same times; its first go pays what the accept reserved",
    ),
    Pays(
      name: "1.3",
      spell: frenzy(),
      class_id: stalker,
      holding: 100.0,
      slot: 3,
      paid: each(at: [0, 500, 1000, 1500, 2000, 2500], pays: suit_power(10)),
      left: 40.0,
      reason: "Spell4 39366: type 8 cost 10, delay 0, max 2500, pulse 500: the first go is at the press, whose accept pays (pays_at_accept), and the later gos pay with nothing reserved",
    ),
    Pays(
      name: "1.4",
      spell: emission_costing_three(),
      class_id: engineer,
      holding: 100.0,
      slot: 1,
      paid: each(at: [410, 820, 1230], pays: volatility(3)),
      left: 92.0,
      reason: "Spell4 58841 holds Focus, which is not held, so its cost is planted as 3 of slot 1; its own times are 410, 820 and 1230: the rule reads the cast method, not the vital; 100 less 3 x 3 is 91, and its last go gives 1 of slot 1 (its plan's one Gain), so 92",
    ),
    Pays(
      name: "1.5",
      spell: discharge(),
      class_id: esper,
      holding: 5.0,
      slot: 1,
      paid: [],
      left: 5.0,
      reason: "Discharge (base 38201) is a channel whose rows hold no cost: nothing to pay at any go (the Esper's slot holds 5 at most)",
    ),
  ]
  |> list.each(fn(row) {
    let run =
      channel_support.run_channel(scene: channel_support.channel_scene(
        spell: row.spell,
        class_id: row.class_id,
        holding: row.holding,
      ))
    assert channel_support.payments(run:) == row.paid
      as { row.name <> ": " <> row.reason }
    assert near(channel_support.held(run:, slot: row.slot), row.left)
      as { row.name <> ": the slot reads what the payments leave" }
  })
}

// ---- 2: a go that cannot be paid ends the channel ----

type Ending {
  Ending(
    name: String,
    spell: Spell,
    class_id: Int,
    holding: Float,
    slot: Int,
    before: fn(Int, Caster) -> Caster,
    leaves_open: fn(Int) -> Bool,
    paid: List(#(Int, Payment)),
    struck: List(Int),
    went: Int,
    ended_at: Int,
    left: Float,
    reason: String,
  )
}

fn unchanged(_: Int, caster: Caster) -> Caster {
  caster
}

fn closed(_: Int) -> Bool {
  False
}

/// Another cast spends these points of slot 1 when the timer at `at` is due.
fn spent_at(at at: Int, points points: Int) -> fn(Int, Caster) -> Caster {
  fn(after_ms, caster: Caster) {
    case after_ms == at {
      True ->
        cast_state.Caster(
          ..caster,
          resources: class_resource.paid(resources: caster.resources, payments: [
            Payment(slot: 1, amount: points),
          ]),
        )
      False -> caster
    }
  }
}

/// The slot gains these points when the timer at `at` is due.
fn gained_at(
  at at: Int,
  slot slot: Int,
  points points: Int,
) -> fn(Int, Caster) -> Caster {
  fn(after_ms, caster: Caster) {
    case after_ms == at {
      True ->
        cast_state.Caster(
          ..caster,
          resources: class_resource.gain(resources: caster.resources, gains: [
            class_resource.Gain(slot:, amount: points),
          ]).0,
        )
      False -> caster
    }
  }
}

fn ending_scene(row: Ending) -> Scene {
  channel_support.channel_scene(
    spell: with_cooldown(row.spell),
    class_id: row.class_id,
    holding: row.holding,
  )
}

fn ending_run(row: Ending, until until: Option(Int)) -> Run {
  channel_support.run_scripted(
    scene: ending_scene(row),
    until_after_ms: until,
    before: row.before,
    leaves_open: row.leaves_open,
  )
}

/// The lines the client reads of a channel that went `went` times and ended: its press is
/// confirmed with the 0x7fd, each go is a 0x7f4 and the end a 0x7fe (the 0x7ff start is
/// told to viewers, not written to the caster).
fn client_lines(went went: Int) -> List(String) {
  list.flatten([
    ["confirmed k1"],
    list.index_map(list.repeat(Nil, went), fn(_, phase) {
      "went k1 p" <> int.to_string(phase)
    }),
    ["finished k1"],
  ])
}

pub fn a_channel_whose_go_cannot_be_paid_ends_as_a_cancel_ends_it_test() -> Nil {
  use <- owned_test.run(10_000)
  [
    Ending(
      name: "2.1",
      spell: electrocute(),
      class_id: engineer,
      holding: 30.0,
      slot: 1,
      before: unchanged,
      leaves_open: closed,
      paid: each(at: [500, 1000, 1500], pays: volatility(8)),
      struck: [500, 1000, 1500],
      went: 3,
      ended_at: 2000,
      left: 6.0,
      reason: "30 pays three gos (22, 14, 6) and the 6 left cannot pay the fourth, which ends the channel with a 0x7fe (opcode.0x7fe)",
    ),
    Ending(
      name: "2.2",
      spell: electrocute(),
      class_id: engineer,
      holding: 24.0,
      slot: 1,
      before: unchanged,
      leaves_open: closed,
      paid: each(at: [500, 1000, 1500], pays: volatility(8)),
      struck: [500, 1000, 1500],
      went: 3,
      ended_at: 2000,
      left: 0.0,
      reason: "a pulse the slot exactly covers is paid: 24 pays three gos down to 0 (0x1403b3320)",
    ),
    Ending(
      name: "2.3",
      spell: electrocute(),
      class_id: engineer,
      holding: 8.9,
      slot: 1,
      before: unchanged,
      leaves_open: closed,
      paid: each(at: [500], pays: volatility(8)),
      struck: [500],
      went: 1,
      ended_at: 1000,
      left: 0.9,
      reason: "the client reads a slot as a whole number (0x1403b3320): 8.9 pays the first go and the 0.9 left is not a pulse",
    ),
    Ending(
      name: "2.4",
      spell: emission_costing_three(),
      class_id: engineer,
      holding: 7.0,
      slot: 1,
      before: unchanged,
      leaves_open: closed,
      paid: each(at: [410, 820], pays: volatility(3)),
      struck: [410, 820],
      went: 2,
      ended_at: 1230,
      left: 1.0,
      reason: "7 pays two pulses of 3 and the third, the channel's last go at 1230, finds 1: the end applies at the last go as at any other",
    ),
    Ending(
      name: "2.5",
      spell: particle_ejector(),
      class_id: engineer,
      holding: 12.0,
      slot: 1,
      before: unchanged,
      leaves_open: closed,
      paid: each(at: [500, 1000], pays: volatility(5)),
      struck: [500, 1000],
      went: 2,
      ended_at: 1500,
      left: 2.0,
      reason: "Spell4 34658 costs 5: 12 pays two gos and the 2 left cannot pay the third",
    ),
    Ending(
      name: "2.6",
      spell: frenzy(),
      class_id: stalker,
      holding: 25.0,
      slot: 3,
      before: unchanged,
      leaves_open: closed,
      paid: each(at: [0, 500], pays: suit_power(10)),
      struck: [0, 500],
      went: 2,
      ended_at: 1000,
      left: 5.0,
      reason: "Spell4 39366 costs 10 and its first go is at 0: the accept pays, go 1 pays, and go 2 finds 5",
    ),
    Ending(
      name: "2.7",
      spell: electrocute(),
      class_id: engineer,
      holding: 16.0,
      slot: 1,
      before: spent_at(at: 1000, points: 8),
      leaves_open: closed,
      paid: each(at: [500], pays: volatility(8)),
      struck: [500],
      went: 1,
      ended_at: 1000,
      left: 0.0,
      reason: "the check reads the caster as it is at the go: another cast spent the 8 left before go 1",
    ),
    Ending(
      name: "2.8",
      spell: frenzy(),
      class_id: stalker,
      holding: 10.0,
      slot: 3,
      before: gained_at(at: 500, slot: 3, points: 10),
      leaves_open: closed,
      paid: each(at: [0, 500], pays: suit_power(10)),
      struck: [0, 500],
      went: 2,
      ended_at: 1000,
      left: 0.0,
      reason: "the check reads the caster as it is at the go, upward as well: the slot regenerated 10 before go 1, so go 1 pays and go 2 finds 0",
    ),
    Ending(
      name: "2.9",
      spell: electrocute(),
      class_id: engineer,
      holding: 8.0,
      slot: 1,
      before: unchanged,
      leaves_open: fn(after_ms) { after_ms == 500 },
      paid: each(at: [500], pays: volatility(8)),
      struck: [500],
      went: 0,
      ended_at: 1000,
      left: 0.0,
      reason: "go 0's round is still open when go 1 is asked: the end is the cancel's, and the round's late answer finds no live cast (go: Error(Nil) -> no effects)",
    ),
  ]
  |> list.each(fn(row) {
    let reason = row.name <> ": " <> row.reason
    let run = ending_run(row, until: None)
    assert channel_support.payments(run:) == row.paid as reason
    assert channel_support.goes(run:) == row.struck
      as { row.name <> ": the go that cannot be paid is not struck" }
    assert channel_support.finished_at(run:) == Ok(row.ended_at)
      as { row.name <> ": the channel ends at the first go it cannot pay" }
    assert channel_support.failures(run:) == 0
      as { row.name <> ": no 0x7f9 is written, only the 0x7fe" }
    assert channel_support.lines(run:) == client_lines(went: row.went)
      as { row.name <> ": the client reads the gos that went and one 0x7fe" }
    assert near(channel_support.held(run:, slot: row.slot), row.left)
      as { row.name <> ": the slot reads what the payments leave" }
    assert numbered(support.cancelled_timers(
        effects: { ending_step(run:, at: row.ended_at) }.effects,
      ))
      == numbered(channel_support.timers_due_after(run:, after_ms: row.ended_at))
      as {
        row.name <> ": the go and finish timers still waiting are cancelled"
      }
    assert dict.size(run.state.casts) == 0 && run.state.current == None
      as {
        row.name <> ": the cast is not live and is no longer the current cast"
      }
    let ended_ms = channel_support.pressed_at_ms + row.ended_at
    assert cooldown.left_ms(
        book: run.state.cooldowns,
        spell4_id: row.spell.spell4_id,
        now_ms: ended_ms,
      )
      == 8000
      as {
        row.name
        <> ": 0x14053e1b0 starts a Channeled cast's cooldown when it ends"
      }
    // One row stands for them all: the end is a cancel's whichever row reaches it; the rows
    // differ in what they pay.
    case row.name == "2.1" {
      True -> ends_as_a_cancel_does(row)
      False -> Nil
    }
    list.each(
      list.filter(run.steps, fn(step) { row.leaves_open(step.after_ms) }),
      fn(open) {
        let #(_, late) =
          support.answered_each(
            caster: run.caster,
            state: run.state,
            effects: open.effects,
            at: ended_ms + 1,
            struck_of: fn(_) { [] },
            rolls: [],
            poses: dict.new(),
          )
        assert support.writes(effects: late) == []
          as {
            row.name <> ": the late answer of a closed round writes nothing"
          }
      },
    )
  })
}

/// The end by the go that cannot be paid is a cancel's: the same frames, tells, timers
/// cancelled and state as the client's 0x801 at the same instant.
fn ends_as_a_cancel_does(row: Ending) -> Nil {
  let #(dry, cancelled, fired) = dry_end_and_cancel(row)
  let same =
    row.name <> ": the end is a cancel's, as a 0x801 at the same instant: "
  assert support.writes(effects: dry.1) == support.writes(effects: cancelled.1)
    as { same <> "the same frames" }
  assert support.tells(effects: dry.1) == support.tells(effects: cancelled.1)
    as { same <> "the same tells" }
  assert numbered(support.cancelled_timers(effects: dry.1))
    == numbered(
      list.filter(support.cancelled_timers(effects: cancelled.1), fn(timer) {
        timer != fired
      }),
    )
    as {
      same
      <> "the same timers cancelled, but the go's own timer, which has fired"
    }
  assert dry.0.casts == cancelled.0.casts
    && dry.0.current == cancelled.0.current
    as { same <> "no live cast and no current cast" }
  assert dry.0.cooldowns == cancelled.0.cooldowns
    as { same <> "the same cooldowns" }
}

/// The timers' numbers, sorted.
fn numbered(timers: List(TimerId)) -> List(Int) {
  list.sort(support.timer_numbers(timers:), int.compare)
}

fn ending_step(run run: Run, at ended_at: Int) -> Step {
  let assert Ok(step) =
    list.find(run.steps, fn(step) { step.after_ms == ended_at })
    as "the channel's ending step is in the run"
  step
}

/// The channel run to just before its end, then ended by the go that cannot be paid and,
/// from the same state, by the client's 0x801 at the same instant: the state and effects of
/// each.
fn dry_end_and_cancel(
  row: Ending,
) -> #(#(State, List(Effect)), #(State, List(Effect)), TimerId) {
  let before = ending_run(row, until: Some(row.ended_at - 1))
  let at_ms = channel_support.pressed_at_ms + row.ended_at
  let assert Ok(#(go_timer, _)) =
    list.find(before.started, fn(started) { started.1 == row.ended_at })
    as "a go is due at the end"
  let caster = row.before(row.ended_at, before.caster)
  let dry =
    support.fired_raw_as(
      caster:,
      state: before.state,
      timer: go_timer,
      at: at_ms,
    )
  let assert Ok(cancelled) =
    support.cancelled_in(
      plans: support.plans_with(spell: with_cooldown(row.spell)),
      state: before.state,
      cast_id: before.cast_id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: at_ms,
    )
  #(dry, cancelled, go_timer)
}

// ---- 3: an early end has paid for the gos that ran ----

type Stop {
  Cancelled
  Died
  LeftTheWorld
  PersistenceFailed
}

type Early {
  Early(
    name: String,
    stop: Stop,
    after_ms: Int,
    paid: Int,
    finished: Bool,
    reason: String,
  )
}

/// The caster is in combat, which Electrocute's planted persistence asks for
/// (Prerequisite 903, type 28: the caster in combat).
fn in_combat() -> Prerequisite {
  prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
}

/// What a stop does to the run's state at `after_ms` after the press.
fn stopped(
  run run: Run,
  stop stop: Stop,
  after_ms after_ms: Int,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let now = support.at(ms: channel_support.pressed_at_ms + after_ms)
  case stop {
    Cancelled -> {
      let assert Ok(done) =
        support.cancelled_in(
          plans: support.plans_with(spell:),
          state: run.state,
          cast_id: run.cast_id,
          reason: cast_result.SpellCancelled,
          bit: 1,
          at: now.monotonic_ms,
        )
      done
    }
    Died -> cast.died(cast: run.state, caster: support.dead_caster(), now:)
    LeftTheWorld -> cast_tick.left(cast: run.state)
    PersistenceFailed ->
      cast.persisted(
        cast: run.state,
        caster: cast_state.Caster(..run.caster, in_combat: False),
        now:,
      )
  }
}

pub fn a_channel_that_ends_early_has_paid_only_for_the_gos_that_ran_test() -> Nil {
  use <- owned_test.run(10_000)
  [
    Early(
      name: "3.1",
      stop: Cancelled,
      after_ms: 100,
      paid: 0,
      finished: True,
      reason: "a 0x801 before go 0: no go ran, so nothing is paid (opcode.0x801)",
    ),
    Early(
      name: "3.2",
      stop: Cancelled,
      after_ms: 1500,
      paid: 3,
      finished: True,
      reason: "a 0x801 right after go 2 (gos at 500, 1000, 1500): each go that ran paid",
    ),
    Early(
      name: "3.3",
      stop: Died,
      after_ms: 1000,
      paid: 2,
      finished: True,
      reason: "the caster dies after go 1: two gos paid, and the death writes no payment (cast.all_ended)",
    ),
    Early(
      name: "3.4",
      stop: LeftTheWorld,
      after_ms: 1000,
      paid: 2,
      finished: False,
      reason: "the caster leaves the world after go 1: two gos paid, and nothing is written (cast_tick.left)",
    ),
    Early(
      name: "3.5",
      stop: PersistenceFailed,
      after_ms: 1000,
      paid: 2,
      finished: True,
      reason: "the cast's persistence fails after go 1: two gos paid, and the end writes no payment (cast.persisted)",
    ),
  ]
  |> list.each(fn(row) {
    let spell = Spell(..electrocute(), caster_persistence: Some(in_combat()))
    let scene =
      channel_support.channel_scene(spell:, class_id: engineer, holding: 100.0)
    let scene =
      channel_support.Scene(
        ..scene,
        caster: cast_state.Caster(..scene.caster, in_combat: True),
      )
    let run =
      channel_support.run_scripted(
        scene:,
        until_after_ms: Some(row.after_ms),
        before: unchanged,
        leaves_open: closed,
      )
    let reason = row.name <> ": " <> row.reason
    assert list.length(channel_support.payments(run:)) == row.paid as reason
    let #(state, ended) =
      stopped(run:, stop: row.stop, after_ms: row.after_ms, spell:)
    assert { support.finished_ids(support.writes(effects: ended)) != [] }
      == row.finished
      as {
        row.name <> ": the end writes the cast's 0x7fe or, on leaving, nothing"
      }
    // Every timer the run started is fired now: those the end cancelled are gone, any
    // other finds no cast to pay for.
    let later =
      list.fold(
        list.sort(run.started, fn(first, second) {
          int.compare(first.1, second.1)
        }),
        #(state, ended),
        fn(so_far, started) {
          let #(state, effects) = so_far
          let #(state, more) =
            support.fired_raw_as(
              caster: run.caster,
              state:,
              timer: started.0,
              at: channel_support.pressed_at_ms + started.1 + 10_000,
            )
          #(state, list.append(effects, more))
        },
      )
    assert support.payments(effects: later.1) == []
      as { row.name <> ": nothing is paid after the end" }
    assert support.goes_asked(effects: later.1) == []
      as { row.name <> ": no go is asked after the end" }
  })
}

// ---- 5: the press ----

type Press {
  Refused(result: Int)
  Accepted(first_go_pays: Payment, after_ms: Int)
}

/// What a press's caster holds the points in: the class slot, or Focus.
type Holds {
  HoldsInSlot
  HoldsFocus
}

type Pressing {
  Pressing(
    name: String,
    spell: Spell,
    class_id: Int,
    holding: Float,
    holds: Holds,
    outcome: Press,
    reason: String,
  )
}

pub fn a_channel_press_is_refused_when_one_gos_cost_cannot_be_met_test() -> Nil {
  use <- owned_test.run(10_000)
  [
    Pressing(
      name: "5.1",
      spell: electrocute(),
      class_id: engineer,
      holding: 7.0,
      holds: HoldsInSlot,
      outcome: Refused(51),
      reason: "Electrocute costs 8 of vital 6: 7 is refused 50 + slot 1 (Spell4CastResult.vital_cost, 0x1403b3320)",
    ),
    Pressing(
      name: "5.2",
      spell: particle_ejector(),
      class_id: engineer,
      holding: 4.0,
      holds: HoldsInSlot,
      outcome: Refused(51),
      reason: "Spell4 34658 costs 5: 4 is refused 51",
    ),
    Pressing(
      name: "5.3",
      spell: frenzy(),
      class_id: stalker,
      holding: 9.0,
      holds: HoldsInSlot,
      outcome: Refused(53),
      reason: "Spell4 39366 costs 10 of slot 3: 9 is refused 50 + 3",
    ),
    Pressing(
      name: "5.4",
      spell: emission(),
      class_id: medic,
      holding: 100.0,
      holds: HoldsFocus,
      outcome: Accepted(
        first_go_pays: Payment(slot: -1, amount: 15),
        after_ms: 410,
      ),
      reason: "Spell4 58841 costs 15 of type 15 (Focus): 100 Focus holds it (0x1403b3320 case 0xe), and its first go, at 410, pays 15",
    ),
    Pressing(
      name: "5.5",
      spell: electrocute(),
      class_id: engineer,
      holding: 8.0,
      holds: HoldsInSlot,
      outcome: Accepted(first_go_pays: volatility(8), after_ms: 500),
      reason: "the press check is one go's cost (0x1403b3320): exactly 8 is accepted and its first go pays",
    ),
  ]
  |> list.each(fn(row) {
    let scene = case row.holds {
      HoldsInSlot ->
        channel_support.channel_scene(
          spell: row.spell,
          class_id: row.class_id,
          holding: row.holding,
        )
      HoldsFocus ->
        channel_support.focus_scene(
          spell: row.spell,
          class_id: row.class_id,
          focus: row.holding,
        )
    }
    let reason = row.name <> ": " <> row.reason
    case row.outcome {
      Refused(result:) -> {
        let #(state, effects, _) = channel_support.pressed(scene:)
        assert support.refusal_results(effects:) == [result] as reason
        assert support.payments(effects:) == []
          as { row.name <> ": a refused press pays nothing" }
        assert support.started_timers(effects:) == []
          as { row.name <> ": a refused press starts no timer" }
        assert support.frames_of(message_id: 0x07FD, effects:) == []
          as { row.name <> ": a refused press is not confirmed" }
        assert dict.size(state.casts) == 0
          as {
            row.name <> ": a refused press reserves nothing: no cast is live"
          }
      }
      Accepted(first_go_pays:, after_ms:) -> {
        let run = channel_support.run_channel(scene:)
        assert support.refusal_results(effects: channel_support.effects(run:))
          == []
          as reason
        assert list.first(channel_support.payments(run:))
          == Ok(#(after_ms, first_go_pays))
          as reason
      }
    }
  })
}

// ---- 6: each paid go is one spend for the procs ----

type Spends {
  Spends(
    name: String,
    spell: Spell,
    class_id: Int,
    holding: Float,
    events: List(#(Int, Int)),
    reason: String,
  )
}

pub fn each_paid_go_of_a_channel_is_one_spend_for_the_procs_test() -> Nil {
  use <- owned_test.run(10_000)
  [
    Spends(
      name: "6.1",
      spell: electrocute(),
      class_id: engineer,
      holding: 100.0,
      events: list.map([500, 1000, 1500, 2000, 2500, 3000], fn(at) { #(at, 1) }),
      reason: "one Pay at each of 6 gos raises one SpendsResource each (cast_proc.resources_spent)",
    ),
    Spends(
      name: "6.2",
      spell: electrocute(),
      class_id: engineer,
      holding: 30.0,
      events: list.map([500, 1000, 1500], fn(at) { #(at, 1) }),
      reason: "the go that cannot be paid writes no Pay, so it raises no spend",
    ),
    Spends(
      name: "6.4",
      spell: emission(),
      class_id: medic,
      holding: 1000.0,
      events: list.map([410, 820, 1230], fn(at) { #(at, 1) }),
      reason: "Emission (Focus): three gos, each Pay of 15 raises one SpendsResource (Spell4Effects.effectType.14.dataBits00 kind 103, a guess already stated in cast/proc.resources_spent)",
    ),
    Spends(
      name: "6.3",
      spell: frenzy(),
      class_id: stalker,
      holding: 100.0,
      events: list.map([0, 500, 1000, 1500, 2000, 2500], fn(at) { #(at, 1) }),
      reason: "the accept's payment counts the same: the first spend comes with the press",
    ),
  ]
  |> list.each(fn(row) {
    let scene = case row.spell.costs {
      [spell_plan.FocusCost(..)] ->
        channel_support.focus_scene(
          spell: row.spell,
          class_id: row.class_id,
          focus: row.holding,
        )
      _ ->
        channel_support.channel_scene(
          spell: row.spell,
          class_id: row.class_id,
          holding: row.holding,
        )
    }
    let run = channel_support.run_channel(scene:)
    assert channel_support.spends(run:) == row.events
      as { row.name <> ": " <> row.reason }
  })
}

// ---- 7: a Focus channel ----

pub fn a_focus_channel_pays_15_at_each_of_emissions_3_gos_and_ends_when_the_pool_cannot_pay_the_next_test() -> Nil {
  use <- owned_test.run(10_000)
  let focus_points = fn(points) { Payment(slot: -1, amount: points) }
  // Name, the Focus held, the payments by time, the end (none: it ran its 3 gos), why.
  [
    #(
      "7.1",
      1000.0,
      each(at: [410, 820, 1230], pays: focus_points(15)),
      None,
      "Spell4 58841: type 15 cost 15, delay 410, max 1250, pulse 410: 3 gos, each paying the cost (the tooltip prices every pulse, ToolTips.lua 2458-2491), 1000 less 45",
    ),
    #(
      "7.2",
      20.0,
      each(at: [410], pays: focus_points(15)),
      Some(820),
      "20 pays the first go and the 5 left cannot pay the second: the channel ends as a cancel ends it (the server's choice), the paid go stays paid",
    ),
  ]
  |> list.each(fn(row) {
    let #(name, held, paid, ended_at, reason) = row
    let run =
      channel_support.run_channel(scene: channel_support.focus_scene(
        spell: emission(),
        class_id: medic,
        focus: held,
      ))
    assert channel_support.payments(run:) == paid as { name <> ": " <> reason }
    assert channel_support.failures(run:) == 0
      as {
        name
        <> ": no 0x7f9, which would destroy the target nodes the server keeps (opcode.0x7f9)"
      }
    case ended_at {
      Some(at) -> {
        assert channel_support.finished_at(run:) == Ok(at)
          as { name <> ": the end is the 0x7fe of the go that cannot be paid" }
      }
      None -> Nil
    }
  })
}
