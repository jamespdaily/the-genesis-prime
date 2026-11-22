//// A lasting cast whose spell's persistence condition stops holding ends
//// (`genesis_prime/game/cast` `persisted`). Expected values come from these places,
//// each named at its assertion:
//// - `Spell4.prerequisiteIdCasterPersistence`, `Spell4.prerequisiteIdTargetPersistence`:
////   the client never evaluates either column, it keeps them to word the results 282 and
////   283 (`0x1405648a0`); stopping a cast whose condition fails is the server's, so what
////   it sends is the server's choice from the client's messages: `opcode.0x7f9` fails a
////   cast with a result, destroys every node it holds (so its buff ends) and leaves it
////   filed, and `opcode.0x7fe` takes it out of the cast table
////   (`cast.target_node_end`).
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite 36425
////   29484 903`): the Spell Surge buff 47439 holds CasterPersistence 36425, slot 4 at least
////   25 (Spell Power), and Spell Surge 47273 holds CastGate 29484.
//// - A periodic Proxy's own persistence (`Spell4Effects.prerequisiteIdCasterApply`: the
////   client reads no effect row's persistence): the server ends the whole cast with the
////   spell column's frames (a guess), and checks it with the caster as the second unit, as
////   the effect rows' order has it (`Spell4Effects.prerequisiteIdTargetApply`) and not the
////   cast's primary target, which only the spell column's order uses. Augmented Blade's
////   stack removal 82838 ends with its last Kinetic Rage stack or when the toggle turns back
////   on (Prerequisite 38758, `Spell4.82838`, a guess: the client checks no persistence).
//// - The server's choices (the cast module's doc): the check runs at the end of each input
////   in the world; CasterPersistence before TargetPersistence; a failing cast ends as a
////   death ends one cast, with the caster's first unit and the cast's primary target the
////   second; a persistence of a type not read, and a target persistence on a creature,
////   keep the cast with one debug line for the spell.

import cast_support as support
import class_resource_support
import client_tables
import genesis_prime/client_connection.{CastFinished}
import genesis_prime/game/cast
import genesis_prime/game/cast/persist as cast_persist
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/class_resource
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spell_plan.{
  type Spell, Always, KeepsStealth, Spell, StealthRow,
}
import genesis_prime/game/spend
import genesis_prime/game/ticking.{Schedule, Ticks}
import genesis_prime/message/cast_result
import genesis_prime/message/spell_failed
import genesis_prime/message/spell_started
import genesis_prime/step.{type TimerId, ConnectionId, LogDebug}
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import prerequisite_support as prerequisites
import unitest

/// The bag indices of the planted bases 1 and 3 (`cast_support.abilities`).
const bag_of_base_1 = 8

const bag_of_base_3 = 11

/// Prerequisite 903, type 28 comparison 1: the caster in combat.
fn in_combat() -> Prerequisite {
  prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
}

fn unread() -> Prerequisite {
  prerequisites.single(id: 41_834, condition: #(
    prerequisites.unread_type(),
    1,
    10_518,
    1,
  ))
}

fn persisted(
  state state: State,
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  cast.persisted(cast: state, caster:, now: support.at(ms:))
}

/// Each 0x7f9 the effects write: the cast id, the result, the unit id and the bit.
fn failed(effects effects: List(Effect)) -> List(#(Int, Int, Int, Int)) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_failed.message_id {
      True -> {
        let assert Ok(failure) = spell_failed.decode(frame.body)
          as "a 0x7f9 the rule wrote decodes"
        Ok(#(
          failure.cast_id,
          cast_result.to_value(failure.result),
          failure.unit_id,
          failure.cut_visuals,
        ))
      }
      False -> Error(Nil)
    }
  })
}

/// The Spell4 id and the cast id of each 0x7ff the effects write (a child's start; a
/// press is confirmed by a 0x7fd, `cast_support.pressed_id`).
fn started(effects effects: List(Effect)) -> List(#(Int, Int)) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a 0x7ff the rule wrote decodes"
        Ok(#(start.spell4_id, start.cast_id))
      }
      False -> Error(Nil)
    }
  })
}

fn cast_id_of(spell4_id spell4_id: Int, effects effects: List(Effect)) -> Int {
  let assert Ok(#(_, cast_id)) =
    list.find(started(effects:), fn(start) { start.0 == spell4_id })
    as "the effects start a cast of the spell"
  cast_id
}

fn finished_ids(effects effects: List(Effect)) -> List(Int) {
  support.finished_ids(support.writes(effects:))
}

// ---- the Spell Surge buff ----

fn spellslinger(power power: Float) -> Caster {
  cast_state.Caster(
    ..support.caster_holding(resources: support.holding(
      class_id: 7,
      value: power,
    )),
    abilities: [Spell4BaseId(31_213)],
  )
}

pub fn a_step_that_leaves_spell_power_at_24_ends_the_spell_surge_buff_and_at_25_nothing_happens_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(client_tables.shared())
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: spellslinger(power: 25.0),
      bag: 0,
      at: 1000,
    )
  let buff = cast_id_of(spell4_id: 47_439, effects: pressed)
  let #(unchanged, nothing) =
    persisted(state:, caster: spellslinger(power: 25.0), at: 1100)
  assert nothing == [] && unchanged == state
    as "36425 holds at 25 Spell Power (slot 4 at least 25): nothing happens"
  let #(ended, effects) =
    persisted(state:, caster: spellslinger(power: 24.0), at: 1200)
  assert failed(effects:) == [#(buff, 282, 7, 0)]
    as "Prerequisite 36425 fails at 24: 0x7f9 {the buff's cast id, 282 Prereq_CasterPersistence, the caster, 0}"
  assert support.ids(frames: support.writes(effects:)) == [0x07F9, 0x07FE]
    && finished_ids(effects:) == [buff]
    as "then the 0x7fe that takes the cast out of the client's table (0x7f9 leaves it filed, opcode.0x7f9)"
  assert support.tells(effects:)
    == [
      #(ConnectionId(2), CastFinished(cast_id: buff)),
      #(ConnectionId(3), CastFinished(cast_id: buff)),
    ]
    as "each viewer is told the cast finished"
  let #(_, again) =
    persisted(state: ended, caster: spellslinger(power: 24.0), at: 1300)
  assert again == [] as "the cast is gone: a later step ends nothing"
  let #(_, second_press) =
    support.press_by(
      plans:,
      state: ended,
      caster: spellslinger(power: 24.0),
      bag: 0,
      at: 2000,
    )
  assert support.refusal_results(effects: second_press) == [151]
    as "the buff is gone, so at 24 Spell Power Spell Surge's own condition (29484) fails again"
}

