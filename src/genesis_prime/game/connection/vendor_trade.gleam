//// What the game connection's buy (genesis_prime/game/connection/vendor_purchase) and sale
//// (genesis_prime/game/connection/vendor_sale) share: the effects the rules ask for carried
//// out in order, and the store's answer to the change they asked for, which differs between
//// them only in what the answer leaves and in the words of the log.

import genesis_prime/client_connection.{type Answer, Continue, FromStore}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session, InWorld, Session} as connection_state
import genesis_prime/game/vendor_trade.{type Effect as TradeEffect}
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{type ItemsAnswer, ForItems}
import gleam/list

/// The connection's effects for what a rule decided, in order.
pub fn effects_of(
  session session: Session,
  effects effects: List(TradeEffect),
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  list.map(effects, fn(effect) {
    case effect {
      vendor_trade.Send(frame:) -> connection_state.to_client(session, frame)
      vendor_trade.Refuse(code:) ->
        connection_state.to_client(
          session,
          connection_frames.generic_error_frame(code:),
        )
      vendor_trade.Log(level:, text:) ->
        connection_state.log(session:, level:, text:)
    }
  })
}

/// The store's answer to the change a trade asked for: `left` says what the answer leaves
/// of the entered player and the effects to carry out, and the player is in the world again
/// with them; a store that failed ends the connection with reason 8, its log line starting
/// with `what` and naming `kind` as what the answer was not.
pub fn answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  what what: String,
  kind kind: String,
  outcome outcome: Outcome(Answer),
  left left: fn(ItemsAnswer) -> #(world_entry.Entered, List(TradeEffect)),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(ForItems(answer))) -> {
      let #(entered, effects) = left(answer)
      let session = Session(..session, status: InWorld(holder:, entered:))
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
        text: what <> ": the store is unavailable",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      lost(
        session:,
        now:,
        holder:,
        entered:,
        text: what
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
        text: what <> ": the answer is none a " <> kind <> " asked for",
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
