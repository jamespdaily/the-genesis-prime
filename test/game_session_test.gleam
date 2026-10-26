//// The rule of a game connection: the hello, the 0x58F that carries the
//// session key, the cipher the key makes, and the routing of each client
//// message to character select and the world entry. Expected values come from
//// the client's records: the hello is message 3 inside 0x3DC under the base key
//// and the client answers with 0x58F inside 0x244 under it (opcode.0x3,
//// opcode.0x3dc, opcode.0x58f, opcode.0x244), after which both ways use the
//// cipher the session key makes (opcode.0x3dc: "re-keyed after 0x58f"); the
//// create request is the 0x25B frame ciphered into 0x25C, which goes inside
//// 0x244 (opcode.0x25c); a world message travels inside 0x38C (opcode.0x38c);
//// 0x7E0, 0x352, 0x786 and 0x7DD are character select's requests
//// (opcode.0x7e0, opcode.0x352, opcode.0x786, opcode.0x7dd); and 0x262 and
//// 0x355 create and remove a unit (opcode.0x262, opcode.0x355).

import character_support
import genesis_prime/character/character
import genesis_prime/character/name
import genesis_prime/character/select
import genesis_prime/character/world_entry
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{
  ClientWrapper, CreateCharacterWrapper,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/game_session.{
  type Effect, type Session, End, Log, MalformedMessage, RedeemSessionKey, Send,
  Store,
}
import genesis_prime/login/account.{Identity}
import genesis_prime/login/guid
import genesis_prime/map/delivery.{Appeared, Disappeared}
import genesis_prime/map/position.{Position}
import genesis_prime/map/unit.{PlayerUnit}
import genesis_prime/message/bit_stream
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/disconnect_notice
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/server_hello
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_destroyed
import genesis_prime/message/world_message.{WorldMessage}
import gleam/list
import gleam/string
import owned_test

/// The session key the tests' client holds.
const key = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>

fn base() -> Cipher {
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key"
  base
}

/// The cipher the session key makes after 0x58F (HandleLoginGameServerHello
/// 0x140038120).
fn session_cipher() -> Cipher {
  let assert Ok(made) = cipher.session_key(key, cipher.base_key)
    as "the session key is 16 bytes"
  let assert Ok(session) = cipher.new(made) as "the session key makes a cipher"
  session
}

fn identity() -> account.Identity {
  let assert Ok(user_id) = guid.from_wire(key) as "16 bytes"
  Identity(id: character_support.account_id, name: "jim", user_id:)
}

fn context() -> game_session.Context {
  game_session.Context(
    select: character_support.context(rows: [character_support.creation_row()]),
    entry: world_entry.Context(
      realm_id: character_support.realm_id,
      world_exists: fn(world_id) { world_id == 51 },
    ),
  )
}

/// A frame the client sent, as the socket's owner cuts it: the message inside
/// 0x244 under the cipher.
fn client_frame(
  cipher cipher: Cipher,
  message_id message_id: Int,
  body body: BitArray,
) -> Frame {
  let assert Ok(bytes) =
    encrypted_frame.wrap(ClientWrapper, Frame(message_id, body), cipher)
    as "the message wraps"
  let assert Ok(#([outer], <<>>)) = frame.decode(bytes) as "one frame"
  outer
}

/// The create request the way LuaCreateCharacter sends it.
fn create_frame(body body: BitArray) -> Frame {
  let assert Ok(carried) =
    encrypted_frame.wrap(
      CreateCharacterWrapper,
      Frame(0x025B, body),
      session_cipher(),
    )
    as "0x25B wraps into 0x25C"
  let assert Ok(#([carrier], <<>>)) = frame.decode(carried) as "one frame"
  client_frame(cipher: session_cipher(), message_id: 0x025C, body: carrier.body)
}

/// A world message the way SendWorldMessage sends it: inside 0x38C.
fn world_frame(message_id message_id: Int, body body: BitArray) -> Frame {
  let assert Ok(inner) = frame.encode(message_id, body) as "the message frames"
  let assert Ok(carried) =
    world_message.encode(WorldMessage(field_1: 3, inner_frame: inner))
    as "0x38C encodes"
  client_frame(cipher: session_cipher(), message_id: 0x038C, body: carried)
}

/// The messages the effects send, each opened from its 0x3DC wrapper under the
/// cipher.
fn messages(effects: List(Effect), cipher: Cipher) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(bytes) -> {
        let assert Ok(#([outer], <<>>)) = frame.decode(bytes)
          as "a send is one frame"
        assert outer.message_id == 0x03DC
          as "opcode.0x3dc: a game server message goes inside 0x3DC"
        let assert Ok(inner) = encrypted_frame.unwrap(outer, cipher)
          as "the message opens under the cipher"
        Ok(inner)
      }
      RedeemSessionKey(_)
      | Store(_)
      | game_session.JoinMap(..)
      | Log(..)
      | End(_) -> Error(Nil)
    }
  })
}

