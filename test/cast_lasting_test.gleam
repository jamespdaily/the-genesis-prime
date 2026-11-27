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
import fixture_tables
import genesis_prime/game/area
import genesis_prime/game/cast
import genesis_prime/game/cast/creature_view
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/crowd_control
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/lasting.{LastingRow, LifeOnly, Listed, Stack}
import genesis_prime/game/lasts
import genesis_prime/game/spell_area
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, Always, GatedOnCaster, GatedOnTarget, Lasting,
}
import genesis_prime/game/spend
import genesis_prime/game/ticking
import genesis_prime/game/unit_casts
import genesis_prime/game/unit_news.{type News, CastFinished, CastTargetsRemoved}
import genesis_prime/message/cast_result
import genesis_prime/message/crowd_control_state.{AbilityRestriction}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed.{
  type SpellTargetsRemoved, SpellTargetsRemoved,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import owned_test
import prerequisite_support
import qcheck

// ---- the planted spells ----

/// A Fluff effect aimed by `aim`: no delay, lasting as `lasts` says.
fn fluff(
  id id: Int,
  aim aim: spell_plan.Aim,
  lasts lasts: lasts.Lasts,
) -> spell_plan.Lasting {
  Lasting(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    aim:,
    row: LastingRow(delay_ms: 0, lasts:),
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
  support.with_effects(
    spell: support.child(spell4_id:, base:),
    kinds: list.map(lasting, spell_plan.LastingEffect),
  )
}

/// A spell whose go takes the casts of the Spell4 `selector` names off the caster.
fn remover(
  spell4_id spell4_id: Int,
  base base: Int,
  selector selector: lasting.Selector,
  count count: Int,
  condition condition: spell_plan.Condition,
) -> Spell {
  support.removing(
    spell4_id:,
    base:,
    effect_id: 196_521,
    selector:,
    count:,
    condition:,
  )
}

// The bag indices of the planted bases: base 1 is bag index 8, base 2 is 10, base 3
// is 11 and base 4 is 20 (`cast_support.abilities`).
const bag_of_base_1 = 8

const bag_of_base_2 = 10

const bag_of_base_3 = 11

/// A press whose go strikes these units.
fn press_striking(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  struck struck: List(cast_state.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  support.pressed_striking_in(plans:, state:, bag_index: bag, struck:, at: ms)
}

// ---- what a go lists ----

pub fn a_go_lists_a_fluff_effect_on_the_caster_with_count_1_and_no_lifetime_test() -> Nil {
  use <- owned_test.run(5000)
  // Power Charge's Fluff 96819 aims at the caster and lasts until removed.
  let plans =
    support.plans_of([
      buff(spell4_id: 42_569, base: 3, lasting: [
        fluff(
          id: 96_819,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.UntilRemoved,
        ),
      ]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
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
        lifetime_ms: 0,
        result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
      ),
    ]
    as "the fourth value 0 leaves the lifetime to the client (opcode.0x7f4.effect_time)"
}

pub fn a_struck_unit_keeps_its_damage_info_and_an_aimed_unit_that_was_not_struck_gets_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.For(duration_ms: 3000),
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          lasts: lasts.For(duration_ms: 3000),
        ),
      ]),
    ])
  let #(_, effects) =
    press_striking(
      plans:,
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        cast_state.Hit(
          unit_id: 20,
          unit: cast_state.HitCreature(life: 1),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ],
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
    support.press(
      plans: support.plans_of([buff(spell4_id: 101, base: 3, lasting: [])]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.length(support.finished_ids(support.writes(effects:))) == 1
}

// ---- a cast that lingers ----

fn eight_seconds_on_the_caster() -> Plans {
  support.plans_of([
    buff(spell4_id: 77_116, base: 3, lasting: [
      fluff(
        id: 200_468,
        aim: spell_plan.AimsAtCaster,
        lasts: lasts.For(duration_ms: 8000),
      ),
    ]),
  ])
}

pub fn a_cast_with_a_node_that_has_life_left_sends_no_finish_after_its_last_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    support.press(
      plans: eight_seconds_on_the_caster(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.finished_ids(support.writes(effects:)) == []
    as "the client ends no buff on time, so the 0x7fe waits (cast.target_node_end)"
  assert list.contains(
      support.tells(effects:),
      CastFinished(cast_id: support.pressed_id(effects:)),
    )
    == False
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [8000]
    as "one timer at the node's end, 8 s from the go (Mental Overflow 200468)"
}

pub fn the_finish_and_the_audiences_news_come_when_the_life_is_over_and_not_before_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.press(
      plans: eight_seconds_on_the_caster(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, early) = support.fired(state:, timer:, at: 8999)
  assert support.writes(effects: early) == []
    as "a timer that fires with life left writes nothing"
  let assert [#(timer, 1)] = support.started_timers(effects: early)
  let #(_, ended) = support.fired(state:, timer:, at: 9000)
  assert support.finished_ids(support.writes(effects: ended)) == [id]
  assert support.tells(effects: ended) == [CastFinished(cast_id: id)]
}

/// A lingering cast ends with its 0x7fe alone, for a cast method the client destroys at 0x811
/// and one it does not: the client runs FinishCast for it, which starts the cooldowns of a
/// method 1 or 2 cast (`opcode.0x7fe`) and destroys every node of the cast
/// (`cast.target_node_end`); a 0x811 first would destroy a cast whose method the client does
/// not keep (`opcode.0x811`) and so skip that FinishCast. The casts are the server's own
/// (`cast.level_up_started`), since a press of a PressHold spell is not built. A Channeled
/// cast's end is in the channel test below.
pub fn a_lingering_cast_ends_with_the_finish_alone_whatever_its_method_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(spell_plan.Normal, "Normal, which the client destroys at 0x811"),
      #(
        spell_plan.PressHold,
        "PressHold (method 2), whose cooldowns FinishCast starts",
      ),
    ],
    fn(row) {
      let spell =
        spell_plan.Spell(
          ..buff(spell4_id: 77_116, base: 3, lasting: [
            fluff(
              id: 200_468,
              aim: spell_plan.AimsAtCaster,
              lasts: lasts.For(duration_ms: 8000),
            ),
          ]),
          method: row.0,
        )
      let #(state, started) =
        cast.level_up_started(
          cast: cast_state.new(),
          caster: support.caster(),
          spell:,
          now: support.at(ms: 1000),
        )
      let #(state, effects) =
        support.answered_with_no_targets(state:, effects: started, at: 1000)
      let assert [#(timer, 8000)] = support.started_timers(effects:) as row.1
      let #(state, early) = support.fired(state:, timer:, at: 8999)
      let assert [#(timer, 1)] = support.started_timers(effects: early) as row.1
      let #(_, ended) = support.fired(state:, timer:, at: 9000)
      assert support.ids(frames: support.writes(effects: ended)) == [0x07FE]
        as row.1
    },
  )
}

pub fn nodes_ending_at_two_times_end_with_a_0x811_and_then_the_finish_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.For(duration_ms: 3000),
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          lasts: lasts.For(duration_ms: 8000),
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        cast_state.Hit(
          unit_id: 20,
          unit: cast_state.HitCreature(life: 1),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ],
      at: 1000,
    )
  let id = support.pressed_id(effects:)
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
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.For(duration_ms: 3000),
        ),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          lasts: lasts.For(duration_ms: 3000),
        ),
        fluff(id: 3, aim: spell_plan.AimsAtCaster, lasts: lasts.UntilRemoved),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        cast_state.Hit(
          unit_id: 20,
          unit: cast_state.HitCreature(life: 1),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
        cast_state.Hit(
          unit_id: 21,
          unit: cast_state.HitCreature(life: 1),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ],
      at: 1000,
    )
  let id = support.pressed_id(effects:)
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
    support.plans_of([
      buff(spell4_id: 42_569, base: 3, lasting: [
        fluff(
          id: 96_819,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.UntilRemoved,
        ),
      ]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  assert support.finished_ids(support.writes(effects:)) == []
  assert support.started_timers(effects:) == []
}

// ---- a type 80 removal ----

pub fn a_removal_takes_the_casts_of_a_spell_off_and_a_later_timer_finds_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.For(duration_ms: 5000),
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects: first)
  let assert [#(timer, 5000)] = support.started_timers(effects: first)
  let #(state, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 2000)
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
    support.plans_of([
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let #(state, second) =
    support.press(plans:, state:, bag: bag_of_base_3, at: 1100)
  let #(_, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 1200)
  assert support.removed_targets(support.writes(effects: removal))
    == [#(support.pressed_id(effects: first), [7])]
    as "count 1 takes the older cast's whole node"
  assert support.removed_stacks(support.writes(effects: removal)) == []
  assert support.pressed_id(effects: second)
    != support.pressed_id(effects: first)
}

pub fn a_removal_that_a_gate_stops_takes_nothing_off_until_the_gate_passes_test() -> Nil {
  use <- owned_test.run(5000)
  // Quick Draw's removal 196521: it runs only behind prerequisite 17302, type 15 of
  // 43500, the caster under Quick Draw's marker.
  let gate =
    prerequisite_support.loaded(id: 17_302, rows: [
      prerequisite_support.row(id: 17_302, flags: 0, conditions: [
        #(15, 1, 0, 43_500),
      ]),
    ])
  let plans =
    support.plans_of([
      buff(spell4_id: 43_500, base: 3, lasting: [
        fluff(
          id: 99_472,
          aim: spell_plan.AimsAtCaster,
          lasts: lasts.For(duration_ms: 990),
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_1, at: 1000)
  assert support.removed_targets(support.writes(effects: without)) == []
    as "the caster is under no 43500: the gate fails"
  let #(state, marker) =
    support.press(plans:, state:, bag: bag_of_base_3, at: 1100)
  let #(_, with) = support.press(plans:, state:, bag: bag_of_base_1, at: 1200)
  assert support.removed_targets(support.writes(effects: with))
    == [#(support.pressed_id(effects: marker), [7])]
    as "with the marker held, the removal takes it off"
}

pub fn a_removal_behind_a_target_prerequisite_is_not_applied_with_a_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(id: 1, aim: spell_plan.AimsAtCaster, lasts: lasts.UntilRemoved),
      ]),
      remover(
        spell4_id: 301,
        base: 1,
        selector: lasting.Spell(Spell4Id(101)),
        count: 1,
        condition: GatedOnTarget(
          prerequisite: prerequisite_support.single(id: 5, condition: #(
            38,
            1,
            0,
            5,
          )),
        ),
      ),
    ])
  let #(state, _) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let #(_, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 1100)
  assert support.removed_targets(support.writes(effects: removal)) == []
  assert list.all(support.logs(effects: removal), fn(line) {
    !string.contains(line.1, "prerequisite")
  })
    as "the gate is read and the caster fails it: no line about it"
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
        lasts: lasts.UntilRemoved,
      ),
    ]),
    stack: Stack(group_id: group, cap:),
  )
}

