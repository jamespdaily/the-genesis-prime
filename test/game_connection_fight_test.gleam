//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover a creature's
//// news, a viewer's casts, the caster's strike and a creature's fight, with
//// both rules.

import cast_support
import connection_rule_support as support
import creature_path_support as path_support
import fixture_tables
import game_client
import game_connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, type News, type Request, Appeared, AskHandOff,
  AskMap, AskMapRun, AskSessions, AskStore, CastFinished, CastStarted, CastWent,
  ForStay, FromMap, Removed, SentBySessions, TellChat, TellMoved, TellPeer,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_state
import genesis_prime/message/cast_result
import genesis_prime/message/float32
import genesis_prime/message/movement_face_unit.{MovementFaceUnit}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_kind_10.{MovementKind10}
import genesis_prime/message/movement_kind_13.{MovementKind13}
import genesis_prime/message/movement_kind_21.{MovementKind21}
import genesis_prime/message/movement_kind_26.{MovementKind26}
import genesis_prime/message/movement_move_asked
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags
import genesis_prime/message/movement_time
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/relayed_movement
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_position
import genesis_prime/message/unit_combat_state.{UnitCombatState}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_death_state.{UnitDeathState}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_stat_change
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/message/unit_stat_shield.{UnitStatShield}
import genesis_prime/message/unit_target.{UnitTarget}
import genesis_prime/message/unit_threat.{UnitThreat}
import genesis_prime/server
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, ConnectionId, Map,
  OwnEffect, OwnEvent, TimerId, Unwatch, Watch, Woken,
}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, Spell4BaseId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_kind.{Kind}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_turn
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map.{Left}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import genesis_prime/world_map/spawn_source
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import place_support
import planted_table
import spawn_support
import spell_tables

fn spell_go_of(cast_id cast_id: Int) -> spell_go.SpellGo {
  spell_go.SpellGo(
    cast_id:,
    ignore_cooldown: 0,
    destination: spell_position.SpellPosition(x: 0, y: 0, z: 0),
    targets: [],
    initial_positions: [],
    telegraph_positions: [],
    missiles: [],
    phase: 0,
  )
}

pub fn a_viewer_writes_a_cast_start_only_for_a_caster_its_client_shows_and_a_go_or_finish_only_for_a_start_it_wrote_test() -> Nil {
  use <- owned_test.run(10_000)
  let start =
    game_connection_support.spell_started_of(cast_id: 2_147_497_985, caster: 9)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastStarted(start:),
      )),
    )
  assert support.writes(taken) == []
    as "unit 9 is not shown, so its client could not take the cast bar (opcode.0x7ff)"
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: Appeared(game_connection_support.another_unit()),
      )),
    )
  let go =
    game_connection_support.news_of(
      unit_id: 9,
      news: CastWent(go: spell_go_of(cast_id: start.cast_id)),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(go),
    )
  assert game_connection_support.written_ids(taken) == []
    as "a go for a start the viewer did not write is dropped (0x140561c30: the client drops a go with an unknown cast id)"
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastStarted(start:),
      )),
    )
  assert game_connection_support.written_ids(taken) == [0x07FF]
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(go),
    )
  assert game_connection_support.written_ids(taken) == [0x07F4]
  let finish =
    game_connection_support.news_of(
      unit_id: 9,
      news: CastFinished(cast_id: start.cast_id),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(finish),
    )
  assert game_connection_support.written_ids(taken) == [0x07FE]
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(go),
    )
  assert game_connection_support.written_ids(taken) == []
    as "the finish ends the cast for the viewer: a later go is dropped"
}

pub fn a_viewer_writes_the_finish_of_each_cast_of_a_unit_before_the_unit_is_removed_and_none_after_test() -> Nil {
  use <- owned_test.run(10_000)
  let first =
    game_connection_support.spell_started_of(cast_id: 2_147_497_985, caster: 9)
  let second =
    game_connection_support.spell_started_of(cast_id: 2_147_497_986, caster: 9)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: Appeared(game_connection_support.another_unit()),
      )),
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastStarted(start: second),
      )),
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastStarted(start: first),
      )),
    )
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: Removed,
      )),
    )
  let finishes =
    cast_support.finished_ids(game_connection_support.heard(
      taken,
      game_connection_support.keyed(),
    ))
  assert game_connection_support.written_ids(taken) == [0x07FE, 0x07FE, 0x0355]
    as "the client keeps a cast that never gets its 0x7fe live (cast.no_answer), and a cast id used again restarts it (opcode.0x7ff), so each cast is finished before the unit goes"
  assert finishes == [2_147_497_985, 2_147_497_986] as "in cast id order"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 9,
        news: CastFinished(cast_id: first.cast_id),
      )),
    )
  assert game_connection_support.written_ids(taken) == []
    as "the viewer keeps no id of the removed unit's casts"
}

pub fn a_0x9a_in_the_world_is_taken_by_the_cast_rule_and_a_bag_index_not_held_is_answered_0x7fc_4_test() -> Nil {
  use <- owned_test.run(10_000)
  let press =
    cast_support.press_body(
      client_cast_id: 9,
      bag_index: 99,
      target: 0,
      press: 1,
    )
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.world_message(0x009A, press),
    )
  let assert [Frame(message_id: 0x07FC, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x7fc: the refusal of a press"
  assert spell_cast_refused.decode(body)
    == Ok(spell_cast_refused.SpellCastRefused(
      client_cast_id: 9,
      spell4_id: 0,
      result: cast_result.SpellUnknown,
    ))
    as "0x14039a040: 4 for a bag index the player does not hold"
  assert support.unhandled_ids(taken) == []
}

pub fn a_0x801_for_a_cast_that_is_not_live_changes_nothing_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let cancel =
    cast_support.cancel_body(
      cast_id: 2_147_497_985,
      reason: cast_result.SpellCancelled,
      bit: 1,
    )
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.world_message(0x0801, cancel),
    )
  assert game_connection_support.written_ids(taken) == []
    && support.unhandled_ids(taken) == []
    as "opcode.0x801: an unknown or finished id is nothing, not an unhandled message"
}

pub fn a_0x9a_outside_the_world_is_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(10_000)
  let press =
    cast_support.press_body(
      client_cast_id: 9,
      bag_index: 0,
      target: 0,
      press: 1,
    )
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      game_connection_support.world_message(0x009A, press),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x009A))]
    as "the cast rows are taken with the player in the world only (genesis_prime/game/routing)"
}

// ------------------------------------------- a creature's news and the caster's strike

/// A creature's news that is not its first.
fn beast_news(
  unit_id unit_id: Int,
  news news: News,
) -> Event(ConnectionEvent(Message, Answer)) {
  game_connection_support.sent_by_a_peer(game_connection_support.news_of(
    unit_id:,
    news:,
  ))
}

/// The Beast units a press strikes, a round after the one before, and the
/// round closed with each one's answer.
fn press_and_close(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
) -> #(game_connection.State, List(Int)) {
  let ms = client_cast_id * paralytic_surge_round_ms
  let #(state, taken) =
    game_connection_support.press_paralytic_surge_at(
      state:,
      client_cast_id:,
      ms:,
    )
  let told = game_connection_support.strikes_told(taken)
  let state =
    list.fold(told, state, fn(state, strike) {
      game_connection_support.at(
        state:,
        ms:,
        event: game_connection_support.landed(key: strike.1),
      ).0
    })
  #(state, list.map(told, fn(strike) { strike.0 }))
}

/// The removals a step tells creatures, as the creature's unit, its life and the request.
fn despawns_told(
  taken: ConnectionStep(Request),
) -> List(#(Int, Int, client_connection.Request)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(
        to: step.Creature(unit_id:, life:, ..),
        request: client_connection.TellDespawn(..) as request,
      )) -> Ok(#(unit_id, life, request))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// Paralytic Surge pressed at 1000 ms on the Beast the client shows, its round answered
/// landed at 1100 ms: the steps the answers take, on the tables with Spell4Effects 99097
/// added as a copy of Surge's CCStateSet row 96126 (targetFlags 4, delay 0, phaseFlags -1,
/// no data) with these columns.
fn surge_with_a_despawn_row(
  columns columns: List(#(String, planted_table.Cell)),
) -> List(ConnectionStep(Request)) {
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 96_126,
    id: 99_097,
    with: [#("effectType", planted_table.Integer(97)), ..columns],
    body: fn(tables) {
      let #(state, _) =
        game_connection_support.feed(
          game_connection_support.medic_in(tables),
          game_connection_support.beast_appears(unit_id: 40),
        )
      let #(state, pressed) =
        game_connection_support.press_paralytic_surge_at(
          state:,
          client_cast_id: 1,
          ms: 1000,
        )
      let #(_, answered) =
        list.fold(
          game_connection_support.strikes_told(pressed),
          #(state, []),
          fn(so_far, strike) {
            let #(state, steps) = so_far
            let #(state, taken) =
              game_connection_support.at(
                state:,
                ms: 1100,
                event: game_connection_support.landed(key: strike.1),
              )
            #(state, list.append(steps, [taken]))
          },
        )
      [pressed, ..answered]
    },
  )
}

pub fn a_creature_despawns_effect_becomes_a_tell_to_that_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects 99097 is a type 97 row aimed at the area (targetFlags 4) with a delay of
  // 3000 ms; Paralytic Surge's area holds the Beast, unit 40, which the client shows in
  // life 4 (`beast_appears`: its 0x262 news). The round opens at the press, 1000 ms, and
  // the go comes at the answer, 1100 ms.
  let steps =
    surge_with_a_despawn_row(columns: [
      #("delayTime", planted_table.Integer(3000)),
    ])
  assert list.flat_map(steps, despawns_told)
    == [
      #(
        40,
        4,
        client_connection.TellDespawn(
          delay_ms: 3000,
          struck_at_ms: 1000,
          went_at_ms: 1100,
        ),
      ),
    ]
    as "the connection tells the creature of that life, with the row's delay, the round's time and the go's time, and tells no other"
}

pub fn a_despawn_aimed_at_the_caster_never_removes_the_players_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  // The row aims at the caster alone (targetFlags 1): a creature caster could be removed by
  // it and a player never is, so the plan leaves it out and the cast goes on as before
  // (`Spell4Effects.effectType.97`, `opcode.0x355`: removing the player's own unit would
  // lose the world).
  let steps =
    surge_with_a_despawn_row(columns: [
      #("targetFlags", planted_table.Integer(1)),
    ])
  assert list.flat_map(steps, despawns_told) == []
    as "no creature is told to leave"
  assert list.all(steps, fn(taken) {
    !list.contains(game_connection_support.written_ids(taken), 0x0355)
  })
    as "and the client is sent no 0x355 for the caster's unit, or any"
  assert list.any(steps, fn(taken) {
    list.contains(game_connection_support.written_ids(taken), 0x07F4)
  })
    as "the cast still goes"
}

