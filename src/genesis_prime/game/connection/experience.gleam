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
////                               unit properties' level and the attacker's level (read from
////                               the unit's stat 10 when a cast or a blow is made)
////                            ─▶ 0x938 {self, 10, level} to the player's client
////                            ─▶ a Level news to each viewer, which writes 0x938 stat 10 for a
////                               unit it shows
//// ```
////
//// - **A credit for another stay, or for a player not in the world,** never gets here:
////   `stay_sent` drops it, as it drops every other send for a stay the player has left. A
////   credit that waits behind the camp's final save is dropped once the player has left.
//// - **The experience is saved** with the place (`state.saving`), so what a credit added
////   counts toward the next save.

import genesis_prime/client_connection
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/experience.{
  type Credit, Credited, GainSent, LevelRose, Progress,
}
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/store
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/unit_fields
import gleam/list

/// A creature's credit for the kill of the player's blow: the experience rule takes it, and
/// its effects are written to the player's client and told to its viewers.
pub fn credited(
  session session: Session,
  now _now: Now,
  entered entered: world_entry.Entered,
  credit credit: Credit,
) -> client_connection.Handled(Session) {
  let Credited(progress:, effects:) =
    experience.credited(
      progress: Progress(
        experience: entered.experience,
        level: entered.character.level,
      ),
      credit:,
      tables: session.settings.tables,
      numbers: session.settings.numbers,
    )
  let session =
    connection_state.with_entered(session:, change: fn(entered) {
      world_entry.Entered(
        ..entered,
        experience: progress.experience,
        character: store.Character(..entered.character, level: progress.level),
        unit: player_unit.with_integer_stat(
          record: entered.unit,
          stat_id: unit_fields.level_stat,
          value: progress.level,
        ),
        properties: unit_properties.at_level(
          properties: entered.properties,
          level: progress.level,
        ),
      )
    })
  client_connection.Continue(
    session,
    list.flat_map(effects, carried_out(session:, entered:, effect: _)),
  )
}

/// What one effect of the rule is, as the connection's effects.
fn carried_out(
  session session: Session,
  entered entered: world_entry.Entered,
  effect effect: experience.Effect,
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  case effect {
    GainSent(gain:, unit_id:) -> [
      connection_state.to_client(
        session,
        connection_frames.experience_gained_frame(gain:, unit_id:),
      ),
    ]
    LevelRose(level:) -> [
      connection_state.to_client(
        session,
        connection_frames.level_frame(unit_id: entered.unit_id, level:),
      ),
      ..connection_state.news_to_viewers(
        entered:,
        news: client_connection.Level(level:),
      )
    ]
  }
}