// ---- a planted cast ----

/// A planted spell of base 3 with a 1000 ms cast time and a cast bar, whose cast is live
/// and the caster's current cast until its go, with this persistence.
fn casting_for_a_second(
  caster_persistence caster_persistence: option.Option(Prerequisite),
  target_persistence target_persistence: option.Option(Prerequisite),
) -> Spell {
  Spell(
    ..support.child(spell4_id: 7003, base: 3),
    cast_time_ms: 1000,
    cast_bar: spell_plan.ShowsCastBar,
    caster_persistence:,
    target_persistence:,
  )
}

/// A planted spell of base 3 with no cast time whose go holds a node on the caster for
/// a minute: it lingers, with a timer for the node's end.
fn lingering_for_a_minute(
  caster_persistence caster_persistence: option.Option(Prerequisite),
) -> Spell {
  support.with_effects(
    spell: Spell(..support.child(spell4_id: 7004, base: 3), caster_persistence:),
    kinds: [
      spell_plan.LastingEffect(spell_plan.Lasting(
        effect_id: Spell4EffectsId(1),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: LastingRow(delay_ms: 0, duration_ms: 60_000, until_removed: False),
        condition: Always,
        tag: spend.always,
      )),
    ],
  )
}

pub fn a_lingering_casts_nodes_end_timer_is_cancelled_when_its_persistence_ends_it_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      lingering_for_a_minute(caster_persistence: Some(in_combat())),
    ])
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: support.caster_in_combat(in_combat: True),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [#(nodes_end, 60_000)] = support.started_timers(effects: pressed)
    as "the lingering cast waits for its node's end on one timer"
  let #(_, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 2000,
    )
  assert support.cancelled_timers(effects:) == [nodes_end]
    as "the NodesEnd timer is cancelled with the cast (cast.target_node_end)"
  assert support.ids(frames: support.writes(effects:)) == [0x07F9, 0x07FE]
}

pub fn a_live_cast_whose_persistence_ends_clears_the_current_cast_cancels_its_go_and_starts_the_press_held_for_it_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: Some(in_combat()),
        target_persistence: None,
      ),
      support.child(spell4_id: 5001, base: 1),
    ])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [#(go, 1000)] = support.started_timers(effects: pressed)
    as "the cast waits for its go on a timer"
  // 400 ms of the current cast are left, inside the queue window: the press is held.
  let #(state, held) =
    support.press_by(
      plans:,
      state:,
      caster: fighting,
      bag: bag_of_base_1,
      at: 1600,
    )
  assert support.writes(effects: held) == []
  let #(ended, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1700,
    )
  assert list.contains(support.cancelled_timers(effects:), go)
    as "the go timer is cancelled"
  assert list.take(support.ids(frames: support.writes(effects:)), 3)
    == [0x07F9, 0x07FE, 0x07FD]
    as "the cast ends, and the current cast it cleared lets the held press start: it is confirmed with a 0x7fd"
  let #(_, free) =
    support.press_by(
      plans:,
      state: ended,
      caster: fighting,
      bag: bag_of_base_1,
      at: 5000,
    )
  assert support.refusal_results(effects: free) == []
    as "nothing blocks a later press"
}

pub fn a_persistence_of_a_type_not_read_keeps_the_cast_with_one_debug_line_for_the_spell_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: Some(unread()),
        target_persistence: None,
      ),
    ])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [#(go, _)] = support.started_timers(effects: pressed)
  let #(state, first) = persisted(state:, caster: fighting, at: 1100)
  assert list.map(support.logs(effects: first), fn(line) { line.0 })
    == [LogDebug]
    && failed(effects: first) == []
    as "the condition of a type the server does not read goes on with one debug line"
  let #(state, second) = persisted(state:, caster: fighting, at: 1200)
  assert second == [] as "one line for the spell, not one for each input"
  let #(_, went) = support.fired(state:, timer: go, at: 2000)
  assert list.contains(
    support.ids(frames: support.writes(effects: went)),
    0x07F4,
  )
    as "the cast's go still comes"
}

