//// The player's camp: leaving the world to character select, a feature of the
//// game connection's rule (genesis_prime/game/connection) as the player's
//// movement is (genesis_prime/game/movement). It keeps whether a camp is
//// running and says what the client's two camp messages, 0xBF and 0xC0, are
//// answered with; the rule turns that into writes, the save of the place and
//// the leave of the map.
////
//// ```
//// 0xBF 1, inside 0x38C  ─▶ take ─▶ requested(camp, True, countdown) ─▶ Answer(countdown): Write(0x92)
//// 0xBF 0, inside 0x38C  ─▶ take ─▶ requested(camp, False, _)        ─▶ Cancelled or Ignored: no effect
//// 0xC0, inside 0x38C    ─▶ take ─▶ finished(camp)                   ─▶ Finished: LeaveWorld (the rule saves,
////                                                                      leaves the map, writes 0x594)
////                                                                      or a refusal that ends the connection
//// ```
////
//// - **The client decides when the camp ends.** The server's countdown only
////   starts the client's window: the client's deadline comes from 0x92 alone,
////   and the client sends 0xC0 when it runs out or the player presses Exit
////   (opcode.0x92.countdown_source, opcode.0xc0). A Quit sends 0xC0 at any
////   time after the 0x92, and the server cannot tell it from a camp's
////   (opcode.0xbf, opcode.0xc0), so a 0xC0 is taken whenever it comes while a
////   camp runs.
//// - **Each 0xBF 1 is answered**, with a 0x92 of the setting's countdown and
////   the cancel bit clear. A second one while a camp runs restarts the
////   client's countdown, which the client allows only before its first 0x92
////   arrives (opcode.0xbf); the server keeps one camp.
//// - **0xBF 0 is never answered.** The client cleared its own camp before it
////   sent it, and a cancelling 0x92 in answer would be answered by another
////   0xBF 0 without end (lua.ExitWindow.OnPlayerCampCancel). With no camp
////   running it changes nothing: the exit window sends it after any cancelling
////   0x92, with no test (lua.ExitWindow.OnPlayerCampCancel).
//// - **0xC0 with no camp running** is a message the client never sends: it
////   sends 0xC0 only while a camp the server started with 0x92 runs
////   (opcode.0xc0). The rule ends the connection, as it does for a refused
////   movement command.
//// - **The server never cancels a camp.** The client cancels on nothing but
////   its exit window (Cancel, close, Escape, the signature buttons and every
////   PlayerCampCancel); moving, casting, combat and a hit do not
////   (lua.ExitWindow.OnCancel), and no record says retail cancelled on any of
////   them. A server cancel would also be a 0x92 with a countdown of 0 and the
////   cancel bit set, which the client always answers with a 0xBF 0
////   (lua.ExitWindow.OnPlayerCampCancel).
//// - **The camp ends with the world.** It is kept in the player's world state
////   (genesis_prime/game/world_entry `Entered`), so a camp that ends in
////   character select leaves no camp behind, and a play after it starts with
////   none, as the client's next world does (opcode.0x594.world_teardown).
//// - **Nothing is stored.** A crash of the connection ends the camp with the
////   connection.

import genesis_prime/client_connection
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/camp_countdown.{CampCountdown}
import genesis_prime/message/camp_finished
import genesis_prime/message/camp_request
import gleam/bool
import gleam/result

/// The camp messages of the player in the world, which the client sends inside
/// 0x038C (genesis_prime/game/routing's table says which id is which).
pub type Message {
  /// 0x00BF, the request to start or cancel the camp.
  CampAsked
  /// 0x00C0, the camp is finished.
  CampOver
}

/// What a camp message makes the game connection's rule carry out.
pub type Effect {
  /// Send this message to the client, in the game wrapper under the
  /// connection's cipher.
  Write(frame: Frame)
  /// Leave the world: the save timer is cancelled and the place saved, the
  /// map's run is asked to take the player out, the watch on the map is
  /// dropped and 0x0594 is written (opcode.0x594).
  LeaveWorld
}

/// Whether the player's camp is running.
pub opaque type Camp {
  Camp(running: Bool)
}

