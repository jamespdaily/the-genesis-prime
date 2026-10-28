//// Every message the real client sent in a saved recording decodes with the
//// server's decoders, and a changed message fails the read. Expected values
//// come from these places.
//// - The recordings under `test/recording`, read by hand: the login session of
////   2026-10-26 holds two connections. Its platform login sends Connect,
////   LoginStart and KeyData as text, then 6 chunks ciphered with RC4 of 85,
////   190, 222, 31, 31 and 31 bytes; its auth connection sends one 0x0244 of
////   392 bytes and one bare ping, `07 00 00 00 00 00 00`: length 7, id 0,
////   number 0.
//// - The layout of the login request in the schema (opcode.0x592): a build of
////   32 bits first, its last field a whole number of bytes, and the bit
////   stream's rule that a body ends at its last field.
//// - The schema's directions: every message that travels client to server or
////   either way has a decoder in `client_message`, and no other does.
//// - The ping's number is below 20 (opcode.0x0).

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/login/sts_message
import genesis_prime/message/bit_stream
import genesis_prime/message/character_select_start.{CharacterSelectStart}
import genesis_prime/message/choose_realm.{ChooseRealm}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_message
import genesis_prime/message/client_wrapper.{ClientWrapper}
import genesis_prime/message/close_notice.{CloseNotice}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_carrier.{CreateCharacterCarrier}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/login_request.{LoginRequest}
import genesis_prime/message/ping.{Ping}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/pong.{Pong}
import genesis_prime/message/realm_select_start.{RealmSelectStart}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/world_message.{WorldMessage}
import genesis_prime/message_schema
import genesis_prime/recording.{
  type Recording, Auth, Chunk, ClientToServer, Game, Header, Recording,
  ServerToClient, Sts,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import owned_test
import recorded_client.{
  Bare, ClearRequestAfterKeyData, CutShort, FramesRead, GameConnectionNotRead,
  NotDecoded, NotRead, Received, StsMessageRefused, StsRead, Wrapped,
}
import recording_support
import simplifile

const recording_folder = "test/recording"

const login_session = "test/recording/2026-10-26-login"

pub fn every_client_message_in_every_saved_recording_decodes_test() -> Nil {
  use <- owned_test.run(30_000)
  let results = recorded_client.read_folder(recording_folder)
  assert results != [] as "the saved recordings were found"
  list.each(results, fn(entry) {
    let #(path, read) = entry
    assert result.replace(read, Nil) == Ok(Nil)
      as { "every client message in " <> path <> " reads" }
  })
}

pub fn every_decoded_auth_message_encodes_back_to_its_recorded_bytes_test() -> Nil {
  use <- owned_test.run(30_000)
  let received =
    recorded_client.read_folder(recording_folder)
    |> list.flat_map(fn(entry) {
      let assert Ok(read) = entry.1
        as { "every client message in " <> entry.0 <> " reads" }
      case read {
        FramesRead(messages:) -> messages
        StsRead(..) -> []
      }
    })
  assert received != [] as "the saved recordings hold auth messages"
  list.each(received, fn(message) {
    assert client_message.encode(message.message) == Ok(message.body)
      as "a decoded message encodes to the body the client sent, so every bit of it was read"
  })
}

pub fn the_login_session_holds_the_platform_logins_three_clear_requests_and_its_ciphered_rest_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(key_data) =
    bit_array.base64_decode(
      "gAAAADRocZ2ZyJjY8Pmq2A5MYebcEkkaFX8kMQ7gETXXLfVMMfDO7FntrUONhVL9UU4KNlHs3me1tCQGvYVHskNhrB10Jg/fBioaw02Mq7O9d1PPLlc95GUonsavSe4TgSJTzCmS4QQY9aOn2ycysOhrEpk/056HxhFaM1xp7jT6W0fMIAAAAM2K1eulFYukZtkhM0/TfDE+voQaEw+w/gPZM7oo+8vj",
    )
    as "the KeyData request's text, copied from the recording, is base64"
  assert recorded_client.read_file(login_session <> "/sts-001.recording")
    == Ok(StsRead(
      requests: [
        sts_message.ConnectionOpened(sts_message.Connect(
          connection_type: 400,
          connection_product_type: 0,
          connection_app_index: 0,
          connection_deployment: 0,
          connection_epoch: 0,
          address: Some("10.2.0.2"),
          product_type: 0,
          app_index: 1,
          deployment: 0,
          epoch: 814_727_909,
          program: 902,
          build: 1001,
          process: 1796,
          notify_flags: 0,
          version_flags: 0,
        )),
        sts_message.Transaction(
          sequence: 1,
          request: sts_message.LoginStart(
            login_name: "jimtest",
            net_address: "192.168.8.157",
          ),
        ),
        sts_message.Transaction(
          sequence: 2,
          request: sts_message.KeyData(bytes: key_data),
        ),
      ],
      // The read stops at the KeyData request: the library ciphers every
      // later byte with RC4 under a key made from the server's secret value,
      // which the recording does not hold.
      ciphered_bytes: 85 + 190 + 222 + 31 + 31 + 31,
    ))
    as "Connect, LoginStart and KeyData as the recording's text holds them, then the six ciphered chunks"
}

