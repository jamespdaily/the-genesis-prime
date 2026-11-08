//// The game connection's rule (`genesis_prime/game/connection`), run as the
//// pure function it is: inputs in, new state and effects out, with the
//// client's messages built by `game_client`. These tests cover chat: the
//// speaker, the zone and the whisper.

import character_support
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, CreatureAppeared, ForStay, FromMap,
  FromStore, PeerNews, Removed, SentByPeer, TellPeer,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/connection as game_connection
import genesis_prime/message/bit_stream
import genesis_prime/message/chat_line
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/message/send_whisper.{SendWhisper}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_position_command
import genesis_prime/message/whisper_failed
import genesis_prime/message/world_zone_changed.{WorldZoneChanged}
import genesis_prime/server
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, ConnectionId,
  EndedBeforeAnswer, LogError, NoAnswerInTime, NotRunning, OwnEffect, OwnEvent,
  StoppedWaiting, Unwatch, Watch, WatchEnded, WatchId, Woken,
}
import genesis_prime/store.{CharacterLoaded, ForSelect, ForWorld, Listed}
import genesis_prime/table/id.{Creature2Id, Spell4Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_kind.{Kind}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/map.{
  CreatureRefused, Left, NoPlayerHere, NotSummoned, SeenBy, Summoned,
}
import genesis_prime/world_map/spawn.{
  FailsTheChecks, NoCreatureLevelRow, NoCreatureRow, NoFaction, WouldNotStart,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source.{RunOnly}
import gleam/list
import gleam/option.{None, Some}
import map_spawn_support
import message_support
import owned_test
import spawn_support

// ---- chat: the speaker, the reader and the routing ----

/// A 0x1c3 on (type, 0) inside 0x038C, as the client sends it, with slot 1.
fn chat_line_message(type_id: Int, text: String) -> BitArray {
  chat_line_with(type_id:, text:, message_id: 1)
}

fn chat_line_with(
  type_id type_id: Int,
  text text: String,
  message_id message_id: Int,
) -> BitArray {
  let assert Ok(body) =
    send_chat_line.encode(SendChatLine(
      channel_type: type_id,
      channel_id: 0,
      text: bit_stream.utf16_units(text),
      formats: [],
      chat_message_id: message_id,
    ))
  game_connection_support.world_message(send_chat_line.message_id, body)
}

/// The chat tells of a step: the address each goes to and what it says, in the
/// order of the step's effects.
fn chat_tells(
  taken: ConnectionStep(Request),
) -> List(#(step.Address, chat_tell.Tell)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(to:, request: client_connection.TellChat(tell:))) ->
        Ok(#(to, tell))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

fn peer_tell_kinds(taken: ConnectionStep(Request)) -> List(String) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.Tell(request: TellPeer(..), ..)) -> Ok("unit news")
      OwnEffect(step.Tell(request: client_connection.TellChat(..), ..)) ->
        Ok("chat")
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

pub fn a_say_line_in_the_world_writes_the_accept_and_tells_each_viewer_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [
      2,
      3,
    ])
  let #(_, taken) =
    game_connection_support.read(state, chat_line_message(4, "Hello"))
  assert game_connection_support.written_ids(taken) == [0x01C2]
    as "opcode.0x1c2: the speaker's own line is shown by the accept alone"
  let tells = chat_tells(taken)
  assert list.map(tells, fn(told) { told.0 })
    == [step.Connection(ConnectionId(2)), step.Connection(ConnectionId(3))]
    as "one tell to each viewer, which the shell sends with no answer"
  let assert [#(_, chat_tell.Said(speaker:, line:)), ..] = tells
  assert speaker.name == "Ab Cd" && speaker.character_id == 42
  assert line.channel_type == chat_channel.Say && line.channel_id == 0
  assert support.logs(taken) == [] && !support.stops(taken)
}

pub fn the_viewer_gets_the_speakers_unit_news_before_its_first_line_whatever_the_order_of_watched_and_the_line_test() -> Nil {
  use <- owned_test.run(10_000)
  // The line first: the player 2 is no viewer yet, so it gets no line.
  let #(state, line_first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chat_line_message(4, "Hello"),
    )
  let #(_, appears) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
      )),
    )
  assert peer_tell_kinds(line_first) == []
    as "a player that does not see the speaker yet is told nothing"
  assert peer_tell_kinds(appears) == ["unit news"]
    as "design C: the speaker's connection sends its 0x262 as the map says the player sees it"
  // Watched first: the 0x262 is told in the step before the line, by the same
  // sender, so the viewer's connection takes them in that order.
  let #(state, appears) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(2),
        stay: game_connection_support.viewer_stay(2),
      )),
    )
  let #(_, line) =
    game_connection_support.read(state, chat_line_message(4, "Hello"))
  assert list.append(peer_tell_kinds(appears), peer_tell_kinds(line))
    == ["unit news", "chat"]
    as "the 0x262 comes before the first line: one sender for each pair, and a sender's messages arrive in the order sent, so the bubble finds the unit"
}

