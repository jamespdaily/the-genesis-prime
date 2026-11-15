//// The rows the server requires of the client's tables: columns whose ids
//// must all have a row in another table, checked at load.

import genesis_prime/game/appearance
import genesis_prime/game/character_state
import genesis_prime/game/crowd_control
import genesis_prime/game/currency
import genesis_prime/game/departures
import genesis_prime/game/dropped
import genesis_prime/game/hit_radius
import genesis_prime/game/item_property
import genesis_prime/game/level
import genesis_prime/game/quest_turn_in
import genesis_prime/game/start_place
import genesis_prime/game/vendor_sale
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
/// - GameFormula rows 1115 and 1116, the credit and Renown caps (genesis_prime/game/currency).
/// - GameFormula row 1026, the fraction of the buy price an item sells for
///   (genesis_prime/game/vendor_sale).
/// - GameFormula row 530, the exponent of a quest's credits (genesis_prime/game/quest_turn_in).
/// - The Creature2, QuestObjective, Quest2 and WorldLocation2 rows of the four departures
///   terminals (genesis_prime/game/departures).
/// - No Spell4CCConditions row asks for a held state: ccStateFlagsRequired is 0
///   (genesis_prime/game/crowd_control).
pub fn all() -> List(store.Requirement) {
  list.flatten([
    departures.requirements(),
    crowd_control.requirements(),
    [start_place.requirement()],
    level.requirements(),
    character_state.requirements(),
    appearance.requirements(),
    dropped.requirements(),
    item_property.requirements(),
    hit_radius.requirements(),
    currency.requirements(),
    vendor_sale.requirements(),
    quest_turn_in.requirements(),
  ])
}
