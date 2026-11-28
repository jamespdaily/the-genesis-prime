//// The cast rule's QuestAdvanceObjective rows (`genesis_prime/game/cast`): what a go hands the
//// connection for the type 42 rows of its spell, and when. Expected values come from these
//// places:
//// - `Spell4Effects.effectType.42`: the row's quest, index and amount, and its delay; the
////   client lists the row nowhere (it has no effect for the type), so the go lists none.
//// - Spell4 24501 (the Experimental Loftite Railgun): 89873 (quest 3769, delayTime 6000, no
////   gate) and 89874 (quest 3785, no delay, caster apply prerequisite 14533: quest 3785
////   Accepted with its objective open, `Prerequisite 14533`).
//// - Spell4 45904 (Ignite Tower 2) of Creature2 42205: an Activate row and 107313 (quest 8262
////   index 2 amount 2, delayTime 1500); Spell4 40061 of Creature2 37015 holds two rows aimed at
////   the primary target alone (88719, 88720), behind caster prerequisites 18 and 19.
//// - `Spell4Effects.targetFlags` (a guess, no reader in the client): a row aimed at the primary
////   target alone lands on the caster only when the primary target is the caster, which a press
////   of a spell on the caster makes it.
//// - The server's choices, in the cast rule's doc: a timer once armed is not cancelled by the
////   cast's end or the caster's death, and each cast counts its own rows.

import cast_item_use_test as items
import cast_support as support
import fixture_tables
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{
  type Effect, type State, WithCast, WithNothing, WithUse,
} as cast_state
import genesis_prime/game/quest_advance.{Advance}
import genesis_prime/game/shortcut_spell
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/cast_objective_ability.{CastObjectiveAbility}
import genesis_prime/message/cast_result
import genesis_prime/message/spell_go
import genesis_prime/shared/activate.{type Target}
import genesis_prime/shared/spell_plan.{type Spell}
import genesis_prime/shared/spend
import genesis_prime/table/id
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/list
import gleam/option.{None}
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import quest_support
import spell_tables

// The planted base 1 is bag index 8 in `cast_support.abilities`.
const bag_of_holder = 8

const clients_cast_id = 9

/// The caster of the standing place, holding these quests accepted with one objective each.
fn holding(quests quests: List(Int)) -> cast_state.Caster {
  cast_state.Caster(
    ..support.caster(),
    quests: quest_support.view_of(
      rows: list.map(quests, fn(quest_id) { quest_support.untouched(quest_id:) }),
    ),
  )
}

/// A planted spell of Spell4 1, base 1, that goes at once and holds these type 42 rows.
fn holding_rows(rows rows: List(spell_plan.QuestAdvance)) -> Spell {
  support.with_effects(
    spell: support.child(spell4_id: 1, base: 1),
    kinds: list.map(rows, spell_plan.QuestAdvanceEffect),
  )
}

/// The two type 42 rows of the railgun's spell as the plan reads them.
fn railgun_rows() -> List(spell_plan.QuestAdvance) {
  spell_plan.payloads(
    spell: spell_tables.client_spell(spell4_id: 24_501),
    as_kind: spell_plan.as_quest_advance,
  )
}

/// The row of this effect id that advances quest 3769's objective 0 by 1 after this delay,
/// with no gate.
fn row(
  effect_id effect_id: Int,
  delay delay: Int,
  quest quest: Int,
) -> spell_plan.QuestAdvance {
  spell_plan.QuestAdvance(
    effect_id: id.Spell4EffectsId(effect_id),
    phase_flags: -1,
    aim: spell_plan.AimsAtCaster,
    condition: spell_plan.Always,
    tag: spend.EqualTo(value: 0),
    quest_id: quest,
    objective_index: 0,
    amount: 1,
    delay_ms: delay,
  )
}

/// Fires every timer a step started for this caster, with the time each fired at.
fn run_as(
  caster caster: cast_state.Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  support.run_timers_each(caster:, state:, effects:, from_ms:, struck_of: fn(_) {
    []
  })
}

/// The pressed planted spell by this caster at the time, its go answered with no unit struck.
fn pressed(
  spell spell: Spell,
  caster caster: cast_state.Caster,
  state state: State,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.press_as(
    plans: support.plans_with(spell:),
    state:,
    caster:,
    bag: bag_of_holder,
    at: ms,
  )
}

