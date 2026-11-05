//// The cast rule (`genesis_prime/game/cast`) for lasting effects: what a go lists, how
//// a cast lingers and ends its nodes on time, what a type 80 removal and a stack cap
//// take off, and every failure point of the design. The spells are planted
//// (`cast_support.child` with a Fluff or SpellForceRemove row), on a clock the test
//// drives. Expected values come from these places:
//// - `opcode.0x7f4.target_info`, `opcode.0x7f4.instance_count` and
////   `opcode.0x7f4.effect_time`: a go's effect info names the effect row, the
////   instance count of a cast is 1 for one application, and the fourth value 0 leaves
////   the lifetime to the client's own rule (delay plus durationTime).
//// - `cast.target_node_end`: the client ends no buff on time; 0x7fe, 0x811 and 0x813
////   end it, so the server holds the 0x7fe of a cast with a node that has life left
////   and sends the end when the life is over.
//// - `opcode.0x811` and `opcode.0x813`: a cast taken off units, and one stack fewer.
//// - Jim's decision on stacking (`Spell4StackGroup.stackCap` is the cap) for what a cast at the cap
////   takes off, and the server's choices the design names (a death ends a lingering
////   cast; the oldest cast goes first).

import cast_support as support
import genesis_prime/client_connection.{CastFinished}
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/lasting.{LastingRow, Stack}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, Always, ForceRemove, GatedOnCaster, GatedOnTarget,
  Lasting,
}
import genesis_prime/game/spend
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/step.{ConnectionId, LogDebug}
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId, Spell4Id}
import gleam/list
import gleam/option
import owned_test
import prerequisite_support

// ---- the planted spells ----

/// A Fluff effect aimed by `aim`: no delay, `duration_ms` long, or until removed.
fn fluff(
  id id: Int,
  aim aim: spell_plan.Aim,
  duration_ms duration_ms: Int,
  until_removed until_removed: Bool,
) -> spell_plan.Lasting {
  Lasting(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    aim:,
    row: LastingRow(delay_ms: 0, duration_ms:, until_removed:),
    condition: Always,
    tag: spend.always,
  )
}

/// A spell of no cast time and no cooldown, global cooldown kind 3, whose go holds
/// these Fluff effects.
fn buff(
  spell4_id spell4_id: Int,
  base base: Int,
  lasting lasting: List(spell_plan.Lasting),
) -> Spell {
  spell_plan.Spell(..support.child(spell4_id:, base:), lasting:)
}

/// A spell whose go takes the casts of the Spell4 `selector` names off the caster.
fn remover(
  spell4_id spell4_id: Int,
  base base: Int,
  selector selector: lasting.Selector,
  count count: Int,
  condition condition: spell_plan.Condition,
) -> Spell {
  spell_plan.Spell(..support.child(spell4_id:, base:), removes: [
    ForceRemove(
      effect_id: Spell4EffectsId(196_521),
      phase_flags: -1,
      aim: spell_plan.AimsAtCaster,
      selector:,
      count:,
      condition:,
      tag: spend.always,
    ),
  ])
}

// The bag indices of the planted bases: base 1 is bag index 8, base 2 is 10, base 3
// is 11 and base 4 is 20 (`cast_support.abilities`).
const bag_of_base_1 = 8

const bag_of_base_2 = 10

const bag_of_base_3 = 11

fn plans_of(spells: List(Spell)) -> Plans {
  support.with_spells(plans: support.plans(), spells:)
}

fn press(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.pressed_in(
    plans:,
    state:,
    caster: support.caster(),
    bag_index: bag,
    target: 0,
    at: ms,
  )
}

/// A press whose go strikes these units.
fn press_striking(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  struck struck: List(cast.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index: bag,
      target: 0,
      at: ms,
    )
  support.answered_by(state:, effects:, at: ms, struck:)
}

fn written_ids(effects effects: List(Effect)) -> List(Int) {
  support.ids(frames: support.writes(effects:))
}

