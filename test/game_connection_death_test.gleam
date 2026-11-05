//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover a player's death
//// and coming back.

import cast_support
import character_tables
import connection_rule_support as support
import game_client
import game_connection_support.{Appears}
import genesis_prime/client_connection.{
  type News, type Request, Appeared, AskMap, AskStore, FromMap, PeerNews,
  TellMoved,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell
import genesis_prime/message/cast_result
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/combat_log.{CombatLog}
import genesis_prime/message/combat_log_death.{CombatLogDeath}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_log_resurrect.{CombatLogResurrect}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/enter_world
import genesis_prime/message/float32
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/resurrection_window.{ResurrectionWindow}
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_finished
import genesis_prime/message/start_movement
import genesis_prime/message/unit_combat_state.{UnitCombatState}
import genesis_prime/message/unit_create_ghost
import genesis_prime/message/unit_death_state.{UnitDeathState}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/step.{
  type ConnectionStep, ConnectionId, LogError, LogWarning, Map, NoAnswerInTime,
  OwnEffect, Unwatch, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{AccountId, ListCharacters, Select}
import genesis_prime/world_map/map.{Join, Left, SeenBy}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{None}
import map_support
import owned_test

// ------------------------------------------- a player's death and coming back
//
// Expected values come from the design of step G (the Design artifact of issue
// 368, its test list and failure table, and its shape review) and these places:
// 0x88c (unit, dead, 0, 0) (`opcode.0x88c`); death leaves the combat flag, so 0x89a
// (P, 0) follows (`death.combat_flag`); 0x247 of type 22 or 23 with the unit
// (`opcode.0x247.death`); the ghost's 0x262 of type 23 with the character's id,
// realm, name, race, class and gender, at the body's place, carrying no stat
// (`0x140096970`, `opcode.0x262.ghost`); 0x1b3's fields in wire order: the ghost,
// cost, penalty, dead, the choices, the caster bit, the cooldown and the forced
// release (`opcode.0x1b3`), with the server's choices 0 and Wake Here and Holocrypt
// (`death.server_choices`, `death.window`, `lua.GameLib.RezType`); 0x636 (0, reset
// 1, unit) (`opcode.0x636`); 0x15a (unit, choice, value) (`opcode.0x15a`); 57
// Caster_CannotBeDead for a press of a spell whose caster row has the dead bit,
// Paralytic Surge's row 43 among them (`cast.dead_player`,
// `Spell4.spell4ConditionsIdCaster`); the ghost's 0x637 needs no answer
// (`ghost.movement`); a player created with health 0 is created dead
// (`0x140457bc5`); 0xAD starts a move to another place and the entry burst follows
// (`0x1403b6de0`). The ghost's id is the map's unit id limit, 2^20, plus the
// player's unit id, and the Holocrypt place is the start of the character's race
// and faction in its world (the server's choices). A level-1 Engineer has 736
// health and a shield of 450 (`player.level1_base_health`,
// `player.level1_gear_properties`).

/// The tests' player's ghost: 2^20 + 5.
const ghost_unit_id = 1_048_581

/// The news a step tells viewer `viewer`, in order.
fn news_told(taken: ConnectionStep(Request), viewer: Int) -> List(News) {
  list.filter_map(game_connection_support.peer_tells(taken), fn(tell) {
    case tell.0 == viewer {
      True -> Ok({ tell.1 }.news)
      False -> Error(Nil)
    }
  })
}

pub fn a_player_struck_to_0_dies_with_0x88c_0x89a_off_and_0x247_type_22_then_sees_its_ghost_the_window_and_control_of_the_ghost_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = game_connection_support.dead_in_world()
  let frames =
    game_connection_support.heard(taken, game_connection_support.keyed())
  assert cast_support.ids(frames:)
    == [0x0938, 0x092F, 0x088C, 0x089A, 0x0247, 0x0262, 0x01B3, 0x0636]
    as "the shield and the health at 0, then 0x88c, 0x89a, 0x247, the ghost's 0x262, 0x1b3 and 0x636, in that order"
  assert game_connection_support.decoded(
      frames,
      0x088C,
      unit_death_state.decode,
    )
    == [
      UnitDeathState(
        unit_id: game_connection_support.own_unit_id,
        dead: 1,
        field_3: 0,
        field_4: 0,
      ),
    ]
    as "0x88c: the player's unit is dead; the 5-bit and the 32-bit values 0"
  assert game_connection_support.decoded(
      frames,
      0x089A,
      unit_combat_state.decode,
    )
    == [
      UnitCombatState(
        unit_id: game_connection_support.own_unit_id,
        in_combat: 0,
      ),
    ]
    as "0x89a (P, 0): death does not take a unit out of combat in the client"
  assert game_connection_support.decoded(frames, 0x0247, combat_log.decode)
    == [
      CombatLog(
        entry: combat_log_entry.Death(CombatLogDeath(
          game_connection_support.own_unit_id,
        )),
      ),
    ]
    as "0x247 of type 22 for the player"
  let assert [ghost] =
    game_connection_support.decoded(frames, 0x0262, unit_create_ghost.decode)
    as "the ghost's 0x262 is of type 23"
  assert ghost.unit_id == ghost_unit_id
    && ghost.character_id == 42
    && ghost.realm_id == 5
    && ghost.name == "Ab Cd"
    && ghost.race_id == 1
    && ghost.class_id == 2
    && ghost.gender == 0
    && ghost.title_id == 0
    as "the character's id, the realm's id 5, its name, race, class, gender, and title 0: the tests' character has none (opcode.0x262.ghost, its last value; 0 is no CharacterTitle row)"
  assert ghost.tail.stats == [] as "the client reads no stat of a ghost"
  let assert [start_movement.Position(at), start_movement.Rotation(_)] =
    ghost.tail.movement_commands
    as "a position and a rotation, as the player's own 0x262 starts"
  let body = game_connection_support.entry_place()
  assert at.x == float32.to_bits(start_place.x(body))
    && at.y == float32.to_bits(start_place.y(body))
    && at.z == float32.to_bits(start_place.z(body))
    as "at the body's place: where the player stood when it fell"
  assert game_connection_support.decoded(
      frames,
      0x01B3,
      resurrection_window.decode,
    )
    == [
      ResurrectionWindow(
        ghost_unit_id:,
        wake_here_cost: 0,
        death_penalty_ms: 0,
        dead: 1,
        choices: 3,
        caster_asked: 0,
        wake_here_cooldown_ms: 0,
        forced_release_ms: 0,
      ),
    ]
    as "the window: the ghost, no cost, penalty, cooldown or forced release, dead, Wake Here and Holocrypt"
  assert game_connection_support.decoded(
      frames,
      0x0636,
      client_control_granted.decode,
    )
    == [
      ClientControlGranted(
        echo_value: 0,
        reset_movement: 1,
        unit_id: ghost_unit_id,
      ),
    ]
    as "the ghost's movement to the client"
  let assert [
    client_connection.Shield(..),
    client_connection.Health(health: 0, dead: True),
    client_connection.Died,
    client_connection.CombatState(in_combat: False),
    client_connection.DeathLogged,
  ] = news_told(taken, 2)
    as "the viewer is told the body's death, 0x89a off and the log line, and no ghost"
  Nil
}

pub fn a_viewer_writes_a_players_death_and_coming_back_for_a_unit_it_shows_and_nothing_for_one_it_does_not_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let written = fn(news) {
    game_connection_support.heard(
      game_connection_support.feed(
        shown,
        game_connection_support.sent_by_a_peer(game_connection_support.news_of(
          unit_id: 9,
          news:,
        )),
      ).1,
      game_connection_support.keyed(),
    )
  }
  assert game_connection_support.decoded(
      written(client_connection.Died),
      0x088C,
      unit_death_state.decode,
    )
    == [UnitDeathState(unit_id: 9, dead: 1, field_3: 0, field_4: 0)]
  assert game_connection_support.decoded(
      written(client_connection.CameBack),
      0x088C,
      unit_death_state.decode,
    )
    == [UnitDeathState(unit_id: 9, dead: 0, field_3: 0, field_4: 0)]
    as "0x88c dead 0: the unit stands again"
  assert game_connection_support.decoded(
      written(client_connection.DeathLogged),
      0x0247,
      combat_log.decode,
    )
    == [CombatLog(entry: combat_log_entry.Death(CombatLogDeath(9)))]
  assert game_connection_support.decoded(
      written(client_connection.CameBackLogged),
      0x0247,
      combat_log.decode,
    )
    == [CombatLog(entry: combat_log_entry.Resurrect(CombatLogResurrect(9)))]
  list.each(
    [
      client_connection.Died,
      client_connection.CameBack,
      client_connection.DeathLogged,
      client_connection.CameBackLogged,
    ],
    fn(news) {
      let #(_, taken) =
        game_connection_support.feed(
          game_connection_support.in_world(),
          game_connection_support.sent_by_a_peer(
            game_connection_support.news_of(unit_id: 9, news:),
          ),
        )
      assert support.writes(taken) == []
        as "a unit the client does not show is written nothing"
    },
  )
}

