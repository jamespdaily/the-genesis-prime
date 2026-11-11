//// The cast rule's activate cast (`genesis_prime/game/cast.activate`): the player's right-click
//// of a collectible, the Seaspine Mollusk (Creature2 26462) on the client's own rows, on a
//// clock the test drives. Expected values come from these places:
//// - `opcode.0x97`: the message carries the client's cast id and the unit; the client has set the
////   activate bit on its own cast, which a viewer's 0x7ff carries as `field_13` 1
////   (`opcode.0x7ff.activate`).
//// - Creature2 26462: activateSpellCastTime 2000, activateSpellMaxRange 3.0, activate
////   spell 1817 behind Prerequisite 9358; Spell4 1817: castTime 0, targetMaxRange 5.0; Spell4 8
////   (the default activate spell): castTime 0, targetMaxRange 0.
//// - Spell4Effects 2821 and 3292: the Activate rows of Spell4 1817 and Spell4 8.
//// - `opcode.0x97.range` (`0x1403b2240`): the gap between the units' edges, in three
////   dimensions, is held to the minimum, then the maximum, then the height.
//// - `opcode.0x7f4.target_info` and `opcode.0x7f4.instance_count`: the go names the unit with
////   the effect info of its Activate row.
//// - The Departures Terminal, Creature2 73605: activateSpellCastTime 0, activateSpellMaxRange 4.0,
////   activate spell Spell4 34681 (castTime 0, global cooldown kind 2, Spell4Base 20651:
////   castMethod 5, clientSideInteractionId 357), whose Activate row is Spell4Effects 68913.
//// - `opcode.0x805.fields`: the client's answer is the server's cast id, a result (3 started,
////   1 success, 0 failed, 2 cancelled before starting) and the Spell4Base id plus 1.
//// - `cast.csi_server_flow`, `csi.after_result`, `opcode.0x7fe.csi`: the client never ends the
////   cast; the server's go and finish, or 0x7f9 146 and the finish, end it.

import cast_support as support
import fixture_tables
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/activate.{
  type Target, Activations, Body, CannotBePlanned, Column, Creature,
  HostileToPlayer, InCombat, NoSpell4Row, Planned, Usable,
}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/objective_link
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log
import genesis_prime/game/spell_plan
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/interaction_result.{type InteractionResult}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_failed
import genesis_prime/message/spell_go
import genesis_prime/step.{ConnectionId, LogDebug, LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import place_support
import planted_table
import prerequisite_support
import quest_support

const the_mollusk = 26_462

const a_market_terminal = 34_758

const the_tutorial_mine = 73_463

const market_quest = 7153

const its_unit = 5000

const clients_cast_id = 9

/// The caster stands at a place of exactly representable numbers, so a gap of 3.0 is exact.
fn standing() -> cast.Caster {
  cast.Caster(
    ..support.caster(),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 4096.0,
      y: 0.0,
      z: 512.0,
    ),
  )
}

// Hit radii of exactly representable size: the player's and the object's.
const caster_radius = 0.5

const object_radius = 0.25

fn the_activations() -> activate.Activations {
  activate.activations(tables: fixture_tables.shared())
}

fn mollusk() -> activate.Creature {
  let assert Ok(row) =
    creature2.get(tables: fixture_tables.shared(), id: Creature2Id(the_mollusk))
    as "Creature2 26462 is a root of the fixture"
  activate.creature_of(row:)
}

/// An object `east` units east of the caster (and `up` above it) of this creature.
fn object(
  creature creature: activate.Creature,
  east east: Float,
  up up: Float,
) -> Target {
  object_of(
    creature_id: the_mollusk,
    creature:,
    checklist_index: 0,
    link: activate.NoLink,
    east:,
    up:,
  )
}

fn object_of(
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  link link: activate.Link,
  east east: Float,
  up up: Float,
) -> Target {
  usable_in_state(
    creature_id:,
    creature:,
    checklist_index:,
    link:,
    east:,
    up:,
    alive: True,
    withheld: None,
  )
}

/// A creature or object this far east of the caster, in this life and combat state.
fn usable_in_state(
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  link link: activate.Link,
  east east: Float,
  up up: Float,
  alive alive: Bool,
  withheld withheld: option.Option(activate.Withheld),
) -> Target {
  Usable(
    creature_id:,
    creature:,
    checklist_index:,
    link:,
    body: Body(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 4096.0 +. east,
        y: up,
        z: 512.0,
      ),
      radius: object_radius,
    ),
    alive:,
    in_combat: False,
    withheld:,
  )
}

/// The mollusk's creature (Spell4 1817 as its activate spell) in this state.
fn mollusk_in_state(
  east east: Float,
  alive alive: Bool,
  withheld withheld: option.Option(activate.Withheld),
) -> Target {
  usable_in_state(
    creature_id: the_mollusk,
    creature: mollusk(),
    checklist_index: 0,
    link: activate.NoLink,
    east:,
    up: 0.0,
    alive:,
    withheld:,
  )
}

fn sees_only(target target: Target) -> fn(Int) -> Target {
  fn(unit_id) {
    case unit_id == its_unit {
      True -> target
      False -> activate.Unseen
    }
  }
}

/// The right-click of the unit `unit_id` at the time, by the standing caster.
fn right_click(
  state state: State,
  activations activations: activate.Activations,
  unit_id unit_id: Int,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  right_click_by(
    caster: standing(),
    state:,
    activations:,
    unit_id:,
    target:,
    at: ms,
  )
}

/// The right-click of the unit `unit_id` at the time, by this caster.
fn right_click_by(
  caster caster: cast.Caster,
  state state: State,
  activations activations: activate.Activations,
  unit_id unit_id: Int,
  target target: Target,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(
      client_cast_id: clients_cast_id,
      target_unit_id: unit_id,
    ))
    as "the message fits"
  cast.activate(
    cast: state,
    body:,
    caster:,
    activations:,
    target_of: sees_only(target:),
    caster_radius:,
    now: support.at(ms:),
  )
}

/// The right-click of the Seaspine Mollusk, taken by the rule.
fn right_click_mollusk(
  state state: State,
  east east: Float,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    right_click(
      state:,
      activations: the_activations(),
      unit_id: its_unit,
      target: object(creature: mollusk(), east:, up: 0.0),
      at: ms,
    )
    as "a 0x97 that fits the message is taken"
  taken
}

/// The result a right-click of the mollusk is refused with, when it is refused, and
/// nothing else is done: the one 0x7fc, no timer, no tell.
fn refused_with(
  activations activations: activate.Activations,
  target target: Target,
  unit_id unit_id: Int,
) -> Int {
  let assert Ok(#(_, effects)) =
    right_click(state: cast.new(), activations:, unit_id:, target:, at: 1000)
    as "a refusal is an answer, not an error"
  let assert [result] = support.refusal_results(effects:) as "one 0x7fc"
  assert list.length(support.writes(effects:)) == 1
    && support.started_timers(effects:) == []
    && support.tells(effects:) == []
    as "a refused right-click writes the one 0x7fc and starts nothing"
  result
}

pub fn activate_starts_with_activate_bit_and_creature_cast_time_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, effects) =
    right_click_mollusk(state: cast.new(), east: 1.0, at: 1000)
  let assert [confirmed_frame] =
    support.frames_of(message_id: spell_cast_confirmed.message_id, effects:)
    as "the caster is written one 0x7fd"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed_frame.body)
  assert confirmed.client_cast_id == clients_cast_id
    && confirmed.primary_target_unit_id == its_unit
    as "opcode.0x97: the confirmation answers the client's cast id and names the unit"
  let assert [#(ConnectionId(2), news_2), #(ConnectionId(3), news_3)] =
    support.tells(effects:)
    as "each viewer is told the start"
  assert news_2 == news_3
  let assert CastStarted(start: started) = news_2
  assert started.cast_id == confirmed.server_cast_id
    && started.spell4_id == 1817
    && started.root_spell4_id == 1817
    && started.parent_spell4_id == 0
    && started.caster_unit_id == 7
    && started.primary_target_unit_id == its_unit
    as "the viewers see Spell4 1817, the pick, cast by the caster at the unit"
  assert started.field_13 == 1
    as "opcode.0x7ff.activate: the activate bit is set on the start a viewer is told"
  assert support.writes(effects:)
    |> list.all(fn(frame) { frame.message_id != spell_go.message_id })
    as "Spell4 1817's own castTime is 0, but the cast waits: no go yet"
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [2000]
    as "Creature2 26462's activateSpellCastTime, 2000, is the go's delay, not Spell4 1817's castTime 0"
}