pub fn the_clients_picture_of_a_creature_follows_its_news_and_only_a_creature_it_shows_alive_is_struck_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, struck) = press_and_close(state:, client_cast_id: 1)
  assert struck == [40]
    as "Paralytic Surge's area (row 173: 15 m, 180 degrees) holds the Beast 3 m ahead that the client shows"
  let #(state, taken) =
    game_connection_support.feed(state, beast_news(unit_id: 40, news: Removed))
  assert game_connection_support.written_ids(taken) == [0x0355]
  let #(state, struck) = press_and_close(state:, client_cast_id: 2)
  assert struck == []
    as "the 0x355 cleared the creature's entry: nothing is shown to strike"
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, struck) = press_and_close(state:, client_cast_id: 3)
  assert struck == [40] as "the respawn's 0x262 restores the entry, alive"
  let #(state, taken) =
    game_connection_support.feed(
      state,
      beast_news(unit_id: 40, news: client_connection.Died),
    )
  assert game_connection_support.written_ids(taken) == [0x088C]
  let #(_, struck) = press_and_close(state:, client_cast_id: 4)
  assert struck == []
    as "a 0x88c marks the creature dead in the picture: a dead creature is never selected (Spell4ValidTargets.targetBitmask)"
}

pub fn an_area_press_strikes_a_shown_creature_that_fights_and_passes_over_one_that_never_fights_test() -> Nil {
  use <- owned_test.run(10_000)
  // The same Beast 3 m ahead, shown as unit 40 that fights and unit 41 that does not
  // (`creature_life.Combat.fights`, False for a creature drawn lying dead): Paralytic Surge's
  // area holds both, and only the first is struck, damaged, killed and credited.
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.beast_appears_not_fighting(unit_id: 41),
    )
  let #(_, struck) = press_and_close(state:, client_cast_id: 1)
  assert struck == [40]
    as "the creature that never fights is no candidate of the area"
}

pub fn a_creatures_health_or_death_is_not_written_for_a_unit_the_client_does_not_show_test() -> Nil {
  use <- owned_test.run(10_000)
  let state = game_connection_support.medic_in_world()
  let #(state, taken) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 41,
        news: client_connection.Health(health: 5, dead: False),
      ),
    )
  assert game_connection_support.written_ids(taken) == []
    as "opcode.0x937: the client has no unit 41, so it is not sent a health for it"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      beast_news(unit_id: 41, news: client_connection.Died),
    )
  assert game_connection_support.written_ids(taken) == []
    as "opcode.0x88c: nor a death"
}

pub fn the_news_held_for_a_creature_that_is_removed_and_stands_again_before_the_round_closes_is_not_written_onto_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, taken) =
    game_connection_support.press_paralytic_surge(state:, client_cast_id: 1)
  let assert [#(40, key)] = game_connection_support.strikes_told(taken)
    as "the press strikes the Beast and its round is open"
  let #(state, taken) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: client_connection.Health(health: 0, dead: True),
      ),
    )
  assert game_connection_support.written_ids(taken) == []
    as "the health of a unit of an open round waits for the round's go"
  let #(state, taken) =
    game_connection_support.feed(state, beast_news(unit_id: 40, news: Removed))
  assert game_connection_support.written_ids(taken) == [0x0355]
  let #(state, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.beast_appears(unit_id: 40),
    )
  assert game_connection_support.written_ids(taken) == [0x0262]
  let #(_, taken) =
    game_connection_support.feed(state, game_connection_support.landed(key:))
  let ids = game_connection_support.written_ids(taken)
  assert list.contains(ids, 0x07F4)
    && !list.contains(ids, 0x0937)
    && !list.contains(ids, 0x088C)
    as "the round closes with its go, and the death meant for the unit that was removed is not written onto the one that stands again under its id (opcode.0x355)"
}

// ------------------------------------------- a creature's fight, the player's side
//
// Expected values come from the design of step F (the Design artifact of issue
// 367, section 1, and its shape review): the connection tells its map Ready at
// the stay's first 0xF2 (`opcode.0xf2`); each accepted 0x637 gets the
// connection's next move sequence number, which counts for the connection's life;
// a creature's Threatened sets the combat flag and starts the stream of the
// player's place to it, its Released or the map's Gone clears it with the last
// fighter (`opcode.0x89a`: no client timer); a creature's strike is the hit rule
// on the player's health and shield, written as 0x938 of stat 20 and 0x92f to the
// player and 0x938 and 0x937 to its viewers (`opcode.0x92f`, `opcode.0x938`), and
// answered to the creature; a viewer writes a creature's 0x908, 0x90a, 0x89a and
// 0x638 [kind 0, kind 4] (`opcode.0x908`, `opcode.0x90a`, `movement_command.kind_4`),
// and its picture finds a running creature where its path puts it.

pub fn the_stays_first_0xf2_tells_the_map_the_player_is_ready_and_a_second_does_not_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.told_the_map(first)
    == [
      OwnEffect(step.Tell(
        to: Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
        request: client_connection.TellReady(
          connection: ConnectionId(1),
          seq: 0,
        ),
      )),
    ]
    as "opcode.0xf2: the client's terrain is loaded; a creature may fight the player from now on"
  let #(_, second) =
    game_connection_support.read(
      state,
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.told_the_map(second) == []
    as "Ready once a stay"
}

pub fn two_accepted_0x637s_of_one_client_clock_get_two_sequence_numbers_in_order_test() -> Nil {
  use <- owned_test.run(10_000)
  // `moves_message` writes the client clock 0x1234 into every 0x637: two moves of one
  // frame share it (`opcode.0x637.client_clock`).
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.a_move(1.5),
    )
  let #(_, second) =
    game_connection_support.read(state, game_connection_support.a_move(2.5))
  assert game_connection_support.moves_told(first) == [1]
    && game_connection_support.moves_told(second) == [2]
    as "the connection orders its moves itself, not by the client's clock"
}

pub fn the_move_sequence_number_counts_through_a_camp_and_the_next_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.a_move(1.5),
    )
  assert game_connection_support.moves_told(first) == [1]
  let #(state, second) =
    game_connection_support.read(state, game_connection_support.a_move(2.5))
  assert game_connection_support.moves_told(second) == [2]
  let camped = game_connection_support.camp_from(state)
  let #(again, _) =
    game_connection_support.entered_from(
      camped,
      game_connection_support.world_character(),
    )
  let #(_, after) =
    game_connection_support.read(again, game_connection_support.a_move(3.5))
  assert game_connection_support.moves_told(after) == [3]
    as "a move of the new stay is newer than every move of the old one, so a creature never takes an old in-flight move of the first stay for a newer one"
}

pub fn a_creatures_threat_sets_the_combat_flag_and_streams_the_place_now_and_each_move_to_it_until_its_release_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [5])
  let #(state, moved) =
    game_connection_support.read(state, game_connection_support.a_move(1.5))
  assert game_connection_support.told_creatures(moved) == []
    as "no fighter: no stream"
  let #(state, threatened) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  assert combat_states(threatened) == [#(5, 1)]
    as "0x89a (P, 1) to the player's own client: its unit 5, in combat"
  assert list.map(game_connection_support.peer_tells(threatened), fn(tell) {
      #(tell.0, { tell.1 }.news)
    })
    == [#(5, client_connection.CombatState(in_combat: True))]
    as "and to its viewers"
  assert game_connection_support.told_creatures(threatened)
    == [
      #(
        7,
        client_connection.TellTargetMoved(
          connection: ConnectionId(1),
          place: game_connection_support.standing_at(x: 1.5, y: 2.5, z: 3.5),
          seq: 1,
          stay: game_connection_support.own_stay(),
          hit_radius: place_support.player_hit_radius,
        ),
      ),
    ]
    as "the place now, with the sequence number of the move that put it there"
  let #(state, next) =
    game_connection_support.read(state, game_connection_support.a_move(2.5))
  assert game_connection_support.told_creatures(next)
    == [
      #(
        7,
        client_connection.TellTargetMoved(
          connection: ConnectionId(1),
          place: game_connection_support.standing_at(x: 2.5, y: 2.5, z: 3.5),
          seq: 2,
          stay: game_connection_support.own_stay(),
          hit_radius: place_support.player_hit_radius,
        ),
      ),
    ]
    as "each accepted 0x637 goes to the fighter"
  let #(state, released) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Released(unit_id: 7)),
    )
  assert combat_states(released) == [#(5, 0)]
    as "0x89a (P, 0): the last fighter released it"
  let #(_, after) =
    game_connection_support.read(state, game_connection_support.a_move(3.5))
  assert game_connection_support.told_creatures(after) == []
    as "nothing after the release"
}

pub fn the_map_reporting_a_fighter_gone_clears_the_combat_flag_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(_, gone) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(map.Gone(unit_id: 7)),
    )
  assert combat_states(gone) == [#(5, 0)]
    as "the creature crashed mid-fight: its Gone is its release, and 0x89a (P, 0) follows with no fighter left"
}

/// The 0x89a the step writes, as the unit and its in-combat bit.
fn combat_states(taken: ConnectionStep(Request)) -> List(#(Int, Int)) {
  list.map(
    game_connection_support.heard(taken, game_connection_support.keyed()),
    fn(frame) {
      let assert Frame(message_id: 0x089A, body:) = frame
        as "only 0x89a written"
      let assert Ok(state) = unit_combat_state.decode(body) as "0x89a decodes"
      #(state.unit_id, state.in_combat)
    },
  )
}

pub fn a_stay_entered_again_before_any_move_tells_the_map_ready_with_the_connections_sequence_number_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.a_move(1.5),
    )
  let #(state, _) =
    game_connection_support.read(state, game_connection_support.a_move(2.5))
  let #(again, _) =
    game_connection_support.entered_from(
      game_connection_support.camp_from(state),
      game_connection_support.world_character(),
    )
  let #(_, ready) =
    game_connection_support.read(
      again,
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.told_the_map(ready)
    == [
      OwnEffect(step.Tell(
        to: Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
        request: client_connection.TellReady(
          connection: ConnectionId(1),
          seq: 2,
        ),
      )),
    ]
    as "no move yet in this stay: Ready carries move 2, the connection's last, so a creature holding move 2 of the earlier stay takes this one"
}

pub fn a_creatures_strike_writes_the_shield_and_the_health_and_is_answered_to_the_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  // The tests' character is an Engineer (class 2) of level 1: Armor 250, the 0.75
  // cap of mitigation, and a shield of 450 taking up to 0.625 of a blow
  // (`player.level1_defence`, `player.level1_gear_properties`). The Beast's 12 is
  // mitigated to 3; the shield takes round(1.875) = 2, the health 1 of 736.
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [5])
  let key =
    strike_tell.Key(
      cast_id: 2_147_500_000,
      occasion: strike_tell.AtGo(phase: 0),
      unit_id: 5,
    )
  let #(_, struck) =
    game_connection_support.feed(
      state,
      game_connection_support.a_beast_strike(5),
    )
  let assert [
    Frame(message_id: 0x0938, body: shield),
    Frame(message_id: 0x092F, body: health),
  ] = game_connection_support.heard(struck, game_connection_support.keyed())
    as "0x938, then 0x92f, to the player's own client"
  assert unit_stat_changed.decode(shield)
    == Ok(UnitStatChanged(
      unit_id: 5,
      change: unit_stat_change.Shield(UnitStatShield(value: 448)),
    ))
    as "stat 20, the shield: 450 less 2"
  assert player_health.decode(health)
    == Ok(PlayerHealth(unit_id: 5, health: 735, reason_mask: 0))
    as "the player's own health: 736 less 1, with no fall or breath bit"
  assert list.map(game_connection_support.peer_tells(struck), fn(tell) {
      { tell.1 }.news
    })
    == [
      client_connection.Shield(shield: 448),
      client_connection.Health(health: 735, dead: False),
    ]
    as "its viewers are sent the shield and the health"
  let assert [
    #(
      7,
      client_connection.TellStrikeAnswered(answered: strike_tell.Answered(
        key: answered,
        outcome: strike_tell.Landed(descriptions: [_], ..),
      )),
    ),
  ] = game_connection_support.told_creatures(struck)
  assert answered == key as "the answer names the creature's strike"
}