/// The cast id of the first press the effects confirm: the server's id in its 0x7fd.
fn started_id(effects effects: List(Effect)) -> Int {
  let assert [frame, ..] =
    support.frames_of(message_id: spell_cast_confirmed.message_id, effects:)
    as "a press was confirmed"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
    as "a 0x7fd the rule wrote decodes"
  confirmed.server_cast_id
}

// ---- what a go lists ----

pub fn a_go_lists_a_fluff_effect_on_the_caster_with_count_1_and_no_lifetime_test() -> Nil {
  use <- owned_test.run(5000)
  // Power Charge's Fluff 96819 aims at the caster and lasts until removed.
  let plans =
    plans_of([
      buff(spell4_id: 42_569, base: 3, lasting: [
        fluff(
          id: 96_819,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 0,
          until_removed: True,
        ),
      ]),
    ])
  let #(_, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 7 as "the caster is the unit the row aims at"
  assert info.instance_count == 1
    as "one application is a count of 1 (opcode.0x7f4.instance_count)"
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 96_819,
        instance_id: 1,
        delay_ms: 0,
        field_4: 0,
        result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
      ),
    ]
    as "the fourth value 0 leaves the lifetime to the client (opcode.0x7f4.effect_time)"
}

pub fn a_struck_unit_keeps_its_damage_info_and_an_aimed_unit_that_was_not_struck_gets_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 3000,
          until_removed: False,
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          duration_ms: 3000,
          until_removed: False,
        ),
      ]),
    ])
  let #(_, effects) =
    press_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: [cast.Hit(unit_id: 20, descriptions: [])],
      at: 1000,
    )
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  assert list.map(decoded.targets, fn(info) {
      #(
        info.unit_id,
        list.map(info.effects, fn(effect) { effect.spell4_effects_id }),
      )
    })
    == [#(20, [2]), #(7, [1])]
    as "the struck unit first with the area's effect, then the caster the round did not strike"
}

pub fn a_spell_with_no_lasting_effect_finishes_after_its_last_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    press(
      plans: plans_of([buff(spell4_id: 101, base: 3, lasting: [])]),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.length(support.finished_ids(support.writes(effects:))) == 1
}

// ---- a cast that lingers ----

fn eight_seconds_on_the_caster() -> Plans {
  plans_of([
    buff(spell4_id: 77_116, base: 3, lasting: [
      fluff(
        id: 200_468,
        aim: spell_plan.AimsAtCaster,
        duration_ms: 8000,
        until_removed: False,
      ),
    ]),
  ])
}

pub fn a_cast_with_a_node_that_has_life_left_sends_no_finish_after_its_last_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    press(
      plans: eight_seconds_on_the_caster(),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.finished_ids(support.writes(effects:)) == []
    as "the client ends no buff on time, so the 0x7fe waits (cast.target_node_end)"
  assert list.contains(support.tells(effects:), #(
      ConnectionId(2),
      CastFinished(cast_id: started_id(effects:)),
    ))
    == False
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [8000]
    as "one timer at the node's end, 8 s from the go (Mental Overflow 200468)"
}

pub fn the_finish_and_the_audiences_news_come_when_the_life_is_over_and_not_before_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    press(
      plans: eight_seconds_on_the_caster(),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = started_id(effects:)
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, early) = support.fired(state:, timer:, at: 8999)
  assert support.writes(effects: early) == []
    as "a timer that fires with life left writes nothing"
  let assert [#(timer, 1)] = support.started_timers(effects: early)
  let #(_, ended) = support.fired(state:, timer:, at: 9000)
  assert support.finished_ids(support.writes(effects: ended)) == [id]
  assert support.tells(effects: ended)
    == [
      #(ConnectionId(2), CastFinished(cast_id: id)),
      #(ConnectionId(3), CastFinished(cast_id: id)),
    ]
}

