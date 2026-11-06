//// A player's look: the item visuals its model shows, and the disguises of its own
//// spells that change them for their time. The connection keeps one `Look` for its
//// player (genesis_prime/game/world_entry `Entered`), starts and ends a disguise when
//// the cast rule says so (genesis_prime/game/cast `CasterChangeStarts` with a `Look`
//// change, `PropertyEnds`), writes the slots that changed to the player's client and
//// tells its viewers (genesis_prime/game/connection/look), and hands a viewer that
//// first sees the player the list its 0x262 carries (`visuals`). The module is pure.
////
//// ```
//// cast rule                connection                           clients
////  go + delay
////    CasterChangeStarts ─────▶ start(source, disguise) ─────────▶ 0x933 to the player,
////      (Look)                  slots whose display changed        LookChanged to viewers
////  go + delay + duration, a node taken off, the caster dies
////    PropertyEnds ───────────▶ end(source) ─────────────────────▶ 0x933, LookChanged
////
//// a viewer that first sees the player ◀── visuals(look): the 0x262's item visuals
//// ```
////
//// - **A disguise is a DisguiseOutfit row's displays** (`Spell4Effects.effectType.112`):
////   one or two (slot, display) pairs, the slot an ItemSlot id. The client has no class
////   for the effect, and a look changes only by 0x933 or 0x905 (`opcode.0x933`).
//// - **The base** is the item visuals of the player's own 0x262, the body's and the worn
////   set's (`opcode.0x262.worn_visuals`).
//// - **What shows in a slot** is the newest live disguise that names the slot, else the
////   base's visual for it, else display 0. This is the server's choice: no client code
////   reads a type 112 row, and the rows give no order.
//// - **A display 0 empties the slot** (`opcode.0x933.empty_display`), so the end of a
////   disguise over a slot the base holds nothing in sends the slot with display 0. A
////   slot the base holds an item in is sent that item's visual, colour set and dye
////   included.
//// - **A start or an end reports the visuals whose shown display changed**, in slot
////   order, so one 0x933 carries them. A start that changes nothing, because the slot
////   already shows that display, reports nothing.
//// - **The same source started twice is held once**, as for properties, and ending a
////   source that is not held reports nothing.
//// - **The 0x262's list** is the base with each disguised slot's entry replaced, or
////   added when the base has none. The 0x262 and a 0x933 reach one model through the
////   same `SetUnitItemVisual` (`0x140466d20`), so a viewer created with the overlay and
////   a viewer sent the 0x933 draw the same unit. The overlay is one message and needs
////   no ordering.
//// - **A gap:** dataBits03 of a DisguiseOutfit row is 1 on both ExoSuit rows and on 17
////   others, and no client code reads a type 112 row, so the plan reads it as nothing
////   (genesis_prime/game/spell_plan `disguise_of`).
////
//// What happens at each failure point:
////
//// | Step | Killed there | Twice at once | Late |
//// |---|---|---|---|
//// | A disguise starts | the connection restarts from storage with the base look, and the client is created again | the same source held once, nothing reported the second time | n/a |
//// | A disguise ends | as above | the same source ended twice reports nothing the second time | ending a source not held reports nothing |
//// | Two disguises on one slot | | the newest shows; its end shows the older; the older's end first reports nothing | |
//// | The caster dies | the cast rule's `PropertyEnds` ends each disguise of its casts, each reported | | |
//// | The caster leaves | `Entered` goes with its look; the next entry starts from the base | | |

import genesis_prime/game/unit_properties
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/table/id.{type ItemDisplayId, type ItemSlotId}
import gleam/bool
import gleam/list

/// What one DisguiseOutfit row shows in one slot: the ItemSlot id of its display's
/// item type and the display (`Spell4Effects.effectType.112`).
pub type Shown {
  Shown(item_slot: ItemSlotId, display: ItemDisplayId)
}

/// A DisguiseOutfit row's look change: what it shows, one slot for a dataBits02 row
/// and one for a dataBits01 row, in the order the row gives them.
pub type Disguise {
  Disguise(shown: List(Shown))
}

/// A player's look: its base item visuals and the disguises held over them, newest
/// first. Built by `new`, changed by `start` and `end`.
pub opaque type Look {
  Look(base: List(ItemVisual), held: List(#(unit_properties.Source, Disguise)))
}

/// The look of a player whose 0x262 lists `base`, with no disguise.
pub fn new(base base: List(ItemVisual)) -> Look {
  Look(base:, held: [])
}

/// The look with the disguise of `source` started, and the visuals whose shown display
/// changed, in slot order.
pub fn start(
  look _look: Look,
  source _source: unit_properties.Source,
  disguise _disguise: Disguise,
) -> #(Look, List(ItemVisual)) {
  panic as "shape: #494"
}

/// The look with the disguise of `source` ended, and the visuals whose shown display
/// changed, in slot order; none for a source that is not held.
pub fn end(
  look look: Look,
  source source: unit_properties.Source,
) -> #(Look, List(ItemVisual)) {
  let held = list.any(look.held, fn(held) { held.0 == source })
  use <- bool.guard(when: !held, return: #(look, []))
  panic as "shape: #494"
}

/// The item visuals a 0x262 of the player lists: the base with each disguised slot's
/// entry replaced by what shows there, or added.
pub fn visuals(look look: Look) -> List(ItemVisual) {
  case look.held {
    [] -> look.base
    [_, ..] -> panic as "shape: #494"
  }
}
