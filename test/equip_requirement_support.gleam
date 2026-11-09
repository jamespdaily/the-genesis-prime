//// The character the equip tests dress: what `equip_requirement.Wearer` holds,
//// written as literals so a test's expectations do not come from the code that
//// builds them.

import genesis_prime/game/equip_requirement.{type Wearer, Wearer}
import genesis_prime/game/prerequisite.{Player}

/// The Engineer of the tests: race Human (1), class Engineer (2), faction 166,
/// level 1, gender 0 (male), in world 870, with the item proficiencies 66 (bits
/// 2 and 64) that the Engineer's `Class.startingItemProficiencies` holds.
pub fn engineer() -> Wearer {
  Wearer(
    faction_id: 166,
    level: 1,
    player: Player(
      race_id: 1,
      class_id: 2,
      level: 1,
      path: 3,
      gender: 0,
      world_id: 870,
      zones: [],
    ),
    item_proficiencies: 66,
  )
}

/// The wearer in the World.
pub fn in_world(wearer wearer: Wearer, world_id world_id: Int) -> Wearer {
  Wearer(..wearer, player: Player(..wearer.player, world_id:))
}

/// The wearer of the gender (0 male, 1 female).
pub fn of_gender(wearer wearer: Wearer, gender gender: Int) -> Wearer {
  Wearer(..wearer, player: Player(..wearer.player, gender:))
}

/// The wearer of the Race.
pub fn of_race(wearer wearer: Wearer, race_id race_id: Int) -> Wearer {
  Wearer(..wearer, player: Player(..wearer.player, race_id:))
}

/// The wearer of the Class.
pub fn of_class(wearer wearer: Wearer, class_id class_id: Int) -> Wearer {
  Wearer(..wearer, player: Player(..wearer.player, class_id:))
}