pub fn nodes_ending_at_two_times_end_with_a_0x811_and_then_the_finish_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 3000,
          until_removed: False,
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          duration_ms: 8000,
          until_removed: False,
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: [cast.Hit(unit_id: 20, descriptions: [])],
      at: 1000,
    )
  let id = started_id(effects:)
  assert support.finished_ids(support.writes(effects:)) == []
  let assert [#(first, 3000)] = support.started_timers(effects:)
  let #(state, at_3000) = support.fired(state:, timer: first, at: 4000)
  assert support.removed_targets(support.writes(effects: at_3000))
    == [#(id, [7])]
    as "the caster's node ends first: 0x811 naming its unit"
  assert support.finished_ids(support.writes(effects: at_3000)) == []
  let assert [#(second, 5000)] = support.started_timers(effects: at_3000)
  let #(_, at_9000) = support.fired(state:, timer: second, at: 9000)
  assert support.finished_ids(support.writes(effects: at_9000)) == [id]
  assert support.removed_targets(support.writes(effects: at_9000)) == []
}

pub fn two_nodes_ending_at_the_same_time_are_one_0x811_naming_both_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 3000,
          until_removed: False,
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          duration_ms: 3000,
          until_removed: False,
        ),
        fluff(
          id: 3,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 0,
          until_removed: True,
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: [
        cast.Hit(unit_id: 20, descriptions: []),
        cast.Hit(unit_id: 21, descriptions: []),
      ],
      at: 1000,
    )
  let id = started_id(effects:)
  let assert [#(timer, 3000)] = support.started_timers(effects:)
  let #(_, ended) = support.fired(state:, timer:, at: 4000)
  assert support.removed_targets(support.writes(effects: ended))
    == [#(id, [20, 21])]
    as "the two struck units end together: one 0x811; the caster's node lasts until removed"
  assert support.finished_ids(support.writes(effects: ended)) == []
}

pub fn a_node_until_removed_arms_no_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 42_569, base: 3, lasting: [
        fluff(
          id: 96_819,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 0,
          until_removed: True,
        ),
      ]),
    ])
  let #(_, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert support.finished_ids(support.writes(effects:)) == []
  assert support.started_timers(effects:) == []
}

// ---- a type 80 removal ----

