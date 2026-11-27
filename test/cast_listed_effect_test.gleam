//// The cast rule (`genesis_prime/game/cast`) for the Scale (18), RavelSignal (81) and
//// UnitPropertyConversion (145) rows the plan reads. Each spell holds the rows as the plan
//// reads them from planted Spell4Effects rows (`spell_plan_listed_effect_test`), on a clock
//// the test drives. Expected values come from these places:
//// - `opcode.0x7f4.target_info`, `opcode.0x7f4.instance_count` and
////   `opcode.0x7f4.effect_time`: a go's effect info names the effect row, the result bit,
////   the instance count 1 for one application and the fourth value 0, which leaves the
////   lifetime to the client's own rule (delay plus durationTime).
//// - `cast.target_node_end`: the client ends no buff on time, so the server holds the
////   0x7fe of a cast with a node that has life left; an early 0x7fe would undo the scale.
//// - `Spell4Effects.effectType.18`: the client resizes any unit the go names the effect on,
////   so a Scale row aimed at the area is listed on each struck unit.
//// - `Spell4Effects.effectType.81` and `Spell4Effects.prerequisiteIdTargetApply`: an effect
////   lands only on the units that pass its gate; 11311 is two type 109 conditions, the
////   worlds 1535 and 3022, of which one is enough (`table_rows -- Prerequisite 11311`).
//// - `Spell4Effects.effectType.145` and the modifiers' rule "until removed": row 229304 of
////   the Engineer passive 45000 is flags 2, so its conversion starts at the go and has no
////   end timer; `cast.died` ends every modifier but the innate passive's.

import cast_support as support
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/lasts
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Plans, type Spell}
import genesis_prime/game/spend
import genesis_prime/game/unit_news.{CastFinished}
import genesis_prime/game/unit_properties
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{
  Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import gleam/list
import gleam/string
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables

const one_point_three = 1_067_869_798

const a_quarter = 1_048_576_000

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

// The planted base 1 is bag index 8.
const bag_of_base_1 = 8

// Each planted row has an id no client row holds, since a planted row of a client id
// would replace the client's row (`spell_tables.rows_with_effect`); the comments name the
// client row whose shape it takes.

/// A spell of no cast time and no cooldown that holds the lasting and modifier rows the
/// plan reads from this planted row, and no other.
fn spell_of(
  row row: List(Cell),
  id id: Int,
  spell4_id spell4_id: Int,
  base base: Int,
) -> Spell {
  let assert Ok(planned) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the plan builds"
  let wanted = Spell4EffectsId(id)
  support.with_effects(
    spell: support.with_effects(
      spell: support.child(spell4_id:, base:),
      kinds: list.map(
        list.filter(
          spell_plan.payloads(spell: planned, as_kind: spell_plan.as_lasting),
          fn(lasting) { lasting.effect_id == wanted },
        ),
        spell_plan.LastingEffect,
      ),
    ),
    kinds: list.map(
      list.filter(
        spell_plan.payloads(spell: planned, as_kind: spell_plan.as_modifier),
        fn(modifier) { modifier.effect_id == wanted },
      ),
      spell_plan.ModifierEffect,
    ),
  )
}

// ---- a Scale row ----

pub fn a_go_lists_a_scale_row_on_the_caster_and_the_nodes_life_is_the_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  // 109482's shape: the caster, 1.3 over 500 ms, 8000 ms, here with a delay of 120 ms.
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 99_071,
        effect_type: 18,
        target_flags: 1,
        columns: [
          #("delayTime", Integer(120)),
          #("durationTime", Integer(8000)),
          #("dataBits00", Integer(one_point_three)),
          #("dataBits01", Integer(500)),
          #("dataBits02", Integer(1000)),
        ],
      ),
      id: 99_071,
      spell4_id: 42_908,
      base: 3,
    )
  let #(_, effects) =
    support.press(
      plans: support.plans_of([spell]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [info] = support.go_targets(effects:)
  assert info.unit_id == 7 as "the caster is the unit the row aims at"
  assert info.instance_count == 1
    as "one application is a count of 1 (opcode.0x7f4.instance_count)"
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 99_071,
        instance_id: 1,
        delay_ms: 120,
        lifetime_ms: 0,
        result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
      ),
    ]
    as "the row's delay, the result bit and the fourth value 0 that leaves the lifetime to the client (opcode.0x7f4.effect_time)"
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [8120]
    as "the node lives for the row's delay and durationTime from the go"
}

