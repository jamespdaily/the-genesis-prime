//// Casts on the whole server: what the caster and a player in sight read of a press (0x07FD,
//// 0x07FE and the effects), the stalker, medic, engineer, warrior and spellslinger abilities
//// with their children, their states and their ends.
//// Every wait is for bytes the server writes, with a deadline a passing test never
//// reaches. The tree, the logins and the players come from `game_wire_support`.

import bot_frames
import cast_support
import character_tables
import client_tables
import driven_time
import fixture_tables
import game_client
import game_connection_support as connection_support
import game_wire_support.{
  type TwoEntered, TwoEntered, beast_health_in, beast_place,
  enters_and_sees_the_beasts, finishes, health_in, index_where, location_4_items,
  new_player_at_level, refusals, send_play, two_players_enter,
  two_players_enter_after, two_players_enter_one_map, unit_of, walk_to,
  world_with_a_beast_ahead, world_with_beasts, world_with_spawns,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/casting
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state
import genesis_prime/message/damage_type
import genesis_prime/message/float32
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_effect_damage
import genesis_prime/message/spell_effect_info
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_effect_tick
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_target_info
import genesis_prime/message/unit_cc_state_applied
import genesis_prime/message/unit_cc_state_ended
import genesis_prime/message/unit_create_cast
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_float_stat_changed
import genesis_prime/message/unit_item_visuals_changed.{UnitItemVisualsChanged}
import genesis_prime/message/unit_properties_changed
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/server
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_life.{Attack, Combat}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import login_support
import owned_test
import planted_table
import pog
import spawn_support
import unitest
import world_entry_support

/// As `two_players_enter_one_map`, the first player being of the class given, the
/// server holding the fixture's rows (the starting abilities' own trees) and its game
/// connections and its World taking their time and their timers from `time`, which a
/// test whose casts run on timers moves by hand.
fn two_players_of_class_enter_one_map_with(
  first_class first_class: Int,
  time time: driven_time.Time,
) -> TwoEntered {
  two_players_enter_on(tables: character_tables.shared(), first_class:, time:)
}

/// As `two_players_of_class_enter_one_map_with`, on these tables.
fn two_players_enter_on(
  tables tables: table_store.Tables,
  first_class first_class: Int,
  time time: driven_time.Time,
) -> TwoEntered {
  two_players_enter(started: started_on(tables:, time:), first_class:, level: 9)
}

/// A server holding these tables, its game connections and its World taking their time and
/// their timers from `time`.
fn started_on(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  login_support.start_with(time:, change: fn(settings) {
    server.Settings(
      ..settings,
      game: server.Served(
        ..settings.game,
        settings: connection_state.Settings(..settings.game.settings, tables:),
      ),
    )
  })
}

pub fn a_players_press_is_answered_0x7fd_go_and_finish_and_a_player_in_sight_reads_the_same_cast_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_enter_one_map(time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 2,
    target: 0,
  )
  let #(own, _) = game_client.read_kept(game: first, have: first_have, count: 3)
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 3)
  let assert [
    game_client.CastConfirmed(client_cast_id: 1, server_cast_id: cast_id),
    game_client.CastWent(cast_id: went, phase: 0),
    game_client.CastFinished(cast_id: finished),
  ] = game_client.casts_in(frames: own)
    as "opcode.0x7fd, 0x7f4 and 0x7fe: the caster's client is answered, Paralytic Surge being instant (Spell4.42352: no cast time) and starting no child"
  assert went == cast_id && finished == cast_id
  let assert [
    game_client.CastStarted(
      cast_id: seen_id,
      root_spell4_id: root,
      parent_spell4_id: 0,
      caster_unit_id: 1,
      ..,
    ),
    game_client.CastWent(cast_id: seen_went, phase: 0),
    game_client.CastFinished(cast_id: seen_finished),
  ] = game_client.casts_in(frames: seen)
    as "opcode.0x7ff, 0x7f4 and 0x7fe: the watcher's client reads the same cast, started by unit 1 with no parent"
  assert seen_id == cast_id && seen_went == cast_id && seen_finished == cast_id
    as "one cast id, which no other unit's cast shares (0x140561c30)"
  assert root == 42_352
    as "the root is the pressed spell, Spell4 42352, Paralytic Surge, the Medic's third level-1 ability (SpellLevel 1089) at bag index 2 (opcode.0x7ff.root_parent)"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The unit and the Spell4Effects id and delay of each effect info of one decoded go.
fn effect_infos_of(go go: spell_go.SpellGo) -> List(#(Int, List(#(Int, Int)))) {
  list.map(go.targets, fn(target) {
    #(
      target.unit_id,
      list.map(target.effects, fn(effect) {
        #(effect.spell4_effects_id, effect.delay_ms)
      }),
    )
  })
}

/// The effect infos of the go of the cast `cast_id` among the frames.
fn go_effect_infos(
  frames frames: List(Frame),
  cast_id cast_id: Int,
) -> List(#(Int, List(#(Int, Int)))) {
  list.filter(frames, fn(frame) { frame.message_id == spell_go.message_id })
  |> list.filter_map(fn(frame) { spell_go.decode(frame.body) })
  |> list.filter(fn(go) { go.cast_id == cast_id })
  |> list.flat_map(effect_infos_of)
}

pub fn a_watcher_is_told_the_delays_of_spell4_36201_as_the_table_has_them_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client row sends a player to cast Spell4 36201 (an explorer route's music), which
  // holds the Spell4Effects row 74798 (type 17, flags 2, delay 1) and the type 80 row
  // 135368 (delay 0) on the primary target: the Medic's bag index 2 (SpellLevel 1089,
  // Paralytic Surge) is given it, so a whole server tells the go of a real spell with
  // both rows.
  use tables <- fixture_tables.changed(table: "SpellLevel", id: 1089, with: [
    #("spell4Id", planted_table.Integer(36_201)),
  ])
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_enter_on(tables:, first_class: 4, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 2,
    target: 0,
  )
  let #(own, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  let assert Ok(cast_id) =
    game_client.confirmed_cast_of(frames: own, client_cast_id: 1)
    as "opcode.0x7fd: the press of Spell4 36201 is answered with its server cast id"
  let #(seen, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      go_effect_infos(frames:, cast_id:) != []
    })
  assert go_effect_infos(frames: seen, cast_id:)
    == [#(1, [#(74_798, 1), #(135_368, 0)])]
    as "opcode.0x7f4.first_start: the type 80 row 135368 starts at delay 0, so the client builds the buff and row 74798 (delay 1, flags 2) is told its own 1"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_medics_discharge_pulses_three_times_and_a_player_in_sight_reads_the_same_casts_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 4, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 0,
    target: 0,
  )
  let pulses = [
    "went k1 p0",
    "started k2 80382 root 58832 parent 58832",
    "went k2 p0",
    "started k3 42569 root 58832 parent 80382",
    "went k3 p0",
    "finished k2",
    "went k1 p1",
    "started k4 80382 root 58832 parent 58832",
    "went k4 p0",
    "started k5 42569 root 58832 parent 80382",
    "went k5 p0",
    "finished k4",
    "went k1 p2",
    "started k6 80382 root 58832 parent 58832",
    "went k6 p0",
    "started k7 80383 root 58832 parent 80382",
    "went k7 p0",
    "started k8 42568 root 58832 parent 80383",
    "went k8 p0",
    "finished k8",
    "finished k7",
    "finished k6",
    "finished k1",
  ]
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The channel ends at its channelMaxTime, 1250 ms after the press, the pulses
  // coming every channelPulseTime, 410 ms.
  driven_time.advance(time:, ms: 1250)
  let #(later, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == ["confirmed k1", ..pulses]
    as "Spell4.58832, Discharge, the Medic's first level-1 ability (SpellLevel 631): the accept, then a go for each of its three pulses (channelPulseTime 410, channelMaxTime 1250: 0x14053d1f0), each starting its Proxy 80382 (Spell4Effects 173926, phaseFlags -1) with the pulse index as its phase (opcode.0x7f4.phase); 80382's Proxies 212835 (42569, gate Prerequisite 33154: fewer than 2 stacks) start Power Charge on pulses 0 and 1 and 212838 (80383, gate 32921: exactly 2 stacks) starts 80383 on pulse 2, whose Proxy 212837 starts 42568; then the finish"
  let #(seen, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert cast_support.cast_lines(frames: seen)
    == ["started k1 58832 root 58832 parent 0", ..pulses]
    as "opcode.0x7ff, 0x7f4 and 0x7fe: a player in sight reads the same casts, started by unit 1 with no parent"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// `opcode.0x262.casts` and `cast.target_node_end`: a player that enters beside a Medic
/// holding the bar of Gamma Rays (Spell4 29874, castTime 1250 ms) is created the Medic's
/// unit with the cast listed, not yet gone, and named as its cast in progress; the
/// cast's go and its 0x7fe are then written to it, since the client ends a cast only by
/// the 0x7fe it is sent.
pub fn a_viewer_joining_beside_a_casting_player_shows_its_cast_bar_and_writes_its_end_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    first_acted:,
    second_burst:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started: started_on(tables: character_tables.shared(), time:),
      first_class: 4,
      level: 9,
      first_acts: fn(first, have) {
        // Gamma Rays is the Medic's second level-1 ability, so bag index 1.
        game_client.press_ability(
          game: first,
          client_cast_id: 1,
          bag_index: 1,
          target: 0,
        )
        game_client.read_until_pong(game: first, have:, number: 1)
      },
    )
  let assert [game_client.CastConfirmed(server_cast_id: cast_id, ..)] =
    game_client.casts_in(frames: first_acted)
    as "the press is accepted (opcode.0x7fd) and Gamma Rays' cast time holds its first go"
  let assert Ok(seen_first) = list.last(second_burst)
    as "the second player's entry ends with the 0x262 of the first"
  let created = game_client.unit_create_player_in(frames: [seen_first])
  assert created.unit_id == 1
  assert list.map(created.tail.casts, fn(entry) {
      #(entry.caster_unit_id, entry.cast_id, entry.spell4_id, entry.started)
    })
    == [#(1, cast_id, 29_874, 1)]
    as "opcode.0x262.casts: the create lists the cast the Medic holds the bar of, not yet gone (state 2, bit 1)"
  assert created.tail.cast_id == cast_id
    as "and names it as the cast in progress, which the client looks up in that list (SetUnitCast 0x1404697a0)"
  driven_time.advance(time:, ms: 1250)
  // The first player's pong comes after the go and the finish the clock moved, so the
  // viewer's connection has been told them by the time its own pong comes.
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let #(later, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let own_events = [
    game_client.CastWent(cast_id:, phase: 0),
    game_client.CastFinished(cast_id:),
  ]
  assert list.filter(game_client.casts_in(frames: later), list.contains(
      own_events,
      _,
    ))
    == own_events
    as "the viewer is written the cast's go and its end: the cast is one it was given"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// `opcode.0x262.casts`, `opcode.0x811` and `cast.target_node_end`: a player that enters
/// beside a Medic whose Discharge has pulsed once (410 ms after the press, starting a
/// Power Charge, Spell4 42569, whose Fluff row 96819 lasts until removed) is created the
/// Medic's unit with Discharge listed as the cast in progress and the Power Charge listed
/// beside it with a target info on the Medic's unit (index 0, flags 0, count 1, a Hit, the
/// row at delay 0 and lifetime 0); the clock then moves past the pulse that takes the
/// Power Charges off the Medic (Spell4Effects 212836, Spell4 80383), and the viewer is
/// written the 0x811 that ends the Power Charge it was listed, since the client ends a
/// buff only by what it is sent.
pub fn a_viewer_joining_beside_a_medic_holding_power_charges_lists_them_and_writes_their_end_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(
    started:,
    first:,
    second:,
    second_burst:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started: started_on(tables: character_tables.shared(), time:),
      first_class: 4,
      level: 9,
      first_acts: fn(first, have) {
        // Discharge is the Medic's first level-1 ability, so bag index 0.
        game_client.press_ability(
          game: first,
          client_cast_id: 1,
          bag_index: 0,
          target: 0,
        )
        let #(pressed, have) =
          game_client.read_until_pong(game: first, have:, number: 1)
        // The first pulse comes 410 ms after the press (channelPulseTime).
        driven_time.advance(time:, ms: 500)
        let #(pulsed, have) =
          game_client.read_until_pong(game: first, have:, number: 2)
        #(list.append(pressed, pulsed), have)
      },
    )
  let assert Ok(seen_first) = list.last(second_burst)
    as "the second player's entry ends with the 0x262 of the first"
  let created = game_client.unit_create_player_in(frames: [seen_first])
  assert created.unit_id == 1
  let assert [discharge, power_charge] =
    list.sort(created.tail.casts, fn(left, right) {
      int.compare(left.cast_id, right.cast_id)
    })
    as "the create lists Discharge and the one Power Charge the first pulse started"
  assert #(
      discharge.caster_unit_id,
      discharge.spell4_id,
      discharge.started,
      discharge.targets,
    )
    == #(1, 58_832, 0, [])
    as "Discharge is listed in state 3 (its first go has gone) and holds no node"
  assert #(
      power_charge.caster_unit_id,
      power_charge.spell4_id,
      power_charge.started,
    )
    == #(1, 42_569, 0)
    as "the Power Charge is listed in state 3, a cast of the Medic that is not the current cast"
  assert list.map(power_charge.targets, fn(target) {
      #(
        target.unit_id,
        target.index,
        target.flags,
        target.instance_count,
        target.combat_result,
        list.map(target.effects, fn(effect) {
          #(
            effect.spell4_effects_id,
            effect.instance_id,
            effect.delay_ms,
            effect.lifetime_ms,
          )
        }),
      )
    })
    == [#(1, 0, 0, 1, combat_result.Hit, [#(96_819, 1, 0, 0)])]
    as "its one target is the Medic's unit with row 96819, delay 0 and lifetime 0 (until removed)"
  assert created.tail.cast_id == discharge.cast_id
    as "the cast in progress is Discharge, which the client looks up in that list"
  driven_time.advance(time:, ms: 800)
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  let #(later, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert list.contains(
    game_client.targets_removed_in(frames: later),
    #(power_charge.cast_id, [1]),
  )
    as "the viewer is written the 0x811 that takes the Power Charge off the Medic: the buff it was listed ends on its screen"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_stalkers_two_taps_of_shred_open_and_close_the_threshold_and_a_player_in_sight_reads_both_casts_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 5, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 0,
    target: 0,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The Proxy's phases come 133, 300 and 333 ms after the cast (SpellPhase 3712
  // to 3714), so it is over 766 ms in and the global cooldown, 1000 ms from the
  // press, is not.
  driven_time.advance(time:, ms: 800)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == [
      "confirmed k1",
      "opened 38765 k1",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
    ]
    as "Spell4.38765, Shred (SpellLevel 780, thresholdTime 4000): the first tap casts it and opens the threshold with 0x816 (opcode.0x816), its Proxy 38767 starts in phase 0 (Spell4Effects 83776) and goes in three phases (SpellPhase 3712 to 3714); the Stalker's passive 45057 starts 60724 beside it 50 ms in (its ungated Proxy 147125)"
  game_client.press_ability(
    game: first,
    client_cast_id: 2,
    bag_index: 0,
    target: 0,
  )
  let #(held, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  assert cast_support.cast_lines(frames: held) == []
    as "the second tap is held for the global cooldown: the server has written nothing for it"
  driven_time.advance(time:, ms: 200)
  let #(own, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 4)
  assert cast_support.cast_lines(frames: own)
    == [
      "confirmed k1",
      "went k1 p0",
      "started k2 39467 root 38765 parent 38766",
      "finished k1",
      "closed 38765 1",
    ]
    as "Spell4Thresholds 238: the second tap, held until the global cooldown ends (Spell4.38765: kind 0, SpellCoolDown 115, 1000 ms), casts the stage 38766 and 0x814 closes the threshold with the cooldown bit (opcode.0x814)"
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 15)
  assert cast_support.cast_lines(frames: seen)
    == [
      "started k1 38765 root 38765 parent 0",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
      "started k4 38766 root 38765 parent 38765",
      "went k4 p0",
      "started k5 39467 root 38765 parent 38766",
      "finished k4",
    ]
    as "opcode.0x7ff.root_parent and cast.stage_root_parent: a player in sight reads the base cast with parent 0 and the stage with root and parent 38765, and no threshold message"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// Presses the ability, moves the clock `advance_ms` on so the stage Proxy's phases fire,
/// and reads until `gos` gos of the player's own casts have arrived and the server has
/// written all it held for this connection (pings numbered `pong` and `pong + 1`),
/// giving the frames of the press. A refusal of the press (0x7fc) fails at once, naming
/// its result, because no go would follow it and the Beast's own attacks would keep the
/// wait for them alive for ever, with the test's deadline only warning. `advance_ms` must be in [500, 1133).
fn press_and_read_gos(
  game game: game_client.Game,
  have have: BitArray,
  time time: driven_time.Time,
  client_cast_id client_cast_id: Int,
  advance_ms advance_ms: Int,
  gos gos: Int,
  pong pong: Int,
  beast beast: Int,
) -> #(List(Frame), BitArray) {
  assert advance_ms >= 500 && advance_ms < 1133
    as "the advance is at least 500 ms, so the global cooldown's 500 ms refusal window has passed (below it a second tap is refused with result 14), and under 1133 ms, because both stage Proxies start with no delay (Spell4Effects 83776 and 83782, delayTime 0) and their first phase is at 133 ms (SpellPhase 3712 and 4032), so the first Beast round's 1000 ms strike deadline (strike_tell.deadline_ms) falls at press + 1133 and an advance past it closes that round in driven time while the Beast's real answer is still coming"
  game_client.press_ability(game:, client_cast_id:, bag_index: 0, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: pong)
  driven_time.advance(time:, ms: advance_ms)
  let #(later, have) =
    game_client.read_until(game:, have:, found: fn(later) {
      let seen = list.append(pressed, later)
      list.length(own_go_targets(frames: seen, beast:)) >= gos
      || refusals(frames: seen) != []
    })
  let #(rest, have) =
    game_client.read_until_pong(game:, have:, number: pong + 1)
  let frames = list.flatten([pressed, later, rest])
  assert refusals(frames:) == []
    as "opcode.0x7fc: the press is accepted, so no refusal is written"
  #(frames, have)
}

/// The targets of each go of a cast that is not the Beast's, in order: a Beast a
/// player strikes fights back, and its own gos name the player (the design of step
/// F: a strike puts its striker on the creature's threat list).
fn own_go_targets(
  frames frames: List(Frame),
  beast beast: Int,
) -> List(List(Int)) {
  game_client.go_targets_in(frames:)
  |> list.filter(fn(go) { cast_state.caster_of(cast_id: go.0) != beast })
  |> list.map(fn(go) { go.1 })
}

pub fn a_stalkers_second_tap_of_shred_strikes_the_beast_with_the_stages_proxy_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_beasts(
      places: [beast_place(x: 1.5, z: 0.5)],
      tables: character_tables.shared(),
      time:,
    )
  let #(game, frames, have) =
    enters_and_sees_the_beasts(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 5,
      beasts: 1,
    )
  let assert [beast, ..] = game_client.creatures_created_in(frames:)
  let beast_unit = beast.unit_id
  let own = game_client.unit_create_player_in(frames:).unit_id
  let #(first_tap, have) =
    press_and_read_gos(
      game:,
      have:,
      time:,
      client_cast_id: 1,
      advance_ms: 1000,
      gos: 5,
      pong: 1,
      beast: beast_unit,
    )
  assert own_go_targets(frames: first_tap, beast: beast_unit)
    == [[], [], [beast_unit], [beast_unit], [beast_unit]]
    as "Spell4.38765, Shred: its own go names nobody (it has no damage), so does the Stalker's passive 45057 (its ungated Proxy 147125 starts 60724 after 50 ms, with no damage), and Shred's Proxy 38767, aimed at the area (Spell4Effects 83788, targetFlags 4), goes in three phases (SpellPhase 3712 to 3714), each naming the Beast 3 m away inside Spell4AoeTargetConstraints 694 (360 degrees, 6.5 m)"
  assert list.map(game_client.health_in(frames: first_tap), fn(health) {
      health.1
    })
    == [43, 34, 25]
    as "a Stalker of level 1 with the Novice gear (Assault Power 50.77): a hit of Shred's Proxy is 0.0967 x 50.77 = 4.91 plus 4.22 for the level, 9.13, rounded to 9 (Spell4Effects 83788, 0x140565600); the Beast has 52 health and never deflects, so each of the three hits takes 9"
  let #(second_tap, _) =
    press_and_read_gos(
      game:,
      have:,
      time:,
      client_cast_id: 2,
      advance_ms: 1000,
      gos: 5,
      pong: 3,
      beast: beast_unit,
    )
  assert own_go_targets(frames: second_tap, beast: beast_unit)
    == [[], [beast_unit], [beast_unit], [beast_unit], [own]]
    as "Spell4Thresholds 238: the second tap casts the stage 38766, which strikes nobody itself, and the stage's Proxy 39467 (Spell4Effects 83782), aimed at the area by Spell4Effects 86439 on Spell4 39467's area row 694, goes in three phases (SpellPhase 4032 to 4034), each naming the Beast; then the Stalker's passive 45057 starts 63366 (its row 159136, type 14, dataBits00 44), whose Spell4Effects 159134 (type 73) is aimed at the caster"
  assert list.map(game_client.health_in(frames: second_tap), fn(health) {
      health.1
    })
    == [16, 7, 0]
    as "each go of the stage's Proxy hits for 9 as the base's does (Spell4Effects 86439 holds the parameters of 83788): 25 less 9 is 16, 7 and then the Beast's last 7 health"
  game_client.close(game:)
  login_support.stop(started)
}