fn hello_reply() -> Frame {
  let assert Ok(body) =
    game_hello_reply.encode(GameHelloReply(
      field_1: 0,
      session_key: key,
      field_3: 0,
      account_name: "jim",
      field_5: 3,
    ))
    as "0x58F encodes"
  client_frame(cipher: base(), message_id: 0x058F, body:)
}

/// A connection whose key was redeemed.
fn keyed() -> Session {
  let #(session, _) = game_session.start()
  let #(session, effects) =
    game_session.receive(session, hello_reply(), context())
  assert effects == [RedeemSessionKey(key)]
    as "opcode.0x58f: the key in the message is redeemed"
  let #(session, effects) =
    game_session.session_key_redeemed(session, Ok(identity()))
  assert effects == [] as "a redeemed key starts nothing by itself"
  session
}

/// A connection in idle character select with the characters.
fn idle(characters: List(character.Character)) -> Session {
  let #(session, effects) =
    game_session.receive(
      keyed(),
      client_frame(cipher: session_cipher(), message_id: 0x07E0, body: <<>>),
      context(),
    )
  assert effects == [Store(select.LoadCharacters(character_support.account_id))]
  let #(session, _) =
    game_session.stored(session, select.Loaded(characters), context())
  session
}

fn own(id: Int) -> character.Character {
  character_support.character(id:, name: "Ab Cd")
}

pub fn a_new_connection_is_sent_the_hello_inside_0x3dc_under_the_base_key_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) = game_session.start()
  let assert [hello] = messages(effects, base())
    as "opcode.0x3dc: the server's hello goes inside 0x3DC under the base key, which the game connection holds until 0x58F"
  assert hello.message_id == 0x0003 as "opcode.0x3: the hello is message 3"
  let assert Ok(decoded) = server_hello.decode(hello.body)
    as "the hello decodes"
  assert decoded.build == 16_042 && decoded.message_table_checksum == 0x097998A0
    as "opcode.0x3: a game server's hello carries the build and checksum the client checks"
}

pub fn the_session_key_in_0x58f_is_redeemed_and_the_session_keys_cipher_takes_over_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, effects) =
    game_session.receive(
      keyed(),
      client_frame(cipher: session_cipher(), message_id: 0x07E0, body: <<>>),
      context(),
    )
  assert effects == [Store(select.LoadCharacters(character_support.account_id))]
    as "opcode.0x7e0: after 0x58F the client starts character select under the session key's cipher, and the account is the key's"
  let #(_, effects) = game_session.stored(session, select.Loaded([]), context())
  let assert [listed] = messages(effects, session_cipher())
    as "opcode.0x3dc: the list goes inside 0x3DC under the session key's cipher"
  assert listed.message_id == 0x0117
}

