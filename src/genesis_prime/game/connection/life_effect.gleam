//// What a player's life decided, as the connection's effects: the messages to the
//// player's own client, the news to its viewers, the answer told to the creature that
//// struck it and the start of a fighter's stream (genesis_prime/game/player_life).
//// The life's fights and its death are carried out by genesis_prime/game/connection/life,
//// a change of the player's properties by genesis_prime/game/connection/properties;
//// both turn the life's effects into the connection's here.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/movement as connection_movement
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/world_entry
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, CancelTimer, OwnEffect,
  StartTimer,
}
import gleam/list

/// What player_life decided, as the connection's effects: its own unit's messages
/// to its client, its news to its viewers, the answer told to the creature, and the
/// start of a fighter's stream at the player's place now. The casts' end and the
/// Holocrypt are `life_carried`'s.
pub fn life_effects(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  effects effects: List(player_life.Effect),
) -> List(Effect(ConnectionEffect(Request))) {
  list.flat_map(effects, fn(effect) {
    case effect {
      player_life.ToClient(written:) -> [
        connection_state.to_client(
          session,
          connection_frames.own_unit_frame(entered:, now:, written:),
        ),
      ]
      player_life.ToViewers(news:) ->
        list.map(connection_state.sorted_viewers(entered:), fn(viewer) {
          connection_state.news_to(entered:, viewer:, news:)
        })
      player_life.Answer(to:, answered:) -> [
        OwnEffect(step.Tell(
          to:,
          request: client_connection.TellStrikeAnswered(answered:),
        )),
      ]
      player_life.StreamTo(unit_id:, life:) -> [
        connection_movement.tells_a_fighter_the_place(
          connection: client_connection.connection(session.link),
          entered:,
          fighter: #(unit_id, life),
          place: movement.place(entered.movement),
          seq: session.move_seq,
        ),
      ]
      player_life.StartTimer(timer:, after_ms:) -> [
        OwnEffect(StartTimer(timer:, after_ms:)),
      ]
      player_life.CancelTimer(timer:) -> [OwnEffect(CancelTimer(timer:))]
      player_life.DamageTaken
      | player_life.EndCasts
      | player_life.GoToHolocrypt -> []
    }
  })
}
