//// A scripted client's side of the login, over TCP against the server's real
//// listeners: the STS login to the game token and the auth login that hands the
//// client to the game listener. It is written from the fact file's records
//// (`scripted_client` holds the library's requests and the SRP exchange) and
//// shared by the tests that log a player in before they play.
////
//// Every wait is for bytes the server writes or for the socket to close; the
//// deadlines are for a server that does not answer, never a pause.

import frame_reader
import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{AuthWrapper}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/rc4
import genesis_prime/login/sts_xml
import genesis_prime/message/server_hello
import gleam/bit_array
import gleam/option.{type Option, None, Some}
import gleam/string
import scripted_client.{type Reply}
import seeded
import tcp_client.{type Client}

/// How long a test waits for the server to write the bytes it must, in
/// milliseconds.
const wait_ms = 5000

/// The ports the login's two listeners opened.
pub type Ports {
  Ports(sts_port: Int, auth_port: Int)
}

pub fn connect(port: Int) -> Client {
  let assert Ok(client) = tcp_client.connect(port)
    as "the client could not connect to the listener"
  client
}

pub fn send(client: Client, bytes: BitArray) -> Nil {
  let assert Ok(Nil) = tcp_client.send(client, bytes)
    as "the server closed the connection before the client finished sending"
  Nil
}

/// The client's side of an STS connection: its socket, its RC4 streams once
/// the exchange is done, and the next sequence number.
pub type StsClient {
  StsClient(
    socket: Client,
    sending: Option(rc4.Stream),
    receiving: Option(rc4.Stream),
    next_sequence: Int,
  )
}

/// What the server answered, or that it closed the connection first.
pub type Heard {
  Heard(client: StsClient, reply: Reply)
}

/// Writes a request the way the library does, through RC4 once it is on, and
/// reads the reply: bytes are deciphered as they arrive, in order, until they
/// make one whole reply.
pub fn ask(
  client client: StsClient,
  protocol protocol: String,
  command command: String,
  body body: sts_xml.Node,
) -> Heard {
  let plain =
    scripted_client.request(
      sequence: Some(client.next_sequence),
      protocol:,
      command:,
      body: sts_xml.render(body),
    )
  send(client.socket, case client.sending {
    Some(stream) -> rc4.crypt(stream, plain)
    None -> plain
  })
  let reply = read_reply(client, <<>>)
  Heard(
    client: StsClient(..client, next_sequence: client.next_sequence + 1),
    reply:,
  )
}

fn read_reply(client: StsClient, have: BitArray) -> Reply {
  let assert Ok(bytes) = tcp_client.receive_some(client.socket, wait_ms)
    as "the server did not answer the request"
  let plain = case client.receiving {
    Some(stream) -> rc4.crypt(stream, bytes)
    None -> bytes
  }
  let all = <<have:bits, plain:bits>>
  case scripted_client.read_reply(all) {
    Ok(reply) -> reply
    Error(Nil) -> read_reply(client, all)
  }
}

pub fn child(reply: Reply, name: String) -> String {
  let assert Ok(text) = scripted_client.child_text(reply, name)
    as { "the reply has no " <> name }
  text
}

/// Starts an STS connection with the one-way Connect the library sends first.
pub fn sts_connect(ports: Ports) -> StsClient {
  let socket = connect(ports.sts_port)
  send(
    socket,
    scripted_client.request(
      sequence: None,
      protocol: "Sts",
      command: "Connect",
      body: sts_xml.render(
        sts_xml.Parent("Connect", [sts_xml.Text("ConnType", "1281")]),
      ),
    ),
  )
  StsClient(socket:, sending: None, receiving: None, next_sequence: 1)
}

/// LoginStart and the SRP answer: the reply to the answer, and what the client
/// computed, for a password the client chooses.
pub fn srp_exchange(
  client client: StsClient,
  name name: String,
  password password: String,
  seed seed: Int,
) -> #(Heard, scripted_client.Exchange) {
  let started =
    ask(
      client: client,
      protocol: "Auth",
      command: "LoginStart",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("LoginName", name),
        sts_xml.Text("NetAddress", "192.168.1.5"),
      ]),
    )
  let assert Ok(server_key_data) =
    bit_array.base64_decode(child(started.reply, "KeyData"))
    as "KeyData is base64"
  let #(secret, _) = seeded.bytes(state: seed, count: 32)
  let assert Ok(exchange) =
    scripted_client.exchange(name:, password:, secret:, server_key_data:)
    as "the server's key data is the salt and B"
  let answered =
    ask(
      client: started.client,
      protocol: "Auth",
      command: "KeyData",
      body: sts_xml.Parent("Request", [
        sts_xml.Text(
          "KeyData",
          bit_array.base64_encode(exchange.key_data, True),
        ),
      ]),
    )
  #(answered, exchange)
}