/// What the effects hand the connection: each `QuestAdvanced`'s advances and its event.
fn advanced(
  effects effects: List(Effect),
) -> List(#(List(quest_advance.Advance), cast_state.AdvanceWith)) {
  support.quest_advances(effects:)
}

/// Each timer the effects start, with its delay.
fn waits(effects effects: List(Effect)) -> List(Int) {
  list.map(support.started_timers(effects:), fn(started) { started.1 })
}

fn advance(quest quest: Int) -> quest_advance.Advance {
  Advance(quest_id: quest, objective_index: 0, amount: 1)
}

type GoCase {
  GoCase(
    why: String,
    caster: cast_state.Caster,
    rows: List(spell_plan.QuestAdvance),
    now: List(quest_advance.Advance),
    waits_ms: List(Int),
    fires: List(#(Int, List(quest_advance.Advance))),
  )
}

pub fn a_go_with_a_type_42_row_raises_the_advance_at_its_delay_and_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = railgun_rows()
  list.each(
    [
      GoCase(
        "a caster who holds quest 3769: the gateless row 89873 waits its 6000 ms and the gated twin 89874 fails its prerequisite 14533",
        holding(quests: [3769]),
        rows,
        [],
        [6000],
        [#(7000, [advance(quest: 3769)])],
      ),
      GoCase(
        "a caster who holds the other faction's quest 3785: the gated row advances in the step and the gateless row is raised all the same, which finds no quest 3769 in the log",
        holding(quests: [3785]),
        rows,
        [advance(quest: 3785)],
        [6000],
        [#(7000, [advance(quest: 3769)])],
      ),
      GoCase(
        "a caster who holds neither: only the gateless row waits",
        holding(quests: []),
        rows,
        [],
        [6000],
        [#(7000, [advance(quest: 3769)])],
      ),
      GoCase(
        "rows of two delays arm two timers, the earlier first",
        holding(quests: [3769]),
        [
          row(effect_id: 1, delay: 3000, quest: 3769),
          row(effect_id: 2, delay: 1500, quest: 8262),
        ],
        [],
        [1500, 3000],
        [#(2500, [advance(quest: 8262)]), #(4000, [advance(quest: 3769)])],
      ),
      GoCase(
        "rows of one delay arm one timer, in the order of the rows",
        holding(quests: []),
        [
          row(effect_id: 1, delay: 1500, quest: 3769),
          row(effect_id: 2, delay: 1500, quest: 8262),
        ],
        [],
        [1500],
        [#(2500, [advance(quest: 3769), advance(quest: 8262)])],
      ),
      GoCase(
        "a row of no delay advances in the step and arms nothing",
        holding(quests: []),
        [row(effect_id: 1, delay: 0, quest: 3769)],
        [advance(quest: 3769)],
        [],
        [],
      ),
    ],
    fn(case_) {
      let #(state, effects) =
        pressed(
          spell: holding_rows(rows: case_.rows),
          caster: case_.caster,
          state: cast_state.new(),
          at: 1000,
        )
      assert advanced(effects:)
        == case case_.now {
          [] -> []
          [_, ..] -> [#(case_.now, WithNothing)]
        }
        as case_.why
      assert waits(effects:) == case_.waits_ms as case_.why
      let #(_, fired) =
        run_as(caster: case_.caster, state:, effects:, from_ms: 1000)
      assert list.map(fired, fn(step) { #(step.0, advanced(effects: step.1)) })
        == list.map(case_.fires, fn(fire) {
          #(fire.0, [#(fire.1, WithNothing)])
        })
        as case_.why
    },
  )
}

pub fn a_row_is_absent_from_the_go_and_outlives_the_cast_and_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let caster = holding(quests: [3769])
  let #(state, effects) =
    pressed(
      spell: holding_rows(rows: railgun_rows()),
      caster:,
      state: cast_state.new(),
      at: 1000,
    )
  let assert [go_frame] =
    support.frames_of(message_id: spell_go.message_id, effects:)
    as "the spell goes at once"
  let assert Ok(go) = spell_go.decode(go_frame.body)
  assert list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(info) { info.spell4_effects_id })
    })
    == []
    as "the client has no effect for type 42, so the go lists neither row"
  assert support.finished_ids(support.writes(effects:)) != []
    as "the cast ended at its go, with the row's timer still waiting"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.map(fired, fn(step) { advanced(effects: step.1) })
    == [[#([advance(quest: 3769)], WithNothing)]]
    as "a cast that ended before the timer still raises the row"
  // The caster dies after the go: the timer is not cancelled.
  let #(dead, died) = cast.died(cast: state, caster:, now: support.at(ms: 3000))
  assert support.cancelled_timers(effects: died) == []
    as "the death cancels no timer of a QuestAdvanceObjective row (a server choice)"
  let timer = case support.started_timers(effects:) {
    [#(timer, _)] -> timer
    _ -> panic as "one timer waits"
  }
  let #(_, due) = support.fired_raw(state: dead, timer:, at: 7000)
  assert advanced(effects: due) == [#([advance(quest: 3769)], WithNothing)]
    as "and it fires after the death"
  // A second cast arms a second timer, and each counts.
  let #(state, second) =
    pressed(
      spell: holding_rows(rows: railgun_rows()),
      caster:,
      state:,
      at: 2000,
    )
  assert waits(effects: second) == [6000] as "a second cast arms its own timer"
  let #(_, both) =
    support.run_timers(
      state:,
      effects: list.append(effects, second),
      from_ms: 1000,
    )
  assert list.length(
      list.flat_map(both, fn(step) { advanced(effects: step.1) }),
    )
    == 2
    as "each cast counts its own rows"
}

pub fn a_cast_cancelled_before_its_go_raises_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // The planted `slow` spell goes after 1000 ms; the same spell holds the railgun's rows.
  let slow =
    support.with_effects(
      spell: support.slow(),
      kinds: list.map(railgun_rows(), spell_plan.QuestAdvanceEffect),
    )
  let caster = holding(quests: [3769])
  let #(state, effects) =
    support.press_as(
      plans: support.plans_with(spell: slow),
      state: cast_state.new(),
      caster:,
      bag: 11,
      at: 1000,
    )
  let assert Ok(#(state, cancelled)) =
    support.cancelled(
      state:,
      cast_id: support.pressed_id(effects:),
      reason: cast_result.SpellCancelled,
      bit: 1,
      at: 1500,
    )
    as "the client's 0x801 ends the cast before its go"
  let #(_, fired) =
    support.run_timers(
      state:,
      effects: list.append(effects, cancelled),
      from_ms: 1000,
    )
  assert list.flat_map(fired, fn(step) { advanced(effects: step.1) }) == []
    as "no go, so no row was applied, and no timer of one waits"
}

/// A creature of the fixture 3 m east of the caster, alive.
fn nearby(creature_id creature_id: Int) -> Target {
  support.usable_at(creature_id:, x: 4099.5, radius: 0.25)
}

fn right_click(
  state state: State,
  tables tables: table_store.Tables,
  creature_id creature_id: Int,
  caster caster: cast_state.Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(
      client_cast_id: clients_cast_id,
      target_unit_id: items.its_unit,
    ))
    as "the message fits"
  let assert Ok(taken) =
    cast.activate(
      cast: state,
      body:,
      caster:,
      activations: activate.activations(tables:),
      target_of: fn(unit_id) {
        case unit_id == items.its_unit {
          True -> nearby(creature_id:)
          False -> activate.Unseen
        }
      },
      caster_radius: 0.5,
      now: support.at(ms:),
    )
    as "the right-click is taken"
  taken
}

/// A caster at the place the activate tests use.
fn standing_with(quests quests: List(Int)) -> cast_state.Caster {
  support.standing_at(caster: holding(quests:), x: 4096.0, y: 0.0, z: 512.0)
}

/// What a right-click of the creature at 1000 ms starts, with everything every timer then
/// does.
fn right_clicked(
  tables tables: table_store.Tables,
  creature_id creature_id: Int,
  caster caster: cast_state.Caster,
) -> List(Effect) {
  let #(state, started) =
    right_click(
      state: cast_state.new(),
      tables:,
      creature_id:,
      caster:,
      at: 1000,
    )
  let #(_, fired) = run_as(caster:, state:, effects: started, from_ms: 1000)
  list.append(started, list.flat_map(fired, fn(step) { step.1 }))
}

/// The press of the quest button of this spell by a caster holding no quest, with everything
/// every timer then does.
fn button_pressed(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(Effect) {
  let assert Ok(body) =
    cast_objective_ability.encode(CastObjectiveAbility(
      client_cast_id: clients_cast_id,
      spell4_id:,
      target_unit_id: 0,
      position_x: 0,
      position_y: 0,
      position_z: 0,
    ))
    as "the message fits"
  let assert Ok(#(state, effects)) =
    cast.shortcut(
      cast: cast_state.new(),
      body:,
      caster: holding(quests: []),
      shortcuts: shortcut_spell.shortcuts(tables:),
      held: set.from_list([spell4_id]),
      activations: activate.activations(tables:),
      target_of: fn(_) { activate.Unseen },
      in_cast_group: fn(_, _) { False },
      caster_radius: 0.5,
      now: support.at(ms: 1000),
    )
    as "the press of the button is taken"
  let #(_, fired) =
    run_as(caster: holding(quests: []), state:, effects:, from_ms: 1000)
  list.append(effects, list.flat_map(fired, fn(step) { step.1 }))
}

type WithCase {
  WithCase(
    why: String,
    effects: List(Effect),
    expected: List(#(List(quest_advance.Advance), cast_state.AdvanceWith)),
  )
}

pub fn an_advance_carries_the_use_or_cast_it_was_made_with_test() -> Nil {
  use <- owned_test.run(60_000)
  // The creature's own activate cast: the Seaspine Mollusk (Creature2 26462) casts Spell4 1817
  // (cast time 0, an Activate row 2821), which is given a copy of the railgun's row with the
  // quest 8262, index 2 and amount 2 of Spell4Effects 107313, a delay of 1500, after the go.
  let caster = standing_with(quests: [8262])
  let activated = {
    use tables <- fixture_tables.added(
      table: "Spell4Effects",
      copy_of: 107_313,
      id: 999_003,
      with: [#("spellId", Integer(1817))],
    )
    right_clicked(tables:, creature_id: 26_462, caster:)
  }
  let activate_with =
    WithUse(
      spawn_id: SpawnId(1),
      unit_id: items.its_unit,
      creature_id: 26_462,
      alive_at_press: True,
      by_item: False,
    )
  // An item's cast of a spell that holds an Activate row and a row of no delay: the grenade's
  // spell (Spell4 26663, Activate row 43805) is given a copy of the railgun's row 89873.
  let grenade_effects = {
    use tables <- fixture_tables.added(
      table: "Spell4Effects",
      copy_of: 89_873,
      id: 999_001,
      with: [#("spellId", Integer(26_663)), #("delayTime", Integer(0))],
    )
    let assert Ok(taken) =
      items.use_item_in(
        tables:,
        state: cast_state.new(),
        caster: items.standing(
          level: 50,
          quests: quest_support.view_of(rows: [
            quest_support.accepted(quest_id: 4743, progress: [0, 0, 0, 0]),
          ]),
        ),
        item: items.grenade,
        target: items.shown(creature_id: items.a_slaver_shack, metres: 10.0),
        at: 1000,
      )
      as "the grenade at a slaver shack starts"
    taken.1
  }
  // The quest button's cast: the self spell 25306 is given a row of no delay.
  let button_effects = {
    use tables <- fixture_tables.added(
      table: "Spell4Effects",
      copy_of: 89_873,
      id: 999_002,
      with: [#("spellId", Integer(25_306)), #("delayTime", Integer(0))],
    )
    button_pressed(tables:, spell4_id: 25_306)
  }
  list.each(
    [
      WithCase(
        "a creature's activate cast gives the unit it activates, not by an item, and the delay carries it to its timer",
        activated,
        [
          #(
            [Advance(quest_id: 8262, objective_index: 2, amount: 2)],
            activate_with,
          ),
        ],
      ),
      WithCase(
        "an item's cast of a spell with an Activate row gives the unit, by an item",
        grenade_effects,
        [
          #(
            [advance(quest: 3769)],
            WithUse(
              spawn_id: SpawnId(1),
              unit_id: items.its_unit,
              creature_id: items.a_slaver_shack,
              alive_at_press: True,
              by_item: True,
            ),
          ),
        ],
      ),
      WithCase(
        "a quest button's cast gives its spell and no unit when it takes none",
        button_effects,
        [#([advance(quest: 3769)], WithCast(spell4_id: 25_306, target: None))],
      ),
    ],
    fn(row) {
      assert advanced(effects: row.effects) == row.expected as row.why
    },
  )
  let #(_, pressed_effects) =
    pressed(
      spell: holding_rows(rows: [row(effect_id: 1, delay: 0, quest: 3769)]),
      caster: holding(quests: []),
      state: cast_state.new(),
      at: 1000,
    )
  assert advanced(effects: pressed_effects)
    == [#([advance(quest: 3769)], WithNothing)]
    as "a press has no use or cast of its own"
  // Order: the use is raised before the rows that count with it.
  let grenade_kinds = list.map(grenade_effects, effect_name)
  let assert [first, second] =
    list.filter(grenade_kinds, fn(name) { name != "" })
    as "the go raises the use and then the advance"
  assert first == "Activated" && second == "QuestAdvanced"
    as "the use counts first"
}

fn effect_name(effect effect: Effect) -> String {
  case effect {
    cast_state.Activated(..) -> "Activated"
    cast_state.QuestAdvanced(..) -> "QuestAdvanced"
    _ -> ""
  }
}

pub fn a_row_aimed_at_the_primary_target_is_dropped_by_an_activate_cast_not_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  // Creature2 37015's activate spell is Spell4 40061: an Activate row, and 88719 and 88720
  // aimed at the primary target alone, the creature, which has no quest log.
  let caster = standing_with(quests: [])
  let #(state, started) =
    right_click(
      state: cast_state.new(),
      tables:,
      creature_id: 37_015,
      caster:,
      at: 1000,
    )
  assert support.refusal_results(effects: started) == []
    as "the spell still plans and its use starts: a row that reaches past the caster is dropped, not refused 285"
  let #(_, fired) = run_as(caster:, state:, effects: started, from_ms: 1000)
  assert list.flat_map(fired, fn(step) { advanced(effects: step.1) }) == []
    as "the rows aim at the creature, so the activation advances nothing"
  // A press of a spell on the caster has the caster as its primary target.
  let on_the_primary_target =
    spell_plan.QuestAdvance(
      ..row(effect_id: 88_719, delay: 0, quest: 7442),
      aim: spell_plan.AimsAtPrimaryTarget,
    )
  let #(_, pressed_effects) =
    pressed(
      spell: holding_rows(rows: [on_the_primary_target]),
      caster: holding(quests: []),
      state: cast_state.new(),
      at: 1000,
    )
  assert advanced(effects: pressed_effects)
    == [#([advance(quest: 7442)], WithNothing)]
    as "a self-aimed press lands the row on the caster"
}

type OncePerCast {
  OncePerCast(
    why: String,
    rows: List(spell_plan.QuestAdvance),
    advances: List(quest_advance.Advance),
  )
}

/// Every advance of the effects, in order, whichever go or timer raised it.
fn all_advances(
  effects effects: List(Effect),
  fired fired: List(#(Int, List(Effect))),
) -> List(quest_advance.Advance) {
  list.append(
    advanced(effects:),
    list.flat_map(fired, fn(step) { advanced(effects: step.1) }),
  )
  |> list.flat_map(fn(raised) { raised.0 })
}

pub fn a_row_in_several_gos_counts_once_per_cast_test() -> Nil {
  use <- owned_test.run(60_000)
  // A spell of two phases, at 0 and 1000 ms: a row with phaseFlags -1 is listed by both gos
  // (`spell_effect.applies_in_phase`), and a row of phaseFlags 2 only by the second.
  let in_phases = fn(effect_id, delay, flags) {
    spell_plan.QuestAdvance(
      ..row(effect_id:, delay:, quest: 3769),
      phase_flags: flags,
    )
  }
  let first = Advance(quest_id: 3769, objective_index: 0, amount: 1)
  list.each(
    [
      OncePerCast(
        "a row of no delay in every phase advances at the first go only",
        [in_phases(1, 0, -1)],
        [first],
      ),
      OncePerCast(
        "a row of 500 ms in every phase arms one timer, at the first go",
        [in_phases(1, 500, -1)],
        [first],
      ),
      OncePerCast(
        "a row of 1500 ms in every phase arms one timer, though the second go comes first",
        [in_phases(1, 1500, -1)],
        [first],
      ),
      OncePerCast(
        "a row of the second phase alone advances at the second go, once",
        [in_phases(1, 0, 2)],
        [first],
      ),
      OncePerCast(
        "two rows of every phase advance each once",
        [in_phases(1, 0, -1), in_phases(2, 0, -1)],
        [first, first],
      ),
    ],
    fn(case_) {
      let spell =
        spell_plan.Spell(..holding_rows(rows: case_.rows), phase_delays_ms: [
          0,
          1000,
        ])
      let caster = holding(quests: [3769])
      let #(state, effects) =
        pressed(spell:, caster:, state: cast_state.new(), at: 1000)
      let #(_, fired) = run_as(caster:, state:, effects:, from_ms: 1000)
      assert all_advances(effects:, fired:) == case_.advances as case_.why
    },
  )
}

/// The Spell4Effects 12813, a Proxy row, copied into the spell `parent` to start the spell
/// `child` on the caster (`targetFlags` 1) with no target prerequisite.
fn with_a_proxy_to(
  parent parent: Int,
  child child: Int,
  id id: Int,
  body body: fn(table_store.Tables) -> a,
) -> a {
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 12_813,
    id:,
    with: [
      #("spellId", Integer(parent)),
      #("targetFlags", Integer(1)),
      #("prerequisiteIdTargetApply", Integer(0)),
      #("dataBits00", Integer(child)),
    ],
    body:,
  )
}

pub fn a_childs_rows_count_with_the_use_or_cast_of_the_cast_that_started_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // The railgun's spell 24501 is the child: its row 89873 (quest 3769, delay 6000) is the one
  // that fires, the gated twin 89874 failing its prerequisite for a caster with no quest 3785.
  // A Proxy started from the root's go leaves the use or cast the root was made with to the
  // child, so an objective the use or cast counts is skipped once (`quest_advance.advance`).
  let activated =
    with_a_proxy_to(parent: 1817, child: 24_501, id: 999_005, body: fn(tables) {
      right_clicked(
        tables:,
        creature_id: 26_462,
        caster: standing_with(quests: [3769]),
      )
    })
  let pressed_button =
    with_a_proxy_to(
      parent: 25_306,
      child: 24_501,
      id: 999_006,
      body: fn(tables) { button_pressed(tables:, spell4_id: 25_306) },
    )
  list.each(
    [
      #(
        "a creature's activate cast: the child carries the use of the unit",
        activated,
        WithUse(
          spawn_id: SpawnId(1),
          unit_id: items.its_unit,
          creature_id: 26_462,
          alive_at_press: True,
          by_item: False,
        ),
      ),
      #(
        "a quest button's cast: the child carries the button's cast",
        pressed_button,
        WithCast(spell4_id: 25_306, target: None),
      ),
    ],
    fn(row) {
      let #(why, effects, with) = row
      assert advanced(effects:) == [#([advance(quest: 3769)], with)] as why
    },
  )
}

pub fn an_activation_spell_holding_a_proxy_aimed_at_the_primary_target_is_refused_so_no_child_starts_on_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Seaspine Mollusk (Creature2 26462) casts Spell4 1817 when it is clicked, with the
  // creature's unit as the cast's primary target. Spell4Effects 999104 is a copy of Proxy
  // 83947 (targetFlags 2, Spell4 76766) set in it. The activate cast strikes no one, so a row
  // aimed at the target or an area cannot be planned for it and the click is refused 285: an
  // activation's primary target is never a player a Proxy aimed at the primary target could
  // start a child on, and no child starts on the creature.
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 83_947,
    id: 999_104,
    with: [#("spellId", Integer(1817))],
  )
  let effects =
    right_clicked(
      tables:,
      creature_id: 26_462,
      caster: standing_with(quests: []),
    )
  assert support.refusal_results(effects:)
    == [cast_result.to_value(cast_result.IllegalSpellCast)]
    as "the click is refused as not built"
  assert list.any(support.warning_lines(effects:), fn(line) {
    string.contains(
      line,
      "the effect 999104 of the spell 1817 aims at the target",
    )
  })
    as "and the warning names the row"
  assert support.started_in(effects:) == []
    as "no cast starts, so no child starts on the creature"
}