pub fn a_third_copy_of_a_cap_2_group_takes_the_casters_oldest_off_test() -> Nil {
  use <- owned_test.run(5000)
  // Power Charge 42569 is in stack group 1450, cap 2 (Spell4StackGroup).
  let plans =
    support.plans_of([stacked(spell4_id: 42_569, base: 3, group: 1450, cap: 2)])
  let #(state, first) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let #(state, second) =
    support.press(plans:, state:, bag: bag_of_base_3, at: 1100)
  assert support.removed_targets(support.writes(effects: second)) == []
    as "two casts are within the cap"
  let #(state, third) =
    support.press(plans:, state:, bag: bag_of_base_3, at: 1200)
  assert support.removed_targets(support.writes(effects: third))
    == [#(support.pressed_id(effects: first), [7])]
    as "the third takes the oldest off the caster"
  let #(_, fourth) = support.press(plans:, state:, bag: bag_of_base_3, at: 1300)
  assert support.removed_targets(support.writes(effects: fourth))
    == [#(support.pressed_id(effects: second), [7])]
    as "and the fourth takes the next oldest: two stay"
}

pub fn a_second_cast_of_a_cap_0_spell_takes_the_first_one_off_and_another_spell_stays_test() -> Nil {
  use <- owned_test.run(5000)
  // Charged Shot 34718 is in group 2, cap 0: one cast per spell.
  let plans =
    support.plans_of([
      stacked(spell4_id: 34_718, base: 3, group: 2, cap: 0),
      stacked(spell4_id: 99, base: 2, group: 2, cap: 0),
    ])
  let #(state, first) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let #(state, other) =
    support.press(plans:, state:, bag: bag_of_base_2, at: 1100)
  assert support.removed_targets(support.writes(effects: other)) == []
    as "a cast of another spell of the group stays"
  let #(_, again) = support.press(plans:, state:, bag: bag_of_base_3, at: 1200)
  assert support.removed_targets(support.writes(effects: again))
    == [#(support.pressed_id(effects: first), [7])]
    as "the second Charged Shot takes the first one's marker off"
}

// ---- the caster, and the units in sight ----

pub fn the_caster_dying_finishes_a_lingering_cast_with_its_0x7fe_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.press(
      plans: eight_seconds_on_the_caster(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let #(_, ended) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 2000),
    )
  assert support.finished_ids(support.writes(effects: ended)) == [id]
    as "the server's choice: the client has no path that ends a buff on a unit's death (cast.target_node_end)"
  assert support.tells(effects: ended) == [CastFinished(cast_id: id)]
}

pub fn a_caster_that_leaves_writes_nothing_for_its_lingering_casts_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.press(
      plans: eight_seconds_on_the_caster(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, left) = cast_tick.left(cast: state)
  assert support.writes(effects: left) == []
  assert support.cancelled_timers(effects: left) == [timer]
  let #(_, late) = support.fired(state:, timer:, at: 9000)
  assert support.writes(effects: late) == []
}

pub fn a_nodes_unit_leaving_sight_ends_a_lingering_cast_left_with_no_node_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(
          id: 1,
          aim: spell_plan.AimsAtArea,
          lasts: lasts.For(duration_ms: 8000),
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        cast_state.Hit(
          unit_id: 20,
          unit: cast_state.HitCreature(life: 1),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ],
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, other) =
    cast_proc.unit_removed(cast: state, unit_id: 21, now_ms: 2000)
  assert support.writes(effects: other) == []
    as "a unit that holds no node of the cast changes nothing"
  let #(state, removed) =
    cast_proc.unit_removed(cast: state, unit_id: 20, now_ms: 3000)
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
    support.plans_of([
      buff(spell4_id: 101, base: 3, lasting: [
        fluff(id: 1, aim: spell_plan.AimsAtCaster, lasts: lasts.UntilRemoved),
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          lasts: lasts.For(duration_ms: 8000),
        ),
      ]),
    ])
  let #(state, effects) =
    press_striking(
      plans:,
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        cast_state.Hit(
          unit_id: 20,
          unit: cast_state.HitCreature(life: 1),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ],
      at: 1000,
    )
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(_, removed) =
    cast_proc.unit_removed(cast: state, unit_id: 20, now_ms: 3000)
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

pub fn a_channel_that_holds_its_own_fluff_ends_its_other_steps_when_it_lingers_test() -> Nil {
  use <- owned_test.run(5000)
  // Pulses at 0 and 1000 after the press at 1000 and a channelMaxTime of 1500: the
  // channel ends at 2500, its last go at 2000 gives an 8 s node that ends at 10000.
  let plans =
    support.plans_of([
      channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            lasts: lasts.For(duration_ms: 8000),
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
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
  let #(_, free) = support.press(plans:, state:, bag: bag_of_base_2, at: 2500)
  assert list.contains(support.written_ids(effects: free), 0x07FD)
    as "the current cast is clear while the buff lingers"
  let #(_, refused) =
    support.press(plans:, state:, bag: bag_of_base_3, at: 2500)
  assert support.refusals(effects: refused) == [cast_result.SpellCooldown]
    as "the cooldown started when the cast lingered, at 2500 (0x14053e1b0)"
  // At 8000 the cooldown (5000 from 2500) has ended while the buff still lingers: a
  // cooldown that started at the 0x7fe, at 10000, would still refuse.
  let #(_, again) = support.press(plans:, state:, bag: bag_of_base_3, at: 8000)
  assert support.refusals(effects: again) == []
    as "the press is taken: the cooldown ran from the linger, not from the 0x7fe"
}

// ---- the round of fixes: nodes of a live cast, a cancel, a later go ----

/// A channel that pulses at 0, 3000 and 6000 after the press (no finish timer of its
/// own) whose each go gives the caster a Fluff of 1000 ms.
fn short_buff_on_a_long_channel() -> Plans {
  short_buff_on_a_long_channel_with(cast_bar: spell_plan.HidesCastBar)
}

/// The channel of `short_buff_on_a_long_channel`, its cast bar as given: a cast that shows
/// its bar is the caster's current cast while it lives.
fn short_buff_on_a_long_channel_with(
  cast_bar cast_bar: spell_plan.CastBar,
) -> Plans {
  buffed_channel(initial_delay_ms: 0, cast_bar:)
}

/// The plans of a channel of 6000 ms pulsing every 3000 ms that starts a one-second buff on
/// the caster, whose first go comes after this delay, with this cast bar.
fn buffed_channel(
  initial_delay_ms initial_delay_ms: Int,
  cast_bar cast_bar: spell_plan.CastBar,
) -> Plans {
  support.plans_of([
    spell_plan.Spell(
      ..channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            lasts: lasts.For(duration_ms: 1000),
          ),
        ],
        channel: spell_plan.Channel(
          initial_delay_ms:,
          max_time_ms: 6000,
          pulse_time_ms: 3000,
        ),
      ),
      cast_bar:,
    ),
  ])
}

/// The channel of `short_buff_on_a_long_channel` whose first pulse waits 2000 ms: a live
/// cast that is not the current cast and holds no node until then.
fn channel_before_its_first_go() -> Plans {
  buffed_channel(initial_delay_ms: 2000, cast_bar: spell_plan.HidesCastBar)
}

pub fn a_node_whose_life_ends_while_its_cast_is_live_is_ended_and_the_cast_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = short_buff_on_a_long_channel()
  let #(state, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let #(state, _) =
    support.run_timers_until(state:, effects:, from_ms: 1000, until_ms: 2000)
  let #(_, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 2100)
  assert support.removed_targets(support.writes(effects: removal)) == []
    as "the node ended at 2000: a removal finds nothing on the caster"
}

