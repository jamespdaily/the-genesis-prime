//// What a player's buy from the open vendor (genesis_prime/game/vendor_purchase) and sale
//// to it (genesis_prime/game/vendor_sale) share: the effects a rule asks the connection
//// for, the refusals that end the connection, the checks of the window and the player that
//// come before anything is looked up, and the answer to a store that did not save.
////
//// The two differ in the codes a dead player and a dead vendor get, in whether the window's
//// reach applies (a sale has a range of its own), and in the words of their log lines; a
//// `Trade` carries those.

import genesis_prime/client_connection.{type Undecoded}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/interaction
import genesis_prime/game/player_life
import genesis_prime/game/shown.{type Picture}
import genesis_prime/game/vendor
import genesis_prime/step.{type LogLevel, LogError, LogWarning}
import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// What the rule asks the connection to do.
pub type Effect {
  /// Write a frame to the player's client.
  Send(frame: Frame)
  /// Write a 0x106 with the client's code for why the request is refused.
  Refuse(code: Int)
  /// Write a log line.
  Log(level: LogLevel, text: String)
}

/// Why a request ends the connection with no answer: the client's own code never sends it,
/// or the server's own state is broken.
pub type Refusal {
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: Undecoded)
  /// A held or stocked item, or a row its price reads, that the tables lack: the server's
  /// own state is broken, since the item rows require them.
  NoItemRow(item2_id: Item2Id)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
    NoItemRow(item2_id:) ->
      "a held or stocked item has no row in the client's tables, or a row its price reads: Item2 "
      <> int.to_string(item2_id.value)
  }
}

/// How a kind of trade words and codes the refusals of its window and player.
pub type Trade {
  Trade(
    /// The word its log keys start with.
    key: String,
    /// What the player does, for the log: "buys from" or "sells to".
    verb: String,
    /// What the client would refuse, for the log: "the interaction" or "the sale".
    refused: String,
    /// The client's code for a player who is dead.
    dead_player_code: Int,
    /// The client's code for a vendor who is dead.
    dead_vendor_code: Int,
    /// Whether the window's reach applies, or the trade has a range of its own.
    reach: interaction.ReachCheck,
  )
}

/// The effects of a request the rule refused before it looked at what it asks for, with the
/// log keys met so far.
pub type Declined {
  Declined(effects: List(Effect), logged: Set(String))
}

/// The client's code for a request with no vendor window open (Vendor_NotAVendor).
const not_a_vendor = 16

/// The vendor's window the request is made in, once the player is alive and the vendor is
/// shown, stocked, alive and not Hostile (and within reach, when the trade checks it), or the
/// answer for the first check it breaks: the codes are the client's, and each reason is
/// logged once on the connection.
pub fn opened(
  trade trade: Trade,
  label label: String,
  opened opened: Option(vendor.Opened),
  life life: player_life.Life,
  player player: interaction.Player,
  picture picture: Picture,
  tables tables: table_store.Tables,
  vendors vendors: vendor.Vendors,
  now_ms now_ms: Int,
  logged logged: Set(String),
) -> Result(vendor.Opened, Declined) {
  case opened {
    None ->
      Error(refused_logged(
        trade:,
        reason: "no window",
        text: label
          <> " "
          <> trade.verb
          <> " a vendor with no vendor window open on the connection: the client sends it only in a vendor interaction, so the server answers "
          <> int.to_string(not_a_vendor),
        code: not_a_vendor,
        logged:,
      ))
    Some(window) ->
      case
        refused_when_dead(
          key: trade.key <> " dead",
          text: label
            <> " "
            <> trade.verb
            <> " a vendor while the player is dead: the client sends nothing for a dead player, so the server answers "
            <> int.to_string(trade.dead_player_code),
          code: trade.dead_player_code,
          life:,
          logged:,
        )
      {
        Error(declined) -> Error(declined)
        Ok(Nil) ->
          case
            interaction.vendor_opened(
              unit_id: window.unit_id,
              player:,
              picture:,
              tables:,
              vendors:,
              reach: trade.reach,
              now_ms:,
            )
          {
            Error(refusal) ->
              Error(window_refused(trade:, label:, refusal:, logged:))
            Ok(stock) -> Ok(vendor.Opened(..window, vendor: stock))
          }
      }
  }
}

/// The answer for a window the vendor's unit fails: the window's own code, except that a dead
/// vendor has the trade's.
fn window_refused(
  trade trade: Trade,
  label label: String,
  refusal refusal: interaction.VendorRefusal,
  logged logged: Set(String),
) -> Declined {
  let code = case refusal.reason {
    interaction.VendorDead -> trade.dead_vendor_code
    interaction.VendorNotShown
    | interaction.VendorNotACreature
    | interaction.VendorNoStock
    | interaction.VendorTooFar
    | interaction.VendorHostile -> refusal.code
  }
  refused_logged(
    trade:,
    reason: interaction.reason_key(reason: refusal.reason),
    text: label
      <> " "
      <> trade.verb
      <> " unit "
      <> int.to_string(refusal.unit_id)
      <> ", "
      <> refusal.why
      <> ": the client would refuse "
      <> trade.refused
      <> " with code "
      <> int.to_string(code)
      <> ", so the server answers that",
    code:,
    logged:,
  )
}

/// The refusal of a request a dead player makes, which the client never sends: `Ok` for a
/// living player, else the effects that answer with `code` and log `text` once for `key` on
/// the connection, with the log keys met so far. A buy, a sale and a quest's turn-in each ask
/// it before they look at what the request names.
pub fn refused_when_dead(
  key key: String,
  text text: String,
  code code: Int,
  life life: player_life.Life,
  logged logged: Set(String),
) -> Result(Nil, Declined) {
  case player_life.state(life:) {
    player_life.Alive -> Ok(Nil)
    player_life.Dead -> {
      let #(level, logged) = interaction.log_level(key:, logged:)
      Error(Declined(effects: [Log(level:, text:), Refuse(code:)], logged:))
    }
  }
}

/// A refusal by a code the client's own check gives for a request it never sends, or that
/// this server cannot yet make, with a line to log once for each reason on the connection.
pub fn refused_logged(
  trade trade: Trade,
  reason reason: String,
  text text: String,
  code code: Int,
  logged logged: Set(String),
) -> Declined {
  let #(level, logged) =
    interaction.log_level(key: trade.key <> " " <> reason, logged:)
  Declined(effects: [Log(level:, text:), Refuse(code:)], logged:)
}

/// The client's code for a change that was not saved (DbFailure).
const db_failure = 5

/// The effects for a store that answered ItemsNotSaved to the change of `what`: a later
/// login holds the character, or the credits or the items are not as the connection holds
/// them.
pub fn not_saved(what what: String) -> List(Effect) {
  [
    Log(
      level: LogWarning,
      text: what
        <> ": a later login holds the character, or the credits or the items are not as the connection holds them",
    ),
    Refuse(code: db_failure),
  ]
}

/// The effects for a store that refused the change of `what` by a constraint.
pub fn save_refused(
  what what: String,
  constraint constraint: String,
) -> List(Effect) {
  [
    Log(
      level: LogError,
      text: what
        <> ": the store refused the change by the constraint "
        <> constraint,
    ),
    Refuse(code: db_failure),
  ]
}
