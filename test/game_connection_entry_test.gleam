//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover entering the
//// world and the place the login puts the player at.
////
//// Expected values come from these places.
//// - World entry: the client's path from 0x07DD to control (the fact file's
////   opcode.0xad, opcode.0x262, opcode.0x19b, opcode.0x6bc, opcode.0x636,
////   opcode.0xf1 and opcode.0x61, and the order the client's handlers
////   need), the player's 0x262 against the client's own vector (vector.opcode.0x262.roxo_alive,
////   tested with `player_unit_test`), the saved place a WorldLocation2 row
////   gives (character_tables), the map's join in the rule's doc comment, the
////   failures every ask shares (reason 8), and 0x038C carrying one whole inner
////   frame (opcode.0x38c).

import character_support
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/account_session.{Claimed}
import genesis_prime/client_connection.{
  AskMap, AskStore, FromHandOff, FromMap, FromSessions, FromStore,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/start_place.{Facing}
import genesis_prime/hand_off.{Kept}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/player_entered_world
import genesis_prime/message/player_path.{PlayerPath}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/message/unit_stat_float.{UnitStatFloat}
import genesis_prime/message/unit_stat_value
import genesis_prime/step.{
  CancelTimer, ConnectionId, EndedBeforeAnswer, LogError, LogInfo, LogWarning,
  Map, NoAnswerInTime, NotRunning, OwnEffect, OwnEvent, Sessions, StartTimer,
  StoppedWaiting, TimerFired, TimerId, Unwatch, Watch, WatchEnded, WatchId,
}
import genesis_prime/store.{
  AccountId, Character, CharacterId, CharacterLoaded, ForSelect, ForWorld,
  Listed, LoadCharacter, NotTheAccounts, Unavailable, World,
}
import genesis_prime/world_map/map.{Join}
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/option.{None, Some}
import owned_test
import world_entry_support

// ---- entering the world ----

pub fn message_0x07dd_asks_the_store_for_the_character_then_the_map_and_the_answer_is_0xad_0x262_0x19b_0x6bc_0x636_0xf1_0x61_in_the_clients_order_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.playing(42)
  assert game_connection_support.ask_request(taken)
    == AskStore(World(LoadCharacter(AccountId(7), CharacterId(42))))
    as "opcode.0x7dd: the character's id, and the holder's account, which scopes the read"
  let assert Some(ask) = support.asked(taken)
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
  assert support.writes(taken) == []
    as "nothing is written before the store answers"
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromStore(
          ForWorld(CharacterLoaded(
            game_connection_support.world_character(),
            character_support.epoch(1),
            None,
            world_entry_support.novice_items(
              character: game_connection_support.world_character(),
            ),
          )),
        ),
      ),
    )
  assert game_connection_support.ask_request(taken)
    == AskMap(
      game_connection_support.camp_map(),
      Join(
        ConnectionId(1),
        game_connection_support.world_character(),
        game_connection_support.entry_place(),
        game_connection_support.own_stay(),
        True,
      ),
    )
    as "the saved world of the character, its one open instance, the connection's id, the character and the place the client is told"
  assert support.writes(taken) == []
    as "nothing is written before the map answers"
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(game_connection_support.map_answer(taken))),
    )
  assert game_client.without_passive_cast(
      ids: game_connection_support.written_ids(taken),
    )
    == game_client.world_entry_ids
    as "the order the client needs: 0xAD first; 0x262 before 0x19B; 0x19B before 0x6BC, 0x636 and 0x61 (the client drops 0x6BC until 0x19B has set the player, opcode.0x6bc); 0xF1 after 0xAD (opcode.0xad, opcode.0x19b, opcode.0x6bc, opcode.0x636, opcode.0x61, opcode.0xf1)"
  let after_the_burst =
    list.filter(list.drop(support.effects_of(taken), 7), fn(effect) {
      case effect {
        OwnEffect(step.Write(..)) -> False
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          True
      }
    })
  assert after_the_burst
    == [
      Watch(
        WatchId(2),
        Map(
          game_connection_support.camp_map(),
          game_connection_support.incarnation,
        ),
      ),
      OwnEffect(step.JoinGroup(step.CharacterNamed("ab cd"))),
      OwnEffect(step.JoinGroup(game_connection_support.zone_group(4961))),
      OwnEffect(StartTimer(TimerId(2), 60_000)),
    ]
    as "the connection watches the run of the map that holds its player, after the burst, joins its groups and the save timer starts"
  assert support.asked(taken) == None
  assert !support.stops(taken)
}

