//// The client's reports and requests the server takes and drops: each is
//// decoded and checked, nothing is kept and nothing is sent. They are features
//// of the game connection's rule (genesis_prime/game/connection), and
//// genesis_prime/game/routing says which id is which.
////
//// ```
//// 0x23C, 0x240, 0x23F, 0x23E, 0x23D, 0x241 ─▶ take ─▶ Ok(Nil), nothing logged, nothing sent
//// 0x12B, 0x180, 0x3ED, 0x3EC, 0x269, 0x18F, 0x570 ─▶ take ─▶ Ok(Nil), nothing logged, nothing sent
//// a body the client's reader refuses, or a value its senders never write ─▶ Error(Refusal)
//// ```
////
//// - **The reports** 0x23C, 0x240, 0x23F, 0x23E and 0x23D are telemetry: the
////   client waits for no reply and nothing the player sees depends on them
////   (`opcode.0x23c.body`, `opcode.0x240.body`, `opcode.0x23f.body`,
////   `opcode.0x23e`, `opcode.0x23d`).
//// - **0x241** is the client's activity signal on its realm-select and
////   character-select connection, which has no reader for an answer
////   (`opcode.0x241`).
//// - **The requests** 0x180, 0x3ED, 0x3EC, 0x269, 0x18F and 0x570 are taken
////   without the reply they ask for: the reply each waits for is stated as a
////   gap of the coverage measure, with the issue that closes it.
//// - **0x23D's name** is refused when it has more UTF-16 units than GameFormula
////   row 2375's dataint02, which the client's sender reads as the limit and
////   does not send past (`opcode.0x23d`). The 6 bits before the window id are
////   read and not checked.
//// - **0x12B's type** is 0 (the input flags) or 1 (the shared-challenge
////   preference): the senders write no other (`opcode.0x12b`).
//// - **A signed 32-bit field of 0x23C** is read as unsigned 32 bits: the bits
////   are the same, and nothing is done with the value.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/message/bit_stream
import genesis_prime/message/client_option
import genesis_prime/message/credd_exchange_request
import genesis_prime/message/frame_time_report
import genesis_prime/message/graphics_report
import genesis_prime/message/input_key_set_request
import genesis_prime/message/network_report
import genesis_prime/message/own_auctions_request
import genesis_prime/message/own_commodity_orders_request
import genesis_prime/message/pre_game_activity
import genesis_prime/message/scanbot_request
import genesis_prime/message/trade_cancel
import genesis_prime/message/watchdog_report
import genesis_prime/message/window_opened
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/result

/// The GameFormula row whose dataint02 is the longest window name the client
/// sends (`FUN_140200220(0x947)`, `opcode.0x23d`).
const window_name_formula = 2375

/// The report or request the client sent, which the connection takes from
/// inside 0x038C or, for 0x241, on its own.
pub type Message {
  /// 0x023C, the client's watchdog report.
  WatchdogReport
  /// 0x0240, the client's frame time report.
  FrameTimeReport
  /// 0x023F, the client's network report.
  NetworkReport
  /// 0x023E, the client's graphics report.
  GraphicsReport
  /// 0x023D, a window the client opened.
  WindowOpened
  /// 0x0241, the client's activity signal before the world.
  PreGameActivity
  /// 0x012B, a client option.
  ClientOption
  /// 0x0180, the Scientist's scanbot request.
  ScanbotRequest
  /// 0x03ED, the request for the player's own auctions.
  OwnAuctionsRequest
  /// 0x03EC, the request for the player's own commodity orders.
  OwnCommodityOrdersRequest
  /// 0x0269, the request for the CREDD exchange price.
  CreddExchangeRequest
  /// 0x018F, the cancel of a trade.
  TradeCancel
  /// 0x0570, the request for an input key set.
  InputKeySetRequest
}

/// Why a message is refused: the client's own code never sends it. The
/// connection ends.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A window name longer than the limit the client's sender holds.
  WindowNameTooLong(units: Int, limit: Int)
  /// An option type no sender writes.
  OptionTypeNotSent(option_type: Int)
  /// A shared-challenge preference that is not 0 or 1.
  SharedChallengeNotABool(value: Int)
  /// Input flags with flag 1 clear or a bit above flag 8 set.
  InputFlagsNotSent(value: Int)
}