pub fn a_cancel_of_a_cast_holding_nodes_lets_them_linger_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            lasts: lasts.For(duration_ms: 8000),
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
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

pub fn an_earlier_until_removed_node_survives_a_later_go_with_no_life_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x7f4.instance_count: a later go of the same cast keeps the node's effects
  // and adds the go's; Spell4Effects.effectType.17: the node's life is the longest. So
  // the phase 1 go, whose Fluff has no life, leaves the until-removed node, and the cast
  // lingers after its last go.
  let plans =
    support.plans_of([
      channel(
        lasting: [
          spell_plan.Lasting(
            ..fluff(
              id: 1,
              aim: spell_plan.AimsAtCaster,
              lasts: lasts.UntilRemoved,
            ),
            phase_flags: 1,
          ),
          spell_plan.Lasting(
            ..fluff(
              id: 2,
              aim: spell_plan.AimsAtCaster,
              lasts: lasts.For(duration_ms: 0),
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let #(state, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  let assert [#(2000, last)] = steps
  assert support.finished_ids(support.writes(effects: last)) == []
    as "the last go leaves the earlier node: the cast lingers and writes no 0x7fe"
  assert support.started_timers(effects: last) == []
    as "the node lasts until removed: no timer"
  let #(_, removal) =
    support.press(
      plans: support.with_spells(plans:, spells: [
        remover(
          spell4_id: 301,
          base: 1,
          selector: lasting.Spell(Spell4Id(101)),
          count: 1,
          condition: Always,
        ),
      ]),
      state:,
      bag: bag_of_base_1,
      at: 3000,
    )
  assert support.removed_targets(support.writes(effects: removal))
    == [#(support.pressed_id(effects:), [7])]
    as "the node is still held: a removal takes it off"
}

pub fn a_timed_node_is_re_timed_from_a_later_go_of_its_cast_test() -> Nil {
  use <- owned_test.run(5000)
  // A Fluff of 5 s in both phases, gos at 1000 and 2000: the node of the first go would
  // end at 6000; the later go arms its effect again from 2000, so it ends at 7000.
  let plans =
    support.plans_of([
      channel(
        lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtCaster,
            lasts: lasts.For(duration_ms: 5000),
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
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [1000, 5000]
    as "the later go's timer and the first node's end, 5 s from the go"
  let #(_, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.map(steps, fn(step) {
      #(step.0, support.finished_ids(support.writes(effects: step.1)))
    })
    == [#(2000, []), #(7000, [id])]
    as "the first go's timer for 6000 is replaced: the one 0x7fe is at 7000 (opcode.0x7f4.instance_count)"
}

// ---- a cast's news goes to the map, which relays it to every viewer ----

/// What the map is told of the casts over the timers of a state, in order.
fn told_over(fired fired: List(#(Int, List(cast_state.Effect)))) -> List(News) {
  list.flat_map(fired, fn(step) { support.tells(effects: step.1) })
}

/// `cast.target_node_end` (a node ends only by a 0x811 or a 0x7fe the client is sent): the
/// caster tells the map the news of each of its casts once, whatever the cast holds, and
/// keeps no list of the viewers it was told to; a viewer's own ledger of the casts its
/// create listed (`opcode.0x262.casts`: the current cast and each cast that holds a node
/// with a listed effect, live or lingering) decides what its client is written.
pub fn a_cast_tells_the_map_each_news_of_its_life_once_test() -> Nil {
  use <- owned_test.run(5000)
  let press = fn(plans) {
    let #(state, start) =
      support.press_by(
        plans:,
        state: cast_state.new(),
        caster: support.caster(),
        bag: bag_of_base_3,
        at: 1000,
      )
    #(state, start, support.pressed_id(effects: start))
  }
  let told_after = fn(state, start) {
    told_over(
      fired: support.run_timers(state:, effects: start, from_ms: 1000).1,
    )
  }
  let #(live, live_start, live_id) =
    press(short_buff_on_a_long_channel_with(cast_bar: spell_plan.ShowsCastBar))
  assert cast_state.current_cast_id(cast: live) == live_id
    as "a channel that shows its cast bar is the current cast"
  // A channel with pulses at 3000 and 6000 after the press, holding a 1 s node of its own
  // on the caster at each: the nodes end at 2000, 4000 and 7000.
  let told = told_after(live, live_start)
  assert list.take(told, 1)
    == [
      CastTargetsRemoved(removed: removal(cast_id: live_id), destroyed: False),
    ]
    as "the map is told the end of the node the press made"
  assert list.last(told) == Ok(CastFinished(cast_id: live_id))
    as "and the 0x7fe"
  assert list.length(told) == 5
    as "and each news after: the node ends at 2000 and 4000, the pulses at 3000 and 6000, and the finish"
  assert list.count(told, fn(one) { one == CastFinished(cast_id: live_id) })
    == 1
    as "one 0x7fe"
  let #(hidden, hidden_start, hidden_id) = press(short_buff_on_a_long_channel())
  assert cast_state.current_cast_id(cast: hidden) == 0
    as "a channel that hides its cast bar is not the current cast"
  let told_hidden = told_after(hidden, hidden_start)
  assert list.take(told_hidden, 1)
    == [
      CastTargetsRemoved(removed: removal(cast_id: hidden_id), destroyed: False),
    ]
    as "a live cast that is not the current cast but holds a node is told as any other"
  assert list.last(told_hidden) == Ok(CastFinished(cast_id: hidden_id))
    as "and its 0x7fe"
  let #(lingering, lingering_start, lingering_id) =
    press(eight_seconds_on_the_caster())
  assert dict.has_key(lingering.lingering, lingering_id)
    as "the 8 s buff leaves its cast lingering"
  assert told_after(lingering, lingering_start)
    == [CastFinished(cast_id: lingering_id)]
    as "a lingering cast tells the map its 0x7fe when its node ends"
}

/// The 0x811 that takes the caster's own node (unit 7) off the cast.
fn removal(cast_id cast_id: Int) -> SpellTargetsRemoved {
  SpellTargetsRemoved(cast_id:, unit_ids: [7])
}

// ---- what a go keeps of each effect on the node ----

/// The reached row `kind` of Spell4Effects `id` on the player 7, with `product`.
fn reached_on_caster(
  id id: Int,
  kind kind: spell_plan.Kind,
  product product: cast_state.Product,
) -> cast_state.Reached {
  cast_state.Reached(
    effect: spell_effect.PlannedEffect(
      effect_id: Spell4EffectsId(id),
      phase_flags: -1,
      tag: spend.always,
      kind:,
    ),
    unit_id: 7,
    product:,
  )
}

/// What a go aimed at the player 7 holds: these reached rows, restrictions and periodic
/// rows.
fn aimed_at_caster(
  reached reached: List(cast_state.Reached),
  restrictions restrictions: List(#(cast_state.Restricting, Int)),
  ticking ticking: List(cast_state.TickingOn),
) -> cast_state.Aimed {
  cast_state.Aimed(
    units: [],
    reached:,
    reach_logs: [],
    controls: [],
    restrictions:,
    ticking:,
    rolls_left: [],
  )
}

pub fn a_go_keeps_each_effect_with_its_kind_and_effect_id_on_the_node_test() -> Nil {
  use <- owned_test.run(5000)
  let formula =
    Formula(multiplier: 1.0, base: 40.0, parameters: [
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ])
  let fluff_row = LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 3000))
  let heal =
    spell_plan.Heal(
      effect_id: Spell4EffectsId(4),
      vital: effect_kind.Health,
      phase_flags: -1,
      aim: spell_plan.AimsAtCaster,
      condition: Always,
      tag: spend.always,
      formula:,
      delay_ms: 500,
    )
  list.each(
    [
      #(
        "a reached Fluff row is kept Listed with its Spell4Effects id",
        aimed_at_caster(
          reached: [
            reached_on_caster(
              id: 224_001,
              kind: spell_plan.LastingEffect(Lasting(
                effect_id: Spell4EffectsId(224_001),
                phase_flags: -1,
                aim: spell_plan.AimsAtCaster,
                row: fluff_row,
                condition: Always,
                tag: spend.always,
              )),
              product: cast_state.Plain,
            ),
          ],
          restrictions: [],
          ticking: [],
        ),
        [Listed(effect_id: Spell4EffectsId(224_001), row: fluff_row)],
      ),
      #(
        "a periodic row is kept Listed with the id of its TickingOn, its life its delay and duration and never until removed (ticking.schedule_of refuses flags bit 2)",
        aimed_at_caster(reached: [], restrictions: [], ticking: [
          cast_state.TickingOn(
            unit_id: 7,
            life: 0,
            effect_id: Spell4EffectsId(96_125),
            schedule: ticking.Schedule(
              delay_ms: 0,
              tick_ms: 2000,
              duration_ms: 6000,
              count: ticking.Ticks(3),
            ),
            kind: cast_state.heal_tick(
              vital: effect_kind.Health,
              formula:,
              passed_in: option.None,
            ),
          ),
        ]),
        [
          Listed(
            effect_id: Spell4EffectsId(96_125),
            row: LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 6000)),
          ),
        ],
      ),
      #(
        "an ability restriction row is kept LifeOnly: the 0x87f tells it, not a unit create",
        aimed_at_caster(
          reached: [],
          restrictions: [
            #(
              cast_state.Restricting(
                row: spell_plan.CrowdControl(
                  effect_id: Spell4EffectsId(224_967),
                  phase_flags: -1,
                  aim: spell_plan.AimsAtCaster,
                  row: crowd_control.Row(
                    state: AbilityRestriction,
                    delay_ms: 0,
                    lasts: lasts.For(duration_ms: 5000),
                    armor_removed: 0,
                  ),
                  condition: Always,
                  tag: spend.always,
                  move: option.None,
                ),
                instance_id: 1,
                fresh: True,
              ),
              7,
            ),
          ],
          ticking: [],
        ),
        [
          LifeOnly(row: LastingRow(
            delay_ms: 0,
            lasts: lasts.For(duration_ms: 5000),
          )),
        ],
      ),
      #(
        "a heal applied at once is kept LifeOnly: its life is its delay, so the 0x7fe waits for it, and the go tells its value",
        aimed_at_caster(
          reached: [
            reached_on_caster(
              id: 4,
              kind: spell_plan.HealEffect(heal),
              product: cast_state.Healing(cast_state.Healed(
                effect_id: Spell4EffectsId(4),
                vital: effect_kind.Health,
                delay_ms: 500,
                amount: 40,
                split: heal_split.Split(
                  amount: 40,
                  shield: 0,
                  health: 40,
                  overheal: 0,
                ),
              )),
            ),
          ],
          restrictions: [],
          ticking: [],
        ),
        [
          LifeOnly(row: LastingRow(
            delay_ms: 500,
            lasts: lasts.For(duration_ms: 0),
          )),
        ],
      ),
    ],
    fn(row) {
      let #(reason, aimed, expected) = row
      let assert Ok(node) =
        cast_tick.node_of(
          spell: support.child(spell4_id: 7, base: 3),
          held: option.None,
          aimed:,
          unit_id: 7,
          started_ms: 1000,
          now_ms: 1000,
        )
        as reason
      assert node.effects == expected as reason
    },
  )
}

// ---- the casts a player's unit create lists ----

/// The views a unit create of the player 7 lists, each as its cast id, whether it is the
/// current cast, whether its first go has gone and the units it holds a node on.
fn listed_views(state state: State) -> List(#(Int, Bool, Bool, List(Int))) {
  unit_casts.listed(views: cast_state.views(cast: state, caster_unit_id: 7))
  |> list.map(fn(view) {
    #(
      view.cast_id,
      view.current,
      view.gone,
      list.map(view.targets, fn(target) { target.unit_id }),
    )
  })
}

