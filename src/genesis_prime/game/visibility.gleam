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
////   not read (`NotRead`) and a unit with none (0) are shown. The client never tests
////   this column itself: it only removes a unit on the server's 0x355 or 0x262 flag
////   128 (`Creature2.prerequisiteIdVisibility`), so the server decides.
//// - **At entry** the connection holds no cast, no unit and no vitals yet, so the
////   subject is the player as the character and its place give it, with the quest log
////   and no casts (`cast.entering_subject`); every started spawn's visibility
////   prerequisite of the world reads only the faction, the quest log and the casts on
////   the player.
//// - **At a step** the subject is the one the cast rule holds for the player
////   (`cast.subject_of`).

import genesis_prime/game/prerequisite.{type Prerequisite, type Subject}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/store.{type Character}
import genesis_prime/table/id.{type PrerequisiteId}
import genesis_prime/table/loader/store as table_store
import gleam/set.{type Set}

/// The ids of the prerequisites that fail for the subject: every one whose
/// verdict is `Fails`.
pub fn hidden(
  prerequisites _prerequisites: List(Prerequisite),
  subject _subject: Subject,
) -> Set(PrerequisiteId) {
  panic as "shape: #601 the rule that hides a failing prerequisite"
}

/// The ids of the prerequisites that fail for a character entering a world at a
/// place with the quest log it holds, before its unit and casts exist.
pub fn hidden_at_entry(
  prerequisites _prerequisites: List(Prerequisite),
  tables _tables: table_store.Tables,
  character _character: Character,
  place _place: Place,
  quests _quests: QuestLog,
) -> Set(PrerequisiteId) {
  panic as "shape: #601 the set an entering character hides"
}