pub fn a_target_persistence_on_a_cast_whose_primary_target_is_a_creature_is_not_checked_test() -> Nil {
  use <- owned_test.run(5000)
  // A child aimed at each struck unit has that unit as its primary target (`cast.child`).
  let child =
    Spell(
      ..casting_for_a_second(
        caster_persistence: None,
        target_persistence: Some(in_combat()),
      ),
      spell4_id: id.Spell4Id(7005),
    )
  let parent =
    support.with_effects(spell: support.child(spell4_id: 7006, base: 3), kinds: [
      spell_plan.ProxyEffect(
        spell_plan.Proxy(
          period: None,
          effect_id: Spell4EffectsId(2),
          delay_ms: 0,
          phase_flags: -1,
          condition: spell_plan.Always,
          tag: spend.always,
          target: spell_plan.OnEachStruck,
          spell: child,
          gains: [],
        ),
      ),
    ])
  let plans = support.plans_of([parent])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, _) =
    support.answered_as(
      caster: fighting,
      state:,
      effects: raw,
      at: 1000,
      struck: [
        cast_state.Hit(
          unit_id: 99,
          unit: cast_state.HitCreature(life: 1, struck_at_ms: 0),
          descriptions: [],
          controls: [],
          armor_removed: 0,
          ticking: [],
        ),
      ],
      rolls: [],
    )
  let #(state, first) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1100,
    )
  assert failed(effects: first) == []
    as "the connection holds no creature's state: the condition is not checked"
  assert list.map(support.logs(effects: first), fn(line) { line.0 })
    == [LogDebug]
    as "with one debug line for the spell"
  let #(_, second) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1200,
    )
  assert second == []
}

pub fn a_target_persistence_on_a_cast_the_caster_is_the_target_of_ends_it_with_283_and_the_caster_one_is_checked_first_test() -> Nil {
  use <- owned_test.run(5000)
  let fighting = support.caster_in_combat(in_combat: True)
  let target_only =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: None,
        target_persistence: Some(in_combat()),
      ),
    ])
  let #(state, pressed) =
    support.press_by(
      plans: target_only,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let cast_id = support.pressed_id(effects: pressed)
  let #(_, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1100,
    )
  assert failed(effects:) == [#(cast_id, 283, 7, 0)]
    as "the primary target is the caster: TargetPersistence is checked, and fails with 283"
  let both =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: Some(in_combat()),
        target_persistence: Some(in_combat()),
      ),
    ])
  let #(state, pressed) =
    support.press_by(
      plans: both,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let cast_id = support.pressed_id(effects: pressed)
  let #(_, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1100,
    )
  assert failed(effects:) == [#(cast_id, 282, 7, 0)]
    as "282 before 283, as CasterCast is checked before TargetCast"
}

// ---- several casts ----

pub fn two_casts_whose_persistence_fails_in_one_input_end_in_cast_id_order_test() -> Nil {
  use <- owned_test.run(5000)
  let first_spell =
    Spell(
      ..support.child(spell4_id: 7010, base: 1),
      cast_time_ms: 1000,
      caster_persistence: Some(in_combat()),
    )
  let second_spell =
    Spell(
      ..support.child(spell4_id: 7011, base: 3),
      cast_time_ms: 1000,
      caster_persistence: Some(in_combat()),
    )
  let plans = support.plans_of([first_spell, second_spell])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, one) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(state, two) =
    support.press_by(
      plans:,
      state:,
      caster: fighting,
      bag: bag_of_base_1,
      at: 1100,
    )
  let second_id = support.pressed_id(effects: one)
  let first_id = support.pressed_id(effects: two)
  let #(_, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1200,
    )
  assert list.map(failed(effects:), fn(failure) { failure.0 })
    == list.sort([first_id, second_id], int.compare)
    as "both end in the one input, the lower cast id first"
  assert finished_ids(effects:) == list.sort([first_id, second_id], int.compare)
}

pub fn a_cast_whose_type_15_persistence_names_another_casts_spell_ends_in_the_same_input_test() -> Nil {
  use <- owned_test.run(5000)
  // B, the lower cast id, needs the caster in combat; A needs the caster to be the
  // target of a live cast of B's spell (type 15, comparison 1).
  let spell_b =
    Spell(
      ..support.child(spell4_id: 7021, base: 3),
      cast_time_ms: 1000,
      caster_persistence: Some(in_combat()),
    )
  let spell_a =
    Spell(
      ..support.child(spell4_id: 7020, base: 1),
      cast_time_ms: 1000,
      caster_persistence: Some(
        prerequisites.single(id: 1, condition: #(15, 1, 0, 7021)),
      ),
    )
  let plans = support.plans_of([spell_a, spell_b])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, pressed_b) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(state, pressed_a) =
    support.press_by(
      plans:,
      state:,
      caster: fighting,
      bag: bag_of_base_1,
      at: 1100,
    )
  let id_b = support.pressed_id(effects: pressed_b)
  let id_a = support.pressed_id(effects: pressed_a)
  let #(_, held) = persisted(state:, caster: fighting, at: 1150)
  assert held == [] as "while B holds, A's condition holds"
  let #(ended, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1200,
    )
  assert list.map(failed(effects:), fn(failure) { failure.0 }) == [id_b, id_a]
    as "B fails first; with B gone A's condition fails too, and both end in the same input"
  let #(_, after) = persisted(state: ended, caster: fighting, at: 1300)
  assert after == []
}

// ---- type 130 in a target persistence ----