pub fn a_viewer_writes_a_running_creatures_0x638_as_kind_0_then_kind_4_at_its_speed_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let from =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    )
  let to =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 26.0,
      y: 0.0,
      z: 0.0,
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: client_connection.CreatureMoved(path: creature_path.Running(
          from:,
          via: [],
          to:,
          started_ms: support.now_ms,
          speed: 10.0,
        )),
      ),
    )
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(UnitMovement(unit_id: 40, commands:, ..)) =
    unit_movement.decode(body)
  let assert [
    relayed_movement.Time(movement_time.MovementTime(..)),
    relayed_movement.Path(path),
    ..defaults
  ] = commands
    as "kind 0, the time the path starts at, kind 4, the path, then the defaults"
  assert defaults == path_defaults()
    as "kinds 10, 13, 21 and 26 with bit 1: the client takes the velocity, move, facing and state from the path (`movement_command.defaults_with_kind_4_path`)"
  assert path.speed == 0x4900 && path.path_type == 0 && path.mode == 0
    as "straight lines, mode 0, at 10.0 as a half float (sign 0, exponent 18, fraction 256)"
  assert path.points
    == [
      MovementFloatVector(x: 0, y: 0, z: 0),
      MovementFloatVector(x: float32.to_bits(26.0), y: 0, z: 0),
    ]
    as "the two points of the path, as 32-bit floats: 0, 0, 0 and 26, 0, 0"
  let assert [relayed_movement.Time(movement_time.MovementTime(time:)), ..] =
    commands
  assert time == support.now_ms
    as "kind 0's time is the map's time the path starts at: its monotonic start, 1000, less the origin the tests' map took, 0 (map.server_time)"
}

/// Kinds 10, 13, 21 and 26, each with its blend bit 1: what a creature's run sends after its
/// path, for the client to take the velocity, requested move, facing and state from the path
/// (`movement_command.defaults_with_kind_4_path`, `movement_command.kind_13`,
/// `movement_command.kind_21`).
fn path_defaults() -> List(relayed_movement.RelayedMovement) {
  [
    relayed_movement.VelocityDefault(MovementKind10(blends: 1)),
    relayed_movement.MoveDefault(MovementKind13(blends: 1)),
    relayed_movement.RotationDefault(MovementKind21(blends: 1)),
    relayed_movement.StateDefault(MovementKind26(blends: 1)),
  ]
}

/// A staircase of 28 points two units apart: point 0 is the origin, and each leg goes 2 along
/// +x when its index is even and 2 along +z when it is odd, so the creature bends every 2 units.
fn staircase() -> List(#(Float, Float, Float)) {
  let #(points, _) =
    list.fold(list.repeat(Nil, 27), #([#(0.0, 0.0, 0.0)], 0), fn(state, _) {
      let #(points, leg) = state
      let assert [#(x, y, z), ..] = points
        as "the staircase starts at the origin"
      let next = case leg % 2 == 0 {
        True -> #(x +. 2.0, y, z)
        False -> #(x, y, z +. 2.0)
      }
      #([next, ..points], leg + 1)
    })
  list.reverse(points)
}

/// The 32-bit float bits of each coordinate of the points.
fn bits(points: List(#(Float, Float, Float))) -> List(#(Int, Int, Int)) {
  list.map(points, fn(point) {
    #(
      float32.to_bits(point.0),
      float32.to_bits(point.1),
      float32.to_bits(point.2),
    )
  })
}

/// What a viewer writes of a creature's run news: kind 0's time, kind 4's points as
/// float bits, the speed's half float, type and mode, the commands after the path,
/// and the frame's size in bytes.
fn drawn_run(
  news news: client_connection.News,
) -> #(
  Int,
  List(#(Int, Int, Int)),
  #(Int, Int, Int),
  List(relayed_movement.RelayedMovement),
  Int,
) {
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(_, taken) =
    game_connection_support.feed(state, beast_news(unit_id: 40, news:))
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(UnitMovement(unit_id: 40, commands:, ..)) =
    unit_movement.decode(body)
  let assert [
    relayed_movement.Time(movement_time.MovementTime(time:)),
    relayed_movement.Path(path),
    ..defaults
  ] = commands
    as "kind 0, kind 4, then the defaults that animate it"
  #(
    time,
    list.map(path.points, fn(point) { #(point.x, point.y, point.z) }),
    #(path.speed, path.path_type, path.mode),
    defaults,
    bit_array.byte_size(body),
  )
}

pub fn a_creature_that_runs_28_points_is_drawn_along_all_of_them_and_a_late_viewer_gets_the_rest_test() -> Nil {
  use <- owned_test.run(10_000)
  // Expected values come from the client's reading of a kind 4 path: its points in order,
  // the command's own half-float speed (7.5 is 0x4780), type 0 and mode 0, at constant speed over
  // the whole polyline (`movement_command.kind_4`, `0x1407813d0`), and the four defaults, which
  // follow each leg of the bent path by themselves (`movement_command.defaults_with_kind_4_path`).
  let path =
    path_support.running(
      points: staircase(),
      started_ms: support.now_ms,
      speed: 7.5,
    )
  let #(time, points, shape, defaults, size) =
    drawn_run(news: client_connection.CreatureMoved(path:))
  assert time == support.now_ms
    as "kind 0's time is the monotonic start less the origin the tests' map took, 0"
  assert points == bits(staircase()) as "kind 4 holds all 28 points, in order"
  assert shape == #(0x4780, 0, 0)
    as "at 7.5 as a half float, straight lines, mode 0"
  assert defaults == path_defaults()
    as "kinds 10, 13, 21 and 26 with bit 1, and no kind 11 or kind 24"
  assert size < 500
    as "28 points make a frame of under half a kilobyte: 28 x 12 bytes of points and a short fixed part"
  // Three seconds later the creature has run 22.5 units: 11 legs of 2, and 0.5 into the 12th,
  // which goes along +z from (12, 0, 10) to (12, 0, 12), so a viewer that arrives then is
  // drawn the run from (12, 0, 10.5) through the 16 points still ahead.
  let later = support.now_ms + 3000
  let #(time, points, shape, defaults, _) =
    drawn_run(
      news: client_connection.CreatureMoved(path: creature_path.rest_of(
        path:,
        now_ms: later,
      )),
    )
  assert time == later as "the late viewer's run starts when it arrives"
  assert points == bits([#(12.0, 0.0, 10.5), ..list.drop(staircase(), 12)])
    as "it starts at the creature's place and holds the points ahead of it, 17 in all"
  assert shape == #(0x4780, 0, 0)
  assert defaults == path_defaults()
    as "the late viewer's run takes the same four defaults: the second leg's direction is the client's to find"
}

/// The commands after the kind 4 path of the 0x638 a viewer writes for `news` once it has
/// taken each of `earlier` for the Beast (unit 40), in order.
fn run_tail_after(
  earlier earlier: List(client_connection.News),
  news news: client_connection.News,
) -> List(relayed_movement.RelayedMovement) {
  let state =
    list.fold(
      earlier,
      game_connection_support.feed(
        game_connection_support.medic_in_world(),
        game_connection_support.beast_appears(unit_id: 40),
      ).0,
      fn(state, earlier) {
        game_connection_support.feed(
          state,
          beast_news(unit_id: 40, news: earlier),
        ).0
      },
    )
  let #(_, taken) =
    game_connection_support.feed(state, beast_news(unit_id: 40, news:))
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(UnitMovement(unit_id: 40, commands:, ..)) =
    unit_movement.decode(body)
  let assert [_, relayed_movement.Path(_), ..tail] = commands
    as "kind 0, kind 4, then the tail"
  tail
}

pub fn a_run_that_faces_a_unit_keeps_kind_18_for_it_and_any_other_run_takes_kind_21_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client keeps a unit facing another unit by kind 18 (`movement_command.kind_18`,
  // `0x140782cd0`) until a later rotation command, and kind 21 turns it along its path and
  // keeps the last facing (`movement_command.kind_21`, `0x140783030`), so a chase keeps kind 18
  // for its target and the player circling the creature after the arrival cannot leave it
  // facing away; every other run takes kind 21.
  let run =
    client_connection.CreatureMoved(path: creature_path.Running(
      from: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 0.0,
        y: 0.0,
        z: 0.0,
      ),
      via: [],
      to: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 26.0,
        y: 0.0,
        z: 0.0,
      ),
      started_ms: support.now_ms,
      speed: 10.0,
    ))
  let chasing_unit_20 = [
    relayed_movement.VelocityDefault(MovementKind10(blends: 1)),
    relayed_movement.MoveDefault(MovementKind13(blends: 1)),
    relayed_movement.FaceUnit(MovementFaceUnit(unit_id: 20, blends: 1)),
    relayed_movement.StateDefault(MovementKind26(blends: 1)),
  ]
  let faces = fn(face) {
    client_connection.CreatureFaces(face:, at_ms: support.now_ms)
  }
  let cases = [
    #(
      "a run of a creature that faces no one takes kind 21",
      [],
      path_defaults(),
    ),
    #(
      "a chase faces its target's unit by kind 18, in place of kind 21",
      [faces(creature_turn.Unit(unit_id: 20))],
      chasing_unit_20,
    ),
    #(
      "a walk home faces a point and takes kind 21",
      [
        faces(
          creature_turn.Point(place: place_support.at(
            world_id: 3460,
            world_zone_id: 6009,
            x: 5.0,
            y: 0.0,
            z: 5.0,
          )),
        ),
      ],
      path_defaults(),
    ),
    #(
      "a run held to a fixed facing takes kind 21",
      [
        faces(
          creature_turn.Fixed(facing: start_place.Facing(
            yaw: 1.5,
            pitch: 0.0,
            roll: 0.0,
          )),
        ),
      ],
      path_defaults(),
    ),
    #(
      "a run after a turn at a unit and then at a fixed facing takes kind 21: the last turn counts",
      [
        faces(creature_turn.Unit(unit_id: 20)),
        faces(
          creature_turn.Fixed(facing: start_place.Facing(
            yaw: 1.5,
            pitch: 0.0,
            roll: 0.0,
          )),
        ),
      ],
      path_defaults(),
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, earlier, expected) = row
    assert run_tail_after(earlier:, news: run) == expected as reason
  })
}