pub fn a_stalkers_held_shred_taps_its_stages_again_and_a_player_in_sight_reads_the_same_casts_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 5, time:)
  game_client.hold_ability(game: first, bag_index: 0, target: 0, held: 1)
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The global cooldown of the first cast is 1000 ms (Spell4.38765: SpellCoolDown
  // 115); the clock moves that far, so the Proxy's phases and the repeat fire in the
  // order of their times.
  driven_time.advance(time:, ms: 1000)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let own = cast_support.cast_lines(frames: list.append(pressed, later))
  assert list.take(own, 12)
    == [
      "started k1 38765 root 38765 parent 0",
      "opened 38765 k1",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
    ]
    as "opcode.0x4db and cast.hold_answer: held 1 starts Shred with a cast id of the server's, no 0x7fd, and opens the threshold (opcode.0x816); Spell4.38765 thresholdTime 4000, its Proxy 38767 goes in three phases (SpellPhase 3712 to 3714) and the Stalker's passive 45057 starts 60724 beside it"
  assert list.drop(own, 12)
    == [
      "started k4 38766 root 38765 parent 38765",
      "went k4 p0",
      "started k5 39467 root 38765 parent 38766",
      "finished k4",
      "closed 38765 1",
    ]
    as "cast.hold_repeat: with the key still down, one global cooldown later (Spell4.38765: SpellCoolDown 115, 1000 ms) the next tap casts the stage 38766 (Spell4Thresholds 238), the last, and 0x814 closes the threshold (opcode.0x814)"
  // The server has taken the release before the clock moves on, and the clock moves
  // 1500 ms, past the next global cooldown (1000 ms) by half of it, so a repeat the
  // release failed to stop would fire inside it.
  game_client.hold_ability(game: first, bag_index: 0, target: 0, held: 0)
  let #(_, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  driven_time.advance(time:, ms: 1500)
  let #(after_release, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 4)
  assert cast_support.cast_lines(frames: after_release)
    == ["went k1 p0", "went k1 p1", "went k1 p2", "finished k1"]
    as "cast.hold_stop: held 0 cuts no cast short, so the stage's Proxy 39467 goes in its three phases (SpellPhase 4032 to 4034), and it ends the repeats, so no cast starts one global cooldown later"
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 19)
  assert cast_support.cast_lines(frames: seen)
    == [
      "started k1 38765 root 38765 parent 0",
      "went k1 p0",
      "started k2 38767 root 38765 parent 38765",
      "finished k1",
      "started k3 60724 root 45057 parent 45057",
      "went k3 p0",
      "finished k3",
      "went k2 p0",
      "went k2 p1",
      "went k2 p2",
      "finished k2",
      "started k4 38766 root 38765 parent 38765",
      "went k4 p0",
      "started k5 39467 root 38765 parent 38766",
      "finished k4",
      "went k5 p0",
      "went k5 p1",
      "went k5 p2",
      "finished k5",
    ]
    as "opcode.0x7ff.root_parent: a player in sight reads the same casts, the base cast with parent 0 and the repeat's stage with root and parent 38765"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn a_stalkers_connection_ending_mid_hold_removes_it_for_a_player_in_sight_and_the_server_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 5, time:)
  game_client.hold_ability(game: first, bag_index: 0, target: 0, held: 1)
  // The hold is under way with the Proxy's phases and the repeat still to fire: the
  // clock does not move, so the connection ends in the middle of it.
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  game_client.close(game: first)
  let #(seen, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0355 })
    })
  assert list.any(seen, fn(frame) {
    frame.message_id == 0x0355
    && unit_destroyed.decode(frame.body)
    == Ok(unit_destroyed.UnitDestroyed(unit_id: 1, chest_world_object_delay: 0))
  })
    as "opcode.0x355: the map removes the unit that held a key when its connection ended"
  game_client.hold_ability(game: second, bag_index: 0, target: 0, held: 1)
  let #(own, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let assert [
    game_client.CastStarted(
      spell4_id: 58_832,
      root_spell4_id: 58_832,
      parent_spell4_id: 0,
      caster_unit_id: 2,
      ..,
    ),
    ..
  ] = game_client.casts_in(frames: own)
    as "the server goes on: the second player's own hold of Spell4.58832, Discharge, the Medic's first level-1 ability (SpellLevel 631), is answered with its own 0x7ff, unit 2 casting"
  game_client.close(game: second)
  login_support.stop(started)
}

/// A suited player's connection ends before the suit's 10,250 ms are up, on a clock the
/// test moves by hand: the watcher is written the suit once, then 0x355 for the unit and
/// no 0x933 after, and the server goes on. The first player's class presses the ability
/// at `bag_index` that puts the suit of `display` on it.
fn a_suited_players_connection_ends(
  tables tables: table_store.Tables,
  first_class first_class: Int,
  bag_index bag_index: Int,
  display display: Int,
) -> Nil {
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, second_have:, ..) =
    two_players_enter_on(tables:, first_class:, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  let is_suit = fn(frame: Frame) { frame.message_id == 0x0933 }
  let #(suited, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, is_suit)
    })
  let assert [suit] = list.filter(suited, is_suit)
    as "the watcher's client is written one 0x933 when the suit goes on"
  assert unit_item_visuals_changed.decode(suit.body)
    == Ok(
      UnitItemVisualsChanged(unit_id: 1, item_visuals: [
        ItemVisual(slot: 64, display_id: display, item_color_set_id: 0, dye: 0),
      ]),
    )
    as "opcode.0x933: unit 1 in slot 64 with the suit of a faction 166 player, ItemDisplay 7221 (178142 of Spell4 47860)"
  // The clock is the test's and has not moved, so the suit's 10,250 ms are not up: the
  // connection ends in the middle of the suit.
  game_client.close(game: first)
  let #(after, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0355 })
    })
  assert list.any(after, fn(frame) {
    frame.message_id == 0x0355
    && unit_destroyed.decode(frame.body)
    == Ok(unit_destroyed.UnitDestroyed(unit_id: 1, chest_world_object_delay: 0))
  })
    as "opcode.0x355: the map removes the suited unit when its connection ended"
  let #(rest, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert list.filter(list.append(after, rest), is_suit) == []
    as "no 0x933 follows the end of the suited player's connection, the restore included: its unit is gone"
  game_client.close(game: second)
  login_support.stop(started)
}

pub fn an_engineers_connection_ending_mid_suit_removes_it_for_a_player_in_sight_with_no_0x933_after_and_the_server_goes_on_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mode: Eradicate is the Engineer's innate, after its three abilities in the bag
  // (`Class` 2 spell4IdInnateAbilityActive00 47866).
  a_suited_players_connection_ends(
    tables: character_tables.shared(),
    first_class: 2,
    bag_index: 3,
    display: 7221,
  )
}

pub fn a_spellslingers_quick_draw_goes_in_five_phases_and_its_charged_shot_is_held_until_the_release_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let TwoEntered(started:, first:, second:, first_have:, second_have:, ..) =
    two_players_of_class_enter_one_map_with(first_class: 7, time:)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: 0,
    target: 0,
  )
  let child = fn(number, spell4_id) {
    [
      "started k"
        <> int.to_string(number)
        <> " "
        <> int.to_string(spell4_id)
        <> " root 43468 parent 43468",
      "went k" <> int.to_string(number) <> " p0",
      "finished k" <> int.to_string(number),
    ]
  }
  let quick_draw =
    list.flatten([
      ["went k1 p0", "went k1 p1"],
      child(2, 43_498),
      ["went k1 p2"],
      child(3, 43_499),
      ["went k1 p3"],
      child(4, 43_498),
      // 43500 holds one lasting row, a type 17 of 990 ms (Spell4Effects 99472), so
      // it is still going when the cast ends 1000 ms in: it has no finish yet.
      [
        "started k5 43500 root 43468 parent 43468",
        "went k5 p0",
      ],
      ["went k1 p4", "finished k1"],
    ])
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  // The phases of Quick Draw come 0, 366, 200, 200 and 234 ms after one another
  // (SpellPhase 5882 to 5886), 1000 ms in all.
  driven_time.advance(time:, ms: 1000)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == ["confirmed k1", ..quick_draw]
    as "Spell4.43468, Quick Draw (SpellLevel 1011): five gos, the phase indexes 0 to 4 (SpellPhase 5882 to 5886), and the children whose caster apply gate passes: no cast of 43500 is live, so 17301 (type 15, comparison 2 on 43500) passes and 17302 (comparison 1) fails: 43498 by Spell4Effects 196513 in phase 1, 43499 by 196514 in phase 2, 43498 by 196515 and 43500 by 196516 in phase 3, each with its own go and finish, then Quick Draw's finish"
  let #(seen, second_have) =
    game_client.read_kept(game: second, have: second_have, count: 18)
  assert cast_support.cast_lines(frames: seen)
    == ["started k1 43468 root 43468 parent 0", ..quick_draw]
  game_client.press_ability(
    game: first,
    client_cast_id: 2,
    bag_index: 1,
    target: 0,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  // Spell4Thresholds 123 raises the charge to level 1 after its thresholdDuration,
  // 1000 ms; the level after it (Spell4Thresholds 124) comes 1400 ms later.
  driven_time.advance(time:, ms: 1000)
  let #(later, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 4)
  assert cast_support.cast_lines(frames: list.append(pressed, later))
    == ["confirmed k1", "opened 34718 k1", "finished k2", "index 34718 1"]
    as "Spell4.34718, Charged Shot (SpellLevel 1036): the press opens the threshold with the cast's id and holds the cast; Spell4Thresholds 123 raises the level to 1 after thresholdDuration 1000 (opcode.0x817); the Quick Draw's 43500, a lasting row of 990 ms (Spell4Effects 99472), finishes in the same window"
  game_client.press_ability(
    game: first,
    client_cast_id: 3,
    bag_index: 1,
    target: 0,
  )
  let #(own, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 5)
  assert cast_support.cast_lines(frames: own)
    == [
      "confirmed k1",
      "went k1 p0",
      "finished k1",
      "closed 34718 0",
      "finished k2",
    ]
    as "the release casts the row at level 1, 34722 (Spell4Thresholds 123), then 0x814 closes the threshold and the base cast ends with its 0x7fe (cast.charge_release_base)"
  let #(seen, _) =
    game_client.read_kept(game: second, have: second_have, count: 6)
  assert cast_support.cast_lines(frames: seen)
    == [
      "started k1 34718 root 34718 parent 0",
      "finished k2",
      "started k3 34722 root 34718 parent 34718",
      "went k3 p0",
      "finished k3",
      "finished k1",
    ]
    as "cast.stage_root_parent: a player in sight reads the charge, then the stage with root and parent 34718, and no go for the base cast"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The targets of each go, in order, of the child 41844 of Fissure whose 0x7ff is among
/// `frames`, read in `in`.
fn fissure_goes(
  frames frames: List(Frame),
  in read: List(Frame),
) -> List(List(Int)) {
  let events = game_client.casts_in(frames:)
  case game_client.starts_of(events:, spell4_id: 41_844) {
    [#(cast_id, _), ..] ->
      list.filter_map(game_client.go_targets_in(frames: read), fn(go) {
        case go.0 == cast_id {
          True -> Ok(go.1)
          False -> Error(Nil)
        }
      })
    [] -> []
  }
}

/// A Beast of 5000 health that never deflects and stands where it is once struck: a client-default
/// Beast has 52 health, which Fissure's first go alone kills, and a struck creature chases its
/// attacker at its run speed, which 0 makes none. The speed is worked out again from the
/// creature's display's run speed (`CombatContext.run_land`) whenever its properties change, as
/// Fissure's debuff changes them, so both are 0.
fn still_beast_at(number number: Int, place place: Place) -> spawn.Spawn {
  let beast = spawn_support.beast_without_deflect_at(number:, place:)
  spawn.Spawn(
    ..beast,
    health: 5000,
    health_source: unit_fields.Recorded,
    combat: Combat(
      ..beast.combat,
      attack: Attack(..beast.combat.attack, run_speed: 0.0),
    ),
    context: spawn.CombatContext(..beast.context, run_land: 0.0),
  )
}

/// A level-4 Medic stands 8 m behind a Beast and presses Fissure at it with three Beasts in
/// view: A 8 m ahead, B 2 m past the hit radius aside of it and C 4 m past it. Fissure's child
/// strikes the 10 wide rectangle of TelegraphDamage 2998 at its first go, the 6 wide one of
/// 2997 at the second and the 2 wide one of 2996 at the third, so the units each go lists are
/// those whose edge is inside the rectangle of that go: A at every go, B at the first two and C
/// at the first alone. No Beast fights the Dominion Medic on sight, none dies and none moves,
/// and nobody moves after the press. The clock is driven and nothing waits on real time.
pub fn a_medic_presses_fissure_among_still_beasts_and_each_go_strikes_only_the_beasts_its_own_rectangle_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let radius = spawn_support.beast_combat().hit_radius
  // The half widths of rows 2998, 2997 and 2996 are 5, 3 and 1. A Beast is struck when its
  // centre is within the half width plus its hit radius of the middle line: B at `radius + 2`
  // is inside the first two (5 + radius, 3 + radius) and outside the third (1 + radius), C at
  // `radius + 4` is inside the first alone, each 1 m from the edge it is judged by.
  let aside_b = radius +. 2.0
  let aside_c = radius +. 4.0
  let started =
    world_with_spawns(
      spawns: [
        still_beast_at(number: 1, place: beast_place(x: 1.5, z: -4.5)),
        still_beast_at(
          number: 2,
          place: beast_place(x: 1.5 +. aside_b, z: -4.5),
        ),
        still_beast_at(
          number: 3,
          place: beast_place(x: 1.5 +. aside_c, z: -4.5),
        ),
      ],
      tables: character_tables.shared(),
      time:,
    )
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 4,
    )
  send_play(game:, character_id: character)
  let #(seen, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= 3
    })
  let beast_at_x = fn(x: Float) {
    let assert Ok(beast) =
      list.find(game_client.creatures_created_in(frames: seen), fn(creature) {
        float.loosely_equals(
          game_client.placed_by_tail(tail: creature.tail).0,
          x,
          0.01,
        )
      })
      as "a Beast stands at this x"
    beast.unit_id
  }
  let beast_ahead = beast_at_x(1.5)
  let beast_near = beast_at_x(1.5 +. aside_b)
  let beast_far = beast_at_x(1.5 +. aside_c)
  // The Medic is stored at (1.5, 2.5, 3.5): A is 8 m ahead of it when it faces -z.
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(1.5, 3.5), target: #(1.5, -4.5)),
    clock: 100,
  )
  game_client.press_ability(game:, client_cast_id: 1, bag_index: 4, target: 0)
  let #(first, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      fissure_goes(frames:, in: frames) != []
    })
  let #(first_flushed, have) =
    game_client.read_until_pong(game:, have:, number: 14)
  let pressed = list.append(first, first_flushed)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Fissure is planned and a level-4 Medic holds it, so the press is not refused"
  let assert Ok(child_started) =
    list.find(
      list.filter(pressed, fn(frame) { frame.message_id == 0x07FF })
        |> list.map(fn(frame) {
          let assert Ok(started) = spell_started.decode(frame.body)
            as "0x7ff decodes"
          started
        }),
      fn(started) { started.spell4_id == 41_844 },
    )
    as "opcode.0x7ff: the child 41844 starts"
  assert #(child_started.root_spell4_id, child_started.parent_spell4_id)
    == #(41_843, 41_843)
    as "Spell4Effects 94215 starts child 41844 of the pressed 41843"
  driven_time.advance(time:, ms: 250)
  let #(second, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      fissure_goes(frames: pressed, in: frames) != []
    })
  let #(second_flushed, have) =
    game_client.read_until_pong(game:, have:, number: 15)
  driven_time.advance(time:, ms: 250)
  let #(third, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      fissure_goes(frames: pressed, in: frames) != []
    })
  let #(third_flushed, _) =
    game_client.read_until_pong(game:, have:, number: 16)
  let struck = fn(read: List(Frame)) {
    case fissure_goes(frames: pressed, in: read) {
      [targets] -> list.sort(targets, int.compare)
      _ -> panic as "the go lists one set of targets"
    }
  }
  assert struck(pressed)
    == list.sort([beast_ahead, beast_near, beast_far], int.compare)
    as "opcode.0x7f4: the first go strikes the 10 wide rectangle (TelegraphDamage 2998, phaseFlags 1), which holds all three Beasts"
  assert struck(list.append(second, second_flushed))
    == list.sort([beast_ahead, beast_near], int.compare)
    as "opcode.0x7f4: the second go strikes the 6 wide rectangle (TelegraphDamage 2997, phaseFlags 2), which holds A and B and not C, which the first go struck"
  assert struck(list.append(third, third_flushed)) == [beast_ahead]
    as "opcode.0x7f4: the third go strikes the 2 wide rectangle (TelegraphDamage 2996, phaseFlags 4), which holds A alone"
  game_client.close(game:)
  login_support.stop(started)
}