pub fn a_session_key_the_hand_off_refuses_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = game_session.start()
  let #(session, _) = game_session.receive(session, hello_reply(), context())
  let #(session, effects) =
    game_session.session_key_redeemed(session, Error(Nil))
  assert effects == [End(game_session.SessionKeyRefused)]
    as "a key that is unknown, used or expired ends the connection"
  let #(_, effects) =
    game_session.receive(
      session,
      client_frame(cipher: base(), message_id: 0x07E0, body: <<>>),
      context(),
    )
  assert effects == [] as "an ended connection takes nothing more"
}

pub fn a_message_other_than_0x58f_before_the_key_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = game_session.start()
  let #(_, effects) =
    game_session.receive(
      session,
      client_frame(cipher: base(), message_id: 0x07E0, body: <<>>),
      context(),
    )
  assert effects == [End(game_session.UnexpectedMessage(message_id: 0x07E0))]
    as "opcode.0x58f: the first message on a game connection is 0x58F"
}

pub fn a_frame_that_is_not_a_0x244_wrapper_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = game_session.start()
  let #(_, effects) =
    game_session.receive(session, Frame(0x07E0, <<>>), context())
  assert effects == [End(game_session.BadWrapper)]
    as "opcode.0x244: every message the client sends travels inside 0x244"
}

pub fn a_0x58f_that_does_not_decode_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) = game_session.start()
  let #(_, effects) =
    game_session.receive(
      session,
      client_frame(cipher: base(), message_id: 0x058F, body: <<1>>),
      context(),
    )
  assert effects
    == [
      End(MalformedMessage(message_id: 0x058F, error: bit_stream.EndOfData)),
    ]
    as "a body that ends inside a field is malformed, and the connection ends"
}

pub fn a_create_request_inside_0x25c_is_decoded_and_given_to_character_select_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) =
    create_character.encode(
      CreateCharacter(
        creation_id: 277,
        name: "Ab Cd",
        path: 2,
        customisation_labels: [1, 2],
        customisation_values: [3, 4],
        bone_values: [0x3F800000, 0xBF000000],
      ),
    )
    as "0x25B encodes"
  let #(_, effects) =
    game_session.receive(idle([]), create_frame(body:), context())
  let assert [Store(select.InsertCharacter(new))] = effects
    as "opcode.0x25c: the 0x25B frame inside 0x25C is a create request for the account"
  assert new.account_id == character_support.account_id
  assert new.name == "Ab Cd"
  assert new.creation_id == 277
}

pub fn a_create_request_that_does_not_decode_ends_the_connection_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    game_session.receive(idle([]), create_frame(body: <<1>>), context())
  assert effects
    == [End(MalformedMessage(message_id: 0x025B, error: bit_stream.EndOfData))]
    as "opcode.0x25b: a body that ends inside a field is malformed; nothing reaches the store"
}

pub fn a_rename_request_is_decoded_and_given_to_character_select_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) =
    rename_character.encode(RenameCharacter(character_id: 11, name: "Ef Gh"))
    as "0x786 encodes"
  let #(_, effects) =
    game_session.receive(
      idle([own(11)]),
      client_frame(cipher: session_cipher(), message_id: 0x0786, body:),
      context(),
    )
  assert effects
    == [
      Store(select.RenameStored(
        account_id: character_support.account_id,
        character_id: 11,
        name: "Ef Gh",
      )),
    ]
    as "opcode.0x786: rename a character of the account"
}

pub fn a_delete_request_is_decoded_and_given_to_character_select_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) =
    delete_character.encode(DeleteCharacter(character_id: 11))
    as "0x352 encodes"
  let #(_, effects) =
    game_session.receive(
      idle([own(11)]),
      client_frame(cipher: session_cipher(), message_id: 0x0352, body:),
      context(),
    )
  assert effects
    == [
      Store(select.DeleteStored(
        account_id: character_support.account_id,
        character_id: 11,
      )),
    ]
    as "opcode.0x352: delete a character of the account"
}

