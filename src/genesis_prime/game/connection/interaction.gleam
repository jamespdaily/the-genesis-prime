//// The player's request to talk to a unit on the game connection
//// (genesis_prime/game/interaction): the rule decides, and this carries out its
//// effects in order, a log line, the 0x0357 that opens the unit's dialog, the 0x090B
//// and 0x00BC that open a vendor's window, or the 0x0106 and refusing 0x090B of a
//// vendor request the client would refuse, and the count of a talk to a creature an
//// objective names (genesis_prime/game/connection/objective). The rule's result for the vendor window is
//// held on the player, which a purchase reads. A refusal ends the connection with the
//// sentence the rule gives.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/objective as connection_objective
import genesis_prime/game/connection/quest as connection_quest
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/objective
import genesis_prime/game/quest
import genesis_prime/game/shown
import genesis_prime/game/world_entry
import genesis_prime/step.{type Now}
import gleam/list
import gleam/option.{None, Some}

/// What a message of the interaction feature does, taken from inside 0x038C with
/// the player in the world.
pub fn interaction_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: interaction.Message,
) -> client_connection.Handled(Session) {
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  case
    interaction.take(
      message:,
      body: inner.body,
      player: interaction.Player(
        race_id: entered.character.race_id,
        faction: faction,
        place: movement.place(state: entered.movement),
      ),
      picture: entered.shown,
      tables: session.settings.tables,
      vendors: session.settings.vendors,
      now_ms: now.monotonic_ms,
      offers: fn(creature) {
        quest.offers(
          tables: session.settings.tables,
          asker: connection_quest.asker(session:, entered:),
          creature:,
        )
      },
      talk_targets: objective.talk_targets(
        log: entered.quests,
        tables: session.settings.tables,
      ),
      logged: session.interaction_logged,
    )
  {
    Ok(taken) -> {
      let session =
        Session(
          ..connection_state.with_entered(session:, change: fn(entered) {
            case taken.window {
              interaction.Opens(opened:) ->
                world_entry.Entered(..entered, vendor: Some(opened))
              interaction.Closes -> world_entry.Entered(..entered, vendor: None)
              interaction.Keeps -> entered
            }
          }),
          interaction_logged: taken.logged,
        )
      let #(session, written) =
        list.fold(taken.effects, #(session, []), fn(so_far, effect) {
          let #(session, written) = so_far
          let #(session, more) = case effect {
            interaction.Log(level:, text:) -> #(session, [
              connection_state.log(session:, level:, text:),
            ])
            interaction.OpenDialog(unit_id:) -> #(session, [
              connection_state.to_client(
                session,
                connection_frames.dialog_open_frame(unit_id:),
              ),
            ])
            interaction.TalkedTo(creature_id:) ->
              connection_objective.counted(
                session:,
                now:,
                event: objective.TalkedTo(creature_id:),
              )
            interaction.OpenVendor(unit_id:, vendor:) -> #(session, [
              connection_state.to_client(
                session,
                connection_frames.vendor_items_frame(unit_id:, vendor:),
              ),
              connection_state.to_client(
                session,
                connection_frames.buyback_list_frame(
                  entries: entered.buyback.entries,
                ),
              ),
            ])
            interaction.RefuseVendor(unit_id:, code:) -> #(session, [
              connection_state.to_client(
                session,
                connection_frames.generic_error_frame(code:),
              ),
              connection_state.to_client(
                session,
                connection_frames.vendor_refused_frame(unit_id:),
              ),
            ])
          }
          #(session, list.append(written, more))
        })
      Continue(session, written)
    }
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: interaction.describe_refusal(refusal:),
      )
  }
}
