//// The cast rule (`genesis_prime/game/cast`) for the level-up fanfare: a tier of the Level Up
//// spell the client's 0x07A5 asks for, on a clock the test drives. Expected values come from
//// these places:
//// - `opcode.0x7ff`, `opcode.0x7f4` and `opcode.0x7fe`: the start names the Spell4 as spell and
////   root, no parent, and the caster as its own primary target; a go lists the caster in a
////   target info with the effect info of the row and the fourth value 0, which leaves the
////   lifetime to the client; the cast is finished by 0x7fe.
//// - `spell.level_up.cast`: the answer is a full cast with no 0x7fd (that answers a press), and
////   its 0x7fe comes when the effect's life is over, 5000 ms after the go (Spell4Effects
////   durationTime): a finish at once would destroy the node and with it the effect
////   (`cast.target_node_end`).
//// - `Spell4StackGroup 2` (stackCap 0): two live casts of the spell coexist, so the second
////   cast's go ends nothing of the first.
//// - `Spell4.tierIndex.level_up`: global cooldown kind 3 starts none, the Spell4 ids of the
////   tiers (`level_up_support.tiers`).

import cast_support as support
import fixture_tables
import genesis_prime/client_connection.{CastFinished, CastStarted, CastWent}
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Effect, type State} as cast_state
import genesis_prime/game/level_up
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/step.{ConnectionId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import level_up_support.{Tier}
import owned_test

/// The unit id of the caster of `support.caster()`.
const caster_unit = 7

fn fanfare(level level: Int) -> Spell {
  let assert Ok(spell) =
    level_up.spell_of(
      fanfares: level_up.fanfares(tables: fixture_tables.shared()),
      level:,
    )
    as "the level has a fanfare"
  spell
}

/// The state and effects of the fanfare of the level asked for at `ms`, its go answered.
fn started(
  state state: State,
  level level: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    cast.level_up_started(
      cast: state,
      caster: support.caster(),
      spell: fanfare(level:),
      now: support.at(ms:),
    )
  support.answered_with_no_targets(state:, effects:, at: ms)
}

fn started_ids(
  effects effects: List(Effect),
) -> List(spell_started.SpellStarted) {
  list.map(
    support.frames_of(message_id: spell_started.message_id, effects:),
    fn(frame) {
      let assert Ok(start) = spell_started.decode(frame.body)
        as "a 0x7ff the rule wrote decodes"
      start
    },
  )
}

fn goes(effects effects: List(Effect)) -> List(spell_go.SpellGo) {
  list.map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      go
    },
  )
}

pub fn a_fanfare_cast_starts_goes_at_once_and_ends_after_the_effects_life_with_no_cooldown_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([2, 4, 12, 50], fn(level) {
    let Tier(spell4_id:, effect_id:, ..) = level_up_support.tier(level:)
    let name = "level " <> int.to_string(level) <> ": "
    let #(state, effects) = started(state: cast_state.new(), level:, at: 1000)
    assert support.ids(frames: support.writes(effects:)) == [0x07FF, 0x07F4]
      as {
        name
        <> "the start, then the go at once, no 0x7fd (a press's answer) and no 0x804"
      }
    let assert [start] = started_ids(effects:)
    assert start.spell4_id == spell4_id && start.root_spell4_id == spell4_id
      as { name <> "the tier's Spell4 is spell and root (opcode.0x7ff)" }
    assert start.parent_spell4_id == 0
      && start.caster_unit_id == caster_unit
      && start.primary_target_unit_id == caster_unit
      as { name <> "no parent, the caster its own primary target" }
    let assert [go] = goes(effects:)
    assert go.cast_id == start.cast_id
      as { name <> "the go is the start's cast" }
    let assert [info] = go.targets
    assert info.unit_id == caster_unit && info.instance_count == 1
      as { name <> "one target info, naming the caster, one application" }
    assert info.effects
      == [
        SpellEffectInfo(
          spell4_effects_id: effect_id,
          instance_id: 1,
          delay_ms: 0,
          lifetime_ms: 0,
          result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
        ),
      ]
      as {
        name
        <> "the tier's row with the life 0 that leaves it to the client (opcode.0x7f4.effect_time)"
      }
    let viewers = [ConnectionId(2), ConnectionId(3)]
    let tells = support.tells(effects:)
    assert list.all(viewers, fn(viewer) {
      list.contains(tells, #(viewer, CastStarted(start:)))
      && list.contains(tells, #(viewer, CastWent(go:)))
    })
      as { name <> "each viewer is told the start and the go the player reads" }
    assert state.global_cooldown_ends_ms == None
      as {
        name <> "global cooldown kind 3 starts none (Spell4.tierIndex.level_up)"
      }
    let assert [#(timer, 5000)] = support.started_timers(effects:)
      as {
        name
        <> "one timer of the row's 5000 ms: the effect's life (spell.level_up.cast)"
      }
    // The go is at 1000, so the life is over at 6000.
    let #(state, early) = support.fired(state:, timer:, at: 5999)
    assert support.frames_of(message_id: 0x07FE, effects: early) == []
      as {
        name
        <> "a timer that fires with life left finishes nothing (cast.target_node_end)"
      }
    let assert [#(timer, 1)] = support.started_timers(effects: early)
    let #(state, ended) = support.fired(state:, timer:, at: 6000)
    assert support.ids(frames: support.writes(effects: ended)) == [0x07FE]
      as {
        name
        <> "the finish alone: it destroys every node of the cast (cast.target_node_end)"
      }
    assert support.finished_ids(support.writes(effects: ended))
      == [start.cast_id]
      as { name <> "0x7fe of the cast" }
    assert list.any(support.tells(effects: ended), fn(tell) {
      tell.1 == CastFinished(cast_id: start.cast_id)
    })
      as { name <> "each viewer is told the finish" }
    assert state.casts == dict.new() && state.lingering == dict.new()
      as { name <> "the state holds no live cast after" }
  })
}

pub fn two_fanfares_in_one_second_are_two_casts_that_end_on_their_own_timers_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([0, 1000, 4999, 5000], fn(gap) {
    let name =
      "a second request " <> int.to_string(gap) <> " ms after the first: "
    let #(state, first) = started(state: cast_state.new(), level: 4, at: 1000)
    let #(state, second) = started(state:, level: 5, at: 1000 + gap)
    let assert [first_start] = started_ids(effects: first)
    let assert [second_start] = started_ids(effects: second)
    assert first_start.cast_id != second_start.cast_id
      as { name <> "two cast ids" }
    assert support.ids(frames: support.writes(effects: second))
      == [0x07FF, 0x07F4]
      as {
        name
        <> "the second has its own start and go, and ends nothing of the first (Spell4StackGroup 2: stackCap 0)"
      }
    let assert [#(first_timer, 5000)] = support.started_timers(effects: first)
    let assert [#(second_timer, 5000)] = support.started_timers(effects: second)
    let #(state, first_ended) =
      support.fired(state:, timer: first_timer, at: 6000)
    let #(state, second_ended) =
      support.fired(state:, timer: second_timer, at: 6000 + gap)
    assert support.finished_ids(support.writes(effects: first_ended))
      == [first_start.cast_id]
      as {
        name <> "the first's 0x7fe comes 5000 ms after its go, its own only"
      }
    assert support.finished_ids(support.writes(effects: second_ended))
      == [second_start.cast_id]
      as {
        name
        <> "the second's 0x7fe comes 5000 ms after its own go, its own only"
      }
    assert state.casts == dict.new() && state.lingering == dict.new()
      as { name <> "both casts are over" }
  })
}
