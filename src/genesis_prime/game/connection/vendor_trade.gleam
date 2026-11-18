//// What the game connection's buy (genesis_prime/game/connection/vendor_purchase) and sale
//// (genesis_prime/game/connection/vendor_sale) share: the effects the rules ask for carried
//// out in order, and the store's answer to the change they asked for, which differs between
//// them only in what the answer leaves and in the words of the log.

import genesis_prime/client_connection.{type Answer, Continue}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/inventory as connection_inventory
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/state.{type Session, InWorld, Session} as connection_state
import genesis_prime/game/vendor_trade.{type Effect as TradeEffect}
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{type ItemsAnswer}
import genesis_prime/table/id.{type Creature2Id, type Item2Id}
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
/// with them; a store that failed ends the connection with reason 8
/// (`connection/inventory.answered`), its log line starting with `what` and naming `kind` as
/// what the answer was not.
pub fn answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  what what: String,
  kind kind: String,
  outcome outcome: Outcome(Answer),
  left left: fn(ItemsAnswer) -> #(world_entry.Entered, List(TradeEffect)),
  bought bought: fn(ItemsAnswer, world_entry.Entered) ->
    Result(#(Item2Id, Creature2Id), Nil),
) -> client_connection.Handled(Session) {
  connection_inventory.answered(
    session:,
    now:,
    holder:,
    entered:,
    what:,
    asked: "a " <> kind,
    outcome:,
    saved: fn(session, answer) {
      let #(entered, effects) = left(answer)
      let session = Session(..session, status: InWorld(holder:, entered:))
      let #(session, settled) = case bought(answer, entered) {
        Ok(#(item2_id, vendor)) ->
          connection_objective.purchased(session:, now:, item2_id:, vendor:)
        Error(Nil) -> connection_objective.settled(session:, now:)
      }
      Continue(session, list.append(effects_of(session:, effects:), settled))
    },
  )
}
