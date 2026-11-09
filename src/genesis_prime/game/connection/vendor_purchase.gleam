//// The player's buy from the open vendor on the game connection
//// (genesis_prime/game/connection): the client's 0x00BE, and the store's answer to the buy
//// it asked for. The rule's decisions are genesis_prime/game/vendor_purchase's, which holds
//// the checks and the failure table; this module carries them out.
////
//// ```
//// 0xBE ─▶ vendor_purchase.take(entered, picture, body) ─▶ Refused(0x106 code, log once per reason)   status stays InWorld
////                                                      └▶ Asks(purchase) ─▶ AskStore(Items(BuyFromVendor ...))   status Buying(holder, entered, purchase), frames held
//// store worker: lock_character_for_save then buy_from_vendor.sql, one transaction
////    ─▶ Bought(total, made)    ─▶ answered: entered.currencies and entered.items updated; 0x919 kind 0, then 0x111 / 0x17F reason 7; status InWorld; held frames replayed
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

import genesis_prime/client_connection.{type Answer, Continue, FromStore}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{
  type Session, Buying, InWorld, Session,
} as connection_state
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/shown
import genesis_prime/game/vendor_purchase
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{ForItems}
import gleam/list

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
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  case
    vendor_purchase.take(
      body: inner.body,
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
    Ok(vendor_purchase.Refused(effects:, logged:)) ->
      Continue(
        Session(..session, interaction_logged: logged),
        effects_of(session:, effects:),
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
        text: vendor_purchase.describe(refusal:),
      )
  }
}

/// The store's answer to the buy: the player is in the world again with the items and credits
/// the answer leaves and the buy's replies or a 0x106 written; a store that failed ends the
/// connection with reason 8.
pub fn buy_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  purchase purchase: vendor_purchase.Purchase,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(ForItems(answer))) -> {
      let #(items, currencies, effects) =
        vendor_purchase.answered(
          purchase:,
          items: entered.items,
          currencies: entered.currencies,
          answer:,
        )
      let session =
        Session(
          ..session,
          status: InWorld(
            holder:,
            entered: world_entry.Entered(..entered, items:, currencies:),
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
        text: vendor_purchase.not_bought(purchase:)
          <> ": the store is unavailable",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      lost(
        session:,
        now:,
        holder:,
        entered:,
        text: vendor_purchase.not_bought(purchase:)
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
        text: vendor_purchase.not_bought(purchase:)
          <> ": the answer is none a buy asked for",
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
  effects effects: List(vendor_purchase.Effect),
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  list.map(effects, fn(effect) {
    case effect {
      vendor_purchase.Send(frame:) -> connection_state.to_client(session, frame)
      vendor_purchase.Refuse(code:) ->
        connection_state.to_client(
          session,
          connection_frames.generic_error_frame(code:),
        )
      vendor_purchase.Log(level:, text:) ->
        connection_state.log(session:, level:, text:)
    }
  })
}