pub fn a_players_views_hold_every_live_and_lingering_cast_with_a_listed_target_test() -> Nil {
  use <- owned_test.run(5000)
  let #(hidden, hidden_effects) =
    support.press(
      plans: short_buff_on_a_long_channel(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(lingering, lingering_effects) =
    support.press(
      plans: eight_seconds_on_the_caster(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(waiting, waiting_effects) =
    support.press(
      plans: channel_before_its_first_go(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(on_creature, creature_effects) =
    press_striking(
      plans: support.plans_of([
        buff(spell4_id: 101, base: 3, lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtArea,
            lasts: lasts.For(duration_ms: 3000),
          ),
        ]),
      ]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: support.hits([20]),
      at: 1000,
    )
  let #(on_two_creatures, two_creature_effects) =
    press_striking(
      plans: support.plans_of([
        buff(spell4_id: 101, base: 3, lasting: [
          fluff(
            id: 1,
            aim: spell_plan.AimsAtArea,
            lasts: lasts.For(duration_ms: 3000),
          ),
        ]),
      ]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: support.hits([21, 20]),
      at: 1000,
    )
  assert dict.is_empty(waiting.lingering)
    && list.all(dict.values(waiting.casts), fn(live) {
      dict.is_empty(live.nodes)
    })
    as "the channel that waits holds a live cast and no node"
  list.each(
    [
      #(
        "a live cast that is not the current cast and holds a node is listed, its first go gone",
        hidden,
        [
          #(support.pressed_id(effects: hidden_effects), False, True, [7]),
        ],
      ),
      #("a lingering cast is listed, its first go gone", lingering, [
        #(support.pressed_id(effects: lingering_effects), False, True, [7]),
      ]),
      #(
        "a lingering cast is not the current cast, even in a state whose current names it (built by hand: the rule clears current when a cast starts to linger): the create's tail names cast 0 for it, so its entry must not claim the cast bar",
        cast_state.State(
          ..lingering,
          current: option.Some(support.pressed_id(effects: lingering_effects)),
        ),
        [#(support.pressed_id(effects: lingering_effects), False, True, [7])],
      ),
      #(
        "the current cast before its first go is listed with its first go not gone",
        cast_state.State(
          ..waiting,
          current: option.Some(support.pressed_id(effects: waiting_effects)),
        ),
        [#(support.pressed_id(effects: waiting_effects), True, False, [])],
      ),
      #(
        "a live cast that is not the current cast and holds no node yet is not listed",
        waiting,
        [],
      ),
      #(
        "a cast whose node is on a creature lists the creature as its target",
        on_creature,
        [
          #(support.pressed_id(effects: creature_effects), False, True, [20]),
        ],
      ),
      #(
        "a cast with nodes on two units lists them in unit id order, whatever order the area struck them in: the entry's target index is the place in that list",
        on_two_creatures,
        [
          #(support.pressed_id(effects: two_creature_effects), False, True, [
            20,
            21,
          ]),
        ],
      ),
    ],
    fn(row) {
      assert listed_views(state: row.1) == row.2 as row.0
    },
  )
}

// ---- the creatures told what a cast holds on them ----

/// What `creature_view.compared` gives the player 7 for each state in turn, the told map
/// carried from one state to the next as the connection's state carries it.
fn compared_in_turn(
  states states: List(State),
) -> List(List(creature_view.Change)) {
  let #(_, changes) =
    list.fold(states, #(dict.new(), []), fn(so_far, state) {
      let #(told, changes) = so_far
      let #(compared, now) =
        creature_view.compared(
          cast: cast_state.State(..state, creature_told: told),
          caster_unit_id: 7,
        )
      #(compared.creature_told, list.append(changes, [now]))
    })
  changes
}

/// A spell whose go leaves a Fluff of `duration_ms` on each unit the round struck.
fn area_buff(duration_ms duration_ms: Int) -> Plans {
  support.plans_of([
    buff(spell4_id: 101, base: 3, lasting: [
      fluff(id: 2, aim: spell_plan.AimsAtArea, lasts: lasts.For(duration_ms:)),
    ]),
  ])
}

