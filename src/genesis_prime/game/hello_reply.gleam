//// What the game connection checks in the client's 0x058F, the reply to the
//// server's hello, beyond its decoding.
////
//// ```
//// 0x058F decoded ─▶ written(reply)            ─▶ Ok(Nil) ─▶ the hand-off is asked to take the session key
////                                              └▶ Error(NotWritten)
//// the hand-off's holder ─▶ names_handed_off(named, holder) ─▶ Ok(Nil) or Error(AccountNotHandedOff)
//// ```
////
//// - **The 64-bit value is 0 and the last 32-bit value is 3** in the client's
////   two senders (`opcode.0x58f.zero`, `opcode.0x58f.three`).
//// - **The account id** is the one 0x03DB handed the client, which the client
////   keeps and sends unchanged (`opcode.0x58f.account_id`). The server learns
////   the holder only when the hand-off answers, so the reply's id is held
////   until then. A later realm switch that hands the client another account's
////   id must put the key and the holder of the id the client keeps.
//// - **The account name** is read and not compared (`gaps`).

import genesis_prime/client_connection.{type Unwritten}
import genesis_prime/gap
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/game_hello_reply.{type GameHelloReply}
import genesis_prime/store.{type AccountId}
import gleam/bool
import gleam/int
import gleam/result

/// Why a reply is refused, which ends the connection: the client's own code
/// never sends it.
pub type Refusal {
  /// The 64-bit value is not 0, or the last value is not 3.
  NotWritten(unwritten: Unwritten)
  /// The reply names an account other than the one the hand-off gave the
  /// session key to.
  AccountNotHandedOff(named: AccountId, handed_off: AccountId)
}

/// Whether the reply's 64-bit value and last value are the ones the client
/// writes, before the hand-off is asked.
pub fn written(reply reply: GameHelloReply) -> Result(Nil, Refusal) {
  use Nil <- result.try(
    client_connection.written(
      message_id: game_hello_reply.message_id,
      field: "the 64-bit value",
      value: reply.zero,
      only: [0],
    )
    |> result.map_error(NotWritten),
  )
  client_connection.written(
    message_id: game_hello_reply.message_id,
    field: "the last value",
    value: reply.three,
    only: [3],
  )
  |> result.map_error(NotWritten)
}

/// Whether the account the reply names is the holder's, once the hand-off has
/// answered.
pub fn names_handed_off(
  named named: AccountId,
  holder holder: Holder,
) -> Result(Nil, Refusal) {
  use <- bool.guard(when: named == holder.account_id, return: Ok(Nil))
  Error(AccountNotHandedOff(named:, handed_off: holder.account_id))
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotWritten(unwritten:) -> client_connection.describe_unwritten(unwritten:)
    AccountNotHandedOff(
      named: store.AccountId(named),
      handed_off: store.AccountId(handed_off),
    ) ->
      "0x058F names account "
      <> int.to_string(named)
      <> ", but the session key was handed off for account "
      <> int.to_string(handed_off)
  }
}

/// What the rule leaves unchecked in the client's 0x058F, for the coverage
/// measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Game connection",
      missing: "A 0x058F is not refused for an account name other than the holder's login name: the client sends the name it logged in with, and whether that matches the stored login name letter for letter is not settled.",
    ),
  ]
}