/// The message taken: `Ok(Nil)` when the body is one the client sends, and the
/// refusal for a body its reader refuses or a value its senders never write.
pub fn take(
  message message: Message,
  body body: BitArray,
  tables tables: table_store.Tables,
) -> Result(Nil, Refusal) {
  case message {
    WatchdogReport ->
      watchdog_report.decode(body)
      |> decoded(watchdog_report.message_id)
    FrameTimeReport ->
      frame_time_report.decode(body)
      |> decoded(frame_time_report.message_id)
    NetworkReport ->
      network_report.decode(body)
      |> decoded(network_report.message_id)
    GraphicsReport ->
      graphics_report.decode(body)
      |> decoded(graphics_report.message_id)
    WindowOpened ->
      window_opened.decode(body)
      |> client_connection.decoded(message_id: window_opened.message_id)
      |> result.map_error(NotDecoded)
      |> result.try(fn(opened) {
        window_name_within_limit(
          units: list.length(opened.window_name),
          tables:,
        )
      })
    PreGameActivity ->
      pre_game_activity.decode(body)
      |> decoded(pre_game_activity.message_id)
    ClientOption ->
      client_option.decode(body)
      |> client_connection.decoded(message_id: client_option.message_id)
      |> result.map_error(NotDecoded)
      |> result.try(option_sent)
    ScanbotRequest ->
      scanbot_request.decode(body)
      |> decoded(scanbot_request.message_id)
    OwnAuctionsRequest ->
      own_auctions_request.decode(body)
      |> decoded(own_auctions_request.message_id)
    OwnCommodityOrdersRequest ->
      own_commodity_orders_request.decode(body)
      |> decoded(own_commodity_orders_request.message_id)
    CreddExchangeRequest ->
      credd_exchange_request.decode(body)
      |> decoded(credd_exchange_request.message_id)
    TradeCancel ->
      trade_cancel.decode(body)
      |> decoded(trade_cancel.message_id)
    InputKeySetRequest ->
      input_key_set_request.decode(body)
      |> decoded(input_key_set_request.message_id)
  }
}

/// A body that decoded is taken, whatever its fields hold.
fn decoded(
  result result: Result(a, bit_stream.DecodeError),
  message_id message_id: Int,
) -> Result(Nil, Refusal) {
  result
  |> client_connection.decoded(message_id:)
  |> result.map_error(NotDecoded)
  |> result.replace(Nil)
}

/// The name of at most the limit's units.
fn window_name_within_limit(
  units units: Int,
  tables tables: table_store.Tables,
) -> Result(Nil, Refusal) {
  let assert Ok(row) =
    game_formula.get(tables:, id: GameFormulaId(window_name_formula))
    as "GameFormula row 2375 is required at load (requirements)"
  case units > row.dataint02 {
    True -> Error(WindowNameTooLong(units:, limit: row.dataint02))
    False -> Ok(Nil)
  }
}

/// The types and values a sender of 0x012B writes: type 0 with the input flags
/// (flag 1 always set, 2, 4 and 8 as the settings are), type 1 with a bool.
fn option_sent(option: client_option.ClientOption) -> Result(Nil, Refusal) {
  case option.option_type, option.value {
    0, flags ->
      case flags >= 1 && flags <= 15 && int.is_odd(flags) {
        True -> Ok(Nil)
        False -> Error(InputFlagsNotSent(value: flags))
      }
    1, 0 | 1, 1 -> Ok(Nil)
    1, value -> Error(SharedChallengeNotABool(value:))
    option_type, _ -> Error(OptionTypeNotSent(option_type:))
  }
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    WindowNameTooLong(units:, limit:) ->
      "0x023D names a window with "
      <> int.to_string(units)
      <> " units, but the client refuses to send a name of more than "
      <> int.to_string(limit)
      <> " (GameFormula row 2375)"
    OptionTypeNotSent(option_type:) ->
      "0x012B has option type "
      <> int.to_string(option_type)
      <> ": the client sends type 0 or 1"
    SharedChallengeNotABool(value:) ->
      "0x012B type 1 has value "
      <> int.to_string(value)
      <> ": the client sends 0 or 1"
    InputFlagsNotSent(value:) ->
      "0x012B type 0 has input flags "
      <> int.to_string(value)
      <> ": the client always sets flag 1 and no flag above 8"
  }
}

/// The load's check that GameFormula row 2375 exists, so a client without it
/// fails the server's start.
pub fn requirements() -> List(table_store.Requirement) {
  [
    table_store.Requirement(
      from_table: "the server's window name limit",
      column: "GameFormula id",
      to_table: "GameFormula",
      missing: fn(tables) {
        case game_formula.get(tables:, id: GameFormulaId(window_name_formula)) {
          Ok(_) -> []
          Error(Nil) -> [window_name_formula]
        }
      },
    ),
  ]
}
