//// A Spellslinger under Spell Surge on the game connection: the surged spell a press casts,
//// the Spell Power it spends, and the end of the surge. Expected values come from these
//// places, each named at its assertion:
//// - CastAbilityBagSpell `0x14039a040` through SpellslingerSurgedSpell `0x1405e7e50`: under
////   a node of Spell Surge's buff 47439 (IsSpellSurgeActive `0x1405e7d10`) a press of Quick
////   Draw 43468 casts 76002 and one of Charged Shot 34718 casts 34719, the alternates
////   `Spell4.spell4IdMechanicAlternateSpell` names, when the ability book holds their bases
////   (GetAbilityBookSpell `0x1403bad30`). The swap runs before the threshold step.
//// - The effects the go lists: Spell4Effects 196642 for 76002 and 196513 for 43468 (their
////   first rows, `table_rows -- Spell4Effects spellId=76002`), 80980 for Charged Shot's
////   34766 and 209967 for 79679 (the rows of effectType 73 the go lists, as the existing
////   release test's 80979 for 34722 is).
//// - The costs: Spell4.76002's innate cost (19, 25) and Spell4Thresholds 129's row cost
////   (19, 25), which is paid at the press that opens the charge (Jim, 2026-11-15), so a
////   press under the open threshold and its release pay nothing more. Spell Power is slot 4
////   of the Spellslinger (max 100), written as 0x935 of stat 6 (`opcode.0x935`,
////   `opcode.0x262.resource_stats`).
//// - Spell 47439's persistence 36425 needs Spell Power at least 25
////   (`Spell4.prerequisiteIdCasterPersistence`), which the client never evaluates: the
////   server ends the buff, with 0x7f9 (282), then 0x7fe (`cast.target_node_end`), after the
////   input's own writes.
//// - Spell Surge 47273 ends 47439 through group 615 when pressed again (`Spell4.47273`).
//// - The ability book the entry's 0x1a0 sets (`opcode.0x1a0`): each of its abilities at tier
////   1 in each of the four action sets.
//// The times are the connection's monotonic input times, set by the test.

import cast_support
import connection_rule_support as support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers
import genesis_prime/message/action_set
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/cast_result
import genesis_prime/message/float32
import genesis_prime/message/spell_failed
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/message/spell_threshold_opened
import genesis_prime/message/unit_float_stat_changed
import genesis_prime/step.{type ConnectionStep, OwnEvent}
import genesis_prime/table/id.{ClassId}
import gleam/list
import gleam/option.{None}
import owned_test
import server_proxy_support

const quick_draw = 0

const charged_shot = 1

const spell_surge = 3

fn settings() -> game_connection.Settings {
  Settings(
    ..connection_support.settings(),
    tables: fixture_tables.shared(),
    server_proxies: server_proxy_support.none(),
  )
}

/// The Spellslinger in the world on the fixture's rows with 100 Spell Power, and its
/// unit id.
fn spellslinger() -> #(game_connection.State, Int) {
  let #(state, entered) = entered()
  #(state, connection_support.player_in(entered).unit_id)
}

fn entered() -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.entered_with(
    settings: settings(),
    class_id: 7,
    saved_health: None,
  )
}

fn frames(steps steps: List(ConnectionStep(Request))) -> List(Frame) {
  list.flat_map(steps, fn(taken) { connection_support.written(taken:) })
}

/// A press of the bag index at `ms` and the cast timers it leads to up to 2500 ms later,
/// each strike landing: the state and every step, the press first.
fn press(
  state state: game_connection.State,
  bag_index bag_index: Int,
  ms ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  connection_support.pressed_until(
    state:,
    bag_index:,
    client_cast_id: ms,
    ms:,
    until_ms: ms + 2500,
  )
}

/// The press of Spell Surge at 1000 ms.
fn surging() -> #(game_connection.State, Int, Int) {
  let #(state, unit_id) = spellslinger()
  let #(state, steps) = press(state:, bag_index: spell_surge, ms: 1000)
  let assert [pressed, ..] = steps
  assert connection_support.refusal_results(taken: pressed) == []
    as "Spell Surge 47273 is cast at 100 Spell Power"
  let assert [surge_cast] =
    list.filter(started_casts(frames: frames(steps:)), fn(start) {
      start.spell4_id == 47_439
    })
    as "the press starts the buff 47439"
  #(state, unit_id, surge_cast.cast_id)
}