pub fn a_spell_whose_only_row_with_a_life_is_a_scale_row_lingers_until_the_rows_end_and_then_finishes_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 99_071,
        effect_type: 18,
        target_flags: 1,
        columns: [
          #("durationTime", Integer(8000)),
          #("dataBits00", Integer(one_point_three)),
        ],
      ),
      id: 99_071,
      spell4_id: 42_908,
      base: 3,
    )
  let #(state, effects) =
    support.press(
      plans: support.plans_of([spell]),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the client ends no buff on time, so an early 0x7fe would undo the scale (cast.target_node_end)"
  let assert [#(timer, 8000)] = support.started_timers(effects:)
  let #(state, early) = support.fired(state:, timer:, at: 8999)
  assert support.finished_ids(support.writes(effects: early)) == []
    as "a timer that fires with life left writes nothing"
  let assert [#(timer, 1)] = support.started_timers(effects: early)
  let #(_, ended) = support.fired(state:, timer:, at: 9000)
  assert support.finished_ids(support.writes(effects: ended)) == [id]
    as "the 0x7fe comes with the end of the row's 8000 ms"
}

pub fn a_scale_row_aimed_at_the_area_is_listed_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 99_072,
        effect_type: 18,
        target_flags: 4,
        columns: [
          #("durationTime", Integer(5000)),
          #("dataBits00", Integer(one_point_three)),
        ],
      ),
      id: 99_072,
      spell4_id: 101,
      base: 3,
    )
  let #(state, effects) =
    support.pressed_raw_in(
      plans: support.plans_of([spell]),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_by(state:, effects:, at: 1000, struck: [
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
    ])
  assert list.map(support.go_targets(effects:), fn(info) {
      #(
        info.unit_id,
        list.map(info.effects, fn(effect) { effect.spell4_effects_id }),
      )
    })
    == [#(20, [99_072]), #(21, [99_072])]
    as "Spell4Effects.effectType.18: the client resizes any unit the go names the effect on, so each struck unit's info lists the row"
}

// ---- a RavelSignal row ----

pub fn a_ravel_signal_row_behind_a_target_prerequisite_is_listed_only_for_a_caster_that_passes_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // 91018 as the client holds it: the caster, behind target apply prerequisite 11311, one
  // type 109 condition on each of the worlds 1535 and 3022 (any one of them is enough).
  let spell =
    spell_of(
      row: spell_tables.effect_row_with(
        id: 99_073,
        effect_type: 81,
        target_flags: 1,
        columns: [
          #("dataBits00", Integer(1)),
          #("dataBits01", Integer(13_076)),
          #("durationTime", Integer(1000)),
          #("prerequisiteIdTargetApply", Integer(11_311)),
        ],
      ),
      id: 99_073,
      spell4_id: 38_784,
      base: 3,
    )
  let in_world = fn(world_id) {
    let caster = support.caster()
    cast_state.Caster(
      ..caster,
      player: prerequisite.Player(..caster.player, world_id:),
    )
  }
  let #(_, in_a_listed_world) =
    support.press_as(
      plans: support.plans_of([spell]),
      state: cast_state.new(),
      caster: in_world(1535),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.listed_effect_ids(effects: in_a_listed_world) == [99_073]
    as "Prerequisite.prerequisiteTypeId.109: the caster is in world 1535, which gate 11311 names, so the row lands on it"
  let #(_, in_another_world) =
    support.press_as(
      plans: support.plans_of([spell]),
      state: cast_state.new(),
      caster: in_world(3460),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.listed_effect_ids(effects: in_another_world) == []
    as "the caster is in world 3460, which gate 11311 does not name, so the row is not applied"
  assert list.filter(support.logs(effects: in_another_world), fn(line) {
      string.contains(line.1, "99073")
    })
    == []
    as "a gate the caster fails writes no line: the gate is read, and the row is not an unread one"
}

// ---- a PropertyConversion row ----

/// The Engineer passive's shape: 229304, flags 2, from property 47 to 60 at a quarter.
fn passive() -> Spell {
  spell_of(
    row: spell_tables.effect_row_with(
      id: 99_074,
      effect_type: 145,
      target_flags: 1,
      columns: [
        #("flags", Integer(2)),
        #("dataBits00", Integer(47)),
        #("dataBits01", Integer(60)),
        #("dataBits02", Integer(a_quarter)),
      ],
    ),
    id: 99_074,
    spell4_id: 250_001,
    base: 250_001,
  )
}

fn caster_of_passive() -> Caster {
  cast_state.Caster(..support.caster(), abilities: [Spell4BaseId(250_001)])
}

/// The passive started at the time, its go answered with no unit struck.
fn passive_started(plans plans: Plans, at ms: Int) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.standing_started(
      cast: cast_state.new(),
      caster: caster_of_passive(),
      plans:,
      base: Spell4BaseId(250_001),
      now: support.at(ms:),
    )
  support.answered_as(
    caster: caster_of_passive(),
    state:,
    effects:,
    at: ms,
    struck: [],
    rolls: [],
  )
}

