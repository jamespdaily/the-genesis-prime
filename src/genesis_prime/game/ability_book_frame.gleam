//// The frames that put abilities in the client's ability book, which the world entry
//// sends for the whole bag and a level rise sends for the abilities it grants
//// (genesis_prime/game/ability_book).
////
//// ```
//// a bag slot ─▶ 0x0111 (location 4, reason 49)       the item in its bag slot, a press names the slot
//// the book   ─▶ 0x01A0 (tier 1 in each action set)   the entry the book window and the bar read
//// ```

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/ability_book
import genesis_prime/game/inventory
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/spell_plan
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers.{AbilityTiers}
import genesis_prime/table/id.{type Spell4BaseId}
import gleam/list

/// The location of the held items that are abilities (`opcode.0x111.ability_bag`).
pub const ability_location = 4

/// The reason an item is added for when it is held from the start: 49, which adds an
/// ability without raising the ability book's change (`opcode.0x111.ability_level_up`)
/// and, as every reason but 27, shows the ability in its bar slot (`0x1403c1bf0`). A level
/// rise adds its abilities the way the entry does, which Eldan's level rise did too.
pub const held_from_the_start = 49

/// The action sets an ability book entry holds, 0 to 3 (`opcode.0x1a0`).
const action_sets = [0, 1, 2, 3]

/// The tier every ability starts at (`opcode.0x1a0`: tier 0 counts as 1).
const first_tier = 1

/// 0x0111 of the ability at a bag index of the ability location.
pub fn held_ability(
  character_number character_number: Int,
  bag_index bag_index: Int,
  base base: Spell4BaseId,
) -> Frame {
  inventory.item_added_frame(
    item_guid: loadout.item_guid(
      character_number:,
      location: ability_location,
      bag_index:,
    ),
    item_id: base.value,
    location: ability_location,
    bag_index:,
    stack_count: 1,
    random_stats: 0,
    charges: 0,
    reason: held_from_the_start,
  )
}

/// 0x01A0 with tier 1 of each ability in each action set.
pub fn tiers(abilities abilities: List(Spell4BaseId)) -> Frame {
  let assert Ok(body) =
    ability_tiers.encode(
      AbilityTiers(
        tiers: list.flat_map(abilities, fn(ability) {
          list.map(action_sets, fn(action_set_index) {
            AbilityTier(
              spell4_base_id: ability.value,
              tier: first_tier,
              action_set_index:,
            )
          })
        }),
      ),
    )
    as "a Spell4Base id of 18 bits, a tier of 4 and a set of 3 fit the message"
  Frame(message_id: ability_tiers.message_id, body:)
}

/// The frames of a level rise: 0x0111 of each ability it grants, at the bag indexes after
/// the bag the old level held, then one 0x01A0 of the granted abilities and the alternates
/// the plans give them; none for a rise that grants nothing.
pub fn granted(
  character_number character_number: Int,
  loadout loadout: Loadout,
  plans plans: spell_plan.Plans,
  from_level from_level: Int,
  to_level to_level: Int,
) -> List(Frame) {
  let abilities = ability_book.granted(loadout:, from_level:, to_level:)
  case abilities {
    [] -> []
    [_, ..] -> {
      let first_index = ability_book.size(loadout:, level: from_level)
      list.append(
        list.index_map(abilities, fn(base, offset) {
          held_ability(
            character_number:,
            bag_index: first_index + offset,
            base:,
          )
        }),
        [tiers(abilities: spell_plan.book(plans:, bag: abilities))],
      )
    }
  }
}