pub fn a_said_tell_writes_a_0x1c8_with_the_player_in_the_world_test() -> Nil {
  use <- owned_test.run(10_000)
  let tell =
    chat_tell.Said(
      speaker: chat_tell.Speaker(
        realm_id: 1,
        character_id: 7,
        name: "Zed Other",
        faction_id: 167,
        unit_id: 9,
        map: game_connection_support.camp_map(),
        incarnation: game_connection_support.incarnation,
      ),
      line: chat_tell.Line(
        channel_type: chat_channel.Say,
        channel_id: 0,
        text: [0x48, 0x69],
        formats: [],
      ),
    )
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      OwnEvent(Woken(client_connection.SentByChat(tell))),
    )
  assert game_connection_support.written_ids(taken) == [0x01C8]
  let assert [Frame(body:, ..)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  let assert Ok(line) = chat_line.decode(body)
  assert line.sender_name == "Zed Other" && line.unit_id == 9
  assert line.cross_faction == 1
    as "chat.cross_faction: the tests' player is faction 166, the speaker 167"
}

pub fn a_chat_tell_with_no_player_in_the_world_is_dropped_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let tell =
    chat_tell.Said(
      speaker: chat_tell.Speaker(
        realm_id: 1,
        character_id: 7,
        name: "Zed Other",
        faction_id: 167,
        unit_id: 9,
        map: game_connection_support.camp_map(),
        incarnation: game_connection_support.incarnation,
      ),
      line: chat_tell.Line(
        channel_type: chat_channel.Say,
        channel_id: 0,
        text: [0x48, 0x69],
        formats: [],
      ),
    )
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select(),
      OwnEvent(Woken(client_connection.SentByChat(tell))),
    )
  assert game_connection_support.written_ids(taken) == []
    && support.logs(taken) == []
    && !support.stops(taken)
    as "a player in character select has no chat: the line is dropped"
}

pub fn a_0x1c3_outside_the_world_is_logged_as_unhandled_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      chat_line_message(4, "Hello"),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x01C3))]
    as "the routing table takes 0x1c3 with the player in the world only"
  assert !support.stops(taken)
}

pub fn a_format_of_type_12_ends_the_connection_with_nothing_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let body =
    message_support.hex(
      "04 00 00 00 00 00 00 00 00 80 00 1e 40 60 00 80 00 00 00 00 00 00 00 00 00 80 00 00",
    )
  let #(refusing, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.world_message(send_chat_line.message_id, body),
    )
  assert list.any(support.logs(taken), fn(line) { line.level == step.LogError })
    as "0x140085ca0: the client's reader refuses a format of type 12 to 15, so the frame is one the client never writes: an error line says so"
  assert support.writes(taken) == [] as "nothing is written to such a client"
  let #(_, taken) =
    game_connection_support.answer(
      state: refusing,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  assert support.effects_of(taken) == [step.Stop]
    as "the last good place is saved and the connection ends (CLAUDE.md: bytes the client's reader refuses end the connection)"
}

pub fn support_and_instance_are_logged_as_unhandled_once_for_each_channel_on_a_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      chat_line_with(type_id: 19, text: "Hi", message_id: 1),
    )
  let #(state, second) =
    game_connection_support.read(
      state,
      chat_line_with(type_id: 19, text: "Hi", message_id: 2),
    )
  let #(_, instance) =
    game_connection_support.read(
      state,
      chat_line_with(type_id: 32, text: "Hi", message_id: 3),
    )
  let warnings = fn(taken) {
    list.filter(support.logs(taken), fn(line) { line.level == step.LogWarning })
  }
  assert list.length(warnings(first)) == 1
    as "Jim, 2026-11-03: the channel is named in a warning"
  assert warnings(second) == [] as "once for each channel on a connection"
  assert list.length(warnings(instance)) == 1
    as "another channel is another line"
  assert game_connection_support.written_ids(second) == [0x01D3]
    as "each line still gets its one answer"
}

// ---- chat: the zone ----

/// The groups a step joins and leaves, in the order of its effects.
fn group_effects(
  taken: ConnectionStep(Request),
) -> List(step.ConnectionEffect(Request)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(step.JoinGroup(address:)) -> Ok(step.JoinGroup(address:))
      OwnEffect(step.LeaveGroup(address:)) -> Ok(step.LeaveGroup(address:))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

fn zone_changed_message(old old: Int, new new: Int) -> BitArray {
  let assert Ok(body) =
    world_zone_changed.encode(WorldZoneChanged(
      old_world_zone_id: old,
      new_world_zone_id: new,
    ))
  game_connection_support.world_message(world_zone_changed.message_id, body)
}

pub fn the_entry_burst_ends_with_0x1da_and_0x1bc_and_joins_the_name_and_the_zone_channel_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = game_connection_support.entered()
  assert game_client.without_passive_cast(
      ids: game_connection_support.written_ids(taken),
    )
    == game_client.world_entry_ids
    as "opcode.0x1da, opcode.0x1bc: after 0x61, 0x1da names the channel and 0x1bc gives it, in that order"
  assert group_effects(taken)
    == [
      step.JoinGroup(step.CharacterNamed("ab cd")),
      step.JoinGroup(game_connection_support.zone_group(4961)),
    ]
    as "the player joins its folded name and the zone channel of its run and the top zone 4961 of its place's zone 6009, in the step that takes the map's Joined"
}

pub fn a_report_under_the_same_top_zone_writes_and_joins_nothing_for_0x63a_and_only_the_0x1bc_for_0xf2_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(zone_changed_message(old: 6009, new: 4962), []),
      #(game_connection_support.terrain_loaded_message(4962), [0x01BC]),
    ],
    fn(sent) {
      let #(bytes, expected) = sent
      let #(_, taken) =
        game_connection_support.read(game_connection_support.in_world(), bytes)
      assert game_connection_support.written_ids(taken) == expected
        && group_effects(taken) == []
        as "chat.zone_reach: 4962 is under the top zone 4961 of the place's zone, so no 0x1da and no group; the first 0xf2 of the stay writes the zone channel's 0x1bc (chat.zone_join_trigger)"
      assert support.logs(taken) == [] && !support.stops(taken)
    },
  )
}

