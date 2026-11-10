//// The player's sale to the open vendor on the game connection
//// (genesis_prime/game/connection): the client's 0x0166 and 0x0167, and the store's answer
//// to the sale it asked for. The rule's decisions are genesis_prime/game/vendor_sale's, which
//// holds the checks; this module carries them out.
////
//// ```
//// 0x166 / 0x167 ─▶ vendor_sale.take(entered, picture, body) ─▶ Refused(0x106 code, log once per reason)   status stays InWorld
////                                                           └▶ Asks(sale) ─▶ AskStore(Items(SellToVendor ...))   status Selling(holder, entered, sale), frames held
//// store worker: lock_character_for_save then sell_to_vendor.sql, one transaction
////    ─▶ Sold(credits) ─▶ answered: entered.items, currencies and buyback updated; 0x919, then per stack 0x148 / 0x17F reason 7 and 0xBA; status InWorld; held frames replayed
////    ─▶ ItemsNotSaved | SaveRefused ─▶ 0x106 5 and a warning; nothing in memory changes; status InWorld
////    ─▶ unavailable, not running, past deadline ─▶ the connection ends, reason 8 (as the buy)
//// ```
////
//// | Where | Killed there | Twice at once | Times out |
//// |---|---|---|---|
//// | take, before asking | nothing written; the window stays | a second 0x166 or the auto-sell 0x167 is held while Selling, then taken against the new items and credits | n/a |
//// | store asked, transaction open | Postgres rolls back; the connection ends, reason 8; the next login loads the old credits and items | the epoch fence, the credits guard and the held-count guard make the second change nothing | the connection ends, reason 8; a committed result is what the next login loads |
//// | store answered, before `answered` runs | the save is done; the next login loads the new credits and items; the buyback entries are lost with the connection (#651 owns the list's lifetime) | n/a (frames held) | n/a |
//// | connection dies while Selling | the store finishes or rolls back on its own | n/a | n/a |

import genesis_prime/client_connection.{type Answer, Continue, FromStore}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{
  type Session, InWorld, Selling, Session,
} as connection_state
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/shown
import genesis_prime/game/vendor_sale
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{ForItems}
import gleam/list

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
        effects_of(session:, effects:),
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
        text: vendor_sale.describe(refusal:),
      )
  }
}

/// The store's answer to the sale: the player is in the world again with the items, credits
/// and buyback list the answer leaves and the sale's replies or a 0x106 written; a store that
/// failed ends the connection with reason 8.
pub fn sale_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  sale sale: vendor_sale.Sale,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(ForItems(answer))) -> {
      let #(items, currencies, buyback, effects) =
        vendor_sale.answered(
          sale:,
          items: entered.items,
          currencies: entered.currencies,
          buyback: entered.buyback,
          answer:,
        )
      let session =
        Session(
          ..session,
          status: InWorld(
            holder:,
            entered: world_entry.Entered(
              ..entered,
              items:,
              currencies:,
              buyback:,
            ),
          ),
        )
      Continue(session, effects_of(session:, effects:))
    }
    step.StoppedWaiting ->
      connection_state.stopped(
        Session(..session, status: InWorld(holder:, entered:)),
        now,
      )
    step.Answer(FromStore(store.Unavailable)) ->
      lost(
        session:,
        now:,
        holder:,
        entered:,
        text: vendor_sale.not_sold(sale:) <> ": the store is unavailable",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      lost(
        session:,
        now:,
        holder:,
        entered:,
        text: vendor_sale.not_sold(sale:)
          <> ": "
          <> client_connection.without_answer(who: "the store", outcome:),
      )
    step.Answer(FromStore(store.ForLogin(..)))
    | step.Answer(FromStore(store.ForSelect(..)))
    | step.Answer(FromStore(store.ForWorld(..)))
    | step.Answer(FromStore(store.ForMove(..)))
    | step.Answer(client_connection.FromHandOff(..))
    | step.Answer(client_connection.FromSessions(..))
    | step.Answer(client_connection.FromMap(..)) ->
      lost(
        session:,
        now:,
        holder:,
        entered:,
        text: vendor_sale.not_sold(sale:)
          <> ": the answer is none a sale asked for",
      )
  }
}

/// The connection ends with reason 8 and saves the player's place as in the world, which
/// the player is in.
fn lost(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  text text: String,
) -> client_connection.Handled(Session) {
  connection_state.told(
    session: Session(..session, status: InWorld(holder:, entered:)),
    now:,
    reason: LostUserServer,
    level: step.LogError,
    text:,
  )
}

/// The connection's effects for what the rule decided, in order.
fn effects_of(
  session session: Session,
  effects effects: List(vendor_sale.Effect),
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  list.map(effects, fn(effect) {
    case effect {
      vendor_sale.Send(frame:) -> connection_state.to_client(session, frame)
      vendor_sale.Refuse(code:) ->
        connection_state.to_client(
          session,
          connection_frames.generic_error_frame(code:),
        )
      vendor_sale.Log(level:, text:) ->
        connection_state.log(session:, level:, text:)
    }
  })
}
