//// A reply that reaches a game connection after the connection stopped
//// waiting for it: the store's worker answered after the deadline, or the
//// registry or the map did. The reply lands in the connection's mailbox with
//// the tag of a subject nobody selects any more. The connection's own selector
//// handles it and logs it through the telemetry module, so it is not left for
//// gleam_otp's actor to discard with its own warning
//// (designing-processes: a late reply is expected and handled; every process
//// logs through one module, with who and where as metadata).
////
//// The connection is the real one, served over TCP by a listener of the test's
//// own, with services the test plants: the store's service makes the late
//// reply in the connection's own process, as a wait that ended would leave it.

import character_support
import game_client
import genesis_prime/character/select.{Loaded}
import genesis_prime/character/world_entry
import genesis_prime/game/game_connection.{Services}
import genesis_prime/game/game_session
import genesis_prime/login/account.{Identity}
import genesis_prime/login/guid
import genesis_prime/map/maps
import gleam/dict
import gleam/erlang/process
import gleam/string
import log_capture
import owned_test
import serving
import tcp_client

/// How long a test waits for a line the server must log, in milliseconds.
const wait_ms = 5000

/// The session key the planted services accept, 16 bytes.
const key = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>

fn services() -> game_connection.Services {
  let assert Ok(user_id) = guid.from_wire(key) as "16 bytes"
  Services(
    redeem_session_key: fn(_key) {
      Ok(Identity(id: character_support.account_id, name: "jim", user_id:))
    },
    run_store: fn(_command) {
      // A wait that ended: its reply subject is the connection's own, and the
      // reply that comes after is a message nothing selects.
      let abandoned = process.new_subject()
      process.send(abandoned, Loaded([]))
      Loaded([])
    },
    watch_sessions: fn() { Ok(process.monitor(process.self())) },
    take_over: fn(_account_id, _notice) { Ok(Nil) },
    leave_map: fn(_map, _connection) { Nil },
    enter_map: fn(_world_id, _newcomer, _deliveries) {
      Error(maps.RegistryNotAnswering)
    },
    context: fn() {
      game_session.Context(
        select: character_support.context(rows: [
          character_support.creation_row(),
        ]),
        entry: world_entry.Context(
          realm_id: character_support.realm_id,
          world_exists: fn(_id) { True },
        ),
      )
    },
  )
}

/// Whether the line is the late reply of the connection with this peer
/// address: tests run beside each other, and a line another connection logs
/// about its own late reply is not this test's.
fn is_about_a_late_reply_of(peer: String) -> fn(log_capture.Event) -> Bool {
  fn(event: log_capture.Event) {
    string.contains(event.text, "late reply")
    && dict.get(event.metadata, "peer") == Ok(log_capture.Text(peer))
  }
}

pub fn a_reply_that_arrives_after_its_deadline_is_logged_by_the_connection_through_the_telemetry_module_test() -> Nil {
  use <- owned_test.run(30_000)
  let capture = log_capture.start()
  let running =
    serving.start(game_connection.protocol(services()), fn(settings) {
      settings
    })
  let game =
    game_client.connect(
      port: running.port,
      session_key: key,
      account_name: "jim",
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_listed] = game_client.read(game:, count: 1)
    as "the connection lists the characters, and the store's reply to it arrived late"
  let assert Ok(line) =
    log_capture.next_matching(
      capture:,
      within: wait_ms,
      matching: is_about_a_late_reply_of(tcp_client.own_address(game.socket)),
    )
    as "the late reply is logged, with the peer of this test's own connection"
  assert line.level == "warning" && string.contains(line.text, "late reply")
    as "a reply that came after its wait is an outside failure the server recovered from: a warning, written by the connection and not by the actor library that would discard it"
  assert dict.get(line.metadata, "process")
    == Ok(log_capture.Text("game_connection"))
    as "designing-processes: every line carries who and where as metadata"
  tcp_client.close(game.socket)
}
