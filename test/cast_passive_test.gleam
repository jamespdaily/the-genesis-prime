//// A class's innate passive started at each join (`genesis_prime/game/cast`
//// `passive_started`, with the plans of the client's tables). The client never
//// casts a passive and shows no buff for it, so the server starts it as a cast
//// of the player's own with no client press. Expected values come from these
//// places.
//// - `Class.spell4IdInnateAbilityPassive00`: Warrior 44926, Engineer 45000 and
////   Stalker 45057, whose Spell4Base ids are 29035, 29076 and 29131; their
////   uiFlags 4 shows no buff and propertyFlags 0x100 keeps the cast when its
////   caster is removed; every one holds globalCooldownEnum 1 with a global row
////   (100 or 146) and a caster condition row 4 (mask 0: alive or dead).
//// - `table_rows -- Spell4Effects spellId=44926`: 103997, 174526 and 174527
////   (type 11, the DamageDealtMultiplier properties 141 to 143 x 1.0 + 0, until
////   removed), 104001 (Fluff behind 24595), 108420 (VitalModifier -1200 behind
////   24604) and 112840 (removes Spell4 42908, Overdrive).
//// - `spellId=45000`: 104980, 177521 and 177522 (the same three properties), 108412
////   (Proxy to 46297 behind Prerequisite 30012, type 11: not read) and 229304
////   (type 145, not read).
//// - `spellId=45057`: 147119, 147132, 159136, 202043 and 211002 (type 14 procs, not
////   read), 147125 (Proxy to 60724 after 50 ms, ungated), 173780 (VitalModifier
////   behind 37067: in combat) and 173872 (Proxy to 60868 behind 28773); `spellId=60724`:
////   146910, type 24, not read.
//// - `Spell4.spellCastStealthChange`, `cast.target_node_end`: a cast whose nodes last
////   until removed lingers and writes its 0x7fe only when its nodes end.
//// The server's choices, in the rule's doc: a passive starts no global cooldown, is
//// never the current cast and opens no threshold, lingers with no 0x7fe, and is the
//// one cast a death leaves; a camp drops it.
//// Skipped where the client's tables are not on the machine, but for the tests that
//// plant a spell.

import cast_support as support
import client_tables
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, GlobalCooldown, ShowsCastBar, Spell,
}
import genesis_prime/message/spell_go
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4BaseId}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import unitest

fn real_plans() -> Plans {
  spell_plan.plans(client_tables.shared())
}

/// The passive of the Spell4Base started at the time, its go answered with no unit
/// struck.
fn started_in(
  plans plans: Plans,
  caster caster: Caster,
  base base: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    cast.passive_started(
      cast: cast.new(),
      caster:,
      plans:,
      base: Spell4BaseId(base),
      now: support.at(ms:),
    )
  support.answered_as(caster:, state:, effects:, at: ms, struck: [], rolls: [])
}

fn started(base base: Int) -> #(State, List(Effect)) {
  started_in(plans: real_plans(), caster: support.caster(), base:, at: 1000)
}

/// The Spell4Effects ids every go of the effects lists, in id order.
fn listed(effects effects: List(Effect)) -> List(Int) {
  list.filter(support.writes(effects:), fn(frame) {
    frame.message_id == spell_go.message_id
  })
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body)
      as "a go the rule wrote decodes"
    list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  })
  |> list.sort(int.compare)
}

fn lines(effects effects: List(Effect)) -> List(String) {
  support.cast_lines(frames: support.writes(effects:))
}

// ---- what each passive starts ----

pub fn the_warriors_passive_starts_with_0x7ff_no_0x7fd_and_lists_the_fluff_and_the_three_properties_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(state, effects) = started(base: 29_035)
  assert lines(effects:)
    == ["started k1 44926 root 44926 parent 0", "went k1 p0"]
    as "opcode.0x7ff: the start of a cast no press made, so no 0x7fd confirms it; its one go follows (castTime 0), and no 0x7fe ends it"
  assert listed(effects:) == [103_997, 104_001, 112_840, 174_526, 174_527]
    as "Spell4Effects 104001 (Fluff, behind 24595, which a caster not under Spell4 59078 passes), the properties 103997, 174526, 174527 and the removal 112840, which a go lists as it lists every type 80 row it applies; 108420 is a gain, which a go does not list"
  assert support.removed_targets(support.writes(effects:)) == []
    as "112840 removes Spell4 42908, which no cast of the caster is"
  let #(_, timers) = support.run_timers(state:, effects:, from_ms: 1000)
  assert timers == [] as "no timer is left: its nodes last until removed"
}