pub fn a_viewer_writes_a_players_death_and_coming_back_as_the_clients_frames_test() -> Nil {
  use <- owned_test.run(10_000)
  // The news a dying player's connection tells its viewer, and then its coming
  // back's, reach a viewer that shows the player as unit 9.
  let #(state, died) = game_connection_support.dead_in_world()
  let #(_, woke) =
    game_connection_support.read(state, game_connection_support.wake_here())
  let #(shown, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.event_of(Appears),
    )
  let written = fn(news: List(News)) {
    let #(_, frames) =
      list.fold(news, #(shown, []), fn(held, news) {
        let #(viewer, frames) = held
        let #(viewer, taken) =
          game_connection_support.feed(
            viewer,
            game_connection_support.sent_by_a_peer(
              game_connection_support.news_of(unit_id: 9, news:),
            ),
          )
        #(
          viewer,
          list.append(
            frames,
            game_connection_support.heard(
              taken,
              game_connection_support.keyed(),
            ),
          ),
        )
      })
    frames
  }
  let death = written(news_told(died, 2))
  assert cast_support.ids(frames: death)
    == [0x0938, 0x0937, 0x088C, 0x089A, 0x0247]
    as "the shield and the health, then 0x88c, 0x89a and 0x247, in the order told"
  assert game_connection_support.decoded(death, 0x088C, unit_death_state.decode)
    == [UnitDeathState(unit_id: 9, dead: 1, field_3: 0, field_4: 0)]
    as "opcode.0x88c: the unit dead"
  assert game_connection_support.decoded(
      death,
      0x089A,
      unit_combat_state.decode,
    )
    == [UnitCombatState(unit_id: 9, in_combat: 0)]
    as "opcode.0x89a: out of combat (death.combat_flag)"
  assert game_connection_support.decoded(death, 0x0247, combat_log.decode)
    == [CombatLog(entry: combat_log_entry.Death(CombatLogDeath(9)))]
    as "opcode.0x247.death: type 22"
  let back = written(news_told(woke, 2))
  assert cast_support.ids(frames: back) == [0x0937, 0x0938, 0x088C, 0x0247]
  assert game_connection_support.decoded(back, 0x0937, unit_health.decode)
    == [UnitHealth(unit_id: 9, health: 736, dead: 0)]
    as "full health, 736 (player.level1_base_health)"
  assert game_connection_support.decoded(back, 0x0938, unit_stat_changed.decode)
    == [UnitStatChanged(unit_id: 9, value: 450)]
    as "the full shield, 450 (player.level1_gear_properties)"
  assert game_connection_support.decoded(back, 0x088C, unit_death_state.decode)
    == [UnitDeathState(unit_id: 9, dead: 0, field_3: 0, field_4: 0)]
  assert game_connection_support.decoded(back, 0x0247, combat_log.decode)
    == [CombatLog(entry: combat_log_entry.Resurrect(CombatLogResurrect(9)))]
    as "opcode.0x247.death: type 23"
}

