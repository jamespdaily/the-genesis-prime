//// The spend of an item's charge on the game connection (genesis_prime/game/connection):
//// the cast a 0x943 started is held while the store saves what the use spends, and the
//// store's answer releases it or cancels it. The rule is genesis_prime/game/item_charge's,
//// which holds the diagram and the failure table; this module carries it out.
////
//// ```
//// InWorld ─ cast.use_item gave Started ─▶ item_charge.spend
////             NothingToSpend ─▶ the cast adopted and its effects carried out, InWorld
////             otherwise      ─▶ ask the store (SpendItem or DeleteItem), SpendingCharge,
////                               the cast's state and effects held
//// SpendingCharge ─ the store's answer ─▶ ItemsSaved: the inventory frame, the press decided
////                                        again at the answer's time, its cast adopted with the
////                                        press id, its effects, InWorld
////                                      ItemsNotSaved | SaveRefused: 0x7fc result 1 and a
////                                        log line, the items and the cast as before, InWorld
////                  the store unavailable, not running, ended or past its deadline
////                                      ─▶ the connection ends with reason 8, nothing released
//// ```
////
//// - **The shell takes no input while the ask is out**, so a second 0x943 waits behind the
////   answer and meets the lowered item and the recorded press id.
//// - **The cast's timers and cooldowns run from its release**: the press is decided again
////   at the answer's time on the items as they were, since the cast rule stamps the
////   times of a start into its state and effects. The press-time decision stands when the
////   second one starts nothing.
//// - **A refused save is the server's failure**, shown with result 1 (`UnableToCreateSpell`,
////   text 119668), and the connection goes on: the store is not known to be away.
//// - **The cast's effects are carried out by the caller's `release`** (the connection's
////   casting), which this module cannot import: casting asks this module to start the spend.

import genesis_prime/client_connection.{type Answer, type Request, Continue}
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/inventory as connection_inventory
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/state.{
  type Session, InWorld, Session, SpendingCharge,
} as connection_state
import genesis_prime/game/inventory
import genesis_prime/game/item_charge
import genesis_prime/game/item_property
import genesis_prime/game/movement
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/cast_result
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, type Outcome,
}
import genesis_prime/store.{ItemsNotSaved, ItemsSaved, SaveRefused}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// What carries out the cast rule's effects for the connection, in order
/// (`connection/casting.cast_effects`).
pub type Release =
  fn(Session, Now, List(cast_state.Effect)) ->
    #(Session, List(Effect(ConnectionEffect(Request))))

