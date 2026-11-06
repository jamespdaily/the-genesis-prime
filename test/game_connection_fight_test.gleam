//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover a creature's
//// news, a viewer's casts, the caster's strike and a creature's fight, with
//// both rules.

import cast_support
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, type News, type Request, Appeared, AskHandOff,
  AskMap, AskMapRun, AskSessions, AskStore, CastFinished, CastStarted, CastWent,
  ForStay, FromMap, Removed, SentBySessions, TellChat, TellMoved, TellPeer,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_result
import genesis_prime/message/float32
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
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
import genesis_prime/table/id.{ClassId, Spell4Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_kind.{Kind}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map.{Left}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id
import genesis_prime/world_map/spawn_source
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import place_support
import spawn_support

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

/// The Beast units a press strikes, and the round closed with each one's answer.
fn press_and_close(
  state state: game_connection.State,
  client_cast_id client_cast_id: Int,
) -> #(game_connection.State, List(Int)) {
  let #(state, taken) =
    game_connection_support.press_paralytic_surge(state:, client_cast_id:)
  let told = game_connection_support.strikes_told(taken)
  let state =
    list.fold(told, state, fn(state, strike) {
      game_connection_support.feed(
        state,
        game_connection_support.landed(key: strike.1),
      ).0
    })
  #(state, list.map(told, fn(strike) { strike.0 }))
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
  let key = strike_tell.Key(cast_id: 2_147_500_000, phase: 0, unit_id: 5)
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
        outcome: strike_tell.Landed(descriptions: [_], controls: []),
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
  ] = commands
    as "kind 0, the time the path starts at, then kind 4, the path"
  assert path.speed == 0x4900 && path.path_type == 0 && path.mode == 0
    as "straight lines, mode 0, at 10.0 as a half float (sign 0, exponent 18, fraction 256)"
  assert path.points
    == [
      MovementFloatVector(x: 0, y: 0, z: 0),
      MovementFloatVector(x: float32.to_bits(26.0), y: 0, z: 0),
    ]
    as "the two points of the path, as 32-bit floats: 0, 0, 0 and 26, 0, 0"
  let assert [relayed_movement.Time(movement_time.MovementTime(time:)), _] =
    commands
  assert time == support.now_ms
    as "kind 0's time is the map's time the path starts at: its monotonic start, 1000, less the origin the tests' map took, 0 (map.server_time)"
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
    ]
    as "kind 0, the time of the placing, then kind 2 at the place with its bit clear, which places the unit at once (0x140714120)"
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
        attack_interval_ms: 1500,
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
          client_connection.TellTargetMoved(connection:, place:, seq:, stay:) ->
            Ok(creature.TargetMoved(by: connection, place:, seq:, stay:))
          client_connection.TellStrikeAnswered(answered:) ->
            Ok(creature.StrikeAnswered(answered:))
          AskStore(..)
          | AskHandOff(..)
          | AskSessions(..)
          | AskMap(..)
          | AskMapRun(..)
          | TellMoved(..)
          | client_connection.TellReady(..)
          | client_connection.TellStealthChanged(..)
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
  let assert [timer] =
    list.filter_map(support.effects_of(taken), fn(effect) {
      case effect {
        OwnEffect(step.StartServiceTimer(timer:, after_ms: 1500)) -> Ok(timer)
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          Error(Nil)
      }
    })
    as "the step starts the next attack tick"
  timer
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
  let assert [home] =
    game_connection_support.decoded(leash, 0x0638, unit_movement.decode)
  let assert [_, relayed_movement.Path(path)] = home.commands
  let assert [_, end] = path.points
  assert end
    == MovementFloatVector(
      x: float32.to_bits(29.128599166870117),
      y: float32.to_bits(-853.87158203125),
      z: float32.to_bits(-563.18798828125),
    )
    as "the path home ends at the Beast's spawn"
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
      UnitDeathState(unit_id: medic_unit, dead: 1, field_3: 0, field_4: 0),
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

/// Paralytic Surge pressed, cast after cast, each strike delivered to the creature
/// and its answer and news back, until the client is written the creature's 0x88c:
/// the connection and the creature after.
fn presses_until_the_beast_dies(
  player player: game_connection.State,
  beast beast: creature.State,
  client_cast_id client_cast_id: Int,
) -> #(game_connection.State, creature.State) {
  assert client_cast_id < 40
    as "Paralytic Surge kills the Beast's 52 health in a few casts"
  let #(player, pressed) =
    game_connection_support.press_paralytic_surge(
      state: player,
      client_cast_id:,
    )
  let #(beast, steps) =
    beast_takes(state: beast, at_ms: 1100, messages: to_the_beast(pressed))
  let #(player, frames, _) =
    medic_takes(player, list.flat_map(steps, to_the_medic))
  case
    list.contains(
      game_connection_support.decoded(frames, 0x088C, unit_death_state.decode),
      UnitDeathState(unit_id: 7, dead: 1, field_3: 0, field_4: 0),
    )
  {
    True -> #(player, beast)
    False ->
      presses_until_the_beast_dies(
        player:,
        beast:,
        client_cast_id: client_cast_id + 1,
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
    presses_until_the_beast_dies(player: medic, beast:, client_cast_id: 1)
  let #(_, respawned) =
    fire_beast(state: beast, at_ms: 61_100, timer: TimerId(1))
  let #(_, frames, _) = medic_takes(medic, to_the_medic(respawned))
  assert list.take(cast_support.ids(frames:), 2) == [0x0355, 0x0262]
    && game_connection_support.decoded(frames, 0x0355, unit_destroyed.decode)
    == [UnitDestroyed(unit_id: 7, field_2: 0)]
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
    == game_client.world_entry_ids
    as "the Spellslinger comes back at the Holocrypt: the entry burst"
}