pub fn a_creatures_killing_strike_on_a_player_mid_cast_ends_the_cast_with_0x7fe_to_it_and_every_viewer_told_its_start_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.watched_by(
      game_connection_support.medic_in_world(),
      [2],
    )
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, pressed) =
    game_connection_support.press_paralytic_surge(state:, client_cast_id: 1)
  let assert [client_connection.CastStarted(start:)] = news_told(pressed, 2)
    as "the viewer is told the cast's start; its round waits on the Beast's answer"
  let assert [#(40, key)] = game_connection_support.strikes_told(pressed)
  let #(state, taken) = game_connection_support.killed(state)
  assert list.contains(
    game_connection_support.decoded(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      0x07FE,
      spell_finished.decode,
    ),
    spell_finished.SpellFinished(cast_id: start.cast_id),
  )
    as "the client does not end its own casts when it dies: the server's 0x7fe ends the live cast"
  assert list.contains(
    news_told(taken, 2),
    client_connection.CastFinished(cast_id: start.cast_id),
  )
    as "and the viewer told its start is told its finish"
  let #(_, late) =
    game_connection_support.feed(state, game_connection_support.landed(key:))
  assert !list.contains(game_connection_support.written_ids(late), 0x07F4)
    as "the round that closes after the death has no go: the cast is over"
}

