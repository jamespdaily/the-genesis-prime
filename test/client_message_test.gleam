//// The messages the client sends reach their own decoders. Expected values come
//// from these places.
//// - The schema's directions: every message that travels client to server or
////   either way has a decoder in `client_message`, and no other does.
//// - The ping's number is below 20 (opcode.0x0).
//// - An empty body ends inside the login request's first field, a build of 32
////   bits (opcode.0x592).

import genesis_prime/message/ability_hold.{AbilityHold}
import genesis_prime/message/bit_stream
import genesis_prime/message/camp_finished.{CampFinished}
import genesis_prime/message/camp_request.{CampRequest}
import genesis_prime/message/cancel_cast.{CancelCast}
import genesis_prime/message/cast_ability.{CastAbility}
import genesis_prime/message/cast_result
import genesis_prime/message/character_select_start.{CharacterSelectStart}
import genesis_prime/message/choose_realm.{ChooseRealm}
import genesis_prime/message/choose_resurrection.{ChooseResurrection}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_message
import genesis_prime/message/client_option.{ClientOption}
import genesis_prime/message/client_wrapper.{ClientWrapper}
import genesis_prime/message/close_notice.{CloseNotice}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_carrier.{CreateCharacterCarrier}
import genesis_prime/message/credd_exchange_request.{CreddExchangeRequest}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/dialog_responses_shown.{DialogResponsesShown}
import genesis_prime/message/fall_value.{FallValue}
import genesis_prime/message/fell_below_floor.{FellBelowFloor}
import genesis_prime/message/frame_time_report.{FrameTimeReport}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/graphics_report.{GraphicsReport}
import genesis_prime/message/innate_index_chosen.{InnateIndexChosen}
import genesis_prime/message/input_key_set_request.{InputKeySetRequest}
import genesis_prime/message/interaction_request.{InteractionRequest}
import genesis_prime/message/login_request.{LoginRequest}
import genesis_prime/message/move_speed_setting.{MoveSpeedSetting}
import genesis_prime/message/movement_command
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_send_interval_answer.{
  MovementSendIntervalAnswer,
}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/network_report.{NetworkReport}
import genesis_prime/message/own_auctions_request.{OwnAuctionsRequest}
import genesis_prime/message/own_commodity_orders_request.{
  OwnCommodityOrdersRequest,
}
import genesis_prime/message/ping.{Ping}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/player_movement.{PlayerMovement}
import genesis_prime/message/pong.{Pong}
import genesis_prime/message/pre_game_activity.{PreGameActivity}
import genesis_prime/message/realm_select_start.{RealmSelectStart}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/scanbot_request.{ScanbotRequest}
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/message/send_whisper.{SendWhisper}
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/trade_cancel.{TradeCancel}
import genesis_prime/message/watchdog_report.{WatchdogReport}
import genesis_prime/message/window_opened.{WindowOpened}
import genesis_prime/message/world_message.{WorldMessage}
import genesis_prime/message/world_zone_changed.{WorldZoneChanged}
import genesis_prime/message_schema
import gleam/int
import gleam/list
import owned_test
import simplifile

pub fn every_message_the_client_sends_reaches_its_own_decoder_test() -> Nil {
  use <- owned_test.run(30_000)
  let samples = client_samples()
  let assert Ok(text) = simplifile.read("src/genesis_prime/message/schema.toml")
    as "the schema file could not be read"
  let assert Ok(schema) = message_schema.parse(text)
    as "the schema file is a schema"
  let client_ids =
    list.filter_map(schema.messages, fn(message) {
      case message.direction {
        message_schema.ClientToServer | message_schema.Both -> Ok(message.id)
        message_schema.ServerToClient -> Error(Nil)
      }
    })
  assert list.sort(list.map(samples, fn(sample) { sample.0 }), int.compare)
    == list.sort(client_ids, int.compare)
    as "there is one sample for each message the schema says the client sends"
  list.each(samples, fn(sample) {
    let #(id, message) = sample
    let assert Ok(body) = client_message.encode(message)
      as "every sample field is within its width"
    assert client_message.decode(message_id: id, body:) == Ok(message)
      as "the body decodes as the message its number names"
    assert client_message.message_id(message) == id
      as "the message names its own number"
  })
}

pub fn a_number_no_client_message_has_is_unknown_and_a_refused_body_is_malformed_test() -> Nil {
  use <- owned_test.run(30_000)
  assert client_message.decode(message_id: 0x0003, body: <<>>)
    == Error(client_message.UnknownMessage(message_id: 0x0003))
    as "0x0003 travels server to client only (opcode.0x3)"
  assert client_message.decode(message_id: 0xFFFF, body: <<>>)
    == Error(client_message.UnknownMessage(message_id: 0xFFFF))
    as "no message has the number 0xFFFF"
  assert client_message.decode(message_id: 0x0000, body: <<20>>)
    == Error(client_message.Malformed(
      message_id: 0x0000,
      error: bit_stream.UnexpectedValue(field: "sequence_number", value: 20),
    ))
    as "a ping's number is below 20 (opcode.0x0)"
  assert client_message.decode(message_id: 0x0592, body: <<>>)
    == Error(client_message.Malformed(
      message_id: 0x0592,
      error: bit_stream.EndOfData,
    ))
    as "an empty body ends inside the login request's first field"
}