/// The units each 0x7f4 of the effects names, with the effect infos listed on each.
fn go_targets(
  effects effects: List(Effect),
) -> List(#(Int, List(spell_effect_info.SpellEffectInfo))) {
  list.flat_map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      list.map(go.targets, fn(target) { #(target.unit_id, target.effects) })
    },
  )
}

fn flattened(steps steps: List(#(Int, List(Effect)))) -> List(Effect) {
  list.flat_map(steps, fn(step) { step.1 })
}

/// A creature of one column, spell 1817 behind no prerequisite, with the mollusk's cast time.
fn creature_with(min min: Float, max max: Float) -> activate.Creature {
  Creature(
    columns: [Column(prerequisite_id: 0, spell4_id: 1817)],
    cast_time_ms: 2000,
    min_range: min,
    max_range: max,
    flags: 0,
  )
}

fn with_planned(
  spell4_id spell4_id: Int,
  planned planned: activate.Planned,
) -> activate.Activations {
  let activations = the_activations()
  Activations(
    ..activations,
    spells: dict.insert(activations.spells, spell4_id, planned),
  )
}

pub fn activate_go_raises_activated_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    right_click_mollusk(state: cast.new(), east: 1.0, at: 1000)
  let #(_, steps) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  assert list.map(steps, fn(step) { step.0 }) == [3000]
    as "the go and the finish come at the accept plus Creature2 26462's activateSpellCastTime, 2000"
  let effects = flattened(steps:)
  assert support.ids(frames: support.writes(effects:)) == [0x07F4, 0x07FE]
    as "the go, then the finish"
  assert go_targets(effects:)
    == [
      #(its_unit, [
        SpellEffectInfo(
          spell4_effects_id: 2821,
          instance_id: 1,
          delay_ms: 0,
          field_4: 0,
          result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
        ),
      ]),
    ]
    as "opcode.0x7f4.target_info: the go names the unit with the effect info of Spell4 1817's Activate row, Spell4Effects 2821 (delay 0), never the unit with no effect info"
  assert list.count(effects, fn(effect) {
      effect
      == cast.Activated(
        unit_id: its_unit,
        creature_id: the_mollusk,
        alive_at_press: True,
        by_item: False,
      )
    })
    == 1
    as "the go raises Activated for the unit and its creature, once"
  // A creature whose columns pass nobody casts the default spell, Spell4 8, which is not
  // among its columns, so the creature's cast time is not its time (`0x1407a1680`): the
  // spell's own castTime, 0, is.
  let plain =
    Creature(
      columns: [],
      cast_time_ms: 500,
      min_range: 0.0,
      max_range: 0.0,
      flags: 0,
    )
  let assert Ok(#(state, pressed)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: object(creature: plain, east: 0.5, up: 0.0),
      at: 1000,
    )
    as "Spell4 8 reaches a unit its edge touches"
  let #(_, steps) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  assert steps == []
    as "Spell4 8's castTime is 0: the go is at the accept, and the creature's activateSpellCastTime of 500 does not delay it"
  assert list.map(go_targets(effects: pressed), fn(target) {
      list.map(target.1, fn(info) { info.spell4_effects_id })
    })
    == [[3292]]
    as "Spell4 8's Activate row is Spell4Effects 3292"
}

const a_scanning_crystal = 8047

const the_teleporter = 766

const a_jabbit_cave = 33_885

const a_gated_creature = 46_497

fn creature_of_row(creature_id creature_id: Int) -> activate.Creature {
  let assert Ok(row) =
    creature2.get(tables: fixture_tables.shared(), id: Creature2Id(creature_id))
    as "the creature is a root of the fixture"
  activate.creature_of(row:)
}

/// The right-click of a unit of this creature, `east` of the caster at 1000 ms, and the
/// timers of the cast run from 1000 ms on the clock the test drives: the written effects of
/// the click, and each timer's time (`from_ms` plus its delay) with its effects.
fn used(
  creature creature: activate.Creature,
  creature_id creature_id: Int,
) -> #(List(Effect), List(#(Int, List(Effect)))) {
  let assert Ok(#(state, clicked)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: object_of(
        creature_id:,
        creature:,
        checklist_index: 0,
        link: activate.NoLink,
        east: 1.0,
        up: 0.0,
      ),
      at: 1000,
    )
    as "the right-click is taken"
  let #(_, steps) = support.run_timers(state:, effects: clicked, from_ms: 1000)
  #(clicked, steps)
}

/// The phase of each 0x7f4 the effects write.
fn go_phases(effects effects: List(Effect)) -> List(Int) {
  list.map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      go.phase
    },
  )
}

