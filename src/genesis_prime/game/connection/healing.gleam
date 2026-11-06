//// The player's own heals on the game connection (genesis_prime/game/connection):
//// what the cast rule's `PropertyStarts` of a shield heal asks, carried out on the
//// player's life.
////
//// ```
//// the cast rule's PropertyStarts(source, ShieldHeal(amount))
////   ─▶ player_life.shield_healed ─▶ 0x938 {P, 20, shield} to the player's client
////                                 ─▶ Shield news to each viewer
//// ```
////
//// - **The amount is the cast rule's**, worked out at the go and shown in its 0x7f4;
////   the life raises the shield by it, capped at its maximum.
//// - **A heal that moves nothing** (a full shield, a dead player) writes nothing
////   (genesis_prime/game/player_life).
//// - **A player not held in the world** (a save, a leave) takes no heal.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/player_life
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import gleam/option.{None, Some}

/// The player's shield heals by `amount` (genesis_prime/game/cast `ShieldHeal`): the
/// life is kept and what it decided is written to the player's client and told to its
/// viewers. With no player in the world it is dropped.
pub fn shield_healed(
  session session: Session,
  now now: Now,
  amount amount: Int,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.held_in_the_world(session.status) {
    None -> #(session, [])
    Some(#(_, entered)) -> {
      let #(life, effects) =
        player_life.shield_healed(life: entered.life, amount:)
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, life:)
        })
      #(session, life_effect.life_effects(session:, now:, entered:, effects:))
    }
  }
}
