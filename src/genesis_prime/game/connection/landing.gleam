//// What another player's cast lands on this connection's player: the heal rows a
//// caster's connection told it (genesis_prime/game/strike_tell `PlayerStrike`), applied to
//// its own life and answered.
////
//// ```
//// caster's connection C                        this connection T (the healed player)
////   Tell(Connection(T), TellPlayerStrike(stay_T, PlayerStrike(key, C, stay_C, outgoing, heals)))
////                      ─▶ ForStay(stay_T, SentByStriker(strike))   (the stay fence; held through an ask)
////                      ─▶ player_life.heals_taken: each row in order on the life the one before left
////   ForStay(stay_C, SentByHealed(PlayerAnswered(key, HealsLanded(splits) | PlayerDead)))
////                      ◀─ Tell(Connection(C), TellPlayerAnswer(stay_C, answered)), then T's own news
//// ```
////
//// - **The answer is told before T's own news**, in the order a creature answers a strike
////   (genesis_prime/game/strike). C holds the healed unit's news while its place in a
////   round waits, so the order decides nothing C's client sees.
//// - **A heal reads the healer's outgoing multiplier from the tell** and T's own incoming
////   multiplier and heal-to-shield conversion (genesis_prime/game/heal_split).
//// - **Nothing here reads the caster**, its sight or the time: a strike arrives for T's
////   stay or is dropped by the stay fence, and is applied when it is taken.
////
//// Gaps for the coverage measure: `gaps()`.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/player_life
import genesis_prime/game/strike_tell
import genesis_prime/game/world_entry
import genesis_prime/gap
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, OwnEffect,
}

/// The heal rows of `strike` applied to the player `entered`, and the answer told to
/// the caster's connection for the stay the strike names, before the player's own news.
pub fn struck(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  strike strike: strike_tell.PlayerStrike,
) -> client_connection.Handled(Session) {
  let #(life, outcome, effects) =
    player_life.heals_taken(
      life: entered.life,
      properties: entered.properties,
      strike:,
    )
  let #(session, news) =
    life_effect.life_changed(session:, now:, change: fn(_) { #(life, effects) })
  let answer: Effect(ConnectionEffect(Request)) =
    OwnEffect(step.Tell(
      to: step.Connection(connection: strike.from),
      request: client_connection.TellPlayerAnswer(
        stay: strike.stay,
        answered: strike_tell.PlayerAnswered(key: strike.key, outcome:),
      ),
    ))
  Continue(session, [answer, ..news])
}

/// What a heal told by another player does not do that a heal of the player's own does.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Casting",
      missing: "A heal told to a player raises neither the healer's LandsHeal nor the healed player's ReceivesHeal event, because the tell carries no spell identity. The client's tables hold such procs in the spells of three abilities (23414, 25595 and 47091: 21 ReceivesHeal rows in their Proxy children) and 38 proc rows in 37 spells that an AMP, an item on equip, an item on activate (70104 and 211223) or a set bonus gives; the server starts no AMP, on-equip or set-bonus spell, and only an item's on-activate spell.",
    ),
    gap.Entry(
      area: "Casting",
      missing: "A heal told to a player is applied whenever it arrives, also after the round of the caster that waits for its answer has closed, because the tell carries no deadline.",
    ),
  ]
}
