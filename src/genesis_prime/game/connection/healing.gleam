//// The player's own heals on the game connection (genesis_prime/game/connection):
//// what the cast rule's `CasterChangeStarts` of a shield heal asks, carried out on the
//// player's life.
////
//// ```
//// the cast rule's CasterChangeStarts(source, ShieldHeal(amount))
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
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/player_life
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}

/// The player's shield heals by `amount` (genesis_prime/game/cast `ShieldHeal`): the
/// life is kept and what it decided is written to the player's client and told to its
/// viewers. With no player in the world it is dropped.
pub fn shield_healed(
  session session: Session,
  now now: Now,
  amount amount: Int,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  life_effect.life_changed(session:, now:, change: fn(entered) {
    player_life.shield_healed(
      life: entered.life,
      amount:,
      properties: entered.properties,
    )
  })
}
