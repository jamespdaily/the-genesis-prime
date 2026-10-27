//// The login's two listeners for the tests that start the server's tree:
//// settings on ports the system picks and listener names of their own, so
//// tests run side by side without sharing a port or a name.

import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import gleam/bit_array
import gleam/crypto
import gleam/option.{None}
import gleam/string

/// The realm the auth rule hands clients to.
pub fn realm() -> auth_connection.Realm {
  auth_connection.Realm(
    id: 1,
    name: "Nexus",
    game_server: Endpoint(address: 0x7F000001, port: 24_000),
  )
}

/// The login's listeners on ports the system picks, with names no other test
/// uses, no recording and nothing planted.
pub fn login() -> server.Login {
  let unique =
    string.lowercase(bit_array.base16_encode(crypto.strong_random_bytes(8)))
  server.Login(
    sts_listener: "test-sts-" <> unique,
    sts_port: 0,
    sts: sts_connection.Settings(
      ask_deadline_ms: 5000,
      game_token_lifetime_ms: 60_000,
    ),
    auth_listener: "test-auth-" <> unique,
    auth_port: 0,
    auth: auth_connection.Settings(
      realm: realm(),
      ask_deadline_ms: 5000,
      session_key_lifetime_ms: 60_000,
      planted: None,
    ),
    send_deadline_ms: 300,
    connection_shutdown_ms: 1000,
    sts_recorder: None,
    auth_recorder: None,
  )
}