pub fn an_activate_cast_of_a_channel_stays_a_channel_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 8047: activateSpellCastTime 0, activate spell 5725 (Spell4Base 5020, castMethod
  // 1; castTime 3000, channelInitialDelay 0, channelMaxTime 3000, channelPulseTime 2999).
  // `0x14053d1f0.activate_channel`: an activate cast replaces only the cast's duration and keeps
  // the channel's go count, (3000 - 0 + 2999) / 2999 = 2. `cast.channel_sequence`: the
  // channel's gos come before its finish. The go times are the server's choice: the
  // initial delay plus each pulse time, 0 and 2999 ms.
  let #(clicked, steps) =
    used(
      creature: creature_of_row(creature_id: a_scanning_crystal),
      creature_id: a_scanning_crystal,
    )
  assert support.written_ids(effects: clicked) == [0x07FD, 0x07F4]
    as "the cast is confirmed and its first go, at 0 ms, is sent at once"
  assert go_phases(effects: clicked) == [0]
    as "the go at 0 ms is the channel's first"
  assert list.map(steps, fn(step) { step.0 }) == [3999, 4000]
    as "from the accept at 1000 ms: the second go at 2999 ms and the finish at channelMaxTime 3000 ms"
  assert list.map(steps, fn(step) { support.written_ids(effects: step.1) })
    == [[0x07F4], [0x07FE]]
    as "cast.channel_sequence: the second go is sent before the finish, and nothing else is"
  assert go_phases(effects: flattened(steps:)) == [1]
    as "the go at 2999 ms is the channel's second"
  assert list.count(flattened(steps:), fn(effect) {
      effect
      == cast.Activated(
        unit_id: its_unit,
        creature_id: a_scanning_crystal,
        alive_at_press: True,
        by_item: False,
      )
    })
    == 1
    as "Spell4Effects 10256, the Activate row (delayTime 2999), is applied once, at the last go"
  assert list.contains(
    list.map(go_targets(effects: clicked), fn(target) {
      list.map(target.1, fn(info) { #(info.spell4_effects_id, info.delay_ms) })
    }),
    [#(10_256, 2999)],
  )
    as "opcode.0x7f4.target_info: the first go lists the unit with the Activate row 10256 at its delay of 2999 ms"
  assert list.flat_map(go_targets(effects: flattened(steps:)), fn(target) {
      list.map(target.1, fn(info) { info.spell4_effects_id })
    })
    == []
    as "cast.channel_sequence: the Activate row 10256 has phaseFlags 1, so it belongs to the first go alone: the second go lists no effect"
}

pub fn an_activate_cast_time_of_0_takes_the_spells_cast_time_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 766: activateSpellCastTime 0, activate spell 1783 (Spell4Base castMethod 0;
  // castTime 2000). `0x14054e340`: the cast time is the creature's when that is not 0, else the
  // spell's castTime.
  let #(clicked, steps) =
    used(
      creature: creature_of_row(creature_id: the_teleporter),
      creature_id: the_teleporter,
    )
  assert support.written_ids(effects: clicked) == [0x07FD]
    as "no go at the accept: the cast has a time"
  assert list.map(steps, fn(step) { step.0 }) == [3000]
    as "the go and the finish come at the accept plus Spell4 1783's castTime, 2000 ms"
  assert list.map(steps, fn(step) { support.written_ids(effects: step.1) })
    == [[0x07F4, 0x07FE]]
    as "the go, then the finish"
}

pub fn a_creatures_activate_cast_time_wins_over_the_spells_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14054e340`: a creature's activate cast time that is not 0 is the cast's time, over
  // its spell's castTime. Creature2 33885: activateSpellCastTime 1500, first activate column
  // Spell4 46055 behind no prerequisite, whose castTime is 4000.
  let #(clicked, steps) =
    used(
      creature: creature_of_row(creature_id: a_jabbit_cave),
      creature_id: a_jabbit_cave,
    )
  assert support.written_ids(effects: clicked) == [0x07FD]
    as "no go at the accept"
  assert list.map(steps, fn(step) { step.0 }) == [2500]
    as "the go comes at the accept plus the creature's 1500 ms, not Spell4 46055's 4000 ms"
}

pub fn a_channel_activation_stopped_before_its_last_go_counts_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 8047, Spell4 5725: the Activate row 10256 (delayTime 2999) is applied by the
  // channel's last go, at 3999 ms. What an activation does is the server's
  // (`Spell4Effects.effectType.7`), and a use cancelled before its go counts nothing
  // (`activate_cancelled_raises_nothing_test`): a channel cancelled after its first go and
  // before its last counts nothing either.
  let assert Ok(#(state, clicked)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: object_of(
        creature_id: a_scanning_crystal,
        creature: creature_of_row(creature_id: a_scanning_crystal),
        checklist_index: 0,
        link: activate.NoLink,
        east: 1.0,
        up: 0.0,
      ),
      at: 1000,
    )
    as "the right-click is taken"
  assert go_phases(effects: clicked) == [0]
    as "the first go is sent at the accept"
  let assert Ok(#(state, stopped)) =
    support.cancelled(
      state:,
      cast_id: support.pressed_id(effects: clicked),
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 2000,
    )
    as "opcode.0x801: the client cancels the cast it is playing"
  let #(_, steps) = support.run_timers(state:, effects: clicked, from_ms: 1000)
  let everything = list.append(stopped, flattened(steps:))
  assert !list.contains(
    everything,
    cast.Activated(
      unit_id: its_unit,
      creature_id: a_scanning_crystal,
      alive_at_press: True,
      by_item: False,
    ),
  )
    as "the channel's timers run after the cancel and nothing is activated"
  assert go_phases(effects: everything) == []
    as "no later go is sent for a cancelled cast"
}

pub fn a_creatures_activate_cast_time_does_not_time_the_default_spell_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x1407a1680`, `0x14054e340`: the creature's activateSpellCastTime applies only to a spell
  // among its activate columns. Creature2 46497: activateSpellCastTime 3000, four columns
  // (Spell4 46191, 46202, 46204 and 46203), each behind a Prerequisite (11720, 11718, 11719,
  // 11717) of the base faction 166 and the path 2, which the Dominion caster (base faction
  // 167, path 0) does not meet; so it casts the default spell, Spell4 8 (GameFormula 414,
  // `0x14046c580`), whose castTime is 0. A column with no prerequisite would end the pick
  // at once, so only a creature whose four columns are all gated falls to the default.
  let assert Ok(#(state, clicked)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: object_of(
        creature_id: a_gated_creature,
        creature: creature_of_row(creature_id: a_gated_creature),
        checklist_index: 0,
        link: activate.NoLink,
        east: 0.5,
        up: 0.0,
      ),
      at: 1000,
    )
    as "Spell4 8 reaches a unit its edge touches"
  let #(_, steps) = support.run_timers(state:, effects: clicked, from_ms: 1000)
  let assert [#(_, CastStarted(start: started)), ..] =
    support.tells(effects: clicked)
    as "the cast starts and its viewers are told"
  assert started.spell4_id == 8
    as "no column passes, so the pick is the default spell"
  assert support.written_ids(effects: clicked) == [0x07FD, 0x07F4, 0x07FE]
    as "Spell4 8's castTime is 0: the go and the finish are at the accept"
  assert steps == [] as "no timer waits for the creature's 3000 ms"
}

/// What a right-click of the market terminal (Creature2 34758, a unit of index 5) does
/// for a caster whose quest 7153 holds this progress for its one objective.
fn market_terminal_pressed(progress progress: Int) -> List(Effect) {
  let assert Ok(row) =
    creature2.get(
      tables: fixture_tables.shared(),
      id: Creature2Id(a_market_terminal),
    )
    as "Creature2 34758 is a root of the fixture"
  let caster =
    cast.Caster(
      ..standing(),
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: market_quest, progress: [progress]),
      ]),
    )
  let assert Ok(#(_, effects)) =
    right_click_by(
      caster:,
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: object_of(
        creature_id: a_market_terminal,
        creature: activate.creature_of(row:),
        checklist_index: 5,
        link: activate.NoLink,
        east: 1.0,
        up: 0.0,
      ),
      at: 1000,
    )
    as "a right-click that fits the message is taken"
  effects
}

pub fn activate_pick_reads_the_checklist_bit_of_the_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [#(_, CastStarted(start: started)), ..] =
    support.tells(effects: market_terminal_pressed(progress: 0))
    as "the cast starts and its viewers are told"
  assert started.spell4_id == 38_925
    as "Creature2 34758's first column, Spell4 38925, behind Prerequisite 13244: type 94 comparison 2 of quest 7153's objective 0 passes while the unit's bit is clear"
  assert support.refusal_results(effects: market_terminal_pressed(progress: 32))
    == [cast_result.to_value(cast_result.TargetIsNotUseable)]
    as "bit 5 of the mask is the unit's (its index 5, 0x1406113b0): the condition fails, and the next column, prerequisite 0 with spell 0, wins: no activate spell, result 100 (0x14046c580)"
}