pub fn the_engineers_passive_lists_its_three_properties_and_skips_the_proxy_it_cannot_decide_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(_, effects) = started(base: 29_076)
  assert lines(effects:)
    == ["started k1 45000 root 45000 parent 0", "went k1 p0"]
    as "46297 does not start, and 229304 (type 145) is skipped"
  assert listed(effects:) == [104_980, 177_521, 177_522]
    as "Spell4Effects 104980, 177521 and 177522: the properties 141 to 143"
  let assert [line] =
    list.filter(support.logs(effects:), fn(line) {
      string.contains(line.1, "46297")
    })
    as "one line says why the Proxy to 46297 does not start"
  assert line.0 == LogDebug
  assert string.contains(line.1, "30012") && string.contains(line.1, "type 11")
    as "Spell4Effects 108412 is behind Prerequisite 30012, of type 11, which the server does not read"
}

pub fn the_stalkers_passive_lists_nothing_and_starts_60724_50_ms_later_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(state, effects) = started(base: 29_131)
  assert lines(effects:)
    == ["started k1 45057 root 45057 parent 0", "went k1 p0"]
    as "the procs 147119, 147132, 159136, 202043 and 211002 (type 14) are not read, so the go lists nothing and the cast lingers with no 0x7fe"
  assert listed(effects:) == []
  assert support.started_timers(effects:) |> list.map(fn(timer) { timer.1 })
    == [50]
    as "Spell4Effects 147125, the ungated Proxy to 60724, waits its delayTime of 50 ms; 173780 (behind 37067: in combat) and the Proxy to 60868 (behind 28773: under Spell4 59312) are withheld out of combat"
  let #(_, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  let assert [#(due, child)] = steps
  assert due == 1050
  assert lines(effects: child)
    == [
      "started k1 60724 root 45057 parent 45057",
      "went k1 p0",
      "finished k1",
    ]
    as "60724's one row, 146910 (type 24), is not read: its go lists nothing and its cast ends"
}

// ---- the passive is no ordinary cast ----

/// A planted passive spell: a cast time of 1000 ms with a cast bar, a global
/// cooldown of 1500 ms that refuses while it runs, which an ordinary press makes the
/// current cast and starts the global cooldown with.
fn slow_passive() -> Spell {
  Spell(
    ..support.child(spell4_id: 250_001, base: 250_001),
    cast_time_ms: 1000,
    cast_bar: ShowsCastBar,
    global_cooldown: GlobalCooldown(
      refused_while_running: True,
      starts_for_ms: Some(1500),
    ),
  )
}

fn planted_plans() -> Plans {
  support.with_spells(plans: support.plans(), spells: [slow_passive()])
}

/// A caster whose bag holds the planted spell at index 0 and Telekinetic Strike
/// at 1.
fn caster_of_planted() -> Caster {
  cast.Caster(..support.caster(), abilities: [
    Spell4BaseId(250_001),
    Spell4BaseId(19_102),
  ])
}

