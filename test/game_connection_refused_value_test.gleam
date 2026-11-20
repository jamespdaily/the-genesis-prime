//// A value the client's own code never writes, in a message it does send, ends
//// the game connection's whole connection the way a body its reader refuses
//// does: one error line naming the message, nothing written, and the place
//// saved first when the player is in the world. The value rules themselves are
//// tested where they live (`routing_test`, `hello_reply_test`, `dropped_test`);
//// this tests only that the connection ends for each. Expected values come
//// from these places.
//// - `opcode.0x38c.send_kind`: the client writes the kinds 3, 11 and 19 only.
//// - `opcode.0x58f.zero`, `opcode.0x58f.three` and `opcode.0x58f.account_id`:
////   the client writes 0, 3 and the account id of its 0x03DB.
//// - `opcode.0x23d.category`: the category is 35 from every sender.
//// - The refusals of a body the client's reader would refuse
////   (`game_connection_dropped_test`): an error line, the place saved, then
////   the end.

import connection_rule_support as support
import dropped_support
import game_client
import game_connection_support as connection_support
import genesis_prime/client_connection.{FromHandOff}
import genesis_prime/game/connection as game_connection
import genesis_prime/hand_off.{Taken}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/statistic_event.{StatisticEvent}
import genesis_prime/step.{LogError}
import gleam/list
import gleam/option.{None}
import owned_test

/// 0x038C of a kind, carrying 0x082D, as the client sends it under the session
/// key.
fn carried_with_kind(kind kind: Int) -> BitArray {
  connection_support.keyed_message(
    message_id: 0x038C,
    body: game_client.world_body(kind:, message_id: 0x082D, body: <<1>>),
  )
}

/// A connection in the world, or in character select, that reads these bytes
/// and refuses them: one error line saying `message`, nothing written, and the
/// end, after the save when the player is in the world.
fn assert_ended(
  state state: game_connection.State,
  bytes bytes: BitArray,
  message message: String,
  in_world in_world: Bool,
  label label: String,
) -> Nil {
  let #(refusing, taken) = connection_support.read(state:, bytes:)
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as { label <> ": one error line" }
  assert support.says(line, message)
    as { label <> ": the line names the message" }
  assert support.writes(taken) == []
    as { label <> ": the client is told nothing" }
  let taken = case in_world {
    False -> taken
    True -> {
      assert connection_support.ask_request(taken)
        == connection_support.save_asked(1, connection_support.entry_place())
        as { label <> ": the place is saved first" }
      assert !support.stops(taken)
      connection_support.answer(
        state: refusing,
        taken:,
        outcome: connection_support.place_saved(),
      ).1
    }
  }
  assert support.stops(taken) as { label <> ": the connection ends" }
}

pub fn a_value_the_client_never_writes_ends_the_connection_test() -> Nil {
  use <- owned_test.run(10_000)
  // 0x038C's kind, in character select and in the world.
  assert_ended(
    state: connection_support.in_select(),
    bytes: carried_with_kind(kind: 4),
    message: "0x038C",
    in_world: False,
    label: "0x038C kind 4 in character select",
  )
  assert_ended(
    state: connection_support.in_world(),
    bytes: carried_with_kind(kind: 4),
    message: "0x038C",
    in_world: True,
    label: "0x038C kind 4 in the world",
  )
  // 0x058F's 64-bit value and last value, in the first read: the hand-off is
  // not asked.
  list.each(
    [
      #(GameHelloReply(..connection_support.reply(), zero: 1), "zero 1"),
      #(GameHelloReply(..connection_support.reply(), three: 2), "three 2"),
    ],
    fn(row) {
      let #(reply, what) = row
      let #(_, taken) =
        connection_support.read(
          state: connection_support.connected(),
          bytes: connection_support.hello_reply_of(reply),
        )
      let assert [line] = support.logs_of(step: taken, level: LogError)
        as { "0x058F with " <> what <> ": one error line" }
      assert support.says(line, "0x058F")
      assert support.asked(taken) == None
        as { "0x058F with " <> what <> ": no hand-off ask" }
      assert support.writes(taken) == []
      assert support.stops(taken)
    },
  )
  // 0x058F's account id other than the holder's, once the hand-off answered.
  let reply = connection_support.reply()
  let #(state, taken) =
    connection_support.read(
      state: connection_support.connected(),
      bytes: connection_support.hello_reply_of(
        GameHelloReply(..reply, account_id: reply.account_id + 1),
      ),
    )
  assert support.asked(taken) != None
    as "the hand-off is asked to take the key before the account is known"
  let #(_, taken) =
    connection_support.answer(
      state:,
      taken:,
      outcome: step.Answer(
        FromHandOff(Taken(holder: connection_support.holder())),
      ),
    )
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "0x058F with another account id: one error line"
  assert support.says(line, "0x058F")
  assert support.asked(taken) == None as "no claim is asked for another account"
  assert support.writes(taken) == []
  assert support.stops(taken)
  // 0x023D's category, in the world.
  assert_ended(
    state: connection_support.in_world(),
    bytes: connection_support.world_message(
      message_id: 0x023D,
      body: dropped_support.statistic_event_changed(fn(event) {
        StatisticEvent(..event, category: 34)
      }),
    ),
    message: "0x023D",
    in_world: True,
    label: "0x023D with category 34 in the world",
  )
}