pub fn a_viewer_writes_a_creature_placed_while_it_ran_as_kind_0_then_kind_2_with_the_blend_bit_clear_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 10.0,
      y: 0.0,
      z: 0.0,
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: client_connection.CreaturePlaced(place:, at_ms: support.now_ms),
      ),
    )
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(UnitMovement(unit_id: 40, commands:, ..)) =
    unit_movement.decode(body)
  assert commands
    == [
      relayed_movement.Time(movement_time.MovementTime(time: support.now_ms)),
      relayed_movement.Position(UnitPositionCommand(
        x: float32.to_bits(10.0),
        y: 0,
        z: 0,
        blends: 0,
      )),
      relayed_movement.MoveAsked(movement_move_asked.MovementMoveAsked(
        x: 0,
        y: 0,
        z: 0,
        blends: 1,
      )),
      relayed_movement.StateFlags(movement_state_flags.MovementStateFlags(
        flags: 0x100,
      )),
    ]
    as "kind 0, the time of the placing, kind 2 at the place with its bit clear, which places the unit at once (0x140714120), then kind 11 zero and kind 24 holding only the ground bit 0x100, which stop the animation"
}

pub fn a_press_during_a_chase_finds_the_creature_where_its_path_puts_it_test() -> Nil {
  use <- owned_test.run(10_000)
  // The Beast appears 3 m ahead of the Medic; its next news is a path that starts
  // 23 m ahead, now, and runs on away along -z: at the press it stands at the
  // path's start, past Paralytic Surge's 15 m (Spell4AoeTargetConstraints 173).
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let from =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.128599166870117,
      y: -853.87158203125,
      z: -583.18798828125,
    )
  let to =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.128599166870117,
      y: -853.87158203125,
      z: -603.18798828125,
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: client_connection.CreatureMoved(path: creature_path.Running(
          from:,
          via: [],
          to:,
          started_ms: support.now_ms,
          speed: 10.0,
        )),
      ),
    )
  let #(_, struck) = press_and_close(state:, client_cast_id: 1)
  assert struck == []
    as "the selection reads the creature at place_at(path, now), 23 m away, not 3 m ahead where its 0x262 put it"
}

pub fn a_press_finds_a_creature_whose_path_brought_it_within_the_area_test() -> Nil {
  use <- owned_test.run(10_000)
  // The positive control: the Beast's path starts 23 m ahead and, at 100 a second
  // from 180 ms before, is run by now, ending 5 m ahead, inside Paralytic Surge's
  // 15 m.
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let at_z = fn(z) {
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.128599166870117,
      y: -853.87158203125,
      z:,
    )
  }
  let #(state, _) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: client_connection.CreatureMoved(path: creature_path.Running(
          from: at_z(-583.18798828125),
          via: [],
          to: at_z(-565.18798828125),
          started_ms: support.now_ms - 180,
          speed: 100.0,
        )),
      ),
    )
  let #(_, struck) = press_and_close(state:, client_cast_id: 1)
  assert struck == [40] as "the path's end, 5 m ahead, is inside the area"
}

// ------------------------------------------- a creature and a player's connection, both rules
//
// The creature's rule (genesis_prime/world_map/creature) and the Medic's connection
// rule driven together, each one's sends delivered to the other by the test, which
// holds a tell or delivers it as the case needs and fires the creature's timers at
// the time it chooses: the fight of the design's CI bot and test 20 with no clock of
// the machine. Expected values: the Virtual Battle Beast (52 health, spell 5649's
// effect 184741 for 12 every 1500 ms, reach 8.0, run speed 10.0; `Spell4Effects.184741`,
// `Creature2.73464`, migration 0010), the game numbers (leash 55), a Medic of level 1
// (Armor 200, the 0.75 cap: 12 is mitigated to 3; its shield of 450 takes round(3 x
// 0.625) = 2 and its 736 health 1; `player.level1_defence`,
// `player.level1_gear_properties`), and the messages' layouts (`opcode.0x908`,
// `opcode.0x90a`, `opcode.0x89a`, `opcode.0x938`, `opcode.0x92f`, `opcode.0x937`).

/// The Medic's unit in the tests' map: unit 5, after the map's four players.
const medic_unit = 5

/// Where the Beast stands: 3 m ahead of the Medic, as `beast_appears` puts it.
fn beast_spawn_place() -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: 29.128599166870117,
    y: -853.87158203125,
    z: -563.18798828125,
  )
}

/// Where the Medic stands: its saved place.
fn medic_place(z_offset: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: 29.128599166870117,
    y: -853.87158203125,
    z: -560.18798828125 +. z_offset,
  )
}

/// The Beast as unit 7 of life 3 of the tests' run of the map, started for the
/// Medic's connection at 1000 ms on the monotonic clock.
fn a_beast_for_the_medic() -> #(
  creature.State,
  step.ServiceStep(creature.Outgoing),
) {
  a_beast_of(spawn_support.beast_at(number: 1, place: beast_spawn_place()))
}

/// The creature of `spawn` as unit 7 of life 3 of the tests' run of the map,
/// started for connection 1, whose player is unit 5, at 1000 ms on the monotonic
/// clock.
fn a_beast_of(
  spawn: spawn.Spawn,
) -> #(creature.State, step.ServiceStep(creature.Outgoing)) {
  let state =
    creature.new(creature.Settings(
      creature: step.CreatureStart(
        map: game_connection_support.camp_map(),
        incarnation: game_connection_support.incarnation,
        unit_id: 7,
        life: 3,
        spawn: spawn_source.Stored(id: spawn_id.SpawnId(1)),
        clock_origin_ms: 0,
        viewers: [#(ConnectionId(1), game_connection_support.own_stay())],
      ),
      spawn:,
      kind: Kind(
        respawn_ms: 60_000,
        attack_spell4_id: Spell4Id(5649),
        alternate_spell4_ids: [],
        attack_interval_ms: 1500,
        guard: option.None,
        specials: [],
      ),
      numbers: spawn_support.numbers,
    ))
  creature.step(
    state,
    support.input_at_ms(ms: 1000, event: OwnEvent(step.Started)),
  )
}

/// The creature's sends to the Medic's connection, as the connection takes them
/// (`server.creature_message`).
fn to_the_medic(taken: step.ServiceStep(creature.Outgoing)) -> List(Message) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Send(to: step.Connection(ConnectionId(1)), message:)) ->
        Ok(server.creature_message(outgoing: message))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The connection's tells to the creature, as the creature takes them.
fn to_the_beast(taken: ConnectionStep(Request)) -> List(creature.Message) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(to: step.Creature(unit_id: 7, ..), request:)) ->
        case request {
          client_connection.TellStrike(tell:) -> Ok(creature.Strike(tell:))
          client_connection.TellTargetMoved(
            connection:,
            place:,
            seq:,
            stay:,
            hit_radius:,
          ) ->
            Ok(creature.TargetMoved(
              by: connection,
              place:,
              seq:,
              stay:,
              hit_radius:,
            ))
          client_connection.TellStrikeAnswered(answered:) ->
            Ok(creature.StrikeAnswered(answered:))
          client_connection.TellTargetChange(
            connection:,
            change: client_connection.ChangeStarts(
              source:,
              modifier:,
              struck_at_ms:,
            ),
          ) ->
            Ok(creature.ModifierStarts(
              by: connection,
              source:,
              modifier:,
              struck_at_ms:,
            ))
          client_connection.TellTargetChange(
            change: client_connection.ChangeEnds(source:),
            ..,
          ) -> Ok(creature.ModifierEnds(source:))
          client_connection.TellThrown(throw:, struck_at_ms:) ->
            Ok(creature.Thrown(throw:, struck_at_ms:))
          client_connection.TellDespawn(delay_ms:, struck_at_ms:, went_at_ms:) ->
            Ok(creature.Despawn(delay_ms:, struck_at_ms:, went_at_ms:))
          client_connection.TellUnitStates(rows:, struck_at_ms:, went_at_ms:) ->
            Ok(creature.UnitStates(rows:, struck_at_ms:, went_at_ms:))
          AskStore(..)
          | AskHandOff(..)
          | AskSessions(..)
          | AskMap(..)
          | AskMapRun(..)
          | TellMoved(..)
          | client_connection.TellReady(..)
          | client_connection.TellStealthChanged(..)
          | client_connection.TellVisibilityChanged(..)
          | client_connection.TellLifeChanged(..)
          | client_connection.TellReleased(..)
          | TellPeer(..)
          | TellChat(..) -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The connection after taking the messages, and the frames it wrote and the tells
/// it made, in order.
fn medic_takes(
  state: game_connection.State,
  messages: List(Message),
) -> #(game_connection.State, List(Frame), List(creature.Message)) {
  list.fold(messages, #(state, [], []), fn(held, message) {
    let #(state, frames, tells) = held
    let #(state, taken) =
      game_connection_support.feed(state, OwnEvent(Woken(message)))
    #(
      state,
      list.append(
        frames,
        game_connection_support.heard(taken, game_connection_support.keyed()),
      ),
      list.append(tells, to_the_beast(taken)),
    )
  })
}

/// The creature after taking the messages at `at_ms`, and its steps.
fn beast_takes(
  state state: creature.State,
  at_ms at_ms: Int,
  messages messages: List(creature.Message),
) -> #(creature.State, List(step.ServiceStep(creature.Outgoing))) {
  list.fold(messages, #(state, []), fn(held, message) {
    let #(state, steps) = held
    let #(state, taken) =
      creature.step(
        state,
        support.input_at_ms(ms: at_ms, event: OwnEvent(step.Told(message))),
      )
    #(state, list.append(steps, [taken]))
  })
}

/// The attack tick the creature's step starts, of the kind's 1500 ms.
fn tick_of(taken: step.ServiceStep(creature.Outgoing)) -> step.TimerId {
  let assert [#(timer, _)] =
    list.filter(started_but_the_arrival(taken), fn(started) {
      started.1 == 1500
    })
    as "the step starts the next attack tick"
  timer
}

/// The timers a step starts, with their delays, but for the chase's arrival timer.
fn started_but_the_arrival(
  taken: step.ServiceStep(creature.Outgoing),
) -> List(#(step.TimerId, Int)) {
  list.filter(support.service_timers_started(taken), fn(started) {
    started.0 != creature.chase_arrival_timer
  })
}

/// The creature after its timer fires at `at_ms`, and its step.
fn fire_beast(
  state state: creature.State,
  at_ms at_ms: Int,
  timer timer: step.TimerId,
) -> #(creature.State, step.ServiceStep(creature.Outgoing)) {
  creature.step(
    state,
    support.input_at_ms(
      ms: at_ms,
      event: OwnEvent(step.ServiceTimerFired(timer:)),
    ),
  )
}