pub fn a_report_under_another_top_zone_renames_the_channel_and_changes_the_group_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(zone_changed_message(old: 6009, new: 648), [0x01DA]),
      #(game_connection_support.terrain_loaded_message(648), [0x01DA, 0x01BC]),
    ],
    fn(sent) {
      let #(bytes, expected) = sent
      let #(_, taken) =
        game_connection_support.read(game_connection_support.in_world(), bytes)
      assert game_connection_support.written_ids(taken) == expected
        as "0x140403670: the client only renames the zone channel; the first 0xf2 of the stay then writes the channel's 0x1bc (chat.zone_join_trigger)"
      assert group_effects(taken)
        == [
          step.LeaveGroup(game_connection_support.zone_group(4961)),
          step.JoinGroup(game_connection_support.zone_group(35)),
        ]
    },
  )
}

pub fn a_0x63a_whose_old_value_is_not_the_one_the_server_holds_is_taken_all_the_same_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      zone_changed_message(old: 1, new: 648),
    )
  assert game_connection_support.written_ids(taken) == [0x01DA]
    as "server choice: whether the client's kept value outlives a camp is not read (opcode.0x63a), so the old value is not checked and a sound client is not dropped"
}

pub fn a_report_of_zone_0_leaves_the_group_and_writes_0x1da_with_no_zone_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.terrain_loaded_message(0),
    )
  assert game_connection_support.written_ids(taken) == [0x01DA, 0x01BC]
  assert group_effects(taken)
    == [step.LeaveGroup(game_connection_support.zone_group(4961))]
}

pub fn a_report_of_a_zone_with_no_row_is_no_zone_with_one_warning_for_each_such_zone_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.terrain_loaded_message(1132),
    )
  assert game_connection_support.written_ids(taken) == [0x01DA, 0x01BC]
    && group_effects(taken)
    == [step.LeaveGroup(game_connection_support.zone_group(4961))]
    && !support.stops(taken)
    as "0x140403670: the client accepts a zone with no row (0x1da names no channel then), so the connection goes on: the player is in no zone"
  let warnings = fn(taken) {
    list.filter(support.logs(taken), fn(line) { line.level == step.LogWarning })
  }
  assert list.length(warnings(taken)) == 1
    && support.logs_of(step: taken, level: LogError) == []
    as "one warning names the zone, and no error"
  let #(state, again) =
    game_connection_support.read(
      state,
      game_connection_support.terrain_loaded_message(1132),
    )
  assert warnings(again) == []
    as "the same zone is logged once for each connection"
  let #(_, other) =
    game_connection_support.read(
      state,
      game_connection_support.terrain_loaded_message(1133),
    )
  assert list.length(warnings(other)) == 1
    as "another such zone is another line"
}

pub fn the_first_0xf2_of_a_stay_writes_0x1bc_and_a_second_does_not_and_a_new_stay_writes_it_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.written_ids(first) == [0x01BC]
    as "chat.zone_join_trigger: ChatLog registers ChatJoin after 0xad, so the first 0xf2 gives the client the Zone channel again"
  let #(_, second) =
    game_connection_support.read(
      state,
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.written_ids(second) == []
    as "a second 0xf2 in the same stay writes none"
  let #(camped, _) = game_connection_support.camped_out()
  let #(again, _) =
    game_connection_support.entered_from(
      camped,
      game_connection_support.world_character(),
    )
  let #(_, new_stay) =
    game_connection_support.read(
      again,
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.written_ids(new_stay) == [0x01BC]
    as "after a camp and a new entry the first 0xf2 writes it again"
}

pub fn a_0x63a_before_the_first_0xf2_does_not_write_0x1bc_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, changed) =
    game_connection_support.read(
      game_connection_support.in_world(),
      zone_changed_message(old: 6009, new: 4962),
    )
  assert game_connection_support.written_ids(changed) == []
    as "only 0xf2 is the trigger: 0x63a is sent on a change, which a player standing still never makes (chat.zone_join_trigger)"
  let #(_, first) =
    game_connection_support.read(
      state,
      game_connection_support.terrain_loaded_message(6009),
    )
  assert game_connection_support.written_ids(first) == [0x01BC]
    as "and the first 0xf2 still writes it"
}

pub fn a_camp_answers_each_pending_whisper_0x1d9_before_it_saves_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  let #(state, _) =
    game_connection_support.read(
      state,
      game_connection_support.camp_request_message(True),
    )
  let #(_, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  assert game_connection_support.written_ids(taken) == [0x01D9]
    as "the design: every 0x1d4 keeps exactly one answer, so the whisper the camp drops is answered before the save"
  assert list.any(support.effects_of(taken), fn(effect) {
    case effect {
      Unwatch(WatchId(101)) -> True
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop -> False
    }
  })
    as "and its watch is dropped"
}

