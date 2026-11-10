//// The player's sale to the open vendor on the game connection
//// (genesis_prime/game/connection): the client's 0x0166 and 0x0167, and the store's answer
//// to the sale it asked for. The rule's decisions are genesis_prime/game/vendor_sale's, which
//// holds the checks; this module carries them out.
////
//// ```
//// 0x166 / 0x167 ─▶ vendor_sale.take(entered, picture, body) ─▶ Refused(0x106 code, log once per reason)   status stays InWorld
////                                                           └▶ Asks(sale) ─▶ AskStore(Items(SellToVendor ...))   status Selling(holder, entered, sale), frames held
//// store worker: lock_character_for_save then sell_to_vendor.sql, one transaction
////    ─▶ Sold(amount) ─▶ answered: entered.items, currencies and buyback updated; 0x919, then per stack 0x148 / 0x17F reason 7 and 0xBA; status InWorld; held frames replayed
////                       ─▶ inventory.regeared: the worn set unchanged (every bag sale) ─▶ nothing more
////                                              changed (a worn item sold) ─▶ 0x933 and LookChanged to viewers, then 0x93a
////    ─▶ ItemsNotSaved | SaveRefused ─▶ 0x106 5 and a warning; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as the buy)
//// ```
////
//// | Where | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written; the window stays | a second 0x166 or the auto-sell 0x167 is held while Selling, then taken against the new items and amounts | n/a |
//// | store asked, transaction open | Postgres rolls back; the connection ends, reason 8; the next login loads the old amounts and items | the epoch fence, the currency guard (a missing row as 0) and the location and held-count guard make the second change nothing | the connection ends, reason 8; a committed result is what the next login loads |
//// | store answered, before `answered` runs | the save is done; the next login loads the new amounts and items, and builds the gear from the saved worn items; the buyback entries are lost with the connection | n/a (frames held) | n/a |
//// | connection dies while Selling | the store finishes or rolls back on its own | n/a | n/a |

import genesis_prime/client_connection.{type Answer, Asking, Continue, Done}
import genesis_prime/game/connection/inventory as connection_inventory
import genesis_prime/game/connection/state.{
  type Session, InWorld, Selling, Session,
} as connection_state
import genesis_prime/game/connection/vendor_trade
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/shown
import genesis_prime/game/vendor_sale
import genesis_prime/game/vendor_trade as trade_rule
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Now, type Outcome}

/// The client's 0x0166 or 0x0167, taken from inside 0x038C with the player in the world: a
/// refusal is written and the player stays in the world; an accepted sale asks the store and
/// the connection waits in `Selling`; a body the client's reader would refuse ends the
/// connection.
pub fn sale_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  request request: vendor_sale.Request,
) -> client_connection.Handled(Session) {
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  case
    vendor_sale.take(
      request:,
      items: entered.items,
      currencies: entered.currencies,
      opened: entered.vendor,
      life: entered.life,
      player: interaction.Player(
        race_id: entered.character.race_id,
        faction:,
        place: movement.place(state: entered.movement),
      ),
      picture: entered.shown,
      tables: session.settings.tables,
      vendors: session.settings.vendors,
      now_ms: now.monotonic_ms,
      logged: session.interaction_logged,
    )
  {
    Ok(vendor_sale.Refused(effects:, logged:)) ->
      Continue(
        Session(..session, interaction_logged: logged),
        vendor_trade.effects_of(session:, effects:),
      )
    Ok(vendor_sale.Asks(sale:, logged:)) ->
      connection_state.ask(
        session: Session(
          ..session,
          interaction_logged: logged,
          status: Selling(holder:, entered:, sale:),
        ),
        now:,
        request: client_connection.AskStore(vendor_sale.request(
          sale:,
          account_id: holder.account_id,
          character_id: entered.character_id,
          session_epoch: movement.session_epoch(state: entered.movement),
        )),
        before: [],
      )
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: trade_rule.describe(refusal:),
      )
  }
}

/// The store's answer to the sale: the player is in the world again with the items,
/// currencies and buyback list the answer leaves and the sale's replies or a 0x106 written,
/// then the look and the properties when the worn items changed (`regeared`); a store that
/// failed ends the connection with reason 8.
pub fn sale_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  sale sale: vendor_sale.Sale,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  let handled =
    vendor_trade.answered(
      session:,
      now:,
      holder:,
      entered:,
      what: vendor_sale.not_sold(sale:),
      kind: "sale",
      outcome:,
      left: fn(answer) {
        let #(items, currencies, buyback, effects) =
          vendor_sale.answered(
            sale:,
            items: entered.items,
            currencies: entered.currencies,
            buyback: entered.buyback,
            answer:,
          )
        #(
          world_entry.Entered(..entered, items:, currencies:, buyback:),
          effects,
        )
      },
    )
  case handled {
    Continue(
      session: Session(status: InWorld(holder:, entered:), ..) as session,
      effects:,
    ) ->
      connection_inventory.regeared(
        session:,
        now:,
        holder:,
        entered:,
        moved: effects,
      )
    Continue(..) | Asking(..) | Done(..) -> handled
  }
}
