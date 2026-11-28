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
////                            ─▶ 0x169 of the new level's ability points when the total changed
////                               (genesis_prime/game/ability_points), after the 0x938 because the
////                               client re-reads the points when it raises PlayerLevelChange, 2000 ms
////                               after it applies that stat (`lua.Abilities.UpdateInterfaceMenuAlerts`)
////                            ─▶ the abilities the new level grants (genesis_prime/game/ability_book):
////                               0x111 in the next bag slots, then 0x1a0 of them and their alternates,
////                               after the 0x938 because the client's availability check reads the
////                               unit's level (`opcode.0x111.ability_level_up`)
////                            ─▶ a Level news to each viewer, which writes 0x938 stat 10 for a
////                               unit it shows
////                            ─▶ the worn gear read again at the new level (genesis_prime/game/gear.of_items,
////                               for a level-scaled item) and its bases (gear.bases): 0x93a with every base
////                               that changed to the player and the news to each viewer, and the life's
////                               maximum health follows (genesis_prime/game/connection/properties)
//// ```
////
//// - **A gain of another source** (a quest turned in) is `gained`, with the rule's `Credited`
////   made by the source, and is carried out the same way.
//// - **A credit for another stay, or for a player not in the world,** never gets here:
////   `stay_sent` drops it, as it drops every other send for a stay the player has left. A
////   credit that waits behind the camp's final save is dropped once the player has left.
//// - **The experience is saved** with the place (`state.saving`), so what a credit added
////   counts toward the next save.

import genesis_prime/client_connection
import genesis_prime/game/ability_book_frame
import genesis_prime/game/ability_points
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/properties as connection_properties
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/experience.{
  type Credited, Credited, GainSent, LevelRose, Progress,
}
import genesis_prime/game/gear
import genesis_prime/game/limited_action_set
import genesis_prime/game/world_entry
import genesis_prime/shared/class_resource
import genesis_prime/shared/kill_credit.{type Credit}
import genesis_prime/shared/player_unit
import genesis_prime/shared/spell_plan
import genesis_prime/shared/spell_tier
import genesis_prime/shared/unit_fields
import genesis_prime/shared/unit_news
import genesis_prime/shared/unit_properties
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/store
import gleam/list

/// A creature's credit for the kill of the player's blow: the experience rule takes it, and
/// its effects are written to the player's client and told to its viewers.
pub fn credited(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  credit credit: Credit,
) -> client_connection.Handled(Session) {
  gained(
    session:,
    now:,
    entered:,
    credited: experience.credited(
      progress: Progress(
        experience: entered.experience,
        level: entered.character.level,
      ),
      credit:,
      tables: session.settings.tables,
      numbers: session.settings.numbers,
    ),
  )
}

/// What the rule made of a gain of any source, carried out: the new experience and level in
/// `Entered`, the frames of its effects, and the gear's properties at the new level: the Base
/// Health the level gives and what a level-scaled worn item gives at it.
pub fn gained(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  credited credited: Credited,
) -> client_connection.Handled(Session) {
  let Credited(progress:, effects:) = credited
  let tables = session.settings.tables
  let worn = gear.of_items(tables:, items: entered.items, level: progress.level)
  case
    gear.bases(
      tables:,
      gear: worn,
      level: progress.level,
      focus_pool: class_resource.base_focus_pool(resources: entered.resources),
    )
  {
    Error(error) ->
      connection_state.end_for(session:, now:, text: gear.describe(error:))
    Ok(bases) -> {
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(
            ..entered,
            experience: progress.experience,
            character: store.Character(
              ..entered.character,
              level: progress.level,
            ),
            unit: player_unit.with_gear(
              record: player_unit.with_integer_stat(
                record: entered.unit,
                stat_id: unit_fields.level_stat,
                value: progress.level,
              ),
              replacing: entered.gear.visuals,
              item_visuals: worn.visuals,
              bases:,
              defaults: unit_properties.defaults(tables:),
              shield: gear.shield_capacity(gear: worn),
            ),
            gear: worn,
            properties: unit_properties.at_level(
              properties: entered.properties,
              level: progress.level,
            ),
          )
        })
      let told =
        list.flat_map(effects, carried_out(session:, entered:, effect: _))
      let #(session, followed) =
        connection_properties.rebased(
          session:,
          now:,
          bases:,
          shield: worn.properties.shield,
        )
      client_connection.Continue(session, list.append(told, followed))
    }
  }
}

/// What one effect of the rule is, as the connection's effects.
fn carried_out(
  session session: Session,
  entered entered: world_entry.Entered,
  effect effect: experience.Effect,
) -> List(Effect(ConnectionEffect(client_connection.Request))) {
  case effect {
    GainSent(gain:, kind:, unit_id:) -> [
      connection_state.to_client(
        session,
        connection_frames.experience_gained_frame(gain:, kind:, unit_id:),
      ),
    ]
    LevelRose(level:) -> {
      let store.CharacterId(character_number) = entered.character.character_id
      let tables = session.settings.tables
      list.flatten([
        [
          connection_state.to_client(
            session,
            connection_frames.level_frame(unit_id: entered.unit_id, level:),
          ),
        ],
        list.map(
          ability_points.after_rise(
            tables:,
            from_level: entered.character.level,
            to_level: level,
            spent: limited_action_set.points_spent(
              tiers: spell_tier.tiers(tables:),
              saved: entered.action_sets,
            ),
          ),
          connection_state.to_client(session, _),
        ),
        list.map(
          ability_book_frame.granted(
            character_number:,
            loadout: entered.loadout,
            plans: spell_plan.plans_with_later(tables:),
            from_level: entered.character.level,
            to_level: level,
          ),
          connection_state.to_client(session, _),
        ),
        [
          connection_state.broadcast(entered:, news: unit_news.Level(level:)),
        ],
      ])
    }
  }
}