pub fn a_zone_line_told_to_a_connection_after_its_camp_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(left, _) = game_connection_support.camped_out()
  let tell =
    chat_tell.ZoneLine(
      speaker: chat_tell.Speaker(
        realm_id: 1,
        character_id: 7,
        name: "Zed Other",
        faction_id: 167,
        unit_id: 9,
        map: game_connection_support.camp_map(),
        incarnation: game_connection_support.incarnation,
      ),
      top_zone_id: 4961,
      line: chat_tell.Line(
        channel_type: chat_channel.Zone,
        channel_id: 1,
        text: [0x48, 0x69],
        formats: [],
      ),
    )
  let #(_, taken) =
    game_connection_support.feed(
      left,
      OwnEvent(Woken(client_connection.SentByChat(tell))),
    )
  assert game_connection_support.written_ids(taken) == []
    && chat_tells(taken) == []
    && support.logs(taken) == []
    && !support.stops(taken)
    as "the design's failure table: after the camp's leave no zone line reaches the player, though the speaker's tell was already sent"
}

pub fn messages_0xf2_and_0x63a_outside_the_world_are_unhandled_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(0x00F2, game_connection_support.terrain_loaded_message(4962)),
      #(0x063A, zone_changed_message(old: 6009, new: 4962)),
    ],
    fn(sent) {
      let #(_, taken) =
        game_connection_support.read(
          game_connection_support.in_select(),
          sent.1,
        )
      assert support.unhandled_ids(taken) == [Some(#("unhandled", sent.0))]
        as "the routing table takes them inside 0x38C with the player in the world only (opcode.0xf2, opcode.0x63a); elsewhere they are logged as unhandled, as before"
      assert group_effects(taken) == [] && !support.stops(taken)
    },
  )
}

pub fn a_camp_leaves_the_name_and_zone_groups_before_it_saves_and_a_new_entry_joins_again_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) = game_connection_support.saving_the_camp()
  assert group_effects(taken)
    == [
      step.LeaveGroup(step.CharacterNamed("ab cd")),
      step.LeaveGroup(game_connection_support.zone_group(4961)),
    ]
    as "the design's failure table: LeaveGroup in the step that starts the camp's leave, so no zone line reaches it after the leave"
  let #(again, _) = game_connection_support.camped_out()
  let #(_, entered_again) =
    game_connection_support.entered_from(
      again,
      game_connection_support.world_character(),
    )
  assert group_effects(entered_again)
    == [
      step.JoinGroup(step.CharacterNamed("ab cd")),
      step.JoinGroup(game_connection_support.zone_group(4961)),
    ]
    as "a new entry joins again"
}

// ---- chat: the whisper ----

fn whisper_message(
  target target: String,
  text text: String,
  message_id message_id: Int,
) -> BitArray {
  let assert Ok(body) =
    send_whisper.encode(SendWhisper(
      target_name: bit_stream.utf16_units(target),
      target_realm_name: [],
      text: bit_stream.utf16_units(text),
      formats: [],
      chat_message_id: message_id,
      account: 0,
    ))
  game_connection_support.world_message(send_whisper.message_id, body)
}

fn incoming_whisper(whisper: Int) -> Event(ConnectionEvent(Message, Answer)) {
  OwnEvent(
    Woken(
      client_connection.SentByChat(chat_tell.Whisper(
        whisper:,
        speaker: chat_tell.Speaker(
          realm_id: 1,
          character_id: 7,
          name: "Zed Other",
          faction_id: 167,
          unit_id: 9,
          map: game_connection_support.camp_map(),
          incarnation: game_connection_support.incarnation,
        ),
        from: ConnectionId(8),
        line: chat_tell.Line(
          channel_type: chat_channel.Whisper,
          channel_id: 0,
          text: [0x48, 0x69],
          formats: [],
        ),
      )),
    ),
  )
}

fn whisper_watch_effects(
  taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.filter(support.effects_of(taken), fn(effect) {
    case effect {
      Watch(..) | OwnEffect(step.TellWatched(..)) -> True
      OwnEffect(_) | Unwatch(..) | step.Log(..) | step.Stop -> False
    }
  })
}

pub fn a_0x1d4_in_the_world_watches_the_targets_name_and_tells_through_that_watch_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  assert game_connection_support.written_ids(taken) == []
    as "nothing is written until the target answers"
  let assert [
    Watch(watch, target),
    OwnEffect(step.TellWatched(
      watch: told_through,
      request: client_connection.TellChat(chat_tell.Whisper(
        whisper: 1,
        from: ConnectionId(1),
        ..,
      )),
    )),
  ] = whisper_watch_effects(taken)
  assert target == step.CharacterNamed("cd ef")
  assert told_through == watch
  assert watch == WatchId(101)
}

pub fn a_whisper_tell_in_the_world_writes_0x1c8_and_tells_the_speaker_heard_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      incoming_whisper(5),
    )
  assert game_connection_support.written_ids(taken) == [0x01C8]
  assert chat_tells(taken)
    == [
      #(
        step.Connection(ConnectionId(8)),
        chat_tell.Heard(whisper: 5, name: "Ab Cd"),
      ),
    ]
}