/// A channel with gos at 1000 and 2000 after a press at 1000, each leaving a Fluff of 5 s on
/// the units its round struck.
fn two_gos_of_an_area_buff() -> Plans {
  support.plans_of([
    channel(
      lasting: [
        fluff(
          id: 2,
          aim: spell_plan.AimsAtArea,
          lasts: lasts.For(duration_ms: 5000),
        ),
      ],
      channel: spell_plan.Channel(
        initial_delay_ms: 0,
        max_time_ms: 1000,
        pulse_time_ms: 1000,
      ),
    ),
  ])
}

/// The view the cast `cast_id` of Spell4 `spell4_id` holds on the creature `unit_id`: its one
/// effect `effect_id` from `starts_ms` to `ends_ms`, the first go gone and no cast in progress.
fn creature_view_of(
  cast_id cast_id: Int,
  spell4_id spell4_id: Int,
  primary_target primary_target: Int,
  unit_id unit_id: Int,
  count count: Int,
  effect_id effect_id: Int,
  starts_ms starts_ms: Int,
  ends_ms ends_ms: Int,
) -> unit_casts.CastView {
  unit_casts.CastView(
    caster_unit_id: 7,
    cast_id:,
    spell4_id: Spell4Id(spell4_id),
    primary_target:,
    gone: True,
    current: False,
    targets: [
      unit_casts.ViewTarget(unit_id:, count:, effects: [
        unit_casts.HeldEffect(
          effect_id: Spell4EffectsId(effect_id),
          starts_ms:,
          ends: unit_casts.EndsAt(ms: ends_ms),
        ),
      ]),
    ],
  )
}

/// The change that tells the creature `unit_id` of `life` the view.
fn view_set(
  unit_id unit_id: Int,
  life life: Int,
  view view: unit_casts.CastView,
) -> creature_view.Change {
  creature_view.ViewSet(unit_id:, life:, view:)
}

/// The state with the cast's node on each unit given by `change`.
fn with_nodes_changed(
  state state: State,
  cast_id cast_id: Int,
  change change: fn(lasting.Node) -> lasting.Node,
) -> State {
  let assert Ok(holder) = cast_state.holder_of(cast: state, cast_id:)
    as "the cast holds nodes"
  cast_tick.with_nodes(
    cast: state,
    cast_id:,
    nodes: dict.map_values(holder.nodes, fn(_, node) { change(node) }),
  )
}

/// `opcode.0x7f4.instance_count`: a later go of a cast arms its node again. The caster tells
/// each creature the node its casts hold on it (`creature_view.compared`), for the round that
/// struck it: the node a go left, the child cast Fissure's Proxy starts on the struck creature
/// (Spell4Effects 141501, 94370: 8000 ms), a later go of the same cast, a stack off, and a
/// compare that finds nothing new.
pub fn the_caster_tells_each_creature_what_its_casts_hold_on_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(on_a_creature, creature_effects) =
    press_striking(
      plans: area_buff(duration_ms: 3000),
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [support.creature_hit(unit_id: 20, life: 3)],
      at: 1000,
    )
  let creature_cast = support.pressed_id(effects: creature_effects)
  let a_go =
    creature_view_of(
      cast_id: creature_cast,
      spell4_id: 101,
      primary_target: 7,
      unit_id: 20,
      count: 1,
      effect_id: 2,
      starts_ms: 1000,
      ends_ms: 4000,
    )
  let #(on_the_caster, _) =
    support.press(
      plans: support.plans_of([
        buff(spell4_id: 101, base: 3, lasting: [
          fluff(
            id: 2,
            aim: spell_plan.AimsAtCaster,
            lasts: lasts.For(duration_ms: 3000),
          ),
        ]),
      ]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(on_a_player, _) =
    press_striking(
      plans: area_buff(duration_ms: 3000),
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        support.player_hit(unit_id: 21),
        cast_state.Deflected(unit_id: 20),
      ],
      at: 1000,
    )
  // Fissure: Spell4 41843 (Spell4Base 26038) starts the proxy 41844 on the caster, whose
  // Proxy row 141501 starts 41886 on each unit its round hit; 41886's row 94370 holds the
  // node. The two rounds are answered at their own life and time.
  let fissure_caster =
    cast_state.Caster(
      ..support.caster(),
      abilities: [Spell4BaseId(26_038)],
      book: [Spell4BaseId(26_038)],
    )
  let #(fissure, fissure_effects) =
    support.pressed_raw_in(
      plans: spell_plan.plans_with_later(tables: fixture_tables.shared()),
      state: cast_state.new(),
      caster: fissure_caster,
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let #(fissure, fissure_effects) =
    support.answered_each(
      caster: fissure_caster,
      state: fissure,
      effects: fissure_effects,
      at: 1000,
      struck_of: fn(asked) {
        case asked.spell4_id.value {
          41_886 -> [
            support.creature_hit(unit_id: 20, life: 2),
          ]
          _ -> [support.creature_hit(unit_id: 20, life: 1)]
        }
      },
      rolls: [],
      poses: dict.new(),
    )
  let assert Ok(child) =
    list.filter_map(
      support.frames_of(
        message_id: spell_started.message_id,
        effects: fissure_effects,
      ),
      fn(frame) {
        let assert Ok(started) = spell_started.decode(frame.body)
          as "a 0x7ff the rule wrote decodes"
        case started.spell4_id {
          41_886 -> Ok(started.cast_id)
          _ -> Error(Nil)
        }
      },
    )
    |> list.first
    as "the proxy's go started the child 41886"
  // A channel with gos at 1000 and 2000: the second go re-arms the node, whether its round
  // struck the creature again (a new round) or hit unit 20 as a player (no creature round).
  let two_gos = fn(second_round) {
    let #(first, effects) =
      press_striking(
        plans: two_gos_of_an_area_buff(),
        state: cast_state.new(),
        bag: bag_of_base_3,
        struck: [support.creature_hit(unit_id: 20, life: 1)],
        at: 1000,
      )
    let #(second, _) =
      support.run_timers_posed(
        caster: support.caster(),
        state: first,
        effects:,
        from_ms: 1000,
        struck_at: fn(_, _) { second_round },
        poses: dict.new(),
        until_ms: option.Some(2000),
      )
    #(first, second, support.pressed_id(effects:))
  }
  let #(first_go, again, channel_cast) =
    two_gos([support.creature_hit(unit_id: 20, life: 1)])
  let #(_, missed, _) = two_gos([support.player_hit(unit_id: 20)])
  let in_a_channel = fn(starts_ms, ends_ms) {
    creature_view_of(
      cast_id: channel_cast,
      spell4_id: 101,
      primary_target: 7,
      unit_id: 20,
      count: 1,
      effect_id: 2,
      starts_ms:,
      ends_ms:,
    )
  }
  // The node keeps the effect its first go listed and lists the second go's again
  // (`lasting.given`), so after a later go it holds the effect twice, both armed at the go.
  let doubled = fn(view: unit_casts.CastView) {
    unit_casts.CastView(
      ..view,
      targets: list.map(view.targets, fn(target) {
        unit_casts.ViewTarget(
          ..target,
          effects: list.append(target.effects, target.effects),
        )
      }),
    )
  }
  // Paralytic Surge's periodic row (Spell4Effects 96125) on the creature, ticking every 2000
  // ms for 6000 ms: the first tick's round closes with no answer at 3000, which ends the node.
  let ticking_row =
    spell_area.TickingDamage(
      damage: spell_area.DamageEffect(
        effect_id: Spell4EffectsId(96_125),
        damage_type: 2,
        delay_ms: 0,
        phase_flags: -1,
        aim: spell_plan.AimsAtArea,
        formula: Formula(multiplier: 1.0, base: 0.0, parameters: []),
        threat_multiplier: 1.0,
        condition: Always,
        tag: spend.always,
      ),
      schedule: ticking.Schedule(
        delay_ms: 0,
        tick_ms: 2000,
        duration_ms: 6000,
        count: ticking.Ticks(3),
      ),
    )
  let #(ticking_state, ticking_effects) =
    press_striking(
      plans: support.plans_of([support.child(spell4_id: 58_591, base: 3)]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        cast_state.Hit(
          unit_id: 20,
          unit: cast_state.HitCreature(life: 3),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [ticking_row],
        ),
      ],
      at: 1000,
    )
  let assert Ok(#(first_tick, _)) =
    list.first(support.started_timers(effects: ticking_effects))
    as "the go armed the first tick"
  let #(ticking_open, tick_effects) =
    support.fired_raw(state: ticking_state, timer: first_tick, at: 3000)
  let assert [asked] = support.tick_strikes(effects: tick_effects)
    as "the first tick asks the creature"
  let #(ticking_closed, _) =
    cast.ticked(
      cast: ticking_open,
      caster: support.caster(),
      now: support.at(ms: 3000),
      asked:,
      struck: option.None,
    )
  let #(three, three_effects) =
    press_striking(
      plans: area_buff(duration_ms: 3000),
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck: [
        support.creature_hit(unit_id: 22, life: 1),
        support.creature_hit(unit_id: 20, life: 1),
        support.creature_hit(unit_id: 21, life: 1),
      ],
      at: 1000,
    )
  let three_cast = support.pressed_id(effects: three_effects)
  // A go gives each node the count 1, and a push off emits a stack off only for a node whose
  // count is higher (`lasting.pushed_off`), so no cast reaches a count of 2 today: the node
  // is built by hand, and the row holds the compare's reaction to a count change, which no
  // real cast path exercises.
  let stacked_twice =
    with_nodes_changed(
      state: on_a_creature,
      cast_id: creature_cast,
      change: fn(node) { lasting.Node(..node, count: 2) },
    )
  let #(one_off, _) =
    cast_tick.stack_off(
      cast: stacked_twice,
      cast_id: creature_cast,
      unit_id: 20,
    )
  let twice =
    creature_view_of(
      cast_id: creature_cast,
      spell4_id: 101,
      primary_target: 7,
      unit_id: 20,
      count: 2,
      effect_id: 2,
      starts_ms: 1000,
      ends_ms: 4000,
    )
  list.each(
    [
      #(
        "a go's node on a creature gives the creature's life and the time of the round that struck it, that creature's target alone and no cast in progress",
        compared_in_turn(states: [on_a_creature]),
        [[view_set(unit_id: 20, life: 3, view: a_go)]],
      ),
      #(
        "a node only on the caster is told no creature",
        compared_in_turn(states: [on_the_caster]),
        [[]],
      ),
      #(
        "a node on a player, and a unit the round deflected, is told no creature: no round struck it as a creature",
        compared_in_turn(states: [on_a_player]),
        [[]],
      ),
      #(
        "Fissure's child go stamps the node with its own round (life 2, 1500), not the proxy's (life 1, 1000)",
        compared_in_turn(states: [fissure]),
        [
          [
            view_set(
              unit_id: 20,
              life: 2,
              view: creature_view_of(
                cast_id: child,
                spell4_id: 41_886,
                primary_target: 20,
                unit_id: 20,
                count: 1,
                effect_id: 94_370,
                starts_ms: 1000,
                ends_ms: 9000,
              ),
            ),
          ],
        ],
      ),
      #(
        "a later go on the same creature gives a whole new set, its start and end armed again",
        compared_in_turn(states: [first_go, again]),
        [
          [
            view_set(unit_id: 20, life: 1, view: in_a_channel(1000, 6000)),
          ],
          [
            view_set(
              unit_id: 20,
              life: 1,
              view: doubled(in_a_channel(2000, 7000)),
            ),
          ],
        ],
      ),
      #(
        "a later go whose round hit the unit as no creature keeps the earlier stamp, with the times armed again",
        compared_in_turn(states: [first_go, missed]),
        [
          [
            view_set(unit_id: 20, life: 1, view: in_a_channel(1000, 6000)),
          ],
          [
            view_set(
              unit_id: 20,
              life: 1,
              view: doubled(in_a_channel(2000, 7000)),
            ),
          ],
        ],
      ),
      #(
        "a node whose count changes (hand-built: no cast path gives a count above 1) gives a set with the new count, and one with the count lowered after a stack off",
        compared_in_turn(states: [on_a_creature, stacked_twice, one_off]),
        [
          [view_set(unit_id: 20, life: 3, view: a_go)],
          [view_set(unit_id: 20, life: 3, view: twice)],
          [view_set(unit_id: 20, life: 3, view: a_go)],
        ],
      ),
      #(
        "a second compare with no step between gives none",
        compared_in_turn(states: [on_a_creature, on_a_creature]),
        [
          [view_set(unit_id: 20, life: 3, view: a_go)],
          [],
        ],
      ),
      #(
        "a tick round that closes with no answer ends the node: its view ends, with no set before it",
        compared_in_turn(states: [ticking_state, ticking_open, ticking_closed]),
        [
          [
            view_set(
              unit_id: 20,
              life: 3,
              view: creature_view_of(
                cast_id: asked.cast_id,
                spell4_id: 58_591,
                primary_target: 7,
                unit_id: 20,
                count: 1,
                effect_id: 96_125,
                starts_ms: 1000,
                ends_ms: 7000,
              ),
            ),
          ],
          [],
          [creature_view.ViewEnds(unit_id: 20, life: 3, cast_id: asked.cast_id)],
        ],
      ),
      #(
        "a go on three creatures gives one set each, in unit order",
        compared_in_turn(states: [three]),
        [
          list.map([20, 21, 22], fn(unit_id) {
            view_set(
              unit_id:,
              life: 1,
              view: creature_view_of(
                cast_id: three_cast,
                spell4_id: 101,
                primary_target: 7,
                unit_id:,
                count: 1,
                effect_id: 2,
                starts_ms: 1000,
                ends_ms: 4000,
              ),
            )
          }),
        ],
      ),
    ],
    fn(row) {
      assert row.1 == row.2 as row.0
    },
  )
}