pub fn a_play_request_asks_the_map_to_join_the_characters_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 11))
    as "0x7DD encodes"
  let #(_, effects) =
    game_session.receive(
      idle([own(11)]),
      client_frame(cipher: session_cipher(), message_id: 0x07DD, body:),
      context(),
    )
  assert effects
    == [
      game_session.JoinMap(world_id: 51, newcomer: character.newcomer(own(11))),
    ]
    as "opcode.0x7dd: play this character, which enters the world on the world of its place"
}

fn playing_unit() -> unit.PlayerUnit {
  PlayerUnit(
    id: 1,
    character_id: 11,
    name: "Ab Cd",
    race_id: 1,
    class_id: 3,
    gender: 1,
    path: 2,
    position: Position(x: 1.0, y: -2.5, z: 100.25),
  )
}

fn waiting_for_the_map() -> Session {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 11))
    as "0x7DD encodes"
  let #(session, _) =
    game_session.receive(
      idle([own(11)]),
      client_frame(cipher: session_cipher(), message_id: 0x07DD, body:),
      context(),
    )
  session
}

pub fn the_maps_answer_sends_the_world_messages_and_0xf2_inside_0x38c_sends_0x61_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, effects) =
    game_session.map_answered(
      waiting_for_the_map(),
      game_session.MapJoined(playing_unit()),
      context(),
    )
  assert list.map(messages(effects, session_cipher()), fn(sent) {
      sent.message_id
    })
    == [0x00AD, 0x0262, 0x019B, 0x00F1]
    as "CheckWorldLoaded 0x1403E8000: 0xAD, the player's unit 0x262, 0x19B and 0xF1, in that order"
  let assert Ok(body) = terrain_loaded.encode(TerrainLoaded(field_1: 9))
    as "0xF2 encodes"
  let #(_, effects) =
    game_session.receive(
      session,
      world_frame(message_id: 0x00F2, body:),
      context(),
    )
  let assert [entered] = messages(effects, session_cipher())
    as "opcode.0xf2: the client's 0xF2 inside 0x38C is answered with 0x61"
  assert entered.message_id == 0x0061
}

pub fn a_map_that_refuses_the_character_sends_0x162_and_character_select_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, effects) =
    game_session.map_answered(
      waiting_for_the_map(),
      game_session.MapRefusedCharacter,
      context(),
    )
  let assert [refused] = messages(effects, session_cipher())
    as "opcode.0x162: the client returns to idle character select when the world refuses"
  assert refused.message_id == 0x0162
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 11))
    as "0x7DD encodes"
  let #(_, effects) =
    game_session.receive(
      session,
      client_frame(cipher: session_cipher(), message_id: 0x07DD, body:),
      context(),
    )
  assert effects
    == [
      game_session.JoinMap(world_id: 51, newcomer: character.newcomer(own(11))),
    ]
    as "the player may choose again"
}

pub fn a_map_that_does_not_answer_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    game_session.map_answered(
      waiting_for_the_map(),
      game_session.MapNotAnswering,
      context(),
    )
  assert effects == [End(game_session.MapAway)]
    as "a map that did not answer may hold the unit, so the connection ends and the map takes the unit off with it"
}

pub fn a_delivery_of_a_unit_in_range_is_sent_as_0x262_and_one_out_of_range_as_0x355_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, effects) =
    game_session.map_answered(
      waiting_for_the_map(),
      game_session.MapJoined(playing_unit()),
      context(),
    )
  assert effects != []
  let other =
    PlayerUnit(..playing_unit(), id: 2, character_id: 12, name: "Ef Gh")
  let #(session, effects) =
    game_session.delivered(session, Appeared(other), context())
  let assert [created] = messages(effects, session_cipher())
    as "opcode.0x262: an unit that came into range is created"
  assert created.message_id == 0x0262
  let assert Ok(decoded) = unit_create_player.decode(created.body)
    as "0x262 decodes"
  assert decoded.unit_id == 2
    && decoded.character_id == 12
    && decoded.name == "Ef Gh"
    && decoded.realm_id == character_support.realm_id
    as "the unit is the other player's, on the connection's realm"
  let #(_, effects) =
    game_session.delivered(session, Disappeared(unit_id: 2), context())
  let assert [removed] = messages(effects, session_cipher())
    as "opcode.0x355: a unit that left is removed"
  assert removed.message_id == 0x0355
  let assert Ok(decoded) = unit_destroyed.decode(removed.body)
    as "0x355 decodes"
  assert decoded.unit_id == 2
}