fn started_casts(
  frames frames: List(Frame),
) -> List(spell_started.SpellStarted) {
  connection_support.decoded(
    frames,
    spell_started.message_id,
    spell_started.decode,
  )
}

/// The Quick Draw each root cast of the frames is, as its Spell4 id: a press tells the
/// caster of its root cast by 0x7fd, which names no spell, and a held key's repeat by a
/// 0x7ff with no parent; every child cast the root leads to is a 0x7ff that names the
/// root (`opcode.0x7ff.root_spell4_id`), so a root cast is the spell its 0x7ffs name. A
/// root cast that is not Quick Draw (the Surge press, whose children name 47273) is left
/// out.
fn quick_draw_casts(frames frames: List(Frame)) -> List(Int) {
  list.fold(frames, [], fn(groups, frame) {
    case
      frame.message_id == 0x07FD,
      frame.message_id == spell_started.message_id
    {
      True, _ -> [[], ..groups]
      _, True ->
        case groups, spell_started.decode(frame.body) {
          _, Ok(started) if started.parent_spell4_id == 0 -> [
            [started.root_spell4_id],
            ..groups
          ]
          [group, ..rest], Ok(started) -> [
            [started.root_spell4_id, ..group],
            ..rest
          ]
          _, _ -> groups
        }
      _, _ -> groups
    }
  })
  |> list.reverse
  |> list.filter_map(fn(group) {
    case
      list.unique(
        list.filter(group, fn(root) { root == 76_002 || root == 43_468 }),
      )
    {
      [root] -> Ok(root)
      _ -> Error(Nil)
    }
  })
}

/// The Spell4Effects id of each effect the frames' gos list, in order.
fn go_effects(frames frames: List(Frame)) -> List(Int) {
  connection_support.decoded(frames, spell_go.message_id, spell_go.decode)
  |> list.flat_map(fn(go) {
    list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  })
}

/// The Spell Power each 0x935 of stat 6 in the frames writes, as the float's bits.
fn spell_power(frames frames: List(Frame)) -> List(Int) {
  connection_support.decoded(
    frames,
    unit_float_stat_changed.message_id,
    unit_float_stat_changed.decode,
  )
  |> list.filter_map(fn(changed) {
    case changed.stat_id == 6 {
      True -> Ok(changed.value)
      False -> Error(Nil)
    }
  })
}

fn bits(values values: List(Float)) -> List(Int) {
  list.map(values, float32.to_bits)
}

fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// The threshold opens the frames write, as the opened spell and the second spell each
/// names.
fn opened(frames frames: List(Frame)) -> List(#(Int, Int)) {
  connection_support.decoded(
    frames,
    spell_threshold_opened.message_id,
    spell_threshold_opened.decode,
  )
  |> list.map(fn(opened) { #(opened.spell4_id, opened.resolving_spell4_id) })
}

/// The Spellslinger's `count` surged Quick Draws, each pressed 3000 ms after the last
/// (past its global cooldown and its cast), from 4000 ms: the state and every step of
/// each press.
fn quick_draws(
  state state: game_connection.State,
  count count: Int,
) -> #(game_connection.State, List(List(ConnectionStep(Request)))) {
  list.fold(
    list.index_map(list.repeat(Nil, count), fn(_, index) { index + 1 }),
    #(state, []),
    fn(so_far, number) {
      let #(state, presses) = so_far
      let #(state, steps) =
        press(state:, bag_index: quick_draw, ms: 1000 + 3000 * number)
      #(state, list.append(presses, [steps]))
    },
  )
}

/// A key of the bag index going up or down at `ms`.
fn key(
  state state: game_connection.State,
  bag_index bag_index: Int,
  held held: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.at(
    state:,
    ms:,
    event: OwnEvent(
      step.Read(connection_support.world_message(
        message_id: 0x04DB,
        body: cast_support.hold_body(bag_index:, target: 0, held:),
      )),
    ),
  )
}

/// A single 0x9a press of the bag index at `ms`, with no timer run.
fn press_once(
  state state: game_connection.State,
  bag_index bag_index: Int,
  ms ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  connection_support.at(
    state:,
    ms:,
    event: OwnEvent(
      step.Read(connection_support.world_message(
        message_id: 0x009A,
        body: cast_support.press_body(
          client_cast_id: ms,
          bag_index:,
          target: 0,
          press: 1,
        ),
      )),
    ),
  )
}

/// The charge opened by the press at `ms` taken to its level 1 (the timer of the first
/// threshold after the opening fires `after_ms` later): the state and the opening step.
fn charged_to_level_1(
  state state: game_connection.State,
  ms ms: Int,
  after_ms after_ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let #(state, opening) = press_once(state:, bag_index: charged_shot, ms:)
  let assert [timer] = list.filter(support.timers_started(opening), cast.owns)
    as "the press opens the charge: one timer of the cast rule, the level 1 timer"
  let #(state, _) =
    connection_support.fired_at(state:, timer:, ms: ms + after_ms)
  #(state, opening)
}

pub fn surge_then_quick_draw_casts_76002_and_pays_25_spell_power_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _, _) = surging()
  let #(_, steps) = press(state:, bag_index: quick_draw, ms: 4000)
  let all = frames(steps:)
  assert quick_draw_casts(frames: all) == [76_002]
    as "a node of 47439 is on the unit and the book holds 52215: the press casts 76002 (its children name it as root), and not 43468"
  assert spell_power(frames: all) == bits(values: [75.0])
    as "76002's innate cost (19, 25) takes 25 from 100 Spell Power, as 0x935 of stat 6"
  assert !list.contains(ids(frames: all), spell_failed.message_id)
    as "Spell Power 75 is at least 25, so 36425 holds and Surge stays on"
}