fn range_answer(
  activations activations: activate.Activations,
  creature creature: activate.Creature,
  east east: Float,
  up up: Float,
) -> Result(Nil, Int) {
  let assert Ok(#(_, effects)) =
    right_click(
      state: cast.new(),
      activations:,
      unit_id: its_unit,
      target: object(creature:, east:, up:),
      at: 1000,
    )
  case support.refusal_results(effects:) {
    [] -> Ok(Nil)
    [result] -> Error(result)
    _ -> panic as "at most one refusal"
  }
}

pub fn activate_range_is_edge_to_edge_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = the_activations()
  // The two radii are 0.5 and 0.25, so units 3.75 apart are 3.0 edge to edge.
  assert range_answer(activations:, creature: mollusk(), east: 3.75, up: 0.0)
    == Ok(Nil)
    as "Creature2 26462's activateSpellMaxRange is 3.0: a gap of exactly 3.0 is in range"
  assert range_answer(activations:, creature: mollusk(), east: 3.76, up: 0.0)
    == Error(105)
    as "a gap of 3.01 is TargetRangeMax (105): the creature's 3.0, not Spell4 1817's targetMaxRange 5.0"
  assert range_answer(activations:, creature: mollusk(), east: 0.0, up: 0.0)
    == Ok(Nil)
    as "units inside each other have a gap of 0, never below it"
  assert range_answer(activations:, creature: mollusk(), east: 1.0, up: 10.0)
    == Error(105)
    as "the distance is three dimensional: a unit 10 up is too far whatever its ground distance"
  let minimum = creature_with(min: 1.0, max: 3.0)
  assert range_answer(activations:, creature: minimum, east: 1.25, up: 0.0)
    == Error(104)
    as "a gap of 0.5 under the creature's activateSpellMinRange 1.0 is TargetRangeMin (104)"
  assert range_answer(activations:, creature: minimum, east: 1.75, up: 0.0)
    == Ok(Nil)
    as "a gap of exactly the minimum is in range"
  let assert Ok(Planned(limits:, ..) as planned) =
    activate.planned_of(activations:, spell4_id: 1817)
  let tall =
    with_planned(
      spell4_id: 1817,
      planned: Planned(
        ..planned,
        limits: activate.Limits(..limits, vertical: 2.0),
      ),
    )
  let high = creature_with(min: 0.0, max: 100.0)
  assert range_answer(activations: tall, creature: high, east: 1.0, up: 10.0)
    == Error(183)
    as "a unit above the spell's targetVerticalRange 2.0 (less both radii) is TargetRangeVertical (183)"
  assert range_answer(activations: tall, creature: high, east: 1.0, up: 1.0)
    == Ok(Nil)
    as "a unit within the vertical range is in range"
  assert range_answer(
      activations: tall,
      creature: mollusk(),
      east: 1.0,
      up: 10.0,
    )
    == Error(105)
    as "0x1403b2240 tests the maximum before the height"
  // Spell 8 is no column of this creature: the Spell4 row's limits hold, and its
  // targetMaxRange is 0, so the units' edges must touch.
  let plain =
    Creature(
      columns: [],
      cast_time_ms: 500,
      min_range: 3.0,
      max_range: 3.0,
      flags: 0,
    )
  assert range_answer(activations:, creature: plain, east: 0.75, up: 0.0)
    == Ok(Nil)
    as "Spell4 8's targetMaxRange is 0: edges that touch are in range, whatever the creature's own range says of other spells"
  assert range_answer(activations:, creature: plain, east: 0.76, up: 0.0)
    == Error(105)
    as "a gap of 0.01 is more than Spell4 8's 0"
  // A creature whose own maximum is 0 falls back to its spell's.
  let open = creature_with(min: 0.0, max: 0.0)
  assert range_answer(activations:, creature: open, east: 5.75, up: 0.0)
    == Ok(Nil)
    as "a creature maximum of 0 is Spell4 1817's targetMaxRange 5.0: a gap of 5.0 is in range"
  assert range_answer(activations:, creature: open, east: 5.76, up: 0.0)
    == Error(105)
    as "a gap of 5.01 is out of it"
}

pub fn activate_refuses_a_unit_not_in_the_picture_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refused_with(
      activations: the_activations(),
      target: activate.Unseen,
      unit_id: its_unit,
    )
    == 31
    as "a unit not in the player's picture is CasterMustHaveTarget (31), CastActivateSpell 0x14039c430's own refusal"
}

pub fn activate_refuses_another_players_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  assert refused_with(
      activations: the_activations(),
      target: activate.AnotherPlayer,
      unit_id: its_unit,
    )
    == 91
    as "another player's unit is NoTarget (91), CastActivateSpell 0x14039c430's own refusal"
}

pub fn an_activate_cast_on_a_dead_creature_is_refused_before_its_range_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = the_activations()
  assert refused_with(
      activations:,
      target: mollusk_in_state(east: 10.0, alive: True, withheld: None),
      unit_id: its_unit,
    )
    == cast_result.to_value(cast_result.TargetRangeMax)
    as "the control: a living creature 10.0 away is beyond Spell4 1817's 5.0 (105)"
  assert refused_with(
      activations:,
      target: mollusk_in_state(east: 10.0, alive: False, withheld: None),
      unit_id: its_unit,
    )
    == cast_result.to_value(cast_result.TargetCannotBeDead)
    as "Spell4 1817's target row is Spell4Conditions 15 (bit 0, value 0): 0x1403b2240 gives a dead target 106 (its lines 63-77) before the range result it gives later (105)"
}

pub fn an_activate_cast_whose_spell_allows_the_dead_starts_on_a_dead_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(row) =
    creature2.get(tables: fixture_tables.shared(), id: Creature2Id(5713))
    as "Creature2 5713 is a root of the fixture"
  let creature = activate.creature_of(row:)
  let assert [Column(prerequisite_id: 0, spell4_id: 6772), ..] =
    creature.columns
    as "its first activate spell is Spell4 6772, whose target row is Spell4Conditions 4 (mask 0)"
  let assert Ok(#(_, effects)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: usable_in_state(
        creature_id: 5713,
        creature:,
        checklist_index: 0,
        link: activate.NoLink,
        east: 1.0,
        up: 0.0,
        alive: False,
        withheld: None,
      ),
      at: 1000,
    )
    as "a right-click is answered"
  assert support.refusal_results(effects:) == []
    as "0x1403b2240 tests no death for a target row with mask 0, so a dead creature is a target"
  assert list.length(support.frames_of(
      message_id: spell_cast_confirmed.message_id,
      effects:,
    ))
    == 1
    as "the cast starts: the caster is written the one 0x7fd"
  assert support.writes(effects:)
    |> list.all(fn(frame) { frame.message_id != spell_go.message_id })
    && support.started_timers(effects:) == []
    as "Creature2 5713's activateSpellCastTime and Spell4 6772's castTime are both 0, so the cast has no bar and its go waits for the client's interaction answer, like any activate cast"
}

pub fn an_activate_cast_that_needs_a_dead_target_is_refused_on_a_living_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  // No activate spell has a must-be-dead target; Spell4Conditions 16 (mask 225, value 1)
  // is the client's own must-be-dead row.
  let #(living, dead) =
    fixture_tables.changed(
      table: "Spell4",
      id: 1817,
      with: [#("spell4ConditionsIdTarget", planted_table.Integer(16))],
      body: fn(tables) {
        let activations = activate.activations(tables:)
        #(
          refused_with(
            activations:,
            target: mollusk_in_state(east: 1.0, alive: True, withheld: None),
            unit_id: its_unit,
          ),
          right_click(
            state: cast.new(),
            activations:,
            unit_id: its_unit,
            target: mollusk_in_state(east: 1.0, alive: False, withheld: None),
            at: 1000,
          ),
        )
      },
    )
  assert living == cast_result.to_value(cast_result.TargetMustBeDead)
    as "a living target of a spell whose target row has value bit 0 set is refused with 107 Target_MustBeDead (0x1403b2240 lines 63-77)"
  let assert Ok(#(_, effects)) = dead as "a right-click is answered"
  assert support.refusal_results(effects:) == []
    as "a dead creature is a target of a must-be-dead spell"
}

/// The effects of the press of a creature withheld for this reason, in range.
fn withheld_press(why why: activate.Withheld) -> List(Effect) {
  let assert Ok(#(_, effects)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: mollusk_in_state(east: 1.0, alive: True, withheld: Some(why)),
      at: 1000,
    )
    as "a right-click is answered"
  effects
}

pub fn an_activate_cast_on_a_creature_hostile_to_the_player_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let effects = withheld_press(why: HostileToPlayer)
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.TargetIsNotUseable)]
    as "0x14047a060 skips kinds 26, 39 and 50 when the player's disposition toward the unit is Hostile, so the client sends no 0x97: the answer is the use of nothing, 100"
  assert support.started_timers(effects:) == [] && support.tells(effects:) == []
    as "no cast starts"
  let assert [#(LogWarning, line)] = support.logs(effects:)
    as "the refusal is logged: the client sends no such press"
  assert string.contains(line, "hostile")
}

