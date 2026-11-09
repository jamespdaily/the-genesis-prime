//// The player's changes of held items on the game connection
//// (genesis_prime/game/connection): the client's 0x182 (a move, swap or merge),
//// 0x17D (a split) and 0x149 (a delete), and the store's answer to the change it
//// asked for. The rule's decisions are genesis_prime/game/inventory's, which
//// holds the sequence and the failure table; this module carries them out.
////
//// ```
//// InWorld ─ 0x182, 0x17D or 0x149 ─▶ refused: the 0x56A written, the status stays
////                    accepted: ask the store (the change's request), MovingItem, frames held
//// MovingItem ─ the store's answer ─▶ InWorld with the items the answer leaves
////                                    and the change's replies or the 0x56A written
////             the store unavailable, not running, ended or past its deadline
////                                 ─▶ the connection ends with reason 8
//// ```

import genesis_prime/client_connection.{type Answer, Continue, FromStore}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/character_state
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/state.{
  type Session, InWorld, MovingItem, Session,
} as connection_state
import genesis_prime/game/equip_requirement
import genesis_prime/game/inventory
import genesis_prime/game/movement
import genesis_prime/game/reward_property
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/disconnect_reason.{LostUserServer}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{ForItems}
import genesis_prime/table/loader/store as table_store
import gleam/list

/// The client's 0x182, 0x17D or 0x149, taken from inside 0x038C with the player
/// in the world: a refusal is written and the player stays in the world; an
/// accepted change asks the store and the connection waits in `MovingItem`; a
/// body the client's reader would refuse ends the connection.
pub fn item_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: inventory.Message,
) -> client_connection.Handled(Session) {
  case
    inventory.take(
      items: entered.items,
      life: entered.life,
      tables: session.settings.tables,
      wearer: wearer_of(tables: session.settings.tables, entered:),
      // The value world entry sent in 0x92C.
      bag_slots: reward_property.bag_slots(
        tables: session.settings.tables,
        system: reward_property.hybrid_system,
        tier: reward_property.signature_tier,
      ),
      message:,
      body: inner.body,
    )
  {
    Ok(inventory.Refused(effects:)) ->
      Continue(session, effects_of(session:, effects:))
    Ok(inventory.Asks(moving:)) ->
      connection_state.ask(
        session: Session(
          ..session,
          status: MovingItem(holder:, entered:, moving:),
        ),
        now:,
        request: client_connection.AskStore(inventory.request(
          moving:,
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
        text: inventory.describe(refusal:),
      )
  }
}

/// What the equip checks read of the entered character: its race, class and
/// faction, its level now (the unit's, which a kill's level-up raises), the
/// player facts the prerequisites read (`prerequisite_player`) and the class's
/// item proficiencies.
fn wearer_of(
  tables tables: table_store.Tables,
  entered entered: world_entry.Entered,
) -> equip_requirement.Wearer {
  let character = entered.character
  equip_requirement.Wearer(
    race_id: character.race_id.value,
    class_id: character.class_id.value,
    faction_id: character.faction_id,
    level: connection_state.level_of(entered:),
    player: prerequisite_player.of(tables:, entered:),
    item_proficiencies: character_state.item_proficiencies(
      tables:,
      class_id: character.class_id,
    ),
  )
}

/// The store's answer to the change: the player is in the world again with the
/// items the answer leaves and the change's replies or a 0x56A written; a store
/// that failed ends the connection with reason 8.
pub fn move_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  moving moving: inventory.Moving,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(ForItems(answer))) -> {
      let #(items, effects) =
        inventory.answered(items: entered.items, moving:, answer:)
      let session =
        Session(
          ..session,
          status: InWorld(
            holder:,
            entered: world_entry.Entered(..entered, items:),
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
        text: inventory.not_done(moving.change) <> ": the store is unavailable",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      lost(
        session:,
        now:,
        holder:,
        entered:,
        text: inventory.not_done(moving.change)
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
        text: inventory.not_done(moving.change)
          <> ": the answer is none an item change asked for",
      )
  }
}

/// The connection ends with reason 8 and saves the player's place as in the
/// world, which the player is in.
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
  effects effects: List(inventory.Effect),
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  list.map(effects, fn(effect) {
    case effect {
      inventory.Send(frame:) -> connection_state.to_client(session, frame)
      inventory.Log(level:, text:) ->
        connection_state.log(session:, level:, text:)
    }
  })
}