pub fn a_dead_players_press_of_an_ability_with_the_dead_bit_is_refused_57_and_strikes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.medic_in_world(),
      game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, _) = game_connection_support.killed(state)
  let #(_, taken) =
    game_connection_support.press_paralytic_surge(state:, client_cast_id: 2)
  let assert [Frame(message_id: 0x07FC, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "one 0x7fc"
  let assert Ok(refused) = spell_cast_refused.decode(body)
  assert refused.result == cast_result.CasterCannotBeDead
    as "57 Caster_CannotBeDead: Paralytic Surge's caster row 43 has the dead bit"
  assert game_connection_support.strikes_told(taken) == []
    && !support.stops(taken)
}

pub fn a_dead_players_press_of_an_ability_without_the_dead_bit_is_taken_as_the_livings_test() -> Nil {
  use <- owned_test.run(60_000)
  // A test whose first use loads a set of planted tables of its own: the
  // deadline is a hang guard, the load alone can take most of 10 s.
  // The client checks only bit 0 of the caster row: without it, it sends the
  // press of a dead caster (cast.dead_player); the planted row 43 lacks it.
  let living =
    game_connection_support.medic_with_beast_in_world(
      character_tables.shared_with_row_43_for_the_dead(),
    )
  let #(dead, _) = game_connection_support.killed(living)
  let #(_, alive_press) =
    game_connection_support.press_paralytic_surge(
      state: living,
      client_cast_id: 2,
    )
  let #(_, dead_press) =
    game_connection_support.press_paralytic_surge(
      state: dead,
      client_cast_id: 2,
    )
  assert game_connection_support.written_ids(alive_press) != [0x07FC]
    && list.length(game_connection_support.strikes_told(alive_press)) == 1
    as "the living Medic's press starts the cast and strikes the Beast"
  assert game_connection_support.written_ids(dead_press)
    == game_connection_support.written_ids(alive_press)
    && game_connection_support.strikes_told(dead_press)
    == game_connection_support.strikes_told(alive_press)
    as "the dead Medic's press is taken as the living's: the same frames, the same strike"
}

pub fn a_strike_on_a_dead_player_is_refused_dead_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.a_beast_strike(
        game_connection_support.own_unit_id,
      ),
    )
  assert support.writes(taken) == []
    && game_connection_support.peer_tells(taken) == []
  let assert [
    #(
      7,
      client_connection.TellStrikeAnswered(answered: strike_tell.Answered(
        outcome: strike_tell.Refused(why: strike_tell.Dead),
        ..,
      )),
    ),
  ] = game_connection_support.told_creatures(taken)
    as "the creature's strike that reaches the player after its death is refused Dead"
  Nil
}

pub fn while_dead_every_0x637_is_dropped_and_after_coming_back_a_move_moves_the_body_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  // The ghost runs far from the body.
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.moves_message([
        game_client.position_command(x: 500.0, y: 300.0, z: 500.0),
      ]),
    )
  assert support.effects_of(taken) == []
    as "nothing to the map, the viewers or the fighters, nothing written, nothing refused: the client expects no answer to the ghost's moves"
  let #(_, malformed) =
    game_connection_support.read(
      state,
      game_connection_support.world_message(0x0637, <<>>),
    )
  let assert [line] = support.logs_of(step: malformed, level: LogError)
    as "a body the client's reader would refuse ends the connection, as for the living"
  assert support.says(line:, words: "does not decode")
    && game_connection_support.ask_request(malformed)
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: None,
    )
    as "a dead player's save keeps no health (death.server_choices); the body's place is saved before the end: where it fell"
  let #(state, _) =
    game_connection_support.read(state, game_connection_support.wake_here())
  let #(_, moved) =
    game_connection_support.read(state, game_connection_support.a_move(1.5))
  assert game_connection_support.moves_told(moved) == [1]
    && game_connection_support.told_the_map(moved)
    == [
      OwnEffect(step.Tell(
        to: Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
        request: TellMoved(
          connection: ConnectionId(1),
          place: game_connection_support.standing_at(x: 1.5, y: 2.5, z: 3.5),
          seq: 1,
        ),
      )),
    ]
    as "the body moves again, and the dropped moves took no sequence number"
}