pub fn message_0xad_carries_the_saved_world_and_position_and_0_in_its_last_two_floats_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [Frame(message_id: 0x00AD, body:), ..] =
    game_connection_support.heard(
      game_connection_support.entered().1,
      game_connection_support.keyed(),
    )
  assert enter_world.decode(body)
    == Ok(EnterWorld(
      world_id: 3460,
      position_x: 0x41E9075F,
      position_y: 0xC45577C8,
      position_z: 0xC40C0C08,
      field_5: 0,
      field_6: 0,
    ))
    as "opcode.0xad: World 3460 and the position of WorldLocation2 row 51596 as 32-bit floats (29.1286, -853.8716 and -560.1880 are 0x41E9075F, 0xC45577C8 and 0xC40C0C08); the fourth and fifth floats are never read, 0.0 (opcode.0xad.last_floats)"
}

pub fn message_0x262_carries_the_characters_values_its_health_its_place_its_body_and_bones_its_class_resource_and_nothing_else_test() -> Nil {
  use <- owned_test.run(10_000)
  assert game_connection_support.player_in(game_connection_support.entered().1)
    == UnitCreatePlayer(
      unit_id: 5,
      character_id: 42,
      realm_id: 5,
      name: "Ab Cd",
      race_id: 1,
      class_id: 2,
      gender: 0,
      group_id: 0,
      owned_unit_ids: [],
      guild_name: "",
      guild_type: 0,
      guild_ids: [],
      bone_values: character_support.bones(48),
      pvp_flags: 0,
      premium_tier: 0,
      title_id: 0,
      tail: UnitCreateTail(
        create_flags: 0,
        stats: [
          unit_fields.integer_stat(stat_id: 0, value: 736),
          unit_fields.integer_stat(stat_id: 10, value: 1),
          unit_fields.integer_stat(stat_id: 20, value: 450),
          // The Engineer's Volatility, slot 1: stat 3 in the float form at 0.0, its
          // start (472510, opcode.0x262.resource_stats).
          UnitStat(
            stat_id: 3,
            value: unit_stat_value.Float(UnitStatFloat(value: 0)),
          ),
        ],
        server_time_estimate_start: 0,
        movement_commands: [
          start_movement.Position(UnitPositionCommand(
            x: 0x41E9075F,
            y: 0xC45577C8,
            z: 0xC40C0C08,
            blends: 0,
          )),
          start_movement.Rotation(MovementRotation(
            yaw: 0,
            pitch: 0,
            roll: 0,
            blends: 0,
          )),
        ],
        properties: [
          UnitProperty(property_id: 7, base: 0x44380000, value: 0x44380000),
          // ResourceMax_1 (UnitProperty2.ResourceMax_0) at 100.0, the Engineer's
          // maximum (the design: Tenton Hammer's Engineer guide).
          UnitProperty(property_id: 10, base: 0x42C80000, value: 0x42C80000),
          UnitProperty(property_id: 35, base: 0x434B1000, value: 0x434B1000),
          UnitProperty(property_id: 36, base: 0x425EC000, value: 0x425EC000),
          UnitProperty(property_id: 41, base: 0x43E10000, value: 0x43E10000),
          UnitProperty(property_id: 42, base: 0x437A0000, value: 0x437A0000),
          UnitProperty(property_id: 175, base: 0x3F200000, value: 0x3F200000),
          UnitProperty(property_id: 176, base: 0x3E19999A, value: 0x3E19999A),
          UnitProperty(property_id: 178, base: 0x45A02800, value: 0x45A02800),
        ],
        item_visuals: [
          ItemVisual(slot: 25, display_id: 137, item_color_set_id: 0, dye: 0),
          ItemVisual(slot: 1, display_id: 3842, item_color_set_id: 0, dye: 0),
          ItemVisual(slot: 2, display_id: 3844, item_color_set_id: 0, dye: 0),
          ItemVisual(slot: 4, display_id: 4179, item_color_set_id: 0, dye: 0),
          ItemVisual(slot: 5, display_id: 3845, item_color_set_id: 0, dye: 0),
          ItemVisual(slot: 6, display_id: 3843, item_color_set_id: 0, dye: 0),
          ItemVisual(slot: 20, display_id: 3409, item_color_set_id: 0, dye: 0),
        ],
        cast_id: 0,
        faction_id: 166,
        base_faction_id: 166,
        tagged_by_unit_id: 0,
        tagged_by_group_id: 0,
        field_14: 0,
        world_object_id: 0,
        world_socket_id: 0,
        cluster_id: 0,
        field_20: 0,
        minimap_marker_id: 0,
        display_info_id: 0,
        outfit_info_id: 0,
      ),
    )
    as "opcode.0x262: the unit id the map gave, the row's character id, the settings' realm id, name, race, class, gender, both factions 166 (vector.opcode.0x262.roxo: a base faction with a row, or 0x19B fails); stat 0 and property 7 are 736, CreatureLevel row 1's 135.97 and the Novice armor's 600 (player.level1_base_health; above 0 as the client's creation check needs, 0x140457bc5), stat 10 is the character's level 1 (0x140458140), and the Engineer's Novice set gives properties 35 and 36 (203.0625, 55.6875), 42 (250), 41 (450), 175, 176 and 178 (0.625, 0.15, 5125) and stat 20, a full shield (Item2.novice_set, player.level1_gear_properties); one kind 2 movement command at the saved position, which the client never moves to the ground after 0xAD (0x1403e828a); the body of the character list (CharacterCustomization row 10: display 137 on slot 25), then the Engineer of faction 166's Novice set worn: chest 3842 in slot 1, legs 3844 in 2, shoulder 4179 in 4, feet 3845 in 5, hands 3843 in 6 and the weapon 3409 in 20, with colour set 0 and dye 0 (opcode.0x262.worn_visuals, Item2.novice_visuals), and the stored bones; PvP flags 0, not the path 3 (0x1403b48b0); every other value is the client's no-value case (opcode.0x262.player_fields, opcode.0x262.unit_fields)"
}

