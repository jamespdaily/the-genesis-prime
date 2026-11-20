//// The frames that put abilities in the client's ability book, which the world entry
//// sends for the whole bag and a level rise sends for the abilities it grants
//// (genesis_prime/game/ability_book).
////
//// ```
//// a bag slot ─▶ 0x0111 (location 4, reason 49)       the item in its bag slot, a press names the slot
//// the book   ─▶ 0x01A0 (tier 1 in each action set)   the entry the book window and the bar read
//// a bar      ─▶ 0x019D (one action set)              the shortcuts the bar slots hold
//// a save     ─▶ 0x00B2 (one bit)                     the answer to the builder's Save
//// ```

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/ability_book
import genesis_prime/game/inventory
import genesis_prime/game/loadout.{type Loadout}
import genesis_prime/game/spell_plan
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers.{AbilityTiers}
import genesis_prime/message/action_set
import genesis_prime/message/action_set_saved.{ActionSetSaved}
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/table/id.{type Spell4BaseId}
import gleam/list
import gleam/option.{type Option, None, Some}

/// The location of the held items that are abilities (`opcode.0x111.ability_bag`).
const ability_location = 4

/// The reason an item is added for when it is held from the start: 49, which adds an
/// ability without raising the ability book's change (`opcode.0x111.ability_level_up`)
/// and, as every reason but 27, shows the ability in its bar slot (`0x1403c1bf0`). A level
/// rise adds its abilities the way the entry does, which Eldan's level rise did too.
pub const held_from_the_start = 49

/// The action sets an ability book entry holds, 0 to 3 (`opcode.0x1a0`).
const action_sets = [0, 1, 2, 3]

/// The tier every ability starts at (`opcode.0x1a0`: tier 0 counts as 1).
const first_tier = 1

/// The result of an action set the client takes as ok (`opcode.0x19d`).
pub const action_set_ok = 1

/// The shortcut type of an ability, by its Spell4Base id (`opcode.0x19d`).
const ability_shortcut = 4

/// The shortcut type that empties the slot it names (`opcode.0x19d`).
const empty_shortcut = 0

/// The 2-bit value of an action set: bit 0 set marks the set unlocked, which the
/// ability book's set arrows and the active set's switch read; nothing in casting
/// or the bar reads it (`opcode.0x19d.set_value`). The one set the server sends is
/// unlocked.
const set_unlocked = 1

/// Which slots of a bar a 0x019D names.
pub type Shortcuts {
  /// Each of the bar's slots: an empty one clears the slot, which a changed bar needs.
  EverySlot
  /// Only the filled slots, each at its own place, for a client whose bar is empty.
  FilledSlots
}

/// 0x019D of one action set: the bar's slots, each an ability by its Spell4Base id or
/// empty, in slot order, with the result the client raises ActionSetError for unless it
/// is `action_set_ok`. A shortcut of type 4 names the slot in the field the client calls
/// the bag index; the client reads its location for no type 4 shortcut (`0x1403c1bf0`),
/// so it is the ability location.
pub fn action_set(
  set set: Int,
  result result: Int,
  slots slots: List(Option(Spell4BaseId)),
  shortcuts shortcuts: Shortcuts,
) -> Frame {
  let named =
    list.index_map(slots, fn(slot, bag_index) {
      case slot, shortcuts {
        Some(ability), _ ->
          Ok(ActionShortcut(
            shortcut_type: ability_shortcut,
            location: ability_location,
            bag_index:,
            object_id: ability.value,
          ))
        None, EverySlot ->
          Ok(ActionShortcut(
            shortcut_type: empty_shortcut,
            location: 0,
            bag_index:,
            object_id: 0,
          ))
        None, FilledSlots -> Error(Nil)
      }
    })
    |> list.filter_map(fn(shortcut) { shortcut })
  let assert Ok(body) =
    action_set.encode(action_set.ActionSet(
      action_set_index: set,
      unlocked: set_unlocked,
      result:,
      shortcuts: named,
    ))
    as "a set below 8, a result of 6 bits, a bar slot below 48 and an id of 32 bits fit the message"
  Frame(message_id: action_set.message_id, body:)
}

/// 0x00B2, the answer to the builder's Save: the bit asks the client for a combat log
/// line (`opcode.0xb2`).
pub fn action_set_saved(
  add_combat_log_line add_combat_log_line: Bool,
) -> Frame {
  let assert Ok(body) =
    action_set_saved.encode(
      ActionSetSaved(add_combat_log_line: case add_combat_log_line {
        True -> 1
        False -> 0
      }),
    )
    as "one bit fits the message"
  Frame(message_id: action_set_saved.message_id, body:)
}

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
    item_flags: 0,
    time_left_ms: 0,
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