pub fn an_activate_cast_on_a_creature_in_combat_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let effects = withheld_press(why: InCombat)
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.TargetIsNotUseable)]
    as "0x14047a060 gives a unit in combat (unit word 0x2ac, set only by 0x89a) the kind 0, which has no handler, so the client sends no 0x97: the answer is 100"
  assert support.started_timers(effects:) == [] && support.tells(effects:) == []
    as "no cast starts"
  let assert [#(LogWarning, line)] = support.logs(effects:)
    as "the refusal is logged"
  assert string.contains(line, "combat")
}

pub fn activate_refuses_unknown_and_unbuilt_spells_test() -> Nil {
  use <- owned_test.run(10_000)
  let creature_of_spell = fn(spell4_id) {
    Creature(
      columns: [Column(prerequisite_id: 0, spell4_id:)],
      cast_time_ms: 2000,
      min_range: 0.0,
      max_range: 3.0,
      flags: 0,
    )
  }
  let refused = fn(activations, creature) {
    refused_with(
      activations:,
      target: object(creature:, east: 1.0, up: 0.0),
      unit_id: its_unit,
    )
  }
  assert refused(
      with_planned(spell4_id: 6754, planned: NoSpell4Row),
      creature_of_spell(6754),
    )
    == 4
    as "a spell the Spell4 table has no row for (6754) is SpellUnknown (4)"
  assert refused(the_activations(), creature_of_spell(200_000)) == 4
    as "a spell the plans do not hold is SpellUnknown (4)"
  let assert Ok(Planned(spell:, ..) as planned) =
    activate.planned_of(activations: the_activations(), spell4_id: 1817)
  let interaction =
    with_planned(
      spell4_id: 1817,
      planned: Planned(
        ..planned,
        spell: spell_plan.Spell(..spell, method: spell_plan.Transactional),
      ),
    )
  let assert Ok(#(state, first)) =
    right_click(
      state: cast.new(),
      activations: interaction,
      unit_id: its_unit,
      target: object(creature: mollusk(), east: 1.0, up: 0.0),
      at: 1000,
    )
  assert support.refusal_results(effects: first)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "Spell.CodeEnumCastMethod: a cast method the rule does not build (castMethod 9, transactional) is IllegalSpellCast, as an ability's is"
  assert support.started_timers(effects: first) == []
    && support.tells(effects: first) == []
    as "no cast starts"
  let assert [#(LogWarning, line)] = support.logs(effects: first)
    as "the refusal is logged once"
  assert string.contains(line, "1817")
  let assert Ok(#(_, second)) =
    right_click(
      state:,
      activations: interaction,
      unit_id: its_unit,
      target: object(creature: mollusk(), east: 1.0, up: 0.0),
      at: 1100,
    )
  assert support.logs(effects: second) == []
    && support.refusal_results(effects: second)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "the second right-click is refused the same and not logged again"
  assert refused(
      with_planned(
        spell4_id: 1817,
        planned: CannotBePlanned(why: "the Spell4Effects row 1 is a Stealth"),
      ),
      mollusk(),
    )
    == cast_result.to_value(cast_result.IllegalSpellCast)
    as "a spell the plan cannot build is refused as not built"
  let assert Ok(#(_, struck)) =
    right_click(
      state: cast.new(),
      activations: the_activations(),
      unit_id: its_unit,
      target: object(creature: creature_of_spell(38_392), east: 1.0, up: 0.0),
      at: 1000,
    )
  assert support.refusal_results(effects: struck)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    && support.started_timers(effects: struck) == []
    as "Spell4 38392 (Creature2 19232's spell) has Spell4Effects 82255, a Proxy aimed at the primary target (targetFlags 2): the activate cast strikes no one, so the press is refused as not built, never run with the effect lost"
  let assert [#(LogWarning, struck_line)] = support.logs(effects: struck)
    as "the refusal is logged"
  assert string.contains(struck_line, "82255")
    as "the log names the effect that would be lost"
  // A castMethod 5 spell pressed from the bag has no activated unit to interact with.
  let interaction_spell =
    spell_plan.Spell(
      ..support.unbuilt(),
      method: spell_plan.ClientSideInteraction,
    )
  let #(_, pressed) =
    support.pressed_raw_in(
      plans: support.plans_with(spell: interaction_spell),
      state: cast.new(),
      caster: standing(),
      bag_index: support.unbuilt_bag_index,
      target: 0,
      at: 1000,
    )
  assert support.refusal_results(effects: pressed)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "Spell.CodeEnumCastMethod: a castMethod 5 spell pressed through 0x9a is still refused 285: only an activate cast opens the interaction"
}

/// Condition types below 301 the server does not read, lowest first.
fn unread_types() -> List(Int) {
  int.range(from: 300, to: 0, with: [], run: fn(unread, type_id) {
    case prerequisite.is_read(type_id:) {
      True -> unread
      False -> [type_id, ..unread]
    }
  })
}

/// Activations of two creatures' prerequisites, each of one condition of an unread type.
fn behind_unread_types(
  first first: Int,
  second second: Int,
) -> activate.Activations {
  let activations = the_activations()
  Activations(
    ..activations,
    prerequisites: activations.prerequisites
      |> dict.insert(
        900_001,
        prerequisite_support.single(id: 900_001, condition: #(first, 1, 0, 0)),
      )
      |> dict.insert(
        900_002,
        prerequisite_support.single(id: 900_002, condition: #(second, 1, 0, 0)),
      ),
  )
}

fn behind(prerequisite_id prerequisite_id: Int) -> Target {
  object(
    creature: Creature(
      columns: [Column(prerequisite_id:, spell4_id: 1817)],
      cast_time_ms: 2000,
      min_range: 0.0,
      max_range: 3.0,
      flags: 0,
    ),
    east: 1.0,
    up: 0.0,
  )
}

pub fn activate_logs_each_unread_prerequisite_type_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [first_type, second_type, ..] = unread_types()
    as "the client's Prerequisite types include some the server does not read"
  let activations = behind_unread_types(first: first_type, second: second_type)
  let click = fn(state, target, at) {
    let assert Ok(taken) =
      right_click(state:, activations:, unit_id: its_unit, target:, at:)
    taken
  }
  let #(state, first) =
    click(cast.new(), behind(prerequisite_id: 900_001), 1000)
  assert support.refusal_results(effects: first)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "a creature that activates through a condition the server does not read is refused as not built"
  let assert [#(LogWarning, first_line)] = support.logs(effects: first)
    as "the first type is logged"
  assert string.contains(first_line, "type " <> int.to_string(first_type))
  let #(state, second) = click(state, behind(prerequisite_id: 900_002), 1100)
  let assert [#(LogWarning, second_line)] = support.logs(effects: second)
    as "a different unread type is logged too, not hidden by the first"
  assert string.contains(second_line, "type " <> int.to_string(second_type))
  let #(state, again) = click(state, behind(prerequisite_id: 900_001), 1200)
  assert support.logs(effects: again) == []
    && support.refusal_results(effects: again)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "the first type's second right-click is refused and not logged again"
  let by_spell =
    Activations(
      ..activations,
      spells: dict.insert(
        activations.spells,
        first_type,
        CannotBePlanned(why: "the Spell4Effects row 1 is a Stealth"),
      ),
    )
  let assert Ok(#(_, by_spell_effects)) =
    right_click(
      state:,
      activations: by_spell,
      unit_id: its_unit,
      target: object(
        creature: Creature(
          columns: [Column(prerequisite_id: 0, spell4_id: first_type)],
          cast_time_ms: 2000,
          min_range: 0.0,
          max_range: 3.0,
          flags: 0,
        ),
        east: 1.0,
        up: 0.0,
      ),
      at: 1300,
    )
  assert list.length(support.logs(effects: by_spell_effects)) == 1
    as "a spell whose Spell4 id equals an unread type already logged is still logged: the types and the spell ids are kept apart"
  Nil
}

/// The Creature2 row of the quest collectible whose objective the tests open and close:
/// questAnimStateId 3741, index 0, activate spell 1817 with cast time 2000.
const the_collectible = 12_919

/// A grimvault chef with both link columns: questAnimStateId 9110 with index 5, and
/// prerequisiteIdAnimState 29873 (type 36: quest 9110's objective 5 at progress 1).
const a_chef_with_both_links = 53_445

/// The right-click of the collectible by a caster with this quest log, its link read by
/// the rule that reads it (genesis_prime/game/objective_link `of`).
fn collectible_clicked(quests quests: quest_log.QuestLog) -> List(Effect) {
  clicked(creature_id: the_collectible, quests:)
}

/// The right-click of the creature's static object by a caster with this quest log, its
/// link read by the rule that reads it.
fn clicked(
  creature_id creature_id: Int,
  quests quests: quest_log.QuestLog,
) -> List(Effect) {
  let tables = fixture_tables.shared()
  let caster = cast.Caster(..standing(), quests:)
  let activations = the_activations()
  let assert Ok(row) = creature2.get(tables:, id: Creature2Id(creature_id))
    as "the creature is a root of the fixture"
  let link =
    objective_link.of(
      tables:,
      activations:,
      subject: cast.subject_for_use(
        cast: cast.new(),
        caster:,
        unit_id: its_unit,
        checklist_index: 0,
      ),
      quests:,
      row:,
      checklist_index: 0,
    )
  let assert Ok(#(_, effects)) =
    right_click_by(
      caster:,
      state: cast.new(),
      activations:,
      unit_id: its_unit,
      target: object_of(
        creature_id:,
        creature: activate.creature_of(row:),
        checklist_index: 0,
        link:,
        east: 1.0,
        up: 0.0,
      ),
      at: 1000,
    )
    as "a right-click that fits the message is answered"
  effects
}

pub fn an_activate_cast_on_a_creature_with_no_open_link_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 3741's one objective, 4813, is done: the client's offer of Creature2 12919
  // waits for its objective to be open, and offers nothing at all otherwise.
  let effects =
    collectible_clicked(
      quests: quest_support.log_of(rows: [
        quest_support.active(
          quest_id: 3741,
          state: 2,
          placeholder: 0,
          tracked: False,
          done_mask: 0b1,
          progress: [6],
        ),
      ]),
    )
  assert support.started_timers(effects:) == [] && support.tells(effects:) == []
    as "no cast starts"
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.TargetIsNotUseable)]
    as "the 0x97 is answered as a use of nothing: result 100"
  let assert [#(LogWarning, line)] = support.logs(effects:)
    as "the refusal is logged"
  assert string.contains(line, "closed")
}

pub fn an_activate_cast_on_a_creature_with_an_open_link_starts_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 3741 is Accepted with objective 4813 at 2 of 6.
  let effects =
    collectible_clicked(
      quests: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 3741, progress: [2]),
      ]),
    )
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [2000]
    as "Creature2 12919's activateSpellCastTime, 2000, is the go's delay"
  assert support.refusal_results(effects:) == [] && support.logs(effects:) == []
    as "nothing is refused or logged"
}

pub fn a_closed_quest_anim_link_refuses_a_creature_whose_prerequisite_link_is_open_test() -> Nil {
  use <- owned_test.run(10_000)
  // Quest 9110's objective 5 (18164, flags 3) waits for the objectives before it, so the
  // questAnim link (index 5) is closed; its progress 1 is what Prerequisite 29873 asks
  // for, so the prerequisite link alone would be open. The client closes the link at the
  // questAnim result and never reads the prerequisite (0x14046c4d0).
  let quests =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: 9110, progress: [0, 0, 0, 0, 0, 1]),
    ])
  let effects = clicked(creature_id: a_chef_with_both_links, quests:)
  assert support.started_timers(effects:) == [] && support.tells(effects:) == []
    as "no cast starts"
  let assert [#(LogWarning, line)] = support.logs(effects:)
    as "the refusal is logged"
  assert string.contains(line, "closed")
}

/// The right-click of the tutorial mine (Creature2 73463) by the standing caster, with its
/// link open, at this time and in this state.
fn mine_clicked(state state: State, at ms: Int) -> #(State, List(Effect)) {
  let assert Ok(row) =
    creature2.get(
      tables: fixture_tables.shared(),
      id: Creature2Id(the_tutorial_mine),
    )
    as "Creature2 73463 is a root of the fixture"
  let assert Ok(clicked) =
    right_click(
      state:,
      activations: the_activations(),
      unit_id: its_unit,
      target: object_of(
        creature_id: the_tutorial_mine,
        creature: activate.creature_of(row:),
        checklist_index: 0,
        link: activate.OpenLink,
        east: 1.0,
        up: 0.0,
      ),
      at: ms,
    )
    as "a right-click that fits the message is answered"
  clicked
}

pub fn an_activate_cast_logs_the_ravel_signals_it_drops_once_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4 85452 holds RavelSignal rows 224571 and 224610 aimed at the primary target
  // (targetFlags 2) and a third, 227177, aimed at the caster (targetFlags 1): the activate
  // cast strikes no one, so the two aimed at the target are dropped, and the log names
  // the spell, the effects and the unit.
  let #(state, first) = mine_clicked(state: cast.new(), at: 1000)
  assert support.refusal_results(effects: first) == []
    as "a dropped signal refuses nothing"
  let #(state, first_steps) =
    support.run_timers(state:, effects: first, from_ms: 1000)
  assert list.contains(
    support.ids(frames: support.writes(effects: flattened(steps: first_steps))),
    0x07F4,
  )
    as "the cast goes after the spell's castTime (`0x14054e340`: the creature's activateSpellCastTime is 0)"
  let assert [#(LogWarning, line)] = support.logs(effects: first)
    as "the dropped signals are logged once, as one line"
  assert string.contains(line, "85452") && string.contains(line, "5000")
    as "the line names the spell and the unit"
  assert string.contains(line, "224571") && string.contains(line, "224610")
    as "the line names the two effects aimed at the target"
  assert !string.contains(line, "227177")
    as "the effect aimed at the caster is not dropped"
  let #(state, second) = mine_clicked(state:, at: 60_000)
  let #(_, second_steps) =
    support.run_timers(state:, effects: second, from_ms: 60_000)
  assert list.contains(
    support.ids(frames: support.writes(effects: flattened(steps: second_steps))),
    0x07F4,
  )
    as "the second press goes too"
  assert support.logs(effects: second) == []
    as "the same spell's signals are not logged again"
}

pub fn activate_cancelled_raises_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    right_click_mollusk(state: cast.new(), east: 1.0, at: 1000)
  let id = support.pressed_id(effects: pressed)
  let assert Ok(#(_, effects)) =
    support.cancelled(
      state:,
      cast_id: id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 1500,
    )
    as "opcode.0x801: 6 with the bit 1 is what the client sends for a cast that ends"
  assert support.ids(frames: support.writes(effects:)) == [0x07FE]
    as "the cast ends with its finish and no go"
  assert support.cancelled_timers(effects:) != []
    as "the go's timer is cancelled"
  assert !list.contains(
    effects,
    cast.Activated(
      unit_id: its_unit,
      creature_id: the_mollusk,
      alive_at_press: True,
      by_item: False,
    ),
  )
    as "a cast cancelled before its go raises no Activated"
}

const the_terminal = 73_605

/// Spell4Base 20651 (the terminal's spell's base) plus 1, the word the client's 0x805
/// carries (`opcode.0x805.fields`).
const the_terminals_word = 20_652

/// The Departures Terminal on the client's own rows: no activate cast time.
fn terminal() -> activate.Creature {
  let assert Ok(row) =
    creature2.get(
      tables: fixture_tables.shared(),
      id: Creature2Id(the_terminal),
    )
    as "Creature2 73605 is a root of the fixture"
  activate.creature_of(row:)
}

/// The terminal with an activate cast time of 2000, for the casts that have a time to
/// wait out.
fn timed_terminal() -> activate.Creature {
  Creature(..terminal(), cast_time_ms: 2000)
}

fn terminal_object(creature creature: activate.Creature) -> Target {
  object_of(
    creature_id: the_terminal,
    creature:,
    checklist_index: 0,
    link: activate.NoLink,
    east: 1.0,
    up: 0.0,
  )
}

/// The right-click of the terminal's unit, taken by the rule.
fn click_terminal(
  state state: State,
  creature creature: activate.Creature,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    right_click(
      state:,
      activations: the_activations(),
      unit_id: its_unit,
      target: terminal_object(creature:),
      at: ms,
    )
    as "a 0x97 that fits the message is taken"
  taken
}

/// The client's 0x805 for the cast at the time, taken by the rule.
fn answered(
  state state: State,
  cast_id cast_id: Int,
  result result: InteractionResult,
  word word: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  let assert Ok(body) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id:,
      result:,
      spell4_base_id_plus_one: word,
    ))
    as "the answer fits the message"
  cast.take(
    cast: state,
    message: cast.Answered,
    body:,
    caster: standing(),
    plans: support.plans(),
    now: support.at(ms:),
  )
}