/// A level-6 Medic saved at 100 health holds Crisis Wave (Spell4Base 25579, Spell4 41382, bag
/// index 7: the Medic's 5 to 6 rise gives it) and presses it on itself. Its area row 661 is
/// ordered by missing health (MissingMostHealth), which a friendly area finds the caster's
/// allies by: the press is confirmed, its go lists the Medic alone, no other player being in
/// sight, with the heal of row 93037 (type 10, flags 5: the caster and the area) and the
/// Medic's health rises by the amount that heal's description gives. The clock is driven and
/// nothing waits on real time.
pub fn a_hurt_medic_presses_crisis_wave_and_the_cast_starts_goes_and_heals_the_caster_where_the_order_refused_it_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_spawns(spawns: [], tables: character_tables.shared(), time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 4,
      level: 6,
    )
  let pool = pog.named_connection(started.settings.pool.pool_name)
  let assert Ok(_) =
    pog.query("update character set health = 100 where character_id = $1")
    |> pog.parameter(pog.int(character))
    |> pog.execute(pool)
    as "the row holds a health below the level's maximum, so a heal is a real change"
  send_play(game:, character_id: character)
  let #(entry, have) = game_client.read_entry_kept(game:, have: <<>>)
  let own = game_client.unit_create_player_in(frames: entry).unit_id
  assert health_in(frames: entry) == 100
    as "opcode.0x262: the Medic enters with the 100 it was saved with"
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: entry), fn(item) { item.1 == 25_579 })
    as "the level-6 Medic holds Crisis Wave's base 25579 (SpellLevel 1194)"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 14)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Crisis Wave is planned, so the press is not refused"
  let assert Ok(cast_id) =
    game_client.confirmed_cast_of(frames: pressed, client_cast_id: 1)
    as "opcode.0x7fd: the press is confirmed with the server's cast id"
  // Spell4.41382 castTime 1250: the go waits for the clock. A pressed cast is told its player
  // by the 0x7fd and the go; the 0x7ff is for a child and for the viewers.
  driven_time.advance(time:, ms: 1250)
  let #(went, _) =
    game_client.read_until(game:, have:, found: fn(frames) {
      finishes(frames:, cast_id:)
    })
  assert game_client.go_targets_in(frames: went)
    |> list.filter(fn(go) { go.0 == cast_id })
    == [#(cast_id, [own])]
    as "opcode.0x7f4: the go lists the Medic alone, no other player being in sight for the area to find"
  assert game_client.missed_in(frames: went) == []
    as "opcode.0x7fb: nothing is missed"
  let assert [go] =
    list.filter_map(went, fn(frame) {
      case frame.message_id == 0x07F4 {
        True -> spell_go.decode(frame.body) |> result.replace_error(Nil)
        False -> Error(Nil)
      }
    })
    |> list.filter(fn(go) { go.cast_id == cast_id })
    as "the cast has one go"
  let assert [info] = go.targets as "the go has the Medic's target info"
  let assert [
    spell_effect_info.SpellEffectInfo(
      spell4_effects_id: 93_037,
      result: spell_effect_result.Damage(spell_effect_damage.SpellEffectDamage(
        description:,
      )),
      ..,
    ),
  ] = info.effects
    as "the Medic's info holds the heal row 93037 (Spell4Effects 93037: type 10, flags 5)"
  let healed = description.health_damage_with_overkill - description.overkill
  assert healed > 0 as "the heal changes the Medic's health"
  // The 1250 ms the clock ran also fire the Medic's health regeneration (`player_life`), each
  // tick its own 0x92f, before the go; the heal's 0x92f is the first after it, and the read
  // ends at the cast's 0x7fe, which follows it.
  let go_index =
    index_where(frames: went, found: fn(frame) { frame.message_id == 0x07F4 })
  let health_in_frames = fn(frames) {
    game_client.own_health_of(events: game_client.fight_in(frames:), unit: own)
  }
  let before =
    health_in_frames(list.take(went, go_index))
    |> list.last
    |> result.unwrap(100)
  let assert [after, ..] = health_in_frames(list.drop(went, go_index + 1))
    as "the heal's 0x92f follows the go before the cast ends"
  assert after - before == healed
    as "opcode.0x92f: the heal raises the Medic's health by the amount the heal's description gives"
  game_client.close(game:)
  login_support.stop(started)
}

/// A world with one Beast 3 m ahead of the place a new test character stands at, which has
/// 1,000,000 health, so a damage over time of a few seconds never kills it.
fn world_with_a_tough_beast_ahead(
  tables tables: table_store.Tables,
  time time: driven_time.Time,
) -> login_support.Started {
  let beast =
    spawn_support.beast_without_deflect_at(
      number: 1,
      place: beast_place(x: 1.5, z: 0.5),
    )
  world_with_spawns(
    spawns: [spawn.Spawn(..beast, health: 1_000_000)],
    tables:,
    time:,
  )
}

pub fn a_spellslinger_over_a_socket_casts_surged_quick_draw_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let started = login_support.start(time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Zed Qu",
      class_id: 7,
      level: 1,
    )
  send_play(game:, character_id: character)
  let #(_, have) = game_client.read_entry_kept(game:, have: <<>>)
  // Spell Surge is the Spellslinger's innate, the bag's index 3 after the three level-1
  // abilities, and Quick Draw its first, index 0 (SpellLevel rows of class 7).
  game_client.press_ability(game:, client_cast_id: 1, bag_index: 3, target: 0)
  let #(surge, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert result.is_ok(game_client.confirmed_cast_of(
    frames: surge,
    client_cast_id: 1,
  ))
    as "opcode.0x7fd: the press of Spell Surge is accepted"
  driven_time.advance(time:, ms: 3000)
  game_client.press_ability(game:, client_cast_id: 2, bag_index: 0, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 2)
  driven_time.advance(time:, ms: 1500)
  let #(later, _) = game_client.read_until_pong(game:, have:, number: 3)
  let frames = list.append(pressed, later)
  assert result.is_ok(game_client.confirmed_cast_of(frames:, client_cast_id: 2))
    as "opcode.0x7fd: the Quick Draw press is accepted"
  let roots =
    list.map(
      bot_frames.decoded(frames, spell_started.message_id, spell_started.decode),
      fn(started) { started.root_spell4_id },
    )
  assert list.contains(roots, 76_002) && !list.contains(roots, 43_468)
    as "CastAbilityBagSpell 0x14039a040 under a node of 47439: the child casts name Quick Draw's alternate 76002 as their root, and none name 43468 (opcode.0x7ff.root_spell4_id)"
  assert list.take(
      list.filter_map(
        bot_frames.decoded(
          frames,
          unit_float_stat_changed.message_id,
          unit_float_stat_changed.decode,
        ),
        fn(changed) {
          case changed.stat_id == 6 {
            True -> Ok(changed.value)
            False -> Error(Nil)
          }
        },
      ),
      1,
    )
    == [float32.to_bits(75.0)]
    as "opcode.0x935: 76002's innate cost (19, 25) takes 25 from the Spellslinger's 100 Spell Power (stat 6, slot 4); the writes after it are the slot refilling over time (class_resource, `Over time`)"
  game_client.close(game:)
  login_support.stop(started)
}

/// The cast entries of the 0x262 of the unit `unit_id` among the frames, as each cast id with
/// the units it lists and, for each, the effects with the time left they were told with.
fn cast_entries_of(
  frames frames: List(Frame),
  unit_id unit_id: Int,
) -> List(#(Int, List(#(Int, List(#(Int, Int)))))) {
  let casts =
    list.flat_map(frames, fn(frame) {
      case created_unit_of(frame:) {
        Ok(#(created, casts)) if created == unit_id -> casts
        Ok(_) | Error(Nil) -> []
      }
    })
  list.map(casts, fn(cast) {
    #(
      cast.cast_id,
      list.map(cast.targets, fn(target) {
        #(
          target.unit_id,
          list.map(target.effects, fn(effect) {
            #(effect.spell4_effects_id, effect.lifetime_ms)
          }),
        )
      }),
    )
  })
}

/// The unit a 0x262 frame creates, with the casts its tail lists.
fn created_unit_of(
  frame frame: Frame,
) -> Result(#(Int, List(unit_create_cast.UnitCreateCast)), Nil) {
  use <- bool.guard(when: frame.message_id != 0x0262, return: Error(Nil))
  use created <- result.map(game_client.created_unit(body: frame.body))
  case created {
    game_client.PlayerCreated(unit:) -> #(unit.unit_id, unit.tail.casts)
    game_client.CreatureCreated(unit:) -> #(unit.unit_id, unit.tail.casts)
    game_client.ObjectCreated(unit_id:, tail:, ..) -> #(unit_id, tail.casts)
  }
}

/// Fissure's child 41886 started and gone on the Beast: its cast id.
fn fissure_child_gone_on(
  frames frames: List(Frame),
  beast beast: Int,
) -> Result(Int, Nil) {
  use #(cast_id, _) <- result.try(
    game_client.starts_of(
      events: game_client.casts_in(frames:),
      spell4_id: 41_886,
    )
    |> list.first,
  )
  case list.contains(game_client.go_targets_in(frames:), #(cast_id, [beast])) {
    True -> Ok(cast_id)
    False -> Error(Nil)
  }
}

/// The viewer's arrival in the order that shows the Beast's own tell, which the test makes
/// certain: the viewer reads the Medic's 0x262 and the Beast's, walks 1026.5 units along z,
/// where the Medic (1023 away) is in sight and the Beast (1026 away) is not (`sight.range`,
/// 1024), reads the Beast's removal, and walks back into the Beast's sight. The Medic's
/// create is then read before the Beast's by the viewer's own steps, not by which of two
/// senders wrote first. Gives the frames of the first arrival (the Medic's entry among
/// them), the frames of the Beast coming into sight again, and the bytes beyond them.
fn beast_comes_into_sight_after_the_medic(
  game game: game_client.Game,
  burst burst: List(Frame),
  have have: BitArray,
  beast beast: Int,
) -> #(List(Frame), List(Frame), BitArray) {
  let #(arrived, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.count(list.append(burst, frames), fn(frame) {
        frame.message_id == 0x0262
      })
      >= 3
    })
  let entry = list.append(burst, arrived)
  walk_to(game:, z: 1026.5, clock: 1)
  let #(_, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), beast)
    })
  let #(_, have) = game_client.read_until_pong(game:, have:, number: 1)
  walk_to(game:, z: 3.5, clock: 2)
  let #(returned, have) =
    game_client.read_until(game:, have:, found: fn(frames) {
      list.any(game_client.creatures_created_in(frames:), fn(creature) {
        creature.unit_id == beast
      })
    })
  #(entry, returned, have)
}

/// The entries of property `property_id` that the 0x93a frames among `frames` give the unit
/// `unit_id`, in order.
fn property_entries_of(
  frames frames: List(Frame),
  unit_id unit_id: Int,
  property_id property_id: Int,
) -> List(UnitProperty) {
  list.filter(frames, fn(frame) { frame.message_id == 0x093A })
  |> list.flat_map(fn(frame) {
    let assert Ok(changed) = unit_properties_changed.decode(frame.body)
      as "0x93a decodes"
    use <- bool.guard(when: changed.unit_id != unit_id, return: [])
    list.filter(changed.properties, fn(entry) {
      entry.property_id == property_id
    })
  })
}

/// The cast ids of the 0x7fe frames among `frames`, in order.
fn finished_casts_in(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastFinished(cast_id:) -> Ok(cast_id)
      _ -> Error(Nil)
    }
  })
}

/// `opcode.0x262.casts`: a viewer that comes into sight after a Medic's Fissure (Spell4Base
/// 26038) has left its debuff on a Beast is shown the debuff, with the time it has left, and
/// is told it ends at the end of the last phase's child. The child 41886's row 94370 holds
/// 8000 ms and property 160. The viewer sees the Medic first and the Beast comes into its
/// sight after (`beast_comes_into_sight_after_the_medic`), where the debuff shows once, from
/// both entries. The clock is the test's.
pub fn a_viewer_arriving_after_a_medic_fissures_a_beast_shows_the_debuff_on_the_beast_and_its_end_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  // The Beast holds 5000 health as its spawn's own: a client-default Beast has 52, which
  // Fissure's first go alone kills, and the child's property 160 modifier clamps health to
  // that maximum; a dead Beast stands again at the next 1000 ms of the clock, which
  // clears the views before the debuff's 8000 ms are over.
  let started =
    world_with_spawns(
      spawns: [
        spawn.Spawn(
          ..spawn_support.beast_without_deflect_at(
            number: 1,
            place: beast_place(x: 1.5, z: 0.5),
          ),
          health: 5000,
          health_source: unit_fields.Recorded,
        ),
      ],
      tables: character_tables.shared(),
      time:,
    )
  let facing_the_beast =
    game_client.yaw_toward(from: #(1.5, 3.5), target: #(1.5, 0.5))
  let TwoEntered(first:, second:, first_acted:, second_burst:, second_have:, ..) =
    two_players_enter_after(
      started:,
      first_class: 4,
      level: 4,
      first_acts: fn(game, have) {
        let #(seen, have) =
          game_client.read_until(game:, have:, found: fn(frames) {
            game_client.creatures_created_in(frames:) != []
          })
        let assert [beast, ..] = game_client.creatures_created_in(frames: seen)
        game_client.face(game:, yaw: facing_the_beast, clock: 100)
        game_client.press_ability(
          game:,
          client_cast_id: 1,
          bag_index: 4,
          target: 0,
        )
        let #(pressed, have) =
          game_client.read_until(game:, have:, found: fn(frames) {
            fissure_child_gone_on(
              frames: list.append(seen, frames),
              beast: beast.unit_id,
            )
            != Error(Nil)
          })
        driven_time.advance(time:, ms: 200)
        let #(settled, have) =
          game_client.read_until_pong(game:, have:, number: 5)
        #(list.flatten([seen, pressed, settled]), have)
      },
    )
  let assert [beast, ..] = game_client.creatures_created_in(frames: first_acted)
  let assert Ok(child) =
    fissure_child_gone_on(frames: first_acted, beast: beast.unit_id)
  let #(frames, returned, have) =
    beast_comes_into_sight_after_the_medic(
      game: second,
      burst: second_burst,
      have: second_have,
      beast: beast.unit_id,
    )
  let node = #(child, [#(beast.unit_id, [#(94_370, 7800)])])
  assert cast_entries_of(frames:, unit_id: 1) == [node]
    as "opcode.0x262.casts: the Medic's own entry lists its child cast with the Beast as a target, 8000 ms of row 94370 less the 200 ms since the go"
  assert cast_entries_of(frames: returned, unit_id: beast.unit_id) == [node]
    as "opcode.0x262.casts: the Beast's own entry lists the same node with the time left it was told, once: the viewer holds the Medic's cast by then"
  let assert [shown, ..] =
    list.filter(
      game_client.creatures_created_in(frames: returned),
      fn(creature) { creature.unit_id == beast.unit_id },
    )
  assert list.contains(
    shown.tail.properties,
    UnitProperty(
      property_id: 160,
      base: float32.to_bits(1.0),
      value: 1_066_192_077,
    ),
  )
    as "Spell4Effects 94370: the same go's modifier of property 160, mode 2, dataBits02 the bits of 1.1, is on the Beast the viewer is shown"
  let #(settled, have) =
    game_client.read_until_pong(game: second, have:, number: 6)
  // Fissure's second and third phases, 250 ms and 500 ms after its first, start a child
  // each, whose nodes push the earlier ones off the Beast at the stack cap (Jim's decision
  // on stacking).
  driven_time.advance(time:, ms: 500)
  let #(phased, have) =
    game_client.read_until_pong(game: second, have:, number: 7)
  assert list.contains(
    game_client.targets_removed_in(frames: phased),
    #(child, [beast.unit_id]),
  )
    as "opcode.0x811: the viewer that was shown the node is told it ends when the next phase's node pushes it off, as the Medic's client is"
  let assert Ok(#(last_child, _)) =
    game_client.starts_of(
      events: game_client.casts_in(frames: phased),
      spell4_id: 41_886,
    )
    |> list.last
    as "the viewer is written the start of each later phase's child"
  assert last_child != child
    as "the last phase's child is another cast than the first"
  // The last child's node is the one nothing pushes off: it ends 8000 ms after its go.
  driven_time.advance(time:, ms: 7000)
  let #(holding, have) =
    game_client.read_until_pong(game: second, have:, number: 8)
  assert !list.contains(finished_casts_in(frames: holding), last_child)
    && property_entries_of(
      frames: holding,
      unit_id: beast.unit_id,
      property_id: 160,
    )
    == []
    as "the last phase's child still holds the Beast, and its modifier, before its 8000 ms are over"
  driven_time.advance(time:, ms: 2000)
  let #(ended, _) = game_client.read_until_pong(game: second, have:, number: 9)
  assert list.contains(finished_casts_in(frames: ended), last_child)
    as "opcode.0x7fe: the last phase's child ends 8000 ms after its go, the finish alone ending its last node"
  assert list.last(property_entries_of(
      frames: ended,
      unit_id: beast.unit_id,
      property_id: 160,
    ))
    == Ok(UnitProperty(
      property_id: 160,
      base: float32.to_bits(1.0),
      value: float32.to_bits(1.0),
    ))
    as "opcode.0x93a: the Beast is given property 160 back as the debuff ends"
  let seen = list.flatten([frames, returned, settled, phased, holding, ended])
  assert game_client.dead_in(frames: seen) == []
    as "the Beast stays alive through the phases: its 5000 health"
  assert list.all(game_client.health_in(frames: seen), fn(health) {
    health.0 != beast.unit_id || { health.1 > 0 && !health.2 }
  })
    as "no 0x937 gives the Beast no health"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// A level-14 Warrior presses Flash Bang (Spell4 32320, base 18547) with three Beasts about
/// it: A 3 m ahead, B 3 m from A and C 10 m from A, both behind A as the player sees them. The
/// cast's area row (Spell4AoeTargetConstraints 113: 1 target, 0 to 20 m, 180 degrees, Closest)
/// names A alone, so the Proxy 60807 aimed at the area starts one child, 47202, on A; the
/// child's area row (704: 4 targets, 0 to 4 m, 360 degrees) and its hit row (TelegraphDamage
/// 1766: a circle of radius 4, flags 0x1200, targetTypeFlags 2) centre the strike on A, so the
/// child's go names A and B and not C. The clock is driven and the Beasts never deflect.
pub fn a_warrior_of_level_14_presses_flash_bang_and_the_struck_beasts_child_strikes_around_that_beast_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_beasts(
      places: [
        beast_place(x: 1.5, z: 0.5),
        beast_place(x: 4.5, z: 0.5),
        beast_place(x: 1.5, z: -9.5),
      ],
      tables: character_tables.shared(),
      time:,
    )
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Gor Qu",
      class_id: 1,
      level: 14,
    )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= 3
    })
  let beast_at = fn(x, z) {
    let assert Ok(beast) =
      list.find(game_client.creatures_created_in(frames:), fn(beast) {
        let placed = game_client.placed_by_tail(tail: beast.tail)
        float.absolute_value(placed.0 -. x) <. 0.01
        && float.absolute_value(placed.2 -. z) <. 0.01
      })
      as "the world shows the Beast planted there"
    beast.unit_id
  }
  let closest = beast_at(1.5, 0.5)
  let beside = beast_at(4.5, 0.5)
  let far = beast_at(1.5, -9.5)
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames:), fn(item) { item.1 == 18_547 })
    as "SpellLevel 931 grants Flash Bang's base 18547 to a Warrior of level 14"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Flash Bang is planned, so the press is not refused"
  let starts_in = fn(frames: List(Frame)) {
    list.filter(frames, fn(frame) { frame.message_id == 0x07FF })
    |> list.map(fn(frame) {
      let assert Ok(started) = spell_started.decode(frame.body)
        as "0x7ff decodes"
      started
    })
  }
  let assert [child] =
    list.filter(starts_in(pressed), fn(started) { started.spell4_id == 47_202 })
    as "opcode.0x7ff: one child, because Spell4AoeTargetConstraints 113 selects 1 target"
  assert #(
      child.root_spell4_id,
      child.parent_spell4_id,
      child.primary_target_unit_id,
    )
    == #(32_320, 32_320, closest)
    as "Spell4Effects 60807 starts child 47202 of 32320 on the closest Beast, A, which is its primary target (opcode.0x7ff)"
  let goes_of_child = fn(frames: List(Frame)) {
    list.filter_map(game_client.go_targets_in(frames:), fn(go) {
      case go.0 == child.cast_id {
        True -> Ok(go.1)
        False -> Error(Nil)
      }
    })
  }
  // Phase 0 goes at once and phase 1 10 ms later (SpellPhase 8101 and 8102), so the clock moves
  // past it before the second go is awaited; whether the first go reached the client before the
  // press's pong is the connection's order of writes, which nothing here relies on.
  driven_time.advance(time:, ms: 100)
  let #(later, have) =
    game_client.read_until(game:, have:, found: fn(later) {
      list.any(
        game_client.casts_in(frames: list.append(pressed, later)),
        fn(event) {
          event == game_client.CastWent(cast_id: child.cast_id, phase: 1)
        },
      )
    })
  let #(rest, _) = game_client.read_until_pong(game:, have:, number: 2)
  let goes = goes_of_child(list.flatten([pressed, later, rest]))
  assert !list.any(goes, fn(targets) { list.contains(targets, far) })
    as "no go of the child names C, 10 m from A"
  assert goes == [[closest, beside], [closest]]
    as "opcode.0x7f4: the child's first go names A (its own place, 0 m) and B (3 m, inside the circle of radius 4 and the area row's 4 m) and not C (10 m): TelegraphDamage 1766 is fixed at the unit it is cast on; its second go holds only Spell4Effects 174854, a type 17 row aimed at the target (phaseFlags -1), so it names the primary target alone"
  game_client.close(game:)
  login_support.stop(started)
}

/// The 0x7ff of the spell `spell4_id` the frames hold, in order.
fn starts_of_spell(
  frames frames: List(Frame),
  spell4_id spell4_id: Int,
) -> List(game_client.CastEvent) {
  list.filter(game_client.casts_in(frames:), fn(event) {
    case event {
      game_client.CastStarted(spell4_id: started, ..) -> started == spell4_id
      game_client.CastRefused(..)
      | game_client.CastConfirmed(..)
      | game_client.CastWent(..)
      | game_client.CastFinished(..)
      | game_client.ThresholdOpened(..)
      | game_client.ThresholdIndex(..)
      | game_client.ThresholdClosed(..)
      | game_client.ThresholdEnded(..) -> False
    }
  })
}