pub fn message_0x19b_names_the_unit_0x6bc_gives_the_path_0x636_gives_control_of_it_0xf1_keeps_the_clients_interval_and_0x61_is_empty_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert [
    _,
    _,
    Frame(message_id: 0x019B, body: is_player),
    Frame(message_id: 0x025E, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x0111, ..),
    Frame(message_id: 0x01A0, ..),
    Frame(message_id: 0x019D, ..),
    Frame(message_id: 0x019F, ..),
    Frame(message_id: 0x06BC, body: path_body),
    Frame(message_id: 0x0636, body: control),
    Frame(message_id: 0x00F1, body: interval),
    Frame(message_id: 0x0061, body: entered_world),
    Frame(message_id: 0x01DA, ..),
    Frame(message_id: 0x01BC, ..),
  ] =
    game_connection_support.heard(
      game_connection_support.entered().1,
      game_connection_support.keyed(),
    )
    |> game_client.frames_without_passive_cast
  assert unit_is_player.decode(is_player)
    == Ok(UnitIsPlayer(unit_id: 5, field_2: 0))
    as "opcode.0x19b: the first value is the unit id the map gave, which must be the unit 0x262 created; the second is never read (opcode.0x19b.second_value)"
  assert player_path.decode(path_body)
    == Ok(PlayerPath(
      path: 3,
      soldier_experience: 0,
      settler_experience: 0,
      scientist_experience: 0,
      explorer_experience: 0,
      unlocked_paths: 8,
      last_path_change_days: 0xBF800000,
    ))
    as "opcode.0x6bc: the stored path 3 (Explorer); experience 0 on each path, which is path level 1 (PathLevel); only the character's own path unlocked, bit 3 is 8; -1.0 days (0xBF800000), so no path change cooldown is left (GameFormula 2366: 1800 seconds)"
  assert client_control_granted.decode(control)
    == Ok(ClientControlGranted(echo_value: 0, reset_movement: 1, unit_id: 5))
    as "vector.opcode.0x636.body: the value 0, the reset bit 1 and the unit id"
  assert movement_send_interval.decode(interval)
    == Ok(MovementSendInterval(
      world_difficulty: 0,
      world_prime_level: 0,
      world_flags: 0,
      interval_milliseconds: 125,
    ))
    as "opcode.0xf1.fields: Normal difficulty, prime level 0 and no flags for an open world; the interval 125 ms, the client's own until 0xF1 arrives (opcode.0xf1, 0x140c3a004; below 25 the client raises it to 25)"
  assert player_entered_world.decode(entered_world)
    == Ok(player_entered_world.PlayerEnteredWorld)
    as "opcode.0x61: the body is empty"
}