/// `cast.target_node_end`: a node the client holds ends only by what the server sends, so a
/// creature told a view is told it ended when the cast's holder is gone: its last node ends
/// by time and the cast finishes (`finish_or_linger`), the caster dies (`all_ended`), the
/// caster leaves the world (`cast_tick.left`); the passive a death sets aside and puts back
/// in the same step holds its node throughout and is told nothing.
pub fn a_holder_gone_or_left_is_told_by_the_compare_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = area_buff(duration_ms: 3000)
  let struck = [support.creature_hit(unit_id: 20, life: 3)]
  let #(held, effects) =
    press_striking(
      plans:,
      state: cast_state.new(),
      bag: bag_of_base_3,
      struck:,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let assert [#(node_end, 3000)] = support.started_timers(effects:)
  let #(finished, _) = support.fired(state: held, timer: node_end, at: 4000)
  let #(dead, _) =
    cast.died(
      cast: held,
      caster: support.dead_caster(),
      now: support.at(ms: 2000),
    )
  let #(left, _) = cast_tick.left(cast: held)
  let #(passive, passive_effects) =
    support.standing_started(
      cast: cast_state.new(),
      caster: support.caster(),
      plans:,
      base: Spell4BaseId(3),
      now: support.at(ms: 1000),
    )
  let #(passive, _) =
    support.answered_by(
      state: passive,
      effects: passive_effects,
      at: 1000,
      struck:,
    )
  let #(passive_after_death, _) =
    cast.died(
      cast: passive,
      caster: support.dead_caster(),
      now: support.at(ms: 2000),
    )
  let ends = creature_view.ViewEnds(unit_id: 20, life: 3, cast_id: id)
  let #(passive_cast, _) = case cast_state.holders(cast: passive) {
    [#(passive_id, _)] -> #(passive_id, Nil)
    _ -> panic as "the passive is the one cast the state holds"
  }
  list.each(
    [
      #(
        "a live cast whose last node ends by time finishes, and its view ends",
        compared_in_turn(states: [held, finished]),
        [[told_view(id:, ends_ms: 4000)], [ends]],
      ),
      #(
        "the caster's death ends every cast, and each view",
        compared_in_turn(states: [held, dead]),
        [[told_view(id:, ends_ms: 4000)], [ends]],
      ),
      #(
        "the caster leaving the world ends every told view",
        compared_in_turn(states: [held, left]),
        [[told_view(id:, ends_ms: 4000)], [ends]],
      ),
      #(
        "the passive a death sets aside and puts back holds its node throughout: no change",
        compared_in_turn(states: [passive, passive_after_death]),
        [
          [
            view_set(
              unit_id: 20,
              life: 3,
              view: creature_view_of(
                cast_id: passive_cast,
                spell4_id: 101,
                primary_target: 7,
                unit_id: 20,
                count: 1,
                effect_id: 2,
                starts_ms: 1000,
                ends_ms: 4000,
              ),
            ),
          ],
          [],
        ],
      ),
    ],
    fn(row) {
      assert row.1 == row.2 as row.0
    },
  )
}