/// The Medic and the Beast after the Medic stands in the Beast's ring, aggroed: the
/// connection, the creature, and the step that started the attack tick.
fn an_aggroed_medic() -> #(
  game_connection.State,
  creature.State,
  step.ServiceStep(creature.Outgoing),
  List(Frame),
) {
  let #(beast, started) = a_beast_for_the_medic()
  let #(medic, shown, _) =
    medic_takes(game_connection_support.medic_in_world(), to_the_medic(started))
  let #(beast, aggro) =
    creature.step(
      beast,
      support.input_at_ms(
        ms: 1000,
        event: OwnEvent(
          step.Told(creature.Approached(
            by: ConnectionId(1),
            unit_id: medic_unit,
            place: medic_place(0.0),
            seq: 1,
            stay: game_connection_support.own_stay(),
            hit_radius: place_support.player_hit_radius,
          )),
        ),
      ),
    )
  let #(medic, frames, _) = medic_takes(medic, to_the_medic(aggro))
  #(medic, beast, aggro, list.append(shown, frames))
}

pub fn a_beasts_aggro_strike_and_leash_reach_the_medics_client_with_the_worked_values_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(medic, beast, aggro, frames) = an_aggroed_medic()
  assert game_connection_support.decoded(frames, 0x0908, unit_target.decode)
    == [UnitTarget(unit_id: 7, target_unit_id: medic_unit, threat: 1)]
    as "0x908: the Beast targets the Medic with the aggro threat 1"
  assert game_connection_support.decoded(
      frames,
      0x089A,
      unit_combat_state.decode,
    )
    == [
      UnitCombatState(unit_id: 7, in_combat: 1),
      UnitCombatState(unit_id: medic_unit, in_combat: 1),
    ]
    as "both 0x89a: the Beast's, then the Medic's own on the Beast's threat"
  // The first tick: the Medic stands 3 m off, within reach 8, so the Beast strikes.
  let #(beast, ticked) =
    fire_beast(state: beast, at_ms: 2500, timer: tick_of(aggro))
  let #(medic, struck, answers) = medic_takes(medic, to_the_medic(ticked))
  assert game_connection_support.decoded(
      struck,
      0x0938,
      unit_stat_changed.decode,
    )
    == [
      UnitStatChanged(
        unit_id: medic_unit,
        change: unit_stat_change.Shield(UnitStatShield(value: 448)),
      ),
    ]
    && game_connection_support.decoded(struck, 0x092F, player_health.decode)
    == [PlayerHealth(unit_id: medic_unit, health: 735, reason_mask: 0)]
    as "12 mitigated to 3: the shield 450 less 2 (stat 20), then the health 736 less 1"
  let #(beast, answered) =
    beast_takes(state: beast, at_ms: 2600, messages: answers)
  let #(medic, went, _) =
    medic_takes(medic, list.flat_map(answered, to_the_medic))
  let assert [go] =
    game_connection_support.decoded(went, 0x07F4, spell_go.decode)
  let assert [target] = go.targets
  let assert [effect] = target.effects
  let assert spell_effect_result.Damage(damage) = effect.result
  assert target.unit_id == medic_unit
    && effect.spell4_effects_id == 184_741
    && damage.description.raw_damage == 12
    && damage.description.shield_absorbed == 2
    && damage.description.health_damage_with_overkill == 1
    as "the Beast's 0x7f4 names the Medic, effect 184741, raw 12: 2 to the shield and 1 to health"
  // The Medic walks 100 m out; the Beast chases to the leash circle, 55 from its
  // spawn, reached 5.5 s after the move, and leashes at the tick that finds it there.
  let #(medic, moved) =
    game_connection_support.read(
      medic,
      game_connection_support.moves_message([
        game_client.position_command(
          x: 29.128599166870117,
          y: -853.87158203125,
          z: -460.18798828125,
        ),
      ]),
    )
  let #(beast, _) =
    beast_takes(state: beast, at_ms: 2600, messages: to_the_beast(moved))
  let #(beast, at_4000) =
    fire_beast(state: beast, at_ms: 4000, timer: tick_of(ticked))
  let #(beast, at_5500) =
    fire_beast(state: beast, at_ms: 5500, timer: tick_of(at_4000))
  let #(beast, at_7000) =
    fire_beast(state: beast, at_ms: 7000, timer: tick_of(at_5500))
  let #(_, leashed) =
    fire_beast(state: beast, at_ms: 8500, timer: tick_of(at_7000))
  let #(_, leash, _) = medic_takes(medic, to_the_medic(leashed))
  assert game_connection_support.decoded(leash, 0x090A, unit_threat.decode)
    == [UnitThreat(unit_id: 7, other_unit_id: medic_unit, threat: 0)]
    as "0x90a 0: the Medic's entry is erased"
  assert game_connection_support.decoded(
      leash,
      0x089A,
      unit_combat_state.decode,
    )
    == [
      UnitCombatState(unit_id: 7, in_combat: 0),
      UnitCombatState(unit_id: medic_unit, in_combat: 0),
    ]
    as "0x89a (C, 0), then the Medic's own on its release"
  assert game_connection_support.decoded(leash, 0x0937, unit_health.decode)
    == [UnitHealth(unit_id: 7, health: 52, dead: 0)]
    as "a full 0x937: the leash restores the Beast's 52"
  let assert [turn, home] =
    game_connection_support.decoded(leash, 0x0638, unit_movement.decode)
    as "the turn to home, then the path home"
  let assert [_, relayed_movement.FacePoint(point)] = turn.commands
  let spawn_bits =
    MovementFloatVector(
      x: float32.to_bits(29.128599166870117),
      y: float32.to_bits(-853.87158203125),
      z: float32.to_bits(-563.18798828125),
    )
  assert MovementFloatVector(x: point.x, y: point.y, z: point.z) == spawn_bits
    && point.blends == 1
    as "kind 19 names the Beast's spawn, turning it over half a second"
  let assert [relayed_movement.Time(_), relayed_movement.Path(path), ..defaults] =
    home.commands
    as "kind 0, the path home, then the defaults that animate the walk; nothing else follows"
  let assert [_, end] = path.points
  assert end == spawn_bits as "the path home ends at the Beast's spawn"
  assert defaults == path_defaults()
    as "kinds 10, 13, 21 and 26 with bit 1: the walk home is animated, grounded and faced by the client's own defaults"
}

pub fn a_player_beside_the_crash_site_bodies_is_sent_no_target_combat_state_or_cast_from_them_test() -> Nil {
  use <- owned_test.run(10_000)
  // The three Dead Crash Survivors of Crash Site (spawns 18388, 18605 and 18619, Creature2
  // 13277, 50716 and 50717: uiFlags 0x1AF, bit 8 of `Creature2.uiFlags.bit8`) are Hostile to a
  // Dominion player and, in the recorded sitting, aimed 0x908, 0x89a and 0x7ff at it from where
  // they lay. Each is started as a creature's process starts it, shown to the Medic's connection
  // and then told what the map would tell a creature whose ring a player entered. The control is
  // the Beast, which the same `Approached` aggroes.
  let opcodes = fn(frames: List(Frame)) {
    list.map(frames, fn(frame) { frame.message_id })
  }
  let fight_opcodes = [0x0908, 0x089A, 0x07FF]
  let bodies = spawn_support.started_of(spawn_support.crash_site_bodies())
  let control = spawn_support.beast_at(number: 1, place: beast_spawn_place())
  let scene =
    list.append(list.map(bodies, fn(body) { #(body, False) }), [
      #(control, True),
    ])
  list.each(scene, fn(entry) {
    let #(spawn, fights) = entry
    let #(beast, started) = a_beast_of(spawn)
    let #(medic, shown, _) =
      medic_takes(
        game_connection_support.medic_in_world(),
        to_the_medic(started),
      )
    assert game_connection_support.decoded(
        shown,
        0x0262,
        unit_create_creature.decode,
      )
      |> list.map(fn(created) { created.creature_id })
      == [spawn.creature_id.value]
      as "the creature is shown to the player whether it fights or not"
    let #(_, aggro) =
      creature.step(
        beast,
        support.input_at_ms(
          ms: 1000,
          event: OwnEvent(
            step.Told(creature.Approached(
              by: ConnectionId(1),
              unit_id: medic_unit,
              place: medic_place(0.0),
              seq: 1,
              stay: game_connection_support.own_stay(),
              hit_radius: place_support.player_hit_radius,
            )),
          ),
        ),
      )
    let #(_, frames, _) = medic_takes(medic, to_the_medic(aggro))
    let sent_fight_frames =
      list.filter(opcodes(frames), fn(id) { list.contains(fight_opcodes, id) })
    assert { sent_fight_frames != [] } == fights
      as "the player is sent the target and the combat flag of a creature that fights, and none of a body"
    assert { support.service_timers_started(aggro) != [] } == fights
      as "no attack tick of a body is left to run, so no later step of the clock sends a cast"
  })
}

/// The Medic's 0x638 commands for the Beast (unit 7), one list per frame, in order.
fn beast_movements(
  frames: List(Frame),
) -> List(List(relayed_movement.RelayedMovement)) {
  list.filter_map(
    game_connection_support.decoded(frames, 0x0638, unit_movement.decode),
    fn(movement) {
      case movement.unit_id {
        7 -> Ok(movement.commands)
        _ -> Error(Nil)
      }
    },
  )
}

/// The one timer a step starts besides the chase's arrival and the attack tick, with
/// its delay: the walk home's arrival.
fn home_timer_of(
  taken: step.ServiceStep(creature.Outgoing),
) -> #(step.TimerId, Int) {
  let assert [started] =
    list.filter(started_but_the_arrival(taken), fn(started) {
      started.1 != 1500
    })
    as "the step starts one timer besides the chase's arrival and the attack tick"
  started
}