pub fn a_whisper_tell_with_no_player_in_the_world_is_answered_not_heard_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.feed(
      game_connection_support.in_select(),
      incoming_whisper(5),
    )
  assert game_connection_support.written_ids(taken) == []
  assert chat_tells(taken)
    == [#(step.Connection(ConnectionId(8)), chat_tell.NotHeard(whisper: 5))]
    as "the design's failure table: a target in character select or in the camp's leave is not in the world"
  let #(left, _) = game_connection_support.camped_out()
  let #(_, taken) = game_connection_support.feed(left, incoming_whisper(6))
  assert chat_tells(taken)
    == [#(step.Connection(ConnectionId(8)), chat_tell.NotHeard(whisper: 6))]
    as "and after the camp's leave"
}

pub fn a_pending_whisper_and_a_whisper_to_the_player_are_taken_while_the_connection_claims_again_after_sessions_ended_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  let #(state, waiting) =
    game_connection_support.feed(state, WatchEnded(WatchId(1)))
  assert !support.stops(waiting)
    as "Sessions ended: the connection waits to claim again"
  let #(state, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(101)))
  assert game_connection_support.written_ids(taken) == [0x01D9]
    && !support.stops(taken)
    && support.logs(taken) == []
    as "the finding: the end of a whisper's watch is taken in the wait, the speaker still gets its 0x1d9, and the connection goes on"
  let #(_, taken) = game_connection_support.feed(state, incoming_whisper(5))
  assert game_connection_support.written_ids(taken) == [0x01C8]
    as "a whisper to the player is written while it waits to claim, since its client holds the world"
}

pub fn the_whisper_numbers_count_for_the_connections_life_across_a_camp_and_a_new_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, first) =
    game_connection_support.read(
      game_connection_support.in_world(),
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  let #(state, _) =
    game_connection_support.read(
      state,
      game_connection_support.camp_request_message(True),
    )
  let #(state, taken) =
    game_connection_support.read(
      state,
      game_connection_support.camp_finished_message(),
    )
  let #(state, taken) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Left)),
    )
  let #(state, taken) =
    game_connection_support.read(state, game_connection_support.select_start())
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromStore(ForSelect(Listed([])))),
    )
  let #(state, taken) = game_connection_support.playing_from(state, 42)
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
          )),
        ),
      ),
    )
  let #(_, joined) =
    game_connection_support.mapped(
      map_state: game_connection_support.map_with_four_players(),
      taken:,
    )
  let #(state, _) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(joined)),
    )
  let #(_, second) =
    game_connection_support.read(
      state,
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  let assert [Watch(watch, _), ..] = whisper_watch_effects(second)
  assert watch == WatchId(102)
    as "the design's finding: a reply to a whisper of the first stay never meets the second stay's first whisper"
  assert list.length(whisper_watch_effects(first)) == 2
}

pub fn a_0x1d4_outside_the_world_is_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_select(),
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x01D4))]
}

pub fn a_whisper_to_an_offline_name_gives_0x1d9_when_its_watch_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.read(
      game_connection_support.in_world(),
      whisper_message(target: "Cd Ef", text: "Hi", message_id: 3),
    )
  let #(_, taken) =
    game_connection_support.feed(state, WatchEnded(WatchId(101)))
  let assert [frame] =
    game_connection_support.heard(taken, game_connection_support.keyed())
  assert frame.message_id == whisper_failed.message_id
  assert support.logs(taken) == []
}

pub fn a_0x597_name_lookup_is_logged_as_unhandled_and_no_player_info_is_written_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world(),
      game_connection_support.world_message(0x0597, <<>>),
    )
  assert support.unhandled_ids(taken) == [Some(#("unhandled", 0x0597))]
    as "chat.name_lookup: no chat line makes the client ask for a name, so the player info of the mail step is not built and 0x597 stays unhandled"
  assert game_connection_support.written_ids(taken) == []
    as "no 0x598 or 0x599 is written"
}

pub fn a_creatures_news_is_written_as_a_type_0_0x262_once_and_removed_by_a_0x355_test() -> Nil {
  use <- owned_test.run(10_000)
  let creature =
    creature_unit.create(
      spawn: spawn_support.battle_beast(number: 1, x: 0.0),
      unit_id: 40,
      health: 52,
      interrupt_armor: option.None,
      server_time_estimate_start: 0,
    )
  let beast = spawn_support.battle_beast(number: 1, x: 0.0)
  let appears =
    game_connection_support.sent_by_a_peer(game_connection_support.news_of(
      unit_id: 40,
      news: CreatureAppeared(
        unit: creature,
        life: 4,
        place: beast.place,
        hit_radius: beast.combat.hit_radius,
        attackable: beast.combat.attackable,
      ),
    ))
  let #(state, taken) =
    game_connection_support.feed(game_connection_support.in_world(), appears)
  let assert [Frame(message_id: 0x0262, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "a creature's 0x262 is written as the creature's process sent it"
  assert unit_create_creature.decode(body) == Ok(creature)
  let #(state, taken) = game_connection_support.feed(state, appears)
  assert support.writes(taken) == []
    as "a unit the client already shows is not created again, whoever owns it"
  let #(_, taken) =
    game_connection_support.feed(
      state,
      game_connection_support.sent_by_a_peer(game_connection_support.news_of(
        unit_id: 40,
        news: Removed,
      )),
    )
  let assert [Frame(message_id: 0x0355, body:)] =
    game_connection_support.heard(taken, game_connection_support.keyed())
    as "opcode.0x355: the creature is removed when its process says so"
  assert unit_destroyed.decode(body)
    == Ok(UnitDestroyed(unit_id: 40, field_2: 0))
}

// ---- the development summon ----
//
// Expected values: the setting, the `!` grammar and the answers' texts are the
// design's choices (a test tool for the play container); the 0x1c2 for
// each 0x1c3 is `opcode.0x1c2`; a system line is `chat.system_line` (ChatChannel
// row 2, flags 8) as a 0x1c8 (`opcode.0x1c8`); the ask is the map's `Summon`
// to the run that took the player, with the settings' deadline, 4000 ms.

/// The connection with the development commands on, after the player said a
/// summon of Commander Durek (Creature2 75048): the map is asked.
fn summoning() -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    game_connection_support.in_world_with_dev_commands(),
    chat_line_message(4, "!summon 75048"),
  )
}

/// The text of each system line the step writes, in order.
fn system_lines(taken: ConnectionStep(Request)) -> List(String) {
  list.filter_map(
    game_connection_support.heard(taken, game_connection_support.keyed()),
    fn(frame) {
      case frame.message_id == chat_line.message_id {
        False -> Error(Nil)
        True -> {
          let assert Ok(line) = chat_line.decode(frame.body)
          assert line.channel_type == 2 && line.channel_id == 0
            as "chat.system_line: channel type 2"
          assert line.sender_name == "" && line.unit_id == 0
            as "chat.system_line: no speaker"
          let assert Ok(text) = bit_stream.from_utf16(line.text)
          Ok(text)
        }
      }
    },
  )
}

/// Whether the connection takes the next line the player says: it is in the
/// world, so the line is answered and nothing is asked.
fn goes_on_in_the_world(state: game_connection.State) -> Bool {
  let #(_, taken) =
    game_connection_support.read(state, chat_line_message(4, "Hello"))
  game_connection_support.written_ids(taken) == [0x01C2]
  && support.asked(taken) == None
  && !support.stops(taken)
}

pub fn with_the_setting_off_a_summon_line_is_said_and_nothing_is_asked_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [
      2,
      3,
    ])
  let #(_, taken) =
    game_connection_support.read(state, chat_line_message(4, "!summon 75048"))
  assert game_connection_support.written_ids(taken) == [0x01C2]
    as "opcode.0x1c2: the speaker's own line"
  assert list.map(chat_tells(taken), fn(told) { told.0 })
    == [step.Connection(ConnectionId(2)), step.Connection(ConnectionId(3))]
    as "the design: with the setting off a `!` line is a Say line, told to each viewer"
  assert support.asked(taken) == None as "nothing is asked of the map"
}

