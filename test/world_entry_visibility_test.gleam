//// What a character's join tells the map to hide (`genesis_prime/game/world_entry`
//// `loaded`, `genesis_prime/game/visibility` `hidden_at_entry`). Expected values come
//// from these places (`table_rows -- Prerequisite 19 41795 41803`):
//// - Prerequisite 19: type 250 (the base faction) equal to 167, the Exiles
////   (Faction2 167; 166 is the Dominion, the faction of a Dominion character's row in
////   CharacterCreation). It fails for a Dominion character and passes for an Exile.
//// - Prerequisite 41803: an OR of type 43 on quests 10527 and 10532, objective 3: it
////   fails for a character whose quest log holds neither quest open.
//// - Prerequisite 41795: type 15 (under the spell 85562), comparison 2 (not under): it
////   passes for a character that is under no cast, which is every character at its
////   entry, so it is not in the join's hidden set.
//// - World 3460's index is those three: the Creature2 rows of the world's started
////   spawns name 19 (the EXILE mount displays 74781 to 74784), 41803 (the Start Arrow
////   73707) and 41795 (the hologram 73619).

import character_tables
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/world_entry
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/world_map/map
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/set.{type Set}
import owned_test
import prerequisite_support
import world_entry_support

/// A prerequisite as the client's rows give it.
fn loaded_prerequisite(number number: Int) -> Prerequisite {
  let tables = character_tables.shared()
  let assert Ok(loaded) =
    prerequisite.load(
      id: PrerequisiteId(number),
      rows: prerequisite.table_rows(tables:),
      arcs: prerequisite.table_arcs(tables:),
      quests: prerequisite.table_quests(tables:),
    )
    as "the client's rows hold the prerequisite and the quests it reads"
  loaded
}

/// World 3460's visibility prerequisites, each once, in id order.
fn world_3460_index() -> dict.Dict(Int, List(Prerequisite)) {
  dict.from_list([
    #(3460, list.map([19, 41_795, 41_803], loaded_prerequisite)),
  ])
}

/// The numbers of the prerequisites the join tells the map to hide, for a
/// character of the faction (Faction2 id) with an empty quest log.
fn join_hidden(faction faction: Int) -> Set(Int) {
  join_hidden_by(faction:, index: world_3460_index())
}

/// The same when the content load holds this index of visibility prerequisites.
fn join_hidden_by(
  faction faction: Int,
  index index: dict.Dict(Int, List(Prerequisite)),
) -> Set(Int) {
  let tables = character_tables.shared()
  let #(_state, loaded) =
    world_entry_support.loaded_seeing(
      tables:,
      character: world_entry_support.character(class: 1, faction:, level: 3),
      items: [],
      saved_experience: None,
      quests: [],
      visibility: index,
    )
  let assert world_entry.Join(effects:, ..) = loaded
    as "the play of a character with a saved place joins its map"
  let asked =
    list.filter_map(effects, fn(effect) {
      case effect {
        world_entry.AskMap(message: map.Join(hidden:, ..), ..) -> Ok(hidden)
        world_entry.AskMap(..)
        | world_entry.AskStore(..)
        | world_entry.Send(..)
        | world_entry.WatchMap(..)
        | world_entry.Life(..)
        | world_entry.StartPassive(..)
        | world_entry.Warn(..) -> Error(Nil)
      }
    })
  let assert [hidden] = asked
    as "the join asks the map once, and the ask names what to hide"
  set.map(hidden, fn(found) {
    let PrerequisiteId(number) = found
    number
  })
}

/// A planted prerequisite of type 15 (`TargetOfLiveCast`), comparison 1, which passes
/// only while a live cast of the Spell4 has the unit as a target.
const needs_a_cast = 900_002

pub fn a_unit_whose_visibility_prerequisite_needs_a_cast_the_player_is_not_casting_is_not_written_at_join_test() -> Nil {
  use <- owned_test.run(60_000)
  let index =
    dict.from_list([
      #(3460, [
        prerequisite_support.single(id: needs_a_cast, condition: #(
          15,
          1,
          0,
          46_073,
        )),
      ]),
    ])
  assert join_hidden_by(faction: 167, index:) == set.from_list([needs_a_cast])
    as "Prerequisite.prerequisiteTypeId.15, comparison 1: it passes only while a live cast of Spell4 46073 has the unit as a target, and a player entering the world casts nothing, so the join names it hidden and its units are not written"
}

pub fn the_join_names_the_hidden_set_by_faction_test() -> Nil {
  use <- owned_test.run(60_000)
  assert join_hidden(faction: 167) == set.from_list([41_803])
    as "an Exile with no quest in World 3460 fails 41803 (neither quest open) and is under no cast, so it passes 41795 and 19 (the Exiles)"
  assert join_hidden(faction: 166) == set.from_list([19, 41_803])
    as "a Dominion character with no quest fails 19 (the base faction is not 167) as well as 41803"
}