/// Prerequisite 43156 (`table_rows -- Prerequisite 43156`) is the TargetPersistence of
/// Spell4 83174, Empowering Probes T4/T8 Buff: one type 130 condition, comparison 1,
/// objectId 704 (a cast of spell group 704, Empowering Probes Buff's group 704 through
/// Spell4GroupList 979, held by the second unit). The planted spell holds that row as its
/// TargetPersistence, and the planted spell B has the group.
///
/// Spell4 83174 itself is not pressed: only Proxy 219576 of the tier 5 Spell4 60423 (base
/// 25729) starts it, and the plans hold the level-1 abilities only, so no cast can
/// hold group 704 yet
/// (`no_level_1_ability_casts_empowering_probes_or_holds_a_group_704_cast_test`). The
/// tiers above 1 are `#336`'s ("each class's spells to level 50").
pub fn an_empowering_probes_buff_persists_while_its_caster_holds_a_group_704_cast_and_ends_without_one_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(row) =
    prerequisite.load(
      id: PrerequisiteId(43_156),
      rows: prerequisite.table_rows(tables:),
      arcs: prerequisite.table_arcs(tables:),
      quests: prerequisite.table_quests(tables:),
    )
    as "the client's rows hold Prerequisite 43156"
  let buff =
    Spell(
      ..support.child(spell4_id: 7020, base: 1),
      cast_time_ms: 1000,
      target_persistence: Some(row),
    )
  let base_buff =
    Spell(
      ..support.child(spell4_id: 7021, base: 3),
      cast_time_ms: 1000,
      groups: [704],
    )
  let plans = support.plans_of([buff, base_buff])
  let caster = support.caster_in_combat(in_combat: True)
  let #(state, pressed_base) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster:,
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(with_base, pressed_buff) =
    support.press_by(plans:, state:, caster:, bag: bag_of_base_1, at: 1100)
  let id_buff = support.pressed_id(effects: pressed_buff)
  let id_base = support.pressed_id(effects: pressed_base)
  let #(_, held) = persisted(state: with_base, caster:, at: 1150)
  assert held == []
    as "the caster holds a cast of group 704, so condition 130 (comparison 1) holds"
  let #(alone, _) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster:,
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(_, effects) = persisted(state: alone, caster:, at: 1150)
  assert list.map(failed(effects:), fn(failure) { failure.1 }) == [283]
    as "with no cast of group 704 the condition fails: the buff ends with 283 (Prereq_TargetPersistence)"
  let assert Ok(#(without_base, _)) =
    support.cancelled_in(
      plans:,
      state: with_base,
      cast_id: id_base,
      reason: cast_result.from_value(11),
      bit: 1,
      at: 1200,
    )
    as "the client cancels the base cast"
  let #(_, effects) = persisted(state: without_base, caster:, at: 1250)
  assert failed(effects:) == [#(id_buff, 283, 7, 0)]
    as "the base cast gone, the buff's persistence fails at the next step"
}

pub fn no_level_1_ability_casts_empowering_probes_or_holds_a_group_704_cast_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Spell4Effects 219576 (a Proxy, effectType 26) of Spell4 60423 (Empowering Probes Base,
  // tierIndex 5, base 25729) starts 83174, and Spell4 41534 (Empowering Probes Buff, base
  // 25730, spellDuration 0, spell4GroupListId 979, whose spellGroupId06 is 704) is the
  // buff of group 704. The plans hold each class's level-1 abilities, and base 25729 is not
  // one of them, so the tiers above 1 and the abilities of levels above 1 are `#336`'s
  // ("each class's spells to level 50").
  let plans = spell_plan.plans(client_tables.shared())
  assert spell_plan.in_plans(plans:, base: Spell4BaseId(25_729)) == Error(Nil)
    as "Empowering Probes is no class's level-1 ability"
  let castable =
    dict.values(plans)
    |> list.flat_map(fn(ability) {
      spell_plan.tree(spell: ability, started: fn(_) { True })
    })
  assert !list.any(castable, fn(spell) { spell.spell4_id.value == 83_174 })
    as "no tree, with every gate open, casts Empowering Probes T4/T8 Buff"
  assert !list.any(castable, fn(spell) { list.contains(spell.groups, 704) })
    as "no tree holds a cast of spell group 704, so type 130 on group 704 has no cast to find yet"
}

// ---- stealth ----

pub fn an_ended_casts_stealth_source_drops_and_stealth_changed_comes_last_test() -> Nil {
  use <- owned_test.run(5000)
  let hiding =
    support.with_effects(
      spell: Spell(
        ..support.child(spell4_id: 7030, base: 3),
        stealth_change: KeepsStealth,
        caster_persistence: Some(in_combat()),
      ),
      kinds: [
        spell_plan.StealthEffect(StealthRow(
          effect_id: Spell4EffectsId(83_834),
          phase_flags: -1,
          breaks: spell_plan.BrokenByDamage,
          row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
          condition: Always,
          tag: spend.always,
        )),
      ],
    )
  let plans = support.plans_of([hiding])
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: support.caster_in_combat(in_combat: True),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert cast_state.stealthed(cast: state)
    && list.contains(pressed, cast_state.StealthChanged(stealthed: True))
    as "the planted spell's Stealth row hides the caster"
  let #(ended, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1100,
    )
  assert !cast_state.stealthed(cast: ended)
    as "the cast's stealth source leaves with the cast"
  assert list.last(effects) == Ok(cast_state.StealthChanged(stealthed: False))
    as "and StealthChanged is the last effect of the input"
  assert failed(effects:) != []
}

// ---- a charge's base cast ----