pub fn a_message_no_rule_handles_is_logged_once_and_the_connection_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let unhandled =
    client_frame(cipher: session_cipher(), message_id: 0x07DF, body: <<>>)
  let #(session, effects) = game_session.receive(idle([]), unhandled, context())
  let assert [Log(game_session.WarningLevel, text)] = effects
    as "building-an-engine: an unhandled message is logged, not dropped silently"
  assert string.contains(text, "0x07DF")
    as "the line names the message by its four-digit number"
  let #(_, effects) = game_session.receive(session, unhandled, context())
  assert effects == [] as "an unhandled message is logged once for each number"
}

pub fn a_request_character_select_cannot_take_ends_the_connection_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 11))
    as "0x7DD encodes"
  let #(_, effects) =
    game_session.receive(
      keyed(),
      client_frame(cipher: session_cipher(), message_id: 0x07DD, body:),
      context(),
    )
  assert effects
    == [
      End(game_session.CharacterSelectBreach(select.RequestBeforeStart)),
    ]
    as "HandleCharacterSelectMessage 0x140020EA0: a request before 0x7E0 breaks the client's own order"
}

pub fn a_refusal_is_logged_as_a_warning_and_a_store_that_failed_as_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(too_short) =
    create_character.encode(
      CreateCharacter(
        creation_id: 277,
        name: "A B",
        path: 2,
        customisation_labels: [],
        customisation_values: [],
        bone_values: [0x3F800000, 0xBF000000],
      ),
    )
    as "0x25B encodes"
  let #(_, effects) =
    game_session.receive(idle([]), create_frame(body: too_short), context())
  assert list.any(effects, fn(effect) {
    case effect {
      Log(game_session.WarningLevel, text) ->
        text == select.describe_refusal(select.NameRefused(name.TooShort(3)))
      Send(_)
      | RedeemSessionKey(_)
      | Store(_)
      | game_session.JoinMap(..)
      | Log(game_session.ErrorLevel, _)
      | End(_) -> False
    }
  })
    as "a name the client's own rule refuses is the player's mistake: a warning that holds the reason"
  let assert Ok(body) =
    create_character.encode(
      CreateCharacter(
        creation_id: 277,
        name: "Ab Cd",
        path: 2,
        customisation_labels: [],
        customisation_values: [],
        bone_values: [0x3F800000, 0xBF000000],
      ),
    )
    as "0x25B encodes"
  let #(session, _) =
    game_session.receive(idle([]), create_frame(body:), context())
  let #(_, effects) =
    game_session.stored(session, select.Unavailable, context())
  assert list.any(effects, fn(effect) {
    case effect {
      Log(game_session.ErrorLevel, text) ->
        text == select.describe_refusal(select.StoreUnavailable)
      Send(_)
      | RedeemSessionKey(_)
      | Store(_)
      | game_session.JoinMap(..)
      | Log(game_session.WarningLevel, _)
      | End(_) -> False
    }
  })
    as "designing-processes: a database that failed is an outside failure, never the player's mistake, and is logged as an error"
}