fn conversion() -> unit_properties.Modifier {
  unit_properties.Conversion(
    from: UnitProperty2Id(47),
    to: UnitProperty2Id(60),
    share: 0.25,
  )
}

pub fn the_innate_passives_go_lists_its_conversion_on_the_caster_and_starts_it_with_no_end_timer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, effects) =
    passive_started(plans: support.plans_of([passive()]), at: 1000)
  assert support.listed_effect_ids(effects:) == [99_074]
    as "the planted row 99074 is listed on the caster"
  let assert [#(source, modifier)] = support.property_starts(effects:)
  assert source.effect_id == Spell4EffectsId(99_074)
  assert modifier == conversion()
  assert support.started_timers(effects:) == []
    as "flags 2: the conversion lasts until it is removed, so no end timer and no node end"
}

pub fn the_casters_death_leaves_the_innate_passives_conversion_live_test() -> Nil {
  use <- owned_test.run(60_000)
  let plans = support.plans_of([passive()])
  // The control: the same spell pressed as an ordinary ability, whose conversion a death
  // ends with the cast.
  let #(pressed, _) =
    support.pressed_in(
      plans:,
      state: cast_state.new(),
      caster: caster_of_passive(),
      bag_index: 0,
      target: 0,
      at: 1000,
    )
  let #(_, ordinary_death) =
    cast.died(
      cast: pressed,
      caster: cast_state.Caster(..caster_of_passive(), dead: True),
      now: support.at(ms: 5000),
    )
  assert list.length(support.caster_change_ends(effects: ordinary_death)) == 1
    as "the control: a death ends an ordinary cast's modifier"
  let #(passive_state, _) = passive_started(plans:, at: 1000)
  let #(_, died) =
    cast.died(
      cast: passive_state,
      caster: cast_state.Caster(..caster_of_passive(), dead: True),
      now: support.at(ms: 5000),
    )
  assert support.caster_change_ends(effects: died) == []
    as "cast.died: every modifier ends but the innate passive's, so its conversion stays"
}

// ---- an ItemVisualSwap row ----

/// The Hazmat Suit Locker's activate spell 45726 with its one type 76 row 106570.
fn hazmat_suit() -> Plans {
  support.plans_of([
    support.client_lasting(spell4_id: 45_726, base: 3, effect_ids: [106_570]),
  ])
}

/// The unit each go names, with the effects it lists on each and their delays.
fn swaps_of(
  effects effects: List(Effect),
) -> List(#(Int, List(#(Int, Int, Int)))) {
  list.map(support.go_targets(effects:), fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) {
        #(effect.spell4_effects_id, effect.delay_ms, effect.lifetime_ms)
      }),
    )
  })
}