/// A Warrior of level 10 presses Plasma Wall (SpellLevel 938: Spell4 38787, base 23169) on the
/// driven clock. Its Proxy 228473 (tickTime 500, durationTime 5000, `Spell4Effects.effectType.26.
/// periodic`; text 311216 "every 0.5s") casts Spell4 87477 at the caster every half second, ten
/// times, each a cast of its own with the wall as parent and root, and the wall's 0x7fe comes
/// after the tenth. A Warrior enters with no Kinetic Energy (`class_resource`: its slot starts
/// empty and is not saved) and holds no Onslaught, so the wall as the client has it cannot be
/// pressed and held for its ticks. The test edits three columns of the Spell4 row to 0, each for its own reason:
/// - `casterInnateRequirement0` (Kinetic Energy of 250): the press is refused 51.
/// - `prerequisiteIdCasterCast` 19750: the Overdrive waiver of that requirement (propertyFlags
///   bit 2 with a requirement block, `Spell4.prerequisiteIdCasterCast`; Overdrive is the cast
///   of 42908). With the requirement gone the row has no block to waive, so the plan reads
///   19750 as a cast gate (`spell_plan.caster_cast_of`) instead of a waiver.
/// - `prerequisiteIdCasterPersistence` 43680 (text 311216, "Removed when you fall below 250
///   Kinetic Energy"): it needs Kinetic Energy of 250 or a live 42908 (43679), so it would end
///   the cast in the input of its own press.
/// The test is about the Proxy's ticks; the end by a persistence is `cast_proxy_tick_test`'s.
pub fn a_warrior_presses_plasma_wall_and_a_child_cast_starts_every_half_second_ten_times_and_the_wall_finishes_after_the_last_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- fixture_tables.changed(table: "Spell4", id: 38_787, with: [
    #("casterInnateRequirement0", planted_table.Integer(0)),
    #("prerequisiteIdCasterCast", planted_table.Integer(0)),
    #("prerequisiteIdCasterPersistence", planted_table.Integer(0)),
  ])
  let time = driven_time.new()
  let started = world_with_spawns(spawns: [], tables:, time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Gor Qu",
      class_id: 1,
      level: 10,
    )
  send_play(game:, character_id: character)
  let #(entry, have) = game_client.read_entry_kept(game:, have: <<>>)
  let own = game_client.unit_create_player_in(frames: entry).unit_id
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: entry), fn(item) { item.1 == 23_169 })
    as "SpellLevel 938 grants Plasma Wall's base 23169 to a Warrior of level 10"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Plasma Wall is planned, so the press is not refused"
  let assert Ok(wall) =
    game_client.confirmed_cast_of(frames: pressed, client_cast_id: 1)
    as "opcode.0x7fd: the press is confirmed with the server's cast id"
  assert starts_of_spell(frames: pressed, spell4_id: 87_477) == []
    as "nothing is cast at the go: the first cast is one tick on"
  let #(ticking, have) =
    list.fold(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      #(pressed, have),
      fn(so_far, number) {
        let #(frames, have) = so_far
        driven_time.advance(time:, ms: 500)
        let #(more, have) =
          game_client.read_until(game:, have:, found: fn(more) {
            let seen = list.append(frames, more)
            // The wall's 0x7fe also ends the wait, so a wall that ends before its tenth
            // tick is a failed assertion below and not a wait with no end.
            list.length(starts_of_spell(frames: seen, spell4_id: 87_477))
            >= number
            || finishes(frames: seen, cast_id: wall)
          })
        #(list.append(frames, more), have)
      },
    )
  let #(finished, have) =
    game_client.read_until(game:, have:, found: fn(more) {
      finishes(frames: list.append(ticking, more), cast_id: wall)
    })
  let frames = list.append(ticking, finished)
  let children = starts_of_spell(frames:, spell4_id: 87_477)
  assert list.length(children) == 10
    as "Spell4Effects 228473: durationTime 5000 over tickTime 500 is ten casts"
  let child_ids =
    list.map(children, fn(event) {
      let assert game_client.CastStarted(
        cast_id:,
        root_spell4_id:,
        parent_spell4_id:,
        caster_unit_id:,
        ..,
      ) = event
      assert #(root_spell4_id, parent_spell4_id, caster_unit_id)
        == #(38_787, 38_787, own)
        as "opcode.0x7ff.root_parent: a cast no press made names the wall as root and parent, and the Warrior casts it"
      cast_id
    })
  assert list.unique(child_ids) == child_ids as "each tick is a cast of its own"
  let events = game_client.casts_in(frames:)
  list.each(child_ids, fn(child) {
    assert list.contains(events, game_client.CastWent(cast_id: child, phase: 0))
      && list.contains(events, game_client.CastFinished(cast_id: child))
      as "each child goes and finishes as any child cast does"
  })
  let assert Ok(last_child) = list.last(child_ids)
  let position = fn(wanted) {
    let assert Ok(found) =
      list.index_map(events, fn(event, index) { #(event, index) })
      |> list.find(fn(entry) { entry.0 == wanted })
    found.1
  }
  assert position(game_client.CastFinished(cast_id: wall))
    > position(game_client.CastFinished(cast_id: last_child))
    as "opcode.0x7fe: the wall finishes after the tenth child, the step that fires the tenth tick"
  driven_time.advance(time:, ms: 1500)
  let #(later, _) = game_client.read_until_pong(game:, have:, number: 2)
  assert starts_of_spell(frames: later, spell4_id: 87_477) == []
    as "no eleventh child follows the wall's end"
  game_client.close(game:)
  login_support.stop(started)
}

/// A Medic of level 8 presses Nullifier (SpellLevel 632: Spell4 70757, base 47675) on the driven
/// clock. Its Proxy 180619 starts the field 58868 (castMethod 10, spellDuration 6000; text 574032
/// "Create a field, lasting 6s"), whose Fluff 175305 holds its node until removed, so the field's
/// 0x7fe comes 6000 ms after the field's start (`Spell4.spellDuration`, `0x1407180c0`) and not
/// before; the node ends by time, so no 0x811 comes with it (`cast.target_node_end`). Each wait
/// is bounded by a pong, since the 0x7fe never comes without the rule.
pub fn a_medic_presses_nullifier_and_its_field_cast_finishes_six_seconds_after_its_start_with_the_0x7fe_alone_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_spawns(spawns: [], tables: fixture_tables.shared(), time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Med Ic",
      class_id: 4,
      level: 8,
    )
  send_play(game:, character_id: character)
  let #(entry, have) = game_client.read_entry_kept(game:, have: <<>>)
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: entry), fn(item) { item.1 == 47_675 })
    as "SpellLevel 632 grants Nullifier's base 47675 to a Medic of level 8"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Nullifier is planned, so the press is not refused"
  let assert [game_client.CastStarted(cast_id: field, ..)] =
    starts_of_spell(frames: pressed, spell4_id: 58_868)
    as "opcode.0x7ff: Proxy 180619 starts the field at the press"
  driven_time.advance(time:, ms: 5999)
  let #(early, have) = game_client.read_until_pong(game:, have:, number: 2)
  assert !finishes(frames: early, cast_id: field)
    as "the field is not finished 5999 ms after its start"
  driven_time.advance(time:, ms: 1)
  let #(late, _) = game_client.read_until_pong(game:, have:, number: 3)
  assert finishes(frames: late, cast_id: field)
    as "opcode.0x7fe: the field finishes 6000 ms after its start (Spell4 58868 spellDuration)"
  assert game_client.targets_removed_in(frames: late) == []
    as "a lingering cast whose last node ends by time writes the 0x7fe alone"
  game_client.close(game:)
  login_support.stop(started)
}

/// A Medic of `level` who has entered a world with one Beast 3 m ahead of the place a new
/// character stands at, and turned to face it: the game, the bytes read, the bag index of the
/// ability of base `base` and the Beast's unit.
fn medic_facing_the_beast(
  started started: login_support.Started,
  character_name character_name: String,
  level level: Int,
  base base: Int,
) -> #(game_client.Game, BitArray, Int, Int) {
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name:,
      class_id: 4,
      level:,
    )
  send_play(game:, character_id: character)
  let #(frames, have) =
    game_client.read_until(game:, have: <<>>, found: fn(frames) {
      list.length(game_client.creatures_created_in(frames:)) >= 1
    })
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames:), fn(item) { item.1 == base })
    as "the Medic's level grants the ability's base"
  let assert [beast] = game_client.creatures_created_in(frames:)
  let own_place =
    game_client.placed_at(unit: game_client.unit_create_player_in(frames:))
  game_client.face(
    game:,
    yaw: game_client.yaw_toward(from: #(own_place.0, own_place.2), target: #(
      1.5,
      0.5,
    )),
    clock: 100,
  )
  #(game, have, bag_index, beast.unit_id)
}

/// The effect ids each 0x7f4 among the frames lists for each unit it names, as the cast id, the
/// unit and the ids, in order.
fn go_effects_in(frames frames: List(Frame)) -> List(#(Int, Int, List(Int))) {
  list.flat_map(frames, fn(frame) {
    case frame.message_id {
      0x07F4 -> {
        let assert Ok(go) = spell_go.decode(frame.body) as "0x7f4 decodes"
        effects_of_go(go:)
      }
      _ -> []
    }
  })
}

/// The effect ids a go lists for each unit it names, with the go's cast id.
fn effects_of_go(go go: spell_go.SpellGo) -> List(#(Int, Int, List(Int))) {
  list.map(go.targets, fn(target) {
    #(go.cast_id, target.unit_id, effect_ids_of(target:))
  })
}

fn effect_ids_of(
  target target: spell_target_info.SpellTargetInfo,
) -> List(Int) {
  list.map(target.effects, fn(effect: spell_effect_info.SpellEffectInfo) {
    effect.spell4_effects_id
  })
}

/// The crowd-control states each 0x87f among the frames tells, as the unit, the state's number
/// and the instance id, in order.
fn states_told_in(frames frames: List(Frame)) -> List(#(Int, Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x087F -> {
        let assert Ok(told) = unit_cc_state_applied.decode(frame.body)
          as "0x87f decodes"
        Ok(#(
          told.unit_id,
          crowd_control_state.to_value(told.state),
          told.instance_id,
        ))
      }
      _ -> Error(Nil)
    }
  })
}

/// The states each 0x880 among the frames ends, as the unit, the cast id and the instance id,
/// in order.
fn states_ended_in(frames frames: List(Frame)) -> List(#(Int, Int, Int)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0880 -> {
        let assert Ok(ended) = unit_cc_state_ended.decode(frame.body)
          as "0x880 decodes"
        Ok(#(ended.unit_id, ended.cast_id, ended.instance_id))
      }
      _ -> Error(Nil)
    }
  })
}

/// A Medic of level 8 presses Nullifier (SpellLevel 632: Spell4 70757) on the driven clock with
/// a Beast 3 m ahead, inside the box of its field (a box 14 by 14 starting 1 m ahead of where
/// the Medic stood at the press, `table_rows -- TelegraphDamage 2789`). Row 141450 of the field
/// 58868 (tickTime 1000, until the field ends; text 574032 "apply an Affliction to foes inside
/// the field every 1s") starts the Affliction 77099 on each foe inside it at each second of the
/// field's six: the child's 0x7f4 lists the Beast and its damage row 200387, and the Beast's
/// health falls with the child's ticks. Each wait is bounded by a pong.
pub fn a_medic_presses_nullifier_and_a_beast_in_its_box_is_given_an_affliction_each_second_for_six_seconds_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started =
    world_with_a_tough_beast_ahead(tables: fixture_tables.shared(), time:)
  let #(game, have, bag_index, beast_unit) =
    medic_facing_the_beast(
      started:,
      character_name: "Med Ic",
      level: 8,
      base: 47_675,
    )
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Nullifier is planned, so the press is not refused"
  let assert [game_client.CastStarted(cast_id: field, caster_unit_id:, ..)] =
    starts_of_spell(frames: pressed, spell4_id: 58_868)
    as "opcode.0x7ff: Proxy 180619 starts the field at the press"
  assert starts_of_spell(frames: pressed, spell4_id: 77_099) == []
    as "the field's Proxy ticks: it casts nothing at the go"
  let #(early, have) =
    advanced_and_read(game:, time:, have:, number: 2, ms: 999)
  assert starts_of_spell(frames: early, spell4_id: 77_099) == []
    as "row 141450: tickTime 1000, so no Affliction 999 ms after the field's start"
  let at_second = fn(have, number, ms) {
    advanced_and_read(game:, time:, have:, number:, ms:)
  }
  let #(first_tick, have) = at_second(have, 3, 1)
  let assert [
    game_client.CastStarted(
      cast_id: child,
      root_spell4_id:,
      parent_spell4_id:,
      caster_unit_id: child_caster,
      ..,
    ),
  ] = starts_of_spell(frames: first_tick, spell4_id: 77_099)
    as "opcode.0x7ff: one Affliction starts at 1000, on the one foe inside the box"
  assert #(root_spell4_id, parent_spell4_id, child_caster)
    == #(70_757, 58_868, caster_unit_id)
    as "opcode.0x7ff.root_parent: the field is the parent, Nullifier the root and the Medic the caster"
  assert list.contains(
    go_effects_in(frames: first_tick),
    #(child, beast_unit, [200_387]),
  )
    as "opcode.0x7f4: the child's go names the Beast and lists the Affliction's damage row 200387"
  let #(rounds, have) =
    list.fold([4, 5, 6, 7, 8], #([], have), fn(so_far, number) {
      let #(rounds, have) = so_far
      let #(round, have) = at_second(have, number, 1000)
      #(list.append(rounds, [round]), have)
    })
  list.each(rounds, fn(round) {
    assert list.length(starts_of_spell(frames: round, spell4_id: 77_099)) == 1
      as "an Affliction at each of the field's six seconds, the Beast still in the box the press made"
  })
  let health =
    list.flat_map([first_tick, ..rounds], beast_health_in(
      frames: _,
      beast: beast_unit,
    ))
  assert health != []
    as "opcode.0x937: the Beast's health falls with the Afflictions' ticks"
  let assert Ok(last_round) = list.last(rounds)
  let last_start =
    index_where(frames: last_round, found: fn(frame) {
      starts_of_spell(frames: [frame], spell4_id: 77_099) != []
    })
  let finish_at =
    index_where(frames: last_round, found: fn(frame) {
      finishes(frames: [frame], cast_id: field)
    })
  assert last_start >= 0 && finish_at > last_start
    as "opcode.0x7fe: the field finishes after the sixth Affliction starts (the tick at 6000 fires before the node ends)"
  let #(later, _) = at_second(have, 9, 1000)
  assert starts_of_spell(frames: later, spell4_id: 77_099) == []
    as "no seventh Affliction follows the field's end"
  game_client.close(game:)
  login_support.stop(started)
}