pub fn the_login_session_holds_the_login_request_in_its_wrapper_and_a_bare_ping_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(FramesRead(messages: [login, ping])) =
    recorded_client.read_file(login_session <> "/auth-001.recording")
    as "the auth connection holds two client messages"
  let assert Received(
    message: client_message.LoginRequest(message: request),
    carried: Wrapped,
    ..,
  ) = login
    as "the first is the login request, inside 0x0244"
  assert request.build == 16_042
    as "the client's build (fact archive_index.header)"
  assert request.account_name == "jimtest" as "the test account"
  assert ping
    == Received(
      message: client_message.Ping(message: Ping(sequence_number: 0)),
      body: <<0>>,
      carried: Bare,
    )
    as "the second is ping 0, bare"
}

pub fn a_game_connection_recording_fails_the_read_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let path =
    plant(folder:, name: "game-001.recording", role: Game, bytes: ping_frame())
  assert recorded_client.read_folder(folder)
    == [
      #(path, Error(NotRead(path:, role: Game, problem: GameConnectionNotRead))),
    ]
    as "a game recording is reported, never passed unread"
}

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

pub fn a_login_request_with_its_last_byte_cut_fails_naming_the_file_connection_message_and_error_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let body = recorded_login_request_body()
  let cut = bit_array.slice(body, 0, bit_array.byte_size(body) - 1)
  let assert Ok(cut) = cut as "the body is longer than one byte"
  let path =
    plant(
      folder:,
      name: "auth-001.recording",
      role: Auth,
      bytes: wrapped(id: 0x0592, body: cut, key: cipher.base_key),
    )
  assert recorded_client.read_folder(folder)
    == [
      #(
        path,
        Error(NotRead(
          path:,
          role: Auth,
          problem: NotDecoded(client_message.Malformed(
            message_id: 0x0592,
            error: bit_stream.EndOfData,
          )),
        )),
      ),
    ]
    as "the last field is whole bytes, so the cut body ends inside it"
}

pub fn a_login_request_with_one_extra_byte_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let body = <<recorded_login_request_body():bits, 0>>
  let path =
    plant(
      folder:,
      name: "auth-001.recording",
      role: Auth,
      bytes: wrapped(id: 0x0592, body:, key: cipher.base_key),
    )
  assert recorded_client.read_file(path)
    == Error(NotRead(
      path:,
      role: Auth,
      problem: NotDecoded(client_message.Malformed(
        message_id: 0x0592,
        error: bit_stream.TrailingBytes(count: 1),
      )),
    ))
    as "a body ends at its last field"
}

pub fn a_wrapper_ciphered_under_another_key_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let path =
    plant(
      folder:,
      name: "auth-001.recording",
      role: Auth,
      bytes: wrapped(
        id: 0x0592,
        body: recorded_login_request_body(),
        key: cipher.base_key + 1,
      ),
    )
  let assert Error(NotRead(path: failed, role: Auth, problem: NotDecoded(_))) =
    recorded_client.read_file(path)
    as "the inner frame deciphered under the base key is not the login request"
  assert failed == path as "the failure names the file"
}