/// The delay of the chase's arrival timer a step starts.
fn chase_arrival_after_ms(taken: step.ServiceStep(creature.Outgoing)) -> Int {
  let assert [#(_, after_ms)] =
    list.filter(support.service_timers_started(taken), fn(started) {
      started.0 == creature.chase_arrival_timer
    })
    as "the step starts the chase's arrival timer"
  after_ms
}

pub fn a_beast_that_chases_the_player_runs_in_the_clients_view_and_stops_where_it_arrives_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(medic, beast, aggro, _) = an_aggroed_medic()
  // The Medic steps 12 m out, so the Beast stands 15 m off, beyond its reach 8.
  let #(medic, moved) =
    game_connection_support.read(
      medic,
      game_connection_support.moves_message([
        game_client.position_command(
          x: 29.128599166870117,
          y: -853.87158203125,
          z: -548.18798828125,
        ),
      ]),
    )
  let #(beast, chasing) =
    beast_takes(state: beast, at_ms: 1100, messages: to_the_beast(moved))
  let assert [chase] = chasing
  let #(medic, run, _) = medic_takes(medic, to_the_medic(chase))
  let assert [
    [relayed_movement.Time(_), relayed_movement.Path(path), ..defaults],
  ] = beast_movements(run)
    as "kind 0, the path, then the defaults that make the client animate it"
  assert defaults
    == [
      relayed_movement.VelocityDefault(MovementKind10(blends: 1)),
      relayed_movement.MoveDefault(MovementKind13(blends: 1)),
      relayed_movement.FaceUnit(MovementFaceUnit(unit_id: medic_unit, blends: 1)),
      relayed_movement.StateDefault(MovementKind26(blends: 1)),
    ]
    as "kinds 10, 13 and 26 with bit 1 animate and ground the run, and kind 18 keeps the Beast facing the Medic along the path and after it stops"
  assert chase_arrival_after_ms(chase) == 1100
    as "the Beast stops 4 m short of the Medic: 11 m at 10 m/s"
  let #(beast, arrived) =
    fire_beast(state: beast, at_ms: 2200, timer: creature.chase_arrival_timer)
  let #(medic, stop, _) = medic_takes(medic, to_the_medic(arrived))
  let assert [end] = list.drop(path.points, 1)
  let assert [
    [
      relayed_movement.Time(_),
      relayed_movement.Position(position),
      relayed_movement.MoveAsked(stopped),
      relayed_movement.StateFlags(standing),
    ],
  ] = beast_movements(stop)
    as "kind 0, kind 2, then kind 11 zero and kind 24 clear: the creature stands"
  assert MovementFloatVector(x: position.x, y: position.y, z: position.z) == end
    && stopped
    == movement_move_asked.MovementMoveAsked(x: 0, y: 0, z: 0, blends: 1)
    && standing.flags == 0x100
    as "the creature is placed where the path ended and its animation stops"
  // The Medic stands still: the Beast's tick strikes from where it stands and sends no movement.
  let #(beast, ticked) =
    fire_beast(state: beast, at_ms: 2500, timer: tick_of(aggro))
  let #(medic, struck, answers) = medic_takes(medic, to_the_medic(ticked))
  assert beast_movements(struck) == []
    as "a creature in reach of a player who stands still is sent no movement"
  let #(beast, answered) =
    beast_takes(state: beast, at_ms: 2600, messages: answers)
  let #(medic, _, _) = medic_takes(medic, list.flat_map(answered, to_the_medic))
  // The Medic walks 100 m out: the Beast runs to the leash circle, 55 from its spawn, and
  // leashes at the tick that finds it there (7 s), walking home with the same animation.
  let #(medic, moved) =
    game_connection_support.read(
      medic,
      game_connection_support.moves_message([
        game_client.position_command(
          x: 29.128599166870117,
          y: -853.87158203125,
          z: -460.18798828125,
        ),
      ]),
    )
  let #(beast, _) =
    beast_takes(state: beast, at_ms: 2600, messages: to_the_beast(moved))
  let #(beast, at_4000) =
    fire_beast(state: beast, at_ms: 4000, timer: tick_of(ticked))
  let #(beast, at_5500) =
    fire_beast(state: beast, at_ms: 5500, timer: tick_of(at_4000))
  let #(beast, leashed) =
    fire_beast(state: beast, at_ms: 7000, timer: tick_of(at_5500))
  let #(medic, leash, _) = medic_takes(medic, to_the_medic(leashed))
  let assert [_, [_, relayed_movement.Path(_), ..home_tail]] =
    beast_movements(leash)
    as "the turn to home, then the path home"
  assert home_tail == path_defaults()
    as "the walk home takes the same four defaults"
  let #(home_timer, home_after_ms) = home_timer_of(leashed)
  let #(_, home) =
    fire_beast(state: beast, at_ms: 7000 + home_after_ms, timer: home_timer)
  let #(_, at_home, _) = medic_takes(medic, to_the_medic(home))
  let assert [
    [
      relayed_movement.Time(_),
      relayed_movement.Position(spawn),
      relayed_movement.MoveAsked(stopped),
      relayed_movement.StateFlags(standing),
    ],
    ..
  ] = beast_movements(at_home)
    as "the arrival home places the Beast and stops it, before the turn and the chase of the Medic it finds near"
  assert MovementFloatVector(x: spawn.x, y: spawn.y, z: spawn.z)
    == MovementFloatVector(
      x: float32.to_bits(29.128599166870117),
      y: float32.to_bits(-853.87158203125),
      z: float32.to_bits(-563.18798828125),
    )
    && stopped
    == movement_move_asked.MovementMoveAsked(x: 0, y: 0, z: 0, blends: 1)
    && standing.flags == 0x100
    as "at the spawn, kind 11 zero and kind 24 holding only the ground bit"
}

pub fn a_creature_back_at_its_spawn_sends_the_blended_turn_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(medic, beast, aggro, _) = an_aggroed_medic()
  // The Medic walks 100 m out; the Beast chases to the leash circle and leashes, walks home and
  // arrives at its spawn (the arrival places it and then turns it).
  let #(medic, moved) =
    game_connection_support.read(
      medic,
      game_connection_support.moves_message([
        game_client.position_command(
          x: 29.128599166870117,
          y: -853.87158203125,
          z: -460.18798828125,
        ),
      ]),
    )
  let #(beast, _) =
    beast_takes(state: beast, at_ms: 1100, messages: to_the_beast(moved))
  let #(beast, at_2500) =
    fire_beast(state: beast, at_ms: 2500, timer: tick_of(aggro))
  let #(beast, at_4000) =
    fire_beast(state: beast, at_ms: 4000, timer: tick_of(at_2500))
  let #(beast, at_5500) =
    fire_beast(state: beast, at_ms: 5500, timer: tick_of(at_4000))
  let #(beast, leashed) =
    fire_beast(state: beast, at_ms: 7000, timer: tick_of(at_5500))
  let #(medic, _, _) = medic_takes(medic, to_the_medic(leashed))
  let #(home_timer, home_after_ms) = home_timer_of(leashed)
  let #(_, home) =
    fire_beast(state: beast, at_ms: 7000 + home_after_ms, timer: home_timer)
  let #(_, at_home, _) = medic_takes(medic, to_the_medic(home))
  // The Beast's spawn faces yaw 0 (`place_support.at`), which faces -z, so the point is the
  // spawn 1 m on in -z (`movement_command.kind_19`, `movement_command.kind_14.facing`).
  let assert [_placed, [_, relayed_movement.FacePoint(point)], ..] =
    beast_movements(at_home)
    as "the arrival places the Beast, then turns it: kind 0 and kind 19, no kind 14"
  assert point.blends == 1 as "the client blends the turn over half a second"
  assert MovementFloatVector(x: point.x, y: point.y, z: point.z)
    == MovementFloatVector(
      x: float32.to_bits(29.128599166870117),
      y: float32.to_bits(-853.87158203125),
      z: float32.to_bits(-564.18798828125),
    )
    as "the point is 1 m from the spawn along its facing"
}

pub fn a_medic_and_a_beast_striking_each_other_at_one_instant_both_get_their_answers_before_either_deadline_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(medic, beast, aggro, _) = an_aggroed_medic()
  // The Beast's tick sends its strike; the test holds it.
  let #(beast, ticked) =
    fire_beast(state: beast, at_ms: 2500, timer: tick_of(aggro))
  let #(started, held_attack) =
    list.partition(to_the_medic(ticked), fn(message) {
      case message {
        ForStay(sent: client_connection.SentByFoe(..), ..) -> False
        ForStay(..) | SentBySessions(..) | client_connection.SentByChat(..) ->
          True
      }
    })
  let #(medic, _, _) = medic_takes(medic, started)
  // The Medic presses Paralytic Surge: its strike is told; the test holds it too.
  let #(medic, pressed) =
    game_connection_support.press_paralytic_surge(
      state: medic,
      client_cast_id: 1,
    )
  let held_strike = to_the_beast(pressed)
  assert list.length(held_strike) == 1 && list.length(held_attack) == 1
    as "both rounds are open, each strike in flight to the other"
  // Both tells are delivered, each into a process whose own round waits.
  let #(medic, _, medic_answer) = medic_takes(medic, held_attack)
  let #(beast, beast_steps) =
    beast_takes(state: beast, at_ms: 2510, messages: held_strike)
  let #(medic, medic_went, _) =
    medic_takes(medic, list.flat_map(beast_steps, to_the_medic))
  let #(_, beast_answered) =
    beast_takes(state: beast, at_ms: 2520, messages: medic_answer)
  let #(_, beast_went, _) =
    medic_takes(medic, list.flat_map(beast_answered, to_the_medic))
  let gos =
    list.map(
      game_connection_support.decoded(
        list.append(medic_went, beast_went),
        0x07F4,
        spell_go.decode,
      ),
      fn(go) { list.map(go.targets, fn(target) { target.unit_id }) },
    )
  assert gos == [[7], [medic_unit]]
    as "each strike is a tell answered in its owner's own step: the Medic's go names the Beast, the Beast's names the Medic, and no deadline timer fired"
}

// ---- the done-when fight: each class against a planted creature, both rules
//
// The creature's rule and the player's connection rule driven together, as in
// `a_beasts_aggro_strike_and_leash_...`, with the creature's timers fired at the
// times the test chooses. Of the planted abilities only the Medic's Paralytic
// Surge strikes a creature (`novice_tables`: the one damage effect), so the Medic
// kills the Beast and the Beast kills each other class's player.

/// The Battle Beast with its blow raised to 2000: a planted creature, since the
/// Beast's own 12 takes some 400 ticks to kill a level-1 player and the fight is
/// about the death, not the number.
fn a_lethal_beast() -> spawn.Spawn {
  spawn_support.spawn_dealing(
    spawn: spawn_support.beast_at(number: 1, place: beast_spawn_place()),
    damage: 2000,
  )
}

/// The player of `player` and the creature of `spawn` after the player stands in
/// its ring, aggroed: the connection, the creature, the step that started the
/// attack tick, and the frames the player's client was written.
fn aggroed(
  player player: game_connection.State,
  spawn spawn: spawn.Spawn,
) -> #(
  game_connection.State,
  creature.State,
  step.ServiceStep(creature.Outgoing),
  List(Frame),
) {
  let #(beast, started) = a_beast_of(spawn)
  let #(player, shown, _) = medic_takes(player, to_the_medic(started))
  let #(beast, aggro) =
    creature.step(
      beast,
      support.input_at_ms(
        ms: 1000,
        event: OwnEvent(
          step.Told(creature.Approached(
            by: ConnectionId(1),
            unit_id: medic_unit,
            place: medic_place(0.0),
            seq: 1,
            stay: game_connection_support.own_stay(),
            hit_radius: place_support.player_hit_radius,
          )),
        ),
      ),
    )
  let #(player, frames, _) = medic_takes(player, to_the_medic(aggro))
  #(player, beast, aggro, list.append(shown, frames))
}

/// The creature's attack ticks from `timer` at `at_ms`, then every 1500 ms, each
/// strike delivered to the player, its answer to the creature and the creature's go
/// back, until the player's client is written its own 0x88c: the connection after.
fn ticks_until_the_player_dies(
  player player: game_connection.State,
  beast beast: creature.State,
  timer timer: step.TimerId,
  at_ms at_ms: Int,
  ticks_left ticks_left: Int,
) -> game_connection.State {
  assert ticks_left > 0
    as "the lethal Beast kills a level-1 player in a few ticks"
  let #(beast, ticked) = fire_beast(state: beast, at_ms:, timer:)
  let #(player, struck, answers) = medic_takes(player, to_the_medic(ticked))
  let #(beast, answered) =
    beast_takes(state: beast, at_ms: at_ms + 10, messages: answers)
  let #(player, _, _) =
    medic_takes(player, list.flat_map(answered, to_the_medic))
  case
    list.contains(
      game_connection_support.decoded(struck, 0x088C, unit_death_state.decode),
      UnitDeathState(unit_id: medic_unit, dead: 1, unread_3: 0, health: 0),
    )
  {
    True -> player
    False ->
      ticks_until_the_player_dies(
        player:,
        beast:,
        timer: tick_of(ticked),
        at_ms: at_ms + 1500,
        ticks_left: ticks_left - 1,
      )
  }
}