/// A Medic of level 12 presses Restrictor (SpellLevel 1119: Spell4 38279, base 22861) on the
/// driven clock with a Beast 3 m ahead, inside the box of its field (15 by 6, starting 1 m
/// ahead, a Random area of up to 10 units, `table_rows -- Spell4AoeTargetConstraints 391`).
/// Row 131274 of the field 38287 (tickTime 500, for the field's 4000 ms; text 306769 "apply a
/// Snare to foes inside the field every 0.5s") starts Snare 77118 on the Beast each half
/// second: the child's 0x7f4 lists the CCStateSet row 200476 with a non-zero instance id of its
/// own and the 0x87f tells state 21 under that id (`opcode.0x87f`, `cc_state.instance_id`); the
/// state ends with its own 0x880 after the state's 2000 ms (`cc_state.end`). The Beast stands at
/// Interrupt Armor 0, as a state lands only then. The Beast is shown the state and is not slowed
/// (no rule of the server reads a state's slow). Each wait is bounded by a pong.
pub fn a_medic_presses_restrictor_and_a_beast_in_its_field_is_shown_a_snare_state_every_half_second_test() -> Nil {
  use <- owned_test.run(120_000)
  let time = driven_time.new()
  let started = world_with_a_beast_ahead(tables: fixture_tables.shared(), time:)
  let #(game, have, bag_index, beast_unit) =
    medic_facing_the_beast(
      started:,
      character_name: "Res Tr",
      level: 12,
      base: 22_861,
    )
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(pressed, have) = game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Restrictor is planned, so the press is not refused"
  let assert [game_client.CastStarted(cast_id: field, ..)] =
    starts_of_spell(frames: pressed, spell4_id: 38_287)
    as "opcode.0x7ff: Proxy 82064 starts the field at the press"
  let #(early, have) =
    advanced_and_read(game:, time:, have:, number: 2, ms: 499)
  assert starts_of_spell(frames: early, spell4_id: 77_118) == []
    as "row 131274: tickTime 500, so no Snare 499 ms after the field's start"
  let #(first_tick, have) =
    advanced_and_read(game:, time:, have:, number: 3, ms: 1)
  let assert [game_client.CastStarted(cast_id: first_child, ..)] =
    starts_of_spell(frames: first_tick, spell4_id: 77_118)
    as "opcode.0x7ff: one Snare child starts at 500, on the Beast"
  let assert [#(_, _, [200_476])] =
    list.filter(go_effects_in(frames: first_tick), fn(entry) {
      entry.0 == first_child && entry.1 == beast_unit
    })
    as "opcode.0x7f4: the child's go lists the CCStateSet row 200476 on the Beast"
  let assert [#(_, first_effect_instance)] =
    list.filter_map(
      list.flat_map(first_tick, fn(frame) {
        case frame.message_id {
          0x07F4 -> {
            let assert Ok(go) = spell_go.decode(frame.body)
            [go]
          }
          _ -> []
        }
      }),
      fn(go) {
        case go.cast_id == first_child {
          True ->
            list.flat_map(go.targets, fn(target) { target.effects })
            |> list.first
            |> result.map(fn(effect) {
              #(effect.spell4_effects_id, effect.instance_id)
            })
          False -> Error(Nil)
        }
      },
    )
    as "the go's effect carries an instance id"
  assert first_effect_instance != 0
    as "cc_state.instance_id: the id the 0x7f4 lists must be non-zero"
  assert states_told_in(frames: first_tick)
    == [#(beast_unit, 21, first_effect_instance)]
    as "opcode.0x87f: the Beast is told Snare (state 21) under the id the go listed"
  let #(second_tick, have) =
    advanced_and_read(game:, time:, have:, number: 4, ms: 500)
  let #(rounds, have) =
    list.fold([5, 6, 7, 8, 9, 10], #([], have), fn(so_far, number) {
      let #(rounds, have) = so_far
      let #(round, have) =
        advanced_and_read(game:, time:, have:, number:, ms: 500)
      #(list.append(rounds, [round]), have)
    })
  // The eight rounds end at 500, 1000, 1500, 2000, 2500, 3000, 3500 and 4000, the ticks.
  let ticks = [first_tick, second_tick, ..rounds]
  let children =
    list.map(ticks, fn(round) {
      let assert [game_client.CastStarted(cast_id:, ..)] =
        starts_of_spell(frames: round, spell4_id: 77_118)
        as "a Snare child at each of the field's eight half seconds, 500 to 4000"
      cast_id
    })
  let instances =
    list.map(ticks, fn(round) {
      let assert [#(unit, 21, instance)] = states_told_in(frames: round)
        as "opcode.0x87f: one Snare (state 21) is told at each tick"
      assert unit == beast_unit as "and it is the Beast's"
      instance
    })
  assert list.first(instances) == Ok(first_effect_instance)
    as "the first tick's state is the id its go listed"
  assert list.length(list.unique(instances)) == 8
    && !list.contains(instances, 0)
    as "cc_state.instance_id: each child's state has a non-zero instance id of its own"
  // Stack group 1771 holds one snare of the caster on a unit (`Spell4StackGroup.stackCap` 1),
  // so each child takes the last one's node off with a 0x811, and only a 0x880 ends a state
  // (`cc_state.end`): the previous child's state ends at the next tick, long before its own
  // 2000 ms, and the last child's is still held when the field finishes.
  assert list.map(ticks, states_ended_in)
    == [
      [],
      ..list.map(list.zip(children, instances), fn(previous) {
        [#(beast_unit, previous.0, previous.1)]
      })
      |> list.take(7)
    ]
    as "opcode.0x880: at each tick after the first, the previous child's state ends under its cast and instance id, so the Beast holds one Snare at a time"
  let #(later, _) = advanced_and_read(game:, time:, have:, number: 11, ms: 500)
  assert starts_of_spell(frames: later, spell4_id: 77_118) == []
    && list.any(rounds, finishes(frames: _, cast_id: field))
    as "the field finishes at 4000 and no ninth Snare follows"
  assert states_ended_in(frames: later) == []
    as "the last child's state runs to its own 2000 ms, 6000"
  game_client.close(game:)
  login_support.stop(started)
}

/// Advances the driven clock by `ms` and reads what the connection wrote up to its pong with
/// `number`.
fn advanced_and_read(
  game game: game_client.Game,
  time time: driven_time.Time,
  have have: BitArray,
  number number: Int,
  ms ms: Int,
) -> #(List(Frame), BitArray) {
  driven_time.advance(time:, ms:)
  game_client.read_until_pong(game:, have:, number:)
}

/// A Warrior of level 24 presses Augmented Blade (SpellLevel 922: Spell4 46935, base 30896) on
/// the driven clock, and presses it again 3.5 s later. On, its Proxy 210305 casts 79753, whose
/// Proxy 210304 (delay 1000, tickTime 1000, `Spell4Effects.effectType.26.periodic`; text 442084
/// "Gain a stack of Kinetic Rage every 1s") casts a Kinetic Rage stack, 79757, at 2000 and
/// 3000. Off, 57357 takes the toggle's cast and 79753 off and starts 82838 one ms later (row
/// 217946, delayTime 1), whose Proxy 217944 (tickTime 500, persistence 38758; text 679906
/// "Removes a stack every 0.5 s when Augmented Blade is off") casts 82839 at 4001 and 4501,
/// each taking a stack, and 82838 ends with the last. The client sees the two stack removals
/// half a second apart and no third. Each wait is bounded by a pong. Kinetic Energy stays 0
/// throughout, so the proc 210339 (it fires 57357 on a change of the resource) never fires.
/// The test edits two cells of the Spell4 row to 0, each for its own reason:
/// - `casterInnateRequirement0` (Kinetic Energy of 250): the press is refused 51, and a Warrior
///   enters with none.
/// - `prerequisiteIdCasterCast` 37392 ("under Overdrive or under 79753"): the waiver of that
///   requirement (`Spell4.prerequisiteIdCasterCast`). With the requirement gone the plan reads
///   it as a gate, which a Warrior under neither cannot pass.
pub fn a_warrior_turns_augmented_blade_on_for_two_stacks_and_off_and_the_client_sees_two_stacks_removed_half_a_second_apart_and_no_third_test() -> Nil {
  use <- owned_test.run(120_000)
  use tables <- fixture_tables.changed(table: "Spell4", id: 46_935, with: [
    #("casterInnateRequirement0", planted_table.Integer(0)),
    #("prerequisiteIdCasterCast", planted_table.Integer(0)),
  ])
  let time = driven_time.new()
  let started = world_with_spawns(spawns: [], tables:, time:)
  let #(game, character) =
    new_player_at_level(
      started:,
      number: 1,
      character_name: "Aug Bl",
      class_id: 1,
      level: 24,
    )
  send_play(game:, character_id: character)
  let #(entry, have) = game_client.read_entry_kept(game:, have: <<>>)
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: entry), fn(item) { item.1 == 30_896 })
    as "SpellLevel 922 grants Augmented Blade's base 30896 to a Warrior of level 24"
  game_client.press_ability(game:, client_cast_id: 1, bag_index:, target: 0)
  let #(first_press, have) =
    game_client.read_until_pong(game:, have:, number: 1)
  assert refusals(frames: first_press) == []
    && game_client.confirmed_cast_of(frames: first_press, client_cast_id: 1)
    != Error(Nil)
    as "opcode.0x7fd: Augmented Blade is planned and the press is confirmed, not refused"
  // At 1999 no stack has started; the first starts at 2000 and the second at 3000.
  let #(at_1999, have) =
    advanced_and_read(game:, time:, have:, number: 2, ms: 1999)
  assert starts_of_spell(frames: at_1999, spell4_id: 79_757) == []
    as "row 210304: delayTime 1000 and tickTime 1000, so no stack before 2000"
  let #(at_2000, have) =
    advanced_and_read(game:, time:, have:, number: 3, ms: 1)
  assert list.length(starts_of_spell(frames: at_2000, spell4_id: 79_757)) == 1
    as "the first Kinetic Rage stack starts at 2000"
  let #(at_3000, have) =
    advanced_and_read(game:, time:, have:, number: 4, ms: 1000)
  assert list.length(starts_of_spell(frames: at_3000, spell4_id: 79_757)) == 1
    as "the second starts at 3000"
  // The second press at 3500 turns it off: 57357 starts, and 82838 one ms later.
  driven_time.advance(time:, ms: 500)
  game_client.press_ability(game:, client_cast_id: 2, bag_index:, target: 0)
  let #(second_press, have) =
    game_client.read_until_pong(game:, have:, number: 5)
  assert refusals(frames: second_press) == []
    as "the second press is not refused"
  assert list.length(starts_of_spell(frames: second_press, spell4_id: 57_357))
    == 1
    as "rows 136943 and 210350 take the toggle's cast and 79753 off, and Proxy 210340 starts 57357"
  assert starts_of_spell(frames: second_press, spell4_id: 82_838) == []
    as "82838 starts one ms after 57357's go, not at the press"
  let #(at_3501, have) =
    advanced_and_read(game:, time:, have:, number: 6, ms: 1)
  let assert [game_client.CastStarted(cast_id: removal_buff, ..)] =
    starts_of_spell(frames: at_3501, spell4_id: 82_838)
    as "row 217946: 82838 starts at 3501"
  let #(at_4000, have) =
    advanced_and_read(game:, time:, have:, number: 7, ms: 499)
  assert starts_of_spell(frames: at_4000, spell4_id: 79_757) == []
    && starts_of_spell(frames: at_4000, spell4_id: 82_839) == []
    as "79753's Proxy is gone, so no third stack, and 82838's first tick is not due before 4001"
  let #(at_4001, have) =
    advanced_and_read(game:, time:, have:, number: 8, ms: 1)
  assert list.length(starts_of_spell(frames: at_4001, spell4_id: 82_839)) == 1
    && !finishes(frames: at_4001, cast_id: removal_buff)
    as "Proxy 217944's first tick, 500 ms after 82838's go, starts 82839 and a stack is left"
  let #(at_4501, have) =
    advanced_and_read(game:, time:, have:, number: 9, ms: 500)
  assert list.length(starts_of_spell(frames: at_4501, spell4_id: 82_839)) == 1
    as "the second tick starts the second 82839"
  assert finishes(frames: at_4501, cast_id: removal_buff)
    as "opcode.0x7fe: 82838 ends in the input that takes the last stack"
  let #(at_6501, _) =
    advanced_and_read(game:, time:, have:, number: 10, ms: 2000)
  assert starts_of_spell(frames: at_6501, spell4_id: 82_839) == []
    && starts_of_spell(frames: at_6501, spell4_id: 79_757) == []
    as "no third removal and no stack follows"
  game_client.close(game:)
  login_support.stop(started)
}

/// The 0x7f4 among `frames`, decoded.
fn gos_in(frames frames: List(Frame)) -> List(spell_go.SpellGo) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == spell_go.message_id {
      True -> {
        let assert Ok(go) = spell_go.decode(frame.body) as "a 0x7f4 decodes"
        Ok(go)
      }
      False -> Error(Nil)
    }
  })
}

/// The value the property `property_id` holds in the player's own 0x262 among `frames`, 0 where
/// it sets none (the UnitProperty2 default of the properties read here).
fn own_property_in(
  frames frames: List(Frame),
  property_id property_id: Int,
) -> Float {
  result.unwrap(
    game_client.property_of(
      unit: game_client.unit_create_player_in(frames:),
      property_id:,
    ),
    0.0,
  )
}

/// An Esper of level 9 (Mind Over Body is an Esper's from level 6, Spell4Base 19030) presses
/// Mind Over Body at a Medic of level 9 that entered 300 health below its maximum, on the
/// client's real tables. Spell4 32820 (castTime 1250) holds one heal row at the primary
/// target, Spell4Effects 62019 (effectType 10, targetFlags 2, formula 0.3281 of the Support
/// Power and 17.51 a level, the stat part rounded alone, `0x140565600`): the Medic's
/// connection applies it and answers the Esper's, whose go lists the heal with what the Medic
/// took (opcode.0x7f4.target_info, `spell.heal_result_log`). The Esper's Support Power is its
/// property 36 (Support Rating) times GameFormula 1266's second value, read from its own
/// 0x262 and the tables; the Medic's maximum health is its own 0x262's (the client's Max
/// Health, property 7, cut to a whole number).
///
/// The Medic regenerates 2.5% of its maximum every 500 ms out of combat (a server choice,
/// `player_life`), so by the go, 1250 ms on, it has regenerated twice and its room is less
/// than the heal: the heal is partly overheal, and the room is read from the health the
/// Medic's client was last told before the heal.
pub fn an_esper_pressing_mind_over_body_at_an_ally_heals_it_and_the_go_lists_the_heal_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let missing = 300
  // The Medic's saved health is set before it plays, below the maximum a Medic of level 9
  // has on the same tables.
  let #(_, medic_entry) =
    world_entry_support.entry(
      tables:,
      character: world_entry_support.character(class: 4, faction: 166, level: 9),
    )
  let saved =
    casting.caster_of(tables:, entered: medic_entry).vitals.max_health - missing
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    second_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started:,
      first_class: 3,
      level: 9,
      first_acts: fn(_, have) {
        let pool = pog.named_connection(started.settings.pool.pool_name)
        let assert Ok(_) =
          pog.query("update character set health = $1 where name = 'Ann Qu'")
          |> pog.parameter(pog.int(saved))
          |> pog.execute(pool)
          as "the Medic's row holds the health it saved"
        #([], have)
      },
    )
  let esper = 1
  let medic = unit_of(seen_second)
  let medic_sheet =
    game_client.sheet(
      unit: game_client.unit_create_player_in(frames: second_burst),
      tables:,
    )
  assert medic == 2 && medic_sheet.max_health == saved + missing
    as "the Medic is the second unit and its own 0x262 gives the maximum health its saved health is 300 below"
  assert health_in(frames: second_burst) == saved
    as "opcode.0x262: the Medic enters with the health it saved"
  assert own_property_in(frames: second_burst, property_id: 111) == 0.0
    as "UnitProperty2 row 111 (HealToShieldConversion) has the default 0 and the Medic's 0x262 sets none, so the Medic's heal all goes to its health"
  let assert Ok(power) = game_formula.get(tables:, id: GameFormulaId(1266))
    as "the client's tables hold GameFormula row 1266"
  let support_power =
    own_property_in(frames: first_burst, property_id: 36) *. power.datafloat01
  let amount =
    float.round(int.to_float(float.round(0.3281 *. support_power)) +. 157.59)
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 9,
      ability: 19_030,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  driven_time.advance(time:, ms: 1250)
  // The answer crosses from the Medic's process, so the go is waited for by itself and
  // never by a pong alone.
  let #(went, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      gos_in(frames:) != []
    })
  let #(rest, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let esper_frames = list.flatten([pressed, went, rest])
  let #(medic_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      gos_in(frames:) != []
      && game_client.own_health_of(
        events: game_client.fight_in(frames:),
        unit: medic,
      )
      != []
    })
  let #(medic_rest, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let medic_frames = list.append(medic_read, medic_rest)
  let medic_events = game_client.fight_in(frames: medic_frames)
  let medic_healths =
    game_client.own_health_of(events: medic_events, unit: medic)
  let assert Ok(after) = list.last(medic_healths)
    as "the Medic's client is written its health after the heal"
  let before =
    list.reverse(medic_healths)
    |> list.drop(1)
    |> list.first
    |> result.unwrap(saved)
  let room = medic_sheet.max_health - before
  assert after == medic_sheet.max_health && room > 0 && room < amount
    as "opcode.0x92f: the heal takes the Medic's health to its maximum from what it had after its regeneration, and that room is less than the heal, so the Medic could not take the heal whole"
  assert game_client.shield_of(events: medic_events, unit: medic) == []
    as "opcode.0x938: the Medic's shield is untouched"
  assert refusals(frames: esper_frames) == []
    as "opcode.0x7fc: the press at the Medic in sight is accepted"
  let assert [confirmed] =
    connection_support.decoded(
      esper_frames,
      spell_cast_confirmed.message_id,
      spell_cast_confirmed.decode,
    )
    as "the Esper's client is answered the press once"
  assert confirmed.primary_target_unit_id == medic
    as "opcode.0x9a: Mind Over Body is the Targeted kind (Spell4TargetMechanics row 4), so the 0x7fd names the Medic as the cast's primary target"
  let assert [started_cast] =
    connection_support.decoded(
      medic_frames,
      spell_started.message_id,
      spell_started.decode,
    )
    as "the Medic's client is told the cast once"
  assert started_cast.primary_target_unit_id == medic
    && started_cast.caster_unit_id == esper
    as "opcode.0x7ff: the Medic's client reads the Esper's cast with the Medic itself as its primary target"
  let assert [go] = gos_in(frames: esper_frames)
    as "the Esper's client reads one 0x7f4"
  let assert [target] = go.targets
    as "the go names one unit, the Medic: none of the Esper's own is listed"
  assert target.unit_id == medic
  assert list.map(target.effects, fn(effect) {
      #(effect.spell4_effects_id, effect.result)
    })
    == [
      #(
        62_019,
        cast_support.heal_result(
          amount:,
          kind: damage_type.Heal,
          overkill: amount - room,
        ),
      ),
    ]
    as "Spell4Effects 62019 is listed on the Medic with the heal it applied: a Heal of the amount, the part the Medic's room could not take as the overheal, which the client logs as a heal of the amount and that overheal (`spell.heal_result_log`)"
  assert gos_in(frames: medic_frames) == [go]
    as "the Medic's client reads the very 0x7f4 the Esper's client reads"
  let esper_events = game_client.fight_in(frames: esper_frames)
  assert game_client.own_health_of(events: esper_events, unit: esper) == []
    as "the Esper's own health is not raised: the caster is not the target"
  assert list.last(game_client.health_of(events: esper_events, unit: medic))
    == Ok(medic_sheet.max_health)
    as "opcode.0x937: the Esper's client, a viewer of the Medic, is told its health after the heal"
  assert list.length(esper_frames)
    - 1
    - index_where(frames: list.reverse(esper_frames), found: fn(frame) {
      frame.message_id == 0x0937
    })
    > index_where(frames: esper_frames, found: fn(frame) {
      frame.message_id == spell_go.message_id
    })
    as "the Esper's connection holds the Medic's health news while the Medic's place waits and writes it after the go"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// What a Medic's press of Emission, with a hurt Medic ally standing `south` metres south of it,
/// showed the two clients.
type EmissionRound {
  EmissionRound(
    caster: Int,
    ally: Int,
    saved: Int,
    amount: Int,
    go: spell_go.SpellGo,
    caster_healths: List(Int),
    ally_healths: List(Int),
  )
}

/// A Medic of level 6 presses Emission (Spell4 58841, Spell4Base 38210) with no target named,
/// facing -z, while a Medic ally that entered with 100 health stands `south` metres south of it
/// (a negative number is ahead), the caster saved with the same health. The first pulse of the
/// channel goes at 410 ms (the row's phaseFlags 1 is the first go), before either Medic's
/// regeneration, which falls every 500 ms (`player_life`): both read their own health after the
/// heal.
fn emission_pressed_with_an_ally(south south: Float) -> EmissionRound {
  let time = driven_time.new()
  let tables = character_tables.shared()
  let started = started_on(tables:, time:)
  let saved = 100
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    second_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) =
    game_wire_support.two_players_enter_saved(
      started:,
      first_class: 4,
      level: 6,
      saved_health: option.Some(saved),
      first_acts: fn(_, have) { #([], have) },
    )
  let caster = unit_of_player(frames: first_burst)
  let ally = unit_of(seen_second)
  assert health_in(frames: first_burst) == saved
    && health_in(frames: second_burst) == saved
    as "opcode.0x262: both Medics enter with the 100 they were saved with"
  let #(x, y, z) =
    game_client.placed_by_tail(
      tail: game_client.unit_create_player_in(frames: first_burst).tail,
    )
  game_client.face(game: first, yaw: 0.0, clock: 100)
  game_client.move_to(game: second, clock: 110, x:, y:, z: z +. south)
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0638 })
    })
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: first_burst), fn(item) {
      item.1 == 38_210
    })
    as "the level-6 Medic holds Emission's base 38210 (SpellLevel 1221)"
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: Emission is planned, so the press is not refused"
  driven_time.advance(time:, ms: 410)
  let #(went, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      gos_in(frames:) != []
    })
  let #(rest, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let caster_frames = list.flatten([went, rest])
  let #(ally_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      gos_in(frames:) != []
    })
  let #(ally_rest, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let ally_frames = list.append(ally_read, ally_rest)
  let assert Ok(power) = game_formula.get(tables:, id: GameFormulaId(1266))
    as "the tables hold GameFormula row 1266"
  let support_power =
    own_property_in(frames: first_burst, property_id: 36) *. power.datafloat01
  let amount =
    float.round(
      int.to_float(float.round(0.0784 *. support_power)) +. 3.41 *. 6.0,
    )
  let assert Ok(go) =
    list.find(gos_in(frames: caster_frames), fn(go) {
      list.any(go.targets, fn(target) {
        list.any(target.effects, fn(effect) {
          effect.spell4_effects_id == 141_384
        })
      })
    })
    as "the caster's client reads the 0x7f4 that holds the heal row 141384 (phaseFlags 1: the first pulse alone)"
  let healths = fn(frames, unit) {
    game_client.own_health_of(events: game_client.fight_in(frames:), unit:)
  }
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
  EmissionRound(
    caster:,
    ally:,
    saved:,
    amount:,
    go:,
    caster_healths: healths(caster_frames, caster),
    ally_healths: healths(ally_frames, ally),
  )
}

/// The unit id the player's own 0x262 among `frames` gives it.
fn unit_of_player(frames frames: List(Frame)) -> Int {
  game_client.unit_create_player_in(frames:).unit_id
}