pub fn a_clear_request_after_key_data_in_the_same_chunk_fails_the_read_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Every byte after the KeyData request is ciphered, so a request read in
  // the clear after it is never counted as ciphered or passed as read.
  let key_data = <<
    "POST /Auth/KeyData STS/1.0\r\ns:2\r\nl:45\r\n\r\n<Request>\n<KeyData>AAAA</KeyData>\n</Request>\n":utf8,
  >>
  let ping = <<"POST /Sts/Ping STS/1.0\r\nl:0\r\n\r\n":utf8>>
  let path =
    plant(folder:, name: "sts-001.recording", role: Sts, bytes: <<
      key_data:bits,
      ping:bits,
    >>)
  assert recorded_client.read_file(path)
    == Error(NotRead(path:, role: Sts, problem: ClearRequestAfterKeyData))
    as "the Ping after KeyData is reported"
}

pub fn an_unknown_platform_login_command_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let path =
    plant(folder:, name: "sts-001.recording", role: Sts, bytes: <<
      "POST /Sts/Unknown STS/1.0\r\nl:0\r\n\r\n":utf8,
    >>)
  assert recorded_client.read_file(path)
    == Error(NotRead(
      path:,
      role: Sts,
      problem: StsMessageRefused(sts_message.UnknownCommand(
        protocol: "Sts",
        command: "Unknown",
      )),
    ))
    as "the login has no command Unknown"
}

pub fn a_recording_that_ends_inside_a_message_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let whole =
    wrapped(
      id: 0x0592,
      body: recorded_login_request_body(),
      key: cipher.base_key,
    )
  let assert Ok(cut) = bit_array.slice(whole, 0, 391)
    as "the recorded 0x0244 is 392 bytes"
  let auth = plant(folder:, name: "auth-001.recording", role: Auth, bytes: cut)
  assert recorded_client.read_file(auth)
    == Error(NotRead(path: auth, role: Auth, problem: CutShort(bytes: 391)))
    as "391 of the frame's 392 bytes are there"
  let request = <<"POST /Sts/Connect STS/1.0\r\nl:218\r\n\r\n<Connect>\n":utf8>>
  let sts = plant(folder:, name: "sts-001.recording", role: Sts, bytes: request)
  assert recorded_client.read_file(sts)
    == Error(NotRead(
      path: sts,
      role: Sts,
      problem: CutShort(bytes: bit_array.byte_size(request)),
    ))
    as "the request's head says 218 bytes of body and 10 are there"
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
    #(0x00F2, client_message.TerrainLoaded(message: TerrainLoaded(field_1: 2))),
  ]
}

/// The body of the login request in the saved login session.
fn recorded_login_request_body() -> BitArray {
  let assert Ok(FramesRead(messages: [Received(body:, ..), ..])) =
    recorded_client.read_file(login_session <> "/auth-001.recording")
    as "the saved login session's auth connection reads"
  body
}

/// The bytes of 0x0244 around the frame of `id` and `body`, ciphered under
/// `key`.
fn wrapped(id id: Int, body body: BitArray, key key: Int) -> BitArray {
  let assert Ok(chosen) = cipher.new(key:) as "the key is not 0"
  let assert Ok(bytes) =
    encrypted_frame.wrap(
      wrapper: encrypted_frame.ClientWrapper,
      inner: Frame(message_id: id, body:),
      cipher: chosen,
    )
    as "the frame is within the size limit"
  bytes
}

/// The bytes of ping 0 in its own frame.
fn ping_frame() -> BitArray {
  let assert Ok(bytes) = frame.encode(message_id: 0x0000, body: <<0>>)
    as "a ping is 7 bytes"
  bytes
}

/// Writes a recording of `role` named `name` in `folder`, holding `bytes` sent
/// by the client in one chunk after one chunk from the server, and returns its
/// path.
fn plant(
  folder folder: String,
  name name: String,
  role role: recording.Role,
  bytes bytes: BitArray,
) -> String {
  let path = folder <> "/" <> name
  let planted: Recording =
    Recording(header: Header(..recording_support.header(), role:), chunks: [
      Chunk(direction: ServerToClient, microseconds: 0, bytes: <<1, 2, 3>>),
      Chunk(direction: ClientToServer, microseconds: 10, bytes:),
    ])
  let assert Ok(encoded) = recording.encode(planted)
    as "the planted recording's fields are within their widths"
  let assert Ok(Nil) = simplifile.write_bits(path, encoded)
    as "the planted recording was written"
  path
}
