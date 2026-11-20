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
////   without the reply they ask for: the coverage measure's messages checklist lists
////   the reply each waits for.
//// - **0x23D's event text** is refused when it has more UTF-16 units than GameFormula
////   row 2375's dataint02, which the client's sender reads as the limit and
////   does not send past (`opcode.0x23d`). Its character id is refused when it
////   is not the id of the character the connection plays: every recorded send
////   names it (`opcode.0x23d`). Its category is refused when it is not 35
////   (`opcode.0x23d.category`) and its 2nd and 6th 64-bit values when they are
////   not 0 (`opcode.0x23d.zero_values`). The event id and the other values are
////   read and not checked (`gaps`).
//// - **0x0180's profile** is read and not checked: what a value means is not
////   read, and no scanbot is made to compare it with (`opcode.0x180`).
//// - **0x0570's key set id** is read and not checked: the player's key sets
////   are not kept, so no id can be compared with one (`opcode.0x570`).
//// - **0x12B's type** is 0 (the input flags) or 1 (the shared-challenge
////   preference): the senders write no other (`opcode.0x12b`).
//// - **A signed 32-bit field of 0x23C** is read as unsigned 32 bits: the bits
////   are the same, and nothing is done with the value.

import genesis_prime/client_connection.{type Undecoded, type Unwritten}
import genesis_prime/gap
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
import genesis_prime/message/statistic_event
import genesis_prime/message/trade_cancel
import genesis_prime/message/watchdog_report
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import genesis_prime/table/loader/formula_requirement
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The GameFormula row whose dataint02 is the longest event text the client
/// sends (`FUN_140200220(0x947)`, `opcode.0x23d`).
const event_text_formula = 2375

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
  /// 0x023D, the client's statistics event.
  StatisticEvent
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
  /// An event text longer than the limit the client's sender holds.
  EventTextTooLong(units: Int, limit: Int)
  /// A statistics event that names a character other than the one the connection
  /// plays (`own` is `None` when it has none in the world).
  EventNamesAnotherCharacter(named: Int, own: Option(Int))
  /// A value no sender writes: a statistics event's category or one of its
  /// two zero values (`opcode.0x23d.category`, `opcode.0x23d.zero_values`), an
  /// option type, a shared-challenge preference that is not 0 or 1, or input
  /// flags with flag 1 clear or a bit above flag 8 set (`opcode.0x12b`).
  NotWritten(unwritten: Unwritten)
}

/// The message taken: `Ok(Nil)` when the body is one the client sends, and the
/// refusal for a body its reader refuses or a value its senders never write.
/// `character_id` is the id of the character the connection plays, `None`
/// while it has none in the world.
pub fn take(
  message message: Message,
  body body: BitArray,
  tables tables: table_store.Tables,
  character_id character_id: Option(Int),
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
    StatisticEvent ->
      statistic_event.decode(body)
      |> client_connection.decoded(message_id: statistic_event.message_id)
      |> result.map_error(NotDecoded)
      |> result.try(fn(event) {
        use Nil <- result.try(event_values_written(event))
        use Nil <- result.try(event_names_own_character(
          named: event.character_id,
          own: character_id,
        ))
        event_text_within_limit(units: list.length(event.event_text), tables:)
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

/// The category and the two values the client's emitters always write as 0
/// (`opcode.0x23d.category`, `opcode.0x23d.zero_values`).
fn event_values_written(
  event: statistic_event.StatisticEvent,
) -> Result(Nil, Refusal) {
  use Nil <- result.try(
    written(
      message_id: statistic_event.message_id,
      field: "the category",
      value: event.category,
      only: [event_category],
    ),
  )
  use Nil <- result.try(
    written(
      message_id: statistic_event.message_id,
      field: "the second value",
      value: event.zero_value_2,
      only: [0],
    ),
  )
  written(
    message_id: statistic_event.message_id,
    field: "the sixth value",
    value: event.zero_value_6,
    only: [0],
  )
}

/// The category every sender of 0x023D writes (`opcode.0x23d.category`).
const event_category = 35

/// The event names the character the connection plays: the client's first
/// 64-bit value is its own character id in every recorded send
/// (`opcode.0x23d`).
fn event_names_own_character(
  named named: Int,
  own own: Option(Int),
) -> Result(Nil, Refusal) {
  use <- bool.guard(own == Some(named), Ok(Nil))
  Error(EventNamesAnotherCharacter(named:, own:))
}

/// The event text of at most the limit's units.
fn event_text_within_limit(
  units units: Int,
  tables tables: table_store.Tables,
) -> Result(Nil, Refusal) {
  let assert Ok(row) =
    game_formula.get(tables:, id: GameFormulaId(event_text_formula))
    as "GameFormula row 2375 is required at load (requirements)"
  case units > row.dataint02 {
    True -> Error(EventTextTooLong(units:, limit: row.dataint02))
    False -> Ok(Nil)
  }
}

/// The types and values a sender of 0x012B writes: type 0 with the input flags
/// (flag 1 always set, 2, 4 and 8 as the settings are), type 1 with a bool
/// (`opcode.0x12b`).
fn option_sent(option: client_option.ClientOption) -> Result(Nil, Refusal) {
  use Nil <- result.try(
    written(
      message_id: client_option.message_id,
      field: "the option type",
      value: option.option_type,
      only: [0, 1],
    ),
  )
  case option.option_type {
    0 ->
      written(
        message_id: client_option.message_id,
        field: "type 0's input flags",
        value: option.value,
        only: [1, 3, 5, 7, 9, 11, 13, 15],
      )
    _ ->
      written(
        message_id: client_option.message_id,
        field: "type 1's value",
        value: option.value,
        only: [0, 1],
      )
  }
}

/// Whether a value is one the client writes, as this module's refusal.
fn written(
  message_id message_id: Int,
  field field: String,
  value value: Int,
  only only: List(Int),
) -> Result(Nil, Refusal) {
  client_connection.written(message_id:, field:, value:, only:)
  |> result.map_error(NotWritten)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    EventTextTooLong(units:, limit:) ->
      "0x023D carries an event text of "
      <> int.to_string(units)
      <> " units, but the client refuses to send a text of more than "
      <> int.to_string(limit)
      <> " (GameFormula row 2375)"
    EventNamesAnotherCharacter(named:, own:) ->
      "0x023D names character "
      <> int.to_string(named)
      <> ", but "
      <> case own {
        Some(own) -> "the connection plays character " <> int.to_string(own)
        None -> "the connection has no character in the world"
      }
    NotWritten(unwritten:) -> client_connection.describe_unwritten(unwritten:)
  }
}

/// The load's check that GameFormula row 2375 exists, so a client without it
/// fails the server's start.
pub fn requirements() -> List(table_store.Requirement) {
  [
    formula_requirement.row_present(
      from_table: "the server's event text limit",
      id: event_text_formula,
    ),
  ]
}

/// What the rule leaves unchecked in the client's reports and requests, for the
/// coverage measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Dropped messages",
      missing: "A 0x23D is not refused for an event id other than 499, 502 to 510, 512 and 513 (the ids the client's emitters send; 500, 501 and 511 have none in the client's code that was found), for a text on an event other than 508 and 512, or for a third, fourth or fifth value the client's emitter would not send.",
    ),
  ]
}