pub fn a_store_a_maps_or_a_map_that_gives_no_answer_ends_the_play_with_0x036a_reason_8_and_a_warning_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each([NoAnswerInTime, NotRunning, EndedBeforeAnswer], fn(outcome) {
    list.each(
      [
        #(game_connection_support.playing(42), "the store"),
        #(game_connection_support.joining(), "the map"),
      ],
      fn(asked) {
        let #(#(state, taken), who) = asked
        let #(_, taken) =
          game_connection_support.answer(state:, taken:, outcome:)
        assert game_connection_support.disconnect(
            taken,
            game_connection_support.keyed(),
          )
          == LostUserServer
          as "0x1400168a0 and opcode.0xad: the client waits for 0xAD or 0x162 with no timeout, so every failure ends with 0x036A, reason 8 for the server's own"
        let assert [line] = support.logs_of(step: taken, level: LogWarning)
          as "the failure is the server's: a warning"
        assert support.says(line, who) as "the line names the process"
        assert line.about.account_id == Some(7)
      },
    )
  })
  let #(state, taken) = game_connection_support.playing(42)
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(Unavailable)),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "a store that is unavailable"
  let assert [_] = support.logs_of(step: taken, level: LogWarning)
  list.each(
    [game_connection_support.playing(42), game_connection_support.joining()],
    fn(asked) {
      let #(state, taken) = asked
      let #(_, taken) =
        game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "the server stopping while the connection waits: the client is told"
      assert support.logs(taken) == [] as "a stop is no failure"
    },
  )
}

pub fn an_answer_that_is_none_world_entry_asked_for_is_a_bug_with_reason_8_and_an_error_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      // The map's answer while the store is asked.
      #(
        game_connection_support.playing(42),
        step.Answer(FromMap(game_connection_support.a_join_answer())),
      ),
      // The store's answer while the map is asked.
      #(
        game_connection_support.joining(),
        step.Answer(
          FromStore(
            ForWorld(CharacterLoaded(
              game_connection_support.world_character(),
              character_support.epoch(1),
              None,
              world_entry_support.novice_items(
                character: game_connection_support.world_character(),
              ),
            )),
          ),
        ),
      ),
      // Another process's answers.
      #(
        game_connection_support.playing(42),
        step.Answer(FromStore(ForSelect(Listed([])))),
      ),
      #(game_connection_support.playing(42), step.Answer(FromSessions(Claimed))),
      #(game_connection_support.playing(42), step.Answer(FromHandOff(Kept))),
    ],
    fn(asked) {
      let #(#(state, taken), outcome) = asked
      let #(_, taken) = game_connection_support.answer(state:, taken:, outcome:)
      assert game_connection_support.disconnect(
          taken,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "the client waits for 0xAD or 0x162, so it is told"
      assert list.length(support.logs_of(step: taken, level: LogError)) == 1
        as "an answer of another ask is a bug of the server's: an error"
    },
  )
}