pub fn a_removal_takes_the_casts_of_a_spell_off_and_a_later_timer_finds_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 5000,
          until_removed: False,
        ),
      ]),
      remover(
        spell4_id: 301,
        base: 1,
        selector: lasting.Spell(Spell4Id(101)),
        count: 1,
        condition: Always,
      ),
    ])
  let #(state, first) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = started_id(effects: first)
  let assert [#(timer, 5000)] = support.started_timers(effects: first)
  let #(state, removal) = press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert support.removed_targets(support.writes(effects: removal))
    == [#(id, [7])]
    as "the cast holds one node, on the caster: the whole count goes with a 0x811"
  assert list.contains(
      support.finished_ids(support.writes(effects: removal)),
      id,
    )
    == False
    as "a Normal cast the client destroys itself when its last node goes: only the 0x811 (opcode.0x811)"
  let #(_, late) = support.fired(state:, timer:, at: 6000)
  assert support.writes(effects: late) == []
    as "the timer finds no cast: no frame"
  assert support.tells(effects: late) == []
}

pub fn a_removal_takes_the_older_of_two_casts_whole_and_leaves_the_newer_test() -> Nil {
  use <- owned_test.run(5000)
  // A node's count is 1 per application, so two casts hold 1 each, and a count of 1
  // over them takes the older one's whole node and none of the newer one's.
  let plans =
    plans_of([
      stacked(spell4_id: 101, base: 3, group: 7, cap: 5),
      remover(
        spell4_id: 301,
        base: 1,
        selector: lasting.Spell(Spell4Id(101)),
        count: 1,
        condition: Always,
      ),
    ])
  let #(state, first) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(state, second) = press(plans:, state:, bag: bag_of_base_3, at: 1100)
  let #(_, removal) = press(plans:, state:, bag: bag_of_base_1, at: 1200)
  assert support.removed_targets(support.writes(effects: removal))
    == [#(started_id(effects: first), [7])]
    as "count 1 takes the older cast's whole node"
  assert support.removed_stacks(support.writes(effects: removal)) == []
  assert started_id(effects: second) != started_id(effects: first)
}

pub fn a_removal_that_a_gate_stops_takes_nothing_off_until_the_gate_passes_test() -> Nil {
  use <- owned_test.run(5000)
  // Quick Draw's removal 196521: it runs only behind prerequisite 17302, type 15 of
  // 43500, the caster under Quick Draw's marker.
  let gate =
    prerequisite.of_row(
      row: prerequisite_support.row(id: 17_302, flags: 0, conditions: [
        #(15, 1, 0, 43_500),
      ]),
    )
  let plans =
    plans_of([
      buff(spell4_id: 43_500, base: 3, lasting: [
        fluff(
          id: 99_472,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 990,
          until_removed: False,
        ),
      ]),
      remover(
        spell4_id: 43_468,
        base: 1,
        selector: lasting.Spell(Spell4Id(43_500)),
        count: 1,
        condition: GatedOnCaster(gates: [gate]),
      ),
    ])
  let #(state, without) =
    press(plans:, state: cast.new(), bag: bag_of_base_1, at: 1000)
  assert support.removed_targets(support.writes(effects: without)) == []
    as "the caster is under no 43500: the gate fails"
  let #(state, marker) = press(plans:, state:, bag: bag_of_base_3, at: 1100)
  let #(_, with) = press(plans:, state:, bag: bag_of_base_1, at: 1200)
  assert support.removed_targets(support.writes(effects: with))
    == [#(started_id(effects: marker), [7])]
    as "with the marker held, the removal takes it off"
}

pub fn a_removal_behind_a_target_prerequisite_is_not_applied_with_a_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 0,
          until_removed: True,
        ),
      ]),
      remover(
        spell4_id: 301,
        base: 1,
        selector: lasting.Spell(Spell4Id(101)),
        count: 1,
        condition: GatedOnTarget(prerequisite_id: PrerequisiteId(5)),
      ),
    ])
  let #(state, _) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(_, removal) = press(plans:, state:, bag: bag_of_base_1, at: 1100)
  assert support.removed_targets(support.writes(effects: removal)) == []
  assert list.any(support.logs(effects: removal), fn(line) {
    line.0 == LogDebug
    && line.1
    == "the SpellForceRemove effect 196521 applies only behind target prerequisite 5, which is not checked, so it is not applied"
  })
}

// ---- stacking ----

fn stacked(
  spell4_id spell4_id: Int,
  base base: Int,
  group group: Int,
  cap cap: Int,
) -> Spell {
  spell_plan.Spell(
    ..buff(spell4_id:, base:, lasting: [
      fluff(
        id: spell4_id,
        aim: spell_plan.AimsAtCaster,
        duration_ms: 0,
        until_removed: True,
      ),
    ]),
    stack: Stack(group_id: group, cap:),
  )
}