pub fn with_the_setting_on_a_summon_line_is_answered_told_to_no_viewer_and_asks_the_map_test() -> Nil {
  use <- owned_test.run(10_000)
  let state =
    game_connection_support.watched_by(
      game_connection_support.in_world_with_dev_commands(),
      [2, 3],
    )
  let #(_, taken) =
    game_connection_support.read(state, chat_line_message(4, "!summon 75048"))
  assert game_connection_support.written_ids(taken) == [0x01C2]
    as "opcode.0x1c2: the speaker's own line is answered before the ask"
  assert chat_tells(taken) == [] as "the design: the line is told to no viewer"
  let assert Some(ask) = support.asked(taken)
  assert ask.request == game_connection_support.summon_asked(75_048, None)
    as "the design: the connection asks the run of the map that took the player to summon Creature2 75048, with its own id"
  assert ask.deadline_ms == support.now_ms + 4000
    as "the settings' ask deadline from the time of the input"
}

pub fn an_unknown_command_and_a_malformed_summon_each_answer_one_system_line_and_ask_nothing_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #("!teleport 75048", "unknown command"),
      #(
        "!summon",
        "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3",
      ),
      #(
        "!summon x",
        "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3",
      ),
      #(
        "!summon 75048 x",
        "!summon's level is a whole number, as !summon 75048 3",
      ),
      #(
        "!summon 75048 3 4",
        "!summon takes a Creature2 id and an optional level, as !summon 75048 or !summon 75048 3",
      ),
    ],
    fn(row) {
      let #(state, taken) =
        game_connection_support.read(
          game_connection_support.in_world_with_dev_commands(),
          chat_line_message(4, row.0),
        )
      assert game_connection_support.written_ids(taken) == [0x01C2, 0x01C8]
        as "opcode.0x1c2 then the one system line"
      assert system_lines(taken) == [row.1]
        as "the design's texts, on the System channel"
      assert support.asked(taken) == None && chat_tells(taken) == []
      assert goes_on_in_the_world(state)
    },
  )
}

pub fn a_summon_line_with_a_level_asks_the_map_for_that_level_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    game_connection_support.read(
      game_connection_support.in_world_with_dev_commands(),
      chat_line_message(4, "!summon 75048 3"),
    )
  assert game_connection_support.written_ids(taken) == [0x01C2]
    as "opcode.0x1c2: the speaker's own line is answered before the ask"
  let assert Some(ask) = support.asked(taken)
  assert ask.request == game_connection_support.summon_asked(75_048, Some(3))
    as "the design: the ask names the level the line named"
}

pub fn a_level_the_map_refused_is_a_system_line_naming_it_and_the_player_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) =
    game_connection_support.read(
      game_connection_support.in_world_with_dev_commands(),
      chat_line_message(4, "!summon 73465 51"),
    )
  let assert client_connection.AskMapRun(map: _, message:, ..) =
    game_connection_support.ask_request(taken)
  let #(map_state, _) = map_spawn_support.started(at: [])
  let #(map_state, _) =
    map_spawn_support.join(state: map_state, at_ms: 5100, connection: 1, x: 0.0)
  let #(_, refused) =
    map.step(
      map_state,
      support.input(OwnEvent(step.Asked(caller: step.CallerId(1), message:))),
    )
  let assert [#(_, answer)] = support.replies(refused)
  assert answer
    == NotSummoned(reason: CreatureRefused(NoCreatureLevelRow(level: 51)))
    as "the map's answer for a level the planted tables hold no CreatureLevel row for (they hold rows 1 to 50 and 101)"
  let #(state, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(answer)),
    )
  assert system_lines(answered) == ["not summoned: CreatureLevel 51 has no row"]
    as "the design: one system line, naming the level, and never said aloud"
  assert game_connection_support.written_ids(answered) == [0x01C8]
  assert chat_tells(answered) == []
  assert goes_on_in_the_world(state)
}