/// The set of the area buff's cast `id` on the creature 20 of life 3, struck at 1000, ending
/// at `ends_ms`.
fn told_view(id id: Int, ends_ms ends_ms: Int) -> creature_view.Change {
  view_set(
    unit_id: 20,
    life: 3,
    view: creature_view_of(
      cast_id: id,
      spell4_id: 101,
      primary_target: 7,
      unit_id: 20,
      count: 1,
      effect_id: 2,
      starts_ms: 1000,
      ends_ms:,
    ),
  )
}

/// The cast's live node on each of units 20 to 24 as the draw says: its effects (none, a
/// listed one with a life, or one that only gives the node its life), whether a round
/// struck it as a creature (and its life), and its count.
fn node_drawn(
  unit_id unit_id: Int,
  draw draw: #(Int, Bool, Int, Int),
) -> lasting.Node {
  let #(kind, stamped, count, life) = draw
  lasting.Node(
    unit_id:,
    count:,
    life: lasting.EndsAt(ms: 4000),
    effects: case kind {
      0 -> []
      1 -> [
        Listed(
          effect_id: Spell4EffectsId(2),
          row: LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 3000)),
        ),
      ]
      _ -> [
        LifeOnly(row: LastingRow(
          delay_ms: 0,
          lasts: lasts.For(duration_ms: 3000),
        )),
      ]
    },
    armed_ms: 1000,
    held_until_ms: option.None,
    struck: case stamped {
      True -> option.Some(lasting.StruckCreature(life:))
      False -> option.None
    },
  )
}

/// Whatever the caster's casts hold and whatever the creatures were told before, the changes
/// `creature_view.compared` gives take the told map to exactly the nodes that list a target and
/// a round struck as a creature, whichever way a node came or left the state; a second
/// compare gives none (`creature_view`'s invariant).
pub fn the_views_told_equal_what_the_caster_holds_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(base, effects) =
    support.press(
      plans: channel_before_its_first_go(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  qcheck.given(
    qcheck.tuple2(
      qcheck.list_from(qcheck.tuple5(
        qcheck.bounded_int(from: 20, to: 24),
        qcheck.bounded_int(from: 0, to: 2),
        qcheck.bool(),
        qcheck.bounded_int(from: 1, to: 3),
        qcheck.bounded_int(from: 1, to: 9),
      )),
      qcheck.list_from(qcheck.tuple4(
        qcheck.bounded_int(from: 20, to: 25),
        qcheck.bounded_int(from: 1, to: 2),
        qcheck.bounded_int(from: 1, to: 9),
        qcheck.bounded_int(from: 1, to: 3),
      )),
    ),
    fn(drawn) {
      let #(nodes, earlier) = drawn
      let held =
        cast_tick.with_nodes(
          cast: base,
          cast_id: id,
          nodes: dict.from_list(
            list.map(nodes, fn(node) {
              let #(unit_id, kind, stamped, count, life) = node
              #(
                unit_id,
                node_drawn(unit_id:, draw: #(kind, stamped, count, life)),
              )
            }),
          ),
        )
      let told_before =
        dict.from_list(
          list.map(earlier, fn(entry) {
            let #(unit_id, cast_choice, life, count) = entry
            #(
              #(
                case cast_choice {
                  1 -> id
                  _ -> 5
                },
                unit_id,
              ),
              cast_state.Told(
                life:,
                target: unit_casts.ViewTarget(unit_id:, count:, effects: []),
              ),
            )
          }),
        )
      let #(compared, changes) =
        creature_view.compared(
          cast: cast_state.State(..held, creature_told: told_before),
          caster_unit_id: 7,
        )
      let applied =
        list.fold(changes, told_before, fn(told, change) {
          case change {
            creature_view.ViewSet(unit_id:, life:, view:) ->
              case view.targets {
                [target] ->
                  dict.insert(
                    told,
                    #(view.cast_id, unit_id),
                    cast_state.Told(life:, target:),
                  )
                [] | [_, ..] -> told
              }
            creature_view.ViewEnds(unit_id:, cast_id:, ..) ->
              dict.delete(told, #(cast_id, unit_id))
          }
        })
      let expected =
        dict.from_list(
          list.map(nodes, fn(node) {
            let #(unit_id, kind, stamped, _, life) = node
            #(unit_id, #(kind, stamped, life))
          }),
        )
        |> dict.to_list
        |> list.filter_map(fn(entry) {
          case entry.1 {
            #(1, True, life) -> Ok(#(#(id, entry.0), life))
            _ -> Error(Nil)
          }
        })
        |> dict.from_list
      assert dict.map_values(applied, fn(_, told) { told.life }) == expected
        as "the changes take the told map to the nodes that list a target and a creature round"
      assert compared.creature_told == applied
        as "the state records what it told"
      assert creature_view.compared(cast: compared, caster_unit_id: 7).1 == []
        as "a second compare with no step between gives none"
    },
  )
}

// ---- an aura cast's end ----
//
// A castMethod 10 spell's buff runs from the cast's start to its spellDuration
// (`Spell4.spellDuration`, `0x1407180c0`); the client ends no node on time, so the server
// sends the 0x7fe then (`cast.target_node_end`).

/// Nullifier (Spell4Base 47675, Spell4 70757) as the Medic's only ability: its Proxy 180619
/// starts the field 58868 (castMethod 10, spellDuration 6000) on the caster.
fn nullifier_caster() -> cast_state.Caster {
  cast_state.Caster(
    ..support.caster(),
    abilities: [Spell4BaseId(47_675)],
    book: [Spell4BaseId(47_675)],
  )
}

/// The cast id the 0x7ff of the field 58868 names in the effects.
fn field_cast_id(effects effects: List(Effect)) -> Int {
  support.started_cast_id(spell4_id: 58_868, effects:)
}

/// The times at which the steps write a 0x7fe naming the cast, and a 0x811 naming it.
fn ended_at(
  steps steps: List(#(Int, List(Effect))),
  cast_id cast_id: Int,
) -> #(List(Int), List(Int)) {
  let times_of = fn(named: fn(List(cast_state.Effect)) -> Bool) {
    list.filter_map(steps, fn(step) {
      case named(step.1) {
        True -> Ok(step.0)
        False -> Error(Nil)
      }
    })
  }
  #(
    times_of(fn(effects) {
      list.contains(support.finished_ids(support.writes(effects:)), cast_id)
    }),
    times_of(fn(effects) {
      list.any(support.removed_targets(support.writes(effects:)), fn(removal) {
        removal.0 == cast_id
      })
    }),
  )
}

