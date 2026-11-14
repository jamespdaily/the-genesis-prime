//// Which visibility prerequisites fail for a player: the set the connection tells
//// its map, so the map shows the player only the units whose prerequisite does not
//// fail (genesis_prime/world_map/map).
////
//// ```
//// world_entry (the Join)      ─▶ hidden_at_entry(world's prerequisites, character, place, quests)
//// the end of each step        ─▶ hidden(world's prerequisites, the cast rule's subject)
//// hidden changed since the last step ─▶ TellVisibilityChanged ─▶ the map's VisibilityChanged
//// ```
////
//// - **What hides a unit** is a verdict of `Fails` for the prerequisite named by
////   its Creature2 row's `prerequisiteIdVisibility`. A prerequisite the server does
////   not read (`NotRead`) and a unit with none (0) are shown; a type 47 condition is
////   one of those, though a cast it gates is refused. The client never tests
////   this column itself: it only removes a unit on the server's 0x355 or 0x262 flag
////   128 (`Creature2.prerequisiteIdVisibility`), so the server decides.
//// - **At entry** the connection holds no cast and no unit yet, so the subject is the
////   player as the character and its place give it, with the quest log, the health it
////   enters at and no casts (`cast.entering_subject`); every started spawn's
////   visibility prerequisite of the world reads only the faction, the quest log and
////   the casts on the player. It holds no checker, so a condition on the player's
////   items, ability book or world difficulty is not read there, and the first
////   end-of-step check decides it.
//// - **At a step** the subject is the one the cast rule holds for the player
////   (`cast.subject_of`), with the checker: the items, the ability book and the
////   world difficulty.

import genesis_prime/game/cast
import genesis_prime/game/prerequisite.{type Prerequisite, type Subject}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/store.{type Character}
import genesis_prime/table/id.{type PrerequisiteId}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option}
import gleam/set.{type Set}

/// The ids of the prerequisites that fail for the subject: every one whose
/// verdict is `Fails`.
pub fn hidden(
  prerequisites prerequisites: List(Prerequisite),
  subject subject: Subject,
) -> Set(PrerequisiteId) {
  prerequisites
  |> list.filter(fn(found) {
    case prerequisite.check_for_visibility(prerequisite: found, subject:) {
      prerequisite.Fails -> True
      prerequisite.Passes | prerequisite.NotRead(..) -> False
    }
  })
  |> list.map(fn(found) { prerequisite.id(prerequisite: found) })
  |> set.from_list
}

/// The ids of the prerequisites that fail for a character entering a world at a
/// place with the quest log it holds, before its unit and casts exist. The
/// character's faction is both its current and its base faction, the level is the
/// character's (a level override stat exists only on the unit). `health` is the
/// health the player enters at against its maximum.
pub fn hidden_at_entry(
  prerequisites prerequisites: List(Prerequisite),
  tables tables: table_store.Tables,
  character character: Character,
  place place: Place,
  quests quests: QuestLog,
  health health: Option(prerequisite.Vital),
) -> Set(PrerequisiteId) {
  let player =
    prerequisite.player_of(
      tables:,
      character:,
      world_id: start_place.world_id(place),
      zone: start_place.world_zone_id(place),
      level: character.level,
    )
  let subject =
    cast.entering_subject(
      player:,
      factions: prerequisite.Factions(
        current: character.faction_id,
        base: character.faction_id,
      ),
      quests:,
      health:,
    )
  hidden(prerequisites:, subject:)
}