/// A round of Paralytic Surge: its recharge, `Spell4.42352` spellCoolDown 25000 ms
/// (its cast time is 0), after which the next press is taken.
const paralytic_surge_round_ms = 25_000

/// How the Beast answers a step of the Medic's connection at `ms`: each tell it
/// made reaches the creature, and what the creature sends back the connection, the
/// steps in order, the connection's own first.
fn answering_the_beast(
  beast beast: creature.State,
  player player: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(creature.State, game_connection.State, List(ConnectionStep(Request))) {
  let #(beast, steps) =
    beast_takes(state: beast, at_ms: ms, messages: to_the_beast(taken))
  let #(player, answered) =
    list.fold(
      list.flat_map(steps, to_the_medic),
      #(player, []),
      fn(held, message) {
        let #(player, answered) = held
        let #(player, step) =
          game_connection_support.at(
            state: player,
            ms:,
            event: OwnEvent(Woken(message)),
          )
        #(player, list.append(answered, [step]))
      },
    )
  #(beast, player, [taken, ..answered])
}

/// Paralytic Surge pressed, cast after cast, each cast run to its end (its
/// timers fired, each strike delivered to the creature and its answer and news
/// back) before the next press, a round later, until the client is written the
/// creature's 0x88c: the connection and the creature after.
fn presses_until_the_beast_dies(
  player player: game_connection.State,
  beast beast: creature.State,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
) -> #(game_connection.State, creature.State) {
  assert client_cast_id < 40
    as "Paralytic Surge kills the Beast's 52 health in a few casts"
  let #(player, beast, steps) =
    game_connection_support.pressed_until_answered(
      state: player,
      world: beast,
      bag_index: 2,
      client_cast_id:,
      ms:,
      until_ms: ms + paralytic_surge_round_ms,
      answer: answering_the_beast,
    )
  let frames =
    list.flat_map(steps, game_connection_support.heard(
      _,
      game_connection_support.keyed(),
    ))
  case
    list.contains(
      game_connection_support.decoded(frames, 0x088C, unit_death_state.decode),
      UnitDeathState(unit_id: 7, dead: 1, unread_3: 0, health: 0),
    )
  {
    True -> #(player, beast)
    False ->
      presses_until_the_beast_dies(
        player:,
        beast:,
        client_cast_id: client_cast_id + 1,
        ms: ms + paralytic_surge_round_ms,
      )
  }
}

/// The player of `class_id` in the world: the tests' character of that class.
fn a_player_of(class_id: Int) -> game_connection.State {
  game_connection_support.entered_as(
    Character(
      ..game_connection_support.world_character(),
      class_id: ClassId(class_id),
    ),
  ).0
}

pub fn a_player_of_each_class_fights_a_planted_creature_until_one_dies_and_both_come_back_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Medic kills the Beast, which stands again at its respawn: its corpse
  // timer of the kind's 60 s fires, and the client is written its 0x355 and its
  // 0x262 at full health (`death.creature_respawn`).
  let #(medic, beast, _, _) =
    aggroed(
      player: a_player_of(4),
      spawn: spawn_support.beast_at(number: 1, place: beast_spawn_place()),
    )
  let #(medic, beast) =
    presses_until_the_beast_dies(
      player: medic,
      beast:,
      client_cast_id: 1,
      ms: 1100,
    )
  let #(_, respawned) =
    fire_beast(state: beast, at_ms: 61_100, timer: TimerId(1))
  let #(_, frames, _) = medic_takes(medic, to_the_medic(respawned))
  assert list.take(cast_support.ids(frames:), 2) == [0x0355, 0x0262]
    && game_connection_support.decoded(frames, 0x0355, unit_destroyed.decode)
    == [UnitDestroyed(unit_id: 7, chest_world_object_delay: 0)]
    && list.map(
      game_connection_support.decoded(
        frames,
        0x0262,
        unit_create_creature.decode,
      ),
      fn(unit) { creature_unit.health_of(unit:) },
    )
    == [52]
    as "the Beast's corpse is removed and the Beast stands again at its full 52"
  // Each other class is killed by the Beast and comes back by Wake Here; the
  // Spellslinger by the Holocrypt.
  list.each([1, 2, 3, 5], fn(class_id) {
    let #(player, beast, aggro, _) =
      aggroed(player: a_player_of(class_id), spawn: a_lethal_beast())
    let dead =
      ticks_until_the_player_dies(
        player:,
        beast:,
        timer: tick_of(aggro),
        at_ms: 2500,
        ticks_left: 20,
      )
    let #(alive, woke) =
      game_connection_support.read(dead, game_connection_support.wake_here())
    assert game_connection_support.written_ids(woke)
      == [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247]
      as { "class " <> int.to_string(class_id) <> " comes back by Wake Here" }
    let #(_, struck) =
      game_connection_support.feed(
        alive,
        game_connection_support.a_beast_strike(
          game_connection_support.own_unit_id,
        ),
      )
    assert game_connection_support.decoded(
        game_connection_support.heard(struck, game_connection_support.keyed()),
        0x092F,
        player_health.decode,
      )
      != []
      as { "class " <> int.to_string(class_id) <> " is struck again: alive" }
  })
  let #(player, beast, aggro, _) =
    aggroed(player: a_player_of(7), spawn: a_lethal_beast())
  let dead =
    ticks_until_the_player_dies(
      player:,
      beast:,
      timer: tick_of(aggro),
      at_ms: 2500,
      ticks_left: 20,
    )
  let #(state, chosen) =
    game_connection_support.read(dead, game_connection_support.holocrypt())
  assert game_connection_support.ask_request(chosen)
    == game_connection_support.leave_asked()
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken: chosen,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(_, joined) =
    game_connection_support.mapped(
      map_state: game_connection_support.map_after_a_stay(),
      taken:,
    )
  let #(_, burst) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(joined)),
    )
  assert game_connection_support.written_ids(burst)
    == game_client.holocrypt_entry_ids()
    as "the Spellslinger comes back at the Holocrypt: the entry burst, with no second 0x25E (opcode.0x25e.entry_order)"
}

// ---- Electrocute: a channel's every pulse strikes the creature ----