pub fn a_third_copy_of_a_cap_2_group_takes_the_casters_oldest_off_test() -> Nil {
  use <- owned_test.run(5000)
  // Power Charge 42569 is in stack group 1450, cap 2 (Spell4StackGroup).
  let plans =
    plans_of([stacked(spell4_id: 42_569, base: 3, group: 1450, cap: 2)])
  let #(state, first) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(state, second) = press(plans:, state:, bag: bag_of_base_3, at: 1100)
  assert support.removed_targets(support.writes(effects: second)) == []
    as "two casts are within the cap"
  let #(state, third) = press(plans:, state:, bag: bag_of_base_3, at: 1200)
  assert support.removed_targets(support.writes(effects: third))
    == [#(started_id(effects: first), [7])]
    as "the third takes the oldest off the caster"
  let #(_, fourth) = press(plans:, state:, bag: bag_of_base_3, at: 1300)
  assert support.removed_targets(support.writes(effects: fourth))
    == [#(started_id(effects: second), [7])]
    as "and the fourth takes the next oldest: two stay"
}

pub fn a_second_cast_of_a_cap_0_spell_takes_the_first_one_off_and_another_spell_stays_test() -> Nil {
  use <- owned_test.run(5000)
  // Charged Shot 34718 is in group 2, cap 0: one cast per spell.
  let plans =
    plans_of([
      stacked(spell4_id: 34_718, base: 3, group: 2, cap: 0),
      stacked(spell4_id: 99, base: 2, group: 2, cap: 0),
    ])
  let #(state, first) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(state, other) = press(plans:, state:, bag: bag_of_base_2, at: 1100)
  assert support.removed_targets(support.writes(effects: other)) == []
    as "a cast of another spell of the group stays"
  let #(_, again) = press(plans:, state:, bag: bag_of_base_3, at: 1200)
  assert support.removed_targets(support.writes(effects: again))
    == [#(started_id(effects: first), [7])]
    as "the second Charged Shot takes the first one's marker off"
}

// ---- the caster, and the units in sight ----

pub fn the_caster_dying_finishes_a_lingering_cast_with_its_0x7fe_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    press(
      plans: eight_seconds_on_the_caster(),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = started_id(effects:)
  let #(_, ended) = cast.died(cast: state, now: support.at(ms: 2000))
  assert support.finished_ids(support.writes(effects: ended)) == [id]
    as "the server's choice: the client has no path that ends a buff on a unit's death (cast.target_node_end)"
  assert support.tells(effects: ended)
    == [
      #(ConnectionId(2), CastFinished(cast_id: id)),
      #(ConnectionId(3), CastFinished(cast_id: id)),
    ]
}

pub fn a_caster_that_leaves_writes_nothing_for_its_lingering_casts_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    press(
      plans: eight_seconds_on_the_caster(),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, left) = cast.left(cast: state)
  assert support.writes(effects: left) == []
  assert support.cancelled_timers(effects: left) == [timer]
  let #(_, late) = support.fired(state:, timer:, at: 9000)
  assert support.writes(effects: late) == []
}

pub fn a_nodes_unit_leaving_sight_ends_a_lingering_cast_left_with_no_node_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtArea,
          duration_ms: 8000,
          until_removed: False,
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: [cast.Hit(unit_id: 20, descriptions: [])],
      at: 1000,
    )
  let id = started_id(effects:)
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, other) =
    cast.unit_removed(cast: state, unit_id: 21, now_ms: 2000)
  assert support.writes(effects: other) == []
    as "a unit that holds no node of the cast changes nothing"
  let #(state, removed) =
    cast.unit_removed(cast: state, unit_id: 20, now_ms: 3000)
  assert support.finished_ids(support.writes(effects: removed)) == [id]
    as "the client dropped the node with the unit's 0x355; the cast ends and frees its id"
  assert support.removed_targets(support.writes(effects: removed)) == []
    as "no 0x811: the client has the node gone already"
  assert support.cancelled_timers(effects: removed) == [timer]
  let #(_, late) = support.fired(state:, timer:, at: 9000)
  assert support.writes(effects: late) == []
}

pub fn a_node_removed_with_its_unit_leaves_the_casts_other_nodes_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          duration_ms: 0,
          until_removed: True,
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          duration_ms: 8000,
          until_removed: False,
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: [cast.Hit(unit_id: 20, descriptions: [])],
      at: 1000,
    )
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(_, removed) = cast.unit_removed(cast: state, unit_id: 20, now_ms: 3000)
  assert support.finished_ids(support.writes(effects: removed)) == []
    as "the caster's node stays until removed"
  assert support.cancelled_timers(effects: removed) == [timer]
    as "the timer for the ended node is cancelled; no other node ends by time"
  assert support.started_timers(effects: removed) == []
}