/// The cast rule's decision of a 0x943's body again, at the time and for the items it is
/// given: the state and effects of the cast it starts, none when it starts nothing
/// (`casting.item_use_started`).
pub type Decide =
  fn(Session, Now, world_entry.Entered, BitArray) ->
    Option(#(cast_state.State, List(cast_state.Effect)))

/// The cast the player's 0x943 started, taken from `cast.use_item`: the item the press
/// named is spent from (`item_charge.spend`); a spend that takes nothing applies the cast
/// at once, any other asks the store and the connection waits in `SpendingCharge` with the
/// cast's state and effects held.
pub fn started(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  press press: cast_state.ItemPress,
  body body: BitArray,
  cast cast: cast_state.State,
  effects effects: List(cast_state.Effect),
  release release: Release,
) -> client_connection.Handled(Session) {
  let tables = session.settings.tables
  let assert Ok(item) =
    inventory.held_at(items: entered.items, place: press.place)
    as "the cast rule started the press on the item held at its place"
  let assert Ok(max_charges) =
    item_property.max_charges(tables:, item2_id: item.item2_id.value)
    as "the use check read the item's row"
  let assert Ok(stack_limit) =
    item_property.stack_limit(tables:, item2_id: item.item2_id.value)
    as "the use check read the item's row"
  let spend = item_charge.spend(item:, stack_limit:, max_charges:)
  let spending =
    item_charge.Spending(press:, body:, item:, spend:, cast:, effects:)
  case
    item_charge.request(
      spend:,
      item:,
      account_id: holder.account_id,
      character_id: entered.character_id,
      session_epoch: movement.session_epoch(state: entered.movement),
    )
  {
    None -> {
      let entered = world_entry.Entered(..entered, cast:)
      let session = Session(..session, status: InWorld(holder:, entered:))
      let #(session, written) = release(session, now, effects)
      Continue(session, written)
    }
    Some(request) ->
      connection_state.ask(
        session: Session(
          ..session,
          status: SpendingCharge(holder:, entered:, spending:),
        ),
        now:,
        request: client_connection.AskStore(request),
        before: [],
      )
  }
}

/// The store's answer to the spend, as the diagram says: the inventory frame, the cast and
/// its effects after `ItemsSaved`; 0x7fc result 1 and the items and cast as before after
/// `ItemsNotSaved` or `SaveRefused`; the connection ends with reason 8 when the store
/// failed (`connection/inventory.answered`).
pub fn answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  spending spending: item_charge.Spending,
  outcome outcome: Outcome(Answer),
  decide decide: Decide,
  release release: Release,
) -> client_connection.Handled(Session) {
  let what = "the spend of the item's charge was not saved"
  connection_inventory.answered(
    session:,
    now:,
    holder:,
    entered:,
    what:,
    asked: "a spend",
    outcome:,
    saved: fn(session, answer) {
      case answer {
        ItemsSaved ->
          released(
            session:,
            now:,
            holder:,
            entered:,
            spending:,
            decide:,
            release:,
          )
        ItemsNotSaved ->
          cancelled(
            session:,
            holder:,
            entered:,
            spending:,
            level: step.LogWarning,
            text: "a later login holds the character, or the item is not as the server holds it",
          )
        SaveRefused(constraint:) ->
          cancelled(
            session:,
            holder:,
            entered:,
            spending:,
            level: step.LogError,
            text: "the store refused the change by the constraint "
              <> constraint,
          )
        store.ItemMade(..)
        | store.Bought(..)
        | store.Sold(..)
        | store.TurnedIn(..) ->
          connection_inventory.lost(
            session:,
            now:,
            holder:,
            entered:,
            text: what <> ": the answer is none a spend asked for",
          )
      }
    },
  )
}

/// The spend is saved: the inventory frame, the cast the press starts at this time adopted
/// with the press id and its effects carried out, then what the items now held count for
/// the objectives and, for a worn item, the gear. The press is decided again on the items as
/// the press found them; the press-time decision stands when that starts nothing.
fn released(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  spending spending: item_charge.Spending,
  decide decide: Decide,
  release release: Release,
) -> client_connection.Handled(Session) {
  let #(cast, effects) = case
    decide(
      Session(..session, status: InWorld(holder:, entered:)),
      now,
      entered,
      spending.body,
    )
  {
    Some(decided) -> decided
    None -> #(spending.cast, spending.effects)
  }
  let #(items, frame) =
    item_charge.spent(
      items: entered.items,
      item: spending.item,
      spend: spending.spend,
    )
  let entered = world_entry.Entered(..entered, items:, cast:)
  let session = Session(..session, status: InWorld(holder:, entered:))
  let told = case frame {
    Some(frame) -> [connection_state.to_client(session, frame)]
    None -> []
  }
  let #(session, released) = release(session, now, effects)
  let #(session, settled) = connection_objective.settled(session:, now:)
  let assert Some(entered) = connection_state.entered_of(session.status)
    as "the player stays in the world while the cast is released"
  connection_inventory.regeared(
    session:,
    now:,
    holder:,
    entered:,
    moved: list.flatten([told, released, settled]),
  )
}

/// The spend is not saved: the cast is cancelled with 0x7fc result 1, an outside failure
/// shown as the server's, and the items and the cast stay as they were.
fn cancelled(
  session session: Session,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  spending spending: item_charge.Spending,
  level level: step.LogLevel,
  text text: String,
) -> client_connection.Handled(Session) {
  let session = Session(..session, status: InWorld(holder:, entered:))
  let press = spending.press
  let frame =
    cast_frame.refused_frame(
      client_cast_id: press.client_cast_id,
      spell4_id: press.spell4_id,
      result: cast_result.UnableToCreateSpell,
    )
  Continue(session, [
    connection_state.to_client(session, frame),
    connection_state.log(
      session:,
      level:,
      text: "the use of the item at ("
        <> int.to_string(press.place.location)
        <> ", "
        <> int.to_string(press.place.bag_index)
        <> ") cancelled its cast of Spell4 "
        <> int.to_string(press.spell4_id)
        <> ": "
        <> text,
    ),
  ])
}