pub fn an_ordinary_press_of_the_planted_spell_is_the_current_cast_and_starts_the_global_cooldown_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    support.pressed_raw_in(
      plans: planted_plans(),
      state: cast.new(),
      caster: caster_of_planted(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let #(_, pressed) =
    support.pressed_raw_in(
      plans: planted_plans(),
      state:,
      caster: caster_of_planted(),
      bag_index: 1,
      target: 0,
      at: 1100,
    )
  assert support.refusal_results(effects: pressed) == [13]
    as "the control: a cast with a cast bar is the current cast, which refuses a press while it lasts (13, 0x1403b14c0)"
}

pub fn a_passive_starts_no_global_cooldown_is_never_the_current_cast_and_opens_no_threshold_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, effects) =
    cast.passive_started(
      cast: cast.new(),
      caster: caster_of_planted(),
      plans: planted_plans(),
      base: Spell4BaseId(250_001),
      now: support.at(ms: 1000),
    )
  assert lines(effects:) == ["started k1 250001 root 250001 parent 0"]
    as "0x7ff alone: no 0x7fd, and its go waits for its cast time"
  let #(_, pressed) =
    support.pressed_raw_in(
      plans: planted_plans(),
      state:,
      caster: caster_of_planted(),
      bag_index: 1,
      target: 0,
      at: 1100,
    )
  assert support.refusal_results(effects: pressed) == []
    as "the passive is not the current cast, so it refuses nothing, and its 1500 ms global cooldown is not started, so the press is not held by it (14)"
  assert support.frames_of(message_id: 0x0816, effects:) == []
    as "opcode.0x816: no threshold opens for a passive"
}

// ---- death, camp and entry ----

/// The Warrior's passive pressed as an ordinary ability: its nodes linger as a
/// passive's do.
fn warrior_pressed_as_an_ability() -> #(State, List(Effect)) {
  let caster =
    cast.Caster(..support.caster(), abilities: [Spell4BaseId(29_035)])
  let #(state, effects) =
    support.pressed_raw_in(
      plans: real_plans(),
      state: cast.new(),
      caster:,
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  support.answered_as(
    caster:,
    state:,
    effects:,
    at: 1000,
    struck: [],
    rolls: [],
  )
}

pub fn death_leaves_the_passive_with_its_nodes_and_modifiers_where_it_ends_an_ordinary_cast_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(ordinary, _) = warrior_pressed_as_an_ability()
  let #(_, ordinary_death) =
    cast.died(cast: ordinary, now: support.at(ms: 5000))
  assert list.length(support.frames_of(
      message_id: 0x07FE,
      effects: ordinary_death,
    ))
    == 1
    as "the control: the same spell pressed as an ability lingers, and its caster's death ends it with its 0x7fe (cast.died)"
  assert list.length(support.property_ends(effects: ordinary_death)) == 3
    as "and takes its three property modifiers off"
  let #(passive, _) = started(base: 29_035)
  let #(left, died) = cast.died(cast: passive, now: support.at(ms: 5000))
  assert support.frames_of(message_id: 0x07FE, effects: died) == []
    as "Spell4.44926: caster condition row 4 holds alive or dead, and propertyFlags 0x100 keeps the cast when its caster is removed, so death leaves the passive"
  assert support.property_ends(effects: died) == [] as "and its modifiers"
  let #(_, after) = cast.died(cast: left, now: support.at(ms: 6000))
  assert support.frames_of(message_id: 0x07FE, effects: after) == []
    as "a second death still leaves it"
}

pub fn a_camp_or_the_holocrypt_drops_the_passive_writing_nothing_and_the_next_join_starts_it_again_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(passive, _) = started(base: 29_035)
  let #(dropped, effects) = cast.left(cast: passive)
  assert support.writes(effects:) == []
    as "a camp writes nothing for any cast (cast.left)"
  let #(_, again) =
    cast.passive_started(
      cast: dropped,
      caster: support.caster(),
      plans: real_plans(),
      base: Spell4BaseId(29_035),
      now: support.at(ms: 9000),
    )
  assert lines(effects: again) == ["started k1 44926 root 44926 parent 0"]
    as "the next join starts the passive afresh"
}

pub fn a_player_saved_dead_starts_the_passive_at_entry_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let caster = cast.Caster(..support.caster(), dead: True)
  let #(_, effects) =
    started_in(plans: real_plans(), caster:, base: 29_035, at: 1000)
  assert lines(effects:)
    == ["started k1 44926 root 44926 parent 0", "went k1 p0"]
    as "Spell4.44926: caster condition row 4 (mask 0) holds alive or dead, so a dead player holds it too"
}