pub fn a_ghosts_0x637_the_clients_code_never_sends_ends_the_connection_after_saving_where_the_body_lies_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client writes the ghost's moves as it writes the body's
  // (`ghost.movement`, `opcode.0x637`), so it never sends one the body's
  // movement refuses.
  let #(dead, _) = game_connection_support.dead_in_world()
  list.each(game_connection_support.refused_moves(), fn(refused) {
    let #(bytes, what) = refused
    let #(_, taken) = game_connection_support.read(dead, bytes)
    let assert [_] = support.logs_of(step: taken, level: LogError)
      as { what <> ": one error line says what the client sent" }
    assert game_connection_support.ask_request(taken)
      == game_connection_support.save_asked_keeping(
        sequence: 1,
        place: game_connection_support.entry_place(),
        health: None,
      )
      && support.writes(taken) == []
      as {
        what
        <> ": the place the body lies at is saved with no health (death.server_choices), nothing written"
      }
  })
}

pub fn a_0x15a_the_rule_refuses_writes_nothing_and_logs_a_warning_and_one_the_clients_reader_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(dead, _) = game_connection_support.dead_in_world()
  list.each(
    [
      #(
        dead,
        game_connection_support.choice_message(unit_id: 9, choice: 1, value: 0),
      ),
      #(
        dead,
        game_connection_support.choice_message(
          unit_id: ghost_unit_id,
          choice: 1,
          value: 0,
        ),
      ),
      #(
        dead,
        game_connection_support.choice_message(
          unit_id: game_connection_support.own_unit_id,
          choice: 4,
          value: 0,
        ),
      ),
      #(
        dead,
        game_connection_support.choice_message(
          unit_id: game_connection_support.own_unit_id,
          choice: 32,
          value: 0,
        ),
      ),
      #(
        dead,
        game_connection_support.choice_message(
          unit_id: game_connection_support.own_unit_id,
          choice: 1,
          value: 5,
        ),
      ),
      #(game_connection_support.in_world(), game_connection_support.wake_here()),
    ],
    fn(case_) {
      let #(_, taken) = game_connection_support.read(case_.0, case_.1)
      assert support.effects_of(taken)
        |> list.filter(fn(effect) {
          case effect {
            step.Log(..) -> False
            OwnEffect(_) | Watch(..) | Unwatch(..) | step.Stop -> True
          }
        })
        == []
        as "another unit, the ghost, a choice not offered, a nonzero value, the living: nothing changes"
      assert list.length(support.logs_of(step: taken, level: LogWarning)) == 1
        as "a warning names the refusal"
    },
  )
  let #(_, malformed) =
    game_connection_support.read(
      dead,
      game_connection_support.world_message(0x015A, <<>>),
    )
  let assert [line] = support.logs_of(step: malformed, level: LogError)
    as "a body the client's reader would refuse ends the connection"
  assert support.says(line:, words: "does not decode")
    && game_connection_support.ask_request(malformed)
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: None,
    )
    as "a dead player's save keeps no health (death.server_choices); after the save of the place, as any end in the world"
}

pub fn a_second_choice_is_refused_unchanged_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  let #(state, _) =
    game_connection_support.read(state, game_connection_support.wake_here())
  let #(_, second) =
    game_connection_support.read(state, game_connection_support.holocrypt())
  assert support.writes(second) == []
    && support.asked(second) == None
    && list.length(support.logs_of(step: second, level: LogWarning)) == 1
    as "the first choice brought the player back: the second finds it alive and is refused with a warning"
}