pub fn four_surged_quick_draws_spend_spell_power_to_0_and_end_surge_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, unit_id, surge_cast_id) = surging()
  let #(state, presses) = quick_draws(state:, count: 4)
  assert list.map(presses, fn(steps) { spell_power(frames: frames(steps:)) })
    == [
      bits(values: [75.0]),
      bits(values: [50.0]),
      bits(values: [25.0]),
      bits(values: [0.0]),
    ]
    as "each surged Quick Draw takes 25 from Spell Power: 75, 50, 25 and 0"
  let assert [first, second, third, fourth] = presses
  assert !list.contains(ids(frames: frames(steps: first)), 0x07F9)
    && !list.contains(ids(frames: frames(steps: second)), 0x07F9)
    && !list.contains(ids(frames: frames(steps: third)), 0x07F9)
    as "at 75, 50 and 25 Spell Power 36425 holds: Surge stays on"
  let assert [press_step, ..] = fourth
  let written = connection_support.written(taken: press_step)
  let written_ids = ids(frames: written)
  assert list.drop(written_ids, list.length(written_ids) - 2)
    == [0x07F9, 0x07FE]
    as "the input that brings Spell Power to 0 ends the buff after its own writes: 0x7f9 then 0x7fe"
  assert list.contains(
    list.take(written_ids, list.length(written_ids) - 2),
    0x0935,
  )
    as "its own writes hold the 0x935"
  let assert [failure] =
    list.filter(written, fn(frame) {
      frame.message_id == spell_failed.message_id
    })
  let assert Ok(failed) = spell_failed.decode(failure.body)
    as "the 0x7f9 decodes"
  assert failed.unit_id == unit_id
    as "0x7f9 names the player's unit (cast.target_node_end)"
  assert cast_result.to_value(failed.result) == 282
    as "Spell4.47439's persistence 36425 gives Prereq_CasterPersistence, 282"
  let assert [finished] =
    connection_support.decoded(
      written,
      spell_finished.message_id,
      spell_finished.decode,
    )
  assert finished.cast_id == surge_cast_id
    as "0x7fe ends the cast of 47439 that the Surge press started"
  let #(_, fifth) = press(state:, bag_index: quick_draw, ms: 16_000)
  let all = frames(steps: fifth)
  assert quick_draw_casts(frames: all) == [43_468]
    as "Surge is over: the press casts Quick Draw 43468"
  assert spell_power(frames: all) == []
    as "Quick Draw 43468 holds no cost, so no 0x935"
}

