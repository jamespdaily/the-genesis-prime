//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Every message the client sends, by its number: a variant for each message
//// of the schema that travels client to server or either way, `decode` to read
//// a body by its message's number, `encode` to write it back and `message_id`
//// to name it. A number no such message has is reported as unknown.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/camp_finished.{type CampFinished}
import genesis_prime/message/camp_request.{type CampRequest}
import genesis_prime/message/character_select_start.{type CharacterSelectStart}
import genesis_prime/message/choose_realm.{type ChooseRealm}
import genesis_prime/message/client_control_echoed.{type ClientControlEchoed}
import genesis_prime/message/client_wrapper.{type ClientWrapper}
import genesis_prime/message/close_notice.{type CloseNotice}
import genesis_prime/message/create_character.{type CreateCharacter}
import genesis_prime/message/create_character_carrier.{
  type CreateCharacterCarrier,
}
import genesis_prime/message/delete_character.{type DeleteCharacter}
import genesis_prime/message/fall_value.{type FallValue}
import genesis_prime/message/fell_below_floor.{type FellBelowFloor}
import genesis_prime/message/game_hello_reply.{type GameHelloReply}
import genesis_prime/message/login_request.{type LoginRequest}
import genesis_prime/message/move_speed_setting.{type MoveSpeedSetting}
import genesis_prime/message/movement_send_interval_answer.{
  type MovementSendIntervalAnswer,
}
import genesis_prime/message/ping.{type Ping}
import genesis_prime/message/play_character.{type PlayCharacter}
import genesis_prime/message/player_movement.{type PlayerMovement}
import genesis_prime/message/pong.{type Pong}
import genesis_prime/message/realm_select_start.{type RealmSelectStart}
import genesis_prime/message/rename_character.{type RenameCharacter}
import genesis_prime/message/terrain_loaded.{type TerrainLoaded}
import genesis_prime/message/world_message.{type WorldMessage}
import genesis_prime/message/zone_value_changed.{type ZoneValueChanged}

/// A message the client sends, decoded: one variant for each message.
pub type ClientMessage {
  Ping(message: Ping)
  Pong(message: Pong)
  CloseNotice(message: CloseNotice)
  LoginRequest(message: LoginRequest)
  GameHelloReply(message: GameHelloReply)
  CharacterSelectStart(message: CharacterSelectStart)
  RealmSelectStart(message: RealmSelectStart)
  ClientWrapper(message: ClientWrapper)
  WorldMessage(message: WorldMessage)
  CreateCharacter(message: CreateCharacter)
  CreateCharacterCarrier(message: CreateCharacterCarrier)
  PlayCharacter(message: PlayCharacter)
  DeleteCharacter(message: DeleteCharacter)
  RenameCharacter(message: RenameCharacter)
  ChooseRealm(message: ChooseRealm)
  ClientControlEchoed(message: ClientControlEchoed)
  TerrainLoaded(message: TerrainLoaded)
  CampRequest(message: CampRequest)
  CampFinished(message: CampFinished)
  PlayerMovement(message: PlayerMovement)
  ZoneValueChanged(message: ZoneValueChanged)
  MovementSendIntervalAnswer(message: MovementSendIntervalAnswer)
  MoveSpeedSetting(message: MoveSpeedSetting)
  FallValue(message: FallValue)
  FellBelowFloor(message: FellBelowFloor)
}

/// Why a body is not a message the client sends.
pub type ClientMessageError {
  /// No message the client sends has this number.
  UnknownMessage(message_id: Int)
  /// The body is not the message its number names.
  Malformed(message_id: Int, error: DecodeError)
}

/// The message a body holds, read by the decoder of the message its number
/// names.
pub fn decode(
  message_id message_id: Int,
  body body: BitArray,
) -> Result(ClientMessage, ClientMessageError) {
  case message_id {
    0x0000 -> decoded(body, message_id, ping.decode, Ping)
    0x0001 -> decoded(body, message_id, pong.decode, Pong)
    0x0002 -> decoded(body, message_id, close_notice.decode, CloseNotice)
    0x0592 -> decoded(body, message_id, login_request.decode, LoginRequest)
    0x058F -> decoded(body, message_id, game_hello_reply.decode, GameHelloReply)
    0x07E0 ->
      decoded(
        body,
        message_id,
        character_select_start.decode,
        CharacterSelectStart,
      )
    0x07A4 ->
      decoded(body, message_id, realm_select_start.decode, RealmSelectStart)
    0x0244 -> decoded(body, message_id, client_wrapper.decode, ClientWrapper)
    0x038C -> decoded(body, message_id, world_message.decode, WorldMessage)
    0x025B ->
      decoded(body, message_id, create_character.decode, CreateCharacter)
    0x025C ->
      decoded(
        body,
        message_id,
        create_character_carrier.decode,
        CreateCharacterCarrier,
      )
    0x07DD -> decoded(body, message_id, play_character.decode, PlayCharacter)
    0x0352 ->
      decoded(body, message_id, delete_character.decode, DeleteCharacter)
    0x0786 ->
      decoded(body, message_id, rename_character.decode, RenameCharacter)
    0x07DF -> decoded(body, message_id, choose_realm.decode, ChooseRealm)
    0x0635 ->
      decoded(
        body,
        message_id,
        client_control_echoed.decode,
        ClientControlEchoed,
      )
    0x00F2 -> decoded(body, message_id, terrain_loaded.decode, TerrainLoaded)
    0x00BF -> decoded(body, message_id, camp_request.decode, CampRequest)
    0x00C0 -> decoded(body, message_id, camp_finished.decode, CampFinished)
    0x0637 -> decoded(body, message_id, player_movement.decode, PlayerMovement)
    0x063A ->
      decoded(body, message_id, zone_value_changed.decode, ZoneValueChanged)
    0x00D5 ->
      decoded(
        body,
        message_id,
        movement_send_interval_answer.decode,
        MovementSendIntervalAnswer,
      )
    0x063B ->
      decoded(body, message_id, move_speed_setting.decode, MoveSpeedSetting)
    0x00FB -> decoded(body, message_id, fall_value.decode, FallValue)
    0x00FC -> decoded(body, message_id, fell_below_floor.decode, FellBelowFloor)
    _ -> Error(UnknownMessage(message_id:))
  }
}