pub fn wake_here_writes_the_coming_back_in_the_clients_order_where_the_body_lies_and_a_later_strike_lands_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.wake_here())
  let frames =
    game_connection_support.heard(taken, game_connection_support.keyed())
  assert list.map(frames, fn(frame) { frame.message_id })
    == [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247]
    as "0x92f full, the shield, 0x88c (P, 0), 0x1b3 dead 0, the ghost's 0x355, 0x636 for the body, 0x247 type 23, in that order"
  assert game_connection_support.decoded(frames, 0x092F, player_health.decode)
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: 736,
        reason_mask: 0,
      ),
    ]
    as "full health"
  assert game_connection_support.decoded(
      frames,
      0x0938,
      unit_stat_changed.decode,
    )
    == [
      UnitStatChanged(unit_id: game_connection_support.own_unit_id, value: 450),
    ]
    as "the full shield"
  assert game_connection_support.decoded(
      frames,
      0x088C,
      unit_death_state.decode,
    )
    == [
      UnitDeathState(
        unit_id: game_connection_support.own_unit_id,
        dead: 0,
        field_3: 0,
        field_4: 0,
      ),
    ]
  assert game_connection_support.decoded(
      frames,
      0x01B3,
      resurrection_window.decode,
    )
    == [
      ResurrectionWindow(
        ghost_unit_id:,
        wake_here_cost: 0,
        death_penalty_ms: 0,
        dead: 0,
        choices: 3,
        caster_asked: 0,
        wake_here_cooldown_ms: 0,
        forced_release_ms: 0,
      ),
    ]
  assert game_connection_support.decoded(frames, 0x0355, unit_destroyed.decode)
    == [UnitDestroyed(unit_id: ghost_unit_id, field_2: 0)]
  assert game_connection_support.decoded(
      frames,
      0x0636,
      client_control_granted.decode,
    )
    == [
      ClientControlGranted(
        echo_value: 0,
        reset_movement: 1,
        unit_id: game_connection_support.own_unit_id,
      ),
    ]
  assert game_connection_support.decoded(frames, 0x0247, combat_log.decode)
    == [
      CombatLog(
        entry: combat_log_entry.Resurrect(CombatLogResurrect(
          game_connection_support.own_unit_id,
        )),
      ),
    ]
  assert news_told(taken, 2)
    == [
      client_connection.Health(health: 736, dead: False),
      client_connection.Shield(shield: 450),
      client_connection.CameBack,
      client_connection.CameBackLogged,
    ]
    as "the viewer is told the body's full health and shield, its coming back and the log line"
  let #(_, struck) =
    game_connection_support.feed(
      state,
      game_connection_support.a_beast_strike(
        game_connection_support.own_unit_id,
      ),
    )
  assert game_connection_support.decoded(
      game_connection_support.heard(struck, game_connection_support.keyed()),
      0x092F,
      player_health.decode,
    )
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: 735,
        reason_mask: 0,
      ),
    ]
    as "a later strike lands: the Beast's 12 mitigated to 3, 1 of it to health"
}

pub fn the_holocrypt_comes_back_as_wake_here_then_leaves_the_map_and_joins_at_the_start_of_the_race_and_faction_in_its_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, chosen) = game_connection_support.holocrypt_chosen()
  assert game_connection_support.written_ids(chosen)
    == [0x092F, 0x0938, 0x088C, 0x01B3, 0x0355, 0x0636, 0x0247]
    as "the coming back as Wake Here writes it, where the body lies"
  assert news_told(chosen, 2)
    == [
      client_connection.Health(health: 736, dead: False),
      client_connection.Shield(shield: 450),
      client_connection.CameBack,
      client_connection.CameBackLogged,
      client_connection.Removed,
    ]
    as "the old viewers are told the coming back, then the unit's 0x355"
  assert game_connection_support.ask_request(chosen)
    == game_connection_support.leave_asked()
    as "the run of the map is asked to take the player out"
  let #(_, joining) = game_connection_support.holocrypt_joining()
  assert list.contains(support.effects_of(joining), Unwatch(watch: WatchId(2)))
    as "the old map's watch is dropped"
  let start = character_tables.novice_start_place()
  assert game_connection_support.ask_request(joining)
    == AskMap(
      map: MapId(world_id: 3460, instance: 0),
      message: Join(
        connection: ConnectionId(1),
        character: game_connection_support.world_character(),
        place: start,
        stay: map_support.stay(count: 2),
      ),
    )
    as "a Dominion Cassian in World 3460: the Novice start's row 51596 is that world's start of its race and faction"
  let #(state, taken) = game_connection_support.at_the_holocrypt()
  assert game_connection_support.written_ids(taken)
    == game_client.world_entry_ids
    as "the entry burst, 0xAD first: the client removes every unit and loads again (0x1403b6de0)"
  let assert [entered] =
    game_connection_support.decoded(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      0x00AD,
      enter_world.decode,
    )
  assert entered.world_id == 3460
    && entered.position_x == float32.to_bits(start_place.x(start))
    && entered.position_y == float32.to_bits(start_place.y(start))
    && entered.position_z == float32.to_bits(start_place.z(start))
    as "0xAD at the Holocrypt place"
  assert game_connection_support.player_in(taken).unit_id == 6
    as "a new unit of the map's"
  assert support.watches(taken)
    == [
      #(
        WatchId(2),
        Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
      ),
    ]
    as "the map that took it is watched"
  let #(_, watched) =
    game_connection_support.feed(
      state,
      game_connection_support.in_second_stay(
        game_connection_support.sent_by_the_map(SeenBy(
          by: ConnectionId(3),
          stay: game_connection_support.viewer_stay(3),
        )),
      ),
    )
  let assert [#(3, stay, PeerNews(news: Appeared(unit:), unit_id: 6))] =
    game_connection_support.peer_tells_for(watched)
  assert stay == game_connection_support.viewer_stay(3)
    as "for the stay of the viewer the map named"
  let assert [start_movement.Position(at), _] = unit.tail.movement_commands
  assert at.x == float32.to_bits(start_place.x(start))
    && at.z == float32.to_bits(start_place.z(start))
    as "a viewer at the start place is sent the player's 0x262 there"
}

