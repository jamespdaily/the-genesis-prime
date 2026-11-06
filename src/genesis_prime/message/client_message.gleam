//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Every message the client sends, by its number: a variant for each message
//// of the schema that travels client to server or either way, `decode` to read
//// a body by its message's number, `encode` to write it back, `message_id` to
//// give its number and `name` to give its name in the schema. A number no such
//// message has is reported as unknown.

import genesis_prime/message/ability_hold.{type AbilityHold}
import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/camp_finished.{type CampFinished}
import genesis_prime/message/camp_request.{type CampRequest}
import genesis_prime/message/cancel_cast.{type CancelCast}
import genesis_prime/message/cast_ability.{type CastAbility}
import genesis_prime/message/character_select_start.{type CharacterSelectStart}
import genesis_prime/message/choose_realm.{type ChooseRealm}
import genesis_prime/message/choose_resurrection.{type ChooseResurrection}
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
import genesis_prime/message/innate_index_chosen.{type InnateIndexChosen}
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
import genesis_prime/message/send_chat_line.{type SendChatLine}
import genesis_prime/message/send_whisper.{type SendWhisper}
import genesis_prime/message/terrain_loaded.{type TerrainLoaded}
import genesis_prime/message/world_message.{type WorldMessage}
import genesis_prime/message/world_zone_changed.{type WorldZoneChanged}

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
  WorldZoneChanged(message: WorldZoneChanged)
  MovementSendIntervalAnswer(message: MovementSendIntervalAnswer)
  MoveSpeedSetting(message: MoveSpeedSetting)
  FallValue(message: FallValue)
  FellBelowFloor(message: FellBelowFloor)
  SendChatLine(message: SendChatLine)
  SendWhisper(message: SendWhisper)
  CastAbility(message: CastAbility)
  AbilityHold(message: AbilityHold)
  InnateIndexChosen(message: InnateIndexChosen)
  CancelCast(message: CancelCast)
  ChooseResurrection(message: ChooseResurrection)
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
      decoded(body, message_id, world_zone_changed.decode, WorldZoneChanged)
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
    0x01C3 -> decoded(body, message_id, send_chat_line.decode, SendChatLine)
    0x01D4 -> decoded(body, message_id, send_whisper.decode, SendWhisper)
    0x009A -> decoded(body, message_id, cast_ability.decode, CastAbility)
    0x04DB -> decoded(body, message_id, ability_hold.decode, AbilityHold)
    0x016F ->
      decoded(body, message_id, innate_index_chosen.decode, InnateIndexChosen)
    0x0801 -> decoded(body, message_id, cancel_cast.decode, CancelCast)
    0x015A ->
      decoded(body, message_id, choose_resurrection.decode, ChooseResurrection)
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
    WorldZoneChanged(message:) -> world_zone_changed.encode(message)
    MovementSendIntervalAnswer(message:) ->
      movement_send_interval_answer.encode(message)
    MoveSpeedSetting(message:) -> move_speed_setting.encode(message)
    FallValue(message:) -> fall_value.encode(message)
    FellBelowFloor(message:) -> fell_below_floor.encode(message)
    SendChatLine(message:) -> send_chat_line.encode(message)
    SendWhisper(message:) -> send_whisper.encode(message)
    CastAbility(message:) -> cast_ability.encode(message)
    AbilityHold(message:) -> ability_hold.encode(message)
    InnateIndexChosen(message:) -> innate_index_chosen.encode(message)
    CancelCast(message:) -> cancel_cast.encode(message)
    ChooseResurrection(message:) -> choose_resurrection.encode(message)
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
    WorldZoneChanged(..) -> world_zone_changed.message_id
    MovementSendIntervalAnswer(..) -> movement_send_interval_answer.message_id
    MoveSpeedSetting(..) -> move_speed_setting.message_id
    FallValue(..) -> fall_value.message_id
    FellBelowFloor(..) -> fell_below_floor.message_id
    SendChatLine(..) -> send_chat_line.message_id
    SendWhisper(..) -> send_whisper.message_id
    CastAbility(..) -> cast_ability.message_id
    AbilityHold(..) -> ability_hold.message_id
    InnateIndexChosen(..) -> innate_index_chosen.message_id
    CancelCast(..) -> cancel_cast.message_id
    ChooseResurrection(..) -> choose_resurrection.message_id
  }
}

/// The name of a message in the schema.
pub fn name(message: ClientMessage) -> String {
  case message {
    Ping(..) -> "ping"
    Pong(..) -> "pong"
    CloseNotice(..) -> "close_notice"
    LoginRequest(..) -> "login_request"
    GameHelloReply(..) -> "game_hello_reply"
    CharacterSelectStart(..) -> "character_select_start"
    RealmSelectStart(..) -> "realm_select_start"
    ClientWrapper(..) -> "client_wrapper"
    WorldMessage(..) -> "world_message"
    CreateCharacter(..) -> "create_character"
    CreateCharacterCarrier(..) -> "create_character_carrier"
    PlayCharacter(..) -> "play_character"
    DeleteCharacter(..) -> "delete_character"
    RenameCharacter(..) -> "rename_character"
    ChooseRealm(..) -> "choose_realm"
    ClientControlEchoed(..) -> "client_control_echoed"
    TerrainLoaded(..) -> "terrain_loaded"
    CampRequest(..) -> "camp_request"
    CampFinished(..) -> "camp_finished"
    PlayerMovement(..) -> "player_movement"
    WorldZoneChanged(..) -> "world_zone_changed"
    MovementSendIntervalAnswer(..) -> "movement_send_interval_answer"
    MoveSpeedSetting(..) -> "move_speed_setting"
    FallValue(..) -> "fall_value"
    FellBelowFloor(..) -> "fell_below_floor"
    SendChatLine(..) -> "send_chat_line"
    SendWhisper(..) -> "send_whisper"
    CastAbility(..) -> "cast_ability"
    AbilityHold(..) -> "ability_hold"
    InnateIndexChosen(..) -> "innate_index_chosen"
    CancelCast(..) -> "cancel_cast"
    ChooseResurrection(..) -> "choose_resurrection"
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