/// The rows of the heal 141384 the go lists on the unit `unit_id`, one list for each of its
/// entries (the caster's entry also holds the Gain row 179618 of Emission's first go, which is
/// not under test).
fn heal_listed_on(
  round: EmissionRound,
  unit_id: Int,
) -> List(List(#(Int, spell_effect_result.SpellEffectResult))) {
  list.filter(round.go.targets, fn(target) { target.unit_id == unit_id })
  |> list.map(fn(target) {
    list.filter(target.effects, fn(effect) {
      effect.spell4_effects_id == 141_384
    })
    |> list.map(fn(effect) { #(effect.spell4_effects_id, effect.result) })
  })
}

/// A Medic of level 6 presses Emission (Spell4 58841) with no target named, which none of the
/// whole-server tests walks: its area is a friendly one (Spell4TargetMechanics flags 9, bit 0
/// beneficial), so the allies of the cone 3063 (shape 8, 1 to 15 m over 50 degrees ahead of
/// the caster) take the heal of its row 141384 (type 10, targetFlags 5, delay 0, parameter 13
/// x 0.0784 and 10 x 3.41, `0x140565600`: the stat part rounded alone). A hurt Medic ally 8 m
/// ahead applies it itself and answers, the caster's 0x7f4 lists the ally's heal with the
/// split the ally answered and the caster's own, and both Medics' own 0x92f show their health
/// raised by the amount. The same ally 8 m behind the caster, outside the cone, is not healed
/// and not listed.
pub fn a_medic_pressing_emission_heals_the_ally_in_its_cone_and_the_caster_reads_the_go_with_its_heal_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  let listed = heal_listed_on
  let heal_of = fn(round: EmissionRound) {
    [
      #(
        141_384,
        cast_support.heal_result(
          amount: round.amount,
          kind: damage_type.Heal,
          overkill: 0,
        ),
      ),
    ]
  }
  let ahead = emission_pressed_with_an_ally(south: -8.0)
  assert ahead.amount > 0 as "the row's amount is above 0"
  assert listed(ahead, ahead.ally) == [heal_of(ahead)]
    as "opcode.0x7f4: the ally 8 m ahead is listed with its own heal, the split it answered: the whole amount, the ally's room being 100 or more"
  assert listed(ahead, ahead.caster) == [heal_of(ahead)]
    as "opcode.0x7f4: the caster's own heal is listed, its room being as large"
  assert list.last(ahead.ally_healths) == Ok(ahead.saved + ahead.amount)
    as "opcode.0x92f: the ally's health rises by the row's amount"
  assert list.last(ahead.caster_healths) == Ok(ahead.saved + ahead.amount)
    as "opcode.0x92f: the caster's own health rises by the row's amount"
  let behind = emission_pressed_with_an_ally(south: 8.0)
  assert listed(behind, behind.ally) == []
    as "opcode.0x7f4: the ally 8 m behind the caster is outside the cone and not listed"
  assert behind.ally_healths == []
    as "opcode.0x92f: the ally outside the cone is told no health"
  assert listed(behind, behind.caster) == [heal_of(behind)]
    as "the control: the caster's own heal is listed whoever stands in the cone"
}

/// What a Medic's press of Triage, with a Medic ally standing 8 m ahead of it, showed the two
/// clients: each Medic's own health before the press (`caster_saved`, `ally_saved`), the
/// amount of the heal row 141503, the caster's go and what each client read of its own health.
type TriageRound {
  TriageRound(
    caster: Int,
    ally: Int,
    caster_saved: Int,
    ally_saved: Int,
    amount: Int,
    go: spell_go.SpellGo,
    caster_healths: List(Int),
    ally_healths: List(Int),
  )
}

/// A Medic of level 9 presses Triage (Spell4 29888, Spell4Base 16336, a type 2 target: the
/// caster is its primary target whatever it has targeted) with a Medic of the same faction
/// 8 m ahead of it, the two saved with the health given. Triage has no cast time, so the go is
/// the press's own, before either Medic's regeneration, which falls every 500 ms
/// (`player_life`): each reads its own health after the heal.
fn triage_pressed_with_an_ally(
  caster_saved caster_saved: Int,
  ally_saved ally_saved: Int,
) -> TriageRound {
  let time = driven_time.new()
  let tables = character_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) =
    game_wire_support.two_players_enter_saved_each(
      started:,
      first_class: 4,
      level: 9,
      first_health: option.Some(caster_saved),
      second_health: option.Some(ally_saved),
      first_acts: fn(_, have) { #([], have) },
    )
  let caster = unit_of_player(frames: first_burst)
  let ally = unit_of(seen_second)
  assert health_in(frames: first_burst) == caster_saved
    as "opcode.0x262: the caster enters with the health it was saved with"
  let #(x, y, z) =
    game_client.placed_by_tail(
      tail: game_client.unit_create_player_in(frames: first_burst).tail,
    )
  game_client.face(game: first, yaw: 0.0, clock: 100)
  game_client.move_to(game: second, clock: 110, x:, y:, z: z -. 8.0)
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0638 })
    })
  let assert Ok(#(bag_index, _)) =
    list.find(location_4_items(frames: first_burst), fn(item) {
      item.1 == 16_336
    })
    as "the level-9 Medic holds Triage's base 16336 (SpellLevel 1021)"
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  let #(went, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      gos_in(frames:) != []
    })
  assert refusals(frames: went) == []
    as "opcode.0x7fc: Triage is planned, so the press is not refused"
  let #(rest, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let caster_frames = list.append(went, rest)
  let #(ally_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      gos_in(frames:) != []
    })
  let #(ally_rest, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let ally_frames = list.append(ally_read, ally_rest)
  let assert Ok(power) = game_formula.get(tables:, id: GameFormulaId(1266))
    as "the tables hold GameFormula row 1266"
  let support_power =
    own_property_in(frames: first_burst, property_id: 36) *. power.datafloat01
  let amount =
    float.round(
      int.to_float(float.round(0.3139 *. support_power)) +. 13.67 *. 9.0,
    )
  let assert Ok(go) =
    list.find(gos_in(frames: caster_frames), fn(go) { go.targets != [] })
    as "the caster's client reads a 0x7f4 that lists a unit"
  let healths = fn(frames, unit) {
    game_client.own_health_of(events: game_client.fight_in(frames:), unit:)
  }
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
  TriageRound(
    caster:,
    ally:,
    caster_saved:,
    ally_saved:,
    amount:,
    go:,
    caster_healths: healths(caster_frames, caster),
    ally_healths: healths(ally_frames, ally),
  )
}

/// The rows of the heal 141503 the go lists on the unit `unit_id`, one list for each of its
/// entries.
fn triage_heal_listed_on(
  round: TriageRound,
  unit_id: Int,
) -> List(List(#(Int, spell_effect_result.SpellEffectResult))) {
  list.filter(round.go.targets, fn(target) { target.unit_id == unit_id })
  |> list.map(fn(target) {
    list.filter(target.effects, fn(effect) {
      effect.spell4_effects_id == 141_503
    })
    |> list.map(fn(effect) { #(effect.spell4_effects_id, effect.result) })
  })
}

/// A Medic of level 9 presses Triage with no target named: its area (Spell4AoeTargetConstraints
/// 735: 360 degrees, 0 to 35 m, one target, ordered by missing health) finds the Medic ally
/// 8 m ahead, and its heal row 141503 (type 10, targetFlags 4: the area alone, parameter 13 x
/// 0.3139 and 10 x 13.67, `0x140565600`: the stat part rounded alone) does not name the caster,
/// so the caster is a candidate of the area, as the text 195454 says ("yourself or an ally based
/// on who has the lowest health", Jim's decision on 2026-11-23). The one it takes is the one
/// missing the most health, by the health each told the server on entering. Case one: the ally
/// entered missing more: its own 0x92f rises by the row's amount, the caster's 0x7f4 lists that
/// heal on the ally, and the caster's own health does not rise. Case two: the caster entered
/// missing more: its own health rises and the ally's does not.
pub fn a_medic_pressing_triage_heals_whoever_misses_the_most_health_of_itself_and_the_ally_in_its_cone_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  let heal_of = fn(round: TriageRound) {
    [
      #(
        141_503,
        cast_support.heal_result(
          amount: round.amount,
          kind: damage_type.Heal,
          overkill: 0,
        ),
      ),
    ]
  }
  let ally_hurt =
    triage_pressed_with_an_ally(caster_saved: 400, ally_saved: 100)
  assert ally_hurt.amount > 0 as "the row's amount is above 0"
  assert triage_heal_listed_on(ally_hurt, ally_hurt.ally)
    == [heal_of(ally_hurt)]
    as "opcode.0x7f4: the ally, which entered missing more health, is listed with its own heal, the split it answered"
  assert triage_heal_listed_on(ally_hurt, ally_hurt.caster) == []
    as "opcode.0x7f4: the caster, missing less than the ally, is not selected, and Triage's one target is the ally"
  assert list.last(ally_hurt.ally_healths)
    == Ok(ally_hurt.ally_saved + ally_hurt.amount)
    as "opcode.0x92f: the ally's health rises by the row's amount"
  assert ally_hurt.caster_healths == []
    as "opcode.0x92f: the caster's health does not rise"
  let caster_hurt =
    triage_pressed_with_an_ally(caster_saved: 100, ally_saved: 400)
  assert triage_heal_listed_on(caster_hurt, caster_hurt.caster)
    == [heal_of(caster_hurt)]
    as "opcode.0x7f4: the caster, which entered missing more health, is listed with its own heal"
  assert triage_heal_listed_on(caster_hurt, caster_hurt.ally) == []
    as "opcode.0x7f4: the ally, missing less than the caster, is not listed"
  assert list.last(caster_hurt.caster_healths)
    == Ok(caster_hurt.caster_saved + caster_hurt.amount)
    as "opcode.0x92f: the caster's own health rises by the row's amount"
  assert caster_hurt.ally_healths == []
    as "opcode.0x92f: the ally is told no health"
}

/// The 0x7f8 among `frames`, decoded, in order.
fn ticks_in(
  frames frames: List(Frame),
) -> List(spell_effect_tick.SpellEffectTick) {
  connection_support.decoded(
    frames,
    spell_effect_tick.message_id,
    spell_effect_tick.decode,
  )
}

/// An Esper of level 9 (Bolster is an Esper's from level 7, Spell4Base 19031) presses
/// Bolster at a Medic of level 9 that entered below its maximum, on the client's real
/// tables. Spell4 32821 (castTime 0) holds one periodic heal row at the primary target,
/// Spell4Effects 80077 (effectType 10, targetFlags 2, tickTime 1000, durationTime 8000,
/// formula 0.1977 of the Support Power and 10.54 a level, the stat part rounded alone,
/// `0x140565600`): each tick tells the Medic's connection the row, the Medic applies it and
/// answers, and the Esper's client reads a 0x7f8 naming the Medic with the heal the Medic
/// applied (`opcode.0x7f8`, `spell.heal_result_log`).
///
/// The Medic regenerates 2.5% of its maximum, r, every 500 ms out of combat (a server
/// choice, `player_life`), and the Esper presses 250 ms after the clock starts so that no
/// regeneration falls at a tick: the ticks are at 1250 ms and each 1000 ms on, the
/// regenerations at each 500 ms, so the room tick k reads is the missing health less 2k
/// regenerations and the k - 1 earlier ticks. The Medic enters 8 r + 3 a + a / 2 below its
/// maximum, a being the tick's amount: ticks 1 to 3 are taken whole, tick 4 finds a / 2 of
/// room and is partly overheal, and ticks 5 to 8 find the Medic full and are wholly
/// overheal. Each tick's overheal is checked against the health the Medic's client was
/// last told before it, and the Medic's next 0x92f is that health and what the tick took.
pub fn an_esper_pressing_bolster_at_an_ally_heals_it_on_each_tick_and_the_caster_reads_each_0x7f8_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let #(_, medic_entry) =
    world_entry_support.entry(
      tables:,
      character: world_entry_support.character(class: 4, faction: 166, level: 9),
    )
  let #(_, esper_entry) =
    world_entry_support.entry(
      tables:,
      character: world_entry_support.character(class: 3, faction: 166, level: 9),
    )
  let assert Ok(power) = game_formula.get(tables:, id: GameFormulaId(1266))
    as "the client's tables hold GameFormula row 1266"
  // Spell4Effects 80077 at level 9: round(0.1977 x Support Power) + 10.54 x 9, the Support
  // Power being the Support Rating times GameFormula 1266's second value.
  let amount_of = fn(support_rating) {
    float.round(
      int.to_float(float.round(
        0.1977 *. { support_rating *. power.datafloat01 },
      ))
      +. 94.86,
    )
  }
  let max_health =
    casting.caster_of(tables:, entered: medic_entry).vitals.max_health
  let regeneration =
    float.truncate(
      int.to_float(max_health) *. spawn_support.numbers.health_regen_fraction,
    )
  let planned_amount =
    amount_of(
      casting.caster_of(tables:, entered: esper_entry).stats.support_rating,
    )
  let missing = 8 * regeneration + 3 * planned_amount + planned_amount / 2
  let saved = max_health - missing
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    second_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) =
    two_players_enter_after(
      started:,
      first_class: 3,
      level: 9,
      first_acts: fn(_, have) {
        let pool = pog.named_connection(started.settings.pool.pool_name)
        let assert Ok(_) =
          pog.query("update character set health = $1 where name = 'Ann Qu'")
          |> pog.parameter(pog.int(saved))
          |> pog.execute(pool)
          as "the Medic's row holds the health it saved"
        #([], have)
      },
    )
  let esper = 1
  let medic = unit_of(seen_second)
  let medic_sheet =
    game_client.sheet(
      unit: game_client.unit_create_player_in(frames: second_burst),
      tables:,
    )
  assert medic == 2 && medic_sheet.max_health == saved + missing
    as "the Medic is the second unit and its own 0x262 gives the maximum health its saved health is the missing health below"
  assert health_in(frames: second_burst) == saved
    as "opcode.0x262: the Medic enters with the health it saved"
  let amount = amount_of(own_property_in(frames: first_burst, property_id: 36))
  assert amount == planned_amount
    as "the Esper's own 0x262 gives the Support Rating the Medic's missing health was sized by"
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 9,
      ability: 19_031,
    )
  driven_time.advance(time:, ms: 250)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  let #(pressed, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  assert refusals(frames: pressed) == []
    as "opcode.0x7fc: the press at the Medic in sight is accepted (a Focus cost of 70 is held)"
  let assert [go] =
    list.filter(gos_in(frames: pressed), fn(go) { go.targets != [] })
    as "the cast has no cast time: the Esper's client reads the one 0x7f4 that names a unit at the press (Bolster's Proxy child 216947 casts on the Esper and lists none)"
  let assert [target] = go.targets
    as "the go names one unit, the Medic: none of the Esper's own is listed"
  assert target.unit_id == medic
  assert list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    == [80_077]
    as "Spell4Effects 80077 is listed on the Medic"
  assert list.all(target.effects, fn(effect) {
    case effect.result {
      spell_effect_result.Damage(..) -> False
      _ -> True
    }
  })
    as "the go lists the periodic row with no description: the ticks carry the heals"
  assert ticks_in(frames: pressed) == [] as "opcode.0x7f8: no tick at the press"
  // The clock stands 1 ms short of the first tick: nothing is written.
  driven_time.advance(time:, ms: 999)
  let #(before_first, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  assert ticks_in(frames: before_first) == []
    as "Spell4Effects 80077: tickTime 1000, so no 0x7f8 before 1000 ms"
  let #(medic_before, second_have) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let medic_health_before =
    game_client.own_health_of(
      events: game_client.fight_in(frames: medic_before),
      unit: medic,
    )
  // Each tick: the clock steps, the Esper's client is read until its tick count grows (the
  // answer crosses from the Medic's process), then the Medic's client up to a pong, which
  // follows the news the Medic wrote when it applied the heal.
  let #(steps, first_have, _) =
    list.fold(
      [1, 2, 3, 4, 5, 6, 7, 8],
      #([], first_have, second_have),
      fn(so_far, tick) {
        let #(done, first_have, second_have) = so_far
        driven_time.advance(time:, ms: case tick {
          1 -> 1
          _ -> 1000
        })
        let #(seen, first_have) =
          game_client.read_until(
            game: first,
            have: first_have,
            found: fn(frames) { ticks_in(frames:) != [] },
          )
        let #(medic_frames, second_have) =
          game_client.read_until_pong(
            game: second,
            have: second_have,
            number: tick + 1,
          )
        #(list.append(done, [#(seen, medic_frames)]), first_have, second_have)
      },
    )
  let #(rest, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  let esper_frames =
    list.append(list.flat_map(steps, fn(step) { step.0 }), rest)
  let ticks = ticks_in(frames: esper_frames)
  assert list.map(ticks, fn(tick) { #(tick.spell4_effects_id, tick.unit_id) })
    == list.repeat(#(80_077, medic), 8)
    as "Spell4Effects 80077: one 0x7f8 for each of the 8 ticks of its 8000 ms, each naming the Medic, and none after the eighth"
  assert list.all(steps, fn(step) { list.length(ticks_in(frames: step.0)) == 1 })
    as "one 0x7f8 for each 1000 ms step"
  let descriptions =
    list.map(ticks, fn(tick) {
      let assert [description] = tick.descriptions
        as "a tick on another player carries the one heal the player applied"
      description
    })
  assert list.all(descriptions, fn(description) {
    description.damage_type == damage_type.Heal
    && description.combat_result == combat_result.Hit
    && description.raw_damage == amount
    && description.scaled_raw_damage == amount
    && description.health_damage_with_overkill == amount
    && description.killed == 0
  })
    as "each tick is a Hit of damage type Heal (4) of the amount the formula gives for the Esper: round(0.1977 x Support Power) + 10.54 x 9"
  let overheals =
    list.map(descriptions, fn(description) { description.overkill })
  let writes_of = fn(frames) {
    game_client.own_health_of(
      events: game_client.fight_in(frames:),
      unit: medic,
    )
  }
  assert medic_health_before == [saved + regeneration, saved + 2 * regeneration]
    as "opcode.0x92f: the Medic regenerated twice before the first tick, 2.5% of its maximum each time"
  assert list.take(overheals, 3) == [0, 0, 0]
    && list.drop(overheals, 4) == list.repeat(amount, 4)
    as "ticks 1 to 3 find room for the whole heal and ticks 5 to 8 find the Medic full"
  assert list.take(list.drop(overheals, 3), 1) == [amount - amount / 2]
    as "tick 4 finds half of the heal's room: the rest is overheal"
  // The health the Medic's client was told before each tick, and what the tick wrote: the
  // news up to the step's pong, the tick's own 0x92f last when the tick took any.
  let medic_told =
    list.index_fold(
      list.zip(steps, overheals),
      [saved, ..medic_health_before],
      fn(told, step_and_overheal, index) {
        let #(step, overheal) = step_and_overheal
        let tick = index + 1
        let told = list.append(told, writes_of(step.1))
        let taken = amount - overheal
        let tick_name = "tick " <> int.to_string(tick)
        case list.reverse(told) {
          [written, before, ..] if taken > 0 -> {
            assert written == before + taken
              as {
                "opcode.0x92f: "
                <> tick_name
                <> " raises the health the Medic's client was last told by what it took"
              }
            assert overheal == amount - int.min(amount, max_health - before)
              as {
                "opcode.0x7f8: "
                <> tick_name
                <> " takes what the Medic's room allows and the rest is overheal"
              }
          }
          [before, ..] -> {
            assert before == max_health && overheal == amount
              as {
                "a tick that takes nothing finds the Medic at its maximum and is wholly overheal: "
                <> tick_name
              }
          }
          [] -> panic as "the Medic's client was told its health"
        }
        told
      },
    )
  assert list.last(medic_told) == Ok(max_health)
    && medic_told == list.sort(medic_told, int.compare)
    as "the Medic's health only rises, to its maximum"
  assert list.filter(esper_frames, fn(frame) {
      frame.message_id == spell_finished.message_id
    })
    |> list.length
    == 1
    as "opcode.0x7fe: the cast ends once"
  assert list.map(esper_frames, fn(frame) { frame.message_id })
    |> list.filter(fn(id) {
      id == spell_finished.message_id || id == spell_effect_tick.message_id
    })
    |> list.last
    == Ok(spell_finished.message_id)
    as "the cast's 0x7fe follows the eighth tick"
  let esper_events = game_client.fight_in(frames: esper_frames)
  assert game_client.own_health_of(events: esper_events, unit: esper) == []
    as "the Esper's own health is untouched: the caster is not the target"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The absorption each 0x938 of stat 22 among `frames` gives `unit`, in order.
fn absorptions_in(frames frames: List(Frame), unit unit: Int) -> List(Int) {
  list.filter_map(game_client.fight_in(frames:), fn(event) {
    case event {
      game_client.AbsorptionIs(unit_id:, absorption:) if unit_id == unit ->
        Ok(absorption)
      _ -> Error(Nil)
    }
  })
}

/// An Esper of level 6 (Phantasmal Armor is an Esper's from level 6: SpellLevel 773, class 3,
/// characterLevel 6, Spell4 32823, Spell4Base 19033) presses it at a Medic of level 6 in sight, on the
/// client's real tables. Spell4 32823 (castTime 0, propertyFlags 257, durationTime 10 000
/// of its rows) holds one Absorption row, Spell4Effects 62024 (effectType 29, targetFlags 2,
/// mask 7, 10 000 ms, formula 1.9389 of the Support Power and 103.41 a level, the stat part
/// rounded alone, `0x140565600`; a tier 1 spell holds no modifier row, which the cast rule's
/// tests read with the real rows of tiers 5 to 9). The Esper's connection tells the Medic's
/// connection the pool at the go and its end after 10 000 ms; the Medic's client reads the
/// 0x938 of its own absorption (stat 22), and the Esper's, a viewer of the Medic, reads the
/// same stat of the Medic's unit from the Medic's news (`opcode.0x938`). The buff the go's
/// 0x7f4 lists ends with the cast's 0x7fe, which no client timer ends
/// (`cast.target_node_end`). The pool is round(round(1.9389 x Support Power) + 103.41 x 6),
/// the Support Power being the Esper's property 36 (Support Rating) times GameFormula 1266's
/// second value, read from its own 0x262. The Medic's pool and the Esper's go come from two
/// senders, so each is waited for by itself and never by its order against the other; the
/// clock is the test's.
pub fn an_esper_presses_phantasmal_armor_at_a_player_in_sight_and_that_player_reads_the_buff_the_absorb_and_the_end_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter(started:, first_class: 3, level: 6)
  let esper = 1
  let medic = unit_of(seen_second)
  assert medic == 2 as "the Medic is the second unit"
  let assert Ok(power) = game_formula.get(tables:, id: GameFormulaId(1266))
    as "the client's tables hold GameFormula row 1266"
  let support_power =
    own_property_in(frames: first_burst, property_id: 36) *. power.datafloat01
  let amount =
    float.round(
      int.to_float(float.round(1.9388999938964844 *. support_power)) +. 620.46,
    )
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  // The cast also starts the Interrupt Armor child on the Medic (Spell4 76766, a cast of its
  // own), whose start and go a client may read before or after the pressed cast's own, so the
  // pressed cast's go is the one that lists Spell4Effects 62024, and its start the one of
  // Spell4 32823.
  let pressed_gos = fn(frames) {
    list.filter(gos_in(frames:), fn(go) {
      list.any(go.targets, fn(target) {
        list.any(target.effects, fn(effect) {
          effect.spell4_effects_id == 62_024
        })
      })
    })
  }
  // The Medic's client is written the cast and its go, and its own absorption.
  let #(medic_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      pressed_gos(frames) != [] && absorptions_in(frames:, unit: medic) != []
    })
  let #(esper_read, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      pressed_gos(frames) != [] && absorptions_in(frames:, unit: medic) != []
    })
  assert refusals(frames: esper_read) == []
    as "opcode.0x7fc: the press at the Medic in sight is accepted"
  let assert [started_cast] =
    list.filter(
      connection_support.decoded(
        medic_read,
        spell_started.message_id,
        spell_started.decode,
      ),
      fn(start) { start.spell4_id == 32_823 },
    )
    as "the Medic's client is told the pressed cast once"
  assert started_cast.caster_unit_id == esper
    && started_cast.primary_target_unit_id == medic
    && started_cast.spell4_id == 32_823
    as "opcode.0x7ff: the Medic's client reads the Esper's cast of Spell4 32823 with the Medic as its primary target"
  let assert [go] = pressed_gos(medic_read)
    as "the Medic's client reads the cast's 0x7f4 once"
  assert go.cast_id == started_cast.cast_id
    as "and it is the go of the cast the Medic was told the start of"
  let assert [target] = go.targets
    as "the go names one unit, the Medic: the pressed spell's row aims at the primary target alone"
  assert target.unit_id == medic
  assert list.map(target.effects, fn(effect) {
      #(effect.spell4_effects_id, effect.delay_ms)
    })
    == [#(62_024, 0)]
    as "opcode.0x7f4.target_info: Spell4Effects 62024 is listed on the Medic with delay 0, which makes the Medic's client show the buff"
  assert pressed_gos(esper_read) == [go]
    as "the Esper's client reads the same 0x7f4"
  assert absorptions_in(frames: medic_read, unit: medic) == [amount]
    as "opcode.0x938: the Medic's client is told its absorption, the pool the Esper's formula gives"
  assert absorptions_in(frames: esper_read, unit: medic) == [amount]
    as "opcode.0x938: the Esper's client, a viewer of the Medic, reads the same stat of the Medic's unit from its news"
  assert !list.contains(
      finished_casts_in(frames: medic_read),
      started_cast.cast_id,
    )
    && !list.contains(
      finished_casts_in(frames: esper_read),
      started_cast.cast_id,
    )
    as "opcode.0x7fe: no client's buff ends before its time, and the cast is not finished while its node lives"
  // The node ends 10 000 ms after the go: the Esper's connection tells the end and the
  // 0x7fe goes to both clients.
  driven_time.advance(time:, ms: 10_000)
  let ended = fn(frames) {
    list.contains(finished_casts_in(frames:), started_cast.cast_id)
    && absorptions_in(frames:, unit: medic) == [0]
  }
  let #(medic_ended, _) =
    game_client.read_until(game: second, have: second_have, found: ended)
  let #(esper_ended, _) =
    game_client.read_until(game: first, have: first_have, found: ended)
  assert list.count(finished_casts_in(frames: medic_ended), fn(id) {
      id == started_cast.cast_id
    })
    == 1
    as "opcode.0x7fe: the Medic's client reads the cast end once, which ends its buff"
  assert absorptions_in(frames: medic_ended, unit: medic) == [0]
    as "opcode.0x938: the Medic's absorption returns to 0 with the cast's node"
  assert list.count(finished_casts_in(frames: esper_ended), fn(id) {
      id == started_cast.cast_id
    })
    == 1
    as "the Esper's client reads the same end"
  assert absorptions_in(frames: esper_ended, unit: medic) == [0]
    as "and the Medic's absorption at 0 from its news"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// The Interrupt Armor each 0x938 of stat 21 among `frames` gives the unit `unit`, in order
/// (`opcode.0x938.interrupt_armor`).
fn armors_in(frames frames: List(Frame), unit unit: Int) -> List(Int) {
  list.filter_map(game_client.fight_in(frames:), fn(event) {
    case event {
      game_client.InterruptArmorIs(unit_id:, armor:) if unit_id == unit ->
        Ok(armor)
      _ -> Error(Nil)
    }
  })
}

/// Phantasmal Armor as above: its Proxy 83947 starts the Interrupt Armor child (Spell4 76766,
/// a cast of its own) on the player the press named, the Medic, and not on the Esper.
/// Spell4Effects 199192 of the child is Interrupt Armor, +1 for 5000 ms, targetFlags 2 (the
/// primary target, the Medic), and the child's propertyFlags are 0 (`table_rows -- Spell4Effects
/// 83947 199192`). The Medic's client reads the child's 0x7ff (the Esper its caster, itself the
/// primary target), a 0x7f4 that lists the Medic with that effect, and its own armor (stat 21
/// of 0x938) at 1; the Esper's client, a viewer of the Medic, reads the same stat of the
/// Medic's unit from the Medic's news and none for its own unit. The child's node on the
/// Medic ends 5000 ms after the go, with the child's own 0x7fe and the armor back to 0, while
/// the parent's absorb (stat 22) stands until its 10 000 ms are over. The child's frames come
/// from the Esper's connection and the Medic's armor from its own, two senders, so each is
/// waited for by itself; the clock is the test's.
pub fn an_esper_presses_phantasmal_armor_at_a_player_in_sight_and_that_player_reads_the_interrupt_armor_for_five_seconds_and_the_esper_reads_none_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(first:, second:, seen_second:, first_have:, second_have:, ..) =
    two_players_enter(started:, first_class: 3, level: 6)
  let esper = 1
  let medic = unit_of(seen_second)
  assert medic == 2 as "the Medic is the second unit"
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  let child_starts = fn(frames) {
    list.filter(
      connection_support.decoded(
        frames,
        spell_started.message_id,
        spell_started.decode,
      ),
      fn(start) { start.spell4_id == 76_766 },
    )
  }
  let child_gos = fn(frames) {
    list.filter(gos_in(frames:), fn(go) {
      list.any(go.targets, fn(target) {
        list.any(target.effects, fn(effect) {
          effect.spell4_effects_id == 199_192
        })
      })
    })
  }
  let #(medic_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      child_starts(frames) != []
      && child_gos(frames) != []
      && armors_in(frames:, unit: medic) != []
    })
  let assert [child_start] = child_starts(medic_read)
    as "the Medic's client is told the child once"
  assert child_start.caster_unit_id == esper
    && child_start.primary_target_unit_id == medic
    as "opcode.0x7ff: the child's caster is the Esper and its primary target the Medic"
  let assert [go] = child_gos(medic_read)
    as "the Medic's client reads the child's 0x7f4 once"
  assert go.cast_id == child_start.cast_id
    as "and it is the go of the child the Medic was told the start of"
  let assert [target] = go.targets as "the child's go names one unit, the Medic"
  assert target.unit_id == medic
  assert list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    == [199_192]
    as "opcode.0x7f4.target_info: Spell4Effects 199192 is listed on the Medic, which makes its client show the buff"
  // The Medic's own armor is written by its own connection when the Esper's connection
  // tells it the change, so it is waited for by itself, not by its order against the child's
  // frames.
  let #(esper_read, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      child_gos(frames) != [] && armors_in(frames:, unit: medic) != []
    })
  assert armors_in(frames: medic_read, unit: medic) == [1]
    as "opcode.0x938: the Medic's client is told its own armor, +1, once"
  assert armors_in(frames: esper_read, unit: medic) == [1]
    as "the Esper's client, a viewer of the Medic, reads the same stat of the Medic's unit from its news"
  // The Esper's own connection has written everything the press gave it by the time its
  // pong is read, so no armor for its own unit is missing from what it was sent.
  let #(esper_after, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  assert armors_in(frames: list.append(esper_read, esper_after), unit: esper)
    == []
    as "opcode.0x938: the Esper's client reads no armor for its own unit: the row lands on the Medic"
  assert !list.contains(
    finished_casts_in(frames: medic_read),
    child_start.cast_id,
  )
    as "opcode.0x7fe: the child does not end before its time"
  // The child's node ends 5000 ms after the go: its 0x7fe and the Medic's armor back to 0.
  driven_time.advance(time:, ms: 5000)
  let ended = fn(frames) {
    list.contains(finished_casts_in(frames:), child_start.cast_id)
    && armors_in(frames:, unit: medic) == [0]
  }
  let #(medic_ended, second_have) =
    game_client.read_until(game: second, have: second_have, found: ended)
  assert list.count(finished_casts_in(frames: medic_ended), fn(id) {
      id == child_start.cast_id
    })
    == 1
    as "opcode.0x7fe: the Medic's client reads the child's end once"
  assert armors_in(frames: medic_ended, unit: medic) == [0]
    as "opcode.0x938: the Medic's armor returns to 0 with the child's node"
  assert absorptions_in(frames: medic_ended, unit: medic) == []
    as "the parent's absorb is not told to change: its 10 000 ms are not over"
  let #(esper_ended, _) =
    game_client.read_until(game: first, have: first_have, found: ended)
  assert armors_in(frames: esper_ended, unit: medic) == [0]
    as "the Esper's client reads the same armor of the Medic's unit"
  // The parent's end 10 000 ms after the go, as in the whole-server test of the pressed cast.
  driven_time.advance(time:, ms: 5000)
  let #(medic_parent_ended, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      absorptions_in(frames:, unit: medic) == [0]
    })
  assert absorptions_in(frames: medic_parent_ended, unit: medic) == [0]
    as "opcode.0x938: the Medic's absorption returns to 0 when the parent's 10 000 ms are over"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// Phantasmal Armor as above, then the Esper walks out of the Medic's sight: 1040 units