pub fn what_the_dead_client_sends_during_the_holocrypts_leave_and_join_is_taken_as_from_the_dead_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client is in the world as a ghost until the join's 0xAD: it moves its
  // ghost and may choose again. Those frames wait in the bytes read while the
  // leave and the join are asked, and are taken after the join's answer. The
  // ghost has run far from the body and from the Holocrypt.
  let #(state, _) = game_connection_support.dead_in_world()
  let ghost_move =
    game_connection_support.moves_message([
      game_client.position_command(x: 500.0, y: 2.5, z: 500.0),
    ])
  let #(state, chosen) =
    game_connection_support.read(state, <<
      game_connection_support.holocrypt():bits,
      ghost_move:bits,
      game_connection_support.holocrypt():bits,
    >>)
  assert game_connection_support.ask_request(chosen)
    == game_connection_support.leave_asked()
  let #(state, joining) =
    game_connection_support.answer(
      state:,
      taken: chosen,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(_, joined) =
    game_connection_support.mapped(
      map_state: game_connection_support.map_after_a_stay(),
      taken: joining,
    )
  let #(state, burst) =
    game_connection_support.answer(
      state:,
      taken: joining,
      outcome: step.Answer(FromMap(joined)),
    )
  assert !support.stops(burst)
    && support.asked(burst) == None
    && support.logs_of(step: burst, level: LogError) == []
    as "nothing the client may send while dead ends the connection"
  assert game_connection_support.written_ids(burst)
    == game_client.world_entry_ids
    && game_connection_support.moves_told(burst) == []
    as "the ghost's move is dropped, as every 0x637 while dead: the body stands at the Holocrypt"
  assert list.length(support.logs_of(step: burst, level: LogWarning)) == 1
    as "the second choice is refused unchanged, with a warning"
  let #(state, late) = game_connection_support.read(state, ghost_move)
  assert game_connection_support.moves_told(late) == []
    && support.logs(late) == []
    as "a ghost's move that reaches the server after the burst is dropped too, until the client has loaded the world"
  let #(state, _) =
    game_connection_support.read(
      state,
      game_connection_support.terrain_loaded_message(6009),
    )
  let #(_, moved) =
    game_connection_support.read(state, game_connection_support.a_move(1.5))
  assert game_connection_support.moves_told(moved) == [1]
    as "after the stay's first 0xF2 a move moves the body, the first numbered since the dead dropped none"
}

pub fn the_holocrypt_of_a_world_with_no_start_of_the_race_and_faction_is_the_place_the_stay_entered_at_test() -> Nil {
  use <- owned_test.run(60_000)
  // A test whose first use loads a set of planted tables of its own: the
  // deadline is a hang guard, the load alone can take most of 10 s.
  // The planted Novice start of the tests' race and faction stands in World 0
  // here, so World 3460 holds none: the server's choice is the place the stay
  // entered at (death.server_choices).
  let fresh =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        tables: character_tables.shared_with_novice_start_in_world_0(),
      ),
    ).0
  assert game_connection_support.entry_place()
    != character_tables.novice_start_place()
    as "the place the stay entered at is not the Novice start"
  let #(state, _) =
    game_connection_support.entered_from(
      game_connection_support.in_select_from(fresh),
      game_connection_support.world_character(),
    )
  let #(state, _) =
    game_connection_support.killed(
      game_connection_support.watched_by(state, [2]),
    )
  let #(state, chosen) =
    game_connection_support.read(state, game_connection_support.holocrypt())
  let #(_, joining) =
    game_connection_support.answer(
      state:,
      taken: chosen,
      outcome: step.Answer(FromMap(Left)),
    )
  assert game_connection_support.ask_request(joining)
    == AskMap(
      map: game_connection_support.camp_map(),
      message: Join(
        connection: ConnectionId(1),
        character: game_connection_support.world_character(),
        place: game_connection_support.entry_place(),
        stay: map_support.stay(count: 2),
      ),
    )
}