/// The bytes of a message's body, or the first field that cannot be written.
pub fn encode(message: ClientMessage) -> Result(BitArray, EncodeError) {
  case message {
    Ping(message:) -> ping.encode(message)
    Pong(message:) -> pong.encode(message)
    CloseNotice(message:) -> close_notice.encode(message)
    LoginRequest(message:) -> login_request.encode(message)
    GameHelloReply(message:) -> game_hello_reply.encode(message)
    CharacterSelectStart(message:) -> character_select_start.encode(message)
    RealmSelectStart(message:) -> realm_select_start.encode(message)
    ClientWrapper(message:) -> client_wrapper.encode(message)
    WorldMessage(message:) -> world_message.encode(message)
    CreateCharacter(message:) -> create_character.encode(message)
    CreateCharacterCarrier(message:) -> create_character_carrier.encode(message)
    PlayCharacter(message:) -> play_character.encode(message)
    DeleteCharacter(message:) -> delete_character.encode(message)
    RenameCharacter(message:) -> rename_character.encode(message)
    ChooseRealm(message:) -> choose_realm.encode(message)
    ClientControlEchoed(message:) -> client_control_echoed.encode(message)
    TerrainLoaded(message:) -> terrain_loaded.encode(message)
    CampRequest(message:) -> camp_request.encode(message)
    CampFinished(message:) -> camp_finished.encode(message)
    PlayerMovement(message:) -> player_movement.encode(message)
    ZoneValueChanged(message:) -> zone_value_changed.encode(message)
    MovementSendIntervalAnswer(message:) ->
      movement_send_interval_answer.encode(message)
    MoveSpeedSetting(message:) -> move_speed_setting.encode(message)
    FallValue(message:) -> fall_value.encode(message)
    FellBelowFloor(message:) -> fell_below_floor.encode(message)
  }
}

/// The number of a message.
pub fn message_id(message: ClientMessage) -> Int {
  case message {
    Ping(..) -> ping.message_id
    Pong(..) -> pong.message_id
    CloseNotice(..) -> close_notice.message_id
    LoginRequest(..) -> login_request.message_id
    GameHelloReply(..) -> game_hello_reply.message_id
    CharacterSelectStart(..) -> character_select_start.message_id
    RealmSelectStart(..) -> realm_select_start.message_id
    ClientWrapper(..) -> client_wrapper.message_id
    WorldMessage(..) -> world_message.message_id
    CreateCharacter(..) -> create_character.message_id
    CreateCharacterCarrier(..) -> create_character_carrier.message_id
    PlayCharacter(..) -> play_character.message_id
    DeleteCharacter(..) -> delete_character.message_id
    RenameCharacter(..) -> rename_character.message_id
    ChooseRealm(..) -> choose_realm.message_id
    ClientControlEchoed(..) -> client_control_echoed.message_id
    TerrainLoaded(..) -> terrain_loaded.message_id
    CampRequest(..) -> camp_request.message_id
    CampFinished(..) -> camp_finished.message_id
    PlayerMovement(..) -> player_movement.message_id
    ZoneValueChanged(..) -> zone_value_changed.message_id
    MovementSendIntervalAnswer(..) -> movement_send_interval_answer.message_id
    MoveSpeedSetting(..) -> move_speed_setting.message_id
    FallValue(..) -> fall_value.message_id
    FellBelowFloor(..) -> fell_below_floor.message_id
  }
}

fn decoded(
  body: BitArray,
  message_id: Int,
  decode: fn(BitArray) -> Result(message, DecodeError),
  variant: fn(message) -> ClientMessage,
) -> Result(ClientMessage, ClientMessageError) {
  case decode(body) {
    Ok(message) -> Ok(variant(message))
    Error(error) -> Error(Malformed(message_id:, error:))
  }
}