/// along z, past the sight range of 1024 (`sight.range`) from the Medic, who stays where it
/// entered. The client keeps a cast whose spell holds propertyFlags 0x100 and its buff when
/// the caster's unit is removed (`cast.target_node_end`), so the Medic's client reads the
/// Esper's removal (0x355) with no 0x7fe of the cast before it and its absorption (stat 22
/// of 0x938) not returned to 0; after the test's clock passes the row's 10 000 ms the Medic's
/// client reads the 0x7fe of that cast once and the absorption return to 0. The end is a frame
/// the Medic's own connection writes with the Esper out of its sight, after three processes
/// (the map and the two connections) changed who sees whom; each read waits for its own frame
/// and never for the order of one sender's frame against another's, and the clock is the
/// test's.
pub fn an_esper_walks_out_of_the_sight_of_the_ally_it_pressed_phantasmal_armor_at_and_the_ally_keeps_the_buff_and_the_absorb_until_the_end_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(first:, second:, seen_second:, second_have:, ..) =
    two_players_enter(started:, first_class: 3, level: 6)
  let esper = 1
  let medic = unit_of(seen_second)
  assert medic == 2 as "the Medic is the second unit"
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  // The pressed cast is the one of Spell4 32823 (the Interrupt Armor child on the Medic is a
  // cast of its own), and the Medic's own absorption is told by its own connection.
  let pressed_start = fn(frames) {
    list.filter(
      connection_support.decoded(
        frames,
        spell_started.message_id,
        spell_started.decode,
      ),
      fn(start) { start.spell4_id == 32_823 },
    )
  }
  let #(medic_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      pressed_start(frames) != []
      && list.any(absorptions_in(frames:, unit: medic), fn(value) { value > 0 })
    })
  let assert [started_cast] = pressed_start(medic_read)
    as "the Medic's client is told the pressed cast once"
  let assert [pool] = absorptions_in(frames: medic_read, unit: medic)
    as "the Medic's client is told its absorption once"
  assert pool > 0 as "opcode.0x938: the Medic holds the Esper's pool"
  // The Esper walks out of the Medic's sight, and the Medic's client reads its removal.
  walk_to(game: first, z: 1040.0, clock: 1)
  let #(removal_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), esper)
    })
  let #(after_removal, second_have) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let until_pong = list.flatten([medic_read, removal_read, after_removal])
  assert !list.contains(
    finished_casts_in(frames: until_pong),
    started_cast.cast_id,
  )
    as "opcode.0x7fe: the removal of the caster's unit leaves the cast of a 0x100 spell and its buff on the Medic (the Interrupt Armor child, a cast of its own, is finished with the unit)"
  // Only the 0x7fe check above is ordered by the pong: the 0x355 and the 0x7fe are written in
  // one handling of the Esper's removal. The release of the absorption (a source that ends
  // when its caster is unseen) comes from the Esper's connection's `UnseenBy`, another
  // sender, so a pong read here may precede it and this check alone could pass without
  // testing anything; the absorption kept to its end is read where the end is waited for.
  assert absorptions_in(frames: until_pong, unit: medic) == [pool]
    as "opcode.0x938: and the Medic's absorption is not told to change"
  // The cast's node on the Medic ends 10 000 ms after the go: the Esper's connection tells
  // the Medic's the end, which writes the absorption's end and, in the same handling of the
  // Medic's connection, the cast's 0x7fe (`landing.changed`: the ends first, then the casts
  // held with no caster). The read waits for the absorption's return to 0; a pong then bounds
  // the 0x7fe, which is among those frames or never written, so a missing 0x7fe fails the
  // count below instead of hanging the read.
  driven_time.advance(time:, ms: 10_000)
  let #(medic_ended, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      absorptions_in(frames:, unit: medic) == [0]
    })
  let #(after_end, second_have) =
    game_client.read_until_pong(game: second, have: second_have, number: 2)
  let until_end = list.append(medic_ended, after_end)
  assert list.count(finished_casts_in(frames: until_end), fn(id) {
      id == started_cast.cast_id
    })
    == 1
    as "opcode.0x7fe: the Medic's client reads the cast's end once, which ends its buff"
  assert absorptions_in(frames: until_end, unit: medic) == [0]
    as "opcode.0x938: and its absorption returns to 0"
  let #(later, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 3)
  assert finished_casts_in(frames: later) == []
    as "the cast is finished once, not again by a later write"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// Phantasmal Armor as above, then the Esper walks out of the Medic's sight, and a third
/// player, a Medic, comes into the first Medic's sight and never sees the Esper. The Medic's
/// 0x262 lists the Esper's cast of Spell4 32823 (`opcode.0x262.casts`): the Esper as its
/// caster, the Medic as its primary and only target, Spell4Effects 62024 with the time it has
/// left; the client shows a cast whose caster it does not know (`cast.unknown_caster`), so the
/// third client shows the buff. When the test's clock passes the row's 10 000 ms the Esper's
/// connection tells the Medic's the end and the Medic's tells the third a 0x811 naming the
/// Medic for that cast id (`opcode.0x811`), and no 0x7fe of it, which would end the cast's
/// nodes on other units too. The third client's reads wait for the Medic's 0x262 and the
/// 0x811 by themselves; the flow is three processes (the Esper's connection, the Medic's and
/// the third's), so no read depends on the order of one sender's frame against another's.
pub fn a_player_that_arrives_beside_an_ally_after_its_esper_walked_away_shows_the_phantasmal_armor_buff_on_the_ally_until_it_ends_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(first:, second:, seen_second:, second_have:, ..) =
    two_players_enter(started:, first_class: 3, level: 6)
  let esper = 1
  let medic = unit_of(seen_second)
  assert medic == 2 as "the Medic is the second unit"
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  let pressed_start = fn(frames) {
    list.filter(
      connection_support.decoded(
        frames,
        spell_started.message_id,
        spell_started.decode,
      ),
      fn(start) { start.spell4_id == 32_823 },
    )
  }
  let #(medic_read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      pressed_start(frames) != []
      && list.any(absorptions_in(frames:, unit: medic), fn(value) { value > 0 })
    })
  let assert [started_cast] = pressed_start(medic_read)
    as "the Medic's client is told the pressed cast once"
  walk_to(game: first, z: 1040.0, clock: 1)
  let #(_, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), esper)
    })
  // The third player enters at the Medic's place, 1040 units from the Esper.
  let #(third, third_character) =
    new_player_at_level(
      started:,
      number: 3,
      character_name: "Third Mc",
      class_id: 4,
      level: 6,
    )
  send_play(game: third, character_id: third_character)
  let #(third_entry, third_have) =
    game_client.read_entry_kept(game: third, have: <<>>)
  let created_medic = fn(frames) {
    list.any(frames, fn(frame) {
      created_unit_of(frame:) |> result.map(fn(created) { created.0 })
      == Ok(medic)
    })
  }
  let #(third_arrived, third_have) =
    game_client.read_until(game: third, have: third_have, found: fn(frames) {
      created_medic(list.append(third_entry, frames))
    })
  let third_seen = list.append(third_entry, third_arrived)
  assert !list.any(third_seen, fn(frame) {
    created_unit_of(frame:) |> result.map(fn(created) { created.0 })
    == Ok(esper)
  })
    as "the third player never sees the Esper: it stands 1040 units away, past the sight range"
  let medic_casts =
    list.flat_map(third_seen, fn(frame) {
      case created_unit_of(frame:) {
        Ok(#(created, casts)) if created == medic -> casts
        Ok(_) | Error(Nil) -> []
      }
    })
  let assert Ok(pressed) =
    list.find(medic_casts, fn(cast) { cast.cast_id == started_cast.cast_id })
    as "opcode.0x262.casts: the Medic's 0x262 lists the Esper's cast the third player was never told"
  assert pressed.caster_unit_id == esper
    && pressed.spell4_id == 32_823
    && pressed.primary_target_unit_id == medic
    as "the entry names the Esper as its caster, Spell4 32823 and the Medic as the primary target"
  let assert [target] = pressed.targets
    as "the cast holds one target, the Medic"
  assert target.unit_id == medic as "and it is the Medic"
  let assert [effect] = target.effects
    as "the Medic holds the one effect Spell4Effects 62024 of tier 1"
  assert effect.spell4_effects_id == 62_024
    && effect.delay_ms == 0
    && effect.lifetime_ms > 0
    && effect.lifetime_ms <= 10_000
    as "opcode.0x7f4.effect_time: the absorb is listed with delay 0 and the time it has left, at most its 10 000 ms"
  // The node ends 10 000 ms after the go: the Esper's connection tells the Medic's the end,
  // and the Medic's connection tells the third player's. The Medic's own client is written
  // its absorption's end in the step that tells the viewers, and the Medic's move after it is
  // told to the third player after the end, by the one sender, so the third player's read of
  // the move bounds the 0x811, which is among the frames read by then or never written.
  driven_time.advance(time:, ms: 10_000)
  let #(_, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      absorptions_in(frames:, unit: medic) == [0]
    })
  walk_to(game: second, z: 3.0, clock: 1)
  let #(until_end, _) =
    game_client.read_until(game: third, have: third_have, found: fn(frames) {
      list.any(game_client.fight_in(frames:), fn(event) {
        case event {
          game_client.Moves(unit_id:, ..) -> unit_id == medic
          _ -> False
        }
      })
    })
  assert list.count(
      game_client.targets_removed_in(frames: until_end),
      fn(removed) { removed == #(started_cast.cast_id, [medic]) },
    )
    == 1
    as "opcode.0x811: the third player's client reads one 0x811 naming the Medic for the cast, which ends the buff"
  assert !list.contains(
    finished_casts_in(frames: until_end),
    started_cast.cast_id,
  )
    as "opcode.0x7fe: and no 0x7fe of the cast, which would end its nodes on other units"
  game_client.close(game: first)
  game_client.close(game: second)
  game_client.close(game: third)
  login_support.stop(started)
}