pub fn the_map_ending_while_the_player_is_dead_saves_where_the_body_lies_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  let #(state, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(2)))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked_keeping(
      sequence: 1,
      place: game_connection_support.entry_place(),
      health: None,
    )
    as "a dead player's save keeps no health (death.server_choices); the body's place: where it fell"
  assert support.writes(taken) == [] && !support.stops(taken)
  let #(_, ended) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      ended,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "the player is gone from the world with its map, dead or not: 0x036A reason 8"
}

pub fn a_holocrypt_leave_with_no_answer_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.holocrypt_chosen()
  let #(_, ended) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      ended,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "as the camp's leave: 0x036A reason 8 and the end"
}

pub fn a_refused_holocrypt_join_returns_to_character_select_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.holocrypt_joining()
  let #(state, refused) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromMap(map.NotJoined(reason: map.NoBaseHealth(level: 1))),
      ),
    )
  assert game_connection_support.written_ids(refused) == [0x0594]
    as "the player is in no map: 0x0594 puts the client in character select, as the camp's leave does"
  assert list.length(support.logs_of(step: refused, level: LogWarning)) == 1
  let #(_, listing) =
    game_connection_support.read(state, game_connection_support.select_start())
  assert game_connection_support.ask_request(listing)
    == AskStore(Select(ListCharacters(AccountId(7))))
    as "a new character select takes the client's 0x07E0"
}

pub fn a_holocrypt_join_with_no_answer_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.holocrypt_joining()
  let #(_, ended) =
    game_connection_support.answer(state:, taken:, outcome: NoAnswerInTime)
  assert game_connection_support.disconnect(
      ended,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "as a play's join: 0x036A reason 8 and the end"
}

pub fn a_viewer_that_arrives_while_the_player_is_dead_gets_its_0x262_with_health_0_and_no_ghost_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(3),
        stay: game_connection_support.viewer_stay(3),
      )),
    )
  let assert [#(3, PeerNews(news: Appeared(unit:), unit_id:))] =
    game_connection_support.peer_tells(taken)
  assert unit_id == game_connection_support.own_unit_id
    as "the body, not the ghost"
  assert list.contains(
    unit.tail.stats,
    unit_fields.integer_stat(stat_id: 0, value: 0),
  )
    as "stat 0, the health, is 0: the client creates the body dead"
}

pub fn a_viewer_that_arrives_after_a_hit_gets_the_players_shield_and_health_now_test() -> Nil {
  use <- owned_test.run(10_000)
  // The Beast's 12 is mitigated to 3: 2 from the shield of 450 and 1 from the
  // health of 736, as the strike tests above work them out.
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.a_beast_strike(
        game_connection_support.own_unit_id,
      ),
    )
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(3),
        stay: game_connection_support.viewer_stay(3),
      )),
    )
  let assert [#(3, PeerNews(news: Appeared(unit:), ..))] =
    game_connection_support.peer_tells(taken)
  assert list.contains(
    unit.tail.stats,
    unit_fields.integer_stat(stat_id: 20, value: 448),
  )
    as "stat 20, the shield, as the hit left it (opcode.0x938)"
  assert list.contains(
    unit.tail.stats,
    unit_fields.integer_stat(stat_id: 0, value: 735),
  )
    as "stat 0, the health, as the hit left it"
}

pub fn a_player_dead_at_camp_enters_again_alive_and_full_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = game_connection_support.dead_in_world()
  let #(again, entry) =
    game_connection_support.entered_from(
      game_connection_support.camp_from(state),
      game_connection_support.world_character(),
    )
  assert list.contains(
    game_connection_support.player_in(entry).tail.stats,
    unit_fields.integer_stat(stat_id: 0, value: 736),
  )
    as "the new entry's 0x262 carries full health"
  let #(_, struck) =
    game_connection_support.feed(
      again,
      game_connection_support.in_second_stay(
        game_connection_support.a_beast_strike(
          game_connection_support.own_unit_id,
        ),
      ),
    )
  assert game_connection_support.decoded(
      game_connection_support.heard(struck, game_connection_support.keyed()),
      0x0938,
      unit_stat_changed.decode,
    )
    == [
      UnitStatChanged(unit_id: game_connection_support.own_unit_id, value: 448),
    ]
    && game_connection_support.decoded(
      game_connection_support.heard(struck, game_connection_support.keyed()),
      0x092F,
      player_health.decode,
    )
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: 735,
        reason_mask: 0,
      ),
    ]
    as "alive and full: a strike lands on the full shield and health"
}