pub fn the_base_cast_of_an_open_charge_ends_with_its_threshold_test() -> Nil {
  use <- owned_test.run(5000)
  let charged_shot =
    Spell(
      ..support.ability(base: 20_684),
      caster_persistence: Some(in_combat()),
    )
  let plans = support.plans_of([charged_shot])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag: support.charged_shot,
      at: 1000,
    )
  assert list.contains(
    support.ids(frames: support.writes(effects: pressed)),
    0x0816,
  )
    as "the press opens the charge's threshold"
  let #(ended, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1100,
    )
  assert list.take(support.ids(frames: support.writes(effects:)), 3)
    == [0x07F9, 0x0814, 0x07FE]
    as "the base cast fails, its threshold closes with a 0x814 and the cast ends as a 0x801 ends it"
  let #(_, again) =
    support.press_by(
      plans:,
      state: ended,
      caster: fighting,
      bag: support.charged_shot,
      at: 5000,
    )
  assert list.contains(
    support.ids(frames: support.writes(effects: again)),
    0x0816,
  )
    as "no threshold is open: the next press opens it again"
}

// ---- nothing to end ----

pub fn a_caster_that_left_or_died_has_no_cast_left_for_the_check_to_end_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: Some(in_combat()),
        target_persistence: None,
      ),
    ])
  let #(state, _) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: support.caster_in_combat(in_combat: True),
      bag: bag_of_base_3,
      at: 1000,
    )
  let out = support.caster_in_combat(in_combat: False)
  let #(left, _) = cast_tick.left(cast: state)
  assert persisted(state: left, caster: out, at: 1100).1 == []
    as "`left` dropped every cast"
  let #(dead, _) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  assert persisted(state: dead, caster: out, at: 1200).1 == []
    as "`died` ended every cast but the innate passive's"
}

// ---- a spell with no persistence column ----

pub fn a_state_with_no_persistence_column_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    support.press_by(
      plans: support.plans(),
      state: cast_state.new(),
      caster: support.caster(),
      bag: 0,
      at: 1000,
    )
  assert persisted(state:, caster: support.caster(), at: 1100) == #(state, [])
    as "the abilities' spells hold none: the check finds nothing and writes nothing"
  assert !cast_persist.persists(cast: state)
}

// ---- a held key ----

pub fn a_held_key_whose_cast_the_persistence_ended_casts_again_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: Some(in_combat()),
        target_persistence: None,
      ),
    ])
  let fighting = support.caster_in_combat(in_combat: True)
  let assert Ok(#(state, down)) =
    cast.take(
      cast: cast_state.new(),
      message: cast_state.KeyHeld,
      body: support.hold_body(bag_index: bag_of_base_3, target: 0, held: 1),
      caster: fighting,
      plans:,
      now: support.at(ms: 1000),
    )
    as "a 0x4db that fits the message is taken"
  assert support.ids(frames: support.writes(effects: down)) == [0x07FF]
    as "the key goes down in combat: its first cast starts, with no 0x7fd"
  let #(_, effects) =
    persisted(
      state:,
      caster: support.caster_in_combat(in_combat: False),
      at: 1100,
    )
  assert support.ids(frames: support.writes(effects:))
    == [0x07F9, 0x07FE, 0x07FF, 0x07F9, 0x07FE]
    as "the cast the persistence ended is the held key's last, so the key repeats in the same input (a cast of its own, 0x7ff), and the check runs on that cast too, which fails the same condition"
}

// ---- Life Force: a persistence on the caster's Focus ----