/// One message of each kind the client sends, with its number, each field
/// within its width in the schema.
fn client_samples() -> List(#(Int, client_message.ClientMessage)) {
  [
    #(0x0000, client_message.Ping(message: Ping(sequence_number: 19))),
    #(0x0001, client_message.Pong(message: Pong(sequence_number: 200))),
    #(0x0002, client_message.CloseNotice(message: CloseNotice)),
    #(
      0x0592,
      client_message.LoginRequest(message: LoginRequest(
        build: 16_042,
        files_digest: 0x0123_4567_89AB_CDEF,
        account_name: "account",
        user_id: <<1:size(128)>>,
        game_token: <<2:size(128)>>,
        field_6: 6,
        field_7: 7,
        field_8: 8,
        field_9: 9,
        processor_manufacturer: "maker",
        processor_name: "processor",
        processor_description: "description",
        processor_family: 25,
        processor_level: 26,
        processor_revision: 27,
        processor_clock_speed: 4200,
        processor_core_count: 8,
        memory_mebibytes: 32_768,
        video_adapter_description: "adapter",
        video_adapter_vendor_id: 0x10DE,
        video_adapter_device_id: 0x2684,
        video_adapter_subsystem_id: 3,
        video_adapter_revision: 161,
        video_adapter_memory_mebibytes: 4095,
        processor_architecture: 9,
        windows_version: 10,
        service_pack: 0,
        os_flags: 1,
        realm_data_center_id: 9,
      )),
    ),
    #(
      0x058F,
      client_message.GameHelloReply(message: GameHelloReply(
        field_1: 1,
        session_key: <<3:size(128)>>,
        field_3: 3,
        account_name: "account",
        field_5: 5,
      )),
    ),
    #(
      0x07E0,
      client_message.CharacterSelectStart(message: CharacterSelectStart),
    ),
    #(0x07A4, client_message.RealmSelectStart(message: RealmSelectStart)),
    #(
      0x0244,
      client_message.ClientWrapper(
        message: ClientWrapper(inner_frame: <<7:little-size(32), 0x92, 0x05, 9>>),
      ),
    ),
    #(
      0x038C,
      client_message.WorldMessage(
        message: WorldMessage(field_1: 3, inner_frame: <<
          6:little-size(32),
          0xF2,
          0x00,
        >>),
      ),
    ),
    #(
      0x025B,
      client_message.CreateCharacter(
        message: CreateCharacter(
          creation_id: 4,
          name: "Name",
          path: 1,
          customisation_labels: [1, 2],
          customisation_values: [3, 4],
          bone_values: [0, 1, 2],
        ),
      ),
    ),
    #(
      0x025C,
      client_message.CreateCharacterCarrier(
        message: CreateCharacterCarrier(inner_frame: <<
          6:little-size(32),
          0x5B,
          0x02,
        >>),
      ),
    ),
    #(
      0x07DD,
      client_message.PlayCharacter(message: PlayCharacter(character_id: 5)),
    ),
    #(
      0x0352,
      client_message.DeleteCharacter(message: DeleteCharacter(character_id: 6)),
    ),
    #(
      0x0786,
      client_message.RenameCharacter(message: RenameCharacter(
        character_id: 7,
        name: "Other",
      )),
    ),
    #(0x07DF, client_message.ChooseRealm(message: ChooseRealm(realm_id: 1))),
    #(
      0x0635,
      client_message.ClientControlEchoed(message: ClientControlEchoed(
        echo_value: 8,
      )),
    ),
    #(
      0x00F2,
      client_message.TerrainLoaded(message: TerrainLoaded(world_zone_id: 2)),
    ),
    #(0x00BF, client_message.CampRequest(message: CampRequest(start: 1))),
    #(0x00C0, client_message.CampFinished(message: CampFinished)),
    #(
      0x0637,
      client_message.PlayerMovement(
        message: PlayerMovement(client_clock: 0x1234, commands: [
          movement_command.Time(MovementTime(time: 0x1335)),
          movement_command.Mode(MovementMode(mode: 3)),
        ]),
      ),
    ),
    #(
      0x063A,
      client_message.WorldZoneChanged(message: WorldZoneChanged(
        old_world_zone_id: 1,
        new_world_zone_id: 2,
      )),
    ),
    #(
      0x00D5,
      client_message.MovementSendIntervalAnswer(
        message: MovementSendIntervalAnswer(field_1: 1, field_2: 0, field_3: 3),
      ),
    ),
    #(
      0x063B,
      client_message.MoveSpeedSetting(message: MoveSpeedSetting(move_speed: 2)),
    ),
    #(0x00FB, client_message.FallValue(message: FallValue(field_1: 0x40000000))),
    #(
      0x00FC,
      client_message.FellBelowFloor(message: FellBelowFloor(
        no_ground: 1,
        camera_x: 0x3F800000,
        camera_y: 0x40000000,
        camera_z: 0xC0400000,
      )),
    ),
    #(
      0x01C3,
      client_message.SendChatLine(message: SendChatLine(
        channel_type: 4,
        channel_id: 0,
        text: [0x48, 0x65, 0x6C, 0x6C, 0x6F],
        formats: [],
        chat_message_id: 1,
      )),
    ),
    #(
      0x01D4,
      client_message.SendWhisper(message: SendWhisper(
        target_name: bit_stream.utf16_units("Ab Cd"),
        target_realm_name: [],
        text: [0x48, 0x69],
        formats: [],
        chat_message_id: 2,
        account: 0,
      )),
    ),
    #(
      0x009A,
      client_message.CastAbility(message: CastAbility(
        client_cast_id: 0x80002803,
        bag_index: 2,
        target_unit_id: 0x12345,
        press: 1,
      )),
    ),
    #(
      0x04DB,
      client_message.AbilityHold(message: AbilityHold(
        bag_index: 2,
        target_unit_id: 0x12345,
        held: 1,
      )),
    ),
    #(
      0x016F,
      client_message.InnateIndexChosen(message: InnateIndexChosen(
        innate_index: 2,
      )),
    ),
    #(
      0x0801,
      client_message.CancelCast(message: CancelCast(
        cast_id: 0x80002804,
        reason: cast_result.SpellCancelled,
        field_3: 1,
      )),
    ),
    #(
      0x015A,
      client_message.ChooseResurrection(message: ChooseResurrection(
        unit_id: 0x1001,
        choice: 1,
        field_3: 0,
      )),
    ),
    #(
      0x023C,
      client_message.WatchdogReport(message: WatchdogReport(
        field_1: 0x0123_4567_89AB_CDEF,
        field_2: 2,
        field_3: 3,
        field_4: 0x3F80_0000,
        field_5: 0x4000_0000,
        field_6: 0x4040_0000,
        field_7: 7,
      )),
    ),
    #(
      0x0240,
      client_message.FrameTimeReport(message: FrameTimeReport(
        field_1: 1,
        field_2: 2,
        field_3: 0x3F80_0000,
        field_4: 0x4000_0000,
        field_5: 0x4040_0000,
        field_6: 0x4080_0000,
        field_7: 7,
      )),
    ),
    #(
      0x023F,
      client_message.NetworkReport(message: NetworkReport(
        field_1: 1,
        field_2: 2,
        field_3: 3,
        field_4: 4,
      )),
    ),
    #(
      0x023E,
      client_message.GraphicsReport(message: GraphicsReport(
        average_1: 0x3F80_0000,
        average_2: 0x4000_0000,
        average_3: 0x4040_0000,
        average_4: 0x4080_0000,
        raw_1: 0x40A0_0000,
        raw_2: 0x40C0_0000,
        raw_3: 0x40E0_0000,
        raw_4: 0x4100_0000,
      )),
    ),
    #(
      0x023D,
      client_message.WindowOpened(
        message: WindowOpened(
          field_1: 35,
          window_id: 512,
          character_id: 13,
          field_4: 0,
          open_time: 90_720,
          field_6: 0,
          field_7: 0,
          field_8: 0,
          window_name: [
            0x52, 0x65, 0x73, 0x75, 0x72, 0x72, 0x65, 0x63, 0x74, 0x44, 0x69,
            0x61, 0x6C, 0x6F, 0x67,
          ],
        ),
      ),
    ),
    #(0x0241, client_message.PreGameActivity(message: PreGameActivity)),
    #(
      0x012B,
      client_message.ClientOption(message: ClientOption(
        option_type: 1,
        value: 1,
      )),
    ),
    #(
      0x0180,
      client_message.ScanbotRequest(message: ScanbotRequest(
        profile: 0x1234,
        from_command: 1,
      )),
    ),
    #(0x03ED, client_message.OwnAuctionsRequest(message: OwnAuctionsRequest)),
    #(
      0x03EC,
      client_message.OwnCommodityOrdersRequest(
        message: OwnCommodityOrdersRequest,
      ),
    ),
    #(
      0x0269,
      client_message.CreddExchangeRequest(message: CreddExchangeRequest),
    ),
    #(0x018F, client_message.TradeCancel(message: TradeCancel)),
    #(
      0x0570,
      client_message.InputKeySetRequest(message: InputKeySetRequest(
        key_set_id: 0x0123_4567_89AB,
      )),
    ),
    #(
      0x07EA,
      client_message.InteractionRequest(message: InteractionRequest(
        unit_id: 0x0001_2345,
        kind: 37,
      )),
    ),
    #(
      0x0356,
      client_message.DialogResponsesShown(message: DialogResponsesShown),
    ),
  ]
}