/// The answer, which must be taken, not refused.
fn answered_ok(
  state state: State,
  cast_id cast_id: Int,
  result result: InteractionResult,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    answered(state:, cast_id:, result:, word: the_terminals_word, at: ms)
    as "an answer that names a waiting interaction and its spell is taken"
  taken
}

fn activated_by(effects effects: List(Effect)) -> Int {
  list.count(effects, fn(effect) {
    effect
    == cast.Activated(
      unit_id: its_unit,
      creature_id: the_terminal,
      alive_at_press: True,
      by_item: False,
    )
  })
}

/// The go and the finish of a cast that went, and the activation it raises.
fn assert_went_and_finished(effects effects: List(Effect)) -> Nil {
  assert support.ids(frames: support.writes(effects:)) == [0x07F4, 0x07FE]
    as "the go, then the finish"
  assert go_targets(effects:)
    == [
      #(its_unit, [
        SpellEffectInfo(
          spell4_effects_id: 68_913,
          instance_id: 1,
          delay_ms: 0,
          field_4: 0,
          result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
        ),
      ]),
    ]
    as "opcode.0x7f4.activate: the go names the unit with the effect info of Spell4 34681's Activate row, Spell4Effects 68913 (delay 0)"
  assert list.count(effects, fn(effect) {
      effect
      == cast.Activated(
        unit_id: its_unit,
        creature_id: the_terminal,
        alive_at_press: True,
        by_item: False,
      )
    })
    == 1
    as "the go raises Activated for the unit and its creature, once"
}