/// What the rule does about a camp message.
pub type Decision {
  /// Write 0x92 with this countdown and the cancel bit clear.
  Answer(countdown_ms: Int)
  /// A running camp was cancelled by the client: nothing is written.
  Cancelled
  /// A cancel with no camp running: nothing is written, nothing changes.
  Ignored
  /// The camp is finished: save the place, leave the map, write 0x594.
  Finished
}

/// Why a camp message is refused: the client's own code never sends it.
pub type Refusal {
  /// 0xC0 with no camp running (opcode.0xc0).
  FinishedWithNoCamp
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: client_connection.Undecoded)
}

/// No camp: the state of a player who has just entered the world.
pub fn none() -> Camp {
  Camp(running: False)
}

/// The client's 0xBF: `start` is its bit. A start makes a camp run and is
/// answered with `countdown_ms`, the setting's; a cancel clears the camp.
pub fn requested(
  camp camp: Camp,
  start start: Bool,
  countdown_ms countdown_ms: Int,
) -> #(Camp, Decision) {
  case start, camp.running {
    True, _ -> #(Camp(running: True), Answer(countdown_ms:))
    False, True -> #(none(), Cancelled)
    False, False -> #(none(), Ignored)
  }
}

/// The client's 0xC0: `Finished` while a camp runs, and the refusal when none
/// does.
pub fn finished(camp camp: Camp) -> Result(Decision, Refusal) {
  use <- bool.guard(when: !camp.running, return: Error(FinishedWithNoCamp))
  Ok(Finished)
}

/// What one camp message does: 0xBF is what `requested` makes of it, answered
/// with 0x92 for a start (`countdown_ms` is the setting's) and with nothing for
/// a cancel, and 0xC0 is what `finished` makes of it, which leaves the world.
/// A body the client's reader would refuse, or a 0xC0 with no camp, is the
/// refusal that ends the connection.
pub fn take(
  camp camp: Camp,
  message message: Message,
  body body: BitArray,
  countdown_ms countdown_ms: Int,
) -> Result(#(Camp, List(Effect)), Refusal) {
  case message {
    CampAsked ->
      camp_request.decode(body)
      |> client_connection.decoded(message_id: camp_request.message_id)
      |> result.map_error(NotDecoded)
      |> result.map(fn(decoded) {
        let #(running, decision) =
          requested(camp:, start: decoded.start == 1, countdown_ms:)
        case decision {
          Answer(countdown_ms:) -> #(running, [
            Write(frame: countdown_frame(countdown_ms)),
          ])
          Cancelled | Ignored -> #(running, [])
          Finished -> panic as "the camp's rule answers a request with no finish"
        }
      })
    CampOver ->
      camp_finished.decode(body)
      |> client_connection.decoded(message_id: camp_finished.message_id)
      |> result.map_error(NotDecoded)
      |> result.try(fn(_message) { finished(camp:) })
      |> result.map(fn(decision) {
        case decision {
          Finished -> #(camp, [LeaveWorld])
          Answer(..) | Cancelled | Ignored ->
            panic as "the camp's rule answers a finish with no request's decision"
        }
      })
  }
}

/// 0x0092 for a camp: the countdown and the cancel bit clear. The signature
/// bonuses the exit window shows (experience, elder points, 15 currencies and 19
/// account currencies) are 0, since the server has no source for them yet; the
/// currencies are the 120 and 152 bytes of 64-bit amounts the client reads
/// (opcode.0x92).
fn countdown_frame(countdown_ms: Int) -> Frame {
  let assert Ok(body) =
    camp_countdown.encode(
      CampCountdown(
        countdown_ms:,
        cancel: 0,
        experience: 0,
        elder_points: 0,
        currencies: <<0:size(960)>>,
        account_currencies: <<0:size(1216)>>,
      ),
    )
    as "a countdown below 60 s fits the message's 32 bits"
  Frame(message_id: camp_countdown.message_id, body:)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    FinishedWithNoCamp ->
      "0x00C0 holds a finished camp, but no camp is running: the client sends it only for a camp the server started"
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
  }
}