// ---- a spell that channels and holds its own lasting effect ----

/// A planted Channeled spell on bag index 11 with the pulses at `initial_delay_ms`
/// plus each `pulse_time_ms` up to `max_time_ms`, a cast bar and a cooldown of 5000,
/// whose go holds these Fluff effects.
fn channel(
  lasting lasting: List(spell_plan.Lasting),
  channel channel: spell_plan.Channel,
) -> Spell {
  spell_plan.Spell(
    ..buff(spell4_id: 101, base: 3, lasting:),
    method: spell_plan.Channeled,
    channel: option.Some(channel),
    cast_bar: spell_plan.ShowsCastBar,
    cooldown_ms: 5000,
    cooldown_start: spell_plan.NotAtAGo,
  )
}

fn refusal_results(
  effects effects: List(Effect),
) -> List(cast_result.CastResult) {
  list.map(
    support.frames_of(message_id: spell_cast_refused.message_id, effects:),
    fn(frame) {
      let assert Ok(refused) = spell_cast_refused.decode(frame.body)
        as "a 0x7fc the rule wrote decodes"
      refused.result
    },
  )
}

pub fn a_channel_that_holds_its_own_fluff_ends_its_other_steps_when_it_lingers_test() -> Nil {
  use <- owned_test.run(5000)
  // Pulses at 0 and 1000 after the press at 1000 and a channelMaxTime of 1500: the
  // channel ends at 2500, its last go at 2000 gives an 8 s node that ends at 10000.
  let plans =
    plans_of([
      channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            duration_ms: 8000,
            until_removed: False,
          ),
        ],
        channel: spell_plan.Channel(
          initial_delay_ms: 0,
          max_time_ms: 1500,
          pulse_time_ms: 1000,
        ),
      ),
    ])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(_, timers) = support.run_timers(state:, effects:, from_ms: 1000)
  let assert Ok(#(last_due, last)) = list.last(timers)
  assert last_due == 2000 + 8000
    as "the last timer is the lingering cast's end, 8 s after the last pulse"
  assert list.flat_map(timers, fn(fired) {
      support.finished_ids(support.writes(effects: fired.1))
    })
    |> list.length
    == 1
    as "one 0x7fe, at the node's end"
  assert support.finished_ids(support.writes(effects: last)) != []
  // Stop at the channel's end, 2500: the caster is free to press another ability
  // (no 13) and the channel's own cooldown, started then, runs.
  let #(state, _) =
    support.run_timers_until(state:, effects:, from_ms: 1000, until_ms: 2500)
  let #(_, free) = press(plans:, state:, bag: bag_of_base_2, at: 2500)
  assert list.contains(written_ids(effects: free), 0x07FD)
    as "the current cast is clear while the buff lingers"
  let #(_, refused) = press(plans:, state:, bag: bag_of_base_3, at: 2500)
  assert refusal_results(effects: refused) == [cast_result.SpellCooldown]
    as "the cooldown started when the cast lingered, at 2500 (0x14053e1b0)"
  // At 8000 the cooldown (5000 from 2500) has ended while the buff still lingers: a
  // cooldown that started at the 0x7fe, at 10000, would still refuse.
  let #(_, again) = press(plans:, state:, bag: bag_of_base_3, at: 8000)
  assert refusal_results(effects: again) == []
    as "the press is taken: the cooldown ran from the linger, not from the 0x7fe"
}

// ---- the round of fixes: nodes of a live cast, a cancel, a later go ----

/// A channel that pulses at 0, 3000 and 6000 after the press (no finish timer of its
/// own) whose each go gives the caster a Fluff of 1000 ms.
fn short_buff_on_a_long_channel() -> Plans {
  plans_of([
    spell_plan.Spell(
      ..channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            duration_ms: 1000,
            until_removed: False,
          ),
        ],
        channel: spell_plan.Channel(
          initial_delay_ms: 0,
          max_time_ms: 6000,
          pulse_time_ms: 3000,
        ),
      ),
      cast_bar: spell_plan.HidesCastBar,
    ),
  ])
}