pub fn a_world_answer_when_character_select_asked_the_store_is_a_bug_with_reason_8_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = game_connection_support.listing()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForWorld(NotTheAccounts))),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(state, taken) = game_connection_support.listing()
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(game_connection_support.a_join_answer())),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn an_unhandled_message_id_is_a_warning_the_first_time_on_a_connection_and_a_debug_line_after_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.move_message(0x0635),
    )
  let assert [first] = support.logs(taken)
  assert first.level == LogWarning
    as "the first 0x635 of the connection is logged as unhandled, as a warning"
  assert first.about.message == Some(#("unhandled", 0x0635))
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.move_message(0x0635),
    )
  let assert [again] = support.logs(taken)
  assert again.level == step.LogDebug
    as "a repeat of an id already logged is a debug line, since the client sends some messages again and again"
  assert again.about.message == Some(#("unhandled", 0x0635))
  let #(_, taken) =
    game_connection_support.read(
      state,
      game_connection_support.unhandled_request(),
    )
  let assert [other] = support.logs(taken)
  assert other.level == LogWarning as "another id is its first: a warning"
}

pub fn a_world_message_carries_one_whole_frame_whose_message_is_logged_under_its_own_id_in_character_select_and_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [game_connection_support.in_select(), game_connection_support.in_world()],
    fn(state) {
      let #(_, taken) =
        game_connection_support.read(
          state,
          game_connection_support.store_request(),
        )
      assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x082D))]
        as "opcode.0x38c: a 5-bit value, then the world message's whole frame (0x14007e180); the inner message is logged as unhandled under its own id"
      assert !support.stops(taken)
      assert support.writes(taken) == []
    },
  )
}

pub fn a_world_message_with_no_whole_frame_or_bytes_after_it_is_one_the_client_never_writes_and_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let whole = game_client.world_body(kind: 3, message_id: 0x082D, body: <<1>>)
  let bad = [
    #(<<>>, "no kind byte"),
    #(<<3>>, "a kind and no frame"),
    #(<<3, 8, 0, 0>>, "a length cut short"),
    #(<<3, 20, 0, 0, 0, 0x2D, 0x08, 1>>, "a length of 20 and 3 bytes"),
    #(<<whole:bits, 0>>, "a byte after the frame"),
  ]
  list.each(
    [game_connection_support.in_select(), game_connection_support.in_world()],
    fn(state) {
      list.each(bad, fn(case_) {
        let #(body, what) = case_
        let #(state, taken) =
          game_connection_support.read(
            state,
            game_connection_support.keyed_message(0x038C, body),
          )
        assert list.length(support.logs_of(step: taken, level: LogError)) == 1
        let taken = case support.asked(taken) {
          None -> taken
          Some(_) -> {
            assert game_connection_support.ask_request(taken)
              == game_connection_support.save_asked(
                1,
                game_connection_support.entry_place(),
              )
              as "the player in the world is saved before the connection ends"
            game_connection_support.answer(
              state:,
              taken:,
              outcome: game_connection_support.place_saved(),
            ).1
          }
        }
        assert support.stops(taken)
          as { "opcode.0x38c: " <> what <> " ends the connection" }
      })
    },
  )
}