pub fn every_end_has_a_sentence_and_a_level_test() -> Nil {
  use <- owned_test.run(5000)
  let reasons = [
    game_session.BadWrapper,
    game_session.UnexpectedMessage(message_id: 0x07E0),
    MalformedMessage(message_id: 0x025B, error: bit_stream.EndOfData),
    game_session.SessionKeyRefused,
    game_session.CharacterSelectBreach(select.StartedTwice),
    game_session.WorldEntryBreach(world_entry.BeganTwice),
    game_session.MapAway,
    game_session.MapEnded,
    game_session.StoreAway(select.ListNotLoaded),
    game_session.AnswerNotBuilt,
  ]
  assert list.all(reasons, fn(reason) { game_session.describe(reason) != "" })
  assert game_session.level_of(game_session.AnswerNotBuilt)
    == game_session.ErrorLevel
    as "a message the server could not build is a bug"
  assert game_session.level_of(game_session.SessionKeyRefused)
    == game_session.WarningLevel
}

pub fn a_database_that_cannot_give_the_list_ends_the_connection_as_an_error_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, effects) =
    game_session.receive(
      keyed(),
      client_frame(cipher: session_cipher(), message_id: 0x07E0, body: <<>>),
      context(),
    )
  assert effects == [Store(select.LoadCharacters(character_support.account_id))]
    as "opcode.0x7e0: the list is the account's characters"
  let #(_, effects) =
    game_session.stored(session, select.Unavailable, context())
  assert effects == [End(game_session.StoreAway(select.ListNotLoaded))]
    as "designing-processes: a database that failed is an outside failure of the server, never the player's breach"
  assert game_session.level_of(game_session.StoreAway(select.ListNotLoaded))
    == game_session.ErrorLevel
    as "an outside failure the connection cannot go on without is logged as an error"
  assert game_session.describe(game_session.StoreAway(select.ListNotLoaded))
    == select.describe_outage(select.ListNotLoaded)
}

pub fn a_write_answered_unavailable_reads_the_characters_again_and_then_answers_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(body) =
    create_character.encode(
      CreateCharacter(
        creation_id: 277,
        name: "Ab Cd",
        path: 2,
        customisation_labels: [],
        customisation_values: [],
        bone_values: [0x3F800000, 0xBF000000],
      ),
    )
    as "0x25B encodes"
  let #(session, effects) =
    game_session.receive(idle([]), create_frame(body:), context())
  assert list.any(effects, fn(effect) {
    case effect {
      Store(select.InsertCharacter(_)) -> True
      Store(select.LoadCharacters(_))
      | Store(select.RenameStored(..))
      | Store(select.DeleteStored(..))
      | Send(_)
      | RedeemSessionKey(_)
      | game_session.JoinMap(..)
      | Log(_, _)
      | End(_) -> False
    }
  })
    as "the create asks the store"
  let #(session, effects) =
    game_session.stored(session, select.Unavailable, context())
  assert list.contains(
    effects,
    Store(select.LoadCharacters(character_support.account_id)),
  )
    as "a write that was answered Unavailable is followed by a read of the characters, so the client's list is the store's"
  assert messages(effects, session_cipher()) == []
    as "nothing is sent until the list is read"
  let #(_, effects) =
    game_session.stored(session, select.Loaded([own(11)]), context())
  let assert [failure, listed] = messages(effects, session_cipher())
    as "the failure is answered, then the list"
  assert failure.message_id == 0x00DC && listed.message_id == 0x0117
    as "opcode.0xdc and opcode.0x117: the create result, then the character list the store holds"
}

pub fn the_end_of_the_map_that_holds_the_unit_ends_the_connection_as_a_warning_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, _) =
    game_session.map_answered(
      waiting_for_the_map(),
      game_session.MapJoined(playing_unit()),
      context(),
    )
  let #(session, effects) = game_session.map_ended(session)
  assert effects == [End(game_session.MapEnded)]
    as "a map that starts again is empty, so the unit the connection joined is gone, and the connection ends so the player enters again"
  assert game_session.level_of(game_session.MapEnded)
    == game_session.WarningLevel
    as "designing-processes: an outside failure the server recovered from is a warning"
  assert game_session.describe(game_session.MapEnded) != ""
  let #(_, effects) = game_session.map_ended(session)
  assert effects == [] as "a connection that has ended takes no more"
}

