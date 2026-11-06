//// The player's look on the game connection (genesis_prime/game/connection): its rule
//// (genesis_prime/game/look) is kept in the player's `Entered` beside its properties,
//// and this module turns what the cast rule decides into the rule's inputs and carries
//// out the slots that changed. No new process: the connection that owns the player
//// speaks for its unit to each viewer, as it does for stealth and properties.
////
//// ```
//// the cast rule's CasterChangeStarts(Look) ─▶ look.start ─┐
//// the cast rule's CasterChangeEnds              ─▶ look.end   ─┤ visuals whose display changed
////                                                          ├─▶ 0x933 {owner, visuals} to the player's client
////                                                          └─▶ LookChanged(visuals) to each viewer
//// ```
////
//// ```
//// owner's connection                                    viewer's connection            clients
//// go of Mode: Eradicate (47866 ─▶ Proxy 47860), gate 30100 passes for an Exile
////   0x7f4 lists 112543 on the caster
////   start at the go: look.start(source, [64 -> 4807])
////     changed [64 4807 0 0] ─▶ 0x933 {owner, ..} ───────────────────────────────────▶ owner's client
////                           ─▶ Tell(v, LookChanged(..)) ─▶ shown? 0x933 {owner, ..} ─▶ viewer's client
//// 10,250 ms later, the modifier's end timer
////   look.end(source)
////     changed [64 0 0 0]    ─▶ 0x933 {owner, ..} ───────────────────────────────────▶ owner's client
////                           ─▶ Tell(v, LookChanged(..)) ─▶ shown? 0x933 {owner, ..} ─▶ viewer's client
////
//// a viewer comes to see the owner mid-disguise
////   map: SeenBy(v2, stay) ─▶ Tell(v2, Appeared(0x262 with slot 64 = 4807)) ─▶ not shown? 0x262 ─▶ drawn in the suit
//// ```
////
//// - **The player and its viewers are told the same visuals**, the slots whose shown
////   display changed, in one 0x933 each (`opcode.0x933`); a viewer's client shows the
////   unit when its news arrives and drops it otherwise
////   (genesis_prime/game/connection/viewers). A viewer that arrives later is created
////   with the current visuals in its 0x262 (`frames.appearance_at`, `look.visuals`), so it
////   needs no 0x933.
//// - **A change that moves nothing is not told:** a disguise that shows what the slot
////   shows, a source already held, and an end of a source that is not held.
//// - **A player not held in the world** (a save, a leave) takes no change: its look goes
////   with its `Entered`.
//// - **Death:** the cast rule's `died` ends the modifiers of its casts (`CasterChangeEnds`),
////   so the look ends in the death's step and the restore 0x933 goes to the player and
////   its viewers in the order the cast rule gives the ends.
//// - **Camp or the Holocrypt:** the viewers get `Removed` (0x355) and no 0x933; `Entered`
////   and its look go, and the next stay's 0x262 holds the base visuals.
//// - **The connection crashes:** the supervisor rebuilds it from storage, the map sends
////   its viewers `UnseenBy`, `Gone` writes their 0x355, and the next entry has the base
////   look.
//// - **Late and out-of-order news:** a `LookChanged` of an earlier stay is dropped at
////   `stay_sent`; one for a unit the viewer does not show, or no longer shows, is
////   dropped; one to a connection that has ended is a dropped send. `Appeared` and
////   `LookChanged` to one viewer come from one sender, so the BEAM keeps their order, and
////   the overlay in the 0x262 is built when `SeenBy` is taken, so a later change arrives
////   after it.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/look
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/step.{type ConnectionEffect, type Effect}
import gleam/option.{None, Some}

/// A disguise of the player's own spell starts (genesis_prime/game/cast
/// `CasterChangeStarts` with a `Look` change).
pub fn started(
  session session: Session,
  source source: unit_properties.Source,
  disguise disguise: look.Disguise,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  changed(session:, change: look.start(look: _, source:, disguise:))
}

/// A disguise of the player's own spell ends (genesis_prime/game/cast `CasterChangeEnds`),
/// or is told ended for a source the look does not hold, which changes nothing.
pub fn ended(
  session session: Session,
  source source: unit_properties.Source,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  changed(session:, change: look.end(look: _, source:))
}

/// The session with the look changed by `change`, and for the visuals it reports: the
/// look held and everything told. The player's `Entered` is updated once.
fn changed(
  session session: Session,
  change change: fn(look.Look) -> #(look.Look, List(ItemVisual)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.held_in_the_world(session.status) {
    None -> #(session, [])
    Some(#(_, entered)) -> {
      let #(look, visuals) = change(entered.look)
      let updated = world_entry.Entered(..entered, look:)
      let session =
        connection_state.with_entered(session:, change: fn(_) { updated })
      case visuals {
        [] -> #(session, [])
        [_, ..] -> #(session, told(session:, entered: updated, visuals:))
      }
    }
  }
}

/// 0x933 to the player's client and `LookChanged` to each viewer, the same visuals.
fn told(
  session session: Session,
  entered entered: world_entry.Entered,
  visuals visuals: List(ItemVisual),
) -> List(Effect(ConnectionEffect(Request))) {
  [
    connection_state.to_client(
      session,
      connection_frames.item_visuals_frame(
        unit_id: entered.unit_id,
        item_visuals: visuals,
      ),
    ),
    ..connection_state.news_to_viewers(
      entered:,
      news: client_connection.LookChanged(item_visuals: visuals),
    )
  ]
}
