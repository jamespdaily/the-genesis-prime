//// The rows the server requires of the client's tables: columns whose ids
//// must all have a row in another table, checked at load.

import genesis_prime/game/appearance
import genesis_prime/game/character_state
import genesis_prime/game/dropped
import genesis_prime/game/hit_radius
import genesis_prime/game/item_property
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
/// - GameFormula row 2375, the longest window name the client sends
///   (genesis_prime/game/dropped).
/// - The Prerequisite row of each Item2 and ItemSpecial that names one, and the
///   ItemSpecial row of each Item2 that names one (genesis_prime/game/item_property).
/// - A Race row for each playable race, whose hitRadius a quest giver's reach counts
///   (genesis_prime/game/hit_radius).
pub fn all() -> List(store.Requirement) {
  list.flatten([
    [start_place.requirement()],
    level.requirements(),
    character_state.requirements(),
    appearance.requirements(),
    dropped.requirements(),
    item_property.requirements(),
    hit_radius.requirements(),
  ])
}
