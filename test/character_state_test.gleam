//// The rows message 0x025E reads (`genesis_prime/game/character_state`). Expected
//// values come from these places.
//// - `opcode.0x25e.safe_body`: the experience is the XpPerLevel row's
////   minXpForLevel for the character's level and the item proficiencies are the
////   class's `Class.startingItemProficiencies`, so a load without a Class row for
////   a playable class fails, as "a missing row fails the load" (CLAUDE.md). The
////   playable classes are Warrior 1, Engineer 2, Esper 3, Medic 4, Stalker 5 and
////   Spellslinger 7 (`Class` rows of the client's table).
//// - The XpPerLevel rows to the highest level are required by the level's own
////   load check (`level_test`), so the only levels with no row are 0 and the ones
////   above the record at the highest level, which a saved character can hold
////   (the `character` table bounds a level below only at 0): such a play is
////   refused when the store answers, before the map is asked, so no unit of it
////   reaches the map.
//// The real-table test is skipped where the client's tables are not on the machine.

import character_tables
import client_tables
import fixture_tables
import genesis_prime/game/character_state
import genesis_prime/game/world_entry
import genesis_prime/table/class
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table
import unitest
import world_entry_support

const playable = [1, 2, 3, 4, 5, 7]

/// Loads a Class table of the committed rows of these classes, with the
/// character state's requirements.
fn load(
  classes classes: List(Int),
) -> Result(table_store.Tables, table_store.LoadError) {
  use folder <- planted_table.in_folder([
    planted_table.file(
      class.schema,
      list.filter(fixture_tables.committed_rows(class.schema), fn(row) {
        case row {
          [planted_table.Integer(id), ..] -> list.contains(classes, id)
          _ -> False
        }
      }),
    ),
  ])
  table_store.read(
    from: folder,
    entries: [class.entry()],
    requirements: character_state.requirements(),
    derivations: [],
  )
}

pub fn the_table_load_fails_when_a_playable_class_has_no_class_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(_) = load(classes: playable)
    as "the six playable classes' rows load"
  list.each(playable, fn(missing) {
    assert load(classes: list.filter(playable, fn(class) { class != missing }))
      == Error(table_store.RowMissing(
        from_table: "the server's playable classes",
        column: "Class id",
        to_table: "Class",
        id: missing,
      ))
      as {
        "opcode.0x25e.safe_body: a load without the Class row of class "
        <> int.to_string(missing)
        <> " fails"
      }
  })
}

pub fn the_client_has_a_class_row_for_each_playable_class_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert list.flat_map(character_state.requirements(), fn(requirement) {
      requirement.missing(client_tables.shared())
    })
    == []
    as "the client's Class table holds rows 1, 2, 3, 4, 5 and 7"
}

pub fn a_level_with_no_xp_per_level_row_is_refused_before_the_map_is_asked_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([0, 202, 1000], fn(level) {
    // With nothing saved, and with an experience saved: the level's row is
    // asked first, so a saved experience does not let such a play in.
    list.each([None, Some(5000)], fn(saved_experience) {
      let #(_, loaded) =
        world_entry_support.loaded_holding(
          tables: character_tables.shared(),
          character: world_entry_support.character(
            class: 2,
            faction: 166,
            level:,
          ),
          items: [],
          saved_experience:,
          quests: [],
        )
      assert loaded
        == world_entry.Refused(
          character_id: 42,
          warning: "a play of character 42, whose level "
            <> int.to_string(level)
            <> " has no XpPerLevel row",
        )
        as {
          "XpPerLevel holds the client's records 1 to 201: level "
          <> int.to_string(level)
          <> " has none, so the play is refused and no Join is asked of the map"
        }
    })
  })
}