fn create_body(labels labels: Int, bones bones: Int) -> BitArray {
  let assert Ok(body) =
    create_character.encode(CreateCharacter(
      creation_id: 277,
      name: "Ab Cd",
      path: 2,
      customisation_labels: list.repeat(1, labels),
      customisation_values: list.repeat(1, labels),
      bone_values: list.repeat(0x3F800000, bones),
    ))
    as "0x25B encodes"
  body
}

pub fn a_create_request_with_more_bone_values_or_labels_than_the_client_can_send_does_not_decode_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    game_session.receive(
      idle([]),
      create_frame(body: create_body(labels: 1, bones: 49)),
      context(),
    )
  assert effects
    == [
      End(MalformedMessage(
        message_id: 0x025B,
        error: bit_stream.UnexpectedValue("bone_values", 49),
      )),
    ]
    as "opcode.0x25b.counts: 48 bone values is the most the client sends, so 49 is bad input at the edge and ends the connection"
  let #(_, effects) =
    game_session.receive(
      idle([]),
      create_frame(body: create_body(labels: 28, bones: 2)),
      context(),
    )
  assert effects
    == [
      End(MalformedMessage(
        message_id: 0x025B,
        error: bit_stream.UnexpectedValue("customisation_labels", 28),
      )),
    ]
    as "opcode.0x25b.counts: CharacterCustomizationLabel has 27 rows and each label is sent once, so 28 labels is bad input"
  let #(_, effects) =
    game_session.receive(
      idle([]),
      create_frame(body: create_body(labels: 15, bones: 48)),
      context(),
    )
  assert !list.any(effects, fn(effect) {
    case effect {
      End(_) -> True
      Send(_)
      | RedeemSessionKey(_)
      | Store(_)
      | game_session.JoinMap(..)
      | Log(_, _) -> False
    }
  })
    as "the most the client sends, 48 bone values, is decoded; the rule decides what is made of it"
}

pub fn a_connection_told_to_end_by_a_second_login_sends_0x36a_with_reason_19_and_ends_test() -> Nil {
  use <- owned_test.run(5000)
  let #(session, effects) = game_session.taken_over(idle([own(11)]))
  let assert [notice] = messages(effects, session_cipher())
    as "opcode.0x36a: the player is told it is disconnected"
  assert notice.message_id == 0x036A
  let assert Ok(decoded) = disconnect_notice.decode(notice.body)
    as "0x36A decodes"
  assert decoded.reason == 19
    as "opcode.0x36a: reason 19 is 'This account has been disconnected', the only reason about the account; that retail sent it is a guess (no recording of a double login)"
  assert list.contains(effects, End(game_session.SessionTakenOver))
    as "the connection ends after the notice"
  let #(_, effects) = game_session.taken_over(session)
  assert effects == [] as "a connection that has ended takes no more"
  assert game_session.level_of(game_session.SessionTakenOver)
    == game_session.WarningLevel
}

pub fn a_slot_that_is_not_free_ends_the_connection_as_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    game_session.account_claimed(keyed(), game_session.SlotNotFreed)
  assert effects == [End(game_session.SessionNotFreed)]
    as "a connection that could not take its account's slot does not play beside the old one"
  assert game_session.level_of(game_session.SessionNotFreed)
    == game_session.ErrorLevel
    as "the old connection that did not end is an outside failure the server cannot repair"
  let #(_, effects) =
    game_session.account_claimed(keyed(), game_session.SlotFree)
  assert effects == [] as "a free slot starts nothing by itself"
  assert game_session.describe(game_session.SessionTakenOver) != ""
    && game_session.describe(game_session.SessionNotFreed) != ""
}