pub fn nullifiers_field_cast_finishes_at_its_spell_duration_with_the_0x7fe_alone_and_a_second_start_replaces_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = spell_plan.plans_with_later(tables: fixture_tables.shared())
  let caster = nullifier_caster()
  let #(state, effects) =
    support.press_as(plans:, state: cast_state.new(), caster:, bag: 0, at: 1000)
  let first = field_cast_id(effects:)
  // A second press of 70757 is refused by its cooldown of 8000, so the second start of the
  // field is Proxy 180619 fired again, 2000 ms after the press.
  let assert Ok(nullifier) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(47_675))
    as "the plans hold Nullifier"
  let assert Ok(proxy) =
    list.find_map(nullifier.effects, fn(planned) {
      case planned.kind {
        spell_plan.ProxyEffect(proxy:) -> Ok(proxy)
        _ -> Error(Nil)
      }
    })
    as "Nullifier holds the Proxy that starts its field"
  let #(state, _, start) =
    cast_state.armed(
      cast: state,
      due: cast_state.StartChild(
        root: Spell4Id(70_757),
        parent: Spell4Id(70_757),
        primary_target: caster.unit_id,
        named_player: option.None,
        proxy:,
        counted_with: cast_state.WithNothing,
        from: option.None,
        fired: False,
      ),
      after_ms: 2000,
    )
  // The field's Proxy 141450 asks for the units inside the box each second, and the connection
  // answers; nobody stands in it here.
  let #(_, fired) =
    support.run_timers_finding(
      caster:,
      state:,
      effects: list.append(effects, [start]),
      from_ms: 1000,
      until_ms: 20_000,
      units: dict.new(),
      found_by: fn(_) { [] },
    )
  let steps = list.map(fired, fn(step) { #(step.at_ms, step.effects) })
  let assert [second] =
    list.filter_map(steps, fn(step) {
      case step.0 == 3000 {
        True -> Ok(field_cast_id(effects: step.1))
        False -> Error(Nil)
      }
    })
    as "the second start of the field is at 3000"
  assert ended_at(steps:, cast_id: first) == #([3000], [3000])
    as "the second start takes the first field off (group 1519, cap 1): 0x811, then its 0x7fe at once, and its own end at 7000 never comes"
  assert ended_at(steps:, cast_id: second) == #([9000], [])
    as "the second field ends 6000 ms after its own start, with the 0x7fe alone (text 574032: lasting auraDuration)"
}

pub fn nullifiers_field_asks_each_second_for_six_ticks_and_each_answer_starts_an_affliction_on_each_unit_found_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 141450 (tickTime 1000, flags 2) in the field 58868 (spellDuration 6000) names the
  // Affliction 77099, so the field, pressed at 1000, asks for its units at 2000 to 7000 and
  // the sixth ask fires before the field's own 0x7fe at 7000 (text 574032;
  // `table_rows -- Spell4Effects 141450 -- Spell4 58868`).
  let plans = spell_plan.plans_with_later(tables: fixture_tables.shared())
  let caster = nullifier_caster()
  let #(state, effects) =
    support.press_as(plans:, state: cast_state.new(), caster:, bag: 0, at: 1000)
  let field = field_cast_id(effects:)
  let #(_, fired) =
    support.run_timers_finding(
      caster:,
      state:,
      effects:,
      from_ms: 1000,
      until_ms: 20_000,
      units: dict.new(),
      found_by: fn(_) { [21, 22] },
    )
  let asks =
    list.flat_map(fired, fn(step) {
      list.map(step.found, fn(asked) { #(step.at_ms, asked) })
    })
  assert list.map(asks, fn(ask) { ask.0 })
    == [2000, 3000, 4000, 5000, 6000, 7000]
    as "one ask each second for the six seconds of the field, and no seventh"
  assert list.map(asks, fn(ask) { { ask.1 }.tick }) == [1, 2, 3, 4, 5, 6]
  let assert [#(_, first), ..] = asks
  assert first.cast_id == field
    && first.spell4_id == Spell4Id(58_868)
    && first.effect_id == Spell4EffectsId(141_450)
    && first.primary_target == caster.unit_id
    && first.started_at == area.pose_of(place: caster.place)
    as "the first ask names the field, the row, the caster as the unit the row ticks on and the pose the press began at"
  let steps = list.map(fired, fn(step) { #(step.at_ms, step.effects) })
  let afflictions = support.starts_of(steps:, spell4_id: 77_099)
  assert support.times_of(starts: afflictions)
    == [
      2000,
      2000,
      3000,
      3000,
      4000,
      4000,
      5000,
      5000,
      6000,
      6000,
      7000,
      7000,
    ]
    as "each answer starts the Affliction on each of the two units found: 12 children"
  list.each(afflictions, fn(child) {
    assert { child.1 }.parent_spell4_id == 58_868
      && { child.1 }.root_spell4_id == 70_757
      as "opcode.0x7ff.root_parent: the field is the parent and Nullifier the root"
  })
  assert list.map(afflictions, fn(child) { { child.1 }.primary_target_unit_id })
    |> list.unique
    |> list.sort(int.compare)
    == [21, 22]
    as "each child is made on a unit found"
  assert ended_at(steps:, cast_id: field).0 == [7000]
    as "the field's 0x7fe at 7000 follows the sixth tick's children (ticking.ending_with_node)"
}

/// A spell of base 3 with a cast time of 1500 ms and an aura of 6000 ms whose go holds an
/// until-removed Fluff on the caster. The committed fixture holds no method-10 spell with a
/// cast time (120 of the 681 method-10 spells that have an aura and an until-removed row do,
/// `table_rows -- Spell4`), so the spell is planted; it is pressed as a Normal spell because
/// the rule builds no ability of method 10, and the rule reads the aura from `aura_ms` alone.
fn aura_with_a_cast_time() -> Spell {
  spell_plan.Spell(
    ..buff(spell4_id: 77_117, base: 3, lasting: [
      fluff(
        id: 200_469,
        aim: spell_plan.AimsAtCaster,
        lasts: lasts.UntilRemoved,
      ),
    ]),
    cast_time_ms: 1500,
    aura_ms: option.Some(6000),
  )
}

pub fn an_aura_counts_from_the_casts_start_and_not_from_its_go_test() -> Nil {
  use <- owned_test.run(5000)
  // A node given at the go at 2500 of a cast started at 1000 ends at 7000, the start plus the
  // aura; a count from the go would end it at 8500 (`0x1407180c0`: the buff's length runs from
  // the client's clock at the 0x7ff, `0x14053d1f0`).
  let aimed =
    aimed_at_caster(
      reached: [
        reached_on_caster(
          id: 200_469,
          kind: spell_plan.LastingEffect(Lasting(
            effect_id: Spell4EffectsId(200_469),
            phase_flags: -1,
            aim: spell_plan.AimsAtCaster,
            row: LastingRow(delay_ms: 0, lasts: lasts.UntilRemoved),
            condition: Always,
            tag: spend.always,
          )),
          product: cast_state.Plain,
        ),
      ],
      restrictions: [],
      ticking: [],
    )
  let assert Ok(node) =
    cast_tick.node_of(
      spell: aura_with_a_cast_time(),
      held: option.None,
      aimed:,
      unit_id: 7,
      started_ms: 1000,
      now_ms: 2500,
    )
  assert node.life == lasting.EndsAt(ms: 7000)
    as "the aura ends 6000 ms after the cast's start, not after its go"
  let plans = support.plans_of([aura_with_a_cast_time()])
  let #(state, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  assert support.refusals(effects:) == [] as "the press is taken"
  let id = support.pressed_id(effects:)
  let #(_, steps) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.map(steps, fn(step) {
      #(step.0, support.finished_ids(support.writes(effects: step.1)))
    })
    == [#(2500, []), #(7000, [id])]
    as "the go at 2500 gives the node; the cast's 0x7fe comes at 7000, 6000 ms after its press"
}

/// A Proxy aimed at the caster that casts a spell at each tick of `schedule`.
fn periodic_proxy(schedule schedule: ticking.Schedule) -> spell_plan.Proxy {
  spell_plan.Proxy(
    effect_id: Spell4EffectsId(210_304),
    delay_ms: 0,
    phase_flags: -1,
    condition: Always,
    tag: spend.always,
    target: spell_plan.OnCaster,
    spell: support.child(spell4_id: 79_757, base: 79_757),
    gains: [],
    period: option.Some(spell_plan.Periodic(schedule:, persistence: option.None)),
  )
}

pub fn the_node_of_a_holder_with_only_an_open_proxy_lasts_until_removed_or_until_its_aura_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let timed =
    ticking.Schedule(
      delay_ms: 1000,
      tick_ms: 1000,
      duration_ms: 4000,
      count: ticking.Ticks(4),
    )
  let caster = support.caster()
  list.each(
    [
      #(
        "a holder with only an open Proxy has a node that lasts until removed",
        [support.open_schedule(delay_ms: 1000, tick_ms: 1000)],
        option.None,
        lasting.UntilRemoved,
      ),
      #(
        "as an aura of 6000 ms started at 1000 its node ends with the aura",
        [support.open_schedule(delay_ms: 1000, tick_ms: 1000)],
        option.Some(6000),
        lasting.EndsAt(ms: 7000),
      ),
      #(
        "an aura that ends at or before the go gives no end (the client reads a sum not later than now as none)",
        [support.open_schedule(delay_ms: 1000, tick_ms: 1000)],
        option.Some(1500),
        lasting.UntilRemoved,
      ),
      #(
        "a finite Proxy keeps the node its delay plus durationTime long",
        [timed],
        option.None,
        lasting.EndsAt(ms: 2500 + 1000 + 4000),
      ),
      #(
        "an open and a finite Proxy together: the open one decides",
        [timed, support.open_schedule(delay_ms: 1000, tick_ms: 1000)],
        option.None,
        lasting.UntilRemoved,
      ),
    ],
    fn(row) {
      let #(reason, schedules, aura_ms, expected) = row
      let proxies =
        list.map(schedules, fn(schedule) { periodic_proxy(schedule:) })
      let spell =
        spell_plan.Spell(
          ..support.with_effects(
            spell: support.child(spell4_id: 79_753, base: 3),
            kinds: list.map(proxies, spell_plan.ProxyEffect),
          ),
          aura_ms:,
        )
      let aimed =
        aimed_at_caster(
          reached: [],
          restrictions: [],
          ticking: support.proxies_ticking_on_the_caster(proxies:, caster:),
        )
      let assert Ok(node) =
        cast_tick.node_of(
          spell:,
          held: option.None,
          aimed:,
          unit_id: caster.unit_id,
          started_ms: 1000,
          now_ms: 2500,
        )
        as reason
      assert node.life == expected as reason
    },
  )
}
