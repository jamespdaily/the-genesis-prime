//// The tables the server loads at its start: the ones its rules read, not all
//// the client's. Each entry is a table that a module outside
//// `genesis_prime/table/` reads, and a test fails when a module reads a table
//// that is missing here (a new engine that reads a table adds it) or when an
//// entry is read by none. The coverage tool and the tests of the client's
//// tables load every table (`genesis_prime/table.load`).

import genesis_prime/table/character_creation
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/game_formula
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/requirement
import genesis_prime/table/loader/store
import genesis_prime/table/world_location2
import genesis_prime/table/xp_per_level

/// The entry of each table the server loads, in file-name order.
/// - CharacterCreation: the row a create request names
///   (genesis_prime/game/character_creation).
/// - CharacterCustomization and CharacterCustomizationLabel: the rows and
///   labels of a character's look (genesis_prime/game/appearance).
/// - CustomizationParameter and CustomizationParameterMap: the bone values a
///   create request carries (genesis_prime/game/appearance).
/// - GameFormula and XpPerLevel: the starting level (genesis_prime/game/level).
/// - WorldLocation2: the start places (genesis_prime/game/start_place).
pub fn entries() -> List(store.Entry) {
  [
    character_creation.entry(),
    character_customization.entry(),
    character_customization_label.entry(),
    customization_parameter.entry(),
    customization_parameter_map.entry(),
    game_formula.entry(),
    world_location2.entry(),
    xp_per_level.entry(),
  ]
}

/// Loads the server's tables under the server's own key, the same in every
/// run, from the folder that holds the client's extracted `.tbl` files: each
/// table of `entries`, the rows the server requires, and the values built once
/// from them. The load of the server's start and of a test that replays a
/// recording.
pub fn load(from folder: String) -> Result(store.Tables, store.LoadError) {
  store.load_for_server(
    from: folder,
    entries: entries(),
    requirements: requirement.all(),
    derivations: derivation.all(),
  )
}