/// A Medic whose Focus maximum is 1000 and who holds `held` of it, with the planted base 3
/// among its abilities.
fn medic_holding_focus(held held: Int) -> Caster {
  let resources =
    class_resource.paid(
      resources: class_resource_support.resources_with(
        class_id: 4,
        changes: [#(5, 1000.0)],
        level: 1,
      ),
      payments: [class_resource.Payment(slot: -1, amount: 1000 - held)],
    )
  support.caster_holding(resources:)
}

pub fn life_force_persists_while_the_casters_focus_meets_prerequisite_38318_and_ends_when_it_falls_below_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4 81977 (Life Force) holds prerequisiteIdCasterPersistence 38318: one type 71
  // condition on vital 15, comparison 4 (at least) of 30, so the cast lasts while the
  // caster's Focus is at least 30 percent of its maximum. 81977 itself cannot be planned
  // outside an item (its Modifier row 215678 holds a type 18 parameter), so the planted
  // spell holds the client's row as its CasterPersistence.
  let plans =
    support.plans_of([
      casting_for_a_second(
        caster_persistence: Some(prerequisites.fixture_row(row: 38_318)),
        target_persistence: None,
      ),
    ])
  let #(state, pressed) =
    support.press_by(
      plans:,
      state: cast_state.new(),
      caster: medic_holding_focus(held: 1000),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert support.refusal_results(effects: pressed) == []
    as "the press is accepted"
  let focus_cast = support.pressed_id(effects: pressed)
  let #(unchanged, nothing) =
    persisted(state:, caster: medic_holding_focus(held: 300), at: 1100)
  assert nothing == [] && unchanged == state
    as "300 of 1000 is 30 percent: 38318 holds and nothing happens"
  let #(_, effects) =
    persisted(state:, caster: medic_holding_focus(held: 299), at: 1200)
  assert failed(effects:) == [#(focus_cast, 282, 7, 0)]
    as "29.9 percent fails 38318: 0x7f9 {the cast id, 282 Prereq_CasterPersistence, the caster, 0}"
}

// ---- a periodic Proxy's own persistence ----

/// A planted spell of this id and base whose only effect is a Proxy on the caster that casts a
/// child every 500 ms for 5 seconds, holding this persistence on its row.
fn periodic_holder(
  spell4_id spell4_id: Int,
  base base: Int,
  persistence persistence: option.Option(Prerequisite),
) -> Spell {
  support.with_effects(spell: support.child(spell4_id:, base:), kinds: [
    spell_plan.ProxyEffect(spell_plan.Proxy(
      effect_id: Spell4EffectsId(spell4_id),
      delay_ms: 0,
      phase_flags: -1,
      condition: Always,
      tag: spend.always,
      target: spell_plan.OnCaster,
      spell: support.child(spell4_id: 7030, base: 7030),
      gains: [],
      period: Some(spell_plan.Periodic(
        schedule: Schedule(
          delay_ms: 0,
          tick_ms: 500,
          duration_ms: 5000,
          count: Ticks(10),
        ),
        persistence:,
      )),
    )),
  ])
}

/// The press of the planted base 3 ability, its go answered with no unit struck.
fn pressed_periodic(
  plans plans: spell_plan.Plans,
  caster caster: Caster,
) -> #(State, List(Effect)) {
  support.press_as(
    plans:,
    state: cast_state.new(),
    caster:,
    bag: bag_of_base_3,
    at: 1000,
  )
}

pub fn a_periodic_proxys_own_persistence_ends_its_cast_in_the_input_that_breaks_it_and_a_cast_with_none_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let fighting = support.caster_in_combat(in_combat: True)
  let idle = support.caster_in_combat(in_combat: False)
  let persisting =
    support.plans_of([
      periodic_holder(spell4_id: 7021, base: 3, persistence: Some(in_combat())),
    ])
  let #(state, pressed) = pressed_periodic(plans: persisting, caster: fighting)
  let cast_id = support.pressed_id(effects: pressed)
  let armed = dict.keys(state.timers)
  assert armed != [] as "the go armed the Proxy's tick and the node's end"
  assert cast_persist.persists(cast: state)
    as "a cast whose Proxy row holds a persistence has something to check"
  let #(unchanged, nothing) = persisted(state:, caster: fighting, at: 1100)
  assert nothing == [] && unchanged == state
    as "the persistence holds: nothing happens"
  let #(ended, effects) = persisted(state:, caster: idle, at: 1200)
  assert failed(effects:) == [#(cast_id, 282, 7, 0)]
    as "the persistence fails in this input: 0x7f9 {the cast id, 282, the caster, 0}, as the spell column's does"
  assert support.ids(frames: support.writes(effects:)) == [0x07F9, 0x07FE]
    && finished_ids(effects:) == [cast_id]
    as "then the 0x7fe that takes the cast out of the client's table"
  assert set.from_list(support.cancelled_timers(effects:))
    == set.from_list(armed)
    && dict.size(ended.timers) == 0
    as "the tick timer and the node's end timer are cancelled and none is left"
  assert support.tells(effects:)
    == [
      #(ConnectionId(2), CastFinished(cast_id:)),
      #(ConnectionId(3), CastFinished(cast_id:)),
    ]
    as "each viewer is told the cast finished"
  let plain =
    support.plans_of([
      periodic_holder(spell4_id: 7021, base: 3, persistence: None),
    ])
  let #(state, _) = pressed_periodic(plans: plain, caster: fighting)
  assert !cast_persist.persists(cast: state)
    as "a periodic Proxy with no persistence gives the connection nothing to check"
  let both =
    support.plans_of([
      Spell(
        ..periodic_holder(
          spell4_id: 7021,
          base: 3,
          persistence: Some(in_combat()),
        ),
        caster_persistence: Some(in_combat()),
      ),
    ])
  let #(state, pressed) = pressed_periodic(plans: both, caster: fighting)
  let #(_, effects) = persisted(state:, caster: idle, at: 1200)
  assert failed(effects:)
    == [#(support.pressed_id(effects: pressed), 282, 7, 0)]
    as "the spell column and the row both fail: the cast ends once"
}

pub fn a_periodic_proxys_persistence_checks_the_caster_as_second_unit_even_when_the_cast_has_another_primary_target_test() -> Nil {
  use <- owned_test.run(5000)
  // Each persistence is a type 60 condition on the Proxy of Spell4 7022 itself (the stacks of
  // 7022 the second unit cast against the value), whose cast holds one stack on the caster
  // and none on the struck creature 99. Second unit the caster: the count is 1; second unit
  // the creature 99, the cast's primary target: the count is 0.
  let cases = [
    #(
      "at least 1 stack: the count 1 holds it, and with the creature 99 as second unit the count would be 0 and the cast would end",
      #(60, 4, 7022, 1),
      False,
    ),
    #(
      "no stack at all (comparison 1, value 0): the count 1 fails it, and with the creature 99 as second unit the count would be 0 and the cast would hold",
      #(60, 1, 7022, 0),
      True,
    ),
  ]
  list.each(cases, fn(case_) {
    let #(reason, condition, ends) = case_
    let persistence = prerequisites.single(id: 41_835, condition:)
    let child =
      periodic_holder(spell4_id: 7022, base: 3, persistence: Some(persistence))
    let plans = support.plans_starting_on_each_struck(started: child)
    let fighting = support.caster_in_combat(in_combat: True)
    let #(state, raw) =
      support.pressed_raw_in(
        plans:,
        state: cast_state.new(),
        caster: fighting,
        bag_index: bag_of_base_3,
        target: 0,
        at: 1000,
      )
    let #(state, effects) =
      support.answered_as(
        caster: fighting,
        state:,
        effects: raw,
        at: 1000,
        struck: support.hits([99]),
        rolls: [],
      )
    let cast_id = cast_id_of(spell4_id: 7022, effects:)
    let assert Ok(holder) = cast_state.holder_of(cast: state, cast_id:)
      as "the struck unit's child is a cast of its own"
    assert holder.primary_target == 99
      as "the child's primary target is the struck creature, not the caster"
    let #(after, effects) = persisted(state:, caster: fighting, at: 1100)
    case ends {
      False -> {
        assert failed(effects:) == [] && after == state as reason
      }
      True -> {
        assert failed(effects:) == [#(cast_id, 282, 7, 0)]
          && support.ids(frames: support.writes(effects:)) == [0x07F9, 0x07FE]
          as reason
      }
    }
  })
}

pub fn a_periodic_proxys_persistence_of_a_type_the_server_does_not_read_keeps_the_cast_with_one_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let type_12 = prerequisites.single(id: 41_836, condition: #(12, 1, 0, 0))
  let type_56 = prerequisites.single(id: 41_837, condition: #(56, 1, 0, 0))
  assert prerequisite.unread_types(prerequisite: type_12) == [12]
    && prerequisite.unread_types(prerequisite: type_56) == [56]
    as "types 12 and 56 are ones the server does not read"
  let plans =
    support.plans_of([
      periodic_holder(spell4_id: 7023, base: 3, persistence: Some(type_12)),
      periodic_holder(spell4_id: 7024, base: 1, persistence: Some(type_56)),
    ])
  let fighting = support.caster_in_combat(in_combat: True)
  let #(state, _) =
    support.press_as(
      plans:,
      state: cast_state.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(state, _) =
    support.press_as(
      plans:,
      state:,
      caster: fighting,
      bag: bag_of_base_1,
      at: 1100,
    )
  assert list.length(cast_state.holders(cast: state)) == 2
    as "both casts are held"
  let #(state, first) = persisted(state:, caster: fighting, at: 1200)
  assert failed(effects: first) == []
    && list.map(support.logs(effects: first), fn(line) { line.0 })
    == [LogDebug, LogDebug]
    as "each unread persistence keeps its cast with one debug line for its spell"
  let #(state, second) = persisted(state:, caster: fighting, at: 1300)
  let #(_, third) = persisted(state:, caster: fighting, at: 1400)
  assert second == [] && third == []
    as "no more lines and no end on the inputs after"
}

// ---- Augmented Blade's stack removal ----

/// The timers due at `until_ms` or before fire, earliest first, each answered as a go that
/// struck nobody and followed by the check of every cast's persistence, as the connection
/// runs it after each input: the state, each step's time and effects, and the timers left.
fn driven(
  state state: State,
  caster caster: Caster,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
) -> #(State, List(#(Int, List(Effect))), List(#(Int, TimerId))) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [#(due, timer), ..rest] if due <= until_ms -> {
      let #(state, fired) = support.fired(state:, timer:, at: due)
      let #(state, checked) = persisted(state:, caster:, at: due)
      let effects = list.append(fired, checked)
      let cancelled = support.cancelled_timers(effects:)
      let #(state, steps, left) =
        driven(
          state:,
          caster:,
          pending: list.append(
            list.filter(rest, fn(other) { !list.contains(cancelled, other.1) }),
            support.due_of(effects:, now_ms: due),
          ),
          until_ms:,
        )
      #(state, [#(due, effects), ..steps], left)
    }
    _ -> #(state, [], pending)
  }
}