pub fn a_go_lists_an_item_visual_swap_row_on_the_caster_with_its_delay_and_lifetime_0_test() -> Nil {
  use <- owned_test.run(60_000)
  // 122321 (Spell4 48373, Blessing of Dominus) aims at the caster with a delay of 4000
  // and a durationTime of 5000 (`table_rows -- Spell4Effects 122321`).
  let plans =
    support.plans_of([
      support.client_lasting(spell4_id: 48_373, base: 3, effect_ids: [122_321]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let assert [info] = support.go_targets(effects:)
  assert info.unit_id == 7
    as "the caster is the unit the row aims at (targetFlags 1)"
  assert info.instance_count == 1
    as "one application is a count of 1 (opcode.0x7f4.instance_count)"
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 122_321,
        instance_id: 1,
        delay_ms: 4000,
        lifetime_ms: 0,
        result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
      ),
    ]
    as "the row's delay 4000 and the fourth value 0 that leaves the lifetime to the client (opcode.0x7f4.effect_time)"
  let ids = list.map(support.writes(effects:), fn(frame) { frame.message_id })
  assert !list.contains(ids, 0x0933)
    as "the client swaps and restores the visual itself: the server sends no 0x933 (Spell4Effects.effectType.76)"
  assert support.property_starts(effects:) == []
    as "the server keeps no state for the swap"
  // 45726's own row, which has no delay, and the hazmat suit it gives the player.
  let #(_, effects) =
    support.press(
      plans: hazmat_suit(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert swaps_of(effects:) == [#(7, [#(106_570, 0, 0)])]
    as "`table_rows -- Spell4Effects 106570`: the caster, delayTime 0, listed with lifetime 0"
}

pub fn a_cast_whose_item_visual_swap_row_has_flags_2_lingers_and_writes_no_finish_by_time_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, effects) =
    support.press(
      plans: hazmat_suit(),
      state: cast_state.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.finished_ids(support.writes(effects:)) == []
    as "106570 has flags 2: its node lasts until removed, so the cast writes no 0x7fe after its go (cast.target_node_end)"
  assert support.started_timers(effects:) == []
    as "a node until removed arms no timer, so no time ends it"
  assert list.filter(support.tells(effects:), fn(told) {
      told.1 == CastFinished(cast_id: support.pressed_id(effects:))
    })
    == []
    as "the audience is told no end"
}

pub fn the_casters_death_ends_a_flags_2_item_visual_swap_node_with_the_finish_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, effects) =
    support.press(
      plans: hazmat_suit(),
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
    as "the server's choice: the client has no path that ends a buff on a unit's death (cast.target_node_end), so the node's cast ends with the caster"
  assert support.tells(effects: ended)
    == [
      #(ConnectionId(2), CastFinished(cast_id: id)),
      #(ConnectionId(3), CastFinished(cast_id: id)),
    ]
}

/// A press of the plans' ability of base 3 whose go finds the creature `unit_id` struck.
fn pressed_striking(
  plans plans: Plans,
  unit_id unit_id: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: ms,
    )
  support.answered_by(state:, effects:, at: ms, struck: [
    cast_state.Hit(
      unit_id:,
      unit: cast_state.HitCreature(life: 1),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  ])
}

pub fn a_timed_item_visual_swap_row_ends_its_node_with_the_finish_at_its_end_test() -> Nil {
  use <- owned_test.run(60_000)
  // 43533 (Spell4 26567): the primary target, delayTime 333, durationTime 10000, and the
  // spell's propertyFlags 0 make its lifetime 10333 from the go. A press of an ability
  // makes the caster its primary target (`cast.press_of`), so the row lands on the caster.
  let plans =
    support.plans_of([
      support.client_lasting(spell4_id: 26_567, base: 3, effect_ids: [43_533]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  assert swaps_of(effects:) == [#(7, [#(43_533, 333, 0)])]
    as "the go lists the row on the primary target, the caster, with its delay 333 and lifetime 0"
  assert support.finished_ids(support.writes(effects:)) == []
    as "the node has life left, so the finish waits"
  let assert [#(timer, 10_333)] = support.started_timers(effects:)
  let #(state, early) = support.fired(state:, timer:, at: 11_332)
  assert support.writes(effects: early) == []
    as "a timer that fires 1 ms before the lifetime (go at 1000 + 10333 = 11333) writes nothing"
  let assert [#(timer, 1)] = support.started_timers(effects: early)
  let #(_, ended) = support.fired(state:, timer:, at: 11_333)
  assert support.finished_ids(support.writes(effects: ended)) == [id]
    as "the finish comes at the end of the row's delay and duration"
}

pub fn a_timed_item_visual_swap_node_ends_with_targets_removed_while_another_node_lives_test() -> Nil {
  use <- owned_test.run(60_000)
  // The creature 20, struck by the go, holds a node of a Fluff effect aimed at the area
  // that ends at 20000 ms after the go, the stand-in for a longer buff of the same cast.
  let longer_buff =
    spell_plan.Lasting(
      effect_id: Spell4EffectsId(99_201),
      phase_flags: -1,
      aim: spell_plan.AimsAtArea,
      row: LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 20_000)),
      condition: spell_plan.Always,
      tag: spend.always,
    )
  let swap =
    support.client_lasting(spell4_id: 26_567, base: 3, effect_ids: [43_533])
  let plans =
    support.plans_of([
      support.with_effects(
        spell: swap,
        kinds: list.map(
          list.append(
            spell_plan.payloads(spell: swap, as_kind: spell_plan.as_lasting),
            [longer_buff],
          ),
          spell_plan.LastingEffect,
        ),
      ),
    ])
  let #(state, effects) = pressed_striking(plans:, unit_id: 20, at: 1000)
  let id = support.pressed_id(effects:)
  let assert [#(timer, 10_333)] = support.started_timers(effects:)
  let #(state, at_swap_end) = support.fired(state:, timer:, at: 11_333)
  assert support.removed_targets(support.writes(effects: at_swap_end))
    == [#(id, [7])]
    as "the swap's node on the caster ends first: 0x811 naming its unit"
  assert support.finished_ids(support.writes(effects: at_swap_end)) == []
    as "the struck creature's longer node keeps the cast live"
  let assert [#(timer, 9667)] = support.started_timers(effects: at_swap_end)
  let #(_, at_buff_end) = support.fired(state:, timer:, at: 21_000)
  assert support.finished_ids(support.writes(effects: at_buff_end)) == [id]
    as "the finish comes with the last node's end (go at 1000 + 20000)"
  assert support.removed_targets(support.writes(effects: at_buff_end)) == []
}

/// A spell whose go takes the casts of the Spell4 `selector` names off the caster.
fn remover(
  spell4_id spell4_id: Int,
  base base: Int,
  selector selector: lasting.Selector,
) -> Spell {
  support.removing(
    spell4_id:,
    base:,
    effect_id: 99_202,
    selector:,
    count: 1,
    condition: spell_plan.Always,
  )
}

pub fn a_force_remove_takes_off_a_flags_2_item_visual_swap_node_test() -> Nil {
  use <- owned_test.run(60_000)
  // The swap spell is of cast method Normal, as 45726's Spell4Base 29754 is (castMethod 0),
  // and holds its one node on the caster: a removal takes the node off with a 0x811, and
  // the client destroys a Normal cast itself when its last node goes (opcode.0x811,
  // `cast.node_off`), so the removal writes no 0x7fe.
  let plans =
    support.plans_of([
      support.client_lasting(spell4_id: 45_726, base: 3, effect_ids: [106_570]),
      remover(
        spell4_id: 301,
        base: 1,
        selector: lasting.Spell(Spell4Id(45_726)),
      ),
    ])
  let #(state, first) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects: first)
  let #(_, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert support.removed_targets(support.writes(effects: removal))
    == [#(id, [7])]
    as "the cast holds one node, on the caster: the whole node goes with a 0x811"
  assert !list.contains(
    support.finished_ids(support.writes(effects: removal)),
    id,
  )
    as "a Normal cast is destroyed by the client when its last node goes: no 0x7fe (opcode.0x811)"
}

pub fn an_item_visual_swap_row_with_no_delay_duration_or_flags_2_ends_with_the_cast_test() -> Nil {
  use <- owned_test.run(60_000)
  // 74394 (Spell4 36149): the caster, delayTime 0, durationTime 0, flags 0
  // (`table_rows -- Spell4Effects 74394`): the row has no life of its own.
  let plans =
    support.plans_of([
      support.client_lasting(spell4_id: 36_149, base: 3, effect_ids: [74_394]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast_state.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  assert swaps_of(effects:) == [#(7, [#(74_394, 0, 0)])]
    as "the go lists the row"
  assert support.finished_ids(support.writes(effects:)) == [id]
    as "no row has a life, so the cast finishes after its last go and the node ends with it"
  assert support.started_timers(effects:) == []
}