/// The client's whole STS login to the game token, as the library goes.
pub fn sts_login(
  ports ports: Ports,
  name name: String,
  password password: String,
  seed seed: Int,
) -> scripted_client.StsLogin {
  let #(answered, exchange) =
    srp_exchange(
      client: sts_connect(ports),
      name: string.lowercase(name),
      password:,
      seed:,
    )
  assert answered.reply.status == 200
    as "StsConnLib64.MT.dll!0x18002d3b0: the client accepts the server's M2"
  assert child(answered.reply, "KeyData")
    == bit_array.base64_encode(
      <<32:size(32)-little, exchange.expected_m2:bits>>,
      True,
    )
    as "StsConnLib64.MT.dll!0x18002d3b0: M2 = SHA-256(A | M1 | K)"
  let assert Ok(receiving) = rc4.start(exchange.session_key)
    as "this OTP has RC4"
  let assert Ok(sending) = rc4.start(exchange.session_key) as "this OTP has RC4"
  let client =
    StsClient(
      ..answered.client,
      sending: Some(sending),
      receiving: Some(receiving),
    )
  let finished =
    ask(
      client: client,
      protocol: "Auth",
      command: "LoginFinish",
      body: sts_xml.Empty("Request"),
    )
  let user_id = child(finished.reply, "UserId")
  assert child(finished.reply, "AuthType") == "0"
    as "StsConnLib64.MT.dll!0x1800043d0: AuthType 0 is a finished login"
  let listed =
    ask(
      client: finished.client,
      protocol: "GameAccount",
      command: "ListMyAccounts",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", user_id),
        sts_xml.Text("GameCode", "wildstar"),
      ]),
    )
  let assert Ok(game_account) = sts_xml.child(listed.reply.root, "GameAccount")
    as "exactly one GameAccount (HandleListMyAccountsResult 0x1400b36c0)"
  let assert Ok(alias) = sts_xml.child(game_account, "Alias")
    as "GameAccount has an Alias"
  let token =
    ask(
      client: listed.client,
      protocol: "Auth",
      command: "RequestGameToken",
      body: sts_xml.Parent("Request", [
        sts_xml.Text("UserId", user_id),
        sts_xml.Text("GameCode", "wildstar"),
        sts_xml.Text("AccountAlias", alias.text),
      ]),
    )
  scripted_client.StsLogin(user_id:, token: child(token.reply, "Token"), name:)
}

/// Reads frames from the auth connection until there are `count` of them.
pub fn read_frames(
  client client: Client,
  have have: BitArray,
  count count: Int,
) -> List(Frame) {
  let assert Ok(frames) =
    frame_reader.read(have:, count:, next: fn() {
      tcp_client.receive_some(client, wait_ms)
    })
    as "the auth server did not write the frames"
  frames
}

/// A frame from the auth server as the client reads it: a 0x76 wrapper is
/// opened under the base key.
pub fn as_the_client_reads(sent: Frame) -> Frame {
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key"
  case sent.message_id == encrypted_frame.message_id(AuthWrapper) {
    True -> {
      let assert Ok(inner) = encrypted_frame.unwrap(sent, base)
        as "the client reads 0x76 under the base key"
      inner
    }
    False -> sent
  }
}

/// Connects to the auth listener, reads the hello and sends the login request
/// of an STS login with the given build.
pub fn auth_login(
  ports ports: Ports,
  login login: scripted_client.StsLogin,
  build build: Int,
) -> Client {
  let socket = connect(ports.auth_port)
  let assert [hello] = read_frames(client: socket, have: <<>>, count: 1)
    as "the auth server did not greet the client"
  assert hello.message_id == 0x0003
    as "opcode.0x3: the server's hello is message 3"
  let assert Ok(decoded) = server_hello.decode(hello.body)
    as "the hello decodes"
  assert decoded.build == 16_042 && decoded.message_table_checksum == 0x097998A0
    as "CheckAuthServerVersion 0x140037b70: the client checks build 16042 and checksum 0x097998A0"
  let assert Ok(request_bytes) =
    frame.encode(
      scripted_client.login_request_frame(login:, build:).message_id,
      scripted_client.login_request_frame(login:, build:).body,
    )
    as "the request frame encodes"
  send(socket, request_bytes)
  socket
}
