//// A player's look (`genesis_prime/game/look`). Expected values come from these places:
//// - `opcode.0x262.worn_visuals`: a worn item's visual is its slot, its display, colour
////   set 0 and dye 0; the Engineer of faction 166's Novice set is chest 3842 in slot 1
////   and the weapon 3409 in slot 20 (`Item2.novice_visuals`).
//// - `Spell4Effects.effectType.112`: the Eradication ExoSuit is ItemDisplay 4807
////   'AMR_Mechsuit_000' (`-- ItemDisplay 4807`) in ItemSlot 64 (`-- Item2Type 346`), and
////   the Warrior of faction 167's Novice weapon, display 119, is a WeaponPrimary display
////   in slot 20 (`Item2.novice_visuals`).
//// - `opcode.0x933.empty_display`: display 0 empties a slot, and to put back a slot that
////   held an item 0x933 carries that item's display and colour.
//// - The server's choices, which the module's doc names: the newest disguise on a slot
////   shows, and a source is held once (the properties' rule, `unit_properties`).

import genesis_prime/game/look.{Disguise}
import genesis_prime/game/unit_properties.{type Source, Source}
import genesis_prime/game/worn_visual.{WornVisual}
import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/table/id.{ItemDisplayId, ItemSlotId, Spell4EffectsId}
import owned_test

/// The EngineerMechSuit slot (`-- ItemSlot 64`) and WeaponPrimary (`-- ItemSlot 20`).
const suit_slot = 64

const weapon_slot = 20

/// The Eradication ExoSuit's display for an Exile (`-- ItemDisplay 4807`) and for a
/// Dominion player (7221).
const exile_suit = 4807

const dominion_suit = 7221

/// The Engineer of faction 166's Novice chest and weapon (`Item2.novice_visuals`).
const chest = ItemVisual(slot: 1, display_id: 3842, item_color_set_id: 0, dye: 0)

const novice_weapon =
  ItemVisual(slot: 20, display_id: 3409, item_color_set_id: 0, dye: 0)

fn source(cast_id cast_id: Int, effect_id effect_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(effect_id))
}

fn disguise(slot slot: Int, display display: Int) -> look.Disguise {
  Disguise(shown: [
    WornVisual(slot: ItemSlotId(slot), display: ItemDisplayId(display)),
  ])
}

fn visual(slot slot: Int, display display: Int) -> ItemVisual {
  ItemVisual(slot:, display_id: display, item_color_set_id: 0, dye: 0)
}

/// An Engineer whose 0x262 lists its chest and weapon and nothing in slot 64.
fn engineer() -> look.Look {
  look.new(base: [chest, novice_weapon])
}

pub fn a_disguise_on_a_slot_the_base_lacks_reports_that_slot_with_its_display_and_colour_0_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, changed) =
    look.start(
      look: engineer(),
      source: source(cast_id: 1, effect_id: 112_543),
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  assert changed == [visual(slot: suit_slot, display: exile_suit)]
    as "slot 64, display 4807, colour set 0 and dye 0 (opcode.0x262.worn_visuals)"
}

