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

import cast_support as support
import fixture_tables
import genesis_prime/client_connection.{CastStarted}
import genesis_prime/game/activate.{
  type Target, Activations, Body, CannotBePlanned, Column, Creature, NoSpell4Row,
  Object, Planned,
}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/step.{ConnectionId, LogWarning}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
import place_support
import prerequisite_support

const the_mollusk = 26_462

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
  Object(
    creature_id: the_mollusk,
    creature:,
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
  let assert Ok(body) =
    cast_activate.encode(CastActivate(
      client_cast_id: clients_cast_id,
      target_unit_id: unit_id,
    ))
    as "the message fits"
  cast.activate(
    cast: state,
    body:,
    caster: standing(),
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
      effect == cast.Activated(unit_id: its_unit, creature_id: the_mollusk)
    })
    == 1
    as "the go raises Activated for the unit and its creature, once"
  // A creature whose columns pass nobody casts the default spell, Spell4 8.
  let plain =
    Creature(columns: [], cast_time_ms: 500, min_range: 0.0, max_range: 0.0)
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
  assert list.map(steps, fn(step) { step.0 }) == [1500]
    as "this creature's activateSpellCastTime is 500"
  assert list.map(go_targets(effects: flattened(steps:)), fn(target) {
      list.map(target.1, fn(info) { info.spell4_effects_id })
    })
    == [[3292]]
    as "Spell4 8's Activate row is Spell4Effects 3292"
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
  let assert Ok(Planned(spell:, effects:, limits:)) =
    activate.planned_of(activations:, spell4_id: 1817)
  let tall =
    with_planned(
      spell4_id: 1817,
      planned: Planned(
        spell:,
        effects:,
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
    Creature(columns: [], cast_time_ms: 500, min_range: 3.0, max_range: 3.0)
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

pub fn activate_refuses_a_unit_it_cannot_activate_test() -> Nil {
  use <- owned_test.run(10_000)
  let activations = the_activations()
  assert refused_with(activations:, target: activate.Unseen, unit_id: its_unit)
    == 31
    as "a unit not in the player's picture is CasterMustHaveTarget (31)"
  assert refused_with(
      activations:,
      target: activate.AnotherPlayer,
      unit_id: its_unit,
    )
    == 91
    as "another player's unit is NoTarget (91)"
}

pub fn activate_refuses_unknown_and_unbuilt_spells_test() -> Nil {
  use <- owned_test.run(10_000)
  let creature_of_spell = fn(spell4_id) {
    Creature(
      columns: [Column(prerequisite_id: 0, spell4_id:)],
      cast_time_ms: 2000,
      min_range: 0.0,
      max_range: 3.0,
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
  let assert Ok(Planned(spell:, effects:, limits:)) =
    activate.planned_of(activations: the_activations(), spell4_id: 1817)
  let interaction =
    with_planned(
      spell4_id: 1817,
      planned: Planned(
        spell: spell_plan.Spell(
          ..spell,
          method: spell_plan.ClientSideInteraction,
        ),
        effects:,
        limits:,
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
    as "a cast method the rule does not build (castMethod 5, client side interaction) is IllegalSpellCast, as an ability's is"
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
    cast.Activated(unit_id: its_unit, creature_id: the_mollusk),
  )
    as "a cast cancelled before its go raises no Activated"
}