/// Nothing was written, nothing raised and no timer started.
fn assert_nothing_happened(effects effects: List(Effect)) -> Nil {
  assert support.writes(effects:) == []
    && support.started_timers(effects:) == []
    && activated_by(effects:) == 0
    as "nothing is written, started or raised"
}

pub fn a_client_side_interaction_activate_cast_starts_and_waits_for_the_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, effects) =
    click_terminal(state: cast.new(), creature: terminal(), at: 1000)
  assert support.ids(frames: support.writes(effects:)) == [0x07FD]
    as "opcode.0x7fd.csi: the caster is written the start, and no go or finish: the client's interaction opens on the 0x7fd and the cast waits for its answer"
  let assert [frame] = support.writes(effects:)
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
  assert confirmed.client_cast_id == clients_cast_id
    && confirmed.primary_target_unit_id == its_unit
    as "opcode.0x97: the confirmation answers the client's cast id and names the unit"
  let assert [#(ConnectionId(2), news_2), #(ConnectionId(3), news_3)] =
    support.tells(effects:)
    as "each viewer is told the start"
  assert news_2 == news_3
  let assert CastStarted(start: started) = news_2
  assert started.spell4_id == 34_681
    && started.field_13 == 1
    && started.caster_unit_id == 7
    && started.primary_target_unit_id == its_unit
    as "the viewers see Spell4 34681 cast by the caster at the unit, with the activate bit (opcode.0x7ff.activate)"
  assert support.started_timers(effects:) == []
    as "Creature2 73605's activateSpellCastTime is 0: no go timer waits"
  let assert Ok(#(_, cancel_effects)) =
    support.cancelled(
      state:,
      cast_id: confirmed.server_cast_id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 60_000,
    )
  assert support.ids(frames: support.writes(effects: cancel_effects))
    == [0x07FE]
    as "a minute later the cast is still live: a cancel ends it with its finish (opcode.0x7fe.csi), and the cast never went"
}

pub fn a_success_answer_sends_the_go_and_the_finish_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  let #(_, effects) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 1200,
    )
  assert_went_and_finished(effects:)
  assert support.finished_ids(support.writes(effects:)) == [id]
    as "the finish names the cast"
}

pub fn a_failed_or_cancelled_answer_fails_the_cast_with_146_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  let fails = fn(result) {
    let #(_, effects) = answered_ok(state:, cast_id: id, result:, at: 1200)
    assert support.ids(frames: support.writes(effects:)) == [0x07F9, 0x07FE]
      as "opcode.0x7fe.csi: the cast fails with 0x7f9 and its finish, and no go"
    let assert [failed_frame, _] = support.writes(effects:)
    let assert Ok(failed) = spell_failed.decode(failed_frame.body)
    assert failed.cast_id == id && cast_result.to_value(failed.result) == 146
      as "Spell.CodeEnumCastResult.146: ClientSideInteractionFail"
    assert activated_by(effects:) == 0
      as "a failed interaction activates nothing"
  }
  fails(interaction_result.Failed)
  fails(interaction_result.CancelledBeforeStart)
}

pub fn a_started_answer_changes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  let #(state, started) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Started,
      at: 1001,
    )
  assert support.writes(effects: started) == []
    && support.started_timers(effects: started) == []
    && activated_by(effects: started) == 0
    as "0x140779a70.once: the client's 3 only says the interaction began: nothing is sent, started or raised"
  let assert [#(LogDebug, text)] = support.logs(effects: started)
    as "the answer 3 is logged at debug"
  assert string.contains(text, "began")
    && string.contains(text, int.to_string(id))
    as "the log names the cast whose interaction began"
  let #(_, effects) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 1500,
    )
  assert_went_and_finished(effects:)
}

pub fn a_timed_interaction_goes_at_its_cast_time_after_an_early_answer_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 0)
  let id = support.pressed_id(effects: pressed)
  let #(state, early) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 500,
    )
  assert_nothing_happened(effects: early)
  let #(_, steps) = support.run_timers(state:, effects: pressed, from_ms: 0)
  assert list.map(steps, fn(step) { step.0 }) == [2000]
    as "opcode.0x7ff.csi_cast_bar: the cast's time is the creature's activateSpellCastTime, 2000"
  assert_went_and_finished(effects: flattened(steps:))
}

pub fn a_timed_interaction_waits_for_the_answer_after_its_cast_time_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 0)
  let id = support.pressed_id(effects: pressed)
  let #(state, steps) = support.run_timers(state:, effects: pressed, from_ms: 0)
  assert list.map(steps, fn(step) { step.0 }) == [2000]
    as "the go's timer fires at the cast time"
  assert_nothing_happened(effects: flattened(steps:))
  let #(_, effects) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 3000,
    )
  assert_went_and_finished(effects:)
}