pub fn a_surged_charged_shot_pays_25_at_the_opening_press_and_nothing_at_release_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _, _) = surging()
  let #(state, opening) = charged_to_level_1(state:, ms: 4000, after_ms: 600)
  let opened_frames = connection_support.written(taken: opening)
  assert opened(frames: opened_frames) == [#(34_719, 34_718)]
    as "the press resolves to 34719 before the threshold step: 0x816 opens 34719 and names the bag ability 34718 as its second spell, which a later press is matched against (`FindThresholdBySecondSpell` 0x1403c0190)"
  assert spell_power(frames: opened_frames) == bits(values: [75.0])
    as "Spell4Thresholds 129's cost (19, 25) is paid at the opening press: 100 less 25"
  let #(_, released) = press_once(state:, bag_index: charged_shot, ms: 4700)
  assert connection_support.refusal_results(taken: released) == []
  let released_frames = connection_support.written(taken: released)
  assert go_effects(frames: released_frames) == [80_980]
    as "the level 1 release fires 34766 (Spell4Thresholds 192), whose go lists Spell4Effects 80980"
  assert spell_power(frames: released_frames) == []
    as "the opening press paid, so the release pays nothing more"
}

pub fn a_surged_charged_shot_at_25_ends_surge_and_its_key_up_fires_the_surged_stage_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, unit_id, surge_cast_id) = surging()
  let #(state, _) = quick_draws(state:, count: 3)
  let #(state, opening) = charged_to_level_1(state:, ms: 13_000, after_ms: 600)
  let written = connection_support.written(taken: opening)
  assert opened(frames: written) == [#(34_719, 34_718)]
  let written_ids = ids(frames: written)
  assert list.drop(written_ids, list.length(written_ids) - 2)
    == [0x07F9, 0x07FE]
    as "25 Spell Power paid to 0 ends Surge in that input, after its own writes"
  assert spell_power(frames: written) == bits(values: [0.0])
  let assert [failure] =
    list.filter(written, fn(frame) {
      frame.message_id == spell_failed.message_id
    })
  let assert Ok(failed) = spell_failed.decode(failure.body)
    as "the 0x7f9 decodes"
  assert failed.unit_id == unit_id && cast_result.to_value(failed.result) == 282
  let assert [finished] =
    connection_support.decoded(
      written,
      spell_finished.message_id,
      spell_finished.decode,
    )
  assert finished.cast_id == surge_cast_id
  let #(_, up) = key(state:, bag_index: charged_shot, held: 0, ms: 13_700)
  assert connection_support.refusal_results(taken: up) == []
  assert go_effects(frames: connection_support.written(taken: up)) == [80_980]
    as "the key up swaps nothing now that Surge is gone, so the swapped 34718 is the open threshold's second spell: it fires 34719's stage 34766, as the client's press does (`ResolveThresholdSpell` 0x1403bfd60)"
}

pub fn after_surge_ends_mid_charge_a_bag_press_casts_plain_charged_shot_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _, _) = surging()
  let #(state, _) = quick_draws(state:, count: 3)
  let #(state, _) = charged_to_level_1(state:, ms: 13_000, after_ms: 600)
  let #(_, again) = press_once(state:, bag_index: charged_shot, ms: 16_000)
  assert connection_support.refusal_results(taken: again) == []
    as "Surge ended: the swap leaves 34718, which is the second spell of the open 34719 threshold, so the client finds that threshold (`FindThresholdBySecondSpell` 0x1403c0190) and the press is its own, never a refusal"
  let written = connection_support.written(taken: again)
  assert opened(frames: written) == []
    as "the press goes to the open threshold and opens no new one"
  assert go_effects(frames: written) == [80_980]
    as "the open threshold is at level 1: the press fires 34766 (Spell4Thresholds 192), whose go lists Spell4Effects 80980"
  assert spell_power(frames: written) == []
    as "the opening press paid, so the release pays nothing more"
}

pub fn a_surged_charged_shot_press_under_its_open_threshold_pays_nothing_more_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _, _) = surging()
  let #(state, _) = press_once(state:, bag_index: charged_shot, ms: 4000)
  let #(_, again) = press_once(state:, bag_index: charged_shot, ms: 4100)
  assert connection_support.refusal_results(taken: again) == []
  let written = connection_support.written(taken: again)
  assert opened(frames: written) == []
    as "the press goes to the open threshold of 34719 and opens no new one"
  assert go_effects(frames: written) == [209_967]
    as "the uncharged release fires row 129's stage 79679, whose go lists Spell4Effects 209967"
  assert spell_power(frames: written) == []
    as "row 129's cost was paid at the opening press, and nothing is charged again"
}

