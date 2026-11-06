//// The rows the server requires of the client's tables: columns whose ids
//// must all have a row in another table, checked at load.

import genesis_prime/game/appearance
import genesis_prime/game/character_state
import genesis_prime/game/level
import genesis_prime/game/start_place
import genesis_prime/table/loader/store
import gleam/list

/// Each required column. A feature that follows a column adds it here, with
/// the evidence that the client reads it.
/// - The start places of the starts of each race and faction, each a row of
///   WorldLocation2 (genesis_prime/game/start_place).
/// - GameFormula row 145 and the XpPerLevel records to the highest level
///   (genesis_prime/game/level).
/// - A Class row for each playable class (genesis_prime/game/character_state).
/// - The CustomizationParameter row of each CustomizationParameterMap row and
///   the CharacterCustomizationLabel row of each label of an indexed
///   CharacterCustomization row (genesis_prime/game/appearance).
pub fn all() -> List(store.Requirement) {
  list.flatten([
    [start_place.requirement()],
    level.requirements(),
    character_state.requirements(),
    appearance.requirements(),
  ])
}
