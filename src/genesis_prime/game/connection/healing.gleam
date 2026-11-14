//// The player's own heals on the game connection (genesis_prime/game/connection):
//// what the cast rule's `CasterChangeStarts` of a heal asks, carried out on the
//// player's life.
////
//// ```
//// the cast rule's CasterChangeStarts(source, Heal(vital, amount))
////   ─▶ player_life.healed ─▶ 0x938 {P, 20, shield} to the player's client
////                          ─▶ Shield news to each viewer        (a shield heal)
////                          ─▶ 0x92f to the player's client
////                          ─▶ Health news to each viewer        (a health heal)
//// ```
////
//// - **The amount is the cast rule's**, worked out at the go and shown in its 0x7f4;
////   the life raises the vital by it, capped at its maximum.
//// - **A heal that moves nothing** (a full vital, a dead player) writes nothing
////   (genesis_prime/game/player_life).
//// - **A player not held in the world** (a save, a leave) takes no heal.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/effect_kind
import genesis_prime/game/player_life
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}

/// The player's `vital` heals by `amount` (genesis_prime/game/cast `Heal`): the life is
/// kept and what it decided is written to the player's client and told to its viewers.
/// With no player in the world it is dropped.
pub fn healed(
  session session: Session,
  now now: Now,
  vital vital: effect_kind.Vital,
  amount amount: Int,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  life_effect.life_changed(session:, now:, change: fn(entered) {
    player_life.healed(
      life: entered.life,
      vital:,
      amount:,
      properties: entered.properties,
    )
  })
}