pub fn ending_a_disguise_over_a_slot_the_base_lacks_reports_display_0_test() -> Nil {
  use <- owned_test.run(5000)
  let started = source(cast_id: 1, effect_id: 112_543)
  let #(look, _) =
    look.start(
      look: engineer(),
      source: started,
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  let #(look, changed) = look.end(look:, source: started)
  assert changed == [visual(slot: suit_slot, display: 0)]
    as "display 0 empties slot 64 (opcode.0x933.empty_display)"
  assert look.visuals(look:) == [chest, novice_weapon]
    as "the 0x262's list after the end is the base's"
}

pub fn a_disguise_on_a_base_slot_replaces_its_display_and_its_end_puts_the_whole_visual_back_test() -> Nil {
  use <- owned_test.run(5000)
  // The Engineer's weapon is dyed: colour set 5 and dye 0x12345, so that the restore has
  // a colour to put back (opcode.0x933.empty_display: "that item's display and colour").
  let dyed =
    ItemVisual(slot: 20, display_id: 3409, item_color_set_id: 5, dye: 0x12345)
  let held = source(cast_id: 2, effect_id: 90_001)
  let #(look, started) =
    look.start(
      look: look.new(base: [chest, dyed]),
      source: held,
      disguise: disguise(slot: weapon_slot, display: 119),
    )
  assert started == [visual(slot: weapon_slot, display: 119)]
    as "the disguise's display with colour 0, over the base's"
  let #(_, ended) = look.end(look:, source: held)
  assert ended == [dyed]
    as "the base's display, colour set and dye, not colour 0"
}

pub fn two_disguises_on_one_slot_show_the_newest_and_ending_the_newest_shows_the_older_test() -> Nil {
  use <- owned_test.run(5000)
  let older = source(cast_id: 1, effect_id: 112_543)
  let newer = source(cast_id: 2, effect_id: 178_142)
  let #(look, _) =
    look.start(
      look: engineer(),
      source: older,
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  let #(look, second) =
    look.start(
      look:,
      source: newer,
      disguise: disguise(slot: suit_slot, display: dominion_suit),
    )
  assert second == [visual(slot: suit_slot, display: dominion_suit)]
    as "the newest shows"
  let #(look, ended_newer) = look.end(look:, source: newer)
  assert ended_newer == [visual(slot: suit_slot, display: exile_suit)]
    as "the older shows again"
  let #(_, ended_older) = look.end(look:, source: older)
  assert ended_older == [visual(slot: suit_slot, display: 0)]
}

pub fn ending_the_older_of_two_disguises_first_reports_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let older = source(cast_id: 1, effect_id: 112_543)
  let newer = source(cast_id: 2, effect_id: 178_142)
  let #(look, _) =
    look.start(
      look: engineer(),
      source: older,
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  let #(look, _) =
    look.start(
      look:,
      source: newer,
      disguise: disguise(slot: suit_slot, display: dominion_suit),
    )
  let #(look, ended_older) = look.end(look:, source: older)
  assert ended_older == [] as "the newer still shows, so no slot changed"
  let #(_, ended_newer) = look.end(look:, source: newer)
  assert ended_newer == [visual(slot: suit_slot, display: 0)]
    as "the older is gone, so the base's nothing shows"
}

pub fn the_same_source_started_twice_is_held_once_and_a_source_not_held_ends_with_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let held = source(cast_id: 1, effect_id: 112_543)
  let #(look, first) =
    look.start(
      look: engineer(),
      source: held,
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  assert first != []
  let #(look, again) =
    look.start(
      look:,
      source: held,
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  assert again == [] as "the second start of one source reports nothing"
  let #(look, ended) = look.end(look:, source: held)
  assert ended == [visual(slot: suit_slot, display: 0)]
  let #(_, ended_twice) = look.end(look:, source: held)
  assert ended_twice == [] as "held once, so the second end reports nothing"
  let #(_, never_held) =
    look.end(look: engineer(), source: source(cast_id: 9, effect_id: 9))
  assert never_held == [] as "a source not held reports nothing"
}

pub fn a_disguise_whose_display_the_slot_already_shows_reports_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // The Engineer's weapon, 3409, worn with colour 0: a disguise of the same display with
  // colour 0 moves nothing.
  let #(look, changed) =
    look.start(
      look: engineer(),
      source: source(cast_id: 1, effect_id: 90_002),
      disguise: disguise(slot: weapon_slot, display: 3409),
    )
  assert changed == [] as "the slot shows 3409 in colour 0 already"
  assert look.visuals(look:) == [chest, novice_weapon]
}

pub fn the_0x262_list_is_the_base_with_each_disguised_slots_entry_replaced_or_added_at_the_end_test() -> Nil {
  use <- owned_test.run(5000)
  let #(look, _) =
    look.start(
      look: engineer(),
      source: source(cast_id: 1, effect_id: 112_543),
      disguise: disguise(slot: suit_slot, display: exile_suit),
    )
  let #(look, _) =
    look.start(
      look:,
      source: source(cast_id: 1, effect_id: 90_003),
      disguise: disguise(slot: weapon_slot, display: 119),
    )
  assert look.visuals(look:)
    == [
      chest,
      visual(slot: weapon_slot, display: 119),
      visual(slot: suit_slot, display: exile_suit),
    ]
    as "slot 20 replaced in place, slot 64 added at the end (opcode.0x262.worn_visuals)"
}

pub fn a_row_with_two_displays_reports_both_in_slot_order_test() -> Nil {
  use <- owned_test.run(5000)
  // A DisguiseOutfit row can name a dataBits02 and a dataBits01 display
  // (`Spell4Effects.effectType.112`): both are shown, and one 0x933 carries them in
  // slot order.
  let #(_, changed) =
    look.start(
      look: engineer(),
      source: source(cast_id: 1, effect_id: 90_004),
      disguise: Disguise(shown: [
        WornVisual(
          slot: ItemSlotId(suit_slot),
          display: ItemDisplayId(exile_suit),
        ),
        WornVisual(slot: ItemSlotId(weapon_slot), display: ItemDisplayId(119)),
      ]),
    )
  assert changed
    == [
      visual(slot: weapon_slot, display: 119),
      visual(slot: suit_slot, display: exile_suit),
    ]
}