pub fn a_node_whose_life_ends_while_its_cast_is_live_is_ended_and_the_cast_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = short_buff_on_a_long_channel()
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = started_id(effects:)
  let #(_, timers) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.map(timers, fn(fired) {
      #(
        fired.0,
        support.removed_targets(support.writes(effects: fired.1)),
        support.finished_ids(support.writes(effects: fired.1)),
      )
    })
    == [
      #(2000, [#(id, [7])], []),
      #(4000, [], []),
      #(5000, [#(id, [7])], []),
      #(7000, [], []),
      #(8000, [], [id]),
    ]
    as "each 1 s node ends with a 0x811 while the channel goes on; the last go lingers and its end is the 0x7fe (cast.target_node_end)"
}

pub fn a_node_ended_by_time_is_no_longer_held_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.with_spells(plans: short_buff_on_a_long_channel(), spells: [
      remover(
        spell4_id: 301,
        base: 1,
        selector: lasting.Spell(Spell4Id(101)),
        count: 1,
        condition: Always,
      ),
    ])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(state, _) =
    support.run_timers_until(state:, effects:, from_ms: 1000, until_ms: 2000)
  let #(_, removal) = press(plans:, state:, bag: bag_of_base_1, at: 2100)
  assert support.removed_targets(support.writes(effects: removal)) == []
    as "the node ended at 2000: a removal finds nothing on the caster"
}

pub fn a_cancel_of_a_cast_holding_nodes_lets_them_linger_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            duration_ms: 8000,
            until_removed: False,
          ),
        ],
        channel: spell_plan.Channel(
          initial_delay_ms: 0,
          max_time_ms: 6000,
          pulse_time_ms: 3000,
        ),
      ),
    ])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = started_id(effects:)
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans:,
      state:,
      cast_id: id,
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 2000,
    )
  assert support.finished_ids(support.writes(effects: cancelled)) == []
    as "the cancel stops the channel but ends no buff: the 0x7fe waits for the node (cast.target_node_end)"
  assert list.length(support.cancelled_timers(effects: cancelled)) >= 1
    as "the pending go is cancelled"
  let assert [#(timer, 7000)] = support.started_timers(effects: cancelled)
  let #(_, ended) = support.fired(state:, timer:, at: 9000)
  assert support.finished_ids(support.writes(effects: ended)) == [id]
    as "the node of the go at 1000 ends at 9000: the 0x7fe"
}

pub fn a_later_go_that_lists_a_unit_with_no_life_replaces_its_node_test() -> Nil {
  use <- owned_test.run(5000)
  // Phase 0's Fluff lasts until removed, phase 1's has no life: the second go sets the
  // node again with its own life (opcode.0x7f4.instance_count), so no node is left and
  // the cast ends with its last go instead of lingering for good.
  let plans =
    plans_of([
      channel(
        lasting: [
          spell_plan.Lasting(
            ..fluff(
              id: 1,
              aim: spell_plan.AimsAtCaster,
              duration_ms: 0,
              until_removed: True,
            ),
            phase_flags: 1,
          ),
          spell_plan.Lasting(
            ..fluff(
              id: 2,
              aim: spell_plan.AimsAtCaster,
              duration_ms: 0,
              until_removed: False,
            ),
            phase_flags: 2,
          ),
        ],
        channel: spell_plan.Channel(
          initial_delay_ms: 0,
          max_time_ms: 1000,
          pulse_time_ms: 1000,
        ),
      ),
    ])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = started_id(effects:)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the first go leaves an until-removed node"
  let #(_, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  let assert [#(2000, last)] = steps
  assert support.finished_ids(support.writes(effects: last)) == [id]
    as "the last go lists the caster with no life: the old node is replaced, so the cast finishes"
}