pub fn a_log_line_in_the_world_is_about_the_players_map_and_character_and_one_in_character_select_is_not_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(2)),
    )
  let assert [line] = support.logs_of(step: taken, level: LogWarning)
  assert line.about.map == Some(game_connection_support.camp_map())
    as "every line of a connection in the world says where: the map the player is in"
  assert line.about.character_id == Some(42)
    as "and who: the character the player plays"
  assert line.about.connection == Some(ConnectionId(1))
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      game_connection_support.taken_over(),
    )
  let assert [line] = support.logs_of(step: taken, level: LogInfo)
  assert line.about.map == None && line.about.character_id == None
    as "in character select the connection is in no map and plays no character"
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.keyed_message(0x0244, <<>>),
    )
  assert list.all(support.logs(taken), fn(line) {
    line.about.map == Some(game_connection_support.camp_map())
    && line.about.character_id == Some(42)
  })
    as "the lines of the shared connection code, which log a refused frame, carry them too"
}

pub fn a_watch_the_rule_did_not_open_ending_in_the_world_is_a_bug_with_an_error_and_the_end_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(9)),
    )
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.stops(taken)
    as "the player is in the world, so the place is saved before the connection ends"
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(2)),
    )
  assert support.stops(taken)
    as "the map's watch is open only while the player is in the world"
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn the_end_of_sessions_in_the_world_claims_again_and_the_claim_puts_the_player_back_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  assert support.effects_of(taken)
    == [
      OwnEffect(CancelTimer(TimerId(2))),
      OwnEffect(StartTimer(TimerId(1), 100)),
    ]
    as "Sessions is likely still restarting, so the claim waits a moment, as in character select; the save timer is cancelled meanwhile"
  assert support.writes(taken) == [] as "the client sees nothing"
  let #(state, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(1))))
  assert support.effects_of(taken) == [Watch(WatchId(1), Sessions)]
  assert game_connection_support.ask_request(taken)
    == game_connection_support.claim_ask()
  let #(state, taken) = game_connection_support.claimed(state:, taken:)
  assert support.writes(taken) == []
  // Back in the world: the movement the client sends is read as in the world,
  // and the map's end ends the connection.
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.move_message(0x0635),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x0635))]
    as "the claim kept where the client is, the player in the world"
  let #(state, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(2)))
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "the map's watch is still open after the claim"
}

pub fn the_end_of_the_map_while_the_claim_waits_ends_the_connection_with_reason_8_and_a_takeover_with_reason_19_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      WatchEnded(WatchId(1)),
    )
  let #(map_ended, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(2)))
  let #(_, taken) =
    game_connection_support.answer(
      state: map_ended,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == LostUserServer
    as "the player's map ended while the connection waits to claim again: its place is saved, then the client is told"
  let #(taken_over, taken) =
    game_connection_support.feed(state, game_connection_support.taken_over())
  let #(_, taken) =
    game_connection_support.answer(
      state: taken_over,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert game_connection_support.disconnect(
      taken,
      game_connection_support.keyed(),
    )
    == AccountDisconnected
}

pub fn a_map_end_while_character_select_waits_to_claim_is_a_bug_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_select_with_a_list(),
      WatchEnded(WatchId(1)),
    )
  let #(_, taken) = game_connection_support.feed(state, WatchEnded(WatchId(2)))
  assert support.stops(taken)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
}

pub fn a_second_0x058f_or_a_play_in_the_world_is_not_taken_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let second =
    game_connection_support.keyed_message(
      0x058F,
      game_client.hello_reply_body(
        session_key: game_connection_support.session_key(),
        account_name: "jim",
      ),
    )
  let #(state, taken) =
    game_connection_support.read(game_connection_support.in_world(), second)
  assert list.length(support.logs_of(step: taken, level: LogError)) == 1
  let #(_, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.stops(taken)
    as "0x058F is sent once (opcode.0x58f), in the world as in character select; in the world the place is saved first"
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.play_message(42),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x07DD))]
    as "a play of the client that is in the world already is logged as unhandled, and no store is asked"
  assert support.asked(taken) == None
  assert !support.stops(taken)
}