pub fn a_summoned_answer_writes_nothing_and_the_player_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = summoning()
  let #(state, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Summoned(unit_id: 9))),
    )
  assert support.writes(answered) == []
    as "the creature sent its own 0x262 as it started, so the connection writes nothing"
  assert support.logs(answered) == [] && !support.stops(answered)
  assert goes_on_in_the_world(state)
}

pub fn a_line_the_client_sent_while_the_summon_was_asked_is_taken_when_the_answer_comes_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = summoning()
  let #(state, held) =
    game_connection_support.read(state, chat_line_message(4, "Hello"))
  assert support.writes(held) == [] && support.asked(held) == None
    as "the client's frames are held while the ask is out"
  let #(_, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(Summoned(unit_id: 9))),
    )
  assert game_connection_support.written_ids(answered) == [0x01C2]
    as "opcode.0x1c2: the held line is taken once the player is back in the world, and answered"
}

pub fn a_map_with_no_player_of_the_connection_answers_one_system_line_that_says_so_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = summoning()
  let #(state, answered) =
    game_connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(FromMap(NotSummoned(reason: NoPlayerHere))),
    )
  assert system_lines(answered)
    == ["not summoned: the player is not in the map"]
    as "the design: the reason, on the System channel"
  assert game_connection_support.written_ids(answered) == [0x01C8]
  assert goes_on_in_the_world(state)
}

pub fn a_refused_creature_answers_one_system_line_naming_the_reason_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(
        CreatureRefused(FailsTheChecks(NoCreatureRow(Creature2Id(999_999)))),
        "not summoned: Creature2 999999 has no row",
      ),
      #(
        CreatureRefused(NoCreatureLevelRow(level: 200)),
        "not summoned: CreatureLevel 200 has no row",
      ),
      #(
        CreatureRefused(WouldNotStart(Creature2Id(75_048), NoFaction)),
        "not summoned: Creature2 75048 would not start as a spawn: no faction",
      ),
      #(
        map.CreatureNotStarted(reason: "the creature supervisor is not running"),
        "not summoned: the creature did not start",
      ),
    ],
    fn(row) {
      let #(state, taken) = summoning()
      let #(state, answered) =
        game_connection_support.answer(
          state:,
          taken:,
          outcome: step.Answer(FromMap(NotSummoned(reason: row.0))),
        )
      assert system_lines(answered) == [row.1]
        as "the design: one system line, with the map's reason"
      assert game_connection_support.written_ids(answered) == [0x01C8]
      assert goes_on_in_the_world(state)
    },
  )
}

pub fn a_map_that_is_not_running_ended_or_gave_no_answer_in_time_answers_not_summoned_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      #(NotRunning, "not summoned: the map was not running"),
      #(EndedBeforeAnswer, "not summoned: the map ended before it answered"),
      #(NoAnswerInTime, "not summoned: the map gave no answer in time"),
    ],
    fn(row) {
      let #(state, taken) = summoning()
      let #(state, answered) =
        game_connection_support.answer(state:, taken:, outcome: row.0)
      assert system_lines(answered) == [row.1]
        as "the design: the player is answered one \"not summoned\" line with why"
      assert game_connection_support.written_ids(answered) == [0x01C8]
      assert support.logs_of(step: answered, level: LogError) == []
        && !support.stops(answered)
        && support.asked(answered) == None
        as "the connection goes on in the world"
      assert goes_on_in_the_world(state)
    },
  )
}

pub fn the_server_stopping_during_the_summon_ends_the_connection_as_a_stop_does_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, taken) = summoning()
  let #(_, answered) =
    game_connection_support.answer(state:, taken:, outcome: StoppedWaiting)
  assert system_lines(answered) == []
    as "no line is written to a player the server is stopping for"
  assert game_connection_support.ask_request(answered)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "a stop saves the player in the world, as in any status that holds one"
}

pub fn an_answer_that_is_none_a_summon_asked_for_ends_the_connection_as_a_bug_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(
    [
      step.Answer(FromStore(store.Unavailable)),
      ..game_connection_support.answers_to_other_asks()
    ],
    fn(outcome) {
      let #(state, taken) = summoning()
      let #(state, answered) =
        game_connection_support.answer(state:, taken:, outcome:)
      assert list.length(support.logs_of(step: answered, level: LogError)) == 1
        as "a bug is an error line"
      assert system_lines(answered) == []
      let #(_, saved) =
        game_connection_support.answer(
          state:,
          taken: answered,
          outcome: game_connection_support.place_saved(),
        )
      assert game_connection_support.disconnect(
          saved,
          game_connection_support.keyed(),
        )
        == LostUserServer
        as "the player's place is saved, then 0x036A reason 8 as for any bug"
    },
  )
}

