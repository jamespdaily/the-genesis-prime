//// The character the equip tests dress: what `equip_requirement.Wearer` holds,
//// written as literals so a test's expectations do not come from the code that
//// builds them.

import genesis_prime/game/equip_requirement.{type Wearer, Wearer}

/// The Engineer of the tests: race Human (1), class Engineer (2), faction 166,
/// level 1, gender 0 (male), in world 870, with the item proficiencies 66 (bits
/// 2 and 64) that the Engineer's `Class.startingItemProficiencies` holds.
pub fn engineer() -> Wearer {
  Wearer(
    race_id: 1,
    class_id: 2,
    faction_id: 166,
    level: 1,
    gender: 0,
    world_id: 870,
    item_proficiencies: 66,
  )
}
