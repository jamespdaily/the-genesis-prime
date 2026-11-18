//// The ability book a character holds on entering the world at a level
//// (`genesis_prime/game/world_entry`, `genesis_prime/game/ability_book`). Expected values
//// come from these places.
//// - `opcode.0x111.ability_level_up`: an ability is added by a 0x0111 of location 4 whose
////   bag index is the slot a press names; reason 49 raises no event, as the entry's does.
//// - `opcode.0x1a0`: an entry holds four action sets, tier 1 in each; the book holds the
////   bag, then the alternate each bag ability names.
//// - `opcode.0x19d`: the action set holds the three level-1 abilities in bar slots 0 to 2,
////   whatever the level: a later ability is placed by the player (the book window's own
////   request).
//// - `SpellLevel.spell4Id.no_prerequisite`: the rows after level 1 and their bases are the
////   ones `ability_book_test` lists; Class `spell4IdInnateAbilityActive00` gives the innate.

import ability_book_support as support
import character_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/loadout
import genesis_prime/game/world_entry
import genesis_prime/message/action_set
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/step.{ConnectionId}
import genesis_prime/store
import gleam/dict
import gleam/list
import gleam/option.{None}
import map_support
import owned_test
import place_support
import world_entry_support

/// A class's level-1 abilities and innate, and the bases after the innate at a level.
type Case {
  Case(
    class_id: Int,
    level: Int,
    level_one: List(Int),
    innate: Int,
    later: List(Int),
  )
}

fn cases() -> List(Case) {
  [
    Case(1, 3, [18_309, 37_968, 38_017], 30_828, []),
    Case(4, 4, [38_201, 16_322, 26_543], 46_615, [26_038]),
    Case(7, 6, [27_638, 20_684, 20_325], 31_213, [
      20_718,
      30_666,
      23_441,
      23_479,
      23_012,
    ]),
  ]
}

fn entering(
  class_id class_id: Int,
  level level: Int,
) -> #(List(Frame), world_entry.Entered) {
  let #(effects, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: world_entry_support.character(
        class: class_id,
        faction: 166,
        level:,
      ),
    )
  #(world_entry_support.frames_of(effects:), entered)
}

pub fn entry_at_a_level_sends_a_0x0111_per_bag_slot_in_bag_order_and_one_0x01a0_of_the_book_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(cases(), fn(case_) {
    let #(frames, _) = entering(class_id: case_.class_id, level: case_.level)
    let bag = list.flatten([case_.level_one, [case_.innate], case_.later])
    assert support.added_in(frames:)
      == list.index_map(bag, fn(base, bag_index) {
        support.Added(
          bag_index:,
          base:,
          reason: 49,
          item_guid: loadout.item_guid(
            character_number: 42,
            location: 4,
            bag_index:,
          ),
        )
      })
      as "opcode.0x111.ability_level_up: one 0x0111 of location 4 per bag slot, in bag order, reason 49, the guid of the slot"
    assert support.tiers_in(frames:)
      == support.tiers_of(bases: list.append(
        bag,
        world_entry_support.alternate_bases(
          class_id: case_.class_id,
          level: case_.level,
        ),
      ))
      as "opcode.0x1a0: tier 1 in each of the four sets for the bag and then the alternates its abilities name"
    let assert Ok(set) =
      action_set.decode(
        { world_entry_support.only_frame(frames:, message_id: 0x019D) }.body,
      )
      as "0x19d decodes"
    assert set.shortcuts
      == list.index_map(case_.level_one, fn(base, slot) {
        ActionShortcut(
          shortcut_type: 4,
          location: 4,
          bag_index: slot,
          object_id: base,
        )
      })
      as "opcode.0x19d: the bar still holds the three level-1 abilities in slots 0 to 2"
  })
}

pub fn the_bag_a_rejoin_sends_is_the_one_the_session_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  // The Medic entered at level 3 and rose to 4 in the session: `experience.gained` keeps the
  // character at the new level, which the rejoin takes (Holocrypt's join re-sends the loadout).
  let tables = character_tables.shared()
  let #(_, at_three) = entering(class_id: 4, level: 3)
  let character = store.Character(..at_three.character, level: 4)
  let risen = world_entry.Entered(..at_three, character:)
  let landing =
    place_support.at(
      world_id: 426,
      world_zone_id: 648,
      x: 4098.16015625,
      y: -665.9780883789062,
      z: -5165.10009765625,
    )
  let #(state, _) =
    world_entry.rejoining(
      entered: risen,
      place: landing,
      health: None,
      connection: ConnectionId(1),
      stay: map_support.stay(count: 2),
      tables:,
      visibility: dict.new(),
    )
  let assert world_entry.InTheWorld(effects:, ..) =
    world_entry_support.joined_state(
      state:,
      tables:,
      character:,
      place: landing,
      now: world_entry_support.now(),
    )
    as "the map's answer to the rejoin puts the player in the world"
  let #(entry_frames, _) = entering(class_id: 4, level: 4)
  assert support.added_in(frames: world_entry_support.frames_of(effects:))
    == support.added_in(frames: entry_frames)
    as "the rejoin's location-4 items are the entry of a Medic at level 4, Fissure's base 26038 at slot 4"
}