/// The answer where the creature of the world takes the tells of the player's steps
/// at `ms` and its messages go back to the player, until nothing is told
/// (`game_connection_support.Answering`).
fn answered_by_the_beast(
  beast beast: creature.State,
  player player: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(creature.State, game_connection.State, List(ConnectionStep(Request))) {
  case to_the_beast(taken) {
    [] -> #(beast, player, [taken])
    tells -> {
      let #(beast, beast_steps) =
        beast_takes(state: beast, at_ms: ms, messages: tells)
      let #(beast, player, later) =
        list.fold(
          list.flat_map(beast_steps, to_the_medic),
          #(beast, player, []),
          fn(held, message) {
            let #(beast, player, later) = held
            let #(player, answer) =
              game_connection_support.at(
                state: player,
                ms:,
                event: OwnEvent(Woken(message)),
              )
            let #(beast, player, more) =
              answered_by_the_beast(beast:, player:, ms:, taken: answer)
            #(beast, player, list.append(later, more))
          },
        )
      #(beast, player, [taken, ..later])
    }
  }
}

/// What the Engineer's client hears from its Electrocute at a Beast in the camp, after four Pulse
/// Blasts, the first of which opens the fight, with `tables` as the server's rows: the Beast and the Engineer
/// are run by their own rules and answer each other (`answered_by_the_beast`).
fn electrocute_frames(tables tables: table_store.Tables) -> List(Frame) {
  let #(engineer, _) =
    game_connection_support.entered_with(
      settings: Settings(
        ..game_connection_support.settings(),
        tables:,
        server_proxies: spell_tables.server_proxies(),
      ),
      class_id: 2,
      saved_health: None,
    )
  let assert Ok(set) =
    loadout.of(tables:, class_id: ClassId(2), faction_id: 166)
    as "the fixture holds the Engineer's Novice set"
  let bag_index = fn(base) {
    let assert Ok(index) =
      list.index_map(set.abilities, fn(held, index) { #(held, index) })
      |> list.key_find(Spell4BaseId(base))
      as "a level-1 Engineer holds the ability"
    index
  }
  let pulse_blast = bag_index(26_468)
  let electrocute = bag_index(25_473)
  let assert Ok(strike) =
    spell4_effects.get(tables:, id: Spell4EffectsId(92_587))
    as "the client's Spell4Effects holds the row 92587"
  assert strike.spell_id == 41_276
    as "Spell4Effects 92587 is Electrocute's damage row (spellId 41276)"
  let #(beast, started) =
    a_beast_of(
      spawn.Spawn(
        ..spawn_support.beast_at(number: 1, place: beast_spawn_place()),
        health: 5000,
      ),
    )
  let #(engineer, shown, _) = medic_takes(engineer, to_the_medic(started))
  assert shown != [] as "the client is shown the Beast"
  // Electrocute costs 8 of the Volatility at each of its six pulses (Spell4 41276
  // innateCostType0 6, a cost per tick), 48 in all, and each Pulse Blast gives 15 (Spell4.42148),
  // the first of a fight included: four give 60.
  let #(engineer, beast) =
    list.index_fold(
      list.repeat(Nil, 4),
      #(engineer, beast),
      fn(so_far, _, blast) {
        let ms = 1000 + blast * 3000
        let #(engineer, beast, _) =
          game_connection_support.pressed_until_answered(
            state: so_far.0,
            world: so_far.1,
            bag_index: pulse_blast,
            client_cast_id: blast + 1,
            ms:,
            until_ms: ms + 1500,
            answer: answered_by_the_beast,
          )
        #(engineer, beast)
      },
    )
  let #(_, _, steps) =
    game_connection_support.pressed_until_answered(
      state: engineer,
      world: beast,
      bag_index: electrocute,
      client_cast_id: 5,
      ms: 14_000,
      until_ms: 18_000,
      answer: answered_by_the_beast,
    )
  list.flat_map(steps, game_connection_support.heard(
    _,
    game_connection_support.keyed(),
  ))
}

pub fn each_of_electrocutes_six_pulses_strikes_the_beast_and_lowers_its_health_test() -> Nil {
  use <- owned_test.run(60_000)
  let frames = electrocute_frames(tables: fixture_tables.shared())
  let goes = game_connection_support.decoded(frames, 0x07F4, spell_go.decode)
  assert list.map(goes, fn(go) { go.phase }) == [0, 1, 2, 3, 4, 5]
    as "Spell4.41276: channelInitialDelay 500, channelMaxTime 3000 and channelPulseTime 500 give six goes, the recording's phases 0 to 5"
  list.each(goes, fn(go) {
    assert list.map(go.targets, fn(target) {
        #(
          target.unit_id,
          list.map(target.effects, fn(effect) { effect.spell4_effects_id }),
        )
      })
      == [#(7, [92_587])]
      as "Spell4Effects 92587 (targetFlags 4, phaseFlags -1) strikes the Beast at every pulse"
  })
  let healths =
    list.filter_map(
      game_connection_support.decoded(frames, 0x0937, unit_health.decode),
      fn(health) {
        case health.unit_id == 7 {
          True -> Ok(health.health)
          False -> Error(Nil)
        }
      },
    )
  assert list.length(healths) == 6
    && list.sort(healths, fn(first, second) { int.compare(second, first) })
    == healths
    && list.unique(healths) == healths
    as "each pulse's damage lowers the Beast's health: six strictly falling values"
}

// ---- A gate the creature fails: the client is shown no hit ----

/// Runs the body on the client's rows with Electrocute's damage row, Spell4Effects 92587,
/// behind target apply prerequisite 3476 made one condition of type 28 (comparison 1, the
/// unit is in combat; comparison 2, it is not; `Prerequisite.prerequisiteTypeId.28`), a gate
/// each creature checks against its own fight (`prerequisite.checked_by_creature`). Kept
/// edits: Prerequisite 3476 and Spell4Effects 92587.
fn electrocute_behind_a_combat_gate(
  comparison comparison: Int,
  body body: fn(table_store.Tables) -> a,
) -> a {
  let assert Ok(rows) =
    fixture_tables.change(
      rows: fixture_tables.rows(),
      table: "Prerequisite",
      id: 3476,
      with: [
        #("prerequisiteTypeId0", planted_table.Integer(28)),
        #("prerequisiteComparisonId0", planted_table.Integer(comparison)),
        #("objectId0", planted_table.Integer(0)),
        #("value0", planted_table.Integer(0)),
      ],
    )
    as "the fixture holds Prerequisite 3476"
  let assert Ok(rows) =
    fixture_tables.change(rows:, table: "Spell4Effects", id: 92_587, with: [
      #("prerequisiteIdTargetApply", planted_table.Integer(3476)),
    ])
    as "the fixture holds Spell4Effects 92587"
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// The effects each go of the client's frames lists on unit 7, the Beast, and the health and
/// stat changes it hears for it.
fn heard_of_the_beast(
  frames frames: List(Frame),
) -> #(List(Int), List(Int), Int) {
  let effects =
    game_connection_support.decoded(frames, 0x07F4, spell_go.decode)
    |> list.flat_map(fn(go) { go.targets })
    |> list.filter(fn(target) { target.unit_id == 7 })
    |> list.flat_map(fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  let healths =
    game_connection_support.decoded(frames, 0x0937, unit_health.decode)
    |> list.filter(fn(health) { health.unit_id == 7 })
    |> list.map(fn(health) { health.health })
  let stats =
    game_connection_support.decoded(frames, 0x0938, unit_stat_changed.decode)
    |> list.filter(fn(changed) { changed.unit_id == 7 })
    |> list.length
  #(effects, healths, stats)
}

pub fn gated_strike_on_a_creature_shows_no_hit_test() -> Nil {
  use <- owned_test.run(60_000)
  // The same Electrocute after the same Pulse Blast, behind the same gate: the Beast is in
  // combat (the Pulse Blast opened the fight), so the gate "is in combat" passes and the
  // gate "is not in combat" fails.
  use passing <- electrocute_behind_a_combat_gate(comparison: 1)
  let #(effects, hit_healths, _) =
    heard_of_the_beast(frames: electrocute_frames(tables: passing))
  assert list.unique(effects) == [92_587]
    && list.length(list.unique(hit_healths)) == 6
    as "behind a gate the Beast passes, Electrocute strikes it as it does with none: its damage row at every pulse and six different healths"
  use failing <- electrocute_behind_a_combat_gate(comparison: 2)
  let frames = electrocute_frames(tables: failing)
  let #(effects, healths, stats) = heard_of_the_beast(frames:)
  assert effects == []
    as "Spell4Effects.prerequisiteIdTargetApply: the Beast fails the gate, so the go lists no effect on it"
  assert healths == []
    as "nothing reached the Beast, so it rolls no hit and the client is told no health of it"
  assert stats == 0
    as "the Beast takes no damage, so the client is told no stat change of it"
  let goes = game_connection_support.decoded(frames, 0x07F4, spell_go.decode)
  assert list.map(goes, fn(go) { go.phase }) == [0, 1, 2, 3, 4, 5]
    as "the channel still goes at each of its six pulses (Spell4.41276): only the gated row is left out"
}

/// The unit states a step tells creatures, as the creature's unit, its life and the request.
fn unit_states_told(
  taken: ConnectionStep(Request),
) -> List(#(Int, Int, client_connection.Request)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(
        to: step.Creature(unit_id:, life:, ..),
        request: client_connection.TellUnitStates(..) as request,
      )) -> Ok(#(unit_id, life, request))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// Paralytic Surge pressed at 1000 ms on the Beast the client shows, its round answered
/// landed at 1100 ms: the steps the answers take, on the tables with Spell4Effects 99097
/// added as a copy of Surge's CCStateSet row 96126 (targetFlags 4, phaseFlags -1) made a
/// UnitStateSet row of state 6, delay 500 ms and duration 2000 ms (Spell4Effects 204411's
/// shape) with these columns.
fn surge_with_a_unit_state_row(
  columns columns: List(#(String, planted_table.Cell)),
) -> List(ConnectionStep(Request)) {
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 96_126,
    id: 99_097,
    with: [
      #("effectType", planted_table.Integer(15)),
      #("dataBits00", planted_table.Integer(6)),
      #("dataBits03", planted_table.Integer(0)),
      #("delayTime", planted_table.Integer(500)),
      #("durationTime", planted_table.Integer(2000)),
      ..columns
    ],
    body: fn(tables) {
      let #(state, _) =
        game_connection_support.feed(
          game_connection_support.medic_in(tables),
          game_connection_support.beast_appears(unit_id: 40),
        )
      let #(state, pressed) =
        game_connection_support.press_paralytic_surge_at(
          state:,
          client_cast_id: 1,
          ms: 1000,
        )
      let #(_, answered) =
        list.fold(
          game_connection_support.strikes_told(pressed),
          #(state, []),
          fn(so_far, strike) {
            let #(state, steps) = so_far
            let #(state, taken) =
              game_connection_support.at(
                state:,
                ms: 1100,
                event: game_connection_support.landed(key: strike.1),
              )
            #(state, list.append(steps, [taken]))
          },
        )
      [pressed, ..answered]
    },
  )
}

pub fn a_creature_holds_unit_states_effect_becomes_a_tell_to_that_creature_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects 99097 is a type 15 row aimed at the area (targetFlags 4) of state 6 with a
  // delay of 500 ms and a duration of 2000 ms; Paralytic Surge's area holds the Beast, unit
  // 40, which the client shows in life 4 (`beast_appears`: its 0x262 news). The round opens
  // at the press, 1000 ms, and the go comes at the answer, 1100 ms.
  let steps = surge_with_a_unit_state_row(columns: [])
  assert list.flat_map(steps, unit_states_told)
    == [
      #(
        40,
        4,
        client_connection.TellUnitStates(
          rows: [unit_state.Row(state: 6, delay_ms: 500, duration_ms: 2000)],
          struck_at_ms: 1000,
          went_at_ms: 1100,
        ),
      ),
    ]
    as "the connection tells the creature of that life, with the row's state, delay and duration, the round's time and the go's time, and tells no other"
  assert list.all(steps, fn(taken) {
    list.all(game_connection_support.written_ids(taken), fn(id) {
      id != 0x0355 && id != 0x087F
    })
  })
    as "the tell draws nothing for the caster: the client reads no row of the type"
}

pub fn a_viewer_writes_a_creatures_facing_as_0x638_only_when_the_unit_is_shown_test() -> Nil {
  use <- owned_test.run(10_000)
  let faces = fn(face) {
    client_connection.CreatureFaces(face:, at_ms: support.now_ms)
  }
  // Before the creature's 0x262 the client shows no unit 40, and a 0x638 for an unknown unit
  // is ignored by the client (`opcode.0x638`): nothing is written.
  let state = game_connection_support.medic_in_world()
  let #(state, unknown) =
    game_connection_support.feed(
      state,
      beast_news(unit_id: 40, news: faces(creature_turn.Unit(unit_id: 9))),
    )
  assert game_connection_support.written_ids(unknown) == []
    as "a unit not yet shown is not written to"
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, shown) =
    game_connection_support.feed(
      state,
      beast_news(unit_id: 40, news: faces(creature_turn.Unit(unit_id: 9))),
    )
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(shown, game_connection_support.keyed())
    as "a shown creature's facing is one 0x638"
  let assert Ok(UnitMovement(unit_id: 40, commands:, ..)) =
    unit_movement.decode(body)
  assert commands
    == [
      relayed_movement.Time(movement_time.MovementTime(time: support.now_ms)),
      relayed_movement.FaceUnit(MovementFaceUnit(unit_id: 9, blends: 1)),
    ]
    as "kind 0 at the news's time, then kind 18 naming unit 9 with the blend bit set"
  let #(state, home) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: faces(
          creature_turn.Point(place: place_support.at(
            world_id: 3460,
            world_zone_id: 6009,
            x: 1.0,
            y: 0.0,
            z: 0.0,
          )),
        ),
      ),
    )
  assert game_connection_support.written_ids(home) == [0x0638]
    as "a point is written as well"
  // A creature that dies, in flight or not, keeps its facing by kind 14 with the bit clear: the
  // viewer writes the face as the creature's rule gave it (`0x140715350`).
  let #(state, frozen) =
    game_connection_support.feed(
      state,
      beast_news(
        unit_id: 40,
        news: faces(
          creature_turn.Fixed(facing: start_place.Facing(
            yaw: 1.5,
            pitch: 0.0,
            roll: 0.0,
          )),
        ),
      ),
    )
  let assert [Frame(message_id: 0x0638, body:)] =
    game_connection_support.heard(frozen, game_connection_support.keyed())
    as "a fixed facing is one 0x638"
  let assert Ok(UnitMovement(commands: [_, rotation], ..)) =
    unit_movement.decode(body)
  assert rotation
    == relayed_movement.Rotation(MovementRotation(
      yaw: 0x3FC00000,
      pitch: 0,
      roll: 0,
      blends: 0,
    ))
    as "kind 14 with the blend bit clear, so a corpse in flight is not turned"
  let #(state, _) =
    game_connection_support.feed(state, beast_news(unit_id: 40, news: Removed))
  let #(_, removed) =
    game_connection_support.feed(
      state,
      beast_news(unit_id: 40, news: faces(creature_turn.Unit(unit_id: 9))),
    )
  assert game_connection_support.written_ids(removed) == []
    as "a creature the 0x355 removed is written to no more"
}