/// A press, answered as a go that struck nobody and followed by the persistence check at
/// the same time: the state, the press's effects and the timers it started.
fn pressed_and_checked(
  plans plans: spell_plan.Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect), List(#(Int, TimerId))) {
  let #(state, pressed) =
    support.press_as(plans:, state:, caster:, bag:, at: ms)
  let #(state, checked) = persisted(state:, caster:, at: ms)
  let effects = list.append(pressed, checked)
  #(state, effects, support.due_of(effects:, now_ms: ms))
}

/// The time of each step that starts a cast of the spell.
fn starts_in(
  steps steps: List(#(Int, List(Effect))),
  spell4_id spell4_id: Int,
) -> List(Int) {
  list.flat_map(steps, fn(step) {
    list.filter_map(started(effects: step.1), fn(start) {
      case start.0 == spell4_id {
        True -> Ok(step.0)
        False -> Error(Nil)
      }
    })
  })
}

pub fn augmented_blades_stack_removal_buff_ends_with_its_last_kinetic_rage_stack_or_when_the_toggle_turns_back_on_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let planned = fn(spell4_id) {
    let assert Ok(spell) =
      spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
      as "the spell plans on its own"
    spell
  }
  let rage = planned(79_757)
  let toggle_on = planned(79_753)
  let toggle_off = planned(57_357)
  let removal_buff = planned(82_838)
  let removal = planned(82_839)
  let proxies_of = fn(spell) {
    spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy)
  }
  // The wiring of the real rows: Proxy 217944 of 82838 casts 82839 every 500 ms until its
  // node ends, holding Prerequisite 38758; 82839's type 80 row 217947 takes one stack of
  // 79757; 57357's Proxy 217946 starts 82838 one ms on; Kinetic Rage's own Proxy 210337
  // ticks every 250 ms and 79757 stacks to the cap of Spell4StackGroup 1916.
  let assert [removing] = proxies_of(removal_buff) as "82838 holds one Proxy"
  assert removing.effect_id == Spell4EffectsId(217_944)
    && removing.spell.spell4_id.value == 82_839
    && removing.period
    == Some(spell_plan.Periodic(
      schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
      persistence: Some(prerequisites.fixture_row(row: 38_758)),
    ))
    as "Proxy 217944 casts 82839 every 500 ms with persistence 38758"
  let assert [taking] =
    list.filter_map(removal.effects, fn(planned) {
      spell_plan.as_remove(kind: planned.kind)
    })
    as "82839 holds one removal"
  assert taking.effect_id == Spell4EffectsId(217_947)
    && taking.selector == lasting.Spell(spell4_id: Spell4Id(79_757))
    && taking.count == 1
    as "row 217947 takes one stack of 79757"
  assert list.any(proxies_of(toggle_off), fn(proxy) {
    proxy.effect_id == Spell4EffectsId(217_946)
    && proxy.delay_ms == 1
    && proxy.spell.spell4_id.value == 82_838
  })
    as "57357 starts 82838 one millisecond after its go (row 217946)"
  assert rage.stack == lasting.Stack(group_id: 1916, cap: 100)
    && list.map(proxies_of(rage), fn(proxy) { proxy.effect_id })
    == [Spell4EffectsId(210_337)]
    as "Kinetic Rage stacks to 100 and holds the drain Proxy 210337"
  // Two stacks of 79757 cast by the rule: a planted ability starts one at each of two ticks
  // after its press at 1000.
  let stacker =
    support.with_effects(spell: support.child(spell4_id: 7041, base: 3), kinds: [
      spell_plan.ProxyEffect(spell_plan.Proxy(
        effect_id: Spell4EffectsId(7041),
        delay_ms: 0,
        phase_flags: -1,
        condition: Always,
        tag: spend.always,
        target: spell_plan.OnCaster,
        spell: rage,
        gains: [],
        period: Some(spell_plan.Periodic(
          schedule: Schedule(
            delay_ms: 0,
            tick_ms: 1000,
            duration_ms: 2000,
            count: Ticks(2),
          ),
          persistence: None,
        )),
      )),
    ])
  let plans =
    support.plans_of([
      stacker,
      Spell(..toggle_off, spell4_base_id: Spell4BaseId(1)),
      Spell(..toggle_on, spell4_base_id: Spell4BaseId(2)),
    ])
  let caster = support.caster()
  let #(state, _, pending) =
    pressed_and_checked(
      plans:,
      state: cast_state.new(),
      caster:,
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(stacked, stacking, pending) =
    driven(state:, caster:, pending:, until_ms: 3000)
  assert starts_in(steps: stacking, spell4_id: 79_757) == [2000, 3000]
    as "two stacks of Kinetic Rage start, one at each tick of the stacker"
  // Scenario 1: the toggle is turned off at 3500; 82838 starts at 3501 and ticks at 4001 and
  // 4501, each tick starting 82839, which takes one stack, and it ends with the last stack.
  let #(off, pressed, off_pending) =
    pressed_and_checked(
      plans:,
      state: stacked,
      caster:,
      bag: bag_of_base_1,
      at: 3500,
    )
  assert failed(effects: pressed) == [] as "the press does not fail a cast"
  let pending = list.append(pending, off_pending)
  let #(ended, removing_steps, _) =
    driven(state: off, caster:, pending:, until_ms: 6501)
  assert starts_in(steps: removing_steps, spell4_id: 82_838) == [3501]
    as "82838 starts one ms after the press"
  assert starts_in(steps: removing_steps, spell4_id: 82_839) == [4001, 4501]
    as "82838 ticks at 500 and 1000 after its go, and there is no third tick"
  let assert [cast_id] =
    list.flat_map(removing_steps, fn(step) { started(effects: step.1) })
    |> list.filter_map(fn(start) {
      case start.0 == 82_838 {
        True -> Ok(start.1)
        False -> Error(Nil)
      }
    })
    as "82838 started once"
  let failures =
    list.flat_map(removing_steps, fn(step) {
      list.map(failed(effects: step.1), fn(failure) { #(step.0, failure) })
    })
  assert failures == [#(4501, #(cast_id, 282, 7, 0))]
    as "82838 fails 282 in the input that takes the last stack, at 4501, and not before"
  assert list.any(removing_steps, fn(step) {
    step.0 == 4501 && list.contains(finished_ids(effects: step.1), cast_id)
  })
    as "its 0x7fe ends it for the client"
  assert !list.any(cast_state.holders(cast: ended), fn(holder) {
    holder.0 == cast_id
  })
    as "82838 is no longer held"
  // Scenario 2: the toggle turned back on at 4100, while 82838 is live, ends it in the input
  // of that start.
  let #(live, _, _) = driven(state: off, caster:, pending:, until_ms: 4100)
  assert list.any(cast_state.holders(cast: live), fn(holder) {
    holder.0 == cast_id
  })
    as "82838 is live at 4100"
  let #(on, on_pressed, _) =
    pressed_and_checked(plans:, state: live, caster:, bag: 10, at: 4100)
  assert failed(effects: on_pressed) == [#(cast_id, 282, 7, 0)]
    as "79753 started: 37378 fails and 82838 ends in the input of that start"
  assert !list.any(cast_state.holders(cast: on), fn(holder) {
    holder.0 == cast_id
  })
    as "82838 is no longer held"
  // Scenario 3: with no stack at all, 82838 ends in the input of its own start.
  let #(bare, _, bare_pending) =
    pressed_and_checked(
      plans:,
      state: cast_state.new(),
      caster:,
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(_, bare_steps, _) =
    driven(state: bare, caster:, pending: bare_pending, until_ms: 3000)
  assert list.map(bare_steps, fn(step) {
      #(step.0, list.map(failed(effects: step.1), fn(failure) { failure.1 }))
    })
    |> list.filter(fn(step) { step.1 != [] })
    == [#(1001, [282])]
    as "82838 starts at 1001 and fails 282 in the input of its own start"
  assert starts_in(steps: bare_steps, spell4_id: 82_839) == []
    as "with no stack it never ticks"
}