pub fn a_client_side_interaction_cast_shows_a_cast_bar_only_with_a_cast_time_test() -> Nil {
  use <- owned_test.run(10_000)
  // The cast bar is not in the start's bytes: it makes the cast the caster's current
  // cast, which refuses the caster's next press with 13 (SpellAlreadyCasting) while it
  // has more than the queue window left.
  let next_press_refused_with = fn(creature) {
    let #(state, _) = click_terminal(state: cast.new(), creature:, at: 1000)
    let #(_, effects) =
      support.pressed_raw_in(
        plans: support.plans(),
        state:,
        caster: standing(),
        bag_index: support.electrocute,
        target: 0,
        at: 1500,
      )
    support.refusal_results(effects:)
  }
  assert next_press_refused_with(timed_terminal())
    == [cast_result.to_value(cast_result.SpellAlreadyCasting)]
    as "opcode.0x7ff.csi_cast_bar: an activateSpellCastTime of 2000 shows the cast bar"
  assert next_press_refused_with(terminal()) == []
    as "opcode.0x7ff.csi_cast_bar: Creature2 73605's activateSpellCastTime 0 shows none, so the caster is free to press"
}

pub fn an_answer_for_a_cast_that_is_not_live_is_dropped_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  let assert Ok(#(ended, _)) =
    support.cancelled(
      state:,
      cast_id: id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 1500,
    )
  let dropped = fn(state, cast_id) {
    let assert Ok(#(_, effects)) =
      answered(
        state:,
        cast_id:,
        result: interaction_result.Failed,
        word: the_terminals_word,
        at: 1600,
      )
      as "an answer for a cast that is not live is dropped, never an error"
    assert_nothing_happened(effects:)
    let assert [#(LogDebug, _)] = support.logs(effects:)
      as "the drop is logged at debug"
    Nil
  }
  dropped(ended, id)
  dropped(cast.new(), 12_345)
}

pub fn an_answer_naming_no_waiting_interaction_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(normal, normal_pressed) =
    right_click_mollusk(state: cast.new(), east: 1.0, at: 1000)
  let normal_id = support.pressed_id(effects: normal_pressed)
  assert answered(
      state: normal,
      cast_id: normal_id,
      result: interaction_result.Succeeded,
      word: the_terminals_word,
      at: 1100,
    )
    == Error(cast.NoInteractionWaits(cast_id: normal_id))
    as "opcode.0x805.fields: the client sends 0x805 only for a castMethod 5 cast, and the mollusk's cast is a Normal one"
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  assert answered(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      word: 20_651,
      at: 1100,
    )
    == Error(cast.WrongAnswerSpell(
      cast_id: id,
      sent: 20_651,
      expected: the_terminals_word,
    ))
    as "opcode.0x805.fields: the third field is the cast's Spell4Base id plus 1, 20652 for Spell4Base 20651, not 20651"
  let #(answered_once, _) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 1200,
    )
  assert answered(
      state: answered_once,
      cast_id: id,
      result: interaction_result.Succeeded,
      word: the_terminals_word,
      at: 1300,
    )
    == Error(cast.NoInteractionWaits(cast_id: id))
    as "csi.ends: one interaction sends exactly one of 0, 1 or 2, so a second answer after the 1 names no waiting interaction"
}

pub fn an_answer_result_the_client_never_sends_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  list.each([4, 5, 6, 7], fn(result) {
    assert answered(
        state:,
        cast_id: id,
        result: interaction_result.Other(result),
        word: the_terminals_word,
        at: 1100,
      )
      == Error(cast.UnknownAnswer(result:))
      as "opcode.0x805.fields: the client's results are 0, 1, 2 and 3, and nothing else"
  })
}

pub fn a_cancel_ends_a_waiting_interaction_cast_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  let assert Ok(#(state, effects)) =
    support.cancelled(
      state:,
      cast_id: id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 1500,
    )
  assert support.ids(frames: support.writes(effects:)) == [0x07FE]
    as "opcode.0x801: the cancel ends the cast with its finish and no go"
  assert support.cancelled_timers(effects:) != []
    as "the go's timer is cancelled"
  let assert Ok(#(_, later)) =
    answered(
      state:,
      cast_id: id,
      result: interaction_result.Failed,
      word: the_terminals_word,
      at: 1600,
    )
    as "opcode.0x7fe.csi: the client answers 0 when the finish closes its window, which finds no cast"
  assert_nothing_happened(effects: later)
}

pub fn a_second_activate_while_an_interaction_waits_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 1000)
  let assert Ok(#(_, effects)) =
    right_click(
      state:,
      activations: the_activations(),
      unit_id: its_unit,
      target: terminal_object(creature: timed_terminal()),
      at: 1500,
    )
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.SpellAlreadyCasting)]
    as "cast.no_answer: the waiting cast is the caster's current cast, which refuses the next with 13"
  assert support.started_timers(effects:) == []
    as "the refused right-click starts nothing"
}

pub fn a_second_activate_while_an_untimed_interaction_waits_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: terminal(), at: 1000)
  let id = support.pressed_id(effects: pressed)
  let assert Ok(#(refused_state, effects)) =
    right_click(
      state:,
      activations: the_activations(),
      unit_id: its_unit,
      target: terminal_object(creature: terminal()),
      at: 1500,
    )
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.SpellAlreadyCasting)]
    as "cast.no_answer: an interaction with no cast bar still waits for its answer, and a second right-click is refused 13"
  assert list.length(support.writes(effects:)) == 1
    && support.started_timers(effects:) == []
    as "the refused right-click writes only its refusal and starts nothing"
  let #(_, answer) =
    answered_ok(
      state: refused_state,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 1600,
    )
  assert_went_and_finished(effects: answer)
}

/// The press of Electrocute, a cast with no cast time, as the rule gives it.
fn pressed_electrocute(
  state state: State,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.pressed_raw_in(
    plans: support.plans(),
    state:,
    caster: standing(),
    bag_index: support.electrocute,
    target: 0,
    at: ms,
  )
}

/// A timed interaction with a press held in the last 500 ms of its bar, and the bar run
/// with no answer yet.
fn held_press_after_the_bar() -> #(State, Int) {
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 0)
  let id = support.pressed_id(effects: pressed)
  let #(state, held) = pressed_electrocute(state:, at: 1800)
  assert support.writes(effects: held) == []
    && support.refusal_results(effects: held) == []
    as "cast.press_queue: 200 ms of the bar are left, within the queue window: the press is held"
  let #(state, steps) = support.run_timers(state:, effects: pressed, from_ms: 0)
  assert list.map(steps, fn(step) { step.0 }) == [2000]
    as "the go's timer fires at the bar's end"
  assert_nothing_happened(effects: flattened(steps:))
  #(state, id)
}

pub fn a_held_press_starts_when_the_answer_succeeds_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, id) = held_press_after_the_bar()
  let #(_, effects) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Succeeded,
      at: 2500,
    )
  assert list.take(support.ids(frames: support.writes(effects:)), 3)
    == [0x07F4, 0x07FE, 0x07FD]
    as "the go and the finish end the cast, and the held press starts after them (cast.press_queue)"
}

pub fn a_held_press_starts_when_the_answer_fails_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, id) = held_press_after_the_bar()
  let #(_, effects) =
    answered_ok(
      state:,
      cast_id: id,
      result: interaction_result.Failed,
      at: 2500,
    )
  assert list.take(support.ids(frames: support.writes(effects:)), 3)
    == [0x07F9, 0x07FE, 0x07FD]
    as "the failure and the finish end the cast, and the held press starts after them (cast.press_queue)"
}

pub fn a_press_after_the_bar_while_the_answer_is_out_is_refused_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, pressed) =
    click_terminal(state: cast.new(), creature: timed_terminal(), at: 0)
  let #(state, _) = support.run_timers(state:, effects: pressed, from_ms: 0)
  let #(_, effects) = pressed_electrocute(state:, at: 3000)
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.SpellAlreadyCasting)]
    as "cast.no_answer: the bar has run and the answer is out, so the cast has no end of its own and the press is refused 13, not held"
}
