//// The player's experience on the game connection (genesis_prime/game/connection): what a
//// creature's kill credit asks of the player in the world, carried out as the rule
//// decided it (genesis_prime/game/experience).
////
//// ```
//// ForStay(stay, SentByKill(credit))   the stay is the player's own, the player in the world
////   ─▶ experience.credited(progress, credit, tables, numbers)
////   ─▶ GainSent(gain, unit)  ─▶ 0x1ac {gain, 0, 0, 2, unit} to the player's client
////   ─▶ LevelRose(level)      ─▶ every holder of the level in `Entered` changes: the character,
////                               the unit's stat 10 (so a later viewer's 0x262 is right), the
////                               unit properties' level and the attacker's level
////                            ─▶ 0x938 {self, 10, level} to the player's client
////                            ─▶ a Level news to each viewer, which writes 0x938 stat 10 for a
////                               unit it shows
//// ```
////
//// - **A credit for another stay, or for a player not in the world,** never gets here:
////   `stay_sent` drops it, as it drops every other send for a stay the player has left.
//// - **The experience is saved** with the place (`state.saving`), so a credit that comes
////   while a save is out waits for its outcome like every other send, and counts toward
////   the next save.

import genesis_prime/client_connection
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/game/experience.{type Credit, Credited, Progress}
import genesis_prime/game/world_entry
import genesis_prime/step.{type Now}

/// A creature's credit for the kill of the player's blow: the experience rule takes it, and
/// its effects are written to the player's client and told to its viewers.
pub fn credited(
  session session: Session,
  now _now: Now,
  entered entered: world_entry.Entered,
  credit credit: Credit,
) -> client_connection.Handled(Session) {
  let Credited(progress: _, effects: _) =
    experience.credited(
      progress: Progress(
        experience: entered.experience,
        level: entered.character.level,
      ),
      credit:,
      tables: session.settings.tables,
      numbers: session.settings.numbers,
    )
  panic as "the build takes the credit with the experience rule, keeps the new experience and level in Entered, and carries out 0x1ac, 0x938 stat 10 and the Level news"
}
