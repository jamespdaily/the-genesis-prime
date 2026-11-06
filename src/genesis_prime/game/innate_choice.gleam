//// The player's choice of an innate: the client's 0x16F, which it sends after it has
//// switched its own innate index and button, a feature of the game connection's
//// rule (genesis_prime/game/connection) taken from inside 0x038C with the player in
//// the world.
////
//// ```
//// 0x16F {index}, inside 0x38C ─▶ take(innate, IndexChosen, body) ─▶ index 0: a debug line, nothing written
////                                                                ─▶ any other index: a refusal that ends the connection
//// ```
////
//// - **The held count** is 1 with an innate and 0 without (genesis_prime/game/innate:
////   slot 0 only). The client's SetInnateIndex refuses an index at or above the
////   unlocked count, or of a slot with no active spell, and sends nothing for it
////   (`0x1405e7490`), so a 0x16F of such an index is one the client never sends.
//// - **Index 0** is the one slot held, which the server's index is already
////   (`opcode.0x19f` sets it at entry). The client sends 0 only before that message
////   has set its own index, which is 4 until then (`opcode.0x16f`), so nothing changes
////   and nothing is written.
//// - **The held count assumes a level below 6.** Slots 1 and 2 are left out because their
////   gates need levels 6 and 10 (`Class.spell4IdInnateAbilityActive00`); the character's
////   level is not checked here, so a character above level 5 would be refused an index
////   the client allows.
//// - **No state is kept**: the index cannot change while one slot is held.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/game/innate.{type Innate}
import genesis_prime/message/innate_index_chosen
import genesis_prime/step.{type LogLevel, LogDebug}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result

/// The innate message of the player in the world, which the client sends inside
/// 0x038C (genesis_prime/game/routing says which id is which).
pub type Message {
  /// 0x016F, the player switches to an innate.
  IndexChosen
}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// Why the choice is refused: the client's own code never sends it. The connection
/// ends.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// An index at or above the slots the player holds.
  NotHeld(index: Int, held: Int)
}

/// What the client's 0x016F is answered with: a debug line for the one slot held, or the
/// refusal for a body the client's reader refuses or an index it never sends.
pub fn take(
  innate innate: Option(Innate),
  message message: Message,
  body body: BitArray,
) -> Result(List(Effect), Refusal) {
  let IndexChosen = message
  innate_index_chosen.decode(body)
  |> client_connection.decoded(message_id: innate_index_chosen.message_id)
  |> result.map_error(NotDecoded)
  |> result.try(fn(chosen) { chosen_index(innate:, index: chosen.innate_index) })
}

fn chosen_index(
  innate innate: Option(Innate),
  index index: Int,
) -> Result(List(Effect), Refusal) {
  let held = case innate {
    Some(_) -> 1
    None -> 0
  }
  case index >= held {
    True -> Error(NotHeld(index:, held:))
    False ->
      Ok([
        Log(
          level: LogDebug,
          text: "0x016F names innate slot "
            <> int.to_string(index)
            <> ", which the player holds: nothing changes",
        ),
      ])
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NotHeld(index:, held:) ->
      "0x016F names innate slot "
      <> int.to_string(index)
      <> ", but the player holds "
      <> int.to_string(held)
      <> ": the client refuses an index at or above the slots it has unlocked and sends nothing for it"
  }
}