pub fn a_connection_that_ends_while_the_summon_is_asked_still_saves_the_player_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) = summoning()
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(step.PeerClosed))
  assert game_connection_support.ask_request(taken)
    == game_connection_support.save_asked(
      1,
      game_connection_support.entry_place(),
    )
    as "the player is in the world while the creature starts, so its place is saved as in InWorld"
}

// ---- the whole summon: the connection, the map and the creature ----

pub fn with_the_setting_on_a_summon_line_starts_the_creature_at_the_players_place_and_the_player_sees_it_test() -> Nil {
  use <- owned_test.run(10_000)
  // The three rules chained, each fed what the one before sent, as the shells
  // carry it. Expected values: the creature stands where the client moved the
  // player (0x637's position, x 1.5, y 2.5, z 3.5, which the connection tells
  // the map), as Creature2 73465, the Virtual Defense Dagun (faction 1442,
  // display 26578, `Creature2.73465`); the player's client is written one 0x262
  // (opcode.0x262) and the map's answer writes nothing.
  let select =
    game_connection_support.in_select_from(
      game_connection_support.accepted(
        game_connection_support.settings_with_dev_commands(),
      ).0,
    )
  let #(joining, joining_taken) =
    game_connection_support.joining_from(
      in_character_select: select,
      character: game_connection_support.world_character(),
    )
  let #(map_state, join_answer) =
    game_connection_support.mapped(
      map_state: game_connection_support.map_with_four_players(),
      taken: joining_taken,
    )
  let #(state, _) =
    game_connection_support.answer(
      state: joining,
      taken: joining_taken,
      outcome: step.Answer(FromMap(join_answer)),
    )
  let standing = game_connection_support.standing_at(x: 1.5, y: 2.5, z: 3.5)
  let #(state, moved) =
    game_connection_support.read(state, game_connection_support.a_move(1.5))
  assert game_connection_support.moves_told(moved) == [1]
  let #(map_state, _) =
    map.step(
      map_state,
      support.input(
        OwnEvent(
          step.Told(message: map.Moved(
            connection: ConnectionId(1),
            place: standing,
            seq: 1,
          )),
        ),
      ),
    )
  let #(state, asked) =
    game_connection_support.read(state, chat_line_message(4, "!summon 73465"))
  assert game_connection_support.ask_request(asked)
    == game_connection_support.summon_asked(73_465, None)
    as "the line asks the player's map run, as one"
  let assert client_connection.AskMapRun(message:, ..) =
    game_connection_support.ask_request(asked)
  let #(map_state, summoned) =
    map.step(
      map_state,
      support.input(OwnEvent(step.Asked(caller: step.CallerId(1), message:))),
    )
  let assert [#(_, start)] = map_spawn_support.starts(summoned)
    as "the map starts one creature"
  let assert RunOnly(summoned: made) = start.spawn as "as a run-only spawn"
  assert made
    == spawn_source.Summoned(
      id: SpawnId(-1),
      creature_id: Creature2Id(73_465),
      level: Some(1),
      place: standing,
    )
    as "at the place the player stands at, with the Dagun's minLevel 1 (Creature2.73465) as the line named no level"
  assert list.any(start.viewers, fn(viewer) { viewer.0 == ConnectionId(1) })
    as "the player sees the place, so it is a viewer"
  let #(_, settled) =
    map_spawn_support.start_settled(state: map_state, at_ms: 6000, spawn: -1)
  let assert [#(_, answer)] = support.replies(settled)
  let assert Summoned(unit_id:) = answer
  assert unit_id == start.unit_id
  let #(state, answered) =
    game_connection_support.answer(
      state:,
      taken: asked,
      outcome: step.Answer(FromMap(answer)),
    )
  assert support.writes(answered) == []
  // The creature, started from the summon as the server builds it.
  let assert Ok(built) =
    spawn.summoned(checks: spawn_support.summon_checks(), summoned: made)
    as "the creature's start rebuilds the spawn the map checked"
  let #(_, started) =
    creature.step(
      creature.new(creature.Settings(
        creature: start,
        spawn: built,
        kind: Kind(
          respawn_ms: 60_000,
          attack_spell4_id: Spell4Id(5649),
          attack_interval_ms: 1500,
        ),
        numbers: spawn_support.numbers,
      )),
      support.input(OwnEvent(step.Started)),
    )
  let appeared =
    list.filter_map(support.effects_of(started), fn(effect) {
      case effect {
        OwnEffect(step.Send(to: step.Connection(ConnectionId(1)), message:)) ->
          Ok(server.creature_message(outgoing: message))
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          Error(Nil)
      }
    })
  let assert [message] = appeared as "the creature sends the player its 0x262"
  let #(_, written) =
    game_connection_support.feed(state:, event: OwnEvent(Woken(message)))
  assert game_connection_support.written_ids(written) == [0x0262]
    as "opcode.0x262: the player's client is shown the creature"
  let assert ForStay(
    sent: SentByPeer(PeerNews(news: CreatureAppeared(unit:, ..), ..)),
    ..,
  ) = message
  assert unit.unit_id == unit_id && unit.creature_id == 73_465
  assert unit.tail.faction_id == 1442 && unit.tail.display_info_id == 26_578
  assert list.contains(
    unit.tail.movement_commands,
    start_movement.Position(unit_position_command.UnitPositionCommand(
      x: 0x3FC00000,
      y: 0x40200000,
      z: 0x40600000,
      blends: 0,
    )),
  )
    as "at the player's place: 1.5, 2.5 and 3.5 as 32-bit floats"
}