pub fn a_held_quick_draw_swaps_at_each_repeat_while_surge_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, _, _) = surging()
  let #(state, down) = key(state:, bag_index: quick_draw, held: 1, ms: 4000)
  let #(state, steps) =
    connection_support.casts_run(
      state:,
      pending: connection_support.cast_timers(steps: [down], ms: 4000),
      until_ms: 30_000,
      steps: [down],
    )
  let all = frames(steps:)
  assert list.take(quick_draw_casts(frames: all), 5)
    == [76_002, 76_002, 76_002, 76_002, 43_468]
    as "76002 at once and at each repeat while Surge holds (0x1405e7e50 runs in each bag cast); the fourth takes Spell Power to 0 and ends Surge, so the next repeat is Quick Draw 43468"
  assert list.take(spell_power(frames: all), 4)
    == bits(values: [75.0, 50.0, 25.0, 0.0])
  let #(_, up) = key(state:, bag_index: quick_draw, held: 0, ms: 30_000)
  assert connection_support.refusal_results(taken: up) == []
}

pub fn a_spellslinger_entry_lists_its_alternates_in_the_ability_book_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, entered) = entered()
  let entry = connection_support.written(taken: entered)
  let assert [tiers_frame] =
    list.filter(entry, fn(frame) { frame.message_id == 0x01A0 })
  let assert Ok(tiers) = ability_tiers.decode(tiers_frame.body)
    as "0x1a0 decodes"
  let book = [27_638, 20_684, 20_325, 31_213, 52_215, 20_685]
  assert tiers.tiers
    == list.flat_map(book, fn(base) {
      list.map([0, 1, 2, 3], fn(action_set_index) {
        AbilityTier(spell4_base_id: base, tier: 1, action_set_index:)
      })
    })
    as "opcode.0x1a0: the bag's four bases, then the alternates of Quick Draw (52215) and Charged Shot (20685) that Spell4.spell4IdMechanicAlternateSpell names, each at tier 1 in each of the four action sets"
  let assert [set_frame] =
    list.filter(entry, fn(frame) { frame.message_id == 0x019D })
  let assert Ok(set) = action_set.decode(set_frame.body) as "0x19d decodes"
  assert set.shortcuts
    == list.index_map([27_638, 20_684, 20_325], fn(base, slot) {
      ActionShortcut(
        shortcut_type: 4,
        location: 4,
        bag_index: slot,
        object_id: base,
      )
    })
    as "opcode.0x19d: the bar holds the first three abilities in slots 0 to 2, as before"
  let #(_, warrior) =
    connection_support.entered_with(
      settings: settings(),
      class_id: 1,
      saved_health: None,
    )
  let assert [warrior_tiers_frame] =
    list.filter(connection_support.written(taken: warrior), fn(frame) {
      frame.message_id == 0x01A0
    })
  let assert Ok(warrior_tiers) = ability_tiers.decode(warrior_tiers_frame.body)
    as "the Warrior's 0x1a0 decodes"
  let assert Ok(set) =
    loadout.of(
      tables: fixture_tables.shared(),
      class_id: ClassId(1),
      faction_id: 166,
    )
  assert warrior_tiers.tiers
    == list.flat_map(loadout.bag(loadout: set), fn(base) {
      list.map([0, 1, 2, 3], fn(action_set_index) {
        AbilityTier(spell4_base_id: base.value, tier: 1, action_set_index:)
      })
    })
    as "no Warrior ability names an alternate: its 0x1a0 lists its bag only, as before"
}

pub fn a_second_surge_press_ends_surge_and_quick_draw_casts_plain_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, unit_id, surge_cast_id) = surging()
  let #(state, steps) = press(state:, bag_index: spell_surge, ms: 4000)
  assert connection_support.decoded(
      frames(steps:),
      spell_targets_removed.message_id,
      spell_targets_removed.decode,
    )
    == [spell_targets_removed.SpellTargetsRemoved(surge_cast_id, [unit_id])]
    as "Spell4.47273's ForceRemove (effect 111668, group list 615) takes the 47439 cast the first press started off the player: 0x811, the client's own end of the buff"
  let #(_, draws) = press(state:, bag_index: quick_draw, ms: 7000)
  let drawn = frames(steps: draws)
  assert quick_draw_casts(frames: drawn) == [43_468]
    as "Surge is off: the next Quick Draw casts 43468"
  assert spell_power(frames: drawn) == []
    as "Quick Draw 43468 holds no cost, so no 0x935"
}