/// A third player, a Medic, stands beside a Medic that an Esper is about to press Phantasmal
/// Armor at, and out of the Esper's sight: the Esper stands 30 m from the Medic (the spell's
/// range is 35 m, Spell4 32823 targetMaxRange) and the third 1000 m the other way, 1003.5 m
/// from the Medic and 1033.5 m from the Esper (sight range 1024, `sight.range`). The third
/// reads the Esper's removal first, which its connection writes when it has taken the map's
/// notice that the third no longer sees it, so the Esper's cast is not told to the third. The
/// third's client is then written, by the Medic's connection alone, the cast's 0x7ff naming the
/// Esper as its caster and the Medic as its primary target (`opcode.0x7ff`) and the 0x7f4 that
/// lists Spell4Effects 62024 on the Medic with the time it has left (`opcode.0x7f4`), the Esper
/// never created for it (`cast.unknown_caster`); when the test's clock passes the row's 10 000
/// ms it reads one 0x811 naming the Medic for that cast, and no 0x7fe of it (`opcode.0x811`).
/// The Medic's frames to the third are one sender's, so the 0x7ff comes before the 0x7f4 and
/// the Medic's move after the end bounds the read of the 0x811; the Esper's go and the
/// third's move are two senders, so nothing reads them in order against each other.
pub fn a_player_beside_an_ally_who_never_sees_its_esper_is_shown_the_phantasmal_armor_buff_when_it_lands_and_until_it_ends_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(first:, second:, seen_second:, first_have:, second_have:, ..) =
    two_players_enter(started:, first_class: 3, level: 6)
  let esper = 1
  let medic = unit_of(seen_second)
  assert medic == 2 as "the Medic is the second unit"
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    )
  let #(third, third_character) =
    new_player_at_level(
      started:,
      number: 3,
      character_name: "Third Mc",
      class_id: 4,
      level: 6,
    )
  send_play(game: third, character_id: third_character)
  let #(third_entry, third_have) =
    game_client.read_entry_kept(game: third, have: <<>>)
  let third_unit =
    game_client.unit_create_player_in(frames: third_entry).unit_id
  assert third_unit == 3 as "the third player is the third unit"
  let created = fn(frames, unit) {
    list.any(frames, fn(frame) {
      created_unit_of(frame:) |> result.map(fn(created) { created.0 })
      == Ok(unit)
    })
  }
  // The third's client has read the creates of the Esper and the Medic, so the Esper's and
  // the Medic's connections hold the third as a viewer.
  let #(_, third_have) =
    game_client.read_until(game: third, have: third_have, found: fn(frames) {
      created(list.append(third_entry, frames), esper)
      && created(list.append(third_entry, frames), medic)
    })
  walk_to(game: first, z: 33.5, clock: 1)
  walk_to(game: third, z: -1000.0, clock: 1)
  let #(_, third_have) =
    game_client.read_until(game: third, have: third_have, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), esper)
    })
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), third_unit)
    })
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: medic,
  )
  // The Esper's connection writes the start of the Interrupt Armor child (Spell4 76766) after
  // the tells of the go, so the Esper's read of it means the Medic's connection has the whole
  // go in its mailbox. The Medic's pong then means it has told the third player's connection,
  // and the third's pong that the third's client has been written what it told: a read bounded
  // by what the clients are sent, which fails by its assertions when the third is told nothing.
  let confirmed = fn(frames) {
    list.filter_map(game_client.casts_in(frames:), fn(event) {
      case event {
        game_client.CastConfirmed(server_cast_id:, ..) -> Ok(server_cast_id)
        _ -> Error(Nil)
      }
    })
  }
  let #(pressed, _) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(
        connection_support.decoded(
          frames,
          spell_started.message_id,
          spell_started.decode,
        ),
        fn(start) { start.spell4_id == 76_766 },
      )
    })
  let assert [pressed_id] = confirmed(pressed) as "the press is confirmed once"
  let #(_, second_have) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let #(third_read, third_have) =
    game_client.read_until_pong(game: third, have: third_have, number: 1)
  let pressed_start = fn(frames) {
    list.filter(
      connection_support.decoded(
        frames,
        spell_started.message_id,
        spell_started.decode,
      ),
      fn(start) { start.cast_id == pressed_id },
    )
  }
  let assert [started_cast] = pressed_start(third_read)
    as "the third's client is told the pressed cast once, by the Medic"
  assert started_cast.caster_unit_id == esper
    && started_cast.primary_target_unit_id == medic
    && started_cast.spell4_id == 32_823
    as "opcode.0x7ff: the start names the Esper as its caster and the Medic as its primary target"
  assert !created(third_read, esper)
    as "cast.unknown_caster: the Esper is not created again for the third client, which shows the buff for a caster it does not hold"
  let assert [go] =
    list.filter(gos_in(frames: third_read), fn(go) {
      go.cast_id == started_cast.cast_id
    })
    as "the third's client is told the cast's go once"
  let assert [target] = go.targets as "the go lists one target, the Medic"
  assert target.unit_id == medic as "and it is the Medic"
  let assert [effect] = target.effects
    as "the Medic holds the one effect Spell4Effects 62024 of tier 1"
  assert effect.spell4_effects_id == 62_024
    && effect.delay_ms == 0
    && effect.lifetime_ms > 0
    && effect.lifetime_ms <= 10_000
    as "opcode.0x7f4.effect_time: the absorb is listed with delay 0 and the time it has left, at most its 10 000 ms"
  let ordered =
    list.filter_map(third_read, fn(frame) {
      case frame.message_id {
        0x07FF -> {
          let assert Ok(start) = spell_started.decode(frame.body)
            as "a 0x7ff decodes"
          case start.cast_id == started_cast.cast_id {
            True -> Ok(0x07FF)
            False -> Error(Nil)
          }
        }
        0x07F4 -> {
          let assert Ok(went) = spell_go.decode(frame.body) as "a 0x7f4 decodes"
          case went.cast_id == started_cast.cast_id {
            True -> Ok(0x07F4)
            False -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })
  assert ordered == [0x07FF, 0x07F4]
    as "the start is written before the go, each once"
  // The node ends 10 000 ms after the go: the Esper's connection tells the Medic's the end and
  // the Medic's connection tells the third player's. The Medic's own client is written its
  // absorption's end in the step that tells the viewers, and the Medic's move after it is told
  // to the third by the one sender, so the third's read of the move bounds the 0x811.
  driven_time.advance(time:, ms: 10_000)
  let #(_, _) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      absorptions_in(frames:, unit: medic) == [0]
    })
  walk_to(game: second, z: 3.0, clock: 1)
  let #(until_end, _) =
    game_client.read_until(game: third, have: third_have, found: fn(frames) {
      list.any(game_client.fight_in(frames:), fn(event) {
        case event {
          game_client.Moves(unit_id:, ..) -> unit_id == medic
          _ -> False
        }
      })
    })
  assert list.count(
      game_client.targets_removed_in(frames: until_end),
      fn(removed) { removed == #(started_cast.cast_id, [medic]) },
    )
    == 1
    as "opcode.0x811: the third player's client reads one 0x811 naming the Medic for the cast, which ends the buff"
  assert !list.contains(
    finished_casts_in(frames: until_end),
    started_cast.cast_id,
  )
    as "opcode.0x7fe: and no 0x7fe of the cast, which would end its nodes on other units"
  game_client.close(game: first)
  game_client.close(game: second)
  game_client.close(game: third)
  login_support.stop(started)
}

/// What a Spellslinger's press of Runes of Protection, with a Medic standing `metres` metres
/// ahead of it, showed the two clients: each Medic's and the Spellslinger's unit, the absorb the
/// row 206315 gives, the frames each client read at the go (`caster_read`, `ally_read`) and
/// those it read when the absorb's 10 000 ms were over (`caster_ended`, `ally_ended`).
type RunesRound {
  RunesRound(
    caster: Int,
    ally: Int,
    amount: Int,
    caster_read: List(Frame),
    ally_read: List(Frame),
    caster_ended: List(Frame),
    ally_ended: List(Frame),
  )
}

/// The primary target of each 0x7ff of the child 78708 among `frames`, in the order read.
fn runes_child_targets(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(
    connection_support.decoded(
      frames,
      spell_started.message_id,
      spell_started.decode,
    ),
    fn(start) {
      case start.spell4_id == 78_708 {
        True -> Ok(start.primary_target_unit_id)
        False -> Error(Nil)
      }
    },
  )
}

/// A Spellslinger of level 6 presses Runes of Protection (Spell4 39092, Spell4Base 23441, a
/// Spellslinger's from level 6: SpellLevel 1144) with no target named, on the client's real
/// tables, facing -z, while a Medic of level 6 stands `metres` metres ahead of it. The Medic is
/// in the area when `ally_hears`: a beam 4.5 m wide and 34 m long ahead of the caster
/// (TelegraphDamage 2044, targetTypeFlags 1) within the area row's 35 m
/// (Spell4AoeTargetConstraints 454: Closest, 4 targets, 0 to 35 m, 360 degrees). The Proxy
/// 206357 starts the child 78708 on the caster and on each ally the area selects; the child holds the absorb 206315 (effectType 29, targetFlags 2, 10 000
/// ms, formula 0.848 of the Support Power and 45.23 a level, the stat part rounded alone,
/// `0x140565600`). The clock is the test's.
fn runes_pressed_with_an_ally(
  metres metres: Float,
  ally_hears ally_hears: Bool,
) -> RunesRound {
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter(started:, first_class: 7, level: 6)
  let caster = unit_of_player(frames: first_burst)
  let ally = unit_of(seen_second)
  let #(x, y, z) =
    game_client.placed_by_tail(
      tail: game_client.unit_create_player_in(frames: first_burst).tail,
    )
  game_client.face(game: first, yaw: 0.0, clock: 100)
  game_client.move_to(game: second, clock: 110, x:, y:, z: z -. metres)
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0638 })
    })
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 7,
      level: 6,
      ability: 23_441,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  // The caster's connection writes every start and the tells of the go in one input, so its
  // pong follows them all, and what it told the Medic's connection is held before that
  // connection's own pong (`game_client.read_until_pong`): both reads end at a pong, never at a
  // frame a Medic that was started no child would not send.
  let #(caster_read, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  let #(ally_read, second_have) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert list.contains(runes_child_targets(frames: ally_read), ally)
    == ally_hears
    as "opcode.0x7ff: the Medic's client reads the child cast with itself as its primary target exactly when it stands in the area"
  assert { absorptions_in(frames: ally_read, unit: ally) != [] } == ally_hears
    as "opcode.0x938: the Medic's client reads an absorb at the go exactly when it stands in the area"
  assert refusals(frames: caster_read) == []
    as "opcode.0x7fc: Runes of Protection is planned, so the press is not refused"
  let expected_starts = case ally_hears {
    True -> list.sort([caster, ally], int.compare)
    False -> [caster]
  }
  assert list.sort(runes_child_targets(frames: caster_read), int.compare)
    == expected_starts
    as "opcode.0x7ff: the caster's client reads the child 78708 cast on itself and on each Medic in the area of 35 m, the Medic its primary target"
  let assert Ok(power) = game_formula.get(tables:, id: GameFormulaId(1266))
    as "the client's tables hold GameFormula row 1266"
  let support_power =
    own_property_in(frames: first_burst, property_id: 36) *. power.datafloat01
  let amount =
    float.round(
      int.to_float(float.round(0.8479999899864197 *. support_power))
      +. 45.22999954223633
      *. 6.0,
    )
  driven_time.advance(time:, ms: 10_000)
  let #(caster_ended, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let #(ally_ended, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 2)
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
  RunesRound(
    caster:,
    ally:,
    amount:,
    caster_read:,
    ally_read:,
    caster_ended:,
    ally_ended:,
  )
}

/// A Spellslinger of level 6 presses Runes of Protection with no target named while a Medic
/// stands 10 m ahead, and again with a Medic 50 m ahead, outside the area of 35 m
/// (`runes_pressed_with_an_ally`): the area's Proxy starts the child 78708 on the caster and
/// on the Medic in it, the caster's client reads the child's 0x7ff naming that Medic as its
/// primary target, the Medic's client reads the absorb of the row 206315 and its end, and the
/// caster reads its own absorb. The Medic outside the area is started no child, so its client
/// reads no absorb and no 0x7ff, and the caster reads one child 0x7ff, its own. The caster's
/// frames and the Medic's come from two connections; the test reads the caster's up to its pong
/// and then the Medic's up to its pong, which relies on one contract of
/// `game_client.read_until_pong`: what the caster's connection told the Medic's before the
/// caster's pong is held before the Medic's pong. It holds here because the round closes at
/// once, the children start inline, the tell to the Medic is sent in the press input, and the
/// 10 000 ms end goes through `driven_time.advance`, whose barrier runs after each timer.
pub fn a_spellslinger_pressing_runes_of_protection_gives_the_ally_in_range_the_absorb_and_the_caster_reads_the_child_cast_on_the_ally_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let near = runes_pressed_with_an_ally(metres: 10.0, ally_hears: True)
  assert absorptions_in(frames: near.caster_read, unit: near.caster)
    == [near.amount]
    as "opcode.0x938: the caster reads its own absorb, the pool the row's formula gives (0.848 of the Support Power and 45.23 a level)"
  assert absorptions_in(frames: near.ally_read, unit: near.ally)
    == [near.amount]
    as "opcode.0x938: the Medic in the area reads the absorb of the row 206315"
  assert absorptions_in(frames: near.ally_ended, unit: near.ally) == [0]
    as "opcode.0x938: the Medic's absorb ends with the child's node, 10 000 ms on"
  assert absorptions_in(frames: near.caster_ended, unit: near.caster) == [0]
    as "and so does the caster's own"
  let far = runes_pressed_with_an_ally(metres: 50.0, ally_hears: False)
  assert runes_child_targets(frames: far.caster_read) == [far.caster]
    as "opcode.0x7ff: the Medic 50 m ahead, outside the area of 35 m, is started no child: the caster reads the one cast on itself"
  assert absorptions_in(frames: far.caster_read, unit: far.caster)
    == [far.amount]
    as "the caster reads its own absorb"
  assert absorptions_in(frames: far.ally_ended, unit: far.ally) == []
    && runes_child_targets(frames: far.ally_ended) == []
    as "the Medic outside the area reads no absorb and no child"
}

/// What a Medic's press of Barrier, with another Medic standing `metres` metres ahead of it
/// (behind it when negative), showed the two clients: each Medic's unit and the frames each
/// client read at the go (`caster_read`, `ally_read`) and when the property's 5000 ms were over
/// (`ally_ended`).
type BarrierRound {
  BarrierRound(
    caster: Int,
    ally: Int,
    caster_read: List(Frame),
    ally_read: List(Frame),
    ally_ended: List(Frame),
  )
}

/// The primary target of each 0x7ff of the spell `spell4_id` among `frames`, in the order read.
fn started_targets_of(
  frames frames: List(Frame),
  spell4_id spell4_id: Int,
) -> List(Int) {
  list.filter_map(
    connection_support.decoded(
      frames,
      spell_started.message_id,
      spell_started.decode,
    ),
    fn(start) {
      case start.spell4_id == spell4_id {
        True -> Ok(start.primary_target_unit_id)
        False -> Error(Nil)
      }
    },
  )
}

/// A Medic of level 14 presses Barrier (Spell4 78081, Spell4Base 53946: castTime 0, no target
/// named) on the client's real tables, facing -z, while a Medic of level 14 stands `metres` metres
/// ahead of it. The area 737 (one ally, 180 degrees ahead, 30 m, ordered by missing health, the
/// caster never a candidate) finds the Medic ahead; the Proxy 204583 starts the child 41369 on it,
/// whose area 429 (3 targets, ordered by missing health, a circle of 8 m on the ally) selects the
/// ally itself, and whose row 92788 (property 175, 5000 ms, targetFlags 5) is the caster's own
/// change and each ally's. The clock is the test's.
fn barrier_pressed_with_an_ally(metres metres: Float) -> BarrierRound {
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_on(tables:, time:)
  let TwoEntered(
    first:,
    second:,
    first_burst:,
    seen_second:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter(started:, first_class: 4, level: 14)
  let caster = unit_of_player(frames: first_burst)
  let ally = unit_of(seen_second)
  let #(x, y, z) =
    game_client.placed_by_tail(
      tail: game_client.unit_create_player_in(frames: first_burst).tail,
    )
  game_client.face(game: first, yaw: 0.0, clock: 100)
  game_client.move_to(game: second, clock: 110, x:, y:, z: z -. metres)
  let #(_, first_have) =
    game_client.read_until(game: first, have: first_have, found: fn(frames) {
      list.any(frames, fn(frame) { frame.message_id == 0x0638 })
    })
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 4,
      level: 14,
      ability: 53_946,
    )
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index:,
    target: 0,
  )
  // As the Runes of Protection test reads: the caster's connection writes every start and the
  // tells of the go in one input, so its pong follows them all, and what it told the ally's
  // connection is held before that connection's own pong.
  let #(caster_read, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  let #(ally_read, second_have) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  assert refusals(frames: caster_read) == []
    as "opcode.0x7fc: Barrier is planned, so the press is not refused"
  driven_time.advance(time:, ms: 5000)
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let #(ally_ended, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 2)
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
  BarrierRound(caster:, ally:, caster_read:, ally_read:, ally_ended:)
}

/// A Medic of level 14 presses Barrier with no target named while a Medic of level 14 stands
/// 10 m ahead, and again with one 10 m behind (`barrier_pressed_with_an_ally`). The area 737
/// finds the Medic ahead, whose connection the caster's tells the property 175 change of the row
/// 92788 (text 640545: "sets Shield Mitigation ... to yourself and N allies in the targeted
/// area for 5s"): its client reads the 0x7ff of the child 41369 naming it, the change in a
/// 0x93a of its own unit and, 5000 ms on, the property given back. The Medic behind is outside
/// the 180 degrees of 737, which finds nobody, so no child starts and neither client reads a
/// change: the caster's own is the child's row too. The caster's frames and the ally's come from two
/// connections, read as the Runes of Protection test reads them.
pub fn a_medic_pressing_barrier_gives_the_ally_in_front_shield_mitigation_for_five_seconds_and_the_ally_behind_none_on_the_whole_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let near = barrier_pressed_with_an_ally(metres: 10.0)
  assert started_targets_of(frames: near.ally_read, spell4_id: 41_369)
    == [near.ally]
    as "opcode.0x7ff: the Medic ahead reads the child 41369 cast with itself as its primary target"
  let given =
    property_entries_of(
      frames: near.ally_read,
      unit_id: near.ally,
      property_id: 175,
    )
  assert list.any(given, fn(entry) { entry.value != entry.base })
    as "opcode.0x93a: the Medic ahead is given a changed property 175, the row 92788's"
  assert list.any(
    property_entries_of(
      frames: near.caster_read,
      unit_id: near.caster,
      property_id: 175,
    ),
    fn(entry) { entry.value != entry.base },
  )
    as "opcode.0x93a: the caster is given its own change of property 175"
  assert list.last(property_entries_of(
      frames: near.ally_ended,
      unit_id: near.ally,
      property_id: 175,
    ))
    |> result.map(fn(entry) { entry.value == entry.base })
    == Ok(True)
    as "opcode.0x93a: 5000 ms on, the Medic ahead is given property 175 back"
  let behind = barrier_pressed_with_an_ally(metres: -10.0)
  assert started_targets_of(frames: behind.ally_read, spell4_id: 41_369) == []
    as "the Medic behind is outside the 180 degrees of the area 737, which finds nobody: no child is cast on it"
  assert property_entries_of(
      frames: behind.ally_read,
      unit_id: behind.ally,
      property_id: 175,
    )
    == []
    as "opcode.0x93a: and its client reads no change of property 175"
  assert property_entries_of(
      frames: behind.caster_read,
      unit_id: behind.caster,
      property_id: 175,
    )
    == []
    as "opcode.0x93a: and so does the caster's: its own change is the child's row 92788, whose Proxy 204583 (targetFlags 4) starts the child on each ally the area found and on the caster never"
}
