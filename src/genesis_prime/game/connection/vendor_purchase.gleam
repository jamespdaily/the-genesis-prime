//// The player's buy from the open vendor on the game connection
//// (genesis_prime/game/connection): the client's 0x00BE and 0x00BB, and the store's answer to
//// the buy or buy back it asked for. The rule's decisions are genesis_prime/game/vendor_purchase's, which holds
//// the checks and the failure table; this module carries them out.
////
//// ```
//// 0xBE ─▶ vendor_purchase.take(entered, picture, body)   (0xBB: take_back, the same ask and answer) ─▶ Refused(0x106 code, log once per reason)   status stays InWorld
////                                                      └▶ Asks(purchase) ─▶ AskStore(Items(BuyFromVendor ...))   status Buying(holder, entered, purchase), frames held
//// store worker: lock_character_for_save then buy_from_vendor.sql, one transaction
////    ─▶ Bought(total, made)    ─▶ answered: entered.currencies and entered.items updated; 0x919 kind 0, then 0x111 / 0x17F reason 7 (16 and a 0xBD after them for a buy back); status InWorld; held frames replayed
////    ─▶ ItemsNotSaved | SaveRefused(constraint) ─▶ 0x106 5 and a warning; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as an item move)
//// ```
////
//// | Case | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written, and the client's window stays | a second 0xBE is held while Buying, then taken against the new totals | n/a |
//// | store asked, transaction open | Postgres rolls back; the monitor ends the connection with reason 8; the next login loads the old state | the epoch fence and the `credits.amount = $4` guard make the second change nothing | the connection ends with reason 8, and the result, if it commits, is loaded next login |
//// | store answered, before `answered` runs | the save is done; the next login loads the new state | n/a (frames held) | n/a |
//// | connection dies while Buying | the store finishes or rolls back; the next login loads whichever | n/a | n/a |

import genesis_prime/client_connection.{type Answer, Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/state.{type Session, Buying, Session} as connection_state
import genesis_prime/game/connection/vendor_trade
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/shown
import genesis_prime/game/vendor_purchase
import genesis_prime/game/vendor_trade as trade_rule
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{type Now, type Outcome}

/// The client's 0x00BE, taken from inside 0x038C with the player in the world: a refusal is
/// written and the player stays in the world; an accepted buy asks the store and the
/// connection waits in `Buying`; a body the client's reader would refuse ends the connection.
pub fn purchase_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let #(player, picture) = window_of(entered:)
  taken(
    session:,
    now:,
    holder:,
    entered:,
    taken: vendor_purchase.take(
      body: inner.body,
      items: entered.items,
      currencies: entered.currencies,
      opened: entered.vendor,
      life: entered.life,
      player:,
      picture:,
      tables: session.settings.tables,
      vendors: session.settings.vendors,
      now_ms: now.monotonic_ms,
      logged: session.interaction_logged,
    ),
  )
}

/// The client's 0x00BB, taken the same way as a buy: the entry's price and items go through
/// the buy's checks and request, and the player stays in the world on a refusal.
pub fn buy_back_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let #(player, picture) = window_of(entered:)
  taken(
    session:,
    now:,
    holder:,
    entered:,
    taken: vendor_purchase.take_back(
      body: inner.body,
      items: entered.items,
      currencies: entered.currencies,
      opened: entered.vendor,
      buyback: entered.buyback,
      life: entered.life,
      player:,
      picture:,
      tables: session.settings.tables,
      vendors: session.settings.vendors,
      now_ms: now.monotonic_ms,
      logged: session.interaction_logged,
    ),
  )
}

/// The player the buyer is and the picture the buy is checked against.
fn window_of(
  entered entered: world_entry.Entered,
) -> #(interaction.Player, shown.Picture) {
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  #(
    interaction.Player(
      race_id: entered.character.race_id,
      faction:,
      place: movement.place(state: entered.movement),
    ),
    entered.shown,
  )
}

/// What the rule made of a buy or a buy back: a refusal is written, an accepted one asks the
/// store, and a refusal that ends the connection ends it.
fn taken(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  taken taken: Result(vendor_purchase.Taken, trade_rule.Refusal),
) -> client_connection.Handled(Session) {
  case taken {
    Ok(vendor_purchase.Refused(effects:, logged:)) ->
      Continue(
        Session(..session, interaction_logged: logged),
        vendor_trade.effects_of(session:, effects:),
      )
    Ok(vendor_purchase.Asks(purchase:, logged:)) ->
      connection_state.ask(
        session: Session(
          ..session,
          interaction_logged: logged,
          status: Buying(holder:, entered:, purchase:),
        ),
        now:,
        request: client_connection.AskStore(vendor_purchase.request(
          purchase:,
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

/// The store's answer to the buy: the player is in the world again with the items, credits
/// and buyback list the answer leaves and the buy's replies or a 0x106 written; a store that
/// failed ends the connection with reason 8.
pub fn buy_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  purchase purchase: vendor_purchase.Purchase,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  vendor_trade.answered(
    session:,
    now:,
    holder:,
    entered:,
    what: vendor_purchase.not_bought(purchase:),
    kind: "buy",
    outcome:,
    left: fn(answer) {
      let #(items, currencies, buyback, effects) =
        vendor_purchase.answered(
          purchase:,
          items: entered.items,
          currencies: entered.currencies,
          buyback: entered.buyback,
          answer:,
        )
      #(world_entry.Entered(..entered, items:, currencies:, buyback:), effects)
    },
  )
}
