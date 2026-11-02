//// The realm the auth server hands the client to, as a wire recording's header
//// holds it (genesis_prime/wire_recording) and as the auth rule's settings hold
//// it, so a replay builds the server the session ran on from the recording.

import genesis_prime/login/auth_connection.{type Realm, Realm}
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/wire_recording

/// The realm as the header records it.
pub fn to_header(realm realm: Realm) -> wire_recording.Realm {
  wire_recording.Realm(
    id: realm.id,
    name: realm.name,
    address: realm.game_server.address,
    port: realm.game_server.port,
  )
}

/// The realm a header records, as the auth rule's settings hold it.
pub fn from_header(recorded recorded: wire_recording.Realm) -> Realm {
  Realm(
    id: recorded.id,
    name: recorded.name,
    game_server: Endpoint(address: recorded.address, port: recorded.port),
  )
}