// ---- the login places the player ----

/// A character saved at `entry_place()` facing yaw 1.5, pitch -0.25, roll 0.5.
fn turned_character() -> store.Character {
  store.Character(
    ..game_connection_support.world_character(),
    place: Some(start_place.turned(
      game_connection_support.entry_place(),
      Facing(yaw: 1.5, pitch: -0.25, roll: 0.5),
    )),
  )
}

pub fn the_login_places_the_player_at_the_saved_place_and_turns_it_the_saved_way_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = game_connection_support.entered_as(turned_character())
  let assert [Frame(message_id: 0x00AD, body:), ..] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(entering) = enter_world.decode(body)
  assert entering.position_x == 0x41E9075F
    && entering.position_y == 0xC45577C8
    && entering.position_z == 0xC40C0C08
    as "opcode.0xad: the world loads at the saved position"
  assert game_connection_support.player_in(taken).tail.movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: 0x41E9075F,
        y: 0xC45577C8,
        z: 0xC40C0C08,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0x3FC00000,
        pitch: 0xBE800000,
        roll: 0x3F000000,
        blends: 0,
      )),
    ]
    as "0x1404586e0, 0x140715350: kind 2 at the saved position with its bit clear, which places the unit at once, then kind 14 with the saved yaw, pitch and roll (1.5 is 0x3FC00000, -0.25 is 0xBE800000, 0.5 is 0x3F000000)"
}

pub fn a_saved_position_beyond_the_worlds_box_is_written_as_the_boxs_edge_in_0xad_and_0x262_and_saved_as_it_was_test() -> Nil {
  use <- owned_test.run(10_000)
  let far = game_connection_support.standing_at(x: 1.0e9, y: 5000.0, z: -1.0e9)
  let #(state, taken) =
    game_connection_support.entered_as(
      Character(..game_connection_support.world_character(), place: Some(far)),
    )
  let assert [Frame(message_id: 0x00AD, body:), ..] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(entering) = enter_world.decode(body)
  assert #(entering.position_x, entering.position_y, entering.position_z)
    == #(0x47000000, 0x45000000, 0xC7000000)
    as "opcode.0xad.position: LoadWorld keeps the position as sent, so the server writes the box the client bounds a unit's position to (0x1405b5070, bounds 32768.0 = 0x47000000 and 2048.0 = 0x45000000): x and z within 32768, y within 2048"
  assert list.first(
      game_connection_support.player_in(taken).tail.movement_commands,
    )
    == Ok(
      start_movement.Position(UnitPositionCommand(
        x: 0x47000000,
        y: 0x45000000,
        z: 0xC7000000,
        blends: 0,
      )),
    )
    as "0x1405b5070: the client draws the unit within the box, so the position written into 0x262 is the box's edge"
  let #(_, taken) =
    game_connection_support.feed(state, step.OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(1, far)
    as "the place the character is saved at stays as the database held it; only what the client is sent is bounded"
}

pub fn a_character_never_turned_still_gets_a_position_at_its_saved_place_and_faces_0_0_0_test() -> Nil {
  use <- owned_test.run(10_000)
  assert game_connection_support.player_in(game_connection_support.entered().1).tail.movement_commands
    == [
      start_movement.Position(UnitPositionCommand(
        x: 0x41E9075F,
        y: 0xC45577C8,
        z: 0xC40C0C08,
        blends: 0,
      )),
      start_movement.Rotation(MovementRotation(
        yaw: 0,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
    ]
    as "0x1404586e0: without a kind 2 the unit stands at 0, 0, 0, so a character whose saved place was never turned still gets a position at its saved place; its facing is 0, 0, 0"
}
