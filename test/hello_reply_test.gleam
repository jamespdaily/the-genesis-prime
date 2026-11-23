//// What the game connection checks in the client's 0x058F beyond decoding
//// (`genesis_prime/game/hello_reply`). Expected values come from these places.
//// - `opcode.0x58f.zero` and `opcode.0x58f.three`: the client's two senders
////   write the 64-bit value 0 and the last value 3.
//// - `opcode.0x58f.account_id`: the first value is the account id of the
////   0x03DB the client was handed.
//// - The recorded reply: the 0x058F the real client sent in the committed
////   session (`wire_replay_support.committed_session`), decoded from its
////   bytes. In each of the 32
////   logins of this server's sittings the reply holds account id 1, 0 and 3
////   (sitting 2026-11-05-main, sequence 30, and the others).

import genesis_prime/client_connection.{Unwritten}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/hello_reply.{AccountNotHandedOff, NotWritten}
import genesis_prime/hand_off.{Holder}
import genesis_prime/login/guid
import genesis_prime/message/client_message
import genesis_prime/message/game_hello_reply.{
  type GameHelloReply, GameHelloReply,
}
import genesis_prime/recorded_message.{Received}
import genesis_prime/store.{AccountId}
import gleam/list
import owned_test
import wire_replay_support as support

/// The 0x058F the real client sent in the committed recorded session, decoded
/// from its bytes.
fn recorded() -> GameHelloReply {
  let #(messages, _) = support.committed_frames(game_connection.rule_name)
  let assert [
    Received(message: client_message.GameHelloReply(message:), ..),
    ..
  ] = messages
    as "the committed session's game connection starts with the hello reply"
  message
}

/// A holder of this account, as the hand-off gives it for the session key.
fn holder_of(account_id account_id: Int) -> hand_off.Holder {
  let assert Ok(game_account_id) = guid.from_wire(<<0:128>>)
    as "16 bytes are a GUID"
  Holder(
    account_id: AccountId(account_id),
    login_name: "genesis",
    game_account_id:,
  )
}

fn not_written(field field: String, value value: Int) -> hello_reply.Refusal {
  NotWritten(Unwritten(message_id: 0x058F, field:, value:))
}

pub fn each_value_the_client_never_writes_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      GameHelloReply(..recorded(), zero: 1),
      Error(not_written(field: "the 64-bit value", value: 1)),
      "opcode.0x58f.zero: the 64-bit value is 0 from both senders",
    ),
    #(
      GameHelloReply(..recorded(), zero: 0xFFFF_FFFF_FFFF_FFFF),
      Error(not_written(field: "the 64-bit value", value: 0xFFFF_FFFF_FFFF_FFFF)),
      "the widest value is no 0",
    ),
    #(
      GameHelloReply(..recorded(), three: 0),
      Error(not_written(field: "the last value", value: 0)),
      "opcode.0x58f.three: the last value is 3 from both senders",
    ),
    #(
      GameHelloReply(..recorded(), three: 2),
      Error(not_written(field: "the last value", value: 2)),
      "2 is below the 3 both senders write",
    ),
    #(
      GameHelloReply(..recorded(), three: 4),
      Error(not_written(field: "the last value", value: 4)),
      "4 is above the 3 both senders write",
    ),
  ]
  list.each(rows, fn(row) {
    let #(reply, expected, why) = row
    assert hello_reply.written(reply:) == expected as why
  })
  assert hello_reply.names_handed_off(
      named: AccountId(8),
      holder: holder_of(account_id: 7),
    )
    == Error(AccountNotHandedOff(named: AccountId(8), handed_off: AccountId(7)))
    as "opcode.0x58f.account_id: the client sends the id its 0x03DB gave, which is the holder's"
}

pub fn the_recorded_reply_with_its_hand_off_is_taken_test() -> Nil {
  use <- owned_test.run(5000)
  assert hello_reply.written(reply: recorded()) == Ok(Nil)
    as "the recorded reply holds 0 and 3"
  assert hello_reply.names_handed_off(
      named: AccountId(recorded().account_id),
      holder: holder_of(account_id: 1),
    )
    == Ok(Nil)
    as "the committed session's account is id 1 (its fixture.sql), and the reply sends it back"
  assert hello_reply.written(
      reply: GameHelloReply(..recorded(), account_name: "another", session_key: <<
        0:128,
      >>),
    )
    == Ok(Nil)
    as "the account name and the session key are not compared here (the hand-off's lookup is the key's check)"
}
